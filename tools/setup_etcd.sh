#!/bin/bash
CLUSTER="$1"
SECRET="$2"
NODE_IP=$(node_ip.sh)
FIRST_SERVER="$3"

if [[ "x$FIRST_SERVER" == "x" ]]; then
  CLUSTER="${CLUSTER}-0"
  cat >/etc/etcd/etcd.conf <<EOF
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
  cat >/etc/etcd/etcd.conf.yaml <<EOF
name: '${CLUSTER}'
initial-cluster-token: '${SECRET}'
initial-cluster-state: new
initial-cluster: ${CLUSTER}=http://${NODE_IP}:2380
data-dir: /var/lib/etcd/postgres.etcd
initial-advertise-peer-urls: http://${NODE_IP}:2380
listen-peer-urls: http://${NODE_IP}:2380
advertise-client-urls: http://${NODE_IP}:2379
listen-client-urls: http://${NODE_IP}:2379,http://localhost:2379
EOF
else
  systemctl stop etcd
  rm -rf /var/lib/etcd/*

  # wait until previous nodes join
  while etcdctl --dial-timeout=30s --endpoints http://${FIRST_SERVER}:2379 member list | grep -q unstarted; do sleep 2; done

  until test $(etcdctl --dial-timeout=30s --endpoints http://${FIRST_SERVER}:2379 member list -w table | grep :2380 | grep -v unstarted | wc -l) -gt 0; do sleep 3; done

  LAST_SERVER_ID=$(etcdctl --dial-timeout=30s --endpoints http://${FIRST_SERVER}:2379 member list -w fields | grep Name | tail -n 1 | sed -r -e 's/^.*-([0-9]+)"$/\1/')
  CLUSTER="${CLUSTER}$RANDOM-"$((LAST_SERVER_ID + 1))
  while true; do
    INITIAL_CLUSTER=$(etcdctl --dial-timeout=30s --endpoints http://${FIRST_SERVER}:2379 member list -w table | grep -v unstarted | grep :2380 | awk -F'[[:space:]]*[|][[:space:]]+' '{print $4 "=" $5}' | sed -e ':a;N;$!ba;s/\n/,/g')
    if [[ "x$INITIAL_CLUSTER" != "x" ]]; then
      break
    fi
  done
  cat >/etc/etcd/etcd.conf <<EOF
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
  cat >/etc/etcd/etcd.conf.yaml <<EOF
name: '${CLUSTER}'
initial-cluster-token: '${SECRET}'
initial-cluster-state: existing
initial-cluster: "${CLUSTER}=http://${NODE_IP}:2380,${INITIAL_CLUSTER}"
data-dir: /var/lib/etcd/postgres.etcd
initial-advertise-peer-urls: http://${NODE_IP}:2380
listen-peer-urls: http://${NODE_IP}:2380
advertise-client-urls: http://${NODE_IP}:2379
listen-client-urls: http://${NODE_IP}:2379,http://localhost:2379
EOF
  until etcdctl --dial-timeout=30s --endpoints http://${FIRST_SERVER}:2379 member add ${CLUSTER} --peer-urls=http://${NODE_IP}:2380; do sleep 5; done
fi

systemctl daemon-reload

# Start etcd with retry logic
for i in {1..5}; do
  systemctl start etcd && break
  echo "etcd start attempt $i failed, retrying in 5s..."
  sleep 5
done

# Wait for this node to be part of a healthy cluster
echo "Waiting for etcd to stabilize..."
sleep 3
