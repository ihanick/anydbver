#!/bin/bash
USR=$1
LDAP_TYPE=$2
CNF_FILE=$3
SERVICE=$4

if [ "x$LDAP_TYPE" = "xldap_simple" ] ; then
  mysql <<EOF
INSTALL PLUGIN authentication_ldap_simple SONAME 'authentication_ldap_simple.so';
EOF
  cat >> "$CNF_FILE" <<EOF
authentication_ldap_simple_auth_method_name=SIMPLE
authentication_ldap_simple_server_host='10.76.129.84'
authentication_ldap_simple_bind_root_dn='cn=ldap,cn=Users,dc=percona,dc=local'
authentication_ldap_simple_bind_root_pwd='verysecretpassword1^'
authentication_ldap_simple_bind_base_dn='dc=percona,dc=local'
authentication_ldap_simple_tls=1
authentication_ldap_simple_user_search_attr='cn'
EOF
else
  mysql <<EOF
INSTALL PLUGIN auth_pam SONAME 'auth_pam.so';
CREATE USER dba@'%' IDENTIFIED WITH auth_pam;
GRANT ALL PRIVILEGES ON *.* TO dba@'%';
FLUSH PRIVILEGES;
EOF
fi

touch /root/mysql-ldap.applied
