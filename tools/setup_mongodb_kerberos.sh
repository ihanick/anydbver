#!/bin/bash
SAMBA_IP="$1"
ADMIN_PASSWORD="${2:-MyPassword2026}"
REALM=EXAMPLE.NET
SSH_OPTS="-o StrictHostKeyChecking=no -i /vagrant/secret/id_rsa"
HOSTNAME=$(hostname)

# Install Kerberos client
if command -v dnf &>/dev/null || command -v yum &>/dev/null; then
  yum -y install krb5-workstation
elif command -v apt-get &>/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt-get -y install krb5-user
fi

# Wait for Samba to be ready (handles race condition with strategy: free)
for i in $(seq 1 60); do
  if ssh $SSH_OPTS root@${SAMBA_IP} "test -f /root/kerberos-samba.configured" 2>/dev/null; then
    break
  fi
  sleep 5
done

# Get krb5.conf from Samba node and add local hostname mapping
scp $SSH_OPTS root@${SAMBA_IP}:/etc/krb5.conf /etc/krb5.conf
echo "    ${HOSTNAME} = ${REALM}" >> /etc/krb5.conf

# Create service principal on Samba node (use fixed password for service account, db password may be too short for Samba policy)
SVC_PASSWORD="SvcPassword2026"
ssh $SSH_OPTS root@${SAMBA_IP} "samba-tool user create mongodbsvc_${HOSTNAME} '${SVC_PASSWORD}' 2>/dev/null; \
  samba-tool spn add mongodb/${HOSTNAME} mongodbsvc_${HOSTNAME}; \
  samba-tool domain exportkeytab /root/${HOSTNAME}_mongodb.keytab --principal=mongodb/${HOSTNAME}"

# Copy keytab and set ownership for mongod
scp $SSH_OPTS root@${SAMBA_IP}:/root/${HOSTNAME}_mongodb.keytab /etc/mongodb.keytab
chown mongod:mongod /etc/mongodb.keytab
chmod 0600 /etc/mongodb.keytab

# Set KRB5_KTNAME via systemd drop-in so mongod can find the keytab
mkdir -p /etc/systemd/system/mongod.service.d
cat > /etc/systemd/system/mongod.service.d/krb5.conf << EOF
[Service]
Environment="KRB5_KTNAME=/etc/mongodb.keytab"
EOF
systemctl daemon-reload

# Wait for MongoDB to be ready
MONGO=/usr/bin/mongo
test -f $MONGO || MONGO=/usr/bin/mongosh
systemctl start mongod || true
until $MONGO --eval 'print("waited for connection")' &>/dev/null ; do sleep 2 ; done

# Create GSSAPI user (use dba credentials if auth is already enabled)
MONGO_AUTH=""
if [ -f /root/.mongorc.js ]; then
  MONGO_AUTH="mongodb://dba:${ADMIN_PASSWORD}@127.0.0.1:27017/admin"
fi
if [ -n "$MONGO_AUTH" ]; then
  $MONGO "$MONGO_AUTH" --eval 'db.getSiblingDB("$external").createUser({user: "dbauser01@'$REALM'", roles: [{role: "root", db: "admin"}]})'
else
  $MONGO admin --eval 'db.getSiblingDB("$external").createUser({user: "dbauser01@'$REALM'", roles: [{role: "root", db: "admin"}]})'
fi

# Stop MongoDB before config changes
systemctl stop mongod

# Configure mongod.conf for GSSAPI
/vagrant/tools/yq -i '.net.bindIp = "0.0.0.0"' /etc/mongod.conf
/vagrant/tools/yq -i '.security.authorization = "enabled"' /etc/mongod.conf
/vagrant/tools/yq -i '.setParameter.authenticationMechanisms = "SCRAM-SHA-1,SCRAM-SHA-256,GSSAPI"' /etc/mongod.conf

# Restart MongoDB with new config
systemctl start mongod

touch /root/kerberos-mongodb.configured
