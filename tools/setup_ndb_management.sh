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
MY_NODE_ID=0

for n in $(echo "$MGMT_NODES"|tr , '\n')
do
  if [[ $n == $(node_ip.sh) ]] ; then
    MY_NODE_ID=$NODE_ID
  fi

  cat >> /var/lib/mysql-cluster/config.ini <<EOF
[ndb_mgmd]
# Management process options:
HostName=$n                    # Hostname or IP address of management node
NodeId=$NODE_ID                # Node ID for this management node
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
NodeId=$NODE_ID                        # Node ID for this sql node
EOF
  (( NODE_ID++ ))
done


#ndb_mgmd --initial -f /var/lib/mysql-cluster/config.ini

cat > /etc/systemd/system/ndb_mgmd.service <<EOF
[Unit]
Description=MySQL Cluster Management Node
After=network.target
Documentation=man:ndb_mgmd(8)
Documentation=https://dev.mysql.com/doc/refman/5.7/en/mysql-cluster.html

[Service]
Type=forking
EnvironmentFile=-/etc/sysconfig/ndb_mgmd
ExecStart=/usr/sbin/ndb_mgmd \$NDBMTD_OPTIONS
Restart=no

[Install]
WantedBy=multi-user.target
EOF

#cat > /etc/sysconfig/ndb_mgmd <<EOF
#NDBMTD_OPTIONS="--ndb-connectstring=$MGMT_NODES --ndb-nodeid=$MY_NODE_ID"
#EOF

cat > /etc/sysconfig/ndb_mgmd <<EOF
NDBMTD_OPTIONS="--initial -f /var/lib/mysql-cluster/config.ini --ndb-nodeid=$MY_NODE_ID"
EOF

systemctl daemon-reload
