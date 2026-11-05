-- PGA Fantasy: core schema
-- Three groups of tables:
--   1. Golf data (global, written only by Edge Functions with the service role)
--   2. League data (members only, guarded by row-level security)
--   3. Money (append-only ledger; side bets are a separate pot)

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.league_role        as enum ('commissioner', 'member');
create type public.tournament_status  as enum ('scheduled', 'in_progress', 'final', 'cancelled');
create type public.league_event_status as enum ('scheduled', 'drafting', 'in_progress', 'final');
create type public.draft_status       as enum ('scheduled', 'live', 'paused', 'complete');
create type public.draft_slot         as enum ('veteran', 'rookie');
create type public.field_status       as enum ('active', 'wd', 'cut', 'dq');
create type public.hole_result        as enum ('hole_in_one', 'eagle', 'birdie', 'par', 'bogey_or_worse');
create type public.ledger_pot         as enum ('main', 'side_bets');
create type public.ledger_kind        as enum ('buy_in', 'season_payout', 'bet_stake', 'bet_win', 'adjustment');
create type public.bet_status         as enum ('open', 'accepted', 'declined', 'expired', 'won', 'push', 'void');

-- ---------------------------------------------------------------------------
-- 1. Golf data
-- ---------------------------------------------------------------------------
create table public.players (
  id           uuid primary key default gen_random_uuid(),
  provider_id  text not null unique,
  first_name   text not null,
  last_name    text not null,
  country      text,
  is_rookie    boolean not null default false,   -- official PGA Tour rookie status from the feed
  owgr         integer,
  updated_at   timestamptz not null default now()
);

create table public.tournaments (
  id           uuid primary key default gen_random_uuid(),
  provider_id  text not null unique,
  name         text not null,
  season       integer not null,
  start_date   date not null,
  end_date     date not null,
  course       text,
  purse_cents  bigint,
  is_major     boolean not null default false,
  has_cut      boolean not null default true,
  status       public.tournament_status not null default 'scheduled',
  updated_at   timestamptz not null default now(),
  check (end_date >= start_date)
);
create index tournaments_season_idx on public.tournaments (season, start_date);

create table public.tournament_field (
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  player_id     uuid not null references public.players (id) on delete cascade,
  status        public.field_status not null default 'active',
  primary key (tournament_id, player_id)
);

create table public.rounds (
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  player_id     uuid not null references public.players (id) on delete cascade,
  round_no      smallint not null check (round_no between 1 and 4),
  strokes       smallint,
  to_par        smallint,
  position      text,                 -- as displayed, e.g. 'T4'
  position_rank integer,              -- numeric place used for scoring, ties share a rank
  is_complete   boolean not null default false,
  updated_at    timestamptz not null default now(),
  primary key (tournament_id, player_id, round_no)
);

create table public.hole_scores (
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  player_id     uuid not null references public.players (id) on delete cascade,
  round_no      smallint not null check (round_no between 1 and 4),
  hole_no       smallint not null check (hole_no between 1 and 18),
  par           smallint not null check (par between 3 and 6),
  strokes       smallint check (strokes > 0),
  updated_at    timestamptz not null default now(),
  primary key (tournament_id, player_id, round_no, hole_no)
);

create table public.tee_groups (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  round_no      smallint not null check (round_no between 1 and 4),
  tee_time      timestamptz not null,
  starting_hole smallint not null default 1 check (starting_hole between 1 and 18),
  player_ids    uuid[] not null,
  unique (tournament_id, round_no, tee_time, starting_hole)
);
create index tee_groups_players_idx on public.tee_groups using gin (player_ids);

-- One row per hole: replaying the feed can never double-count a result.
create table public.scoring_events (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  player_id     uuid not null references public.players (id) on delete cascade,
  round_no      smallint not null,
  hole_no       smallint not null,
  result        public.hole_result not null,
  detected_at   timestamptz not null default now(),
  unique (tournament_id, player_id, round_no, hole_no)
);

-- ---------------------------------------------------------------------------
-- 2. League data
-- ---------------------------------------------------------------------------
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  avatar_url   text,
  created_at   timestamptz not null default now()
);

