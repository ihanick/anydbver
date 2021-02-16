#!/bin/bash
# https://www.percona.com/blog/2020/04/21/using-vault-to-store-the-master-key-for-data-at-rest-encryption-on-percona-server-for-mongodb/
# https://learn.hashicorp.com/tutorials/vault/deployment-guide#step-3-configure-systemd
VAULT_HOST="$1"
NODE_IP=$(node_ip.sh)
mkdir /etc/vault.d
cp /root/ssl/server.pem /etc/vault.d/vault.crt
cp /root/ssl/server-key.pem /etc/vault.d/vault.key
cp /root/ssl/ca.pem /etc/vault.d/ca.crt

chmod 0400 /etc/vault.d/vault.{crt,key}

mkdir /var/lib/vault

cat > /etc/vault.d/vault.hcl << EOF
listener "tcp" {
 address = "${NODE_IP}:8200"
 tls_cert_file="/etc/vault.d/vault.crt"
 tls_key_file="/etc/vault.d/vault.key"
}
storage "file" {
  path = "/var/lib/vault"
}
disable_mlock=true
EOF

#setcap cap_ipc_lock=+ep /usr/local/bin/vault
useradd --system --home /etc/vault.d --shell /bin/false vault

chown -R vault:vault /etc/vault.d /var/lib/vault

cat > /etc/systemd/system/vault.service << EOF
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
#SecureBits=keep-caps
#AmbientCapabilities=CAP_IPC_LOCK
#Capabilities=CAP_IPC_LOCK+ep
#CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=60
StartLimitIntervalSec=60
StartLimitBurst=3
LimitNOFILE=65536
#LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start vault


export VAULT_CACERT=/etc/vault.d/ca.crt
export VAULT_ADDR=https://$VAULT_HOST:8200

until curl -o /dev/null -s  https://$VAULT_HOST:8200/ ; do sleep 1; done

vault operator init > /etc/vault.d/unseal-keys.txt
chmod og-rw /etc/vault.d/unseal-keys.txt
vault operator unseal $(grep 'Unseal Key 1:' /etc/vault.d/unseal-keys.txt|cut -d: -f 2)
vault operator unseal $(grep 'Unseal Key 2:' /etc/vault.d/unseal-keys.txt|cut -d: -f 2)
vault operator unseal $(grep 'Unseal Key 3:' /etc/vault.d/unseal-keys.txt|cut -d: -f 2)
vault login $(grep 'Initial Root Token:' /etc/vault.d/unseal-keys.txt|cut -d: -f 2)
vault secrets enable -path secret kv-v2
