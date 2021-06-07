#!/bin/bash
SRC_INSTALL="$1"
PG_BIN=$(find /usr -maxdepth 1 -type d -name 'pgsql-*' -print -quit)/bin

yum install -y epel-release

if [ "$SRC_INSTALL" == "" ] ; then
  yum install -y patroni-etcd
else
  yum install -y python3-pip pyOpenSSL python3-devel gcc
  yum -y install pyOpenSSL python-setuptools.noarch
  pip3 install --upgrade pip
  pip3 install --upgrade setuptools

  export PATH=$PATH:$PG_BIN
  pip3 install psycopg2
  pip3 install patroni[etcd]

fi
