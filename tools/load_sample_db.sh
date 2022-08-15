#!/bin/bash
DB="$1"
mysql -e "SET GLOBAL pxc_strict_mode=PERMISSIVE;" && true
if [[ $DB == "world" ]] ; then
  mkdir -p /root/sampledb/world
  curl -sL https://downloads.mysql.com/docs/world-db.tar.gz |tar -C /root/sampledb/world/ --strip-components 1 -xz
  mysql < /root/sampledb/world/world.sql
fi

if [[ $DB == "employees" ]] ; then
  mkdir -p /root/sampledb/employees
  
  curl -sL https://github.com/datacharmer/test_db/releases/download/v1.0.7/test_db-1.0.7.tar.gz |tar -C /root/sampledb/employees/ --strip-components 1 -xz
  cd /root/sampledb/employees
  mysql < employees.sql
fi

if [[ $DB == "sakila" ]] ; then
  mkdir -p /root/sampledb/testdb
  
  curl -sL https://github.com/datacharmer/test_db/releases/download/v1.0.7/test_db-1.0.7.tar.gz |tar -C /root/sampledb/testdb/ --strip-components 1 -xz
  cd /root/sampledb/testdb/sakila
  mysql < sakila-mv-schema.sql
  mysql < sakila-mv-data.sql
fi
