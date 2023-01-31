#!/bin/sh
cd centos7
test -f ../../secret/id_rsa || ssh-keygen -t rsa -f ../../secret/id_rsa -P '' && chmod 0600 ../../secret/id_rsa
cp ../../tools/node_ip.sh ../../secret/id_rsa.pub ./
docker build --platform linux/amd64 -t centos:7-sshd-systemd .
cd ../rockylinux8
test -f ../../secret/id_rsa || ssh-keygen -t rsa -f ../../secret/id_rsa -P '' && chmod 0600 ../../secret/id_rsa
cp ../../tools/node_ip.sh ../../secret/id_rsa.pub ./
docker build --platform linux/amd64 -t rockylinux:8-sshd-systemd .
cd ../rockylinux9
test -f ../../secret/id_rsa || ssh-keygen -t rsa -f ../../secret/id_rsa -P '' && chmod 0600 ../../secret/id_rsa
cp ../../tools/node_ip.sh ../../secret/id_rsa.pub ./
docker build --platform linux/amd64 -t rockylinux:9-sshd-systemd .
cd ../jammy
test -f ../../secret/id_rsa || ssh-keygen -t rsa -f ../../secret/id_rsa -P '' && chmod 0600 ../../secret/id_rsa
cp ../../tools/node_ip.sh ../../secret/id_rsa.pub ./
docker build --platform linux/amd64 -t ubuntu:jammy-sshd-systemd .
cd ../..
tar -czf ansible-ssh-docker/ansible-anydbver/anydbver.tar.gz .
cd ansible-ssh-docker/ansible-anydbver/
docker build -t rockylinux:8-anydbver-ansible .
