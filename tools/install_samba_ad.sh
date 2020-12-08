#!/bin/bash
yum install -y vim tar
#yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
#yum -y install gcc perl python-devel gnutls-devel libacl-devel openldap-devel which python3 python3-devel lmdb-devel gnutls-devel
BOOSTRAP_URL='https://git.samba.org/?p=samba.git;a=blob_plain;f=bootstrap/generated-dists/centos7/bootstrap.sh;hb=master'
if grep -q 'VERSION="8"' /etc/os-release ; then
BOOSTRAP_URL='https://git.samba.org/?p=samba.git;a=blob_plain;f=bootstrap/generated-dists/centos8/bootstrap.sh;hb=master'
fi
curl -sL -o /root/samba-boostrap.sh "$BOOSTRAP_URL" 
sed -i -e '/pipefail/d' samba-boostrap.sh

if grep -q 'VERSION="8"' /etc/os-release ; then
	sed -i -e 's/PowerTools/powertools/' -e 's/enabled Devel/enabled devel/' /root/samba-boostrap.sh
#sed -i -e '/compat-gnutls34-devel\|lcov\|libsemanage-python\|policycoreutils-python\|python36-cryptography\|python36-dns\|python36-iso8601\|python36-markdown\|python36-pyasn1\|python36-setproctitle\|quota-devel/d' /root/samba-boostrap.sh
#sed -i -e 's,yum copr enable -y sergiomb/SambaAD,yum copr enable -y sergiomb/SambaAD;dnf config-manager --set-enabled powertools,' /root/samba-boostrap.sh
fi

bash /root/samba-boostrap.sh
export PKG_CONFIG_PATH="/usr/lib64/compat-gnutls34/pkgconfig:/usr/lib64/compat-nettle32/pkgconfig"
curl -sL -o /root/samba-latest.tar.gz https://www.samba.org/samba/ftp/samba-latest.tar.gz
cd /root
tar -xzf samba-latest.tar.gz
cd samba-[0-9]*/
./configure --prefix=/opt/samba
make -j 4
make install
echo "PATH=/opt/samba/sbin:/opt/samba/bin:/usr/sbin:/usr/bin" >> /etc/environment
PATH=/opt/samba/sbin:/opt/samba/bin:/usr/sbin:/usr/bin
which samba-tool

cat << EOF > /etc/systemd/system/samba.service
[Unit]
Description=Samba PDC
After=syslog.target network.target

[Service]
Type=forking
PIDFile=//opt/samba/var/run/samba.pid
ExecStart=/opt/samba/sbin/samba -D
ExecReload=/usr/bin/kill -HUP $MAINPID
ExecStop=/usr/bin/kill $MAINPID

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

rm -f /etc/krb5.conf
