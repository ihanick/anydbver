#!/bin/bash
unset LC_CTYPE
:> test-run.log

OS_LIST=(el7 el8 oel7 oel8 stretch buster bionic focal)
START_STEP=0

opts=$(getopt \
    --longoptions "os:,fail-and-exit,start-step:" \
    --name "$(basename "$0")" \
    --options "" \
    -- "$@"
)

eval set --"$opts"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --os)
      OS_LIST=("$2")
      shift 2
      ;;
    --start-step)
      START_STEP="$2"
      shift 2
      ;;
    --fail-and-exit)
      FAIL_AND_EXIT=1
      shift
      ;;
      *)
      break
      ;;
  esac
done

if [[ "$1" == "--" ]] ; then
  shift
fi

fail_action() {
  echo "$1 : FAIL"
  [[ "$FAIL_AND_EXIT" ]] && exit 1
}

STEP=1
if [[ "x$1" = "x" || "x$1" = "xps-async-proxysql" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  ./anydbver deploy ps:5.7 node1 ps:5.7 master:default node2 ps:5.7 master:default node3 proxysql master:default >> test-run.log
  test $(./anydbver ssh node3 -- mysql --protocol=tcp --port 6032 -uadmin -padmin -e "'select * from runtime_mysql_servers'" 2>/dev/null|grep -c ONLINE ) = 3 || fail_action "ps-async-proxysql"
fi

for os in ${OS_LIST[@]} ; do
STEP=2
  for m in mysql ps ; do
    if [[ "x$1" = "x" || "x$1" = "x$m" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
      for ver in 5.6 5.7 8.0 ; do 
        [[ $ver == "5.6" && ( $os == el8 || $os == oel8 || $os == focal || $os == buster || $os == bionic ) ]] && continue
        [[ $ver == "5.7" && ( $os == el8 || $os == oel8 || $os == focal ) && "$m" == mysql ]] && continue
        ./anydbver deploy --os $os $m:$ver >> test-run.log
        ./anydbver ssh default -- mysql -e "'select version()'" 2>/dev/null |grep -q $ver || fail_action "$os: $m:$ver"
      done
    fi
  done

STEP=3
  if [[ "x$1" = "x" || "x$1" = "xpxc" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
    for ver in 5.6 5.7 8.0; do
      [[ $ver == "5.6" && ( $os == el8 || $os == oel8 || $os == focal || $os == buster ) ]] && continue
      ./anydbver deploy --os $os pxc:$ver node1 pxc:$ver galera-master:default node2 pxc:$ver galera-master:default >> test-run.log
      ./anydbver ssh default -- mysql -e "'show status'" 2>/dev/null|grep wsrep_cluster_size|grep -q 3 || fail_action "$os pxc $ver"
    done
  fi

STEP=4
if [[ "x$1" = "x" || "x$1" = "xmariadb" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  for ver in 10.3 10.4 10.5; do
    ./anydbver deploy mariadb:$ver >> test-run.log
    ./anydbver ssh default -- mysql -e "'select version()'" 2>/dev/null |grep -q $ver || fail_action "mariadb $ver"
  done
fi

done


STEP=5
if [[ "x$1" = "x" || "x$1" = "xmariadb-galera" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  for ver in 10.3 10.4 10.5; do
    ./anydbver deploy mariadb-cluster:$ver node1 mariadb-cluster:$ver galera-master:default node2 mariadb-cluster:$ver galera-master:default >> test-run.log
    ./anydbver ssh default -- mysql -e "'show status'" 2>/dev/null|grep wsrep_cluster_size|grep -q 3 || fail_action "mariadb-galera $ver"
  done
fi

STEP=6
if [[ "x$1" = "x" || "x$1" = "xpmm" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  ./anydbver deploy pmm node1 ps:5.7 pmm-client pmm-server:default >> test-run.log
  curl -u admin:secret -k -s https://$(./anydbver ip)/graph/|grep -q pmm || fail_action "pmm"
fi

STEP=7
if [[ "x$1" = "x" || "x$1" = "xpg" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  for ver in 9.5 9.6 10 11 12 13 ; do
    ./anydbver deploy pg:$ver >> test-run.log
    ./anydbver ssh default -- psql -U postgres -h $(./anydbver ip) -c "'select version()'" 2>/dev/null | grep -q $ver || fail_action "pg $ver"
  done
fi

STEP=8
if [[ "x$1" = "x" || "x$1" = "xpg-replication" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  for ver in 9.5 9.6 10 11 12 13 ; do
    ./anydbver deploy pg:$ver node1 pg:$ver master:default >> test-run.log
    ./anydbver ssh default -- psql -U postgres -h $(./anydbver ip) -xc "'select * from pg_replication_slots'" 2>/dev/null|grep active_pid |cut -d'|' -f 2|egrep -q '[0-9]' || fail_action "pg-replication $ver"
  done
fi

STEP=9
if [[ "x$1" = "x" || "x$1" = "xppg" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  for ver in 12.2 12.3 12.4 12.5 13.0 13.1 ; do
    ./anydbver deploy ppg:$ver >> test-run.log
    ./anydbver ssh default -- psql -U postgres -h $(./anydbver ip) -c "'select version()'" 2>/dev/null | grep -q $ver || fail_action "ppg $ver"
  done
fi

STEP=10
if [[ "x$1" = "x" || "x$1" = "xpsmdb" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  for ver in 3.0 3.2 3.4 3.6 4.2 4.4 ; do
    ./anydbver deploy psmdb:$ver >> test-run.log
    ./anydbver ssh default -- mongo --eval "'db.version()'" 2>/dev/null | grep -q $ver || fail_action "psmdb $ver"
  done
fi

STEP=11
if [[ "x$1" = "x" || "x$1" = "xorchestrator" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  ./anydbver deploy \
          ps:5.7                "hn:ps0.percona.local" \
    node1 ps:5.7 master:default "hn:ps1.percona.local" \
    node2 ps:5.7 master:node1   "hn:ps2.percona.local" \
    node3 orchestrator master:default >> test-run.log
  sleep 10 # wait for topology change
  [[ $(./anydbver ssh node3 -- orchestrator-client -c topology -i ps0.percona.local:3306 2>/dev/null |wc -l) == 3 ]] || fail_action "orchestrator"
fi

STEP=12
if [[ "x$1" = "x" || "x$1" = "xproxysql-mysql-async" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  ./anydbver deploy mysql node1 mysql master:default node2 proxysql master:default >> test-run.log
  ./anydbver ssh node2 -- mysql --protocol=tcp --port 6033 -uroot -psecret -e "'select version()'" 2>/dev/null | \
    grep -q 8.0 || fail_action "proxysql-mysql-async"
fi

STEP=13
if [[ "x$1" = "x" || "x$1" = "xmongo-ldap" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  ./anydbver deploy ldap node1 ldap-master:default psmdb:4.2 >> test-run.log
  ./anydbver ssh node1 -- \
    sudo -u perconaro mongo -u perconaro -psecret --authenticationDatabase "'\$external'" \
      --authenticationMechanism PLAIN --eval "'db.version()'" | \
    grep -q 4.2 || fail_action "mongo-ldap"
fi

STEP=14
if [[ "x$1" = "x" || "x$1" = "xmongo-samba" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  ./anydbver deploy install samba cache:samba default samba node1 psmdb:4.2 samba-dc:default >> test-run.log
  ./anydbver ssh node1 -- \
    sudo -u nihalainen mongo \
      -u nihalainen -pverysecretpassword1^ --authenticationDatabase "'\$external'" \
      --authenticationMechanism PLAIN --eval "'db.version()'" | \
    grep -q 4.2 || fail_action "mongo-samba"
fi


STEP=15
# Regression tests
if [[ "x$1" = "x" || "x$1" = "xissue-2" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  ./anydbver deploy mysql:$(grep 8.0 .version-info/mysql.el7.txt |tail -n 2|head -n 1) >> test-run.log
  ./anydbver ssh default -- mysql -e "'select version()'" 2>/dev/null |grep -q 8.0 || fail_action "issue-2"
fi

STEP=16
if [[ "x$1" = "x" || "x$1" = "xissue-1" ]] && [[ "x$2" = "x" || "x$2" = "xmysql" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  ./anydbver deploy \
    hn:mysql_rs0_gr0 mysql:8.0.18 group-replication \
    node1 hn:mysql_rs0_gr1 mysql:8.0.18 group-replication master:default \
    node2 hn:mysql_rs0_gr2 mysql:8.0.18 group-replication master:default \
    node3 hn:mysql_rs0_router mysql-router:8.0.18 master:default >> test-run.log
  ./anydbver ssh node3 -- mysql --protocol=tcp --port 6446 -uroot -psecret -e "'select version()'" 2>/dev/null |grep -q 8.0 || fail_action "mysql issue-1"
fi
if [[ "x$1" = "x" || "x$1" = "xissue-1" ]] && [[ "x$2" = "x" || "x$2" = "xps" ]] ; then
  ./anydbver deploy \
    hn:mysql_rs0_gr0 ps:8.0.19 group-replication \
    node1 hn:mysql_rs0_gr1 ps:8.0.19 group-replication master:default \
    node2 hn:mysql_rs0_gr2 ps:8.0.19 group-replication master:default \
    node3 hn:mysql_rs0_router mysql-router:8.0.19 master:default >> test-run.log
  ./anydbver ssh node3 -- mysql --protocol=tcp --port 6446 -uroot -psecret -e "'select version()'" 2>/dev/null |grep -q 8.0 || fail_action "ps issue-1"
fi

STEP=17
if [[ "x$1" = "x" || "x$1" = "xissue-3" ]] && [[ "$STEP" -ge "$START_STEP" ]] ; then
  ./anydbver deploy hn:vault.percona.local vault node1 ps:8.0 vault-server:vault.percona.local >> test-run.log
  ./anydbver ssh node1 -- mysql -e "'create database test;create table test.t(iduniqname int auto_increment primary key) ENCRYPTION=\"Y\";show create table test.t'" 2>/dev/null | grep -q iduniqname || fail_action "issue-3"
fi
