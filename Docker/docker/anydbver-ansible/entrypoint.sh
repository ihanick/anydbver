#!/bin/bash
cd /root/anydbver
./anydbver configure provider:existing
exec /usr/sbin/init
