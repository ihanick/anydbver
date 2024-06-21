#!/bin/bash
VERSION=$1
yum groupinstall -y 'Development Tools'
yum install -y wget
wget https://ftp.postgresql.org/pub/source/v$VERSION/postgresql-${VERSION}.tar.bz2
mkdir -p /usr/pgsql-${VERSION}
cd  /usr/pgsql-${VERSION}
tar -xaf ~/postgresql-${VERSION}.tar.bz2 
cd postgresql-${VERSION}/
yum install -y yum-utils
yum-builddep -y postgresql
./configure --prefix=/usr/pgsql-${VERSION}
make all install
make install
groupadd postgres
useradd -m -g postgres postgres
chown -R postgres:postgres /usr/pgsql-${VERSION}
cat >> ~postgres/.bashrc <<EOF
export PATH=/usr/pgsql-${VERSION}/bin:$PATH
export PGDATA=/usr/pgsql-${VERSION}/data
EOF

sudo -u postgres bash <<EOF
cd  /usr/pgsql-${VERSION}
export PATH=/usr/pgsql-${VERSION}/bin:$PATH
export PGDATA=/usr/pgsql-${VERSION}/data
initdb -D \$PGDATA
EOF
