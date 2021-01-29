#!/bin/bash
TYPE=$1
MASTER_IP=$2
MASTER_USER=$3
MASTER_PASSWORD=$4
MASTER_DB=$5
PGDATA=$6
SYSTEMD_UNIT=$7

SERVER_ID=$(ip addr ls|grep 'inet '|grep -v '127.0.0.1'|awk '{print $2}'|cut -d/ -f 1|awk -F '\\.' '{print ($1 * 2^24) + ($2 * 2^16) + ($3 * 2^8) + $4}')


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
fi
