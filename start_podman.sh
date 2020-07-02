#!/bin/bash
:> ansible_hosts
for i in ${USER}.default $(seq 1 2|sed -e s/^/${USER}.node/); do
  podman run -d --name $i centos:7 /sbin/init
  podman exec $i yum install -y sudo
  echo "$i ansible_connection=podman ansible_python_interpreter=/usr/bin/python2.7" >> ansible_hosts
done
