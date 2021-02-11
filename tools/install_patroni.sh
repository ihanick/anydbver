#!/bin/bash
PG_BIN=$(ls -d /usr/pgsql-*/bin|tail -n 1)

yum install -y python3-pip pyOpenSSL python3-devel gcc
yum install -y epel-release
yum -y install pyOpenSSL python-setuptools.noarch
pip3 install --upgrade pip
pip3 install --upgrade setuptools

export PATH=$PATH:$PG_BIN
pip3 install psycopg2
pip3 install patroni[etcd]

