#!/bin/bash

PROJ=${1:-${USER}_anydbver}
OS=${2:-centos/7}
NODES=${3:-1}
NODES=$(( NODES - 1 ))

cat > lxdock.yml << EOF
name: ${PROJ}

shares:
  - source: ${PWD}
    dest: /vagrant

containers:
  - name: default
    image: ${OS}
    privileged: true
    hostnames:
      - default
    provisioning:
      - type: ansible
        playbook: playbook.yml
        lxd_transport: true
EOF

for i in $( seq 1 $NODES)
do
cat >> lxdock.yml << EOF
  - name: node${i}
    image: ${OS}
    privileged: true
    hostnames:
      - default
    provisioning:
      - type: ansible
        playbook: playbook.yml
        lxd_transport: true
EOF
done
