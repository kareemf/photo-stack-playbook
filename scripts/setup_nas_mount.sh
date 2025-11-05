#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

DRY_RUN=0
USE_AUTOFS=0

usage() {
  cat <<'USAGE'
Usage: setup_nas_mount.sh [--dry-run] [--autofs]
  --dry-run     Show actions without making changes
  --autofs      Configure macOS autofs for the mount (requires sudo)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --autofs)
      USE_AUTOFS=1
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
  echo "Missing $ENV_FILE with NAS settings." >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

for var in NAS_HOST NAS_NFS_EXPORT; do
  if [ -z "${!var:-}" ]; then
    echo "Missing $var in $ENV_FILE." >&2
    exit 1
  fi
done

MOUNT_POINT="${NAS_MOUNT_POINT:-/Volumes/Photos}"
NFS_OPTIONS="${NFS_MOUNT_OPTIONS:-vers=3,resvport,rw,hard,intr,tcp}"
NFS_TARGET="${NAS_HOST}:${NAS_NFS_EXPORT}"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '[dry-run] mkdir -p %q\n' "$MOUNT_POINT"
else
  if ! mkdir -p "$MOUNT_POINT" 2>/dev/null; then
    echo "Failed to create mount point $MOUNT_POINT. Adjust permissions or set NAS_MOUNT_POINT." >&2
    exit 1
  fi
fi

if [ ! -w "$MOUNT_POINT" ]; then
  echo "Mount point $MOUNT_POINT is not writable by $(whoami)." >&2
  exit 1
fi

if [ "$USE_AUTOFS" -eq 1 ]; then
  AUTO_MASTER_D="/etc/auto_master.d"
  MAP_NAME="auto_photo_stack"
  MAP_FILE="/etc/${MAP_NAME}"
  MASTER_SNIPPET="${AUTO_MASTER_D}/photo-stack.autofs"
  MAP_ENTRY="${MOUNT_POINT} -fstype=nfs,${NFS_OPTIONS} ${NFS_TARGET}"

  echo "Configuring autofs (requires sudo)..."
  if [ "$DRY_RUN" -eq 1 ]; then
    cat <<EOF
[dry-run] sudo install -d ${AUTO_MASTER_D}
[dry-run] echo "${MAP_ENTRY}" | sudo tee ${MAP_FILE}
[dry-run] echo "/- ${MAP_FILE}" | sudo tee ${MASTER_SNIPPET}
[dry-run] sudo automount -cv
EOF
    exit 0
  fi

  if mount | grep -F " on ${MOUNT_POINT} (" >/dev/null; then
    echo "Unmounting current mount at $MOUNT_POINT..."
    sudo umount "$MOUNT_POINT" || {
      echo "Failed to unmount $MOUNT_POINT. Ensure it is not in use." >&2
      exit 1
    }
  fi

  if [ ! -d "$AUTO_MASTER_D" ]; then
    sudo install -d "$AUTO_MASTER_D"
  fi

  echo "$MAP_ENTRY" | sudo tee "$MAP_FILE" >/dev/null
  echo "/- $MAP_FILE" | sudo tee "$MASTER_SNIPPET" >/dev/null
  sudo automount -cv >/dev/null

  echo "autofs configured. Access $MOUNT_POINT to trigger the mount."
  ls "$MOUNT_POINT" >/dev/null 2>&1 || true
  exit 0
fi

if mount | grep -F " on ${MOUNT_POINT} (" >/dev/null; then
  echo "$MOUNT_POINT already mounted."
  exit 0
fi

echo "Mounting NFS share using NFSv3..."
if [ "$DRY_RUN" -eq 1 ]; then
  printf '[dry-run] sudo mount -t nfs -o %s %s %q\n' "$NFS_OPTIONS" "$NFS_TARGET" "$MOUNT_POINT"
  exit 0
fi

if ! sudo mount -t nfs -o "$NFS_OPTIONS" "$NFS_TARGET" "$MOUNT_POINT"; then
  echo "mount -t nfs failed. Verify NAS_NFS_EXPORT and NAS_MOUNT_POINT." >&2
  exit 1
fi

echo "Mounted ${NFS_TARGET} at $MOUNT_POINT"
echo "Unmount with: sudo umount \"$MOUNT_POINT\""
