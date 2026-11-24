#!/bin/bash
# Reset Nexus admin password directly in PostgreSQL (Shiro1 SHA-512 hash)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  echo "Usage: $0 <new-password>"
  echo "Example: $0 'MyNewPass@2026'"
  exit 1
}

[[ $# -lt 1 ]] && usage

NEW_PASS="$1"
PG_USER=$(cat "$ROOT_DIR/secrets/pg_user.txt")
PG_PASS=$(cat "$ROOT_DIR/secrets/pg_password.txt")

# Generate Shiro1 SHA-512 hash (matches Apache Shiro's SimpleHash algorithm)
HASH=$(python3 -c "
import hashlib, base64, os, sys
password = sys.argv[1]
salt = os.urandom(16)
salt_b64 = base64.b64encode(salt).decode()
result = hashlib.sha512(salt + password.encode('utf-8')).digest()
for _ in range(1023):
    result = hashlib.sha512(result).digest()
hash_b64 = base64.b64encode(result).decode()
print(f'\$shiro1\$SHA-512\$1024\${salt_b64}=\${hash_b64}')
" "$NEW_PASS")

docker exec nexus_postgres \
  env PGPASSWORD="$PG_PASS" \
  psql -U "$PG_USER" -d nexus \
  -c "UPDATE security_user SET password='${HASH}', version=version+1 WHERE id='admin';"

echo "[reset] Admin password updated. Restart Nexus for the change to take effect:"
echo "  docker compose -f ${ROOT_DIR}/docker-compose/nexus/docker-compose.yml restart nexus"
