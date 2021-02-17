#!/bin/bash

MASTER_IP=$1
MASTER_USER="$2"
MASTER_PASSWORD="$3"

if [ ! -f /usr/bin/mysql ] ; then
	  yum install -y mysql
  fi

  mysql -u "$MASTER_USER" --host "$MASTER_IP" --password="$MASTER_PASSWORD" <<EOF
GRANT REPLICATION CLIENT ON *.* TO repl@'%' IDENTIFIED BY '$MASTER_PASSWORD';
EOF
  mysql -u "$MASTER_USER" --host "$MASTER_IP" --password="$MASTER_PASSWORD" <<EOF
CREATE USER repl@'%' IDENTIFIED WITH mysql_native_password BY '$MASTER_PASSWORD';
GRANT REPLICATION CLIENT ON *.* TO repl@'%';
EOF

mysql --force --protocol=tcp --host=127.0.0.1 --port 6032 -uadmin -padmin --prompt='Admin> ' <<EOF
SET mysql-monitor_username='repl';
SET mysql-monitor_password='$MASTER_PASSWORD';
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;

INSERT INTO mysql_users (username,password, default_hostgroup) VALUES ('$MASTER_USER','$MASTER_PASSWORD',1);
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;

INSERT INTO mysql_galera_hostgroups (writer_hostgroup, reader_hostgroup,backup_writer_hostgroup,offline_hostgroup, active,max_writers,writer_is_also_reader,max_transactions_behind) VALUES(1,2,3,4, 1,1,0,100);

INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight) VALUES (2,'$MASTER_IP',3306,1);
EOF

for i in $(mysql -N -u "$MASTER_USER" --host "$MASTER_IP" --password="$MASTER_PASSWORD" -e "show status like 'wsrep_incoming_addresses'\\G"|grep :3306|sed -re 's/:3306,?/ /g')
do
  [[ "$i" == "$MASTER_IP" ]] && continue
  mysql -h $i -u "$MASTER_USER" --password="$MASTER_PASSWORD" -e 'set global read_only=1;'
  mysql --force --protocol=tcp --host=127.0.0.1 --port 6032 -uadmin -padmin --prompt='Admin> ' <<EOF
INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight) VALUES (2,'$i',3306,1);
EOF
done

mysql --force --protocol=tcp --host=127.0.0.1 --port 6032 -uadmin -padmin --prompt='Admin> ' <<EOF
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
INSERT INTO mysql_query_rules (active, match_pattern, destination_hostgroup, cache_ttl) VALUES (1, '^SELECT .* FOR UPDATE', 1, NULL);
INSERT INTO mysql_query_rules (active, match_pattern, destination_hostgroup, cache_ttl) VALUES (1, '^SELECT .*', 2, NULL);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;

set admin-admin_credentials="admin:admin;radmin:radmin";
update global_variables set variable_value='radmin' where variable_name='admin-cluster_username';
update global_variables set variable_value='radmin' where variable_name='admin-cluster_password';
update global_variables set variable_value=200 where variable_name='admin-cluster_check_interval_ms';
update global_variables set variable_value=100 where variable_name='admin-cluster_check_status_frequency';
update global_variables set variable_value='true' where variable_name='admin-cluster_mysql_query_rules_save_to_disk';
update global_variables set variable_value='true' where variable_name='admin-cluster_mysql_servers_save_to_disk';
update global_variables set variable_value='1200' where variable_name='mysql-monitor_galera_healthcheck_timeout';
update global_variables set variable_value='6000' where variable_name='mysql-monitor_galera_healthcheck_interval';

LOAD ADMIN VARIABLES TO RUNTIME;
SAVE ADMIN VARIABLES TO DISK;
EOF
