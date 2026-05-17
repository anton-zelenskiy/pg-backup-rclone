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

# Mounted rclone.conf is :ro; rclone must write token refreshes to a writable copy
prepare_rclone_config() {
  local src="${RCLONE_CONFIG:-/config/rclone/rclone.conf}"
  local dst="/var/lib/rclone/rclone.conf"

  if [ ! -f "$src" ]; then
    log "ERROR: rclone config not found: ${src}"
    exit 1
  fi

  mkdir -p /var/lib/rclone
  cp "$src" "$dst"
  chmod 600 "$dst"
  export RCLONE_CONFIG="$dst"
  log "Using writable rclone config at ${RCLONE_CONFIG}"
}

prepare_rclone_config

write_crontab() {
  # supercronic uses standard 5-field cron (no user column like system crontab)
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
# Do not exec supercronic: as PID 1 it fails fork/reap on Alpine ("no such file or directory")
supercronic -passthrough-logs "$CRONTAB_FILE" &
SUPERCRONIC_PID=$!
trap 'kill -TERM "$SUPERCRONIC_PID" 2>/dev/null; wait "$SUPERCRONIC_PID"' TERM INT
wait "$SUPERCRONIC_PID"
