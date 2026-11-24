#!/bin/bash
# Generate production secrets for oss-nexus stack.
# Run once before first deploy. Never commit the secrets/ directory.
set -euo pipefail

SECRETS_DIR="$(cd "$(dirname "$0")/.." && pwd)/secrets"
SSL_DIR="$(cd "$(dirname "$0")/.." && pwd)/docker-compose/nginx/ssl"

mkdir -p "$SECRETS_DIR" "$SSL_DIR"

echo "[secrets] Generating PostgreSQL credentials..."

if [[ -f "$SECRETS_DIR/pg_user.txt" ]]; then
  echo "[secrets] pg_user.txt already exists — skipping (delete to regenerate)"
else
  echo -n "nexus" > "$SECRETS_DIR/pg_user.txt"
  chmod 644 "$SECRETS_DIR/pg_user.txt"
fi

if [[ -f "$SECRETS_DIR/pg_password.txt" ]]; then
  echo "[secrets] pg_password.txt already exists — skipping"
else
  # 32-byte URL-safe random password
  pw=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^*_+=' < /dev/urandom | head -c 32)
  echo -n "$pw" > "$SECRETS_DIR/pg_password.txt"
  chmod 644 "$SECRETS_DIR/pg_password.txt"
  echo "[secrets] pg_password.txt created"
fi

echo "[secrets] Generating RustFS credentials..."

if [[ -f "$SECRETS_DIR/rustfs_user.txt" ]]; then
  echo "[secrets] rustfs_user.txt already exists — skipping"
else
  echo -n "rustfsadmin" > "$SECRETS_DIR/rustfs_user.txt"
  chmod 644 "$SECRETS_DIR/rustfs_user.txt"
  echo "[secrets] rustfs_user.txt created"
fi

if [[ -f "$SECRETS_DIR/rustfs_password.txt" ]]; then
  echo "[secrets] rustfs_password.txt already exists — skipping"
else
  pw=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^*_+=' < /dev/urandom | head -c 32)
  echo -n "$pw" > "$SECRETS_DIR/rustfs_password.txt"
  chmod 644 "$SECRETS_DIR/rustfs_password.txt"
  echo "[secrets] rustfs_password.txt created"
fi

echo "[secrets] Generating self-signed TLS certificate (replace with real cert in production)..."
if [[ -f "$SSL_DIR/nexus.crt" ]]; then
  echo "[secrets] SSL cert already exists — skipping"
else
  openssl req -x509 -nodes -days 3650 \
    -newkey rsa:4096 \
    -keyout "$SSL_DIR/nexus.key" \
    -out "$SSL_DIR/nexus.crt" \
    -subj "/C=IR/O=Nexus/CN=nexus.local" \
    -addext "subjectAltName=DNS:nexus.local,DNS:localhost,IP:127.0.0.1" \
    2>/dev/null
  chmod 600 "$SSL_DIR/nexus.key"
  echo "[secrets] Self-signed cert generated: $SSL_DIR/nexus.crt"
fi

echo ""
echo "[secrets] Done. Summary:"
ls -la "$SECRETS_DIR/"
echo ""
echo "IMPORTANT: Add trusted CA cert or replace nexus.crt/nexus.key with Let's Encrypt certs before production."
