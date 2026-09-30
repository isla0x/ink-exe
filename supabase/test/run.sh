#!/usr/bin/env bash
# 빈 Postgres 에 스키마를 두 번 올리고(재실행 안전 확인) 테스트를 돌린다.
# 로컬: PGHOST · PGUSER · PGPASSWORD 를 맞추고 bash supabase/test/run.sh
set -euo pipefail
cd "$(dirname "$0")"
export PGOPTIONS='-c client_min_messages=warning'
DB=ink_test
q() { psql -v ON_ERROR_STOP=1 -q -o /dev/null "$@"; }
q -d postgres -c "drop database if exists $DB" -c "create database $DB"
q -d $DB -f stub.sql
q -d $DB -f ../schema.sql
q -d $DB -f ../schema.sql
q -d $DB -f test.sql
echo "db tests OK"
