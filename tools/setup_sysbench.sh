#!/bin/bash
DB="$1" # pg | mysql
DBHOST="$2"
PASS="$3"
DBPORT="$4"
CONCURRENCY=$(grep -c ^processor /proc/cpuinfo)

if [ "x$DB" == "xpg" ]; then
  export PGPASSWORD="$PASS"
  unset PGHOSTADDR
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
  cat >/usr/local/bin/run_sysbench.sh <<EOF
#!/bin/bash
unset PGHOSTADDR
sysbench \
  --db-driver=pgsql \
  --table-size=100000 \
  --tables=$CONCURRENCY --threads=$CONCURRENCY \
  --pgsql-host=$DBHOST --pgsql-user=sbtest --pgsql-password=$PASS --pgsql-db=sbtest \
  --time=60 --report-interval=2 \
  /usr/share/sysbench/oltp_read_write.lua run
EOF
  chmod +x /usr/local/bin/run_sysbench.sh
else # mysql
  PORT=3306
  if [[ $DBPORT != "" ]]; then
    PORT=$DBPORT
    DBPORT="--mysql-port=$DBPORT"
  fi
  USR=root
  until mysql -u $USR -p"$PASS" -h $DBHOST --port=$PORT -e 'select 1'; do sleep 1; done
  mysql -u $USR -p"$PASS" -h $DBHOST --port=$PORT <<EOF
create database sbtest;
EOF
  sysbench \
    --db-driver=mysql \
    --table-size=100000 \
    --tables=$CONCURRENCY --threads=$CONCURRENCY \
    --mysql-host=$DBHOST --mysql-user=root --mysql-password=$PASS $DBPORT --mysql-db=sbtest \
    --report-interval=2 \
    /usr/share/sysbench/oltp_read_write.lua prepare

  cat >/usr/local/bin/run_sysbench.sh <<EOF
#!/bin/bash
unset PGHOSTADDR
sysbench \
  --db-driver=mysql \
  --table-size=100000 \
  --tables=$CONCURRENCY --threads=$CONCURRENCY \
  --mysql-host=$DBHOST --mysql-user=root --mysql-password=$PASS $DBPORT --mysql-db=sbtest \
  --time=60 --report-interval=2 \
  /usr/share/sysbench/oltp_read_write.lua run
EOF
  chmod +x /usr/local/bin/run_sysbench.sh

fi
