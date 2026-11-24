#!/bin/bash
# Graceful shutdown: nginx → nexus → postgres
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_DIR="$ROOT_DIR/docker-compose"

log() { echo "[down] $*"; }

log "Stopping nginx..."
docker compose -f "$COMPOSE_DIR/nginx/docker-compose.yml" down

log "Stopping nexus..."
docker compose -f "$COMPOSE_DIR/nexus/docker-compose.yml" down

log "Stopping postgres..."
docker compose -f "$COMPOSE_DIR/postgres/docker-compose.yml" down

log "Stack stopped. Volumes are preserved."
