#!/bin/bash
CLUSTER="$1"
SECRET="$2"
NODE_IP=$(node_ip.sh)
FIRST_SERVER="$3"

if [[ "x$FIRST_SERVER" == "x" ]] ; then
  CLUSTER="${CLUSTER}-0"
  cat > /etc/etcd/etcd.conf  <<EOF
ETCD_NAME=${CLUSTER}
ETCD_INITIAL_CLUSTER="${CLUSTER}=http://${NODE_IP}:2380"
ETCD_INITIAL_CLUSTER_TOKEN="${SECRET}"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${NODE_IP}:2380"
ETCD_DATA_DIR="/var/lib/etcd/postgres.etcd"
ETCD_LISTEN_PEER_URLS="http://${NODE_IP}:2380"
ETCD_LISTEN_CLIENT_URLS="http://${NODE_IP}:2379,http://localhost:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://${NODE_IP}:2379"
EOF
else
  LAST_SERVER_ID=$(etcdctl  --endpoints http://${FIRST_SERVER}:2379 member list  -w fields |grep Name|tail -n 1|sed -r -e 's/^.*-([0-9]+)"$/\1/')
  CLUSTER="${CLUSTER}$RANDOM-"$(( LAST_SERVER_ID + 1 ))
  INITIAL_CLUSTER=$(etcdctl --endpoints http://${FIRST_SERVER}:2379 member list -w table|grep :2380 | awk -F'[[:space:]]*[|][[:space:]]+' '{print $4 "=" $5}'|sed -e ':a;N;$!ba;s/\n/,/g')
  cat > /etc/etcd/etcd.conf  <<EOF
ETCD_NAME=${CLUSTER}
ETCD_INITIAL_CLUSTER="${CLUSTER}=http://${NODE_IP}:2380,${INITIAL_CLUSTER}"
ETCD_INITIAL_CLUSTER_TOKEN="${SECRET}"
ETCD_INITIAL_CLUSTER_STATE="existing"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${NODE_IP}:2380"
ETCD_DATA_DIR="/var/lib/etcd/postgres.etcd"
ETCD_LISTEN_PEER_URLS="http://${NODE_IP}:2380"
ETCD_LISTEN_CLIENT_URLS="http://${NODE_IP}:2379,http://localhost:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://${NODE_IP}:2379"
EOF
    until etcdctl --endpoints http://${FIRST_SERVER}:2379 member add ${CLUSTER} --peer-urls=http://${NODE_IP}:2380 ; do sleep 5 ; done
fi
