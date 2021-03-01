#!/bin/bash
SRV_IP=$1
PASS=$2
DOM_SID=$3
SRV_TYPE=${4:-mysql}

CNF_FILE=$5
MYSQL_SERVICE=$6

yum install -y authconfig openssh-clients nss-pam-ldapd nscd

# https://wiki.gentoo.org/wiki/Samba/Active_Directory_Guide
cat << EOF > /etc/nslcd.conf
uid nslcd
gid ldap
pagesize 1000
referrals off
idle_timelimit 800
filter passwd (&(objectClass=user)(objectClass=person)(!(objectClass=computer)))
map    passwd uid           sAMAccountName
map    passwd uidNumber     objectSid:$DOM_SID
map    passwd gidNumber     objectSid:$DOM_SID
map    passwd homeDirectory "/home/\$cn"
map    passwd gecos         displayName
map    passwd loginShell    "/bin/bash"
filter shadow (&(objectClass=user)(objectClass=person)(!(objectClass=computer)))
map    shadow uid              sAMAccountName
map    shadow shadowLastChange pwdLastSet
filter group (|(objectClass=group)(objectClass=person))
map    group gidNumber      objectSid:$DOM_SID
uri ldaps://$SRV_IP/
base dc=percona,dc=local
tls_reqcert never
binddn cn=ldap,cn=Users,dc=percona,dc=local
bindpw $PASS
EOF

authconfig --enableldap --enableldapauth --enableshadow --ldapserver="ldaps://$SRV_IP/" --ldapbasedn="dc=percona,dc=local" --enablemkhomedir --update

systemctl start nslcd.service


if [ "x$SRV_TYPE" = "xmysql" ] ; then
  cat << EOF > /etc/pam.d/mysqld 
auth required pam_ldap.so
account required pam_ldap.so
EOF

mysql << EOF
INSTALL PLUGIN auth_pam SONAME 'auth_pam.so';
INSTALL PLUGIN auth_pam_compat SONAME 'auth_pam_compat.so';
CREATE DATABASE support;

CREATE USER ''@'' IDENTIFIED WITH auth_pam as 'mysqld,support=support_users,dba=dba_users';
CREATE USER support_users@'%' IDENTIFIED BY 'some_password';
CREATE USER dba_users@'%' IDENTIFIED BY 'some_password';
GRANT ALL PRIVILEGES ON support.* TO support_users@'%';
GRANT ALL PRIVILEGES ON *.* TO dba_users@'%';
GRANT PROXY ON support_users@'%' TO ''@'';
GRANT PROXY ON dba_users@'%' TO ''@'';
EOF
fi


if [ "x$SRV_TYPE" = "xmysql_ldap_simple" ] ; then
  mysql <<EOF
INSTALL PLUGIN authentication_ldap_simple SONAME 'authentication_ldap_simple.so';
CREATE USER nihalainen@'%' IDENTIFIED WITH authentication_ldap_simple;
EOF
  cat >> "$CNF_FILE" <<EOF
authentication_ldap_simple_auth_method_name=SIMPLE
authentication_ldap_simple_server_host='$SRV_IP'
authentication_ldap_simple_bind_root_dn='cn=ldap,cn=Users,dc=percona,dc=local'
authentication_ldap_simple_bind_root_pwd='verysecretpassword1^'
authentication_ldap_simple_bind_base_dn='dc=percona,dc=local'
authentication_ldap_simple_tls=1
authentication_ldap_simple_user_search_attr='cn'
EOF
  systemctl restart $MYSQL_SERVICE
fi

cat << EOF >> /etc/openldap/ldap.conf
TLS_REQCERT allow
EOF

systemctl restart nslcd
systemctl restart nscd
