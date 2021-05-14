#!/bin/bash
CNF_FILE=$1

[ "x$CNF_FILE" = "x" -a -f /root/mysql.conf.filename ] && CNF_FILE=$(cat /root/mysql.conf.filename)

if ! [ -f "$CNF_FILE" ] ; then exit 0 ; fi

NODES=$(mysql -Ne "show status like 'wsrep_incoming_addresses'"|awk '{gsub(/:3306/,"");print $2}')

if grep -q wsrep_cluster_address $CNF_FILE ; then
  sed -i -re "s|^\s*wsrep_cluster_address\s*=.*$|wsrep_cluster_address=gcomm://$NODES|" "$CNF_FILE"
else
  echo "wsrep_cluster_address=gcomm://$NODES" >>  "$CNF_FILE"
fi
