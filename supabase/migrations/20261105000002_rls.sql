-- PGA Fantasy: row-level security
-- Rule of thumb: members can read their league's data. Anything that changes
-- points, money, invites or rookie status goes through a security-definer RPC
-- (next migration) or an Edge Function using the service role.

-- ---------------------------------------------------------------------------
-- Helpers (security definer so policies can check membership without recursion)
-- ---------------------------------------------------------------------------
create or replace function public.is_league_member(p_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.league_members
    where league_id = p_league_id and user_id = auth.uid()
  );
$$;

create or replace function public.is_commissioner(p_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.league_members
    where league_id = p_league_id and user_id = auth.uid() and role = 'commissioner'
  );
$$;

create or replace function public.shares_league_with(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.league_members a
    join public.league_members b on b.league_id = a.league_id
    where a.user_id = auth.uid() and b.user_id = p_user_id
  );
$$;

create or replace function public.league_of_event(p_league_event_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select league_id from public.league_events where id = p_league_event_id;
$$;

create or replace function public.league_of_draft(p_draft_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select le.league_id
  from public.drafts d
  join public.league_events le on le.id = d.league_event_id
  where d.id = p_draft_id;
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere
-- ---------------------------------------------------------------------------
alter table public.players                 enable row level security;
alter table public.tournaments             enable row level security;
alter table public.tournament_field        enable row level security;
alter table public.rounds                  enable row level security;
alter table public.hole_scores             enable row level security;
alter table public.tee_groups              enable row level security;
alter table public.scoring_events          enable row level security;
alter table public.profiles                enable row level security;
alter table public.leagues                 enable row level security;
alter table public.league_members          enable row level security;
alter table public.league_invites          enable row level security;
alter table public.league_rookie_overrides enable row level security;
alter table public.league_events           enable row level security;
alter table public.drafts                  enable row level security;
alter table public.draft_picks             enable row level security;
alter table public.draft_queues            enable row level security;
alter table public.fantasy_scores          enable row level security;
alter table public.daily_results           enable row level security;
alter table public.side_bets               enable row level security;
alter table public.ledger_entries          enable row level security;
alter table public.settlements             enable row level security;
alter table public.audit_log               enable row level security;

-- ---------------------------------------------------------------------------
-- Golf data: any signed-in user can read; only the service role writes
-- ---------------------------------------------------------------------------
create policy "golf data readable" on public.players          for select to authenticated using (true);
create policy "golf data readable" on public.tournaments      for select to authenticated using (true);
create policy "golf data readable" on public.tournament_field for select to authenticated using (true);
create policy "golf data readable" on public.rounds           for select to authenticated using (true);
create policy "golf data readable" on public.hole_scores      for select to authenticated using (true);
create policy "golf data readable" on public.tee_groups       for select to authenticated using (true);
create policy "golf data readable" on public.scoring_events   for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Profiles: see yourself and people in your leagues; edit only yourself
-- ---------------------------------------------------------------------------
create policy "profiles readable by self and league mates" on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.shares_league_with(id));

create policy "profiles editable by owner" on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- Leagues
-- ---------------------------------------------------------------------------
create policy "leagues readable by members" on public.leagues
  for select to authenticated
  using (public.is_league_member(id));

create policy "leagues editable by commissioner" on public.leagues
  for update to authenticated
  using (public.is_commissioner(id))
  with check (public.is_commissioner(id));

-- Commissioners may change these columns directly; scoring rules and the
-- commissioner itself change only through RPCs that validate and audit.
revoke update on public.leagues from authenticated;
grant update (name, roster_size, rookie_slots, pick_seconds,
              side_bets_enabled, side_bet_min_cents, side_bet_max_cents)
  on public.leagues to authenticated;

-- ---------------------------------------------------------------------------
-- Members
-- ---------------------------------------------------------------------------
create policy "members readable by league mates" on public.league_members
  for select to authenticated
  using (public.is_league_member(league_id));

-- Members can only toggle their own side-bet opt-in.
create policy "members update own opt-in" on public.league_members
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke update on public.league_members from authenticated;
grant update (side_bets_opt_in) on public.league_members to authenticated;

create policy "members can leave, commissioner can remove" on public.league_members
  for delete to authenticated
  using (
    (user_id = auth.uid() and role = 'member')
    or (public.is_commissioner(league_id) and user_id <> auth.uid())
  );

-- ---------------------------------------------------------------------------
-- Invites: commissioner only (joining goes through accept_invite)
-- ---------------------------------------------------------------------------
create policy "invites readable by commissioner" on public.league_invites
  for select to authenticated
  using (public.is_commissioner(league_id));

-- ---------------------------------------------------------------------------
-- Rookie overrides, events, drafts: members read
-- ---------------------------------------------------------------------------
create policy "rookie overrides readable by members" on public.league_rookie_overrides
  for select to authenticated
  using (public.is_league_member(league_id));

create policy "league events readable by members" on public.league_events
  for select to authenticated
  using (public.is_league_member(league_id));

create policy "drafts readable by members" on public.drafts
  for select to authenticated
  using (public.is_league_member(public.league_of_event(league_event_id)));

create policy "draft picks readable by members" on public.draft_picks
  for select to authenticated
  using (public.is_league_member(public.league_of_draft(draft_id)));

create policy "own draft queue" on public.draft_queues
  for all to authenticated
  using (user_id = auth.uid() and public.is_league_member(public.league_of_draft(draft_id)))
  with check (user_id = auth.uid() and public.is_league_member(public.league_of_draft(draft_id)));

-- ---------------------------------------------------------------------------
-- Scores, bets, money, audit: members read, nobody writes from the browser
-- ---------------------------------------------------------------------------
create policy "scores readable by members" on public.fantasy_scores
  for select to authenticated
  using (public.is_league_member(public.league_of_event(league_event_id)));

create policy "daily results readable by members" on public.daily_results
  for select to authenticated
  using (public.is_league_member(public.league_of_event(league_event_id)));

create policy "side bets readable by members" on public.side_bets
  for select to authenticated
  using (public.is_league_member(public.league_of_event(league_event_id)));

create policy "ledger readable by members" on public.ledger_entries
  for select to authenticated
  using (public.is_league_member(league_id));

create policy "settlements readable by members" on public.settlements
  for select to authenticated
  using (public.is_league_member(league_id));

create policy "audit log readable by members" on public.audit_log
  for select to authenticated
  using (public.is_league_member(league_id));
