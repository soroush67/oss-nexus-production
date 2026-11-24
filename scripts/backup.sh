#!/bin/bash
# Backup nexus_data volume + postgres dump
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$ROOT_DIR/backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}

log() { echo "[backup] $*"; }

mkdir -p "$BACKUP_DIR"

# 1. PostgreSQL dump
log "Dumping PostgreSQL..."
PG_USER=$(cat "$ROOT_DIR/secrets/pg_user.txt")
PG_PASS=$(cat "$ROOT_DIR/secrets/pg_password.txt")

docker exec nexus_postgres \
  env PGPASSWORD="$PG_PASS" \
  pg_dump -U "$PG_USER" -d nexus -Fc \
  > "$BACKUP_DIR/nexus_pg_${DATE}.dump"

log "PG dump: $BACKUP_DIR/nexus_pg_${DATE}.dump ($(du -sh "$BACKUP_DIR/nexus_pg_${DATE}.dump" | cut -f1))"

# 2. Nexus blob store + config (via volume snapshot)
log "Backing up nexus-data volume..."
docker run --rm \
  -v nexus_nexus_data:/nexus-data:ro \
  -v "$BACKUP_DIR":/backup \
  docker-hosted.hamainsruance.net/alpine:3.21 \
  tar -czf "/backup/nexus_data_${DATE}.tar.gz" -C /nexus-data .

log "Volume backup: $BACKUP_DIR/nexus_data_${DATE}.tar.gz ($(du -sh "$BACKUP_DIR/nexus_data_${DATE}.tar.gz" | cut -f1))"

# 3. Rotate old backups
log "Rotating backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_DIR" -name "nexus_pg_*.dump" -mtime "+${RETENTION_DAYS}" -delete
find "$BACKUP_DIR" -name "nexus_data_*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete

log "Backup complete."
