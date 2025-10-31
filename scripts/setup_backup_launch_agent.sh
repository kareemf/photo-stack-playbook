#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_SCRIPT="$PROJECT_ROOT/scripts/backup_photo_dbs.sh"
LABEL_DEFAULT="com.user.photo-backup-dbs"

DRY_RUN=0
LABEL="$LABEL_DEFAULT"
WEEKDAY=7
HOUR=3

usage() {
  cat <<'USAGE'
Usage: setup_backup_launch_agent.sh [options]
  --label VALUE      Override launch agent label (default: com.user.photo-backup-dbs)
  --weekday N        Day of week for StartCalendarInterval (1=Sunday, default: 7)
  --hour N           Hour (0-23) for StartCalendarInterval (default: 3)
  --dry-run          Show actions without writing files
  -h, --help         Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)
      LABEL="$2"
      shift 2
      ;;
    --weekday)
      WEEKDAY="$2"
      shift 2
      ;;
    --hour)
      HOUR="$2"
      shift 2
      ;;
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

if [ ! -x "$BACKUP_SCRIPT" ]; then
  echo "Backup script not executable: $BACKUP_SCRIPT" >&2
  echo "Run: chmod +x \"$BACKUP_SCRIPT\"" >&2
  exit 1
fi

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs"
PLIST_PATH="$LAUNCH_AGENTS_DIR/${LABEL}.plist"
LOG_BASE="photo-backup-dbs"
STDOUT_LOG="$LOG_DIR/${LOG_BASE}.log"
STDERR_LOG="$LOG_DIR/${LOG_BASE}-error.log"

if ! [[ "$WEEKDAY" =~ ^[1-7]$ ]]; then
  echo "Weekday must be between 1 and 7." >&2
  exit 1
fi

if ! [[ "$HOUR" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then
  echo "Hour must be between 0 and 23." >&2
  exit 1
fi

run_cmd mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR"

PLIST_CONTENT=$(cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BACKUP_SCRIPT}</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key><integer>${WEEKDAY}</integer>
    <key>Hour</key><integer>${HOUR}</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>${STDOUT_LOG}</string>
  <key>StandardErrorPath</key>
  <string>${STDERR_LOG}</string>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
)

if [ "$DRY_RUN" -eq 1 ]; then
  printf '[dry-run] write %s with:\n%s\n' "$PLIST_PATH" "$PLIST_CONTENT"
else
  printf '%s\n' "$PLIST_CONTENT" > "$PLIST_PATH"
  echo "Launch agent written to $PLIST_PATH"
  echo "Load with: launchctl load \"$PLIST_PATH\""
fi
