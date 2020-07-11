#!/bin/bash
MASTER=$1
USER=postgres
DB=postgres
PASS=$2
cd /etc/pgpool-II
pg_md5 --md5auth --username=$USER $PASS

echo $(/vagrant/tools/node_ip.sh):5432:*:$USER:$PASS > ~/.pgpass
echo "*:5432:*:$USER:$PASS" >> ~/.pgpass
chmod 0600 ~/.pgpass

SLAVE=$(psql -X -A -d $DB -U $USER -h $MASTER -t -c 'select client_addr from pg_stat_replication LIMIT 1')

if [ $SLAVE != "" ] ; then
  sed \
    -e "s/listen_addresses = 'localhost'/listen_addresses = '*'/" \
    -e "s/backend_hostname0 = 'host1'/backend_hostname0 = '$MASTER'/" \
    -e "s/#backend_hostname1 = 'host2'/backend_hostname1 = '$SLAVE'/" \
    -e "s/#backend_port1 = 5433/backend_port1 = 5432/" \
    -e "s/#backend_weight1 = 1/backend_weight1 = 1/" \
    -e "s,#backend_data_directory1 = '/data1',backend_data_directory1 = '/data1'," \
    -e "s/#backend_flag1 = 'ALLOW_TO_FAILOVER'/backend_flag1 = 'ALLOW_TO_FAILOVER'/" \
    -e "s/#backend_application_name1 = 'server1'/backend_application_name1 = 'server1'/" \
    -e "s/sr_check_user = 'nobody'/sr_check_user = '$USER'/" \
    -e "s/^port = 9999/port = 5432/" \
    pgpool.conf.sample-stream > /etc/pgpool-II/pgpool.conf
else
  sed \
      -e "s/listen_addresses = 'localhost'/listen_addresses = '*'/" \
      -e "s/backend_hostname0 = 'host1'/backend_hostname0 = '$MASTER'/" \
      -e "s/sr_check_user = 'nobody'/sr_check_user = '$USER'/" \
      -e "s/^port = 9999/port = 5432/" \
      pgpool.conf.sample-stream > /etc/pgpool-II/pgpool.conf
fi

touch /root/pgpool.applied
