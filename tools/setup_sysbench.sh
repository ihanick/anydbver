#!/bin/bash
DB="$1" # pg | mysql
DBHOST="$2"
PASS="$3"
CONCURRENCY=$(grep -c ^processor /proc/cpuinfo)

if [ "x$DB" == "xpg" ] ; then
  USR="postgres"
  psql -U $USR -h $DBHOST <<EOF
CREATE USER sbtest WITH PASSWORD '$PASS';
CREATE DATABASE sbtest;
GRANT ALL PRIVILEGES ON DATABASE sbtest TO sbtest;
EOF
  sysbench \
    --db-driver=pgsql \
    --table-size=100000 \
    --tables=$CONCURRENCY --threads=$CONCURRENCY \
    --pgsql-host=$DBHOST --pgsql-user=sbtest --pgsql-password=$PASS --pgsql-db=sbtest \
    --time=60 --report-interval=2 \
    /usr/share/sysbench/oltp_read_write.lua prepare
  cat > /usr/local/bin/run_sysbench.sh <<EOF
#!/bin/bash
sysbench \
  --db-driver=pgsql \
  --table-size=100000 \
  --tables=$CONCURRENCY --threads=$CONCURRENCY \
  --pgsql-host=$DBHOST --pgsql-user=sbtest --pgsql-password=$PASS --pgsql-db=sbtest \
  --time=60 --report-interval=2 \
  /usr/share/sysbench/oltp_read_write.lua run
EOF
  chmod +x /usr/local/bin/run_sysbench.sh
fi