-- Default scoring rules. Every rule can be switched off or re-valued per league.
create or replace function public.default_scoring_rules()
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'daily_leader',      jsonb_build_object('enabled', true, 'points', 20),
    'daily_top5',        jsonb_build_object('enabled', true, 'points', 10),
    'daily_top10',       jsonb_build_object('enabled', true, 'points', 5),
    'finish_win',        jsonb_build_object('enabled', true, 'points', 50),
    'finish_second',     jsonb_build_object('enabled', true, 'points', 25),
    'finish_third_plus', jsonb_build_object('enabled', true, 'points', 24), -- 3rd = 24, one less per place, floor 0
    'hole_in_one',       jsonb_build_object('enabled', true, 'points', 25),
    'eagle',             jsonb_build_object('enabled', true, 'points', 10),
    'birdie',            jsonb_build_object('enabled', true, 'points', 1),
    'bogey_or_worse',    jsonb_build_object('enabled', true, 'points', -1),
    'rookie_win',        jsonb_build_object('enabled', true, 'points', 25),
    'rookie_top5',       jsonb_build_object('enabled', true, 'points', 10)
  );
$$;

create table public.leagues (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null check (char_length(name) between 2 and 60),
  season              integer not null,
  commissioner_id     uuid not null references public.profiles (id),
  roster_size         smallint not null default 5 check (roster_size between 1 and 10),
  rookie_slots        smallint not null default 1 check (rookie_slots >= 0),
  pick_seconds        integer not null default 90 check (pick_seconds between 15 and 600),
  scoring_rules       jsonb not null default public.default_scoring_rules(),
  side_bets_enabled   boolean not null default true,
  side_bet_min_cents  integer not null default 500 check (side_bet_min_cents > 0),
  side_bet_max_cents  integer not null default 5000,
  created_at          timestamptz not null default now(),
  check (rookie_slots <= roster_size),
  check (side_bet_max_cents >= side_bet_min_cents)
);

create table public.league_members (
  league_id        uuid not null references public.leagues (id) on delete cascade,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  role             public.league_role not null default 'member',
  side_bets_opt_in boolean not null default false,
  joined_at        timestamptz not null default now(),
  primary key (league_id, user_id)
);
create index league_members_user_idx on public.league_members (user_id);

create table public.league_invites (
  id          uuid primary key default gen_random_uuid(),
  league_id   uuid not null references public.leagues (id) on delete cascade,
  token       text not null unique default encode(gen_random_bytes(16), 'hex'),
  email       text,                       -- optional: restrict the invite to one address
  created_by  uuid not null references public.profiles (id),
  expires_at  timestamptz not null default now() + interval '14 days',
  max_uses    integer check (max_uses is null or max_uses > 0),
  use_count   integer not null default 0,
  revoked_at  timestamptz,
  created_at  timestamptz not null default now()
);

create table public.league_rookie_overrides (
  league_id  uuid not null references public.leagues (id) on delete cascade,
  player_id  uuid not null references public.players (id) on delete cascade,
  is_rookie  boolean not null,
  set_by     uuid not null references public.profiles (id),
  set_at     timestamptz not null default now(),
  primary key (league_id, player_id)
);

create table public.league_events (
  id               uuid primary key default gen_random_uuid(),
  league_id        uuid not null references public.leagues (id) on delete cascade,
  tournament_id    uuid not null references public.tournaments (id),
  draft_at         timestamptz,
  status           public.league_event_status not null default 'scheduled',
  scoring_snapshot jsonb,   -- rules copied when the draft starts; an event keeps the rules it started with
  created_at       timestamptz not null default now(),
  unique (league_id, tournament_id)
);

create table public.drafts (
  id              uuid primary key default gen_random_uuid(),
  league_event_id uuid not null unique references public.league_events (id) on delete cascade,
  pick_order      uuid[] not null default '{}',   -- round 1 order; snake reverses each round
  pick_seconds    integer not null default 90,
  current_pick    integer not null default 1,
  pick_deadline   timestamptz,
  status          public.draft_status not null default 'scheduled',
  started_at      timestamptz,
  completed_at    timestamptz
);

