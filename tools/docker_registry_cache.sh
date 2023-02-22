#!/bin/bash
DEST=$PWD/data/docker-cache
mkdir "$DEST"
cat > $PWD/data/registry-config.yaml <<EOF
# docker run -d -p 5000:5000 --restart=always --name registry -v $PWD/registry-config.yaml:/etc/docker/registry/config.yml registry:2
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
proxy:
  remoteurl: https://registry-1.docker.io
#  username: dockerhubuser
#  password: dockerhubpassword
#auth:
#  htpasswd:
#    realm: basic-realm
#    path: /etc/registry
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF
docker run -d -p 5000:5000 --restart=always --name caching-registry -v $PWD/data/registry-config.yaml:/etc/docker/registry/config.yml -v "$DEST":/var/lib/registry  registry:2
