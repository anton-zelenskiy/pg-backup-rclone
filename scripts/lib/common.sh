#!/bin/bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-7}"
RCLONE_KEEP_DAYS="${RCLONE_KEEP_DAYS:-30}"
RCLONE_CONFIG="${RCLONE_CONFIG:-/config/rclone.conf}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
RCLONE_PATH="${RCLONE_PATH:-Backups/default}"
UPLOAD_ENABLED="${UPLOAD_ENABLED:-true}"
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
RUN_DIR="${BACKUP_DIR}/${TIMESTAMP}"

log() {
  echo "[$(date -Iseconds)] $*"
}

require_var() {
  local name="$1"
  local value="${!name:-}"
  if [ -z "$value" ]; then
    log "ERROR: required variable ${name} is not set"
    exit 1
  fi
}

ensure_backup_dir() {
  mkdir -p "$BACKUP_DIR" "$RUN_DIR"
}

apply_local_retention() {
  if [ "${BACKUP_KEEP_DAYS}" -le 0 ] 2>/dev/null; then
    return 0
  fi
  log "Applying local retention (${BACKUP_KEEP_DAYS} days) in ${BACKUP_DIR}"
  find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime "+${BACKUP_KEEP_DAYS}" -exec rm -rf {} +
}

upload_to_remote() {
  if [ "${UPLOAD_ENABLED}" != "true" ]; then
    log "Upload disabled (UPLOAD_ENABLED=false)"
    return 0
  fi

  if [ ! -f "${RCLONE_CONFIG}" ]; then
    log "ERROR: rclone config not found at ${RCLONE_CONFIG}"
    exit 1
  fi

  export RCLONE_CONFIG
  local remote="${RCLONE_REMOTE}:${RCLONE_PATH}/${TIMESTAMP}"

  log "Uploading ${RUN_DIR} to ${remote}"
  rclone copy "$RUN_DIR" "$remote" --config "$RCLONE_CONFIG"
  rclone copy "$RUN_DIR" "${RCLONE_REMOTE}:${RCLONE_PATH}/latest" --config "$RCLONE_CONFIG"

  if [ "${RCLONE_KEEP_DAYS}" -gt 0 ] 2>/dev/null; then
    log "Applying remote retention (${RCLONE_KEEP_DAYS} days)"
    rclone delete "${RCLONE_REMOTE}:${RCLONE_PATH}" \
      --config "$RCLONE_CONFIG" \
      --min-age "${RCLONE_KEEP_DAYS}d" \
      --rmdirs || true
  fi
}

finish_run() {
  apply_local_retention
  upload_to_remote
  log "Backup run completed: ${RUN_DIR}"
}
