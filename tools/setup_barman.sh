#!/bin/bash
METHOD="$1"
PG_SERVER="$2"
USER="$3"
PASSWORD="$4"
SSH="ssh -i /vagrant/secret/id_rsa -o StrictHostKeyChecking=no"
HOSTNAME=$($SSH "$PG_SERVER" hostname)
CONF_FILE=/etc/barman/conf.d/"$HOSTNAME".conf
BARMAN_SERVER=$(node_ip.sh)
if [[ "$HOSTNAME" == "" ]]; then
  exit 1
fi

if [[ ! -f "$CONF_FILE" ]]; then
  cp /etc/barman/conf.d/ssh-server.conf-template "$CONF_FILE"
  sed -i \
    -e "s/ssh_command = ssh postgres@pg/ssh_command = ssh postgres@$PG_SERVER/" \
    -e "s/conninfo = host=pg user=barman dbname=postgres/conninfo = host=$HOSTNAME user=$USER dbname=postgres password=$PASSWORD/" \
    -e "s/\\[ssh\\]/[$HOSTNAME]/" \
    "$CONF_FILE"
  if [[ ! -f ~barman/.ssh/id_rsa.pub ]]; then
    mkdir -p ~barman/.ssh
    chown barman:barman ~barman/.ssh
    chmod 0700 ~barman/.ssh
    sudo -u barman ssh-keygen -t rsa -b 2048 -q -N "" -f ~barman/.ssh/id_rsa
  fi
  SSH_PUB=$(cat ~barman/.ssh/id_rsa.pub)

  $SSH "$PG_SERVER" <<EOF
until sudo -u postgres psql -c "SELECT 1"; do
  sleep 1
done
mkdir -p ~postgres/.ssh
echo "$SSH_PUB" >> ~postgres/.ssh/authorized_keys
chown -R postgres:postgres ~postgres/.ssh
chmod 0700 ~postgres/.ssh
chmod 0600 ~postgres/.ssh/authorized_keys
dnf install -y barman-cli
sudo -u postgres ssh-keygen -t rsa -b 2048 -q -N "" -f ~postgres/.ssh/id_rsa
EOF
  sudo -u barman bash -c "ssh -o StrictHostKeyChecking=no postgres@$PG_SERVER cat .ssh/id_rsa.pub >>~/.ssh/authorized_keys"
  chmod 0600 ~barman/.ssh/authorized_keys
  sudo -u barman bash -c "ssh -o StrictHostKeyChecking=no postgres@$PG_SERVER ssh -o StrictHostKeyChecking=no barman@$BARMAN_SERVER true"
  systemctl enable crond
  systemctl start crond
  sudo -u barman ssh -o StrictHostKeyChecking=no postgres@"$PG_SERVER" psql <<EOF
ALTER SYSTEM SET archive_command = 'barman-wal-archive --md5 -U barman $BARMAN_SERVER $HOSTNAME %p';
ALTER SYSTEM SET archive_mode = on;
EOF
  $SSH "$PG_SERVER" <<EOF
  bash -c 'systemctl restart $(basename /usr/lib/systemd/system/postgresql-*.service)'
EOF
  sudo -u barman ssh -o StrictHostKeyChecking=no postgres@"$PG_SERVER" psql <<EOF
CHECKPOINT;
SELECT pg_switch_wal();
EOF
  touch /root/barman_configured
fi
