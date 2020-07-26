#!/bin/bash
USR="$1"
PASS="$2"

yum -y install krb5-workstation
yum -y install openssh-clients

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

cat >> /etc/ssh/sshd_config << EOF
KerberosAuthentication yes
GSSAPIAuthentication yes
GSSAPICleanupCredentials yes
EOF

systemctl restart sshd

cat >> /root/.ssh/config << EOF
Host *.percona.local
  GSSAPIAuthentication yes
  GSSAPIDelegateCredentials yes
EOF


kadmin -p root/admin -w "$PASS" addprinc -randkey host/$( hostname )
kadmin -p root/admin -w "$PASS" ktadd host/$( hostname )

kinit -k host/$(hostname)

useradd -m $USR

touch /root/kerberos-client.configured
