#!/bin/bash -e
CONFDEST="$1"
CONFPART="$2"
CLUSTER_NAME="$3"
SERVER_IP=$(/vagrant/tools/node_ip.sh)
SERVER_ID=$(/vagrant/tools/node_ip.sh|awk -F '\\.' '{print ($1 * 2^24) + ($2 * 2^16) + ($3 * 2^8) + $4}')
sed -e "s/server_id=.*\$/server_id=$SERVER_ID/" \
    -e "s/report_host=.*\$/report_host=$SERVER_IP/" \
    -e "s/wsrep_cluster_name=.*\$/wsrep_cluster_name=$CLUSTER_NAME/" "$CONFPART" >> "$CONFDEST"
touch /root/$( basename $CONFPART).applied
