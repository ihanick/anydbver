#!/bin/bash
yum install -y git make
yum groups install -y "Development Tools"
export PATH=$PATH:$(ls -d /usr/pgsql-*/bin|tail -n 1)
export PGHOSTADDR=$(node_ip.sh) PGUSER=postgres PGHOST=$(node_ip.sh)
git clone git://github.com/Percona/pg_stat_monitor.git
cd pg_stat_monitor
make USE_PGXS=1
make USE_PGXS=1 install
psql -c "CREATE EXTENSION pg_stat_monitor;"
psql -c "ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_monitor';"
systemctl restart postgresql-13
touch /root/pg_stat_monitor.installed
