#!/bin/sh
cd rockylinux8
test -f ../../secret/id_rsa || ssh-keygen -t rsa -f ../../secret/id_rsa -P '' && chmod 0600 ../../secret/id_rsa
cp ../../tools/node_ip.sh ../../secret/id_rsa.pub ./
docker build -t rockylinux:8-sshd-systemd .
cd ../ansible-anydbver
tar -czf anydbver.tar.gz ../../
docker build -t rockylinux:8-anydbver-ansible .
