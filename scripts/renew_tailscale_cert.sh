#!/bin/bash
set -Eeuo pipefail

# Resolve paths
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." &>/dev/null && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
COMPOSE_FILE="${REPO_ROOT}/compose/caddy.yml"

# Load .env
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
else
  echo "WARN: .env not found at $ENV_FILE; TS_NODE is required (e.g., macmini.tailnet.ts.net)"
  exit 1
fi

# Required settings (with sane defaults where possible)
: "${CADDY_CERTS_DIR:="$HOME/caddy/certs"}"
: "${CADDY_CONTAINER_NAME:="caddy"}"

mkdir -p "$CADDY_CERTS_DIR"

# Generate/renew the Tailscale certs for the host
echo "Generating Tailscale certs for ${TS_NODE} ..."
tailscale cert "$TS_NODE"

# Move certs into the host certs dir (mounted read-only into the container)
mv -f "${TS_NODE}.crt" "${CADDY_CERTS_DIR}/${TS_NODE}.crt"
mv -f "${TS_NODE}.key" "${CADDY_CERTS_DIR}/${TS_NODE}.key"
echo "Certs written to: ${CADDY_CERTS_DIR}"

# If the Caddy service is up via Compose, ask it to reload the config/certs
if docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps --status running 2>/dev/null | grep -q "$CADDY_CONTAINER_NAME"; then
  echo "Reloading Caddy via Docker Compose ..."
  # Either send SIGHUP or use caddy reload; both work. Using reload here:
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T "$CADDY_CONTAINER_NAME" caddy reload --config /etc/caddy/Caddyfile || \
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" kill -s SIGHUP "$CADDY_CONTAINER_NAME" || true
else
  echo "NOTE: Caddy not running via compose ($COMPOSE_FILE) — skipping reload"
fi

echo "Done."
