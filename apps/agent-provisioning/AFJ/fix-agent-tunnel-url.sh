#!/usr/bin/env bash
# Point an already-provisioned org's agent container at a public tunnel URL
# by patching its docker-compose file's APP_URL/AGENT_HTTP_URL and
# recreating the container via that same compose file - this preserves the
# image, env_file, restart policy, and every other compose-managed setting.
#
# (An earlier version of this script reconstructed the container with a raw
# `docker run`, which silently dropped the env_file (agent.env) entirely -
# losing RPC_URL, contract addresses, NODE_ENV, trust list config, etc - and
# hardcoded the stale ghcr.io/credebl/credo-controller:latest image instead
# of whatever locally-built image the org's compose file actually
# references. Don't go back to that approach.)
#
# Usage:
#   ./fix-agent-tunnel-url.sh <org-id> <org-name> <tunnel-host-or-url>
#
# Example:
#   ./fix-agent-tunnel-url.sh ecfe1ca9-e9b6-4808-a81f-0b68a5b7c424 testlabel \
#     7wkh080x-8018.inc1.devtunnels.ms
#
# <org-name> must match the container name exactly (same string Studio used
# when it created the container - check with: docker ps -a | grep <org-id>).

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <org-id> <org-name> <tunnel-host-or-url>"
  exit 1
fi

ORG_ID="$1"
ORG_NAME="$2"
TUNNEL_INPUT="$3"

# APP_URL wants a bare host - cliAgent.ts does `https://${APP_URL}/oid4vci`
# itself (only reached when NODE_ENV=PROD). AGENT_HTTP_URL wants the full
# https:// URL - it's used as-is in the NODE_ENV!=PROD path, which is what
# every local container here actually runs as (NODE_ENV=DEV via agent.env).
TUNNEL_HOST="${TUNNEL_INPUT#https://}"
TUNNEL_HOST="${TUNNEL_HOST#http://}"
TUNNEL_HOST="${TUNNEL_HOST%/}"
TUNNEL_URL="https://${TUNNEL_HOST}"

CONTAINER="${ORG_ID}_${ORG_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose_${CONTAINER}.yaml"

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Expected compose file not found: $COMPOSE_FILE"
  echo "Check the exact name with: ls ${SCRIPT_DIR}/docker-compose_${ORG_ID}_*.yaml"
  exit 1
fi

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "No container named '$CONTAINER' exists."
  echo "Check the exact name with: docker ps -a | grep ${ORG_ID}"
  exit 1
fi

echo "Container:      $CONTAINER"
echo "Compose file:   $COMPOSE_FILE"
echo "APP_URL:        $TUNNEL_HOST"
echo "AGENT_HTTP_URL: $TUNNEL_URL"
echo

# Patch the two self-reference env vars in place. Every compose file
# start_agent.sh generates has these as plain `KEY: value` lines under
# `environment:`, so a line-anchored substitution is safe here and leaves
# the image, ports, volumes, env_file, and restart policy untouched.
sed -i \
  -e "s|^\( *APP_URL: \).*|\1${TUNNEL_HOST}|" \
  -e "s|^\( *AGENT_HTTP_URL: \).*|\1${TUNNEL_URL}|" \
  "$COMPOSE_FILE"

docker stop "$CONTAINER"
docker rm "$CONTAINER"
docker compose -f "$COMPOSE_FILE" up -d

echo
echo "Done. Verifying..."
sleep 5
docker ps --filter "name=${CONTAINER}" --format "table {{.Names}}\t{{.Status}}"
docker inspect "$CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -E "APP_URL|AGENT_HTTP_URL"
