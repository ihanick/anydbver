#!/bin/bash
USR=$1

mysql <<EOF
INSTALL PLUGIN auth_pam SONAME 'auth_pam.so';
CREATE USER dba@'%' IDENTIFIED WITH auth_pam;
GRANT ALL PRIVILEGES ON *.* TO dba@'%';
FLUSH PRIVILEGES;
EOF

touch /root/mysql-ldap.applied
