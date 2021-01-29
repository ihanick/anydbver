#!/bin/bash
VAULT_URL="$1"
CNF_FILE="$2"
tar -C / -xf /vagrant/secret/vault-client.tar

TOKEN=$(cat /root/.vault-token)

cat > /var/lib/mysql/keyring_vault.conf << EOF
vault_url = https://${VAULT_URL}:8200
secret_mount_point = secret
token = ${TOKEN}
vault_ca = /etc/vault.d/ca.crt
EOF

chmod 0400 /var/lib/mysql/keyring_vault.conf
chown mysql:mysql /var/lib/mysql/keyring_vault.conf

cat >> $CNF_FILE << EOF
early-plugin-load="keyring_vault=keyring_vault.so"
loose-keyring_vault_config=/var/lib/mysql/keyring_vault.conf
EOF
