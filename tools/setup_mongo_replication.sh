#!/bin/bash
REPLICATION_SET=$1
USR=$2
PASS=$3
PRIMARY=$4
SERVER_ID=$(ip addr ls|grep 'inet '|grep -v '127.0.0.1'|awk '{print $2}'|cut -d/ -f 1|awk -F '\\.' '{print ($1 * 2^24) + ($2 * 2^16) + ($3 * 2^8) + $4}')

if [[ "x$PRIMARY" == "x" ]] ; then
  until mongo --eval 'print("waited for connection")' &>/dev/null ; do sleep 2 ; done
  if grep -q 'clusterRole: configsvr' /etc/mongod.conf ; then
    mongo -u $USR -p "$PASS" --eval 'rs.initiate( { _id : "'$REPLICATION_SET'", configsvr: true, members: [ { _id: 0, host: "'$( hostname -I | cut -d' ' -f1 )':27017" }, ] })'
  else
    mongo -u $USR -p "$PASS" --eval 'rs.initiate( { _id : "'$REPLICATION_SET'", members: [ { _id: 0, host: "'$( hostname -I | cut -d' ' -f1 )':27017" }, ] })'
  fi
else
  # wait until local mongod become ready
  until mongo --eval 'print("waited for connection")' &>/dev/null ; do sleep 2 ; done
  mongo -u $USR -p "$PASS" --host $PRIMARY --eval 'rs.add({ host:"'$( hostname -I | cut -d' ' -f1 )':27017"})'
fi
touch /root/${REPLICATION_SET}.init
