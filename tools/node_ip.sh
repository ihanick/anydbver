#!/bin/bash
DEV=$(ip ro ls |grep default | cut -d' ' -f 5)
ip4=$(/sbin/ip -o -4 addr list $DEV | awk '{print $4}' | cut -d/ -f1)
echo $ip4
