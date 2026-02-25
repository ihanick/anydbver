#!/bin/bash
# docker images --format "{{.Repository}}:{{.Tag}}" | grep -w "0.1.23"|xargs -n 1 docker push
PLATFORM=linux/amd64
IMAGE_PUBLISHER=zelmar
IMAGE_VERSION="0.1.30"
PLATFORM_TAG=""
if uname -m | egrep -q 'aarch64|arm64'; then
  PLATFORM=linux/arm64
  PLATFORM_TAG="-arm64"
fi
test -f ../secret/id_rsa || ssh-keygen -t rsa -f ../secret/id_rsa -P ''
cd centos7
cp ../../tools/node_ip.sh ../common/rc.local ./
docker build --platform $PLATFORM -t centos:7-sshd-systemd-$USER .
cd ../rockylinux8
cp ../../tools/node_ip.sh ../common/rc.local ../common/rc-local.service ./
docker build --platform $PLATFORM -t rockylinux:8-sshd-systemd-$USER .
cd ../rockylinux9
cp ../../tools/node_ip.sh ../common/rc.local ../common/rc-local.service ./
docker build --platform $PLATFORM -t rockylinux:9-sshd-systemd-$USER .
cd ../rockylinux10
cp ../../tools/node_ip.sh ../common/rc.local ../common/rc-local.service ./
docker build --platform $PLATFORM -t rockylinux:10-sshd-systemd-$USER .
cd ../focal
cp ../../tools/node_ip.sh ../common/rc.local ../common/rc-local.service ./
docker build --platform $PLATFORM -t ubuntu:focal-sshd-systemd-$USER .
cd ../jammy
cp ../../tools/node_ip.sh ../common/rc.local ../common/rc-local.service ./
docker build --platform $PLATFORM -t ubuntu:jammy-sshd-systemd-$USER .
cd ../noble
cp ../../tools/node_ip.sh ../common/rc.local ../common/rc-local.service ./
docker build --platform $PLATFORM -t ubuntu:noble-sshd-systemd-$USER .
cd ../bookworm
cp ../../tools/node_ip.sh ../common/rc.local ../common/rc-local.service ./
docker build --platform $PLATFORM -t debian:bookworm-sshd-systemd-$USER .
cd ../..
#tar --exclude=images-build --exclude=data --exclude=.git --exclude=secret --exclude=.vagrant --exclude=pkg --exclude=cmd --exclude=__pycache__  -czf images-build/ansible-anydbver/anydbver.tar.gz .
git archive --format=tar HEAD | gzip -c >images-build/ansible-anydbver/anydbver.tar.gz
cd images-build/ansible-anydbver/
docker build -t rockylinux:8-anydbver-ansible-$USER .
for img in centos:7-sshd-systemd-$USER rockylinux:8-sshd-systemd-$USER rockylinux:9-sshd-systemd-$USER rockylinux:10-sshd-systemd-$USER ubuntu:focal-sshd-systemd-$USER ubuntu:jammy-sshd-systemd-$USER ubuntu:noble-sshd-systemd-$USER debian:bookworm-sshd-systemd-$USER rockylinux:8-anydbver-ansible-$USER; do
  docker image tag $img $IMAGE_PUBLISHER/${img/$USER/$IMAGE_VERSION}$PLATFORM_TAG
done
