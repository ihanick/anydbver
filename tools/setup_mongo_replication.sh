#!/bin/bash
USR=root
PASS=secret
until mongo "mongodb://$USR:$PASS@$SERVER_IP:27017/admin" --eval 'print("waited for connection")' &>/dev/null ; do sleep 2 ; done

mongo "mongodb://$USR:$PASS@$SERVER_IP:27017/admin" --eval 'rs.initiate( { _id : "'$REPLICATION_SET'", members: [ { _id: 0, host: "'"$SERVER_IP"':27017" }, ] })'
