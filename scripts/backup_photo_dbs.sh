#!/bin/bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

set -a
source "$PROJECT_ROOT/.env"
set +a

DATE="$(date +%F)"
BACKUP_DIR="/Volumes/Photos/backups"
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/photo-backup-dbs.log"

mkdir -p "$LOG_DIR"

if [ ! -d "$BACKUP_DIR" ]; then
  echo "NAS not mounted; exiting." >> "$LOG_FILE"
  exit 1
fi

# Immich DB → NAS
docker exec -t immich-db pg_dump -U immich -d immich > "$BACKUP_DIR/immich/immich_${DATE}.sql"

# PhotoPrism DB → NAS
docker exec -t photoprism-db mysqldump -u photoprism -p"${PHOTOPRISM_DB_PASS}" photoprism > "$BACKUP_DIR/photoprism/photoprism_${DATE}.sql"

# Compose configs + env
tar czf "$BACKUP_DIR/configs_${DATE}.tgz" -C "$PROJECT_ROOT" compose .env

echo "Backup complete at $(date)" >> "$LOG_FILE"
