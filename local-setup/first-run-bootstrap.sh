#!/usr/bin/env bash
# ==============================================================================
# CREDEBL First-Run Bootstrap
# Provisions the Keycloak realm/clients (via Terraform) and seeds the platform
# database. Needed exactly once per machine before start-all.sh can bring the
# platform up from a truly empty state (fresh clone, no prior Postgres/Keycloak
# data). Idempotent: safe to re-run, and start-all.sh skips calling it at all
# once it has succeeded before.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLATFORM_DIR="${REPO_ROOT}"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform-script/keycloak"
LOG_DIR="${REPO_ROOT}/logs"
MARKER_FILE="${PLATFORM_DIR}/.credebl-bootstrap-done"

mkdir -p "${LOG_DIR}"

log() { echo "  ▶ $*"; }
ok()  { echo "  ✔ $*"; }
warn() { echo "  ⚠ $*"; }
fail() { echo "  ✘ $*"; exit 1; }

if [ -f "${MARKER_FILE}" ]; then
  ok "First-run bootstrap already completed on $(cat "${MARKER_FILE}")."
  exit 0
fi

echo "======================================================"
echo " CREDEBL First-Run Bootstrap"
echo " (one-time: Keycloak realm + database seed)"
echo "======================================================"

# --- OS detection ---
if [ "$(uname)" = "Darwin" ]; then
  OS_ID="Darwin"
elif [ -f /etc/os-release ]; then
  OS_ID=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
else
  OS_ID=$(uname -s)
fi
log "Detected OS: ${OS_ID}"

sed_inplace() {
  if [ "${OS_ID}" = "Darwin" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# --- Step 1: Docker must already be present - never auto-installed here. ---
if ! command -v docker >/dev/null 2>&1; then
  fail "Docker is required and not found. Install Docker Desktop (macOS) or Docker Engine (Linux), then re-run."
fi
if ! docker info >/dev/null 2>&1; then
  fail "Docker is installed but not running. Start Docker Desktop / the Docker daemon, then re-run."
fi
ok "Docker is available."

# --- Step 2: Terraform (auto-installed) ---
ensure_terraform() {
  if command -v terraform >/dev/null 2>&1; then
    ok "Terraform is already installed."
    return 0
  fi
  log "Terraform not found - installing..."
  case "${OS_ID}" in
    Darwin)
      if ! command -v brew >/dev/null 2>&1; then
        fail "Homebrew is required to install Terraform on macOS. Install it from https://brew.sh, then re-run."
      fi
      brew tap hashicorp/tap >/dev/null
      brew install hashicorp/tap/terraform
      ;;
    ubuntu|debian)
      sudo apt-get update
      sudo apt-get install -y gnupg software-properties-common wget
      wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
      echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
      sudo apt-get update
      sudo apt-get install -y terraform
      ;;
    *)
      fail "Don't know how to install Terraform automatically on '${OS_ID}'. Install it yourself (https://developer.hashicorp.com/terraform/install), then re-run."
      ;;
  esac
  command -v terraform >/dev/null 2>&1 || fail "Terraform installation did not succeed."
  ok "Terraform installed."
}
ensure_terraform

# --- Step 3: PostgreSQL must be up (start-all.sh starts it before calling this) ---
if ! docker ps --format '{{.Names}}' | grep -q '^credebl-postgres$'; then
  fail "credebl-postgres container isn't running - start-all.sh should have started it first."
fi

log "Waiting for PostgreSQL to accept connections..."
for _ in $(seq 1 30); do
  if docker exec credebl-postgres pg_isready -U postgres >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
docker exec credebl-postgres pg_isready -U postgres >/dev/null 2>&1 || fail "PostgreSQL never became ready."
ok "PostgreSQL is ready."

# --- Step 4: Create the keycloak database (idempotent) ---
if docker exec credebl-postgres psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='keycloak'" | grep -q 1; then
  ok "'keycloak' database already exists."
else
  log "Creating 'keycloak' database..."
  docker exec credebl-postgres psql -U postgres -c "CREATE DATABASE keycloak;" || fail "Could not create the keycloak database."
  ok "'keycloak' database created."
fi

# --- Step 5: Start Keycloak, pointed at Postgres by its live container IP ---
POSTGRES_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' credebl-postgres)
[ -n "${POSTGRES_IP}" ] || fail "Could not determine credebl-postgres's container IP."

if docker ps --format '{{.Names}}' | grep -q '^credebl-keycloak$'; then
  ok "Keycloak container already running."
elif docker ps -a --format '{{.Names}}' | grep -q '^credebl-keycloak$'; then
  log "Starting existing Keycloak container..."
  docker start credebl-keycloak >/dev/null
else
  log "Creating Keycloak container (DB at ${POSTGRES_IP}:5432)..."
  docker run -d --name credebl-keycloak -p 8080:8080 \
    -e KEYCLOAK_ADMIN=admin \
    -e KEYCLOAK_ADMIN_PASSWORD=admin \
    -e KC_HTTP_ENABLED=true \
    -e KC_DB=postgres \
    -e "KC_DB_URL=jdbc:postgresql://${POSTGRES_IP}:5432/keycloak" \
    -e KC_DB_USERNAME=postgres \
    -e KC_DB_PASSWORD=postgres \
    -e KC_HOSTNAME_STRICT=false \
    -e KC_HOSTNAME_STRICT_HTTPS=false \
    -e KC_PROXY=edge \
    quay.io/keycloak/keycloak:25.0.6 start-dev >/dev/null \
    || fail "Failed to start the Keycloak container."
fi

