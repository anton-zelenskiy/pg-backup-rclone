#!/bin/bash
set -euo pipefail

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
${BACKUP_CRON} root /scripts/backup.sh >> /var/log/backup.log 2>&1
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
touch /var/log/backup.log
log "Starting supercronic"
exec supercronic -passthrough-logs "$CRONTAB_FILE"
