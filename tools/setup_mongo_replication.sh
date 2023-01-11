#!/bin/bash
REPLICATION_SET=$1
USR=$2
PASS=$3
PRIMARY=$4
SERVER_ID=$(ip addr ls|grep 'inet '|grep -v '127.0.0.1'|awk '{print $2}'|cut -d/ -f 1|awk -F '\\.' '{print ($1 * 2^24) + ($2 * 2^16) + ($3 * 2^8) + $4}')

MONGO=/usr/bin/mongo;
test -f $MONGO || MONGO=/usr/bin/mongosh;

if [[ "x$PRIMARY" == "x" ]] ; then
  until $MONGO --eval 'print("waited for connection")' &>/dev/null ; do sleep 2 ; done
  if grep -q 'clusterRole: configsvr' /etc/mongod.conf ; then
    $MONGO "mongodb://$USR:$PASS@127.0.0.1:27017/admin" --eval 'rs.initiate( { _id : "'$REPLICATION_SET'", configsvr: true, members: [ { _id: 0, host: "'$( hostname -I | cut -d' ' -f1 )':27017" }, ] })'
  else
    $MONGO "mongodb://$USR:$PASS@127.0.0.1:27017/admin" --eval 'rs.initiate( { _id : "'$REPLICATION_SET'", members: [ { _id: 0, host: "'$( hostname -I | cut -d' ' -f1 )':27017" }, ] })'
  fi
else
  # wait until local mongod become ready
  until $MONGO --eval 'print("waited for connection")' &>/dev/null ; do sleep 2 ; done
  until $MONGO "mongodb://$USR:$PASS@$PRIMARY:27017/admin" --eval 'rs.status()' | grep -q PRIMARY ; do sleep 2 ; done
  $MONGO "mongodb://$USR:$PASS@$PRIMARY:27017/admin" --eval 'rs.add({ host:"'$( hostname -I | cut -d' ' -f1 )':27017"})'
fi
touch /root/${REPLICATION_SET}.init
