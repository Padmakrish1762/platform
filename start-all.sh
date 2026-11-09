#!/usr/bin/env bash
# ==============================================================================
# CREDEBL One-Shot Startup Script
# Starts Infrastructure, Docker Containers, 17 NestJS Microservices & Studio UI
#
# Assumes this repo (platform) and studio are cloned as SIBLING directories,
# e.g.:
#   ~/credebl/platform   <- this repo, run ./start-all.sh from here
#   ~/credebl/studio
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${REPO_ROOT}/logs"
PID_FILE="${LOG_DIR}/credebl.pids"
PLATFORM_DIR="${REPO_ROOT}"
STUDIO_DIR="${REPO_ROOT}/../studio"

mkdir -p "${LOG_DIR}"
touch "${PID_FILE}"

echo "======================================================"
echo " Starting CREDEBL Services..."
echo " Root directory: ${REPO_ROOT}"
echo " Logs directory: ${LOG_DIR}"
echo "======================================================"

# Helper function to check if a port is listening
is_port_listening() {
  local port=$1
  if command -v ss >/dev/null 2>&1; then
    ss -tlpn 2>/dev/null | grep -q ":${port} "
  elif command -v lsof >/dev/null 2>&1; then
    lsof -i ":${port}" >/dev/null 2>&1
  else
    nc -z 127.0.0.1 "${port}" >/dev/null 2>&1
  fi
}

# --- Step 1: Core Infrastructure ---
echo "[1/4] Checking Infrastructure Services..."

# PostgreSQL (5432)
if is_port_listening 5432; then
  echo "  ✔ PostgreSQL is already running on port 5432."
else
  echo "  ▶ Starting PostgreSQL (5432)..."
  if docker ps -a --format '{{.Names}}' | grep -q "^credebl-postgres$"; then
    docker start credebl-postgres >/dev/null 2>&1
  else
    echo "  ⚠ PostgreSQL container 'credebl-postgres' not found; starting via Docker run..."
    docker run -d --name credebl-postgres -p 5432:5432 -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=credebl postgres:16
  fi
fi

# Redis (6379)
if is_port_listening 6379; then
  echo "  ✔ Redis is already running on port 6379."
else
  echo "  ▶ Starting Redis (6379)..."
  if docker ps -a --format '{{.Names}}' | grep -q "^platform-redis-1$"; then
    docker start platform-redis-1 >/dev/null 2>&1
  else
    docker run -d --name platform-redis-1 -p 6379:6379 redis:8.10-alpine
  fi
fi

# NATS (4222)
if is_port_listening 4222; then
  echo "  ✔ NATS Message Broker is already running on port 4222."
else
  echo "  ▶ Starting NATS (4222)..."
  if docker ps -a --format '{{.Names}}' | grep -q "^nats$"; then
    docker start nats >/dev/null 2>&1
  else
    docker run -d --name nats -p 4222:4222 -p 8222:8222 -p 6222:6222 nats:latest
  fi
fi

# Keycloak (8080)
BOOTSTRAP_MARKER="${PLATFORM_DIR}/.credebl-bootstrap-done"

if is_port_listening 8080; then
  echo "  ✔ Keycloak is already running on port 8080."
elif [ ! -f "${BOOTSTRAP_MARKER}" ]; then
  # Truly fresh machine: no realm, no clients, no seeded database yet.
  # first-run-bootstrap.sh starts Keycloak itself as part of provisioning
  # it (realm/clients via Terraform, then prisma migrate+seed) - this only
  # ever runs once per machine, gated by the marker file it writes on success.
  echo "  ▶ First run detected — bootstrapping Keycloak realm and database (one-time, can take a few minutes)..."
  bash "${REPO_ROOT}/local-setup/first-run-bootstrap.sh"
elif docker ps -a --format '{{.Names}}' | grep -q "^credebl-keycloak$"; then
  echo "  ▶ Starting Keycloak (8080)..."
  docker start credebl-keycloak >/dev/null 2>&1
else
  echo "  ⚠ Bootstrap marker found but no Keycloak container exists — re-running bootstrap..."
  rm -f "${BOOTSTRAP_MARKER}"
  bash "${REPO_ROOT}/local-setup/first-run-bootstrap.sh"
fi

# --- Step 2: Docker Containers ---
echo "[2/4] Checking Docker Containers..."

# Schema File Server (4000)
if is_port_listening 4000; then
  echo "  ✔ Schema File Server is already running on port 4000."
else
  echo "  ▶ Starting Schema File Server container..."
  docker start schema-file-server 2>/dev/null || \
  docker run -d --name schema-file-server -p 4000:4000 \
    -v "${PLATFORM_DIR}/apps/schemas:/app/schemas" \
    ghcr.io/credebl/schema-file-server:latest 2>&1 | tee -a "${LOG_DIR}/docker-schema.log"
fi

