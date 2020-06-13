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

[ -f /usr/bin/mysql ] || yum install -y Percona-Server-client-56.x86_64
mysql --host="$HOST" --user="$USR" --password="$PASS" <<EOF
    DROP DATABASE IF EXISTS \`${DB}\`;
    CREATE DATABASE \`$DB\`;
EOF

sysbench $SYSBENCH_TEST \
  --threads=$THREADS \
  --mysql-host="$HOST" \
  --mysql-user="$USR" \
  --mysql-password="$PASS" \
  --tables=$TBLS \
  --table-size=$ROWS \
  prepare

sysbench $SYSBENCH_TEST \
  --threads=$THREADS \
  --events=0 \
  --time=$BENCH_TIME \
  --mysql-host="$HOST" \
  --mysql-user="$USR" \
  --mysql-password="$PASS" \
  --tables=$TBLS \
  --table-size=$ROWS \
  run