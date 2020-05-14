#!/bin/bash
CONFDEST="$1"
CONFPART="$2"

SERVER_ID=$(ip addr ls|grep 'inet '|grep -v '127.0.0.1'|awk '{print $2}'|cut -d/ -f 1|awk -F '\\.' '{print ($1 * 2^24) + ($2 * 2^16) + ($3 * 2^8) + $4}')
sed -e "s/server_id=.*\$/server_id=$SERVER_ID/" "$CONFPART" >> "$CONFDEST"
touch /root/$( basename $CONFPART).applied
