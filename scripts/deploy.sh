#!/bin/bash
# Full stack deploy: create network → postgres → nexus → nginx
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_DIR="$ROOT_DIR/docker-compose"

log() { echo "[deploy] $*"; }

# Optional flags
DEPLOY_RUSTFS="${DEPLOY_RUSTFS:-false}"
DEPLOY_BACKUP="${DEPLOY_BACKUP:-false}"

# 1. Secrets must exist
if [[ ! -f "$ROOT_DIR/secrets/pg_password.txt" ]]; then
  echo "[deploy] ERROR: secrets not generated. Run: ./scripts/generate-secrets.sh"
  exit 1
fi

# 2. Create data directories on /data/nexus (bind mounts)
DATA_BASE="${DATA_BASE:-/data/nexus}"
log "Creating data directories under $DATA_BASE ..."
mkdir -p \
  "$DATA_BASE/postgres" \
  "$DATA_BASE/nexus-data" \
  "$DATA_BASE/rustfs" \
  "$DATA_BASE/backups"
# Nexus runs as uid 200
chown -R 200:200 "$DATA_BASE/nexus-data" 2>/dev/null || true

# 3. Create shared network if missing
if ! docker network inspect nexus_infra_net >/dev/null 2>&1; then
  log "Creating nexus_infra_net network..."
  docker network create \
    --driver bridge \
    --opt com.docker.network.bridge.name=br-nexus \
    nexus_infra_net
else
  log "Network nexus_infra_net already exists"
fi

# 4. Start postgres first
log "Starting PostgreSQL..."
docker-compose -f "$COMPOSE_DIR/postgres/docker-compose.yml" up -d --pull never --no-build

log "Waiting for PostgreSQL to be healthy..."
for i in $(seq 1 30); do
  status=$(docker inspect --format='{{.State.Health.Status}}' nexus_postgres 2>/dev/null || echo "starting")
  if [[ "$status" == "healthy" ]]; then
    log "PostgreSQL is healthy"
    break
  fi
  echo "  attempt $i/30 — status: $status"
  sleep 5
done

# 5. Start nexus
log "Starting Nexus..."
docker-compose -f "$COMPOSE_DIR/nexus/docker-compose.yml" up -d --pull never --no-build

log "Waiting for Nexus to be healthy (this takes ~2 minutes on first boot)..."
for i in $(seq 1 40); do
  status=$(docker inspect --format='{{.State.Health.Status}}' nexus_app 2>/dev/null || echo "starting")
  if [[ "$status" == "healthy" ]]; then
    log "Nexus is healthy"
    break
  fi
  echo "  attempt $i/40 — status: $status"
  sleep 10
done

# 6. Start nginx
log "Starting Nginx..."
docker-compose -f "$COMPOSE_DIR/nginx/docker-compose.yml" up -d --pull never --no-build

# 7. Optional: RustFS
if [[ "$DEPLOY_RUSTFS" == "true" ]]; then
  if [[ ! -f "$ROOT_DIR/secrets/rustfs_password.txt" ]]; then
    log "ERROR: rustfs secrets missing. Run: ./scripts/generate-secrets.sh"
    exit 1
  fi
  log "Starting RustFS..."
  docker-compose -f "$COMPOSE_DIR/rustfs/docker-compose.yml" up -d --pull never --no-build
  log "RustFS console: http://localhost:9001"
fi

# 8. Optional: Backup cron
if [[ "$DEPLOY_BACKUP" == "true" ]]; then
  log "Starting backup cron..."
  docker-compose -f "$COMPOSE_DIR/backup/docker-compose.yml" up -d --pull never --no-build
fi

log ""
log "Stack is up. Access Nexus at: https://localhost"
log "Default admin password is in: docker exec nexus_app cat /nexus-data/admin.password"
log ""
log "To also start RustFS + backup cron:"
log "  DEPLOY_RUSTFS=true DEPLOY_BACKUP=true ./scripts/deploy.sh"
