#!/bin/sh
echo Starting postgresql secondary
TYPE=streaming_physical_slots
MASTER_IP=$POSTGRES_PRIMARY_HOST
MASTER_USER=postgres
MASTER_PASSWORD="$POSTGRES_PASSWORD"
MASTER_DB=postgres
PGDATA="$PGDATA"
LOGICAL_DB=pgbench

SERVER_ID=$(hostname)

until PGPASSWORD="$MASTER_PASSWORD" PGHOST=$MASTER_IP PGDATABASE=$MASTER_DB PGUSER=$MASTER_USER psql -c "SELECT 1"  ; do
  sleep 1
done

if [ "x$TYPE" = "xstreaming_physical_slots" ] ; then
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
    rm -rf -- $PGDATA/*
    if postgres --version | grep -q -F ' 9.' ; then
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
    if postgres --version | grep -q -F ' 9.' ; then
        cat >> $PGDATA/recovery.conf <<EOF
primary_slot_name = '$SLOT'
EOF
    fi
fi


docker-entrypoint.sh postgres
