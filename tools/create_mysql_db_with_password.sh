#!/bin/bash
PASS=$1
OLDGRANT=$2
SERVICE=$3
S='--socket=/var/lib/mysql/mysqld.sock'

if [[ "x$OLDGRANT" == "xoldgrant" ]]; then
    # ubuntu modifies root@localhost to use auth_socket
    systemctl stop $SERVICE
    while pgrep -x mysqld &>/dev/null ; do sleep 1 ; done
    rm -rf -- /var/lib/mysql/*
    mysql_install_db --user=mysql
    chown -R mysql:mysql /var/lib/mysql

    mysqld --pid-file=/var/lib/mysql/mysqld.pid $S --user=mysql --loose-wsrep-provider='none' --skip-networking &>/dev/null &
    mysqladmin $S --silent --connect-timeout=30 --wait=4 ping

    mysql $S -e "SET PASSWORD FOR root@localhost = PASSWORD('$PASS');GRANT ALL PRIVILEGES ON *.* TO root@'%' IDENTIFIED BY '$PASS';"
else
    # ubuntu modifies root@localhost to use auth_socket
    systemctl stop $SERVICE
    while pgrep -x mysqld &>/dev/null ; do sleep 1 ; done
    rm -rf -- /var/lib/mysql/*
    mysqld --initialize-insecure --user=mysql
    mysqld --pid-file=/var/lib/mysql/mysqld.pid $S --user=mysql --loose-wsrep-provider='none' --skip-networking --loose-log-error=/var/lib/mysql/default.err --loose-log-error-verbosity=3 &>/dev/null &
    mysqladmin $S --silent --connect-timeout=30 --wait=4 ping

    mysql $S -e "ALTER USER root@localhost IDENTIFIED BY '$PASS';CREATE USER root@'%' IDENTIFIED BY '$PASS';GRANT ALL PRIVILEGES ON *.* TO root@'%';";
fi
cat > /root/.my.cnf << EOF 
[client]
password=$1
EOF
mysqladmin $S shutdown

while pgrep -x mysqld &>/dev/null ; do sleep 1 ; done
