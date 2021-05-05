#!/bin/bash
FQDN=$1
bash /vagrant/tools/generate_ssl_certs.sh client.$FQDN $FQDN
mkdir /etc/ssl/docker-registry
cd /etc/ssl/docker-registry
docker run \
  --entrypoint htpasswd \
  httpd:2 -Bbn reg secret > htpasswd
tar xzf /root/certs.tar.gz
docker run -d \
  --restart=always \
  --name registry \
  -v /etc/ssl/docker-registry:/certs \
  -e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
  -e "REGISTRY_AUTH=htpasswd" \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/certs/htpasswd \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/server.pem \
  -e REGISTRY_HTTP_TLS_KEY=/certs/server-key.pem \
  -p 443:443 \
  registry:2

mkdir -p /etc/docker/certs.d/$FQDN
cp /etc/ssl/docker-registry/ca.pem /etc/docker/certs.d/$FQDN/ca.crt
curl --cacert /etc/ssl/docker-registry/ca.pem -i https://$FQDN/
docker login --username reg --password secret https://$FQDN/
