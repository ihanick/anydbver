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
  while true ; do
    while $SSH root@$MASTER_IP ls /root/add-group-member | grep -q add-group-member ; do
      sleep 1
    done
    if $SSH root@$MASTER_IP 'flock -w 5 -x -E 1 /root/.my.cnf -c "touch /root/add-group-member"' ; then
      break
    fi
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
