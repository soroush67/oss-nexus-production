#!/bin/bash
# Migrate all service data from docker volumes to /data/nexus bind mounts
# Run this ONCE on the remote server after updating docker-compose files
set -euo pipefail

DATA_BASE="${DATA_BASE:-/data/nexus}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

log()  { echo "[migrate] $*"; }
step() { echo ""; echo "===== $* ====="; }

step "1. Stop all running services"
docker-compose -f "$PROJECT_DIR/docker-compose/backup/docker-compose.yml"  down 2>/dev/null || true
docker-compose -f "$PROJECT_DIR/docker-compose/rustfs/docker-compose.yml"  down 2>/dev/null || true
docker-compose -f "$PROJECT_DIR/docker-compose/nginx/docker-compose.yml"   down 2>/dev/null || true
docker-compose -f "$PROJECT_DIR/docker-compose/nexus/docker-compose.yml"   down 2>/dev/null || true
docker-compose -f "$PROJECT_DIR/docker-compose/postgres/docker-compose.yml" down 2>/dev/null || true
log "All services stopped"

step "2. Create target directories on $DATA_BASE"
mkdir -p \
  "$DATA_BASE/postgres" \
  "$DATA_BASE/nexus-data" \
  "$DATA_BASE/rustfs" \
  "$DATA_BASE/backups"
log "Directories created"

step "3. Migrate PostgreSQL data"
PG_VOL=$(docker volume inspect postgres_postgres_data --format '{{.Mountpoint}}' 2>/dev/null || true)
if [[ -n "$PG_VOL" && -d "$PG_VOL" ]]; then
  log "Copying PostgreSQL data from $PG_VOL ..."
  cp -a "$PG_VOL/." "$DATA_BASE/postgres/"
  log "PostgreSQL data migrated ($(du -sh "$DATA_BASE/postgres" | cut -f1))"
else
  log "No existing postgres volume found — will start fresh"
fi

step "4. Migrate Nexus data"
NEXUS_VOL=$(docker volume inspect nexus_nexus_data --format '{{.Mountpoint}}' 2>/dev/null || true)
if [[ -n "$NEXUS_VOL" && -d "$NEXUS_VOL" ]]; then
  log "Copying Nexus data from $NEXUS_VOL ..."
  cp -a "$NEXUS_VOL/." "$DATA_BASE/nexus-data/"
  chown -R 200:200 "$DATA_BASE/nexus-data"
  log "Nexus data migrated ($(du -sh "$DATA_BASE/nexus-data" | cut -f1))"
else
  log "No existing nexus_data volume found — will start fresh"
  chown -R 200:200 "$DATA_BASE/nexus-data"
fi

step "5. Migrate RustFS data"
RUSTFS_VOL=$(docker volume inspect rustfs_rustfs_data --format '{{.Mountpoint}}' 2>/dev/null || true)
if [[ -n "$RUSTFS_VOL" && -d "$RUSTFS_VOL" ]]; then
  log "Copying RustFS data from $RUSTFS_VOL ..."
  cp -a "$RUSTFS_VOL/." "$DATA_BASE/rustfs/"
  log "RustFS data migrated ($(du -sh "$DATA_BASE/rustfs" | cut -f1))"
else
  log "No existing rustfs volume found — will start fresh"
fi

step "6. Start services with new bind mounts"
bash "$PROJECT_DIR/scripts/deploy.sh"

step "7. Remove old docker volumes (optional cleanup)"
log "Old volumes still exist. Remove manually if migration looks good:"
log "  docker volume rm postgres_postgres_data nexus_nexus_data rustfs_rustfs_data"

log ""
log "Migration complete! Data is now on $DATA_BASE"
log "  Postgres:   $DATA_BASE/postgres"
log "  Nexus data: $DATA_BASE/nexus-data"
log "  RustFS:     $DATA_BASE/rustfs"
log "  Backups:    $DATA_BASE/backups"