create table public.draft_picks (
  draft_id    uuid not null references public.drafts (id) on delete cascade,
  pick_no     integer not null,
  user_id     uuid not null references public.profiles (id),
  player_id   uuid not null references public.players (id),
  slot        public.draft_slot not null,
  is_autopick boolean not null default false,
  picked_at   timestamptz not null default now(),
  primary key (draft_id, pick_no),
  unique (draft_id, player_id)
);

create table public.draft_queues (
  draft_id   uuid not null references public.drafts (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  player_ids uuid[] not null default '{}',
  updated_at timestamptz not null default now(),
  primary key (draft_id, user_id)
);

-- round_no 0 holds final-finish points; 1-4 hold daily and hole points.
create table public.fantasy_scores (
  league_event_id uuid not null references public.league_events (id) on delete cascade,
  user_id         uuid not null references public.profiles (id),
  player_id       uuid not null references public.players (id),
  round_no        smallint not null check (round_no between 0 and 4),
  points          numeric(8, 2) not null default 0,
  breakdown       jsonb not null default '{}',
  updated_at      timestamptz not null default now(),
  primary key (league_event_id, user_id, player_id, round_no)
);

create table public.daily_results (
  league_event_id uuid not null references public.league_events (id) on delete cascade,
  round_no        smallint not null check (round_no between 1 and 4),
  user_id         uuid not null references public.profiles (id),
  points          numeric(8, 2) not null default 0,
  rank            integer,
  is_official     boolean not null default false,
  primary key (league_event_id, round_no, user_id)
);

-- ---------------------------------------------------------------------------
-- 3. Money
-- ---------------------------------------------------------------------------
create table public.side_bets (
  id                 uuid primary key default gen_random_uuid(),
  league_event_id    uuid not null references public.league_events (id) on delete cascade,
  round_no           smallint not null check (round_no between 1 and 4),
  tee_group_id       uuid not null references public.tee_groups (id),
  creator_id         uuid not null references public.profiles (id),
  opponent_id        uuid not null references public.profiles (id),
  creator_player_id  uuid not null references public.players (id),
  opponent_player_id uuid not null references public.players (id),
  terms              jsonb not null default '{"type": "lower_round_score"}',
  stake_cents        integer not null check (stake_cents > 0),  -- each side puts in this amount
  status             public.bet_status not null default 'open',
  winner_id          uuid references public.profiles (id),
  created_at         timestamptz not null default now(),
  resolved_at        timestamptz,
  check (creator_id <> opponent_id)
);

-- Balance per member per pot = sum(amount_cents). Positive = owed to the member.
-- Rows are never updated or deleted; corrections are new 'adjustment' rows.
create table public.ledger_entries (
  id           uuid primary key default gen_random_uuid(),
  league_id    uuid not null references public.leagues (id) on delete cascade,
  user_id      uuid not null references public.profiles (id),
  pot          public.ledger_pot not null,
  kind         public.ledger_kind not null,
  amount_cents bigint not null check (amount_cents <> 0),
  ref_id       uuid,
  note         text,
  created_by   uuid references public.profiles (id),
  created_at   timestamptz not null default now()
);
create index ledger_entries_league_idx on public.ledger_entries (league_id, pot, user_id);

create table public.settlements (
  id           uuid primary key default gen_random_uuid(),
  league_id    uuid not null references public.leagues (id) on delete cascade,
  pot          public.ledger_pot not null,
  from_user    uuid not null references public.profiles (id),
  to_user      uuid not null references public.profiles (id),
  amount_cents bigint not null check (amount_cents > 0),
  method       text,
  paid_at      timestamptz,
  confirmed_at timestamptz,
  created_at   timestamptz not null default now(),
  check (from_user <> to_user)
);

create table public.audit_log (
  id        uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues (id) on delete cascade,
  actor_id  uuid references public.profiles (id),
  action    text not null,
  before    jsonb,
  after     jsonb,
  at        timestamptz not null default now()
);
create index audit_log_league_idx on public.audit_log (league_id, at desc);

-- The ledger and audit log are append-only, even for the service role.
create or replace function public.prevent_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception '% is append-only', tg_table_name;
end;
$$;

create trigger ledger_entries_append_only
  before update or delete on public.ledger_entries
  for each row execute function public.prevent_mutation();

create trigger audit_log_append_only
  before update or delete on public.audit_log
  for each row execute function public.prevent_mutation();
