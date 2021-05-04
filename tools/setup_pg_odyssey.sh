#!/bin/bash
DB_IP=$1
USER=postgres
DB=postgres
PASS=$2

PASS_HASH=$(echo -n "md5"; echo -n "$PASS$USER" | md5sum | awk '{print $1}')

mkdir /etc/odyssey
curl -sL --output /etc/odyssey/odyssey.conf https://github.com/yandex/odyssey/raw/1.1/odyssey.conf
curl -SL --output /etc/systemd/system/odyssey.service https://raw.githubusercontent.com/yandex/odyssey/master/scripts/systemd/odyssey.service
sed -i \
  -e 's/host "localhost"/host "'$DB_IP'"/' \
  -e 's/authentication "none"/authentication "md5"/' \
  -e 's/.*password ""/\t\tpassword "'$PASS_HASH'"/' \
  -e 's/port 6432/port 5432/' \
  /etc/odyssey/odyssey.conf

useradd -m odyssey
systemctl daemon-reload
systemctl start odyssey
