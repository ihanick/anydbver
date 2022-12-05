#!/bin/sh
test -f ../../secret/id_rsa || ssh-keygen -t rsa -f ../../secret/id_rsa -P '' && chmod 0600 ../../secret/id_rsa
cp ../../tools/node_ip.sh ../../secret/id_rsa.pub ./
docker build -t rockylinux:8-sshd-systemd .
