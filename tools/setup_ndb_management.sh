#!/bin/bash
MGMT_NODES="$1"
DATA_NODES="$2"
SQL_NODES="$3"

mkdir -p /var/lib/mysql-cluster

cat > /var/lib/mysql-cluster/config.ini <<EOF
[ndbd default]
# Options affecting ndbd processes on all data nodes:
NoOfReplicas=2    # Number of fragment replicas
DataMemory=98M    # How much memory to allocate for data storage

EOF

NODE_ID=1

for n in $(echo "$MGMT_NODES"|tr , '\n')
do
  cat >> /var/lib/mysql-cluster/config.ini <<EOF
[ndb_mgmd]
# Management process options:
HostName=$n                    # Hostname or IP address of management node
DataDir=/var/lib/mysql-cluster  # Directory for management node log files
EOF
  (( NODE_ID++ ))
done

for n in $(echo "$DATA_NODES"|tr , '\n')
do
  cat >> /var/lib/mysql-cluster/config.ini <<EOF
[ndbd]
                                # (one [ndbd] section per data node)
HostName=$n                  # Hostname or IP address
NodeId=$NODE_ID                        # Node ID for this data node
DataDir=/usr/local/mysql/data   # Directory for this data node's data files
EOF
  (( NODE_ID++ ))
done

for n in $(echo "$SQL_NODES"|tr , '\n')
do
  cat >> /var/lib/mysql-cluster/config.ini <<EOF
[mysqld]
# SQL node options:
HostName=$n          # Hostname or IP address
                                # (additional mysqld connections can be
                                # specified for this node for various
                                # purposes such as running ndb_restore)
EOF
  (( NODE_ID++ ))
done


ndb_mgmd --initial -f /var/lib/mysql-cluster/config.ini
