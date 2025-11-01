#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." &>/dev/null && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi
LABEL="com.user.tailscale-cert"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
SCRIPT="$REPO_ROOT/scripts/renew_tailscale_cert.sh"
LOG="$HOME/Library/Logs/tailscale-cert.log"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>                
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SCRIPT</string>
  </array>
  <key>RunAtLoad</key>            <true/>
  <key>KeepAlive</key>            <true/>
  <key>StandardOutPath</key>      <string>$LOG</string>
  <key>StandardErrorPath</key>    <string>$LOG</string>
  <key>StartInterval</key>        <integer>600</integer>
</dict>
</plist>
PLIST

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
launchctl start ${LABEL}

echo "LaunchAgent installed: $PLIST"
echo "Logs: $LOG"
