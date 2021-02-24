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

SERVER_ID=$(ip addr ls|grep 'inet '|grep -v '127.0.0.1'|awk '{print $2}'|cut -d/ -f 1|awk -F '\\.' '{print ($1 * 2^24) + ($2 * 2^16) + ($3 * 2^8) + $4}')


if [ "x$SOFT" = "xmariadb_server" ] ; then
  if [[ "x$TYPE" == "xgtid" ]] ; then
      GTID=$(mysql --host $MASTER_IP -N -e "SELECT @@GLOBAL.gtid_current_pos")
      GTID_CUR=$(mysql -N -e "SELECT @@GLOBAL.gtid_current_pos")

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

      rm "${MINF}"
      touch /root/replication.configured
  fi
else
  if [[ "x$TYPE" == "xgtid" ]] ; then
      mysql --host $MASTER_IP -e 'DROP VIEW IF EXISTS mysql.nonexisting_23498985;show master status\G' > "$MINF"
      GTID= $( awk -F': ' '/Executed_Gtid_Set/ {print $2}' "$MINF" )

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
      else
        mysql << EOF
        RESET MASTER;
        SET GLOBAL GTID_PURGED='${GTID}';
        STOP SLAVE;
        CHANGE MASTER TO MASTER_HOST='${MASTER_IP}', MASTER_USER='${MASTER_USER}', MASTER_PASSWORD='${MASTER_PASSWORD}', MASTER_AUTO_POSITION=1, MASTER_SSL=1;
        START SLAVE;
EOF
      fi


      rm "${MINF}"
      touch /root/replication.configured
  fi
fi

if [[ "x$TYPE" == "xgalera" ]] ; then
    systemctl stop $MYSQLD_UNIT
    # pre-requirement
    # vagrant ssh default -- sudo tar cz /var/lib/mysql/ca.pem /var/lib/mysql/ca-key.pem /var/lib/mysql/client-cert.pem /var/lib/mysql/client-key.pem /var/lib/mysql/server-cert.pem /var/lib/mysql/server-key.pem |vagrant ssh node1 -- sudo tar -C / -xz
    rm -rf /var/lib/mysql/*
    tar -C / -xzf /vagrant/secret/"${CLUSTER_NAME}-ssl.tar.gz"
    cat >> "${CNF_FILE}" << EOF
[mysqld]
wsrep_cluster_name=${CLUSTER_NAME}
wsrep_node_name=${CLUSTER_NAME}-node-${SERVER_ID}
wsrep_cluster_address="gcomm://${MASTER_IP}"
EOF
    mysqld --user=mysql &>/dev/null &
    until mysqladmin --silent --connect-timeout=30 --wait=4 ping ; do sleep 5 ; done
    mysqladmin shutdown

    systemctl start $MYSQLD_UNIT
fi


# Group Replication aka InnoDB Cluster
if [[ "x$TYPE" == "xgroup" ]] ; then
    MYIP=$(/vagrant/tools/node_ip.sh)
    if ! mysqlsh "${MASTER_USER}:${MASTER_PASSWORD}@$MASTER_IP" \
        -e 'var cluster=dba.getCluster();print(cluster.status())' 2>/dev/null|grep -q "$CLUSTER_NAME" ; then
        mysqlsh "${MASTER_USER}:${MASTER_PASSWORD}@$MASTER_IP" -e "dba.createCluster('$CLUSTER_NAME', {localAddress: '$MASTER_IP:33061'})"
    fi

    mysqlsh "${MASTER_USER}:${MASTER_PASSWORD}@$MASTER_IP" \
        -e "var c=dba.getCluster();c.addInstance('$MASTER_USER:$MASTER_PASSWORD@$MYIP:3306', {localAddress: '$MYIP:33061', recoveryMethod: 'clone', label: '$MYIP'})"
fi
