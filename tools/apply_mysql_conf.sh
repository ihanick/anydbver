#!/bin/bash -e
CONFDEST="$1"
CONFPART="$2"
CLUSTER_NAME="$3"
USER="$4"
PASSWORD="$5"
DATADIR="$6"
SERVER_IP=$(/bin/bash /vagrant/tools/node_ip.sh)
SERVER_ID=$(/bin/bash /vagrant/tools/node_ip.sh|gawk -F '\\.' '{print ($1 * 2^24) + ($2 * 2^16) + ($3 * 2^8) + $4}')
sed -e "s/server_id=.*\$/server_id=$SERVER_ID/" \
    -e "s/report_host=.*\$/report_host=$SERVER_IP/" \
    -e "s/wsrep_node_name=.*\$/wsrep_node_name=$SERVER_IP/" \
    -e "s/wsrep_cluster_name=.*\$/wsrep_cluster_name=$CLUSTER_NAME/" \
    -e "s/wsrep_sst_auth=.*\$/wsrep_sst_auth=$USER:$PASSWORD/" \
    -e "s,\\\$PGDATA,$DATADIR,g" \
    "$CONFPART" >> "$CONFDEST"
touch /root/$( basename $CONFPART).applied
echo "$CONFDEST" > /root/mysql.conf.filename
