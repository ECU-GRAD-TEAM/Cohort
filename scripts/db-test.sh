#!/usr/bin/env bash
# Rebuild a throwaway database from supabase/migrations + supabase/seed.sql and run
# the pgTAP suite in supabase/tests/database.
#
# Needs PostgreSQL 16+ with pgvector and pgTAP, plus pg_prove
# (Ubuntu: postgresql-16-pgvector postgresql-16-pgtap libtap-parser-sourcehandler-pgtap-perl).
# Connection settings come from the usual libpq variables (PGHOST, PGPORT, PGUSER,
# PGPASSWORD). Against `supabase start` use PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres.
#
# Usage: scripts/db-test.sh [test files...]   (default: every *.test.sql)
set -euo pipefail
shopt -s nullglob

root="$(cd "$(dirname "$0")/.." && pwd)"
db="${TEST_DB:-market_saas_test}"
export PGHOST="${PGHOST:-127.0.0.1}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}"
export PGOPTIONS="${PGOPTIONS:--c client_min_messages=warning}"

run_sql() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }

run_sql -d postgres -c "drop database if exists \"$db\" with (force)" -c "create database \"$db\""
run_sql -d "$db" -f "$root/scripts/sql/supabase-compat.sql"
for migration in "$root"/supabase/migrations/*.sql; do
  run_sql -d "$db" -f "$migration"
done
run_sql -d "$db" -f "$root/supabase/seed.sql"

if [ "$#" -gt 0 ]; then
  pg_prove -d "$db" "$@"
else
  pg_prove -d "$db" "$root"/supabase/tests/database/*.test.sql
fi
