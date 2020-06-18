#!/bin/bash
ENDPOINT=http://10.0.3.145:9000 DEFAULT_REGION=us-east-1 ACCESS_KEY_ID=REPLACE-WITH-AWS-ACCESS-KEY SECRET_ACCESS_KEY=REPLACE-WITH-AWS-SECRET-KEY xbcloud get "s3://operator-testing/cluster1-2020-18-06-02:28:58-full.sst_info" --parallel=10 | xbstream -x -C $PWD --parallel=$(grep -c processor /proc/cpuinfo)
ENDPOINT=http://10.0.3.145:9000 DEFAULT_REGION=us-east-1 ACCESS_KEY_ID=REPLACE-WITH-AWS-ACCESS-KEY SECRET_ACCESS_KEY=REPLACE-WITH-AWS-SECRET-KEY xbcloud get "s3://operator-testing/cluster1-2020-18-06-02:28:58-full" --parallel=10 | xbstream -x -C $PWD --parallel=$(grep -c processor /proc/cpuinfo)
xtrabackup --use-memory=1G --prepare --binlog-info=ON --rollback-prepared-trx --target-dir=$PWD
systemctl stop mysqld
rm -rf /var/lib/mysql/*
xtrabackup --use-memory=1G --move-back --binlog-info=ON --rollback-prepared-trx --target-dir=$PWD --force-non-empty-directories
chown -R mysql:mysql /var/lib/mysql
