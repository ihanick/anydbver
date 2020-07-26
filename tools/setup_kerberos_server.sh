#!/bin/bash
USR=$1
PASS=$2

cat /vagrant/configs/hosts >> /etc/hosts

cat > /etc/krb5.conf << EOF
includedir /etc/krb5.conf.d/

[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

[libdefaults]
 dns_lookup_realm = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 pkinit_anchors = FILE:/etc/pki/tls/certs/ca-bundle.crt
 default_realm = HYD.PERCONA.LOCAL
 #default_ccache_name = KEYRING:persistent:%{uid}

[realms]
 HYD.PERCONA.LOCAL = {
  kdc = kdc.percona.local:88
  admin_server = kdc.percona.local:749
 }

[domain_realm]
 .hyd.percona.local = HYD.PERCONA.LOCAL
 hyd.percona.local = HYD.PERCONA.LOCAL
EOF


cat > /var/kerberos/krb5kdc/kdc.conf << EOF
[kdcdefaults]
 kdc_ports = 88
 kdc_tcp_ports = 88

[realms]
 HYD.PERCONA.LOCAL = {
  master_key_type = aes256-cts
  acl_file = /var/kerberos/krb5kdc/kadm5.acl
  dict_file = /usr/share/dict/words
  admin_keytab = /var/kerberos/krb5kdc/kadm5.keytab
  supported_enctypes = aes256-cts:normal aes128-cts:normal des3-hmac-sha1:normal arcfour-hmac:normal camellia256-cts:normal camellia128-cts:normal des-hmac-sha1:normal des-cbc-md5:normal des-cbc-crc:normal
 }
EOF


cat > /var/kerberos/krb5kdc/kadm5.acl << EOF
*/admin@HYD.PERCONA.LOCAL *
EOF

kdb5_util create -s -P "$PASS"

systemctl start krb5kdc
systemctl start kadmin

kadmin.local addprinc -pw "$PASS" root/admin
kadmin.local addprinc -pw "$PASS" "$USR"
kadmin.local ktadd host/kdc.percona.local
kadmin.local ktadd -k /var/kerberos/krb5kdc/kadm5.keytab kadmin/admin
kadmin.local ktadd -k /var/kerberos/krb5kdc/kadm5.keytab kadmin/changepw

kadmin.local addprinc -randkey host/kdc.pecona.local
kadmin.local ktadd host/kdc.percona.local

touch /root/kerberos.configured
