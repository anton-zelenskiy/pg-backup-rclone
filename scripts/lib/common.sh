#!/bin/bash
set -euo pipefail

source /scripts/lib/rclone_config.sh

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

rclone_global_flags() {
  RCLONE_GLOBAL_FLAGS=()
  if [ -n "${RCLONE_DRIVE_ROOT_FOLDER_ID:-}" ]; then
    RCLONE_GLOBAL_FLAGS+=(--drive-root-folder-id "${RCLONE_DRIVE_ROOT_FOLDER_ID}")
  fi
}

apply_remote_retention() {
  local base_path="$1"
  local base="${RCLONE_REMOTE}:${base_path}"

  if [ "${RCLONE_KEEP_DAYS}" -le 0 ] 2>/dev/null; then
    return 0
  fi

  log "Applying remote retention (${RCLONE_KEEP_DAYS} days) under ${base}"
  local cutoff_epoch=$(( $(date +%s) - RCLONE_KEEP_DAYS * 86400 ))
  local dir_name dir_epoch

  while IFS= read -r dir_name; do
    dir_name="${dir_name%/}"
    [ -z "$dir_name" ] && continue
    [ "$dir_name" = "latest" ] && continue
    [[ "$dir_name" =~ ^[0-9]{8}_[0-9]{6}$ ]] || continue

    dir_epoch=$(date -D "%Y%m%d %H:%M:%S" -d \
      "${dir_name:0:8} ${dir_name:9:2}:${dir_name:11:2}:${dir_name:13:2}" +%s 2>/dev/null) || continue

    if [ "$dir_epoch" -lt "$cutoff_epoch" ]; then
      log "Removing old backup folder: ${base}/${dir_name}"
      rclone purge "${base}/${dir_name}" --config "$RCLONE_CONFIG" "${RCLONE_GLOBAL_FLAGS[@]}" || \
        log "WARNING: failed to remove ${dir_name}"
    fi
  done < <(rclone lsf "${base}/" --config "$RCLONE_CONFIG" "${RCLONE_GLOBAL_FLAGS[@]}" --dirs-only 2>/dev/null)
}

verify_rclone_remote() {
  local root="${RCLONE_REMOTE}:"
  local output

  log "Configured remotes:"
  rclone listremotes --config "$RCLONE_CONFIG" 2>&1 | while read -r line; do
    log "  ${line}"
  done

  log "Checking access to ${root}"
  if output=$(rclone lsd "$root" --config "$RCLONE_CONFIG" "${RCLONE_GLOBAL_FLAGS[@]}" 2>&1); then
    log "Google Drive root is accessible"
    return 0
  fi

  log "$output"
  log "ERROR: cannot list Google Drive (${root})."
  log "Common fixes on the host (as the user who owns rclone.conf):"
  log "  1. rclone config reconnect ${RCLONE_REMOTE}"
  log "     Choose scope: full access (drive), NOT drive.file"
  log "  2. Shared drive: add team_drive = <id> to rclone.conf, or set RCLONE_DRIVE_ROOT_FOLDER_ID"
  log "  3. Test: rclone lsd ${root}"
  log "  4. Test: rclone mkdir ${root}backups-test && rclone rmdir ${root}backups-test"
  exit 1
}

upload_to_remote() {
  if [ "${UPLOAD_ENABLED}" != "true" ]; then
    log "Upload disabled (UPLOAD_ENABLED=false)"
    return 0
  fi

  prepare_rclone_config || exit 1
  log "rclone config: ${RCLONE_CONFIG} (from ${RCLONE_CONFIG_SOURCE:-/config/rclone/rclone.conf})"
  if grep -q '^root_folder_id' "$RCLONE_CONFIG" 2>/dev/null; then
    log "WARNING: root_folder_id must be a Drive folder ID, not a folder name — remove it or use the ID from the Drive URL"
  fi

  rclone_global_flags

  local base_path="${RCLONE_PATH#/}"
  base_path="${base_path%/}"
  local remote="${RCLONE_REMOTE}:${base_path}/${TIMESTAMP}"
  local latest_remote="${RCLONE_REMOTE}:${base_path}/latest"

  verify_rclone_remote

  log "Uploading ${RUN_DIR} to ${remote}"
  rclone copy "$RUN_DIR" "${remote}/" --config "$RCLONE_CONFIG" "${RCLONE_GLOBAL_FLAGS[@]}"
  log "Updating ${latest_remote}"
  rclone copy "$RUN_DIR" "${latest_remote}/" --config "$RCLONE_CONFIG" \
    "${RCLONE_GLOBAL_FLAGS[@]}" --delete-before

  apply_remote_retention "$base_path"
}

finish_run() {
  apply_local_retention
  upload_to_remote
  log "Backup run completed: ${RUN_DIR}"
}
