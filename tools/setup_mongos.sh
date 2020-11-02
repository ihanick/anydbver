#!/bin/bash

USR=$1 # dba
PASS=$2 # secret
SHARDSRV=$3 # rs0/10.76.129.55:27017,10.76.129.229:27017,10.76.129.3:27017


cat > /etc/sysconfig/mongos <<EOF
OPTIONS="-f /etc/mongos.conf"
STDOUT="/var/log/mongo/mongos.stdout"
STDERR="/var/log/mongo/mongos.stderr"
NUMACTL="numactl --interleave=all"
EOF

cat > /etc/systemd/system/mongos.service <<EOF
[Unit]
Description=High-performance, schema-free document-oriented database
After=time-sync.target network.target

[Service]
Type=forking
User=mongod
Group=mongod
PermissionsStartOnly=true
LimitFSIZE=infinity
LimitCPU=infinity
LimitAS=infinity
LimitNOFILE=64000
LimitNPROC=64000
EnvironmentFile=-/etc/sysconfig/mongos
ExecStartPre=/usr/bin/percona-server-mongodb-helper.sh
ExecStart=/usr/bin/env bash -c "\${NUMACTL} /usr/bin/mongos \${OPTIONS} > \${STDOUT} 2> \${STDERR}"
PIDFile=/var/run/mongod.pid

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

KEYFILE=$(yq r /etc/mongos.conf security.keyFile)
KEYFILE_NAME=$(basename "$KEYFILE")
cp "/vagrant/secret/$KEYFILE_NAME" "$KEYFILE"
chmod 0400 "$KEYFILE"
chown mongod:mongod "$KEYFILE"

systemctl start mongos
until mongo --eval 'print("waited for connection")' &>/dev/null ; do sleep 2 ; done
mongo -u "$USR" -p "$PASS" --authenticationDatabase admin --norc mongodb://127.0.0.1:27017/admin --eval "sh.addShard('$SHARDSRV')"
