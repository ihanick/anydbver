#!/bin/bash
SOFT=$1
USER=$2
PASSWORD=$3
PMM_USER=$4
PMM_PASS=$5
SYSTEMD_UNIT=$6

psql -h $(/vagrant/tools/node_ip.sh) -U $USER -c "CREATE USER $PMM_USER WITH ENCRYPTED PASSWORD '$PMM_PASS'"
psql -h $(/vagrant/tools/node_ip.sh) -U $USER -c "GRANT pg_monitor to $PMM_USER"
psql -h $(/vagrant/tools/node_ip.sh) -U $USER -c "ALTER SYSTEM SET shared_preload_libraries TO 'pg_stat_statements'"
systemctl restart $SYSTEMD_UNIT
psql -h $(/vagrant/tools/node_ip.sh) -U $USER -c "CREATE DATABASE $PMM_USER"
psql -h $(/vagrant/tools/node_ip.sh) -U $USER -c "CREATE EXTENSION pg_stat_statements"
psql -h $(/vagrant/tools/node_ip.sh) -U $USER -d $PMM_USER -c "CREATE EXTENSION pg_stat_statements"
#pmm-admin add postgresql --query-source=none --username=$PMM_USER --password="$PMM_PASS" postgres $(/vagrant/tools/node_ip.sh):5432
pmm-admin add postgresql --username=$PMM_USER --password="$PMM_PASS" postgres $(/vagrant/tools/node_ip.sh):5432
touch /root/pmm-postgresql.applied
