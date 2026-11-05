-- Permission and money checks. Runs after 10_happy_path.sql. Fails loudly on any surprise.
\set ON_ERROR_STOP 1

-- Test helpers (test database only)
create function public.test_expect_error(p_sql text, p_contains text default null)
returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'expected an error but none was raised: %', p_sql;
exception
  when others then
    if sqlerrm like 'expected an error%' then raise; end if;
    if p_contains is not null and position(p_contains in sqlerrm) = 0 then
      raise exception 'wrong error for %: got "%" (wanted "%")', p_sql, sqlerrm, p_contains;
    end if;
end $$;

create function public.test_assert(p_ok boolean, p_what text)
returns void language plpgsql as $$
begin
  if p_ok is not true then raise exception 'assertion failed: %', p_what; end if;
end $$;

select id as league_id from leagues \gset
set role authenticated;

-- Sam (member) cannot do commissioner things --------------------------------
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
select test_expect_error(format('select create_invite(%L)', :'league_id'), 'only the commissioner');
select test_expect_error(format('select update_scoring_rules(%L, %L)', :'league_id', '{"birdie":{"enabled":true,"points":100}}'), 'only the commissioner');
select test_expect_error(format('select record_buy_in(%L, %L, 5000)', :'league_id', '00000000-0000-0000-0000-000000000002'), 'only the commissioner');
select test_expect_error(format('select add_league_event(%L, (select id from tournaments limit 1))', :'league_id'), 'only the commissioner');
select test_expect_error('update league_members set role = ''commissioner'' where user_id = auth.uid()', 'permission denied');
select test_expect_error('update leagues set scoring_rules = ''{}''', 'permission denied');
select test_expect_error(format('insert into ledger_entries (league_id, user_id, pot, kind, amount_cents) values (%L, auth.uid(), ''main'', ''season_payout'', 99999)', :'league_id'), 'row-level security');

with u as (update leagues set name = 'hijacked' returning 1)
select test_assert((select count(*) from u) = 0, 'member cannot rename the league');

with u as (update league_members set side_bets_opt_in = true where user_id = auth.uid() returning 1)
select test_assert((select count(*) from u) = 1, 'member can toggle own side-bet opt-in');

-- Eve (not in the league) sees nothing ---------------------------------------
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
select test_assert((select count(*) from leagues) = 0, 'outsider sees no leagues');
select test_assert((select count(*) from league_members) = 0, 'outsider sees no members');
select test_assert((select count(*) from profiles) = 1, 'outsider sees only own profile');
select test_assert((select count(*) from audit_log) = 0, 'outsider sees no audit log');

-- Email-locked invite ---------------------------------------------------------
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select create_invite(:'league_id', 'Sam@Example.com', 7, 1) as locked_token \gset
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
select test_expect_error(format('select accept_invite(%L)', :'locked_token'), 'different email');

-- Scoring rule validation -----------------------------------------------------
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select test_expect_error(format('select update_scoring_rules(%L, %L)', :'league_id', '{"made_up":{"enabled":true,"points":1}}'), 'unknown scoring rule');
select test_expect_error(format('select update_scoring_rules(%L, %L)', :'league_id', '{"eagle":{"enabled":"yes","points":1}}'), 'needs enabled');
select test_assert(
  (select (scoring_rules -> 'birdie' ->> 'points')::int = 2 and (scoring_rules -> 'rookie_win' ->> 'enabled')::boolean = false
     and jsonb_typeof(scoring_rules -> 'hole_in_one') = 'object'
   from leagues),
  'earlier scoring edits kept and every default key present');

-- Buy-ins and the season pot --------------------------------------------------
select record_buy_in(:'league_id', '00000000-0000-0000-0000-000000000001', 10000, 'season buy-in');
select record_buy_in(:'league_id', '00000000-0000-0000-0000-000000000002', 7500);
select test_expect_error(format('select record_buy_in(%L, %L, 7500)', :'league_id', '00000000-0000-0000-0000-000000000003'), 'not in this league');
select test_assert((select sum(buy_in_cents) from league_money_summary(:'league_id')) = 17500, 'pot totals 175.00');
select record_buy_in(:'league_id', '00000000-0000-0000-0000-000000000002', -2500, 'refund');
select test_assert(
  (select buy_in_cents from league_money_summary(:'league_id') where user_id = '00000000-0000-0000-0000-000000000002') = 5000,
  'refund lowers a buy-in');

-- Eve cannot read the league's money even by calling the function directly
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
select test_assert((select count(*) from league_money_summary(:'league_id')) = 0, 'outsider gets no money summary');

-- Ledger and audit log are append-only, even for the database owner -----------
reset role;
select test_expect_error('update ledger_entries set amount_cents = 1', 'append-only');
select test_expect_error('delete from audit_log', 'append-only');

-- Revoked invites stop working ------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select revoke_invite((select id from league_invites where token = :'locked_token'));
select test_assert((select not is_valid and reason = 'revoked' from get_invite_preview(:'locked_token')), 'revoked invite shows as revoked');
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
select test_expect_error(format('select accept_invite(%L)', :'locked_token'), 'revoked');

-- Anonymous visitors cannot call anything -------------------------------------
set role anon;
select test_expect_error('select create_league(''x'', 2027)', 'permission denied');
select test_expect_error(format('select * from get_invite_preview(%L)', :'locked_token'), 'permission denied');

-- Removing events: only before the draft starts --------------------------------
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select remove_league_event((select id from league_events limit 1));
select test_assert((select count(*) from league_events) = 0 and (select count(*) from drafts) = 0, 'event and its draft removed');

reset role;
\echo 'All permission tests passed.'
