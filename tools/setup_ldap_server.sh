#!/bin/sh
# based on https://www.itzgeek.com/how-tos/linux/centos-how-tos/step-step-openldap-server-configuration-centos-7-rhel-7.html
USER=$1
PASSWORD=$2

fix_ldap_certs() {
sed -e "s#{SSHA}PASSWORD_CREATED#$(slappasswd -s $PASSWORD)#" /vagrant/configs/ldap_server/ldaprootpasswd.ldif > /root/ldaprootpasswd.ldif
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
ldapadd -x -w $PASSWORD -D "cn=ldapadm,dc=percona,dc=local" -f /vagrant/configs/ldap_server/dba.ldif

ldappasswd -s $PASSWORD -w $PASSWORD -D "cn=ldapadm,dc=percona,dc=local" -x "uid=dba,ou=People,dc=percona,dc=local"
