#!/bin/bash
MINF=/tmp/master_info.txt
TYPE=$1
MASTER_IP=$2
MASTER_USER=$3
MASTER_PASSWORD=$4
SOFT=$5
CNF_FILE=$6
MYSQLD_UNIT=$7
CLUSTER_NAME=${8:-'pxc-cluster'}
CHANNEL=$9

SERVER_ID=$(ip addr ls|grep 'inet '|grep -v '127.0.0.1'|awk '{print $2}'|cut -d/ -f 1|awk -F '\\.' '{print ($1 * 2^24) + ($2 * 2^16) + ($3 * 2^8) + $4}')


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

  if is_gtid_enabled follower && is_gtid_enabled leader && is_same_gtid follower leader; then
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



if [ "x$SOFT" = "xmariadb_server" ] ; then
  if [[ "x$TYPE" == "xgtid" ]] ; then
      GTID=$(mysql --host $MASTER_IP -N -e "SELECT @@GLOBAL.gtid_current_pos")
      GTID_CUR=$(mysql -N -e "SELECT @@GLOBAL.gtid_current_pos")

      if mysql -Ne "show status like 'wsrep_cluster_size'"|grep -q wsrep_cluster_size ; then
        IS_GALERA=1
        systemctl stop $MYSQLD_UNIT
        mysqld --user=mysql --wsrep-provider=none &>/dev/null &
        until mysqladmin --silent --connect-timeout=30 --wait=4 ping ; do sleep 5 ; done
      else
        IS_GALERA=0
      fi

      if [ "x$GTID" != "x" -a "x$GTID" == "x$GTID_CUR" ] ; then
        mysql << EOF
STOP SLAVE;
RESET SLAVE ALL;
SET GLOBAL gtid_slave_pos = '${GTID}';
CHANGE MASTER TO MASTER_HOST='${MASTER_IP}', MASTER_USER='${MASTER_USER}', MASTER_PASSWORD='${MASTER_PASSWORD}', MASTER_USE_GTID=slave_pos;
START SLAVE;
EOF
      else
	      mysql --host $MASTER_IP -e 'DROP VIEW IF EXISTS mysql.nonexisting_23498985;show master status\G' > "$MINF"
	      GTID=$(mysql --host $MASTER_IP -N -e "SELECT @@GLOBAL.gtid_current_pos")
	      GTID_CUR=$(mysql -N -e "SELECT @@GLOBAL.gtid_current_pos")

	      mysql << EOF
RESET MASTER;
STOP SLAVE;
RESET SLAVE ALL;
SET GLOBAL gtid_slave_pos = '${GTID}';
CHANGE MASTER TO MASTER_HOST='${MASTER_IP}', MASTER_USER='${MASTER_USER}', MASTER_PASSWORD='${MASTER_PASSWORD}', MASTER_USE_GTID=slave_pos;
START SLAVE;
EOF
      fi

      if [[ $IS_GALERA == 1 ]] ; then
        mysqladmin shutdown
        systemctl start $MYSQLD_UNIT
        until mysqladmin --silent --connect-timeout=30 --wait=4 ping ; do sleep 5 ; done
      fi


      rm "${MINF}"
      touch /root/replication.configured
  fi
else
  if [[ "x$TYPE" == "xgtid" ]] ; then
      GTID=$(mysql --host $MASTER_IP -e 'show master status\G' |tr "\n" ' '|sed -e 's/^.*Executed_Gtid_Set: //' -e 's/ //g')
      if [ "x$GTID" = "x" ] ; then
        mysql --host $MASTER_IP -e 'DROP VIEW IF EXISTS mysql.nonexisting_23498985;'
        GTID=$(mysql --host $MASTER_IP -e 'show master status\G' |tr "\n" ' '|sed -e 's/^.*Executed_Gtid_Set: //' -e 's/ //g')
      fi

      if [[ "$SOFT" = pxc* ]] ; then
        systemctl stop $MYSQLD_UNIT
        mysqld --user=mysql --wsrep-provider=none &>/dev/null &
        until mysqladmin --silent --connect-timeout=30 --wait=4 ping ; do sleep 5 ; done
        mysql << EOF
          RESET SLAVE ALL;
          RESET MASTER;
          SET GLOBAL GTID_PURGED='${GTID}';
EOF
        mysqladmin shutdown
        systemctl start $MYSQLD_UNIT
        until mysqladmin --silent --connect-timeout=30 --wait=4 ping ; do sleep 5 ; done
        mysql << EOF
          CHANGE MASTER TO MASTER_HOST='${MASTER_IP}', MASTER_USER='${MASTER_USER}', MASTER_PASSWORD='${MASTER_PASSWORD}', MASTER_AUTO_POSITION=1, MASTER_SSL=1;
          START SLAVE;
EOF
      else # GTID, non-pxc
        if [[ "x$CHANNEL" = x ]] ; then
          # dump restore if source has non-default databases
          if [[ $(mysql --host $MASTER_IP -Ne 'show databases;'|egrep -v '^(information_schema|performance_schema|mysql|sys)$'|wc -l) -gt 0 ]] ; then
            mysqldump --host $MASTER_IP --databases $(mysql --host $MASTER_IP -Ne 'show databases;'|egrep -v '^(information_schema|performance_schema|mysql|sys)$') | mysql
          fi
          mysql << EOF
          RESET MASTER;
          SET GLOBAL GTID_PURGED='${GTID}';
          STOP SLAVE;
          CHANGE MASTER TO MASTER_HOST='${MASTER_IP}', MASTER_USER='${MASTER_USER}', MASTER_PASSWORD='${MASTER_PASSWORD}', MASTER_AUTO_POSITION=1, MASTER_SSL=1;
          START SLAVE;
