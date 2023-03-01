#!/bin/sh
PLATFORM=linux/amd64
if uname -m |grep -q aarch64 ; then
  PLATFORM=linux/arm64
fi
cd centos7
test -f ../../secret/id_rsa || ssh-keygen -t rsa -f ../../secret/id_rsa -P '' && chmod 0600 ../../secret/id_rsa
cp ../../tools/node_ip.sh ../../secret/id_rsa.pub ./
docker build --platform $PLATFORM -t centos:7-sshd-systemd-$USER .
cd ../rockylinux8
test -f ../../secret/id_rsa || ssh-keygen -t rsa -f ../../secret/id_rsa -P '' && chmod 0600 ../../secret/id_rsa
cp ../../tools/node_ip.sh ../../secret/id_rsa.pub ./
docker build --platform $PLATFORM -t rockylinux:8-sshd-systemd-$USER .
cd ../rockylinux9
test -f ../../secret/id_rsa || ssh-keygen -t rsa -f ../../secret/id_rsa -P '' && chmod 0600 ../../secret/id_rsa
cp ../../tools/node_ip.sh ../../secret/id_rsa.pub ./
docker build --platform $PLATFORM -t rockylinux:9-sshd-systemd-$USER .
cd ../jammy
test -f ../../secret/id_rsa || ssh-keygen -t rsa -f ../../secret/id_rsa -P '' && chmod 0600 ../../secret/id_rsa
cp ../../tools/node_ip.sh ../../secret/id_rsa.pub ./
docker build --platform $PLATFORM -t ubuntu:jammy-sshd-systemd-$USER .
cd ../..
tar -czf ansible-ssh-docker/ansible-anydbver/anydbver.tar.gz .
cd ansible-ssh-docker/ansible-anydbver/
docker build -t rockylinux:8-anydbver-ansible-$USER .
