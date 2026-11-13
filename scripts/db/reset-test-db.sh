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

# GradProj has a little state that no migration creates. A file in scripts/db/pre-migration with
# a migration's name runs just before that migration, to recreate it.
# Some migrations only rework GradProj's real records (named staff, transcripts, the approved
# timetable) and stop when those records are missing, which they always are in an empty test
# database. Two lists in scripts/db handle them:
# - data-only-migrations.txt: migrations with no structural change; the test build skips them.
# - data-check-migrations.txt: migrations that also change structure; the test build runs them
#   without their top-level DO $$ ... END $$; blocks, which check or move those records.
skip_list="$repo_root/scripts/db/data-only-migrations.txt"
check_list="$repo_root/scripts/db/data-check-migrations.txt"
listed() { [[ -f "$1" ]] && grep -qxF "$2" "$1"; }
for migration in "$repo_root"/supabase/migrations/*.sql; do
  name="$(basename "$migration" .sql)"
  if listed "$skip_list" "$name"; then
    continue
  fi
  pre="$repo_root/scripts/db/pre-migration/$name.sql"
  if [[ -f "$pre" ]]; then
    psql -X -q "$test_url" -v ON_ERROR_STOP=1 -1 -f "$pre"
  fi
  if listed "$check_list" "$name"; then
    awk '/^DO \$\$/ { skip = 1 } !skip { print } skip && /^END \$\$/ { skip = 0 }' "$migration" |
      psql -X -q "$test_url" -v ON_ERROR_STOP=1 -1 -f -
  else
    psql -X -q "$test_url" -v ON_ERROR_STOP=1 -1 -f "$migration"
  fi
done

echo "$db_name ready"
