#!/bin/bash
cd $(dirname "$0")
test -d secret || mkdir secret
test -f secret/id_rsa || ssh-keygen -t rsa -f secret/id_rsa -P '' && chmod 0600 secret/id_rsa
test -f secret/rs0-keyfile || openssl rand -base64 756 > secret/rs0-keyfile
cp -r secret ../anydbver-ansible
docker build --rm -t c7-systemd .