log "Waiting for Keycloak to be ready (this can take a minute on first boot)..."
for _ in $(seq 1 60); do
  if curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/realms/master 2>/dev/null | grep -q '^200$'; then
    break
  fi
  sleep 3
done
curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/realms/master 2>/dev/null | grep -q '^200$' \
  || fail "Keycloak did not become ready in time. Check 'docker logs credebl-keycloak'."
ok "Keycloak is ready."

# --- Step 6: Terraform apply (fresh realm + clients) ---
# Any .tfstate committed to the repo belongs to the machine that created it,
# not this one - wipe it so terraform treats this as a real first-time apply.
cd "${TERRAFORM_DIR}"
rm -f terraform.tfstate terraform.tfstate.backup secret.env
rm -rf .terraform

log "Running terraform init..."
terraform init -input=false > "${LOG_DIR}/terraform-init.log" 2>&1 \
  || { warn "terraform init failed - see ${LOG_DIR}/terraform-init.log"; tail -n 20 "${LOG_DIR}/terraform-init.log"; exit 1; }

log "Running terraform apply (creating the credebl-platform realm + clients)..."
terraform apply -input=false -auto-approve > "${LOG_DIR}/terraform-apply.log" 2>&1 \
  || { warn "terraform apply failed - see ${LOG_DIR}/terraform-apply.log"; tail -n 30 "${LOG_DIR}/terraform-apply.log"; exit 1; }

[ -f secret.env ] || fail "terraform apply succeeded but secret.env was not produced."
ok "Keycloak realm and clients provisioned."

ADMIN_CLIENT_SECRET=$(grep ADMIN_CLIENT_SECRET secret.env | cut -d '=' -f2)
CREDEBL_CLIENT_SECRET=$(grep CREDEBL_CLIENT_SECRET secret.env | cut -d '=' -f2)
[ -n "${ADMIN_CLIENT_SECRET}" ] && [ -n "${CREDEBL_CLIENT_SECRET}" ] || fail "Could not read client secrets from secret.env."

# --- Step 7: Write the fresh secrets into platform/.env ---
cd "${PLATFORM_DIR}"
sed_inplace "s|^ADMIN_KEYCLOAK_SECRET=.*|ADMIN_KEYCLOAK_SECRET=${ADMIN_CLIENT_SECRET}|" .env
sed_inplace "s|^KEYCLOAK_MANAGEMENT_CLIENT_SECRET=.*|KEYCLOAK_MANAGEMENT_CLIENT_SECRET=${CREDEBL_CLIENT_SECRET}|" .env
ok "Wrote fresh Keycloak client secrets into platform/.env."

# --- Step 8: Database schema + seed data (creates the platform admin user) ---
log "Running prisma generate / migrate / seed (this can take a minute)..."
npx prisma generate > "${LOG_DIR}/prisma-generate.log" 2>&1 || { warn "prisma generate failed - see ${LOG_DIR}/prisma-generate.log"; tail -n 20 "${LOG_DIR}/prisma-generate.log"; exit 1; }
npx prisma migrate deploy > "${LOG_DIR}/prisma-migrate.log" 2>&1 || { warn "prisma migrate deploy failed - see ${LOG_DIR}/prisma-migrate.log"; tail -n 20 "${LOG_DIR}/prisma-migrate.log"; exit 1; }
npx prisma db seed > "${LOG_DIR}/prisma-seed.log" 2>&1 || { warn "prisma db seed failed - see ${LOG_DIR}/prisma-seed.log"; tail -n 30 "${LOG_DIR}/prisma-seed.log"; exit 1; }
ok "Database schema created and seeded (platform admin user provisioned in Keycloak + Postgres)."

# --- Step 9: Set a known platform admin password ---
log "Setting a known Platform Admin password..."
KC_ADMIN_TOKEN=$(curl -s -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
  -d "client_id=admin-cli" -d "username=admin" -d "password=admin" -d "grant_type=password" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
[ -n "${KC_ADMIN_TOKEN}" ] || fail "Could not authenticate to Keycloak's admin API."

ADMIN_KC_ID=$(curl -s -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
  "http://localhost:8080/admin/realms/credebl-platform/users?email=platform.admin@yopmail.com" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -n "${ADMIN_KC_ID}" ] || fail "Could not find the seeded platform admin user in Keycloak."

curl -s -X PUT "http://localhost:8080/admin/realms/credebl-platform/users/${ADMIN_KC_ID}" \
  -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" -H "Content-Type: application/json" \
  -d '{"email":"platform.admin@yopmail.com","firstName":"CREDEBL","lastName":"Admin","enabled":true,"emailVerified":true}' >/dev/null

curl -s -X PUT "http://localhost:8080/admin/realms/credebl-platform/users/${ADMIN_KC_ID}/reset-password" \
  -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" -H "Content-Type: application/json" \
  -d '{"type":"password","value":"PlatformAdmin@123","temporary":false}' >/dev/null
ok "Platform admin login ready: platform.admin@yopmail.com / PlatformAdmin@123"

# --- Step 10: Pre-pull the agent image so first wallet setup isn't slow ---
log "Pre-pulling the credo-controller agent image..."
docker pull ghcr.io/credebl/credo-controller:latest > "${LOG_DIR}/docker-pull-agent.log" 2>&1 \
  && ok "Agent image pulled." \
  || warn "Could not pre-pull the agent image (non-fatal) - see ${LOG_DIR}/docker-pull-agent.log"

date > "${MARKER_FILE}"
echo "======================================================"
echo " Bootstrap complete. Run ./start-all.sh to bring everything up."
echo "======================================================"
