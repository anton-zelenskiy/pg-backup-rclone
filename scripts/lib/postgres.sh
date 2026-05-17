#!/bin/bash
set -euo pipefail

source /scripts/lib/common.sh

PGHOST="${DB_HOST:-${PGHOST:-db}}"
PGPORT="${DB_PORT:-${PGPORT:-5432}}"
PGUSER="${DB_USER:-${PGUSER:-postgres}}"
PGPASSWORD="${DB_PASSWORD:-${PGPASSWORD:-}}"
PGDATABASE="${DB_NAME:-${PGDATABASE:-}}"
BACKUP_ALL_DATABASES="${BACKUP_ALL_DATABASES:-false}"
PGDUMP_EXTRA="${PGDUMP_EXTRA:---clean --if-exists --no-owner --no-acl}"

export PGPASSWORD

list_postgres_databases() {
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -Atqc \
    "SELECT datname FROM pg_database
     WHERE datistemplate = false
       AND datname NOT IN ('postgres')"
}

dump_postgres_database() {
  local database="$1"
  local output="${RUN_DIR}/${database}.sql.gz"

  log "PostgreSQL dump: ${database} -> ${output}"
  pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$database" $PGDUMP_EXTRA | gzip > "$output"
}

test_postgres_connection() {
  log "PostgreSQL: ${PGUSER}@${PGHOST}:${PGPORT}"
  if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -Atqc "SELECT 1" >/dev/null 2>&1; then
    return 0
  fi
  log "ERROR: cannot connect to PostgreSQL"
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -Atqc "SELECT 1" 2>&1 | while read -r line; do
    log "$line"
  done || true
  exit 1
}

backup_postgres() {
  require_var PGPASSWORD
  ensure_backup_dir
  test_postgres_connection

  local databases=()
  if [ "${BACKUP_ALL_DATABASES}" = "true" ]; then
    mapfile -t databases < <(list_postgres_databases)
    if [ "${#databases[@]}" -eq 0 ]; then
      log "ERROR: no PostgreSQL databases found"
      exit 1
    fi
  else
    require_var PGDATABASE
    databases=("$PGDATABASE")
  fi

  for database in "${databases[@]}"; do
    dump_postgres_database "$database"
  done

  finish_run
}
