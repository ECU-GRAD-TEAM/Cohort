#!/usr/bin/env bash
# Supabase compatibility check. On Supabase the `postgres` role is not a superuser, so this
# applies every migration and the seed as a role shaped like it (login, createrole, createdb,
# bypassrls, nosuperuser) and then runs the pgTAP suite as that role. Any WARNING while
# migrating fails the check, because on Supabase it usually means a grant silently did nothing.
#
# Needs a local superuser connection (PGUSER, default postgres) and the same packages as
# scripts/db-test.sh. Local clusters only: the app roles are cluster-wide, so this drops its
# own database, TEST_DB of scripts/db-test.sh and the market_* roles, then recreates the roles
# as the simulated postgres, the way a fresh Supabase project would. If another database still
# uses those roles, dropping them fails and the error names that database.
# The two tests that take away access to the extensions schema print a WARNING here: only the
# schema's owner can revoke it, so they make their point under scripts/db-test.sh.
#
# Usage: PGPASSWORD=... scripts/db-test-nonsuper.sh
set -euo pipefail
shopt -s nullglob

root="$(cd "$(dirname "$0")/.." && pwd)"
db="${NONSUPER_DB:-market_saas_nonsuper}"
sim_role=market_supabase_postgres
sim_password="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
export PGHOST="${PGHOST:-127.0.0.1}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}"
export PGOPTIONS='-c client_min_messages=warning'

as_admin() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }
as_sim()   { PGUSER="$sim_role" PGPASSWORD="$sim_password" psql -X -q -v ON_ERROR_STOP=1 "$@"; }

for stale in "$db" "${TEST_DB:-market_saas_test}"; do
  as_admin -d postgres -c "drop database if exists \"$stale\" with (force)"
done
for role in market_backend market_ai_reader market_analytics_owner market_biometric "$sim_role"; do
  as_admin -d postgres -c "drop role if exists $role"
done
as_admin -d postgres \
  -c "create role $sim_role login password '$sim_password' createrole createdb bypassrls nosuperuser" \
  -c "create database \"$db\" owner $sim_role"

# What Supabase installs as its own superuser before the project's migrations run.
as_admin -d "$db" -f "$root/scripts/sql/supabase-compat.sql"

for file in "$root"/supabase/migrations/*.sql "$root/supabase/seed.sql"; do
  output="$(as_sim -d "$db" -f "$file" 2>&1)"
  if grep -q WARNING <<<"$output"; then
    printf '%s: %s\n' "$(basename "$file")" "$output" >&2
    exit 1
  fi
done
echo "Migrations and seed applied as a non-superuser without warnings."

PGUSER="$sim_role" PGPASSWORD="$sim_password" pg_prove -d "$db" "$root"/supabase/tests/database/*.test.sql
