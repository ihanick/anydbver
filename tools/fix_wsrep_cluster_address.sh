#!/bin/bash
CNF_FILE=$1
NODES=$(mysql -Ne "show status like 'wsrep_incoming_addresses'"|awk '{gsub(/:3306/,"");print $2}')

[ "x$CNF_FILE" = "x" ] && CNF_FILE=$(cat /root/mysql.conf.filename)

if grep -q wsrep_cluster_address $CNF_FILE ; then
  sed -i -re "s|^\s*wsrep_cluster_address=.*$|wsrep_cluster_address=gcomm://$NODES|" "$CNF_FILE"
else
  echo "wsrep_cluster_address=gcomm://$NODES" >>  "$CNF_FILE"
fi
