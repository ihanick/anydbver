#!/bin/bash
CLIENT_CN="$1"
SERVER_CN="$2"
IPNAME=$(echo $SERVER_CN | cut -d. -f 1).$(node_ip.sh).nip.io
if [ ! -f /usr/local/bin/cfssl ]; then
  VERSION=$(curl --silent "https://api.github.com/repos/cloudflare/cfssl/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
  VNUMBER=${VERSION#"v"}
  curl -sL --output /usr/local/bin/cfssl https://github.com/cloudflare/cfssl/releases/download/${VERSION}/cfssl_${VNUMBER}_linux_amd64
  curl -sL --output /usr/local/bin/cfssljson https://github.com/cloudflare/cfssl/releases/download/${VERSION}/cfssljson_${VNUMBER}_linux_amd64
  chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
fi

mkdir /root/ssl
cd /root/ssl
cat <<EOF | cfssl gencert -initca - | cfssljson -bare ca
  {
    "CN": "Root CA",
    "names": [
      {
        "O": "Support"
      }
    ],
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF

cat <<EOF >ca-config.json
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
cat <<EOF | cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=./ca-config.json - | cfssljson -bare server
  {
    "hosts": [
      "*.percona.local",
      "${SERVER_CN}",
      "${IPNAME}"
    ],
    "CN": "${SERVER_CN}",
    "names": [
      {
        "O": "Support"
      }
    ],
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF
cfssl bundle -ca-bundle=ca.pem -cert=server.pem | cfssljson -bare server

cat <<EOF | cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=./ca-config.json - | cfssljson -bare client
  {
    "hosts": [
      "*.percona.local",
      "${CLIENT_CN}"
    ],
    "names": [
      {
        "O": "Support"
      }
    ],
    "CN": "${CLIENT_CN}",
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF

yum install -y tar
tar czf /root/certs.tar.gz ca.pem client.pem client-key.pem server.pem server-key.pem
cp /root/ssl/ca.pem /etc/pki/ca-trust/source/anchors/${IPNAME}.ca.crt
