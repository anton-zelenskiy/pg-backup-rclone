#!/bin/bash
set -euo pipefail

source /scripts/lib/rclone_config.sh

BACKUP_CRON="${BACKUP_CRON:-0 3 * * 0}"
SCHEDULE_ENABLED="${SCHEDULE_ENABLED:-true}"
RUN_ONCE="${RUN_ONCE:-false}"
BACKUP_ON_START="${BACKUP_ON_START:-false}"
CRONTAB_FILE="/etc/crontab"

log() {
  echo "[entrypoint] $*"
}

write_crontab() {
  cat > "$CRONTAB_FILE" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${BACKUP_CRON} /scripts/backup.sh
EOF
  log "Schedule: ${BACKUP_CRON}"
}

run_backup() {
  /scripts/backup.sh
}

if [ "${BACKUP_ON_START}" = "true" ]; then
  log "Running backup on start"
  run_backup
fi

if [ "${RUN_ONCE}" = "true" ] || [ "${SCHEDULE_ENABLED}" != "true" ]; then
  log "One-shot mode"
  run_backup
  exit 0
fi

write_crontab
log "Starting supercronic"
supercronic -passthrough-logs "$CRONTAB_FILE" &
SUPERCRONIC_PID=$!
trap 'kill -TERM "$SUPERCRONIC_PID" 2>/dev/null; wait "$SUPERCRONIC_PID"' TERM INT
wait "$SUPERCRONIC_PID"
