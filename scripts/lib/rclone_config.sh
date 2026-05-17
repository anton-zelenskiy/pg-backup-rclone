#!/bin/bash

# Copy mounted config to a writable path (OAuth refresh + pick up host edits).
prepare_rclone_config() {
  local src="${RCLONE_CONFIG_SOURCE:-/config/rclone/rclone.conf}"
  local dst="/var/lib/rclone/rclone.conf"

  if [ ! -f "$src" ]; then
    echo "[$(date -Iseconds)] ERROR: rclone config not found: ${src}" >&2
    return 1
  fi

  mkdir -p /var/lib/rclone
  cp "$src" "$dst"
  chmod 600 "$dst"
  export RCLONE_CONFIG="$dst"
}
