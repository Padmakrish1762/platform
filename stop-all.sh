#!/usr/bin/env bash
# ==============================================================================
# CREDEBL One-Shot Stop Script
# Cleanly terminates all Platform Microservices, Studio UI & Containers
# ==============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${REPO_ROOT}/logs"
PID_FILE="${LOG_DIR}/credebl.pids"

echo "======================================================"
echo " Stopping CREDEBL Services..."
echo "======================================================"

# 1. Stop Node Microservices
echo "▶ Stopping Platform Microservices..."
SERVICES=(
  "api-gateway"
  "user"
  "organization"
  "geo-location"
  "connection"
  "issuance"
  "verification"
  "utility"
  "ecosystem"
  "notification"
  "webhook"
  "cloud-wallet"
  "agent-service"
  "agent-provisioning"
  "ledger"
  "oid4vc-verification"
  "oid4vc-issuance"
  "x509"
)

for svc in "${SERVICES[@]}"; do
  pkill -f "dist/apps/${svc}/main.js" 2>/dev/null || true
done
pkill -f "port-forward-8002.js" 2>/dev/null || true

# 2. Stop Studio Frontend
echo "▶ Stopping Studio UI..."
pkill -f "next-server" 2>/dev/null || true
pkill -f "next dev" 2>/dev/null || true
pkill -f "pnpm run dev" 2>/dev/null || true

# 3. Stop Docker Containers (Agent Controller & Schema File Server)
echo "▶ Stopping Agent & Schema Containers..."
docker stop schema-file-server 2>/dev/null || true

for container in $(docker ps -q --filter "name=Platform-admin"); do
  docker stop "$container" 2>/dev/null || true
done

# Optional: Stop infrastructure if passed '--all' argument
if [ "${1:-}" = "--all" ]; then
  echo "▶ Stopping Infrastructure Containers (PostgreSQL, Redis, NATS, Keycloak)..."
  docker stop credebl-postgres platform-redis-1 nats credebl-keycloak 2>/dev/null || true
fi

if [ -f "${PID_FILE}" ]; then
  rm -f "${PID_FILE}"
fi

echo "======================================================"
echo " CREDEBL microservices and UI stopped."
echo " (Infrastructure DB/Redis/NATS/Keycloak kept running."
echo "  To stop everything including DB, pass: ./stop-all.sh --all)"
echo "======================================================"
