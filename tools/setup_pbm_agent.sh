#!/bin/bash
RS="$1"
S3_URL="$2"
if [ "x$RS" = "x" ] ; then
  RS=$(yq r /etc/mongod.conf  replication.replSetName)
fi
sed -i -e 's|backupUser:backupPassword@localhost:27017|dba:secret@127.0.0.1:27017|g' -e "s|replicaSet=rs1|replicaSet=$RS|g" /etc/sysconfig/pbm-agent

source /etc/sysconfig/pbm-agent
export PBM_MONGODB_URI


systemctl daemon-reload


if [ "x${S3_URL}" = "x" ] ; then
  [ -d /nfs/local_backups ] || mkdir /nfs/local_backups
  chown mongod:mongod /nfs/local_backups
  cat > pbm_config.yaml <<EOF
storage:
  type: filesystem
  filesystem:
    path: /nfs/local_backups
EOF
else
  proto="$(echo $S3_URL|sed -re 's,^(https?://)([^:@/]*):([^@]*)@([^:/]+):([^/]+)/([^/]+),\1|\2|\3|\4|\5|\6|,' | cut -d\| -f 1)"
  user="$(echo $S3_URL|sed -re 's,^(https?://)([^:@/]*):([^@]*)@([^:/]+):([^/]+)/([^/]+),\1|\2|\3|\4|\5|\6|,' | cut -d\| -f 2)"
  pass="$(echo $S3_URL|sed -re 's,^(https?://)([^:@/]*):([^@]*)@([^:/]+):([^/]+)/([^/]+),\1|\2|\3|\4|\5|\6|,' | cut -d\| -f 3)"
  host="$(echo $S3_URL|sed -re 's,^(https?://)([^:@/]*):([^@]*)@([^:/]+):([^/]+)/([^/]+),\1|\2|\3|\4|\5|\6|,' | cut -d\| -f 4)"
  port="$(echo $S3_URL|sed -re 's,^(https?://)([^:@/]*):([^@]*)@([^:/]+):([^/]+)/([^/]+),\1|\2|\3|\4|\5|\6|,' | cut -d\| -f 5)"
  bucket="$(echo $S3_URL|sed -re 's,^(https?://)([^:@/]*):([^@]*)@([^:/]+):([^/]+)/([^/]+),\1|\2|\3|\4|\5|\6|,' | cut -d\| -f 6)"
  cat > pbm_config.yaml <<EOF
storage:
  type: s3
  s3:
    endpointUrl: "$proto$host:$port"
    region: my-region
    bucket: $bucket
    prefix: data/pbm/test
    credentials:
      access-key-id: $user
      secret-access-key: $pass
EOF
fi

if ! grep -q pbm-agent ~/.bashrc ; then
cat >> ~/.bashrc <<EOF
source /etc/sysconfig/pbm-agent
export PBM_MONGODB_URI
EOF

fi

cp pbm_config.yaml /etc/pbm-storage.conf

nohup bash -c "until pgrep -xn pbm-agent ; do systemctl start pbm-agent; sleep 5; done ; pbm config --file pbm_config.yaml" &> /root/pbm-start.log & disown
