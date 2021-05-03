#!/bin/bash

MASTER_IP=$1
MASTER_USER="$2"
MASTER_PASSWORD="$3"

if [ ! -f /usr/bin/mysql ] ; then
  yum install -y mysql
fi

if ! mysql -uroot -psecret -h 10.218.29.38 -e "show create user repl@'%'" &>/dev/null ; then
  mysql --force -u "$MASTER_USER" --host "$MASTER_IP" --password="$MASTER_PASSWORD" <<EOF
CREATE USER repl@'%' IDENTIFIED WITH mysql_native_password BY '$MASTER_PASSWORD';
GRANT REPLICATION CLIENT ON *.* TO repl@'%';
GRANT SELECT ON sys.* TO repl@'%';
EOF
  mysql -u "$MASTER_USER" --host "$MASTER_IP" --password="$MASTER_PASSWORD" << 'EOF'
USE sys;

DELIMITER $$

CREATE FUNCTION IFZERO(a INT, b INT)
RETURNS INT
DETERMINISTIC
RETURN IF(a = 0, b, a)$$

CREATE FUNCTION LOCATE2(needle TEXT(10000), haystack TEXT(10000), offset INT)
RETURNS INT
DETERMINISTIC
RETURN IFZERO(LOCATE(needle, haystack, offset), LENGTH(haystack) + 1)$$

CREATE FUNCTION GTID_NORMALIZE(g TEXT(10000))
RETURNS TEXT(10000)
DETERMINISTIC
RETURN GTID_SUBTRACT(g, '')$$

CREATE FUNCTION GTID_COUNT(gtid_set TEXT(10000))
RETURNS INT
DETERMINISTIC
BEGIN
  DECLARE result BIGINT DEFAULT 0;
  DECLARE colon_pos INT;
  DECLARE next_dash_pos INT;
  DECLARE next_colon_pos INT;
  DECLARE next_comma_pos INT;
  SET gtid_set = GTID_NORMALIZE(gtid_set);
  SET colon_pos = LOCATE2(':', gtid_set, 1);
  WHILE colon_pos != LENGTH(gtid_set) + 1 DO
     SET next_dash_pos = LOCATE2('-', gtid_set, colon_pos + 1);
     SET next_colon_pos = LOCATE2(':', gtid_set, colon_pos + 1);
     SET next_comma_pos = LOCATE2(',', gtid_set, colon_pos + 1);
     IF next_dash_pos < next_colon_pos AND next_dash_pos < next_comma_pos THEN
       SET result = result +
         SUBSTR(gtid_set, next_dash_pos + 1,
                LEAST(next_colon_pos, next_comma_pos) - (next_dash_pos + 1)) -
         SUBSTR(gtid_set, colon_pos + 1, next_dash_pos - (colon_pos + 1)) + 1;
     ELSE
       SET result = result + 1;
     END IF;
     SET colon_pos = next_colon_pos;
  END WHILE;
  RETURN result;
END$$

CREATE FUNCTION gr_applier_queue_length()
RETURNS INT
DETERMINISTIC
BEGIN
  RETURN (SELECT sys.gtid_count( GTID_SUBTRACT( (SELECT
Received_transaction_set FROM performance_schema.replication_connection_status
WHERE Channel_name = 'group_replication_applier' ), (SELECT
@@global.GTID_EXECUTED) )));
END$$

CREATE FUNCTION my_server_uuid() RETURNS TEXT(36) DETERMINISTIC NO SQL RETURN (SELECT @@global.server_uuid as my_id);$$

CREATE FUNCTION gr_member_in_primary_partition()
RETURNS VARCHAR(3)
DETERMINISTIC
BEGIN
  RETURN (SELECT IF( MEMBER_STATE='ONLINE' AND ((SELECT COUNT(*) FROM
performance_schema.replication_group_members WHERE MEMBER_STATE != 'ONLINE') >=
((SELECT COUNT(*) FROM performance_schema.replication_group_members)/2) = 0),
'YES', 'NO' ) FROM performance_schema.replication_group_members JOIN
performance_schema.replication_group_member_stats USING(member_id) 
WHERE MEMBER_ID=@@global.server_uuid);
END$$

CREATE VIEW gr_member_routing_candidate_status AS SELECT
sys.gr_member_in_primary_partition() as viable_candidate,
IF( (SELECT (SELECT GROUP_CONCAT(variable_value) FROM
performance_schema.global_variables WHERE variable_name IN ('read_only',
'super_read_only')) != 'OFF,OFF'), 'YES', 'NO') as read_only,
sys.gr_applier_queue_length() as transactions_behind, Count_Transactions_in_queue as 'transactions_to_cert' from performance_schema.replication_group_member_stats
WHERE MEMBER_ID=my_server_uuid();$$

DELIMITER ;
EOF
fi

mysql --force --protocol=tcp --host=127.0.0.1 --port 6032 -uadmin -padmin --prompt='Admin> ' <<EOF
SET mysql-monitor_username='repl';
SET mysql-monitor_password='$MASTER_PASSWORD';
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;

INSERT INTO mysql_users (username,password, default_hostgroup) VALUES ('$MASTER_USER','$MASTER_PASSWORD',1);
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;

INSERT INTO mysql_group_replication_hostgroups (writer_hostgroup, reader_hostgroup,backup_writer_hostgroup,offline_hostgroup, active,max_writers,writer_is_also_reader,max_transactions_behind) VALUES(1,2,3,4, 1,1,0,100);

INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight) VALUES (2,'$MASTER_IP',3306,1);
EOF

for i in $(mysql -N -u "$MASTER_USER" --host "$MASTER_IP" --password="$MASTER_PASSWORD" -e "select MEMBER_HOST from performance_schema.replication_group_members;"|cat)
do
  [[ "$i" == "$MASTER_IP" ]] && continue
  #mysql -h $i -u "$MASTER_USER" --password="$MASTER_PASSWORD" -e 'set global read_only=1;'
  mysql --force --protocol=tcp --host=127.0.0.1 --port 6032 -uadmin -padmin --prompt='Admin> ' <<EOF
INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight) VALUES (2,'$i',3306,1);
EOF
done

mysql --force --protocol=tcp --host=127.0.0.1 --port 6032 -uadmin -padmin --prompt='Admin> ' <<EOF
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
INSERT INTO mysql_query_rules (active, match_pattern, destination_hostgroup, cache_ttl) VALUES (1, '^SELECT .*', 2, NULL);
INSERT INTO mysql_query_rules (active, match_pattern, destination_hostgroup, cache_ttl) VALUES (1, '^SELECT .* FOR UPDATE', 1, NULL);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;

set admin-admin_credentials="admin:admin;radmin:radmin";
update global_variables set variable_value='radmin' where variable_name='admin-cluster_username';
update global_variables set variable_value='radmin' where variable_name='admin-cluster_password';
update global_variables set variable_value=200 where variable_name='admin-cluster_check_interval_ms';
update global_variables set variable_value=100 where variable_name='admin-cluster_check_status_frequency';
update global_variables set variable_value='true' where variable_name='admin-cluster_mysql_query_rules_save_to_disk';
update global_variables set variable_value='true' where variable_name='admin-cluster_mysql_servers_save_to_disk';

LOAD ADMIN VARIABLES TO RUNTIME;
SAVE ADMIN VARIABLES TO DISK;
EOF
