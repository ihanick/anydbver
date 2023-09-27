#!/bin/bash
docker_net=$1
metallb_ver=$2

cidr_block=$(docker network inspect $docker_net | jq '.[0].IPAM.Config[0].Subnet' | tr -d '"')

cidr_to_netmask() {
    value=$(( 0xffffffff ^ ((1 << (32 - $2)) - 1) ))
    echo "$(( (value >> 24) & 0xff )).$(( (value >> 16) & 0xff )).$(( (value >> 8) & 0xff )).$(( value & 0xff ))"
}


cidr_host_min() {
  cidr=$1
  ip=$(echo $cidr | cut -d/ -f1)
  mask_bits=$(echo $cidr | cut -d/ -f2)
  mask=$(cidr_to_netmask $ip $mask_bits)

  IFS=. read -r i1 i2 i3 i4 <<< "$ip"
  IFS=. read -r m1 m2 m3 m4 <<< "$mask"
  echo "$((i1 & m1)).$((i2 & m2)).$((i3 & m3)).$(((i4 & m4)+1))"
}

cidr_host_max() {
  cidr=$1
  ip=$(echo $cidr | cut -d/ -f1)
  mask_bits=$(echo $cidr | cut -d/ -f2)
  mask=$(cidr_to_netmask $ip $mask_bits)

  IFS=. read -r i1 i2 i3 i4 <<< "$ip"
  IFS=. read -r m1 m2 m3 m4 <<< "$mask"
  echo "$((i1 & m1 | 255-m1)).$((i2 & m2 | 255-m2)).$((i3 & m3 | 255-m3)).$(((i4 & m4 | 255-m4)-1))"
}

ingress_last_addr=$(cidr_host_max "$cidr_block")
ingress_first_addr=$(cidr_host_min "$ingress_last_addr/24")

ingress_range=$ingress_first_addr-$ingress_last_addr
echo "$ingress_range"

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v${metallb_ver}/config/manifests/metallb-native.yaml
until kubectl -n metallb-system wait --timeout=60s pod --for=condition=ready -l app=metallb,component=controller ; do sleep 2; done

add_pool() {
cat <<EOF | kubectl apply -n metallb-system -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-ip
spec:
  ipAddressPools:
  - default-pool
  interfaces:
  - eth0
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
spec:
  addresses:
  - $ingress_range
  autoAssign: true
  avoidBuggyIPs: true
EOF
}

until add_pool ; do sleep 10 ; done
