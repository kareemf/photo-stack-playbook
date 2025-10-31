#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: setup_nas_mount.sh [--dry-run]
  --dry-run   Show actions without making changes
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE with NAS credentials." >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

for var in NAS_USER NAS_USERPASS NAS_HOST; do
  if [ -z "${!var:-}" ]; then
    echo "Missing $var in $ENV_FILE." >&2
    exit 1
  fi
done

NAS_SHARE="${NAS_SHARE:-photos}"
MOUNT_POINT="/Volumes/Photos"
AUTO_MASTER_D="/etc/auto_master.d/photos.autofs"
AUTO_MAP="/etc/auto_photos"

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

run_sudo_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] sudo '
    printf '%q ' "$@"
    printf '\n'
  else
    sudo "$@"
  fi
}

write_file_as_root() {
  local path="$1"
  local content="$2"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] write %s with:\n%s\n' "$path" "$content"
  else
    printf '%s\n' "$content" | sudo tee "$path" > /dev/null
  fi
}

backup_if_exists() {
  local path="$1"
  if [ -f "$path" ]; then
    local backup="${path}.bak.$(date +%s)"
    run_sudo_cmd cp "$path" "$backup"
    echo "Backed up $path to $backup"
  fi
}

echo "Creating mount point at $MOUNT_POINT"
run_sudo_cmd mkdir -p "$MOUNT_POINT"

if mount | grep -q "on ${MOUNT_POINT} "; then
  echo "$MOUNT_POINT already mounted."
else
  echo "Mounting SMB share for immediate use (password prompt may appear)..."
  run_cmd mount_smbfs "//${NAS_USER}@${NAS_HOST}/${NAS_SHARE}" "$MOUNT_POINT"
fi

echo "Configuring autofs entries"
backup_if_exists "$AUTO_MASTER_D"
backup_if_exists "$AUTO_MAP"

write_file_as_root "$AUTO_MASTER_D" "/Volumes/Photos auto_photos"
write_file_as_root "$AUTO_MAP" "Photos -fstype=smbfs ://${NAS_USER}:${NAS_USERPASS}@${NAS_HOST}/${NAS_SHARE}"

echo "Reloading autofs maps"
run_sudo_cmd automount -cv

echo "All done. SMB share will auto-mount at $MOUNT_POINT on access."
