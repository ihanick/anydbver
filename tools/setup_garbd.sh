#!/bin/bash
MASTER_IP=$1
MASTER_USER=$2
MASTER_PASSWORD=$3
CLUSTER_NAME=${4:-'pxc-cluster'}

sed -i -r \
  -e '/REMOVE THIS AFTER CONFIGURATION/d' \
  -e 's/^.*GALERA_NODES=.*$/GALERA_NODES="'$( \
    mysql -N -u $MASTER_USER \
      --password=$MASTER_PASSWORD \
      --host=$MASTER_IP \
      -e "show status like 'wsrep_incoming_addresses'\G" 2>/dev/null | \
    tail -n 1|sed -e 's/:3306//g')'"/' \
  -e 's/^.*GALERA_GROUP=.*$/GALERA_GROUP="'$CLUSTER_NAME'"/' /etc/sysconfig/garb


if test -f /vagrant/secret/"${CLUSTER_NAME}-ssl.tar.gz" ; then
  tar -C / -xzf /vagrant/secret/"${CLUSTER_NAME}-ssl.tar.gz"
  mkdir /etc/ssl/galera
  cp /var/lib/mysql/ca.pem /etc/ssl/galera/ca-cert.pem
  cp /var/lib/mysql/server-* /etc/ssl/galera/
  chown nobody:nobody /etc/ssl/galera/*
  sed -i -e 's,^.*GALERA_OPTIONS=.*$,GALERA_OPTIONS="socket.ssl=yes;socket.ssl_key=/etc/ssl/galera/server-key.pem;socket.ssl_cert=/etc/ssl/galera/server-cert.pem;socket.ssl_ca=/etc/ssl/galera/ca-cert.pem;socket.ssl_cipher=AES128-SHA256",' /etc/sysconfig/garb
fi

grep -q -F 'cd /tmp' /usr/bin/garb-systemd || sed -i '1 a cd /tmp' /usr/bin/garb-systemd
systemctl start garb
touch /root/garbd.configured
