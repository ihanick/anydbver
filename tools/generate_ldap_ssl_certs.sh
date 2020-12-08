#!/bin/bash
if [ ! -f /usr/local/bin/cfssl ] ; then
  VERSION=$(curl --silent "https://api.github.com/repos/cloudflare/cfssl/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
  VNUMBER=${VERSION#"v"}
  curl -sL --output /usr/local/bin/cfssl https://github.com/cloudflare/cfssl/releases/download/${VERSION}/cfssl_${VNUMBER}_linux_amd64
  curl -sL --output /usr/local/bin/cfssljson https://github.com/cloudflare/cfssl/releases/download/${VERSION}/cfssljson_${VNUMBER}_linux_amd64
  chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
fi

hostnamectl set-hostname ldap.percona.local
sed -i -e 's/\(127.0.1.1.*\)$/\1 ldap ldap.percona.local/' /etc/hosts
mkdir /root/ssl
cd /root/ssl
cat <<EOF | cfssl gencert -initca - | cfssljson -bare ca
  {
    "CN": "Root CA",
    "names": [
      {
        "O": "PSMDB"
      }
    ],
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF

cat <<EOF > ca-config.json
  {
    "signing": {
      "default": {
        "expiry": "87600h",
        "usages": ["signing", "key encipherment", "server auth", "client auth"]
      }
    }
  }
EOF

IP=$(node_ip.sh)
cat <<EOF | cfssl gencert -ca=ca.pem  -ca-key=ca-key.pem -config=./ca-config.json - | cfssljson -bare server
  {
    "CN": "ldap.percona.local",
    "hosts": [
      "*.percona.local",
      "$IP"
    ],
    "names": [
      {
        "O": "PSMDB"
      }
    ],
    "CN": "${CLUSTER_NAME/-rs0}",
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF
cfssl bundle -ca-bundle=ca.pem -cert=server.pem | cfssljson -bare server


cat <<EOF | cfssl gencert -ca=ca.pem  -ca-key=ca-key.pem -config=./ca-config.json - | cfssljson -bare client
  {
    "hosts": [
      "*.percona.local",
      "client.percona.local",
      "mongodb.percona.local"
    ],
    "names": [
      {
        "O": "PSMDB"
      }
    ],
    "CN": "client.percona.local",
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF

yum install -y tar
tar czf /root/ldap-certs.tar.gz ca.pem client.pem client-key.pem server.pem server-key.pem
