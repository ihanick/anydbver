#!/bin/bash
MINF=/tmp/master_info.txt
TYPE=$1
MASTER_IP=$2
MASTER_USER=$3
MASTER_PASSWORD=$4

mysql --host $MASTER -e 'DROP VIEW IF EXISTS mysql.nonexisting_23498985;show master status\G' > "$MINF"

if [[ "x$TYPE" == "xgtid" ]] ; then
    GTID=$( awk -F': ' '/Executed_Gtid_Set/ {print $2}' "$MINF" )

    mysql << EOF
    RESET MASTER;
    SET GLOBAL GTID_PURGED='${GTID}';
    STOP SLAVE;
    CHANGE MASTER TO MASTER_HOST='${MASTER_IP}', MASTER_USER='${MASTER_USER}', MASTER_PASSWORD='${MASTER_PASSWORD}', MASTER_AUTO_POSITION=1, MASTER_SSL=1;
    START SLAVE;
EOF

    touch /root/replication.configured
fi

rm "${MINF}"

