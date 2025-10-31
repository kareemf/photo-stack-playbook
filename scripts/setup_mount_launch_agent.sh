#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MOUNT_SCRIPT="$PROJECT_ROOT/scripts/setup_nas_mount.sh"

DRY_RUN=0
LABEL="com.user.photo-mount"
INTERVAL=""

usage() {
  cat <<'USAGE'
Usage: setup_mount_launch_agent.sh [options]
  --label VALUE       LaunchAgent label (default: com.user.photo-mount)
  --interval SECONDS  Optional StartInterval to retry mount periodically
  --dry-run           Show actions without writing files
  -h, --help          Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)
      LABEL="$2"
      shift 2
      ;;
    --interval)
      INTERVAL="$2"
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

if [ ! -x "$MOUNT_SCRIPT" ]; then
  echo "Mount script not executable: $MOUNT_SCRIPT" >&2
  echo "Run: chmod +x \"$MOUNT_SCRIPT\"" >&2
  exit 1
fi

if [[ -n "$INTERVAL" && ! "$INTERVAL" =~ ^[0-9]+$ ]]; then
  echo "Interval must be an integer number of seconds." >&2
  exit 1
fi

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs"
PLIST_PATH="$LAUNCH_AGENTS_DIR/${LABEL}.plist"
LOG_BASE="photo-mount"
STDOUT_LOG="$LOG_DIR/${LOG_BASE}.log"
STDERR_LOG="$LOG_DIR/${LOG_BASE}-error.log"

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

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
    <string>${MOUNT_SCRIPT}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${STDOUT_LOG}</string>
  <key>StandardErrorPath</key>
  <string>${STDERR_LOG}</string>
EOF
)

if [ -n "$INTERVAL" ]; then
  PLIST_CONTENT=$(cat <<EOF
$PLIST_CONTENT  <key>StartInterval</key>
  <integer>${INTERVAL}</integer>
EOF
)
fi

PLIST_CONTENT=$(cat <<EOF
$PLIST_CONTENT</dict>
</plist>
EOF
)

if [ "$DRY_RUN" -eq 1 ]; then
  printf '[dry-run] write %s with:\n%s\n' "$PLIST_PATH" "$PLIST_CONTENT"
else
  printf '%s\n' "$PLIST_CONTENT" > "$PLIST_PATH"
  echo "Launch agent written to $PLIST_PATH"
  echo "Enable with: launchctl load \"$PLIST_PATH\""
fi
