#!/bin/bash
# backup_photo_dbs.sh
# Backs up Immich (PostgreSQL) and PhotoPrism (MariaDB) databases to NAS.
# - Auto-loads project .env (from repo root)
# - Writes logs to ~/Library/Logs/photo-backup-dbs.log
# - Compresses dumps (.sql.gz)
# - Keeps simple retention

set -Eeuo pipefail

############################
# Config & Defaults
############################
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." &>/dev/null && pwd)"

LOG_FILE="${PHOTO_BACKUP_LOG:-$HOME/Library/Logs/photo-backup-dbs.log}"
ENV_FILE="${PHOTO_STACK_ENV_FILE:-$PROJECT_ROOT/.env}"

# Override via .env (if present), otherwise these sane defaults apply.
BACKUP_DIR_DEFAULT="/Volumes/Photos/backups"
BACKUP_DIR="${BACKUP_DIR:-$BACKUP_DIR_DEFAULT}"

# Container names (override in .env if yours differ)
IMMICH_DB_CONT="${IMMICH_DB_CONT:-immich-db}"
PHOTOPRISM_DB_CONT="${PHOTOPRISM_DB_CONT:-photoprism-db}"

# DB creds / names (from .env or defaults)
IMMICH_DB_USER="${IMMICH_DB_USER:-immich}"
IMMICH_DB_NAME="${IMMICH_DB_NAME:-immich}"

PHOTOPRISM_DB_USER="${PHOTOPRISM_DB_USER:-photoprism}"
PHOTOPRISM_DB_NAME="${PHOTOPRISM_DB_NAME:-photoprism}"
# PHOTOPRISM_DB_PASS is expected from .env (required for mysqldump)

# Retention (days)
RETENTION_DAYS="${RETENTION_DAYS:-14}"

DATE="$(date +%F_%H%M%S)"
OUT_DIR_IM="$BACKUP_DIR/immich"
OUT_DIR_PP="$BACKUP_DIR/photoprism"

############################
# Helpers
############################
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE" ; }
need() { command -v "$1" >/dev/null 2>&1 || { log "ERROR: required command not found: $1"; exit 1; }; }

cleanup_on_error() {
  local code=$?
  log "ERROR: backup failed (exit $code)"
  exit "$code"
}
trap cleanup_on_error ERR

############################
# Preflight
############################
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE" || { echo "Cannot write log $LOG_FILE"; exit 1; }

# Load .env if present
if [[ -f "$ENV_FILE" ]]; then
  # export all variables read from .env
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  log "Loaded env from $ENV_FILE"
else
  log "NOTE: No .env found at $ENV_FILE (continuing with defaults / current env)"
fi

# Re-evaluate after env load (allows overriding defaults in .env)
BACKUP_DIR="${BACKUP_DIR:-$BACKUP_DIR_DEFAULT}"
OUT_DIR_IM="$BACKUP_DIR/immich"
OUT_DIR_PP="$BACKUP_DIR/photoprism"

# Validate tools
need docker
need gzip
need tar

# Validate backup target
if [[ ! -d "$BACKUP_DIR" ]]; then
  log "ERROR: Backup dir not found: $BACKUP_DIR (is NAS mounted?)"
  exit 1
fi
mkdir -p "$OUT_DIR_IM" "$OUT_DIR_PP"

log "=== Photo DB backup started → $BACKUP_DIR ($DATE) ==="

############################
# Immich (PostgreSQL)
############################
if docker ps --format '{{.Names}}' | grep -qx "$IMMICH_DB_CONT"; then
  IM_OUT="$OUT_DIR_IM/immich_${DATE}.sql.gz"
  log "Dumping Immich DB from container '$IMMICH_DB_CONT' to $IM_OUT"
  # -i: keep stdin open, no TTY (-t) to avoid stray characters
  docker exec -i "$IMMICH_DB_CONT" pg_dump -U "$IMMICH_DB_USER" -d "$IMMICH_DB_NAME" \
    | gzip > "$IM_OUT"
  log "Immich DB backup complete: $IM_OUT"
else
  log "WARN: Immich DB container '$IMMICH_DB_CONT' not running; skipping Immich backup"
fi

############################
# PhotoPrism (MariaDB/MySQL)
############################
if docker ps --format '{{.Names}}' | grep -qx "$PHOTOPRISM_DB_CONT"; then
  : "${PHOTOPRISM_DB_PASS:?ERROR: PHOTOPRISM_DB_PASS not set (put it in .env)}"
  PP_OUT="$OUT_DIR_PP/photoprism_${DATE}.sql.gz"
  log "Dumping PhotoPrism DB from container '$PHOTOPRISM_DB_CONT' to $PP_OUT"
  docker exec -i "$PHOTOPRISM_DB_CONT" \
    mysqldump -u "$PHOTOPRISM_DB_USER" -p"$PHOTOPRISM_DB_PASS" "$PHOTOPRISM_DB_NAME" \
    | gzip > "$PP_OUT"
  log "PhotoPrism DB backup complete: $PP_OUT"
else
  log "WARN: PhotoPrism DB container '$PHOTOPRISM_DB_CONT' not running; skipping PhotoPrism backup"
fi

############################
# Compose Config Archive
############################
CONF_OUT="$BACKUP_DIR/configs_${DATE}.tgz"
log "Archiving compose configs and .env → $CONF_OUT"
# -C ensures archive paths are relative to repo root
tar -czf "$CONF_OUT" -C "$PROJECT_ROOT" compose .env 2>>"$LOG_FILE" || {
  log "WARN: Could not archive compose/.env (missing files?) — continuing"
}

############################
# Retention
############################
if [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
  log "Applying retention: ${RETENTION_DAYS} days"
  find "$OUT_DIR_IM" -type f -name '*.sql.gz' -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
  find "$OUT_DIR_PP" -type f -name '*.sql.gz' -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'configs_*.tgz' -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
fi

log "✅ Backup finished successfully"
exit 0
