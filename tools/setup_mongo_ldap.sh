#!/bin/bash
DB_USER=$1
DB_PASS=$2
LDAP_IP=$3
LDAP_AD=$4
DB_LDAP_USR_PASS=$5
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
ldap_servers: ldaps://$LDAP_IP
ldap_search_base: dc=percona,dc=local
ldap_timeout: 10
ldap_filter: sAMAccountName=%U
ldap_bind_dn: cn=ldap,cn=Users,dc=percona,dc=local
ldap_password: verysecretpassword1^
ldap_deref: never
ldap_restart: yes
ldap_scope: sub
ldap_use_sasl: no
ldap_start_tls: no
ldap_version: 3
ldap_auth_method: bind
ldap_tls_check_peer: no
EOF
# ldap_tls_cacert_file: /etc/openldap/certs/ca.pem
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

/vagrant/tools/yq -i ea '. as $item ireduce ({}; . * $item )' /etc/mongod.conf /root/mongo-allow-plain.conf

systemctl enable saslauthd
systemctl start saslauthd

# testsaslauthd -u dba -p $DB_PASS -f /var/run/saslauthd/mux

grep -iq replsetname /etc/mongod.conf
HAS_REPL=$?
if [[ $HAS_REPL == 0 ]]; then
  sed -i -e 's/replSetName:/#replSetName:/i' -e 's/replication:/#replication:/i' /etc/mongod.conf
fi
systemctl restart mongod

mongo <<EOF
db = connect("mongodb://dba:$DB_PASS@127.0.0.1:27017/admin")
db.getSiblingDB("\$external").createUser({user : '$DB_USER', roles: [ {role : "read", db: 'percona'} ]})
db.getSiblingDB("\$external").auth({mechanism: "PLAIN",user : '$DB_USER',pwd: '$DB_PASS',digestPassword: false})
EOF

mongo -u $DB_USER -p$DB_LDAP_USR_PASS --authenticationDatabase '$external' --authenticationMechanism PLAIN <<EOF
use percona
db.col1.find()
EOF

if [[ $HAS_REPL == 0 ]]; then
  sed -i -e 's/#replSetName:/replSetName:/i' -e 's/#replication:/replication:/i' /etc/mongod.conf
  systemctl restart mongod
fi

