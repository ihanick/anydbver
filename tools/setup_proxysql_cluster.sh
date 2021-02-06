#!/bin/bash

MASTER_IP=$1
MASTER_USER="$2"
MASTER_PASSWORD="$3"
MYSQL_PASSWORD="$4"
NODE_IP=$(node_ip.sh)

if [ ! -f /usr/bin/mysql ] ; then
	  yum install -y mysql
  fi

mysql --force --protocol=tcp --host=127.0.0.1 --port 6032 -uadmin -padmin --prompt='Admin> ' <<EOF
SET mysql-monitor_username='repl';
SET mysql-monitor_password='secret';
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;

set admin-admin_credentials="admin:admin;radmin:radmin";
update global_variables set variable_value='radmin' where variable_name='admin-cluster_username';
update global_variables set variable_value='radmin' where variable_name='admin-cluster_password';
update global_variables set variable_value=200 where variable_name='admin-cluster_check_interval_ms';
update global_variables set variable_value=100 where variable_name='admin-cluster_check_status_frequency';
update global_variables set variable_value='true' where variable_name='admin-cluster_mysql_query_rules_save_to_disk';
update global_variables set variable_value='true' where variable_name='admin-cluster_mysql_servers_save_to_disk';

UPDATE global_variables SET variable_value=1000 where variable_name='admin-cluster_check_interval_ms';
UPDATE global_variables SET variable_value=10 where variable_name='admin-cluster_check_status_frequency';
UPDATE global_variables SET variable_value='true' where variable_name='admin-cluster_mysql_query_rules_save_to_disk';
UPDATE global_variables SET variable_value='true' where variable_name='admin-cluster_mysql_servers_save_to_disk';
UPDATE global_variables SET variable_value='true' where variable_name='admin-cluster_mysql_users_save_to_disk';
UPDATE global_variables SET variable_value='true' where variable_name='admin-cluster_proxysql_servers_save_to_disk';
UPDATE global_variables SET variable_value=3 where variable_name='admin-cluster_mysql_query_rules_diffs_before_sync';
UPDATE global_variables SET variable_value=3 where variable_name='admin-cluster_mysql_servers_diffs_before_sync';
UPDATE global_variables SET variable_value=3 where variable_name='admin-cluster_mysql_users_diffs_before_sync';
UPDATE global_variables SET variable_value=3 where variable_name='admin-cluster_proxysql_servers_diffs_before_sync';

LOAD ADMIN VARIABLES TO RUNTIME;
SAVE ADMIN VARIABLES TO DISK;
EOF

mysqldump -uradmin -pradmin --port 6032 --protocol=tcp --host $MASTER_IP --no-create-info --skip-lock-tables --skip-opt --skip-add-locks --skip-triggers --no-tablespaces --skip-comments 0 proxysql_servers|grep ^INSERT > /root/proxysql_servers.sql

if [[ $( wc -l < /root/proxysql_servers.sql ) == 0 ]] ; then

mysql --force --protocol=tcp --host=$MASTER_IP --port 6032 -u$MASTER_USER -p$MASTER_PASSWORD --prompt='Admin> ' <<EOF
UPDATE global_variables SET variable_value='radmin' where variable_name='admin-cluster_password';
UPDATE global_variables SET variable_value='radmin' where variable_name='admin-cluster_username';
UPDATE global_variables SET variable_value=1000 where variable_name='admin-cluster_check_interval_ms';
UPDATE global_variables SET variable_value=10 where variable_name='admin-cluster_check_status_frequency';
UPDATE global_variables SET variable_value='true' where variable_name='admin-cluster_mysql_query_rules_save_to_disk';
UPDATE global_variables SET variable_value='true' where variable_name='admin-cluster_mysql_servers_save_to_disk';
UPDATE global_variables SET variable_value='true' where variable_name='admin-cluster_mysql_users_save_to_disk';
UPDATE global_variables SET variable_value='true' where variable_name='admin-cluster_proxysql_servers_save_to_disk';
UPDATE global_variables SET variable_value=3 where variable_name='admin-cluster_mysql_query_rules_diffs_before_sync';
UPDATE global_variables SET variable_value=3 where variable_name='admin-cluster_mysql_servers_diffs_before_sync';
UPDATE global_variables SET variable_value=3 where variable_name='admin-cluster_mysql_users_diffs_before_sync';
UPDATE global_variables SET variable_value=3 where variable_name='admin-cluster_proxysql_servers_diffs_before_sync';
LOAD ADMIN variables to RUNTIME;
SAVE ADMIN variables to disk;

INSERT INTO proxysql_servers (hostname,port,weight) VALUES ('$MASTER_IP',6032,0);
INSERT INTO proxysql_servers (hostname,port,weight) VALUES ('$NODE_IP',6032,0);
LOAD PROXYSQL SERVERS TO RUNTIME;
SAVE PROXYSQL SERVERS TO DISK;
EOF


mysql --force --protocol=tcp --host=127.0.0.1 --port 6032 -uadmin -padmin --prompt='Admin> ' <<EOF
INSERT INTO proxysql_servers (hostname,port,weight) VALUES ('$MASTER_IP',6032,0);
INSERT INTO proxysql_servers (hostname,port,weight) VALUES ('$NODE_IP',6032,0);
LOAD PROXYSQL SERVERS TO RUNTIME;
SAVE PROXYSQL SERVERS TO DISK;
EOF
else
mysql --force --protocol=tcp --host=$MASTER_IP --port 6032 -u$MASTER_USER -p$MASTER_PASSWORD --prompt='Admin> ' <<EOF
INSERT INTO proxysql_servers (hostname,port,weight) VALUES ('$NODE_IP',6032,0);
LOAD PROXYSQL SERVERS TO RUNTIME;
SAVE PROXYSQL SERVERS TO DISK;
EOF

mysqldump -uradmin -pradmin --port 6032 --protocol=tcp --host $MASTER_IP --no-create-info --skip-lock-tables --skip-opt --skip-add-locks --skip-triggers --no-tablespaces --skip-comments 0 proxysql_servers|grep ^INSERT | mysql --force --protocol=tcp --host='127.0.0.1' --port 6032 -uadmin -padmin --prompt='Admin> ' 
mysql --force --protocol=tcp --host=127.0.0.1 --port 6032 -uadmin -padmin --prompt='Admin> ' <<EOF
LOAD PROXYSQL SERVERS TO RUNTIME;
SAVE PROXYSQL SERVERS TO DISK;
EOF

fi



#mysqldump -uadmin -padmin --port 6032 --protocol=tcp --no-create-info --skip-lock-tables --skip-opt --skip-add-locks --skip-triggers --no-tablespaces --skip-comments 0 proxysql_servers|grep ^INSERT

