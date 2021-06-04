#!/bin/bash -e

wait_until_mysql_ready() {
  local HOST="$1"
  local USER="$2"
  local PASS="$3"
  until mysqladmin -u "$USER" -p"$PASS" -h "$HOST" --silent --connect-timeout=30 --wait=4 ping ; do sleep 5 ; done
}

install_clone_plugin() {
  local HOST="$1"
  local USER="$2"
  local PASS="$3"
  CLONE_INSTALLED=$(mysql -u "$USER" -p"$PASS" -h "$HOST" -Ne "select count(*) FROM information_schema.PLUGINS WHERE PLUGIN_NAME='clone';")
  if [ "$CLONE_INSTALLED" -eq 0 ] ; then
    mysql -u "$USER" -p"$PASS" -h "$HOST" --connect-timeout=30 --wait -e "INSTALL PLUGIN clone SONAME 'mysql_clone.so';"
  fi
}

clone_mysql_server() {
  local DST_HOST="$1"
  local DST_USER="$2"
  local DST_PASS="$3"
  local SRC_HOST="$4"
  local SRC_USER="$5"
  local SRC_PASS="$6"

  wait_until_mysql_ready "$SRC_HOST" "$SRC_USER" "$SRC_PASS"
  install_clone_plugin "$SRC_HOST" "$SRC_USER" "$SRC_PASS"
  wait_until_mysql_ready "$DST_HOST" "$DST_USER" "$DST_PASS"
  install_clone_plugin "$DST_HOST" "$DST_USER" "$DST_PASS"
  if ! mysql -u "$DST_USER" -p"$DST_PASS" -h "$DST_HOST" --connect-timeout=30 --wait <<EOF
SET GLOBAL clone_valid_donor_list = '$SRC_HOST:3306';
CLONE INSTANCE FROM '$SRC_USER'@'$SRC_HOST':3306
IDENTIFIED BY '$SRC_PASS'
EOF
  then
    echo "Clone plugin requires mysqld restart"
  fi
}


setup_gtid_replication() {
  local DST_HOST="$1"
  local DST_USER="$2"
  local DST_PASS="$3"
  local SRC_HOST="$4"
  local SRC_USER="$5"
  local SRC_PASS="$6"

  wait_until_mysql_ready "$SRC_HOST" "$SRC_USER" "$SRC_PASS"

  wait_until_mysql_ready "$DST_HOST" "$DST_USER" "$DST_PASS"
  mysql -u "$DST_USER" -p"$DST_PASS" -h "$DST_HOST" --connect-timeout=30 --wait <<EOF
STOP SLAVE;
CHANGE MASTER TO MASTER_HOST='$SRC_HOST', MASTER_USER='$SRC_USER', MASTER_PASSWORD='$SRC_PASS', MASTER_AUTO_POSITION=1;
START SLAVE;
EOF

}

is_gtid_enabled() {
  local HOST="$1"
  local USER="$2"
  local PASS="$3"

  wait_until_mysql_ready "$HOST" "$USER" "$PASS"
  mysql -u "$USER" -p"$PASS" -h "$HOST" --connect-timeout=30 --wait -Ne 'select @@gtid_mode'|grep -q ON
}

setup_position_replication_clone() {
  local DST_HOST="$1"
  local DST_USER="$2"
  local DST_PASS="$3"
  local SRC_HOST="$4"
  local SRC_USER="$5"
  local SRC_PASS="$6"

  wait_until_mysql_ready "$DST_HOST" "$DST_USER" "$DST_PASS"
  BINLOG_FILE=$(mysql -u "$DST_USER" -p"$DST_PASS" -h "$DST_HOST" --connect-timeout=30 --wait -Ne 'SELECT BINLOG_FILE FROM performance_schema.clone_status')
  BINLOG_POS=$(mysql -u "$DST_USER" -p"$DST_PASS" -h "$DST_HOST" --connect-timeout=30 --wait -Ne 'SELECT BINLOG_POSITION FROM performance_schema.clone_status')
  mysql -u "$DST_USER" -p"$DST_PASS" -h "$DST_HOST" --connect-timeout=30 --wait <<EOF
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

  clone_mysql_server "$DST_HOST" "$DST_USER" "$DST_PASS" "$SRC_HOST" "$SRC_USER" "$SRC_PASS" 

  if is_gtid_enabled "$DST_HOST" "$DST_USER" "$DST_PASS" ; then
    setup_gtid_replication "$DST_HOST" "$DST_USER" "$DST_PASS" "$SRC_HOST" "$SRC_USER" "$SRC_PASS"
  else
    setup_position_replication_clone "$DST_HOST" "$DST_USER" "$DST_PASS" "$SRC_HOST" "$SRC_USER" "$SRC_PASS"
  fi
}

setup_replication "$FOLLOWER_HOST" "$FOLLOWER_USER" "$FOLLOWER_PASSWORD" "$LEADER_HOST" "$LEADER_USER" "$LEADER_PASSWORD" 
echo "Finished"
