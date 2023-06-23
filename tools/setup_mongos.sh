#!/bin/bash

USR=$1 # dba
PASS=$2 # secret
SHARDSRV=$3 # rs0/10.76.129.55:27017,10.76.129.229:27017,10.76.129.3:27017

KEYFILE=$(/vagrant/tools/yq .security.keyFile /etc/mongos.conf)
KEYFILE_NAME=$(basename "$KEYFILE")
cp "/vagrant/secret/$KEYFILE_NAME" "$KEYFILE"
chmod 0400 "$KEYFILE"
chown mongod:mongod "$KEYFILE"

systemctl disable mongod
systemctl stop mongod
systemctl start mongos

MONGO=/usr/bin/mongo;
test -f $MONGO || MONGO=/usr/bin/mongosh;

until $MONGO --eval 'print("waited for connection")' &>/dev/null ; do sleep 2 ; done

FULL_NEW_SEP=$(echo "$SHARDSRV"|sed -re 's|,([^/^,]+/)|;\1|g')
OLDIFS="$IFS"
IFS=";"

for SHARD_ITEM in $FULL_NEW_SEP ; do
  SRV=$(echo "$SHARD_ITEM"| sed -re 's,[^/]+/([^,]+).*,\1,')
  until $MONGO -u dba -p secret --authenticationDatabase admin --norc "mongodb://$SRV" --eval 'rs.status()' |grep -q PRIMARY ; do sleep 1; done
  $MONGO -u "$USR" -p "$PASS" --authenticationDatabase admin --norc mongodb://127.0.0.1:27017/admin --eval "sh.addShard('$SHARD_ITEM')"
done

IFS=OLDIFS

touch /root/mongos.configured
