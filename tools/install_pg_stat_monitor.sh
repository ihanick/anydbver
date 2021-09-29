#!/bin/bash
yum install -y git make
yum groups install -y "Development Tools"
export PATH=$PATH:$(ls -d /usr/pgsql-*/bin|tail -n 1)
git clone git://github.com/Percona/pg_stat_monitor.git
cd pg_stat_monitor
make USE_PGXS=1
make USE_PGXS=1 install
sudo -u postgres psql -c "CREATE EXTENSION pg_stat_monitor;"
sudo -u postgres psql -c "ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_monitor';"
systemctl restart postgresql-13
touch /root/pg_stat_monitor.installed
