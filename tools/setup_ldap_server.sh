#!/bin/sh
# based on https://www.itzgeek.com/how-tos/linux/centos-how-tos/step-step-openldap-server-configuration-centos-7-rhel-7.html
USER=$1
PASSWORD=$2

fix_ldap_certs() {
if test -f /etc/openldap/slapd.d/cn\=config/olcDatabase\=\{2\}mdb.ldif  ; then
  sed -e "s#{SSHA}PASSWORD_CREATED#$(slappasswd -s $PASSWORD)#" -e 's#hdb,cn=config#mdb,cn=config#' /vagrant/configs/ldap_server/ldaprootpasswd.ldif > /root/ldaprootpasswd.ldif
else 
  sed -e "s#{SSHA}PASSWORD_CREATED#$(slappasswd -s $PASSWORD)#" /vagrant/configs/ldap_server/ldaprootpasswd.ldif > /root/ldaprootpasswd.ldif
fi
ldapmodify -Y EXTERNAL  -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/perconaldap.crt
EOF
ldapmodify -Y EXTERNAL  -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/perconaldap.key
EOF

ldapmodify -Y EXTERNAL  -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/perconaldap.key
EOF
ldapmodify -Y EXTERNAL  -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/perconaldap.crt
EOF
}

openssl req -new -x509 -nodes -out /etc/openldap/certs/perconaldap.crt -keyout /etc/openldap/certs/perconaldap.key -days 1460 -subj "/C=US/ST=New Sweden/L=Stockholm/O=Percona/OU=IT Infra/CN=server.percona.local/emailAddress=info@example.com"

systemctl stop slapd
if ! test -f /etc/openldap/certs/password  ; then
  echo $(/bin/bash /vagrant/tools/node_ip.sh) server.percona.local server >> /etc/hosts
  ln -s /etc/openldap/certs/perconaldap.key /etc/openldap/certs/password
  ln -s /etc/openldap/certs/perconaldap.crt /etc/openldap/certs/'OpenLDAP Server'
  chown -R ldap:ldap /etc/openldap/certs/*
  cd /etc/openldap/certs
  /usr/sbin/slapd -u ldap -h "ldap:/// ldapi:///"
  fix_ldap_certs
  pkill -x slapd
  systemctl start slapd
else
  systemctl start slapd
  fix_ldap_certs
fi

ldapmodify -Y EXTERNAL  -H ldapi:/// -f /root/ldaprootpasswd.ldif

cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap:ldap /var/lib/ldap/*
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif

ldapmodify -Y EXTERNAL  -H ldapi:/// -f /vagrant/configs/ldap_server/monitor.ldif

ldapadd -x -w $PASSWORD -D "cn=ldapadm,dc=percona,dc=local" -f /vagrant/configs/ldap_server/base.ldif

# Add users
ldapadd -x -w $PASSWORD -D "cn=ldapadm,dc=percona,dc=local" <<EOF
dn: uid=postgres,ou=People,dc=percona,dc=local
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
cn: postgres
uid: postgres
uidNumber: 26
gidNumber: 26
homeDirectory: /var/lib/pgsql
loginShell: /bin/bash
gecos: DBA [info (at) example]
userPassword: {crypt}x
shadowLastChange: 17058
shadowMin: 0
shadowMax: 99999
shadowWarning: 7
EOF
ldappasswd -s $PASSWORD -w $PASSWORD -D "cn=ldapadm,dc=percona,dc=local" -x "uid=postgres,ou=People,dc=percona,dc=local"
ldapadd -x -w $PASSWORD -D "cn=ldapadm,dc=percona,dc=local" <<EOF
dn: uid=perconaro,ou=People,dc=percona,dc=local
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
cn: perconaro
uid: perconaro
uidNumber: 9998
gidNumber: 100
homeDirectory: /home/perconaro
loginShell: /bin/bash
gecos: perconaro [info (at) example]
userPassword: {crypt}x
shadowLastChange: 17058
shadowMin: 0
shadowMax: 99999
shadowWarning: 7
EOF
ldappasswd -s $PASSWORD -w $PASSWORD -D "cn=ldapadm,dc=percona,dc=local" -x "uid=perconaro,ou=People,dc=percona,dc=local"


ldapadd -x -w $PASSWORD -D "cn=ldapadm,dc=percona,dc=local" -f /vagrant/configs/ldap_server/dba.ldif

ldappasswd -s $PASSWORD -w $PASSWORD -D "cn=ldapadm,dc=percona,dc=local" -x "uid=dba,ou=People,dc=percona,dc=local"

yum install -y tar
tar -C /etc/openldap/certs -xzf /vagrant/secret/ldap-certs.tar.gz
chown ldap:ldap -R /etc/openldap/certs

cp /etc/openldap/certs/ca.pem /etc/pki/ca-trust/source/anchors/ldap.pem
chown root:root /etc/pki/ca-trust/source/anchors/ldap.pem
chmod 0644 /etc/pki/ca-trust/source/anchors/ldap.pem
update-ca-trust

cat >>/etc/openldap/ldap.conf <<EOF 
TLS_CACERT /etc/openldap/certs/ca.pem
EOF

ldapmodify -Y EXTERNAL  -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/server.pem
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/server-key.pem
EOF

ldapmodify -Y EXTERNAL  -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/openldap/certs/ca.pem
EOF

# test: slapcat -b "cn=config" | egrep "olcTLSCertificateFile|olcTLSCertificateKeyFile|olcTLSCACertificateFile"
systemctl restart slapd


# openssl s_client -connect ldap.percona.local:636
# ldapsearch -H ldaps://ldap.percona.local -x cn=dba -b dc=percona,dc=local
