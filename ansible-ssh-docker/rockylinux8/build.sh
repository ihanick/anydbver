#!/bin/sh
cp ../../tools/node_ip.sh ../../secret/id_rsa.pub ./
docker build -t rockylinux:8-sshd-systemd .
