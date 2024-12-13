#!/bin/bash
METHOD="$1"
PG_SERVER="$2"
USER="$3"
PASSWORD="$4"
SSH="ssh -i /vagrant/secret/id_rsa -o StrictHostKeyChecking=no"
HOSTNAME=$($SSH "$PG_SERVER" hostname)
CONF_DIR=/etc/barman/conf.d
if [[ ! -d $CONF_DIR ]]; then
  CONF_DIR=/etc/barman.d
fi
CONF_FILE=$CONF_DIR/"$HOSTNAME".conf
BARMAN_SERVER=$(node_ip.sh)
PG_BIN=$(ls -d /usr/pgsql-*/bin 2>/dev/null)
if [[ "$HOSTNAME" == "" ]]; then
  exit 1
fi

wait_pg_ready() {
  $SSH "$PG_SERVER" <<EOF
until sudo -u postgres psql -c "SELECT 1"; do
  sleep 1
done
EOF
}

setup_barman_to_pg_ssh_key() {
  if [[ ! -f ~barman/.ssh/id_rsa.pub ]]; then
    mkdir -p ~barman/.ssh
    chown barman:barman ~barman/.ssh
    chmod 0700 ~barman/.ssh
    sudo -u barman ssh-keygen -t rsa -b 2048 -q -N "" -f ~barman/.ssh/id_rsa
  fi
  SSH_PUB=$(cat ~barman/.ssh/id_rsa.pub)

  $SSH "$PG_SERVER" <<EOF
mkdir -p ~postgres/.ssh
echo "$SSH_PUB" >> ~postgres/.ssh/authorized_keys
chown -R postgres:postgres ~postgres/.ssh
chmod 0700 ~postgres/.ssh
chmod 0600 ~postgres/.ssh/authorized_keys
EOF
}

setup_pg_to_barman_ssh_key() {
  $SSH "$PG_SERVER" <<EOF
mkdir -p ~postgres/.ssh
chown -R postgres:postgres ~postgres/.ssh
chmod 0700 ~postgres/.ssh
sudo -u postgres ssh-keygen -t rsa -b 2048 -q -N "" -f ~postgres/.ssh/id_rsa
EOF
  sudo -u barman bash -c "ssh -o StrictHostKeyChecking=no postgres@$PG_SERVER cat .ssh/id_rsa.pub >>~/.ssh/authorized_keys"
  chmod 0600 ~barman/.ssh/authorized_keys
  sudo -u barman bash -c "ssh -o StrictHostKeyChecking=no postgres@$PG_SERVER ssh -o StrictHostKeyChecking=no barman@$BARMAN_SERVER true"
}

install_barman_cli_on_pg() {
  $SSH "$PG_SERVER" <<EOF
dnf install -y barman-cli
EOF
}

enable_archiving() {
  sudo -u barman ssh -o StrictHostKeyChecking=no postgres@"$PG_SERVER" psql <<EOF
ALTER SYSTEM SET archive_command = '$1';
ALTER SYSTEM SET archive_mode = on;
EOF
  $SSH "$PG_SERVER" <<EOF
  bash -c 'systemctl restart $(basename /usr/lib/systemd/system/postgresql-*.service)'
EOF
}

switch_wal() {
  $SSH "$PG_SERVER" sudo -u postgres psql <<EOF
CHECKPOINT;
SELECT pg_switch_wal();
EOF
}

if [[ -f "$CONF_FILE" ]]; then
  exit 0
fi

systemctl enable crond
systemctl start crond

if [[ $METHOD == "streaming-only" ]]; then
  if [[ "$PG_BIN" == "" ]]; then
    dnf install -y postgresql-server
    PG_BIN=/usr/bin
  fi
  cp $CONF_DIR/streaming-server.conf-template "$CONF_FILE"
  sed -i \
    -e "s/conninfo = host=pg user=barman dbname=postgres/conninfo = host=$PG_SERVER user=$USER dbname=postgres password=$PASSWORD/" \
    -e "s/streaming_conninfo = host=pg user=streaming_barman/conninfo = host=$PG_SERVER user=$USER dbname=postgres password=$PASSWORD/" \
    -e "s/\\[streaming-server\\]/[$HOSTNAME]/" \
    "$CONF_FILE"
  echo 'path_prefix = "'$PG_BIN'"' >>"$CONF_FILE"
  echo 'create_slot = auto' >>"$CONF_FILE"
  sudo -u barman barman receive-wal --create-slot $HOSTNAME
  sleep 60
  switch_wal
else
  cp $CONF_DIR/ssh-server.conf-template "$CONF_FILE"
  sed -i \
    -e "s/ssh_command = ssh postgres@pg/ssh_command = ssh postgres@$PG_SERVER/" \
    -e "s/conninfo = host=pg user=barman dbname=postgres/conninfo = host=$HOSTNAME user=$USER dbname=postgres password=$PASSWORD/" \
    -e "s/\\[ssh\\]/[$HOSTNAME]/" \
    "$CONF_FILE"
  wait_pg_ready
  setup_barman_to_pg_ssh_key
  setup_pg_to_barman_ssh_key
  install_barman_cli_on_pg
  enable_archiving "barman-wal-archive --md5 -U barman $BARMAN_SERVER $HOSTNAME %p"
  switch_wal
fi

touch /root/barman_configured
