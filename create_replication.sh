#!/bin/bash

if [ "x$RUN" != x ] ; then

  podman network create myCNI
  mkdir -p data/node0 data/node1
  chmod o+rw data/node0 data/node1

  if ! [ -d sampledb/world ] ; then
    mkdir -p sampledb/world
    curl -sL -o sampledb/world/world.sql.gz https://downloads.mysql.com/docs/world.sql.gz
  fi

  if [ "$GTID" = 1 ] ; then
    GTID_OPTS=(--log-slave-updates --enforce_gtid_consistency=ON --gtid_mode=ON)
  fi

  [ "$MYSQL_IMG" = "" ] && MYSQL_IMG=mysql:latest
  podman run --name node0 --network myCNI -d --restart=always \
    -v "$PWD"/sampledb/world:/docker-entrypoint-initdb.d \
    -v "$PWD"/data/node0:/var/lib/mysql \
    -e MYSQL_ROOT_PASSWORD=secret "$MYSQL_IMG" \
    --server-id=51 --log-bin=mysqld-bin "${GTID_OPTS[@]}" --report_host=node0

  podman run --name node1 --network myCNI -d --restart=always \
    -v "$PWD"/data/node1:/var/lib/mysql \
    -e MYSQL_ROOT_PASSWORD=secret "$MYSQL_IMG" \
    --server-id=52 --log-bin=mysqld-bin "${GTID_OPTS[@]}" --report_host=node1


  podman run --name node1-slave-setup --network myCNI -d \
    -v "$PWD"/tools:/tools --entrypoint '' \
    -e LEADER_HOST=node0 -e LEADER_USER=root -e LEADER_PASSWORD=secret -e FOLLOWER_HOST=node1 -e FOLLOWER_USER=root -e FOLLOWER_PASSWORD=secret \
    "$MYSQL_IMG" bash -e /tools/setup_mysql_replication.sh

fi


if [ "x$DESTROY" != x ] ; then
  podman rm -fa
  podman network rm myCNI
  sudo rm -rf data/node*
fi
