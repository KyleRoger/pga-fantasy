-- PGA Fantasy: RPCs and triggers for phase 1
-- Every function that writes checks the caller's role itself (security definer
-- bypasses RLS) and records commissioner actions in audit_log.

-- ---------------------------------------------------------------------------
-- Profiles: created automatically on sign-up
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Golfer'
  );
  insert into public.profiles (id, display_name)
  values (new.id, left(v_name, 40))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------
create or replace function public.require_commissioner(p_league_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  if not public.is_commissioner(p_league_id) then
    raise exception 'only the commissioner can do this' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.write_audit(
  p_league_id uuid, p_action text, p_before jsonb, p_after jsonb
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.audit_log (league_id, actor_id, action, before, after)
  values (p_league_id, auth.uid(), p_action, p_before, p_after);
$$;

-- ---------------------------------------------------------------------------
-- Leagues
-- ---------------------------------------------------------------------------
create or replace function public.create_league(p_name text, p_season integer)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_league_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;

  insert into public.leagues (name, season, commissioner_id)
  values (trim(p_name), p_season, auth.uid())
  returning id into v_league_id;

  insert into public.league_members (league_id, user_id, role)
  values (v_league_id, auth.uid(), 'commissioner');

  perform public.write_audit(v_league_id, 'league.create', null,
    jsonb_build_object('name', trim(p_name), 'season', p_season));

  return v_league_id;
end;
$$;

-- Replaces the league's scoring rules. Each rule must be a known key with
-- { "enabled": boolean, "points": number }. Unknown keys are rejected.
create or replace function public.update_scoring_rules(p_league_id uuid, p_rules jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before jsonb;
  v_merged jsonb;
  v_key    text;
  v_rule   jsonb;
begin
  perform public.require_commissioner(p_league_id);

  if jsonb_typeof(p_rules) <> 'object' then
    raise exception 'rules must be a JSON object' using errcode = '22023';
  end if;

  for v_key, v_rule in select * from jsonb_each(p_rules) loop
    if not (public.default_scoring_rules() ? v_key) then
      raise exception 'unknown scoring rule: %', v_key using errcode = '22023';
    end if;
    if jsonb_typeof(v_rule -> 'enabled') <> 'boolean'
       or jsonb_typeof(v_rule -> 'points') <> 'number' then
      raise exception 'rule % needs enabled (boolean) and points (number)', v_key
        using errcode = '22023';
    end if;
    if abs((v_rule ->> 'points')::numeric) > 1000 then
      raise exception 'rule % points must be between -1000 and 1000', v_key
        using errcode = '22023';
    end if;
  end loop;

  select scoring_rules into v_before from public.leagues where id = p_league_id;

  -- Start from defaults so every key is always present, then apply the change.
  v_merged := public.default_scoring_rules() || v_before || p_rules;

  update public.leagues set scoring_rules = v_merged where id = p_league_id;

  perform public.write_audit(p_league_id, 'league.scoring_rules', v_before, v_merged);
  return v_merged;
end;
$$;

-- ---------------------------------------------------------------------------
-- Invites
-- ---------------------------------------------------------------------------
create or replace function public.create_invite(
  p_league_id  uuid,
  p_email      text default null,
  p_days_valid integer default 14,
  p_max_uses   integer default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
begin
  perform public.require_commissioner(p_league_id);

  if p_days_valid not between 1 and 90 then
    raise exception 'invites can last 1 to 90 days' using errcode = '22023';
  end if;

  insert into public.league_invites (league_id, email, created_by, expires_at, max_uses)
  values (p_league_id, nullif(lower(trim(p_email)), ''), auth.uid(),
          now() + make_interval(days => p_days_valid), p_max_uses)
  returning token into v_token;

  perform public.write_audit(p_league_id, 'invite.create', null,
    jsonb_build_object('email', p_email, 'days_valid', p_days_valid, 'max_uses', p_max_uses));

  return v_token;
end;
$$;

create or replace function public.revoke_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_league_id uuid;
begin
  select league_id into v_league_id from public.league_invites where id = p_invite_id;
  if v_league_id is null then
    raise exception 'invite not found' using errcode = 'P0002';
  end if;
  perform public.require_commissioner(v_league_id);

  update public.league_invites set revoked_at = now()
  where id = p_invite_id and revoked_at is null;

  perform public.write_audit(v_league_id, 'invite.revoke', null,
    jsonb_build_object('invite_id', p_invite_id));
end;
$$;

-- Lets someone who isn't a member yet see what they're joining.
create or replace function public.get_invite_preview(p_token text)
returns table (
  league_id         uuid,
  league_name       text,
  season            integer,
  commissioner_name text,
  member_count      bigint,
  is_valid          boolean,
  reason            text,
  already_member    boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    l.id,
    l.name,
    l.season,
    p.display_name,
    (select count(*) from public.league_members m where m.league_id = l.id),
    (i.revoked_at is null
      and i.expires_at > now()
      and (i.max_uses is null or i.use_count < i.max_uses)),
    case
      when i.revoked_at is not null then 'revoked'
      when i.expires_at <= now() then 'expired'
      when i.max_uses is not null and i.use_count >= i.max_uses then 'used_up'
      else null
    end,
    exists (select 1 from public.league_members m
            where m.league_id = l.id and m.user_id = auth.uid())
  from public.league_invites i
  join public.leagues l on l.id = i.league_id
  join public.profiles p on p.id = l.commissioner_id
  where i.token = p_token;
$$;

create or replace function public.accept_invite(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.league_invites;
  v_email  text;
  v_added  integer;
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;

  select * into v_invite from public.league_invites where token = p_token for update;

  if v_invite.id is null then
    raise exception 'invite not found' using errcode = 'P0002';
  end if;
  if v_invite.revoked_at is not null then
    raise exception 'this invite was revoked' using errcode = '22023';
  end if;
  if v_invite.expires_at <= now() then
    raise exception 'this invite has expired' using errcode = '22023';
  end if;
  if v_invite.max_uses is not null and v_invite.use_count >= v_invite.max_uses then
    raise exception 'this invite has already been used' using errcode = '22023';
  end if;

  if v_invite.email is not null then
    select lower(email) into v_email from auth.users where id = auth.uid();
    if v_email is distinct from v_invite.email then
      raise exception 'this invite was sent to a different email address' using errcode = '42501';
    end if;
  end if;

  insert into public.league_members (league_id, user_id, role)
  values (v_invite.league_id, auth.uid(), 'member')
  on conflict (league_id, user_id) do nothing;
  get diagnostics v_added = row_count;

  if v_added > 0 then
    update public.league_invites set use_count = use_count + 1 where id = v_invite.id;
    insert into public.audit_log (league_id, actor_id, action, after)
    values (v_invite.league_id, auth.uid(), 'member.join',
            jsonb_build_object('invite_id', v_invite.id));
  end if;

  return v_invite.league_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rookie overrides (commissioner, before the event's draft opens)
-- ---------------------------------------------------------------------------
create or replace function public.set_rookie_override(
  p_league_id uuid, p_player_id uuid, p_is_rookie boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before jsonb;
begin
  perform public.require_commissioner(p_league_id);

  select to_jsonb(o) into v_before
  from public.league_rookie_overrides o
  where league_id = p_league_id and player_id = p_player_id;

  if p_is_rookie is null then
    -- null clears the override and falls back to official PGA Tour status
    delete from public.league_rookie_overrides
    where league_id = p_league_id and player_id = p_player_id;
  else
    insert into public.league_rookie_overrides (league_id, player_id, is_rookie, set_by)
    values (p_league_id, p_player_id, p_is_rookie, auth.uid())
    on conflict (league_id, player_id)
      do update set is_rookie = excluded.is_rookie, set_by = excluded.set_by, set_at = now();
  end if;

  perform public.write_audit(p_league_id, 'rookie.override', v_before,
    jsonb_build_object('player_id', p_player_id, 'is_rookie', p_is_rookie));
end;
$$;

-- Effective rookie status for a league: the override if there is one, else the feed.
create or replace function public.league_is_rookie(p_league_id uuid, p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select is_rookie from public.league_rookie_overrides
      where league_id = p_league_id and player_id = p_player_id),
    (select is_rookie from public.players where id = p_player_id),
    false
  );
$$;

-- ---------------------------------------------------------------------------
-- Events: which tournaments count for this league
-- ---------------------------------------------------------------------------
create or replace function public.add_league_event(
  p_league_id uuid, p_tournament_id uuid, p_draft_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
  v_pick_seconds integer;
begin
  perform public.require_commissioner(p_league_id);

  insert into public.league_events (league_id, tournament_id, draft_at)
  values (p_league_id, p_tournament_id, p_draft_at)
  on conflict (league_id, tournament_id) do update set draft_at = excluded.draft_at
  returning id into v_event_id;

  select pick_seconds into v_pick_seconds from public.leagues where id = p_league_id;

  -- Every event gets its own fresh draft.
  insert into public.drafts (league_event_id, pick_seconds)
  values (v_event_id, v_pick_seconds)
  on conflict (league_event_id) do nothing;

  perform public.write_audit(p_league_id, 'event.add', null,
    jsonb_build_object('tournament_id', p_tournament_id, 'draft_at', p_draft_at));

  return v_event_id;
end;
$$;

create or replace function public.remove_league_event(p_league_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.league_events;
begin
  select * into v_event from public.league_events where id = p_league_event_id;
  if v_event.id is null then
    raise exception 'event not found' using errcode = 'P0002';
  end if;
  perform public.require_commissioner(v_event.league_id);

  if v_event.status <> 'scheduled' then
    raise exception 'an event can only be removed before its draft starts' using errcode = '22023';
  end if;

  delete from public.league_events where id = p_league_event_id;

  perform public.write_audit(v_event.league_id, 'event.remove', to_jsonb(v_event), null);
end;
$$;

-- ---------------------------------------------------------------------------
-- Money: season buy-ins (main pot)
-- ---------------------------------------------------------------------------
-- A buy-in is stored as a negative amount: the member owes it to the pot.
-- At season end, finalize-season credits the whole pot to the winner.
create or replace function public.record_buy_in(
  p_league_id uuid, p_user_id uuid, p_amount_cents bigint, p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry_id uuid;
begin
  perform public.require_commissioner(p_league_id);

  if p_amount_cents is null or p_amount_cents = 0 then
    raise exception 'amount must not be zero' using errcode = '22023';
  end if;
  if not exists (select 1 from public.league_members
                 where league_id = p_league_id and user_id = p_user_id) then
    raise exception 'that person is not in this league' using errcode = '22023';
  end if;

  -- Positive input = a buy-in; negative input = a refund/correction.
  insert into public.ledger_entries
    (league_id, user_id, pot, kind, amount_cents, note, created_by)
  values
    (p_league_id, p_user_id, 'main',
     case when p_amount_cents > 0 then 'buy_in' else 'adjustment' end::public.ledger_kind,
     -p_amount_cents, nullif(trim(p_note), ''), auth.uid())
  returning id into v_entry_id;

  perform public.write_audit(p_league_id, 'money.buy_in', null,
    jsonb_build_object('user_id', p_user_id, 'amount_cents', p_amount_cents, 'note', p_note));

  return v_entry_id;
end;
$$;

-- Per-member totals for the league's money page.
create or replace function public.league_money_summary(p_league_id uuid)
returns table (
  user_id           uuid,
  display_name      text,
  buy_in_cents      bigint,
  main_balance_cents bigint,
  side_balance_cents bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    m.user_id,
    p.display_name,
    coalesce(-sum(e.amount_cents) filter (where e.pot = 'main' and e.kind in ('buy_in', 'adjustment')), 0)::bigint,
    coalesce(sum(e.amount_cents) filter (where e.pot = 'main'), 0)::bigint,
    coalesce(sum(e.amount_cents) filter (where e.pot = 'side_bets'), 0)::bigint
  from public.league_members m
  join public.profiles p on p.id = m.user_id
  left join public.ledger_entries e on e.league_id = m.league_id and e.user_id = m.user_id
  where m.league_id = p_league_id
    and public.is_league_member(p_league_id)
  group by m.user_id, p.display_name
  order by p.display_name;
$$;

-- ---------------------------------------------------------------------------
-- Permissions: only signed-in users may call RPCs; internals stay private
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;

grant execute on function
  public.create_league(text, integer),
  public.update_scoring_rules(uuid, jsonb),
  public.create_invite(uuid, text, integer, integer),
  public.revoke_invite(uuid),
  public.get_invite_preview(text),
  public.accept_invite(text),
  public.set_rookie_override(uuid, uuid, boolean),
  public.league_is_rookie(uuid, uuid),
  public.add_league_event(uuid, uuid, timestamptz),
  public.remove_league_event(uuid),
  public.record_buy_in(uuid, uuid, bigint, text),
  public.league_money_summary(uuid),
  public.is_league_member(uuid),
  public.is_commissioner(uuid),
  public.shares_league_with(uuid),
  public.league_of_event(uuid),
  public.league_of_draft(uuid),
  public.default_scoring_rules()
to authenticated;

revoke execute on function
  public.require_commissioner(uuid),
  public.write_audit(uuid, text, jsonb, jsonb),
  public.handle_new_user()
from authenticated;
