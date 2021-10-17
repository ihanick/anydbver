#!/bin/bash
#REGISTRY_URL="https://admin@secret:registry.10.77.130.237.nip.io"
REGISTRY_URL="$1"
REGISTRY_HOST=$(echo "$REGISTRY_URL"|cut -d@ -f 2)
REGISTRY_USER=$(echo "$REGISTRY_URL"|sed -e 's,https://,,'|cut -d: -f 1|cut -d'@' -f 1)
REGISTRY_PASSWORD=$(echo "$REGISTRY_URL"|sed -e 's,https://,,'|cut -d: -f 2|cut -d'@' -f 1)

scp -o StrictHostKeyChecking=no -i /vagrant/secret/id_rsa root@${REGISTRY_HOST}:/etc/pki/ca-trust/source/anchors/${REGISTRY_HOST}.ca.crt /vagrant/secret/${REGISTRY_HOST}.ca.crt

if [ -f /vagrant/secret/${REGISTRY_HOST}.ca.crt ] ; then
  cp /vagrant/secret/${REGISTRY_HOST}.ca.crt /etc/pki/ca-trust/source/anchors/${REGISTRY_HOST}.ca.crt
  update-ca-trust
  
  mkdir -p /etc/rancher/k3s
  cat > /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  ${REGISTRY_HOST}:
    endpoint:
      - "https://${REGISTRY_HOST}"
configs:
  "${REGISTRY_HOST}":
    auth:
      username: ${REGISTRY_USER} # this is the registry username
      password: ${REGISTRY_PASSWORD} # this is the registry password
    tls:
      #cert_file: # path to the cert file used in the registry
      #key_file:  # path to the key file used in the registry
      ca_file: /etc/pki/ca-trust/source/anchors/${REGISTRY_HOST}.ca.crt # path to the ca file used in the registry
EOF

fi

