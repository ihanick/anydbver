#!/bin/bash
DB_USER=$1
DB_PASS=$2
LDAP_IP=$3
LDAP_AD=$4
yum install -y openldap-clients cyrus-sasl-ldap cyrus-sasl-plain cyrus-sasl

sed -i -e 's/MECH=pam/MECH=ldap/g' /etc/sysconfig/saslauthd

cat > /etc/sasl2/mongodb.conf <<EOF
pwcheck_method: saslauthd
saslauthd_path: /var/run/saslauthd/mux
log_level: 5
mech_list: plain
EOF

if [ "x$LDAP_AD" = "xyes" ] ; then
cat > /etc/saslauthd.conf  <<EOF
ldap_servers: ldaps://ihanick-node2.percona.local
ldap_search_base: dc=percona,dc=local
ldap_timeout: 10
ldap_filter: sAMAccountName=%U
ldap_bind_dn: cn=mysqldba,cn=Users,dc=percona,dc=local
ldap_password: verysecretpassword1^
ldap_deref: never
ldap_restart: yes
ldap_scope: sub
ldap_use_sasl: no
ldap_start_tls: no
ldap_version: 3
ldap_auth_method: bind
ldap_tls_cacert_file: /etc/openldap/certs/ca.pem
EOF
else
cat > /etc/saslauthd.conf  <<EOF
ldap_servers: ldap://${LDAP_IP}:389
ldap_search_base: ou=People,dc=percona,dc=local
ldap_filter: (uid=%u)
EOF
fi

cat > /root/mongo-allow-plain.conf <<EOF
setParameter:
  authenticationMechanisms: PLAIN,SCRAM-SHA-1
EOF

/usr/local/bin/yq merge -i /etc/mongod.conf /root/mongo-allow-plain.conf

systemctl enable saslauthd
systemctl start saslauthd

# testsaslauthd -u dba -p $DB_PASS -f /var/run/saslauthd/mux

systemctl restart mongod

mongo <<EOF
db = connect("mongodb://dba:$DB_PASS@127.0.0.1:27017/admin")
db.getSiblingDB("\$external").createUser({user : '$DB_USER', roles: [ {role : "read", db: 'percona'} ]})
db.getSiblingDB("\$external").auth({mechanism: "PLAIN",user : '$DB_USER',pwd: '$DB_PASS',digestPassword: false})
EOF

mongo -u $DB_USER -p$DB_PASS --authenticationDatabase '$external' --authenticationMechanism PLAIN <<EOF
use percona
db.col1.find()
EOF
