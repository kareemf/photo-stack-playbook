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

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for credential encoding." >&2
  exit 1
fi

urlencode() {
  local value="$1"
  local safe_chars="${2:-}"
  python3 -c 'import sys, urllib.parse as p; print(p.quote(sys.argv[1], safe=sys.argv[2]))' "$value" "$safe_chars"
}

NAS_SHARE="${NAS_SHARE:-photos}"
MOUNT_POINT="${NAS_MOUNT_POINT:-/Volumes/Photos}"
FILE_MODE="${SMB_FILE_MODE:-0664}"
DIR_MODE="${SMB_DIR_MODE:-0775}"

NAS_USER_ESC="$(urlencode "$NAS_USER")"
NAS_PASS_ESC="$(urlencode "$NAS_USERPASS")"
NAS_SHARE_ESC="$(urlencode "$NAS_SHARE" "/")"
SMB_URL="//${NAS_USER_ESC}:${NAS_PASS_ESC}@${NAS_HOST}/${NAS_SHARE_ESC}"
SMB_URL_REDACTED="//${NAS_USER_ESC}:********@${NAS_HOST}/${NAS_SHARE_ESC}"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '[dry-run] mkdir -p %q\n' "$MOUNT_POINT"
else
  if ! mkdir -p "$MOUNT_POINT" 2>/dev/null; then
    echo "Failed to create mount point $MOUNT_POINT. Ensure the parent directory is writable or set NAS_MOUNT_POINT in .env." >&2
    exit 1
  fi
fi

if [ ! -w "$MOUNT_POINT" ]; then
  echo "Mount point $MOUNT_POINT is not writable by $(whoami). Adjust ownership or choose a different NAS_MOUNT_POINT." >&2
  exit 1
fi

if mount | grep -F " on ${MOUNT_POINT} (" >/dev/null; then
  echo "$MOUNT_POINT already mounted."
  exit 0
fi

echo "Mounting SMB share for immediate use..."
if [ "$DRY_RUN" -eq 1 ]; then
  printf '[dry-run] mount_smbfs -f %s -d %s %s %q\n' "${FILE_MODE}" "${DIR_MODE}" "${SMB_URL_REDACTED}" "$MOUNT_POINT"
else
  if ! mount_smbfs -f "${FILE_MODE}" -d "${DIR_MODE}" "${SMB_URL}" "$MOUNT_POINT"; then
    echo "mount_smbfs failed. Verify credentials and NAS_MOUNT_POINT." >&2
    exit 1
  fi
fi

echo "Mounted ${SMB_URL_REDACTED} at $MOUNT_POINT"
echo "Unmount with: umount \"$MOUNT_POINT\""
