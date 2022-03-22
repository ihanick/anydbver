#!/bin/bash -e

create_client_my_cnf() {
  local FILE="$1"
  local HOST="$2"
  local USER="$3"
  local PASS="$4"

  cat > /tmp/"$FILE".cnf <<EOF
[client]
host="$HOST"
user="$USER"
password="$PASS"
EOF
}

wait_until_mysql_ready() {
  local FILE="$1"
  until mysql --defaults-file=/tmp/"$FILE".cnf --silent --connect-timeout=30 --wait -e "SELECT 1;" > /dev/null 2>&1 ; do sleep 5 ; done
}

is_clone_allowed() {
  local DST="$1"
  local SRC="$2"
  wait_until_mysql_ready "$SRC"
  VER1=$(mysql --defaults-file=/tmp/"$SRC".cnf -Ne 'select @@version'|cut -d- -f1)
  wait_until_mysql_ready "$DST"
  VER2=$(mysql --defaults-file=/tmp/"$DST".cnf -Ne 'select @@version'|cut -d- -f1)

  if [ "$VER1" != "$VER2" ] ; then
    return 1
  fi

  MAJ=$(echo "$VER1" | cut -d. -f1)
  MIN=$(echo "$VER1" | cut -d. -f3)

  # Clone available since 8.0.17
  if [ "$MAJ" -lt 8 ] || { [ "$MAJ" = 8 ] && [ "$MIN" -le 17 ]; } ; then
    return 1
  fi

  return 0
}

install_clone_plugin() {
  local FILE="$1"
  CLONE_INSTALLED=$(mysql --defaults-file=/tmp/"$FILE".cnf -Ne "select count(*) FROM information_schema.PLUGINS WHERE PLUGIN_NAME='clone';")
  if [ "$CLONE_INSTALLED" -eq 0 ] ; then
    mysql --defaults-file=/tmp/"$FILE".cnf --connect-timeout=30 --wait -e "INSTALL PLUGIN clone SONAME 'mysql_clone.so';"
  fi
}

clone_mysql_server() {
  local DST="$1"
  local SRC="$2"

  wait_until_mysql_ready "$SRC"
  install_clone_plugin "$SRC"
  wait_until_mysql_ready "$DST"
  install_clone_plugin "$DST"
  if ! mysql --defaults-file=/tmp/"$DST".cnf --connect-timeout=30 --wait  2>/tmp/mysql-clone.log <<EOF
SET GLOBAL clone_valid_donor_list = '$SRC_HOST:3306';
CLONE INSTANCE FROM '$SRC_USER'@'$SRC_HOST':3306
IDENTIFIED BY '$SRC_PASS'
EOF
  then
    grep -q 'mysqld is not managed by supervisor process' /tmp/mysql-clone.log || cat /tmp/mysql-clone.log
  fi
}


setup_gtid_replication() {
  local FILE="$1"
  local SRC_HOST="$2"
  local SRC_USER="$3"
  local SRC_PASS="$4"

  wait_until_mysql_ready "$FILE"
  mysql --defaults-file=/tmp/"$FILE".cnf --connect-timeout=30 --wait <<EOF
STOP SLAVE;
CHANGE MASTER TO MASTER_HOST='$SRC_HOST', MASTER_USER='$SRC_USER', MASTER_PASSWORD='$SRC_PASS', MASTER_AUTO_POSITION=1;
START SLAVE;
EOF

}

is_same_gtid() {
  local DST="$1"
  local SRC="$2"

  SRC_GTID=$( mysql --defaults-file=/tmp/"$SRC".cnf --connect-timeout=30 --wait -e "show master status\G"|tr '\n' ' '|sed -e 's/^.*Executed_Gtid_Set: //' )
  DST_GTID=$( mysql --defaults-file=/tmp/"$DST".cnf --connect-timeout=30 --wait -e "show master status\G"|tr '\n' ' '|sed -e 's/^.*Executed_Gtid_Set: //' )
  IS_SUBSET=$( mysql --defaults-file=/tmp/"$DST".cnf --connect-timeout=30 --wait -Ne "SELECT GTID_SUBSET('$SRC_GTID', '$DST_GTID');" )
  [ "$IS_SUBSET" = 1 ]
}

is_gtid_enabled() {
  local FILE="$1"

  wait_until_mysql_ready "$FILE"
  mysql --defaults-file=/tmp/"$FILE".cnf --connect-timeout=30 --wait -Ne 'select @@gtid_mode'|grep -q ON
}

setup_position_replication_clone() {
  local FILE="$1"
  local SRC_HOST="$2"
  local SRC_USER="$3"
  local SRC_PASS="$4"

  wait_until_mysql_ready "$FILE"
  BINLOG_FILE=$(mysql --defaults-file=/tmp/"$FILE".cnf --connect-timeout=30 --wait -Ne 'SELECT BINLOG_FILE FROM performance_schema.clone_status')
  BINLOG_POS=$(mysql --defaults-file=/tmp/"$FILE".cnf --connect-timeout=30 --wait -Ne 'SELECT BINLOG_POSITION FROM performance_schema.clone_status')
  mysql --defaults-file=/tmp/"$FILE".cnf --connect-timeout=30 --wait <<EOF
STOP SLAVE;
CHANGE MASTER TO MASTER_HOST='$SRC_HOST', MASTER_USER='$SRC_USER', MASTER_PASSWORD='$SRC_PASS', MASTER_LOG_FILE='$BINLOG_FILE', MASTER_LOG_POS=$BINLOG_POS;
START SLAVE;
EOF

}

setup_replication() {
  local DST_HOST="$1"
  local DST_USER="$2"
  local DST_PASS="$3"
  local SRC_HOST="$4"
  local SRC_USER="$5"
  local SRC_PASS="$6"

  create_client_my_cnf leader "$SRC_HOST" "$SRC_USER" "$SRC_PASS"
  create_client_my_cnf follower "$DST_HOST" "$DST_USER" "$DST_PASS"

  if is_same_gtid follower leader; then
      setup_gtid_replication follower "$SRC_HOST" "$SRC_USER" "$SRC_PASS"
  elif is_clone_allowed follower leader ; then
    clone_mysql_server follower leader

    if is_gtid_enabled follower ; then
      setup_gtid_replication follower "$SRC_HOST" "$SRC_USER" "$SRC_PASS"
    else
      setup_position_replication_clone follower "$SRC_HOST" "$SRC_USER" "$SRC_PASS"
    fi
  else
    if is_gtid_enabled follower ; then
      echo Use backup
    fi
  fi
}

setup_replication "$FOLLOWER_HOST" "$FOLLOWER_USER" "$FOLLOWER_PASSWORD" "$LEADER_HOST" "$LEADER_USER" "$LEADER_PASSWORD" 
echo "Finished"
