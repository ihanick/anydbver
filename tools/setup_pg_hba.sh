#!/bin/sh
if test -z "$PGDATA"; then
  export PGDATA=/data/db
fi

if ! grep -q "host replication postgres" /docker-entrypoint-initdb.d/00-init.sh 2>/dev/null; then
  cat >>/docker-entrypoint-initdb.d/00-init.sh <<EOF
echo "host replication postgres all scram-sha-256" >> "$PGDATA"/pg_hba.conf
EOF
  chmod +x /docker-entrypoint-initdb.d/00-init.sh
fi

if test -f /entrypoint.sh; then
  /entrypoint.sh postgres
else
  docker-entrypoint.sh postgres
fi
