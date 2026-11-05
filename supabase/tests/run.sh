#!/usr/bin/env bash
# Runs the database tests against a plain Postgres (no Supabase needed).
# Usage: PGHOST=localhost PGUSER=postgres ./supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
DB="${TEST_DB:-pga_fantasy_test}"
psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
for f in supabase/tests/00_supabase_stub.sql supabase/migrations/*.sql supabase/seed.sql \
         supabase/tests/10_happy_path.sql supabase/tests/20_permissions.sql; do
  echo "-> $f"
  psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f"
done
