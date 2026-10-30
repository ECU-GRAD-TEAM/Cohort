#!/usr/bin/env bash
# Rebuilds the test database: drops and recreates it, applies the Supabase stub, then every
# migration in name order. Needs a superuser connection (see the variables below).
set -euo pipefail

admin_url="${TEST_DB_ADMIN_URL:-postgresql://postgres@127.0.0.1:5432/postgres}"
test_url="${TEST_DATABASE_URL:-postgresql://postgres@127.0.0.1:5432/cohort_test}"

# The database name is the last path segment of the URL, without any query string.
db_name="${test_url##*/}"
db_name="${db_name%%\?*}"

# The script force-drops the database, so refuse anything that is not clearly a test database.
if [[ ! "$db_name" =~ ^[a-z][a-z0-9_]*_test$ ]]; then
  echo "refusing to drop '$db_name': a test database name must end in _test" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Keep the output to errors and warnings; the migrations raise many harmless notices.
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"

psql -X -q "$admin_url" -v ON_ERROR_STOP=1 -v db_name="$db_name" <<'SQL'
drop database if exists :"db_name" with (force);
create database :"db_name";
SQL

psql -X -q "$test_url" -v ON_ERROR_STOP=1 -1 -f "$repo_root/scripts/db/supabase-stub.sql"

for migration in "$repo_root"/supabase/migrations/*.sql; do
  psql -X -q "$test_url" -v ON_ERROR_STOP=1 -1 -f "$migration"
done

echo "$db_name ready"
