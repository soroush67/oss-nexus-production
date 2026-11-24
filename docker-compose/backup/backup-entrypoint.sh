#!/bin/sh
# Cron entrypoint: installs mc if RUSTFS_ENABLED, writes crontab, runs crond
set -e

# نصب ابزارهای اضافه (pg_dump از postgres:18-alpine image موجود است)
apk add --no-cache bash curl wget 2>/dev/null

# نصب mc (MinIO Client) اگر RustFS فعال باشد
if [ "${RUSTFS_ENABLED}" = "true" ]; then
  echo "[backup-entrypoint] Installing mc for RustFS upload..."
  wget -qO /usr/local/bin/mc \
    https://dl.min.io/client/mc/release/linux-amd64/mc && \
    chmod +x /usr/local/bin/mc

  RUSTFS_USER=$(cat /run/secrets/rustfs_user)
  RUSTFS_PASS=$(cat /run/secrets/rustfs_password)

  mc alias set rustfs "${RUSTFS_ENDPOINT}" "${RUSTFS_USER}" "${RUSTFS_PASS}" --insecure 2>/dev/null || true
  mc mb --ignore-existing rustfs/"${RUSTFS_BUCKET}" 2>/dev/null || true
  echo "[backup-entrypoint] RustFS configured: ${RUSTFS_ENDPOINT}/${RUSTFS_BUCKET}"
fi

mkdir -p /scripts

# نوشتن crontab
echo "${BACKUP_SCHEDULE} /bin/bash /scripts/run-backup.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root
echo "[backup-entrypoint] Cron schedule: ${BACKUP_SCHEDULE}"

# ساخت wrapper script که env vars را پاس می‌دهد
cat > /scripts/run-backup.sh <<EOF
#!/bin/bash
export BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS}"
export RUSTFS_ENABLED="${RUSTFS_ENABLED}"
export RUSTFS_ENDPOINT="${RUSTFS_ENDPOINT}"
export RUSTFS_BUCKET="${RUSTFS_BUCKET}"
export PG_USER=\$(cat /run/secrets/pg_user)
export PG_PASS=\$(cat /run/secrets/pg_password)

echo "[\$(date)] Starting backup..."

# PG dump
DATE=\$(date +%Y%m%d_%H%M%S)
mkdir -p /backups

PGPASSWORD="\${PG_PASS}" pg_dump \
  -h nexus_postgres -U "\${PG_USER}" -d nexus -Fc \
  > "/backups/nexus_pg_\${DATE}.dump"
echo "[\$(date)] PG dump: /backups/nexus_pg_\${DATE}.dump (\$(du -sh /backups/nexus_pg_\${DATE}.dump | cut -f1))"

# Volume snapshot
tar -czf "/backups/nexus_data_\${DATE}.tar.gz" -C /nexus-data . 2>/dev/null
echo "[\$(date)] Volume backup: /backups/nexus_data_\${DATE}.tar.gz (\$(du -sh /backups/nexus_data_\${DATE}.tar.gz | cut -f1))"

# آپلود به RustFS اگر فعال باشد
if [ "\${RUSTFS_ENABLED}" = "true" ]; then
  RUSTFS_USER=\$(cat /run/secrets/rustfs_user)
  RUSTFS_PASS=\$(cat /run/secrets/rustfs_password)
  mc alias set rustfs "\${RUSTFS_ENDPOINT}" "\${RUSTFS_USER}" "\${RUSTFS_PASS}" --insecure 2>/dev/null
  mc cp "/backups/nexus_pg_\${DATE}.dump"       rustfs/"\${RUSTFS_BUCKET}"/pg/ && echo "[\$(date)] Uploaded PG dump to RustFS"
  mc cp "/backups/nexus_data_\${DATE}.tar.gz"   rustfs/"\${RUSTFS_BUCKET}"/volume/ && echo "[\$(date)] Uploaded volume backup to RustFS"
fi

# Rotate local backups
find /backups -name "nexus_pg_*.dump"      -mtime +"\${BACKUP_RETENTION_DAYS}" -delete
find /backups -name "nexus_data_*.tar.gz"  -mtime +"\${BACKUP_RETENTION_DAYS}" -delete
echo "[\$(date)] Backup complete."
EOF
chmod +x /scripts/run-backup.sh

echo "[backup-entrypoint] Starting crond..."
exec crond -f -l 6
