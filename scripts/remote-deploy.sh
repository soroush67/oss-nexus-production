#!/bin/bash
# Deploy oss-nexus stack to remote server
# Usage: REMOTE_PASS=<password> ./scripts/remote-deploy.sh
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-192.168.11.67}"
REMOTE_USER="${REMOTE_USER:-devops}"
REMOTE_PASS="${REMOTE_PASS:?REMOTE_PASS env var is required}"
REMOTE_DIR="${REMOTE_DIR:-/home/devops/containerd/nexus}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

SSH="sshpass -p '${REMOTE_PASS}' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 ${REMOTE_USER}@${REMOTE_HOST}"
SCP="sshpass -p '${REMOTE_PASS}' scp -o StrictHostKeyChecking=no"

log()  { echo "[remote-deploy] $*"; }
step() { echo ""; echo "===== $* ====="; }

# ─── Step 1: بررسی اتصال ───────────────────────────────────────────────────
step "1. SSH connectivity"
eval "$SSH" "echo 'SSH OK' && uname -a"

# ─── Step 2: نصب docker compose plugin ────────────────────────────────────
step "2. Install docker compose plugin on remote"
eval "$SCP" "/home/soroush/.docker/cli-plugins/docker-compose" \
  "${REMOTE_USER}@${REMOTE_HOST}:/tmp/docker-compose"

eval "$SSH" "echo '${REMOTE_PASS}' | sudo -S bash -s <<'SUDO'
mkdir -p /usr/local/lib/docker/cli-plugins
cp /tmp/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
usermod -aG docker ${REMOTE_USER}
echo 'compose plugin installed'
SUDO"

# ─── Step 3: ذخیره و انتقال image ها ─────────────────────────────────────
step "3. Save and transfer Docker images (~1.6 GB)"
IMAGES_TAR="/tmp/nexus-images.tar"

log "Saving images to ${IMAGES_TAR}..."
docker save \
  docker-hosted.hamainsruance.net/sonatype/nexus3:3.80.0 \
  docker-hosted.hamainsruance.net/postgres:18-alpine \
  docker-hosted.hamainsruance.net/nginx:1.30.7-alpine \
  docker-hosted.hamainsruance.net/alpine:3.21 \
  rustfs/rustfs:latest \
  -o "${IMAGES_TAR}"

log "Image tar size: $(du -sh ${IMAGES_TAR} | cut -f1)"
log "Transferring to remote (this may take a few minutes)..."
eval "$SCP" "${IMAGES_TAR}" "${REMOTE_USER}@${REMOTE_HOST}:/tmp/nexus-images.tar"

log "Loading images on remote..."
eval "$SSH" "echo '${REMOTE_PASS}' | sudo -S docker load -i /tmp/nexus-images.tar && rm /tmp/nexus-images.tar"

# ─── Step 4: انتقال فایل‌های پروژه ───────────────────────────────────────
step "4. Rsync project files"
eval "$SSH" "mkdir -p ${REMOTE_DIR}"

sshpass -p "${REMOTE_PASS}" rsync -av --progress \
  --exclude 'secrets/' \
  --exclude 'docker-compose/nginx/ssl/' \
  --exclude 'backups/' \
  --exclude '.git/' \
  --exclude 'docs/' \
  -e "ssh -o StrictHostKeyChecking=no" \
  "${ROOT_DIR}/" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"

# ─── Step 5: تنظیم secrets روی سرور ریموت ────────────────────────────────
step "5. Copy secrets to remote"
eval "$SSH" "mkdir -p ${REMOTE_DIR}/secrets ${REMOTE_DIR}/docker-compose/nginx/ssl"

eval "$SCP" -r \
  "${ROOT_DIR}/secrets/" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"

eval "$SCP" -r \
  "${ROOT_DIR}/docker-compose/nginx/ssl/" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/docker-compose/nginx/"

# ─── Step 6: تنظیمات روی سرور ریموت ─────────────────────────────────────
step "6. Configure remote server"
eval "$SSH" "echo '${REMOTE_PASS}' | sudo -S bash -s <<'SUDO'
# docker socket permission برای docker group (بدون re-login با sg)
chmod 666 /var/run/docker.sock

# ایجاد external network
docker network create \
  --driver bridge \
  --opt com.docker.network.bridge.name=br-nexus \
  nexus_infra_net 2>/dev/null || echo 'network already exists'

# ایجاد nexus_nexus_data volume (اگر موجود نیست)
docker volume create nexus_nexus_data 2>/dev/null || echo 'volume already exists'

echo 'remote config done'
SUDO"

# ─── Step 7: راه‌اندازی stack ────────────────────────────────────────────
step "7. Deploy stack on remote"
eval "$SSH" "cd ${REMOTE_DIR} && bash scripts/deploy.sh 2>&1"

log ""
log "✅ Deploy complete!"
log "   Nexus: https://${REMOTE_HOST}"
log "   Admin: admin / Admin@1234"
