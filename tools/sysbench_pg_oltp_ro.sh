#!/bin/bash -e
HOST=$1
USR=$2
PASS=$3
DB=${4:-sbtest}
TBLS=${5:-2}
ROWS=${6:-10000}
THREADS=${7:-4}
BENCH_TIME=${8:-100}
SYSBENCH_TEST=/usr/share/sysbench/oltp_read_only.lua

echo "$HOST:5432:*:$USR:$PASS" >> ~/.pgpass
chmod 0600 ~/.pgpass

[ -f /usr/bin/psql ] || yum install -y postgresql

psql -U $USR -d $DB -h $HOST -c 'DROP TABLE IF EXISTS sbtest1;DROP TABLE IF EXISTS sbtest2'

sysbench $SYSBENCH_TEST \
  --db-driver=pgsql \
  --threads=$THREADS \
  --pgsql-host="$HOST" \
  --pgsql-user="$USR" \
  --pgsql-password="$PASS" \
  --pgsql-db="$DB" \
  --tables=$TBLS \
  --table-size=$ROWS \
  prepare

sysbench $SYSBENCH_TEST \
  --db-driver=pgsql \
  --threads=$THREADS \
  --events=0 \
  --time=$BENCH_TIME \
  --pgsql-host="$HOST" \
  --pgsql-user="$USR" \
  --pgsql-password="$PASS" \
  --pgsql-db="$DB" \
  --tables=$TBLS \
  --table-size=$ROWS \
  run
