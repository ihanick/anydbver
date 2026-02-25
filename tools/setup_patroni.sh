#!/bin/bash
CLUSTER="$1"
SECRET="$2"
NODE_IP=$(node_ip.sh)
LOCAL_NET=$(ip --brief addr ls|grep -F $NODE_IP|head -n 1|awk '{print $3}')
FIRST_SERVER="$3"
STANDBY="$4"
source /etc/etcd/etcd.conf

PATRONI_CFG=/etc/patroni/${ETCD_NAME}.yml

PG_BIN=$(ls -d /usr/pgsql-*/bin|tail -n 1)
PG_DATA=$(ls -d /var/lib/pgsql/*/data|tail -n 1)

export PATH=$PATH:$PG_BIN

PATRONI_PATH=$(ls /usr/bin/patroni /usr/local/bin/patroni 2>/dev/null|head -n 1)

localectl set-locale LANG=en_US.UTF-8

mkdir /etc/patroni
chown postgres:postgres /etc/patroni

mkdir -p /home/postgres/archived

# Detect pgbackrest for archive commands
if [ -f /usr/bin/pgbackrest ] || [ -f /usr/sbin/pgbackrest ]; then
    ARCHIVE_CMD="pgbackrest --stanza=db archive-push %p"
    RESTORE_CMD="test -x /usr/bin/pgbackrest && pgbackrest --stanza=db archive-get %f %p || exit 1"
else
    ARCHIVE_CMD="cp -f %p /home/postgres/archived/%f"
    RESTORE_CMD="cp /home/postgres/archived/%f %p"
fi

cat > /tmp/pgpass0 << EOF
*:*:*:*:$SECRET
EOF
chown postgres:postgres -R /tmp/pgpass0
chmod 0600 /tmp/pgpass0


PG_BIN=$(ls -d /usr/pgsql-*/bin)
echo "export PATH=/usr/local/sbin:/usr/local/bin:$PG_BIN:/usr/sbin:/usr/bin" >> /etc/profile.d/sh.local

cat > /usr/local/bin/setup_cluster.sh << EOF
#!/bin/bash
export PGPASSFILE=/tmp/pgpass0
export PATH=/usr/local/sbin:/usr/local/bin:$PG_BIN:/usr/sbin:/usr/bin
until psql -U postgres -d postgres -h localhost -c '\l'; do sleep 1; done
psql -U postgres -d postgres -h localhost -c "CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '${SECRET}';"
EOF

chmod +x /usr/local/bin/setup_cluster.sh

# setup_cluster.sh is called by Patroni's post_init hook after bootstrap
# Don't call it directly here - PostgreSQL is not running yet

if [[ ${STANDBY} != "" ]]; then
	STANDBY_CONF="
    standby_cluster:
      host: ${STANDBY}
      port: 5432"
    # Wait for primary cluster to be ready with replicator user
    echo "Waiting for primary cluster at ${STANDBY} to be ready..."
    export PGPASSFILE=/tmp/pgpass0
    for i in {1..120}; do
        if psql -U replicator -h ${STANDBY} -d postgres -c "SELECT 1" &>/dev/null; then
            echo "Primary cluster is ready"
            break
        fi
        echo "Attempt $i: Primary not ready yet, waiting..."
        sleep 5
    done
else
   STANDBY_CONF=""
fi

cat > /etc/patroni/${ETCD_NAME}.yml << EOF
scope: ${CLUSTER}
#namespace: /service/
name: ${ETCD_NAME}
restapi:
 listen: 0.0.0.0:8008
 connect_address: ${NODE_IP}:8008
etcd3:
 host: ${NODE_IP}:2379
bootstrap:
 # this section will be written into Etcd:/<namespace>/<scope>/config after initializing new cluster
 # and all other cluster members will use it as a global configuration
 dcs:${STANDBY_CONF}
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
#   master_start_timeout: 300
#   synchronous_mode: false
    postgresql:
     use_pg_rewind: true
     use_slots: true
     parameters:
       wal_level: replica
       hot_standby: "on"
       max_wal_senders: 10
       max_replication_slots: 10
       wal_log_hints: "on"
       archive_mode: "on"
       archive_timeout: 600s
       archive_command: "${ARCHIVE_CMD}"
     recovery_conf:
       restore_command: "${RESTORE_CMD}"
 # some desired options for 'initdb'
 initdb:  # Note: It needs to be a list (some options need values, others are switches)
 - encoding: UTF8
 - data-checksums
 pg_hba:  # Add following lines to pg_hba.conf after running 'initdb'
 - host replication replicator $LOCAL_NET md5
 - host replication replicator 0.0.0.0/0 md5
 - host replication replicator 127.0.0.1/32 trust
 - host all all $LOCAL_NET md5
 - host all all 0.0.0.0/0 md5
#  - hostssl all all 0.0.0.0/0 md5
# Additional script to be launched after initial cluster creation (will be passed the connection URL as parameter)
 post_init: /usr/local/bin/setup_cluster.sh
# Some additional users users which needs to be created after initializing new cluster
 users:
    admin:
     password: $SECRET
     options:
       - createrole
       - createdb
postgresql:
 listen: 0.0.0.0:5432
 connect_address: ${NODE_IP}:5432
 data_dir: "${PG_DATA}"
 bin_dir: "${PG_BIN}"
#  config_dir:
 pgpass: /tmp/pgpass0
 authentication:
    replication:
     username: replicator
     password: $SECRET
    superuser:
     username: postgres
     password: $SECRET
 parameters:
    unix_socket_directories: '/var/run/postgresql'
watchdog:
 mode: off
#watchdog:
# mode: required # Allowed values: off, automatic, required
# device: /dev/watchdog
# safety_margin: 5
tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false
EOF

chown postgres:postgres -R /home/postgres/archived /etc/patroni/${ETCD_NAME}.yml
chmod 0600 -R /home/postgres/archived /etc/patroni/${ETCD_NAME}.yml

echo "export PATRONICTL_CONFIG_FILE=/etc/patroni/${ETCD_NAME}.yml" >> /etc/profile



cat > /etc/systemd/system/patroni.service << EOF
# This is an example systemd config file for Patroni
# You can copy it to "/etc/systemd/system/patroni.service",

[Unit]
Description=Runners to orchestrate a high-availability PostgreSQL
After=syslog.target network.target

[Service]
Type=simple

User=postgres
Group=postgres

# Read in configuration file if it exists, otherwise proceed
EnvironmentFile=-/etc/patroni_env.conf

# the default is the user's home directory, and if you want to change it, you must provide an absolute path.
# WorkingDirectory=/home/sameuser

# Where to send early-startup messages from the server
# This is normally controlled by the global default set by systemd
#StandardOutput=syslog

# Pre-commands to start watchdog device
# Uncomment if watchdog is part of your patroni setup
#ExecStartPre=-/usr/bin/sudo /sbin/modprobe softdog
#ExecStartPre=-/usr/bin/sudo /bin/chown postgres /dev/watchdog

# Start the patroni process
ExecStart=$PATRONI_PATH $PATRONI_CFG

# Send HUP to reload from patroni.yml
ExecReload=/bin/kill -s HUP $MAINPID

# only kill the patroni process, not it's children, so it will gracefully stop postgres
KillMode=process

# Give a reasonable amount of time for the server to start up/shut down
TimeoutSec=30

# Do not restart the service if it crashes, we want to manually inspect database on failure
Restart=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl start patroni

touch /root/patroni.configured
