#!/bin/bash
PODMAN_HUB=docker.io/
SELINUX=0
sestatus | grep 'SELinux status'|grep -q enabled && SELINUX=1

get_ip() {
  local SERVER_NAME="$1"
  RET_SERVER_IP=$(podman inspect --format "{{.NetworkSettings.IPAddress}}" "$SERVER_NAME")
  [ "$RET_SERVER_IP" == "" ] && RET_SERVER_IP=$(podman inspect --format "{{.NetworkSettings.Networks.myCNI.IPAddress}}" "$SERVER_NAME")
}

wait_mysql_ready() {
  local SERVER_NAME="$1"
  get_ip "$SERVER_NAME"
  local SERVER_IP="$RET_SERVER_IP"
  podman run --name "$SERVER_NAME"-wait-ready --network myCNI --rm -i \
    --entrypoint '' \
    -e LEADER_HOST="$SERVER_IP" -e LEADER_USER=root -e LEADER_PASSWORD=secret \
    "$MYSQL_IMG" bash -e <<'WAIT_READY_EOF'
create_client_my_cnf() {
  local FILE="$1"
  local HOST="$2"
  local USER="$3"
  local PASS="$4"

  cat > /tmp/"$FILE".cnf <<EOF
[client]
host="$HOST"
user="$USER"
password="$PASS"
EOF
}

wait_until_mysql_ready() {
  local FILE="$1"
  until mysql --defaults-file=/tmp/"$FILE".cnf --silent --connect-timeout=30 --wait -e "SELECT 1;" > /dev/null 2>&1 ; do sleep 5 ; done
}

create_client_my_cnf leader "$LEADER_HOST" "$LEADER_USER" "$LEADER_PASSWORD"
wait_until_mysql_ready leader
WAIT_READY_EOF
}


run_mysql() {
  local SERVER_ID="$1"
  local SERVER_NAME="$2"

  podman run --name "$SERVER_NAME" --network myCNI -d --restart=always \
    -v "$PWD"/sampledb/world:/docker-entrypoint-initdb.d \
    -v "$PWD"/data/"$SERVER_NAME":/var/lib/mysql \
    -e MYSQL_ROOT_HOST='%' \
    -e MYSQL_ROOT_PASSWORD=secret "$MYSQL_IMG" \
    --server-id="$SERVER_ID" --log-bin=mysqld-bin "${GTID_OPTS[@]}" --report_host="$SERVER_NAME"
}

make_snapshot_offline_copy() {
  local DST="$1"
  local SRC="$2"
  local SRC_ID="$3"

  wait_mysql_ready "$SRC"
  podman stop "$SRC"
  # podman logs "$SRC"
  podman rm "$SRC"
  if [ $UID == 0 ] ; then
    rm -rf -- data/"$DST"
    cp -a data/"$SRC" data/"$DST"
    rm -f data/"$DST"/auto.cnf
  else
    podman unshare chmod ogu+rwX -R "$PWD"/data/"$DST"
    rm -rf -- data/"$DST"
    podman unshare cp -a data/"$SRC" data/"$DST"
    podman unshare rm -f data/"$DST"/auto.cnf
  fi
  run_mysql "$SRC_ID" "$SRC"
}



if [ "x$RUN" != x ] ; then

  podman network create myCNI
  if ! [ -d data ] ; then
    mkdir data
    [ "$SELINUX" == 1 ] && sudo chcon -R -t container_file_t data sampledb
  fi
  mkdir -p data/node0 data/node1
  chmod o+rw data/node0 data/node1
  if [ $UID == 0 ] ; then
    chown 1001:1001 -R "$PWD"/data
  else
    podman unshare chown 1001:1001 -R "$PWD"/data
  fi

  if ! [ -d sampledb/world ] ; then
    mkdir -p sampledb/world
    curl -sL -o sampledb/world/world.sql.gz https://downloads.mysql.com/docs/world.sql.gz
    gunzip sampledb/world/world.sql.gz
  fi

  if [ "$GTID" = 1 ] ; then
    GTID_OPTS=(--log-slave-updates --enforce_gtid_consistency=ON --gtid_mode=ON)
  fi

  [ "$MYSQL_IMG" = "" ] && MYSQL_IMG=mysql:latest
  MYSQL_IMG="${PODMAN_HUB}${MYSQL_IMG}"

  run_mysql 51 node0

  if [ "$SNAPSHOT" = 1 ] ; then
    make_snapshot_offline_copy node1 node0 51
  fi

  run_mysql 52 node1

  get_ip node0
  LEADER_IP="$RET_SERVER_IP"
  get_ip node1
  FOLLOWER_IP="$RET_SERVER_IP"

  podman run --name node1-slave-setup --network myCNI -i \
    --entrypoint '' \
    -e LEADER_HOST="$LEADER_IP" -e LEADER_USER=root -e LEADER_PASSWORD=secret -e FOLLOWER_HOST="$FOLLOWER_IP" -e FOLLOWER_USER=root -e FOLLOWER_PASSWORD=secret \
    "$MYSQL_IMG" bash -e < tools/setup_mysql_replication.sh

fi


if [ "x$DESTROY" != x ] ; then
  podman rm -fa && true
  podman network rm -f myCNI && true
  if [ $UID != 0 ] ; then
    podman unshare chmod ogu+rwX -R "$PWD"/data
  fi
  rm -rf -- data/*
fi