EOF
        else
          mysql << EOF
          RESET MASTER;
          SET GLOBAL GTID_PURGED=CONCAT(@@gtid_purged, ',${GTID}');
          STOP SLAVE;
          CHANGE MASTER TO MASTER_HOST='${MASTER_IP}', MASTER_USER='${MASTER_USER}', MASTER_PASSWORD='${MASTER_PASSWORD}', MASTER_AUTO_POSITION=1, MASTER_SSL=1 FOR CHANNEL '${CHANNEL}';
          START SLAVE;
EOF
        fi
      fi


      rm "${MINF}"
      touch /root/replication.configured
  elif [[ "x$TYPE" == "xnogtid" ]] ; then # non-gtid, non-mariadb
    setup_replication "127.0.0.1" "$MASTER_USER" "$MASTER_PASSWORD" "$MASTER_IP" "$MASTER_USER" "$MASTER_PASSWORD"
  fi
fi

if [[ "x$TYPE" == "xgalera" ]] ; then
    MYIP=$(/vagrant/tools/node_ip.sh)
    systemctl stop $MYSQLD_UNIT
    # pre-requirement
    # vagrant ssh default -- sudo tar cz /var/lib/mysql/ca.pem /var/lib/mysql/ca-key.pem /var/lib/mysql/client-cert.pem /var/lib/mysql/client-key.pem /var/lib/mysql/server-cert.pem /var/lib/mysql/server-key.pem |vagrant ssh node1 -- sudo tar -C / -xz
    rm -rf /var/lib/mysql/*
    [ -f /vagrant/secret/"${CLUSTER_NAME}-ssl.tar.gz" ] && tar -C / -xzf /vagrant/secret/"${CLUSTER_NAME}-ssl.tar.gz"
    cat >> "${CNF_FILE}" << EOF
[mysqld]
wsrep_cluster_name=${CLUSTER_NAME}
wsrep_node_name=${MYIP}
wsrep_cluster_address="gcomm://${MASTER_IP}"
EOF
    mysqld --user=mysql &>/dev/null &
    until mysqladmin --silent --connect-timeout=30 --wait=4 ping ; do sleep 5 ; done
    mysqladmin shutdown

    systemctl start $MYSQLD_UNIT
fi


# todo replace with jq
rawurlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"    # You can either set a return variable (FASTER)
  REPLY="${encoded}"   #+or echo the result (EASIER)... or both... :p
}


# Group Replication aka InnoDB Cluster
if [[ "x$TYPE" == "xgroup" ]] ; then
  until mysql --host="$MASTER_IP" --silent --connect-timeout=30 --wait -e "SELECT 1;" > /dev/null 2>&1 ; do sleep 5 ; done
  until mysql --silent --connect-timeout=30 --wait -e "SELECT 1;" > /dev/null 2>&1 ; do sleep 5 ; done


#  mysql --host $MASTER_IP -e 'DROP VIEW IF EXISTS mysql.nonexisting_23498985;'
#  mysql -e 'DROP VIEW IF EXISTS mysql.nonexisting_23498985;'

  rawurlencode "$MASTER_PASSWORD"
  MASTER_PASSWORD_URIENC="$REPLY"
  MYIP=$(/vagrant/tools/node_ip.sh)
  while ! mysqlsh "${MASTER_USER}:${MASTER_PASSWORD_URIENC}@$MASTER_IP" \
      -e 'var cluster=dba.getCluster();print(cluster.status())' 2>/dev/null|grep -q "$CLUSTER_NAME" ; do
    sleep 5
  done

  SSH="ssh -i /vagrant/secret/id_rsa -o StrictHostKeyChecking=no -o PasswordAuthentication=no"

  # allow only one active cluster.addInstance() call
  until echo 'set -o noclobber;{ > /root/add-group-member ; } &> /dev/null'| $SSH root@$MASTER_IP bash ; do
    sleep 1
  done

  mysqlsh "${MASTER_USER}:${MASTER_PASSWORD_URIENC}@$MASTER_IP" \
      -e "var c=dba.getCluster();c.addInstance('$MASTER_USER:$MASTER_PASSWORD_URIENC@$MYIP:3306', {recoveryMethod: 'clone', label: '$MYIP'})" || true

  sleep 10
  until mysql --silent --connect-timeout=30 --wait -e "SELECT 1;" > /dev/null 2>&1 ; do sleep 5 ; done
  until mysql --connect-timeout=30 --wait \
    -e "SELECT STATE FROM performance_schema.clone_status;" 2> /dev/null | grep -q Completed
  do sleep 6 ; done

  if mysqlsh "${MASTER_USER}:${MASTER_PASSWORD_URIENC}@$MASTER_IP" \
      -e 'var cluster=dba.getCluster();print(cluster.status())' 2>/dev/null|grep -q "Use cluster.rescan"
  then
    mysqlsh "${MASTER_USER}:${MASTER_PASSWORD_URIENC}@$MASTER_IP" \
      -e "var cluster=dba.getCluster();cluster.rescan({interactive: false, addInstances: 'auto'})" || true
  fi

  $SSH root@$MASTER_IP rm -f /root/add-group-member
  
fi
