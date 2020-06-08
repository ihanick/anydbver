#!/bin/bash
CNF_FILE=$1
mysql -Ne 'show status like "wsrep_incoming_addresses"\G'|grep -F ,|sed -e 's/:3306//g' -e 's,^,wsrep_cluster_address=gcomm://,' >> $CNF_FILE
