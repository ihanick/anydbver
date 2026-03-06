#!/bin/bash
SAMBA_IP="$1"
ADMIN_PASSWORD="${2:-MyPassword2026}"
PGVER="${3:-17}"
REALM=EXAMPLE.NET
SSH_OPTS="-o StrictHostKeyChecking=no -i /vagrant/secret/id_rsa"
HOSTNAME=$(hostname)
PG_DATA_DIR="/var/lib/pgsql/${PGVER}/data"

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
ssh $SSH_OPTS root@${SAMBA_IP} "samba-tool user create postgressvc_${HOSTNAME} '${SVC_PASSWORD}' 2>/dev/null; \
  samba-tool spn add postgres/${HOSTNAME} postgressvc_${HOSTNAME}; \
  samba-tool domain exportkeytab /root/${HOSTNAME}_postgres.keytab --principal=postgres/${HOSTNAME}"

# Copy keytab
scp $SSH_OPTS root@${SAMBA_IP}:/root/${HOSTNAME}_postgres.keytab /etc/postgres.keytab
chown postgres:postgres /etc/postgres.keytab
chmod 0600 /etc/postgres.keytab

# Add GSS authentication to pg_hba.conf (insert before existing host lines)
sed -i '1i host    all             all             0.0.0.0/0            gss include_realm=0 krb_realm=EXAMPLE.NET' ${PG_DATA_DIR}/pg_hba.conf

# Add keytab path to postgresql.conf
echo "krb_server_keyfile = '/etc/postgres.keytab'" >> ${PG_DATA_DIR}/postgresql.conf

# Restart PostgreSQL
systemctl restart postgresql-${PGVER}

# Create Kerberos user in PostgreSQL (after restart so PG is running)
until sudo -u postgres psql -c "SELECT 1" &>/dev/null; do sleep 1; done
sudo -u postgres psql -c "CREATE USER dbauser01" 2>/dev/null || true

touch /root/kerberos-pg.configured
