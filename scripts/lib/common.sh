#!/bin/bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-7}"
RCLONE_KEEP_DAYS="${RCLONE_KEEP_DAYS:-30}"
RCLONE_CONFIG="${RCLONE_CONFIG:-/var/lib/rclone/rclone.conf}"
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

# rclone mkdir has no -p; create each path segment (e.g. backups, then backups/market-crm)
ensure_rclone_remote_path() {
  local rel_path="$1"
  local built="" part
  local -a parts

  rel_path="${rel_path#/}"
  rel_path="${rel_path%/}"
  [ -z "$rel_path" ] && return 0

  IFS='/' read -ra parts <<< "$rel_path"
  for part in "${parts[@]}"; do
    if [ -z "$built" ]; then
      built="$part"
    else
      built="${built}/${part}"
    fi
    if ! rclone mkdir "${RCLONE_REMOTE}:${built}" --config "$RCLONE_CONFIG" 2>&1; then
      log "mkdir ${RCLONE_REMOTE}:${built} (may already exist)"
    fi
  done
}

upload_to_remote() {
  if [ "${UPLOAD_ENABLED}" != "true" ]; then
    log "Upload disabled (UPLOAD_ENABLED=false)"
    return 0
  fi

  if [ ! -f "${RCLONE_CONFIG}" ]; then
    log "ERROR: rclone config not found at ${RCLONE_CONFIG}"
    log "Hint: mount host dir, e.g. /home/user/.config/rclone:/config/rclone:ro and RCLONE_CONFIG=/config/rclone/rclone.conf"
    exit 1
  fi
  if [ ! -r "${RCLONE_CONFIG}" ]; then
    log "ERROR: rclone config not readable: ${RCLONE_CONFIG}"
    log "Hint: image runs as root; on host run chmod 600 and ensure the file exists"
    exit 1
  fi

  export RCLONE_CONFIG
  local base_path="${RCLONE_PATH#/}"
  base_path="${base_path%/}"
  local base_remote="${RCLONE_REMOTE}:${base_path}"
  local remote="${base_remote}/${TIMESTAMP}"
  local latest_remote="${base_remote}/latest"

  log "Ensuring Google Drive path exists: ${base_remote}"
  ensure_rclone_remote_path "$base_path"
  ensure_rclone_remote_path "${base_path}/latest"

  if ! rclone lsd "$base_remote" --config "$RCLONE_CONFIG" >/dev/null 2>&1; then
    log "ERROR: cannot access remote path ${base_remote}"
    log "Check RCLONE_REMOTE (${RCLONE_REMOTE}) matches: rclone listremotes"
    rclone listremotes --config "$RCLONE_CONFIG" 2>&1 | while read -r line; do log "$line"; done
    exit 1
  fi

  log "Uploading ${RUN_DIR} to ${remote}"
  rclone copy "$RUN_DIR" "$remote" --config "$RCLONE_CONFIG"
  rclone copy "$RUN_DIR" "$latest_remote" --config "$RCLONE_CONFIG" --delete-before

  if [ "${RCLONE_KEEP_DAYS}" -gt 0 ] 2>/dev/null; then
    log "Applying remote retention (${RCLONE_KEEP_DAYS} days)"
    rclone delete "${base_remote}" \
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
