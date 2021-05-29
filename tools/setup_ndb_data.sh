#!/bin/bash
MGMT_NODES="$1"

mkdir -p /usr/local/mysql/data

cat > /etc/systemd/system/ndbmtd.service <<EOF
[Unit]
Description=MySQL Cluster Data Node
After=network.target
Documentation=man:ndbmtd(8)
Documentation=https://dev.mysql.com/doc/refman/5.7/en/mysql-cluster.html

[Service]
Type=forking
EnvironmentFile=-/etc/sysconfig/ndbmtd
ExecStart=/usr/sbin/ndbmtd \$NDBMTD_OPTIONS
Restart=no

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/sysconfig/ndbmtd <<EOF
NDBMTD_OPTIONS="--ndb-connectstring=$MGMT_NODES"
EOF

systemctl daemon-reload

touch /root/ndb.data.configured
