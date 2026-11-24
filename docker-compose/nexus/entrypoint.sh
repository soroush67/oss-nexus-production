#!/bin/sh
# Read Docker secrets and write runtime config files before starting Nexus
set -e

PG_USER=$(cat /run/secrets/pg_user)
PG_PASS=$(cat /run/secrets/pg_password)

# Ensure directories exist
mkdir -p /nexus-data/etc/fabric /nexus-data/etc

# Write nexus.properties with real credentials
cat > /nexus-data/etc/nexus.properties <<EOF
nexus.datastore.enabled=true
nexus.datastore.nexus.jdbcUrl=jdbc\:postgresql\://postgres\:5432/nexus
nexus.datastore.nexus.username=${PG_USER}
nexus.datastore.nexus.password=${PG_PASS}
nexus.datastore.nexus.maximumPoolSize=20
nexus.datastore.nexus.advanced=maxLifetime\=600000
application-port=8081
application-host=0.0.0.0
nexus-args=\${jetty.etc}/jetty.xml,\${jetty.etc}/jetty-http.xml,\${jetty.etc}/jetty-requestlog.xml
nexus.security.anonymous.access=false
nexus.clustered=false
EOF

# Write nexus-store.properties
cat > /nexus-data/etc/fabric/nexus-store.properties <<EOF
name=nexus
type=jdbc
jdbcUrl=jdbc\:postgresql\://postgres\:5432/nexus
username=${PG_USER}
password=${PG_PASS}
advanced=maximumPoolSize\=20;connectionTimeout\=30000;idleTimeout\=600000;maxLifetime\=1800000
EOF

export INSTALL4J_ADD_VM_PARAMS="-Xms2703m -Xmx2703m -XX:MaxDirectMemorySize=2703m -Djava.util.prefs.userRoot=/nexus-data/javaprefs -Djava.net.preferIPv4Stack=true"

exec /opt/sonatype/nexus/bin/nexus run
