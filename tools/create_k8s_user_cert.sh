#!/bin/bash
user=$1
ws=/var/lib/rancher/k3s
ca_path=$ws/server/tls
day=3650
ca1=client-ca
generate="keys/u-"$user

clus_name="cluster.local"
clus_ns="default"

openssl ecparam -name prime256v1 -genkey -noout -out $generate.key
openssl req -new -key $generate.key -out $generate.csr -subj "/CN=${user}@${clus_name}/O=key-gen"
openssl x509 -req -in $generate.csr -CA $ca_path/$ca1.crt -CAkey $ca_path/$ca1.key -CAcreateserial -out $generate.crt -days $day
