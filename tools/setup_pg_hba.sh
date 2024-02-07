#!/bin/sh
if ! grep -q "host replication postgres" /docker-entrypoint-initdb.d/00-init.sh ; then
	cat >> /docker-entrypoint-initdb.d/00-init.sh <<EOF
echo "host replication postgres all scram-sha-256" >> "$PGDATA"/pg_hba.conf
EOF
chmod +x /docker-entrypoint-initdb.d/00-init.sh
fi

docker-entrypoint.sh postgres
