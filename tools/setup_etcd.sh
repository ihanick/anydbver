#!/bin/bash
CLUSTER="$1"
SECRET="$2"
NODE_IP=$(node_ip.sh)
FIRST_SERVER="$3"

if [[ "x$FIRST_SERVER" == "x" ]] ; then
  CLUSTER="${CLUSTER}-0"
  sed -i.bak \
    -e "s|^.*ETCD_NAME=.*\$|ETCD_NAME=${CLUSTER}|" \
    -e "s|^.*ETCD_INITIAL_CLUSTER=.*\$|ETCD_INITIAL_CLUSTER=\"${CLUSTER}=http://${NODE_IP}:2380\"|" \
    -e "s|^.*ETCD_INITIAL_CLUSTER_TOKEN=.*\$|ETCD_INITIAL_CLUSTER_TOKEN=\"${SECRET}\"|" \
    -e "s|^.*ETCD_INITIAL_CLUSTER_STATE=.*\$|ETCD_INITIAL_CLUSTER_STATE=\"new\"|" \
    -e "s|^.*ETCD_INITIAL_ADVERTISE_PEER_URLS=.*\$|ETCD_INITIAL_ADVERTISE_PEER_URLS=\"http://${NODE_IP}:2380\"|" \
    -e "s|^.*ETCD_DATA_DIR=.*\$|ETCD_DATA_DIR=\"/var/lib/etcd/postgres.etcd\"|" \
    -e "s|^.*ETCD_LISTEN_PEER_URLS=.*\$|ETCD_LISTEN_PEER_URLS=\"http://${NODE_IP}:2380\"|" \
    -e "s|^.*ETCD_LISTEN_CLIENT_URLS=.*\$|ETCD_LISTEN_CLIENT_URLS=\"http://${NODE_IP}:2379,http://localhost:2379\"|" \
    -e "s|^.*ETCD_ADVERTISE_CLIENT_URLS=.*\$|ETCD_ADVERTISE_CLIENT_URLS=\"http://${NODE_IP}:2379\"|" \
    /etc/etcd/etcd.conf
else
  LAST_SERVER_ID=$(etcdctl  --endpoints http://${FIRST_SERVER}:2379 member list|sed -e 's/ /\n/g'|grep name=|sed -r -e 's/^.*-([0-9]+)$/\1/'|sort -n|tail -n 1)
  CLUSTER="${CLUSTER}-"$(( LAST_SERVER_ID + 1 ))
  INITIAL_CLUSTER=$(etcdctl --endpoints http://${FIRST_SERVER}:2379 member list|sed -re 's/.*name=([^ ]+) peerURLs=([^ ]+) .*$/\1=\2/'|sed -e ':a;N;$!ba;s/\n/,/g')
  sed -i.bak \
    -e "s|^.*ETCD_NAME=.*\$|ETCD_NAME=${CLUSTER}|" \
    -e "s|^.*ETCD_INITIAL_CLUSTER=.*\$|ETCD_INITIAL_CLUSTER=\"${CLUSTER}=http://${NODE_IP}:2380,${INITIAL_CLUSTER}\"|" \
    -e "s|^.*ETCD_INITIAL_CLUSTER_TOKEN=.*\$|ETCD_INITIAL_CLUSTER_TOKEN=\"${SECRET}\"|" \
    -e "s|^.*ETCD_INITIAL_CLUSTER_STATE=.*\$|ETCD_INITIAL_CLUSTER_STATE=\"existing\"|" \
    -e "s|^.*ETCD_INITIAL_ADVERTISE_PEER_URLS=.*\$|ETCD_INITIAL_ADVERTISE_PEER_URLS=\"http://${NODE_IP}:2380\"|" \
    -e "s|^.*ETCD_DATA_DIR=.*\$|ETCD_DATA_DIR=\"/var/lib/etcd/postgres.etcd\"|" \
    -e "s|^.*ETCD_LISTEN_PEER_URLS=.*\$|ETCD_LISTEN_PEER_URLS=\"http://${NODE_IP}:2380\"|" \
    -e "s|^.*ETCD_LISTEN_CLIENT_URLS=.*\$|ETCD_LISTEN_CLIENT_URLS=\"http://${NODE_IP}:2379,http://localhost:2379\"|" \
    -e "s|^.*ETCD_ADVERTISE_CLIENT_URLS=.*\$|ETCD_ADVERTISE_CLIENT_URLS=\"http://${NODE_IP}:2379\"|" \
    /etc/etcd/etcd.conf
      etcdctl --endpoints http://${FIRST_SERVER}:2379 member add ${CLUSTER} http://${NODE_IP}:2380
fi
