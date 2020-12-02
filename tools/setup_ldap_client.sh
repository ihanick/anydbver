#!/bin/bash
LDAP_IP=$1
yum install -y openssh-server openldap-clients nss-pam-ldapd authconfig
authconfig --enableldap --enableldapauth --ldapserver=ldap://$LDAP_IP --ldapbasedn="dc=percona,dc=local" --enablemkhomedir --update
echo tls_reqcert allow >> /etc/nslcd.conf
systemctl restart nslcd
systemctl restart sshd
touch /root/ldap-client.configured
