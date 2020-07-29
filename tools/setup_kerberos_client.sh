#!/bin/bash
USR="$1"
PASS="$2"
SAMBA=${3:-no}

yum -y install krb5-workstation
yum -y install openssh-clients

cat /vagrant/configs/hosts >> /etc/hosts

if [ "x$SAMBA" = "xno" ] ; then
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
else
cat > /etc/krb5.conf << EOF
[libdefaults]
	default_realm = PERCONA.LOCAL
	dns_lookup_realm = false
	dns_lookup_kdc = false

[realms]
PERCONA.LOCAL = {
	default_domain = percona.local
	kdc = pdc.percona.local:88
	admin_server = pdc.percona.local:749
}

[domain_realm]
	pdc = PERCONA.LOCAL
EOF
fi

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


if [ "x$SAMBA" = "xno" ] ; then
  kadmin -p root/admin -w "$PASS" addprinc -randkey host/$( hostname )
  kadmin -p root/admin -w "$PASS" ktadd host/$( hostname )

  kinit -k host/$(hostname)

  useradd -m $USR
else
  ssh -o StrictHostKeyChecking=no -i /vagrant/secret/id_rsa root@pdc.percona.local /opt/samba/bin/samba-tool user create $(hostname) --random-password
  ssh -o StrictHostKeyChecking=no -i /vagrant/secret/id_rsa root@pdc.percona.local /opt/samba/bin/samba-tool spn add host/$(hostname) $(hostname)
  ssh -o StrictHostKeyChecking=no -i /vagrant/secret/id_rsa root@pdc.percona.local /opt/samba/bin/samba-tool domain exportkeytab /root/$(hostname).keytab --principal=host/$(hostname)@PERCONA.LOCAL
  scp -o StrictHostKeyChecking=no -i /vagrant/secret/id_rsa root@pdc.percona.local:/root/$(hostname).keytab /etc/krb5.keytab
  useradd -m nihalainen
fi

touch /root/kerberos-client.configured
