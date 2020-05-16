#!/bin/bash
PASS=$1
OLDGRANT=$2

if [[ "x$OLDGRANT" == "xoldgrant" ]]; then
    mysqld --user=mysql --loose-wsrep-provider='none' --skip-networking &>/dev/null &
    mysqladmin --silent --connect-timeout=30 --wait=4 ping

    mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('$PASS');GRANT ALL PRIVILEGES ON *.* TO root@'%' IDENTIFIED BY '$PASS';"
else
    mysqld --initialize-insecure --user=mysql
    mysqld --user=mysql --loose-wsrep-provider='none' --skip-networking &>/dev/null &
    mysqladmin --silent --connect-timeout=30 --wait=4 ping

    mysql -e "ALTER USER root@localhost IDENTIFIED BY '$PASS';CREATE USER root@'%' IDENTIFIED BY '$PASS';";
fi
cat > /root/.my.cnf << EOF 
[client]
password=$1
EOF
mysqladmin shutdown

while pgrep -x mysqld ; do sleep 1 ; done