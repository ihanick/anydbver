#!/bin/bash
TYPE=$1
MASTER_IP=$2
MASTER_USER=$3
MASTER_PASSWORD=$4
MASTER_DB=$5
PGDATA=$6
SYSTEMD_UNIT=$7
LOGICAL_DB=$8

SERVER_ID=$(ip addr ls|grep 'inet '|grep -v '127.0.0.1'|awk '{print $2}'|cut -d/ -f 1|awk -F '\\.' '{print ($1 * 2^24) + ($2 * 2^16) + ($3 * 2^8) + $4}')

until PGPASSWORD="$MASTER_PASSWORD" PGHOST=$MASTER_IP PGDATABASE=$MASTER_DB PGUSER=$MASTER_USER psql -c "SELECT 1"  ; do
  sleep 1
done

if [[ "x$TYPE" == "xstreaming_physical_slots" ]] ; then
    SLOT="slot_$SERVER_ID";

    PGPASSWORD="$MASTER_PASSWORD" PGHOST=$MASTER_IP PGDATABASE=$MASTER_DB PGUSER=$MASTER_USER psql <<EOF
    SELECT CASE
    WHEN count(*) = 0
    THEN
      pg_create_physical_replication_slot('$SLOT')
    ELSE
      ('slot exists',0)
    END
    FROM pg_replication_slots WHERE slot_name='$SLOT';
EOF
    systemctl stop $SYSTEMD_UNIT
    rm -rf -- $PGDATA/*
    if [[ "$SYSTEMD_UNIT" == *'-9.'* ]] ; then
        PGPASSWORD="$MASTER_PASSWORD" PGHOST=$MASTER_IP PGDATABASE=$MASTER_DB PGUSER=$MASTER_USER pg_basebackup \
          -D $PGDATA -Fp -P -Xs -Rv &
    else
        PGPASSWORD="$MASTER_PASSWORD" PGHOST=$MASTER_IP PGDATABASE=$MASTER_DB PGUSER=$MASTER_USER pg_basebackup \
          -S "$SLOT" -D $PGDATA -Fp -P -Xs -Rv &
    fi
    
    PGPASSWORD="$MASTER_PASSWORD" PGHOST=$MASTER_IP PGDATABASE=$MASTER_DB PGUSER=$MASTER_USER psql <<EOF1
    CHECKPOINT;
EOF1
    wait
    chown -R postgres:postgres $PGDATA
    if [[ "$SYSTEMD_UNIT" == *'-9.'* ]] ; then
        cat >> $PGDATA/recovery.conf <<EOF
primary_slot_name = '$SLOT'
EOF
    fi
    # it's a next step in playbook: systemctl start $SYSTEMD_UNIT

    touch /root/replication.configured
elif [[ "x$TYPE" == "xlogical" ]] ; then
    unset PGHOSTADDR
    PGPASSWORD="$MASTER_PASSWORD" PGHOST=$(node_ip.sh) PGDATABASE=$MASTER_DB PGUSER=$MASTER_USER psql <<EOF
CREATE USER sbtest WITH PASSWORD '$MASTER_PASSWORD';
CREATE DATABASE $LOGICAL_DB;
GRANT ALL PRIVILEGES ON DATABASE $LOGICAL_DB TO sbtest;
EOF
    PGPASSWORD="$MASTER_PASSWORD" PGHOST=$MASTER_IP PGDATABASE=$LOGICAL_DB PGUSER=$MASTER_USER psql <<EOF
CREATE PUBLICATION ${LOGICAL_DB}_publication FOR ALL TABLES;
EOF
    PGPASSWORD="$MASTER_PASSWORD" PGHOST=$MASTER_IP PGDATABASE=$LOGICAL_DB PGUSER=$MASTER_USER pg_dump -s $LOGICAL_DB > /root/$LOGICAL_DB.schema.sql
    PGPASSWORD="$MASTER_PASSWORD" PGHOST=$(node_ip.sh) PGDATABASE=$LOGICAL_DB PGUSER=$MASTER_USER psql < /root/$LOGICAL_DB.schema.sql
    PGPASSWORD="$MASTER_PASSWORD" PGHOST=$(node_ip.sh) PGDATABASE=$LOGICAL_DB PGUSER=$MASTER_USER psql <<EOF
CREATE SUBSCRIPTION ${LOGICAL_DB}_${SERVER_ID}_subscription CONNECTION 'host=$MASTER_IP port=5432 password=$MASTER_PASSWORD user=$MASTER_USER dbname=$LOGICAL_DB' PUBLICATION ${LOGICAL_DB}_publication;
EOF
    touch /root/replication.configured
fi

