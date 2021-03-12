#!/bin/bash
LDAP_IP=$1
LDAP_USER=$2
LDAP_PASS=$3
apt-get install -y debconf-utils

debconf-set-selections <<EOF
ldap-auth-config ldap-auth-config/rootbindpw password $LDAP_PASS
ldap-auth-config ldap-auth-config/bindpw password $LDAP_PASS
ldap-auth-config ldap-auth-config/override boolean true
ldap-auth-config ldap-auth-config/ldapns/ldap_version select 3
ldap-auth-config ldap-auth-config/ldapns/ldap-server string ldap://$LDAP_IP
ldap-auth-config ldap-auth-config/rootbinddn string cn=ldapadm,dc=percona,dc=local
ldap-auth-config ldap-auth-config/dblogin boolean false
ldap-auth-config ldap-auth-config/move-to-debconf boolean true
ldap-auth-config ldap-auth-config/ldapns/base-dn string dc=percona,dc=local
ldap-auth-config ldap-auth-config/pam_password select md5
ldap-auth-config ldap-auth-config/dbrootlogin boolean true
ldap-auth-config ldap-auth-config/binddn string cn=ldapadm,dc=percona,dc=local
EOF

DEBIAN_FRONTEND=noninteractive apt-get -y install libnss-ldap libpam-ldap ldap-utils
cat >> /etc/ldap/ldap.conf <<EOF
BASE    dc=percona,dc=local
URI     ldap://$LDAP_IP
EOF
cat >> /etc/pam.d/common-session <<EOF
session optional pam_mkhomedir.so skel=/etc/skel umask=077
EOF
sed -i -e 's/files systemd$/files systemd ldap/' /etc/nsswitch.conf
# ldapsearch -x cn=dba -b dc=percona,dc=local
# getent passwd dba
touch /root/ldap-client.configured
