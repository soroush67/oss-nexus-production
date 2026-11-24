#!/bin/bash
set -euo pipefail

PG_USER=$(cat /run/secrets/pg_user)

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Revoke default public schema privileges
    REVOKE CREATE ON SCHEMA public FROM PUBLIC;
    REVOKE ALL ON DATABASE nexus FROM PUBLIC;

    -- Grant only to nexus user
    GRANT ALL PRIVILEGES ON DATABASE nexus TO "${PG_USER}";
    GRANT ALL ON SCHEMA public TO "${PG_USER}";

    -- Performance extensions
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EOSQL

echo "[init] Nexus database initialized successfully"
