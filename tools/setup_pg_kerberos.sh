#!/bin/bash
USR="$1"
PASS="$2"
PGVER=12

kadmin -p root/admin -w "$PASS" ank -randkey postgres/$(hostname)
kadmin -p root/admin -w "$PASS" ktadd -k /etc/sysconfig/pgsql/krb5.keytab postgres/$(hostname)
chown root:postgres /etc/sysconfig/pgsql/krb5.keytab
chmod g+r /etc/sysconfig/pgsql/krb5.keytab
sudo -u postgres psql -c 'CREATE ROLE "'$USR'@HYD.PERCONA.LOCAL" SUPERUSER LOGIN'
sed -i -e 's,host\s*all\s*all\s*0.0.0.0/0.*$,host    all             all             0.0.0.0/0               gss include_realm=1 krb_realm=HYD.PERCONA.LOCAL,' /var/lib/pgsql/$PGVER/data/pg_hba.conf
systemctl restart postgresql-$PGVER