# Credo Agent Controller (8001 / 8002 / 9001 / 9002)
if is_port_listening 9001 || is_port_listening 9002; then
  echo "  ✔ Credo Controller Agent is already running."
else
  AGENT_NAME=$(docker ps -a --filter "name=Platform-admin" --format "{{.Names}}" | head -n1)
  if [ -n "${AGENT_NAME}" ]; then
    echo "  ▶ Starting Credo Agent container (${AGENT_NAME})..."
    docker start "${AGENT_NAME}" >/dev/null 2>&1 || true
  else
    echo "  ℹ No existing Credo Agent container found (will be provisioned on first use)."
  fi
fi

# Make sure pnpm is available before we try to use it below (fresh
# machines that only have Node won't have it yet; corepack ships with
# modern Node and can fetch it without a separate manual install step).
ensure_pnpm() {
  if command -v pnpm >/dev/null 2>&1; then
    return 0
  fi
  echo "  ℹ pnpm not found — bootstrapping it via corepack..."
  if command -v corepack >/dev/null 2>&1; then
    corepack enable >/dev/null 2>&1 || true
    corepack prepare pnpm@latest --activate >/dev/null 2>&1 || true
  fi
  if ! command -v pnpm >/dev/null 2>&1; then
    echo "  ⚠ Could not install pnpm automatically. Install it yourself (npm install -g pnpm) and re-run this script."
    return 1
  fi
}

# --- Step 3: Platform Microservices ---
echo "[3/4] Launching Platform Microservices..."
cd "${PLATFORM_DIR}"

if [ ! -d "${PLATFORM_DIR}/node_modules" ]; then
  if ensure_pnpm; then
    echo "  ▶ Installing platform dependencies (first run only, this can take a few minutes)..."
    if pnpm install > "${LOG_DIR}/platform-install.log" 2>&1; then
      echo "  ✔ Platform dependencies installed."
    else
      echo "  ⚠ pnpm install failed — see ${LOG_DIR}/platform-install.log for details:"
      tail -n 20 "${LOG_DIR}/platform-install.log"
    fi
  fi
fi

if [ ! -d "${PLATFORM_DIR}/dist/apps/api-gateway" ]; then
  echo "  ⚠ Platform microservices are not built in ${PLATFORM_DIR}/dist."
  echo "  Run 'npx nest build <service-name>' for each service listed below, or rebuild from source."
fi

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
  "oid4vc-issuance"
  "oid4vc-verification"
)

for svc in "${SERVICES[@]}"; do
  # Check if service is already running
  if pgrep -f "node.*dist/apps/${svc}/main.js" >/dev/null 2>&1; then
    echo "  ✔ ${svc} is already running."
  elif [ -f "${PLATFORM_DIR}/dist/apps/${svc}/main.js" ]; then
    echo "  ▶ Starting ${svc}..."
    setsid node "dist/apps/${svc}/main.js" > "${LOG_DIR}/${svc}.log" 2>&1 &
    pid=$!
    echo "${svc}:${pid}" >> "${PID_FILE}"
  else
    echo "  ⚠ ${svc} build output not found at dist/apps/${svc}/main.js"
  fi
done

# --- Step 4: Studio UI ---
echo "[4/4] Checking Studio Frontend UI..."
if is_port_listening 3001; then
  echo "  ✔ Studio UI is already running on port 3001."
elif [ ! -d "${STUDIO_DIR}" ]; then
  echo "  ⚠ Studio repo not found at ${STUDIO_DIR} — clone it as a sibling of this repo to run Studio too."
else
  cd "${STUDIO_DIR}"
  if [ ! -d "${STUDIO_DIR}/node_modules" ]; then
    if ensure_pnpm; then
      echo "  ▶ Installing Studio dependencies (first run only, this can take a few minutes)..."
      if pnpm install > "${LOG_DIR}/studio-install.log" 2>&1; then
        echo "  ✔ Studio dependencies installed."
      else
        echo "  ⚠ pnpm install failed — see ${LOG_DIR}/studio-install.log for details:"
        tail -n 20 "${LOG_DIR}/studio-install.log"
      fi
    fi
  fi
  if [ -d "${STUDIO_DIR}/node_modules" ]; then
    echo "  ▶ Starting Studio UI on port 3001..."
    PORT=3001 setsid pnpm run dev > "${LOG_DIR}/studio.log" 2>&1 &
    pid=$!
    echo "studio:${pid}" >> "${PID_FILE}"
  else
    echo "  ⚠ Studio dependencies still missing in ${STUDIO_DIR}/node_modules — install pnpm and re-run this script."
  fi
fi

echo "======================================================"
echo " CREDEBL service initialization complete!"
echo " - Studio UI:     http://localhost:3001"
echo " - API Gateway:   http://localhost:5000"
echo " - Keycloak:      http://localhost:8080"
echo " - Schema Server: http://localhost:4000"
echo " Logs are streamable under: ${LOG_DIR}/*.log"
echo " To stop services: ./stop-all.sh"
echo "======================================================"
