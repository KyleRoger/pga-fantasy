# PGA Fantasy

A private-league fantasy app for the PGA Tour. A commissioner starts a league and invites friends; everyone drafts 5 golfers (including 1 rookie) before each selected event; golfers earn points for daily leaderboard position, final finish and hole results; whoever has the most points at season's end takes the whole pot. Side bets run as a separate pot when two members' golfers share a tee-time group.

It's a mobile-first web app that installs on phones as a PWA. Money is **tracked, not handled**: the app keeps the ledger and members settle up outside it.

**Stack:** Vue 3 + Vite + TypeScript + Pinia + Vue Router, `vite-plugin-pwa`, Supabase (Postgres, Auth, Realtime, Edge Functions).

## What's built (phase 1)

- **Accounts** — email + password or magic-link sign-in; a profile is created automatically.
- **Leagues** — create a league (you become commissioner), see your leagues, member list, remove members, leave a league.
- **Invites** — open links (14 days) or links locked to one email; share sheet on phones, copy elsewhere; cancel any time. Joining shows a preview of the league first.
- **Events** — commissioner picks which tournaments count; each one gets its own draft record.
- **Money** — commissioner records each member's season buy-in (amounts can differ); the season pot total and per-member buy-ins are shown. Side-bet balances appear once side bets exist.
- **Settings** — roster size, rookie slots, seconds per pick, side-bet on/off and stake limits, and a scoring editor where every rule can be switched off or re-valued. Members can opt in or out of side bets.
- **Database** — all 22 tables for the full app, row-level security on every table, and tested RPCs for every commissioner action, each recorded in an append-only audit log.

Still to come, per the roadmap: the live draft room (phase 2), golf data sync and live scoring (phase 3), payouts and settle-up (phase 4), side bets and web push alerts (phase 5).

## Run it locally

You need **Node 20.19+** and **Docker** (for the local Supabase stack).

```bash
npm install
npx supabase start          # starts Postgres, Auth and Studio in Docker; applies migrations and seed data
cp .env.example .env.local  # then paste the "anon key" that `supabase start` printed
npm run dev                 # http://localhost:5173
```

Local email confirmation is off, so you can create accounts straight away. Magic-link emails land in the local inbox at http://127.0.0.1:54324. To test invites, open the invite link in a private window and sign up as a second person.

`npx supabase db reset` wipes the local database and reloads migrations plus the sample tournaments and golfers in `supabase/seed.sql`.

## Put it online

1. **Create a Supabase project** at supabase.com (free tier is fine).
2. **Push the schema:** `npx supabase login`, `npx supabase link --project-ref <your-ref>`, then `npx supabase db push`.
3. **Auth settings** (Supabase dashboard → Authentication → URL configuration): set the Site URL to your app's address and add `https://<your-app>/**` as a redirect URL. Turn email confirmation on.
4. **Host the front end** on Netlify, Vercel or Cloudflare Pages: build command `npm run build`, output folder `dist`, and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` from Project Settings → API. Add a single-page-app rewrite so every path serves `index.html` (Netlify: `/* /index.html 200`).

The anon key is safe in the browser because row-level security guards the data. **Never** put the `service_role` key in the front end; it's only for Edge Functions.

## Project layout

```
src/
  views/             pages: login, leagues, create, join, profile
  views/league/      league pages: home (members + invites), events, money, settings
  components/        bottom nav, page header, invite panel, install prompt
  stores/            Pinia stores: auth, leagues
  lib/               Supabase client, scoring defaults, money/date formatting
supabase/
  migrations/        schema, row-level security, RPC functions
  tests/             SQL tests that run on plain Postgres (also in CI)
  seed.sql           sample tournaments and golfers for local dev
```

## Database tests

The SQL tests check the happy path (sign up → create league → invite → join) and the security rules (members can't act as commissioner, outsiders see nothing, the ledger is append-only, locked and revoked invites are refused, buy-ins add up). They run against any Postgres 16:

```bash
PGHOST=localhost PGUSER=postgres ./supabase/tests/run.sh
```

GitHub Actions runs them, plus a typecheck and build, on every push.

## Design notes

- **Scoring is data.** Each league stores its rules as JSON (`leagues.scoring_rules`); `update_scoring_rules` validates and audits changes. An event copies the rules when its draft starts, so mid-event edits never change live scores.
- **Money rows are permanent.** `ledger_entries` and `audit_log` reject updates and deletes at the database level; corrections are new rows. A buy-in is stored as a negative balance (owed to the pot) so the season payout nets everyone out.
- **The browser can't award points or money.** Members only read league data; writes go through RPCs that check the caller's role, or through Edge Functions with the service role.
