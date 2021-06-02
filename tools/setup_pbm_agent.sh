#!/bin/bash
RS="$1"
if [ "x$RS" = "x" ] ; then
  RS=$(yq r /etc/mongod.conf  replication.replSetName)
fi
sed -i -e 's|backupUser:backupPassword@localhost:27017|dba:secret@127.0.0.1:27017|g' -e "s|replicaSet=rs1|replicaSet=$RS|g" /etc/sysconfig/pbm-agent

source /etc/sysconfig/pbm-agent
export PBM_MONGODB_URI


systemctl daemon-reload

until pgrep -xn pbm-agent ; do
  systemctl start pbm-agent
  sleep 5
done


[ -d /nfs/local_backups ] || mkdir /nfs/local_backups

chown pbm:pbm /nfs/local_backups

cat > pbm_config.yaml <<EOF
storage:
  type: filesystem
  filesystem:
    path: /nfs/local_backups
EOF

if ! grep -q pbm-agent ~/.bashrc ; then
  cat >> ~/.bashrc <<EOF
source /etc/sysconfig/pbm-agent
export PBM_MONGODB_URI
EOF

fi

pbm config --file pbm_config.yaml
