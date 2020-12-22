#!/bin/bash
if [[ "x$1" = "" || "x$1" = "xps-async-proxysql" ]] ; then
  ./anydbver deploy ps:5.7 node1 ps:5.7 master:default node2 ps:5.7 master:default node3 proxysql master:default
  test $(./anydbver ssh node3 mysql --protocol=tcp --port 6032 -uadmin -padmin -e "'select * from runtime_mysql_servers'" 2>/dev/null|grep -c ONLINE ) = 3 || echo FAIL
fi

for m in mysql ps ; do
  if [[ "x$1" = "" || "x$1" = "x$m" ]] ; then
    for ver in 5.6 5.7 8.0 ; do 
      ./anydbver deploy $m:$ver >> test-run.log
      ./anydbver ssh default mysql -e "'select version()'" 2>/dev/null |grep -q $ver || echo FAIL
    done
  fi
done

if [[ "x$1" = "" || "x$1" = "xpmm" ]] ; then
  ./anydbver deploy pmm node1 ps:5.7 pmm-client pmm-server:default >> test-run.log
  curl -u admin:secret -k -s https://$(./anydbver ip)/graph/|grep -q pmm || echo FAILED
fi

if [[ "x$1" = "" || "x$1" = "xpg" ]] ; then
  for ver in 9.5 9.6 10 11 12 13 ; do
    ./anydbver deploy pg:$ver >> test-run.log
    ./anydbver ssh default psql -U postgres -h $(./anydbver ip) -c "'select version()'" 2>/dev/null | grep -q $ver || echo FAIL
  done
fi

if [[ "x$1" = "" || "x$1" = "xpg-replication" ]] ; then
  for ver in 9.5 9.6 10 11 12 13 ; do
    ./anydbver deploy pg:$ver node1 pg:$ver master:default >> test-run.log
    ./anydbver ssh default psql -U postgres -h $(./anydbver ip) -xc "'select * from pg_replication_slots'" 2>/dev/null|grep active_pid |cut -d'|' -f 2|egrep -q '[0-9]' || echo FAIL
  done
fi

