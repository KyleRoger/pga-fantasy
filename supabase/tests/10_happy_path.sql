-- Happy path: sign up, create a league, invite, join. Fails loudly on any surprise.
\set ON_ERROR_STOP 1

create function public.test_check(p_ok boolean, p_what text)
returns void language plpgsql as $$
begin
  if p_ok is not true then raise exception 'check failed: %', p_what; end if;
end $$;

-- Three sign-ups; profiles are created by trigger
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000001', 'kyle@example.com', '{"display_name": "Kyle"}'),
  ('00000000-0000-0000-0000-000000000002', 'sam@example.com', '{}'),
  ('00000000-0000-0000-0000-000000000003', 'eve@example.com', '{}');
select test_check((select count(*) from profiles) = 3, 'a profile per sign-up');
select test_check((select display_name from profiles where id = '00000000-0000-0000-0000-000000000002') = 'sam',
                  'display name falls back to the email name');

-- Kyle creates a league and becomes commissioner
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select create_league('Sunday Hackers', 2027) as league_id \gset
select test_check((select roster_size = 5 and rookie_slots = 1 from leagues), 'defaults: 5 golfers, 1 rookie');
select test_check((select (scoring_rules -> 'finish_win' ->> 'points')::int = 50 from leagues), 'default win = 50');
select test_check((select role = 'commissioner' from league_members where user_id = auth.uid()), 'creator is commissioner');

-- Kyle edits scoring and adds an event (which creates its draft)
select update_scoring_rules(:'league_id', '{"rookie_win": {"enabled": false, "points": 25}, "birdie": {"enabled": true, "points": 2}}');
select add_league_event(:'league_id', (select id from tournaments where provider_id = 'dev-2027-01'));
select test_check((select count(*) from drafts) = 1, 'each event gets a draft');

-- Kyle makes an open invite link; Sam previews and joins
select create_invite(:'league_id') as token \gset
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
select test_check((select count(*) from leagues) = 0, 'Sam cannot see the league before joining');
select test_check(
  (select league_name = 'Sunday Hackers' and commissioner_name = 'Kyle' and is_valid and not already_member
   from get_invite_preview(:'token')),
  'invite preview shows the league');
select test_check(accept_invite(:'token') = :'league_id'::uuid, 'Sam joins');
select test_check(accept_invite(:'token') = :'league_id'::uuid, 'joining twice is harmless');
select test_check((select count(*) from league_members) = 2, 'two members');
select test_check((select count(*) from league_invites) = 0, 'members cannot see invites');

reset role;
select test_check((select use_count from league_invites) = 1, 'invite counted once');
\echo 'All happy-path tests passed.'
