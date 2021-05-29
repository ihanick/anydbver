#!/bin/bash
MGMT_NODES="$1"
CNF_FILE="$2"

cat >> "$CNF_FILE" <<EOF
[mysqld]
ndbcluster
[mysql_cluster]
ndb-connectstring=$MGMT_NODES
EOF


touch /root/ndb.sql.configured
