#!/bin/bash
USR=root
PASS=secret
until mongo "mongodb://$USR:$PASS@$SERVER_IP:27017/admin" --eval 'print("waited for connection")' &>/dev/null ; do sleep 2 ; done
if [[ "$PRIMARY_IP" == "" ]] ; then
  mongo "mongodb://$USR:$PASS@$SERVER_IP:27017/admin" --eval 'rs.initiate( { _id : "'$REPLICATION_SET'", members: [ { _id: 0, host: "'"$SERVER_IP"':27017" }, ] })'
else
  until mongo "mongodb://$USR:$PASS@$PRIMARY_IP:27017/admin" --eval 'print("waited for connection")' &>/dev/null ; do sleep 2 ; done
  mongo "mongodb://$USR:$PASS@$PRIMARY_IP:27017/admin" --eval 'rs.add({ host: "'"$SERVER_IP"':27017" })'
fi
