#!/bin/bash
OS=el7
PMM=""
PMM_PORT=$(( 8443 + $UID ))
DESTROY=0
K8S=0
PACKAGES=''
SAMBA_NODES=''
PYTHON_INT=/usr/bin/python2.7
NUM_NODES=3
# read arguments
opts=$(getopt \
    --longoptions "pmm:,pmm-port:,os:,destroy,k8s,samba:,nodes:,hostname:" \
    --name "$(basename "$0")" \
    --options "" \
    -- "$@"
)

declare -A HOSTNAMES

eval set --$opts
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pmm)
      PMM=$2
      shift 2
      ;;
    --nodes)
      NUM_NODES=$2
      shift 2
      ;;
    --pmm-port)
      PMM_PORT=$2
      shift 2
      ;;
    --os)
      OS=$2
      shift 2
      ;;
    --k8s)
      K8S=1
      shift
      ;;
    --samba)
      SAMBA_NODE=$2
      shift 2
      ;;
    --hostname)
      NODE_NAME=$(echo "$2"|cut -d= -f 1)
      NODE_HOST=$(echo "$2"|cut -d= -f 2)
      HOSTNAMES[$USER.$NODE_NAME]="$NODE_HOST"
      shift 2
      ;;
    --destroy)
      DESTROY=1
      shift
      ;;
      *)
      break
      ;;
  esac
done

if [ $DESTROY -eq 1 ] ; then
  sudo podman rm -f $USER.pmm-server $USER.default $USER.node1 $USER.node2 \
    $USER.k8sm $USER.k8sw1 $USER.k8sw3 $USER.k8sw2 &>/dev/null
  exit 0
fi

if [ $K8S -eq 1 ] ; then
  sudo podman run -d --privileged --tmpfs /run --tmpfs /var/run --name $USER.k8sm rancher/k3s:latest server --no-deploy traefik --flannel-backend=vxlan
  sleep 30
  MIP=$(sudo podman inspect $USER.k8sm|grep -F IPAddress|perl -ne '/"([0-9.]+)"/ and print $1')
  K3S_URL="https://$MIP:6443"
  K3S_TOKEN="$( sudo podman exec -i $USER.k8sm cat /var/lib/rancher/k3s/server/node-token)"
  sudo podman run -d --privileged --tmpfs /run --tmpfs /var/run --name $USER.k8sw1 -e K3S_URL="$K3S_URL" -e K3S_TOKEN="$K3S_TOKEN" rancher/k3s:latest
  sudo podman run -d --privileged --tmpfs /run --tmpfs /var/run --name $USER.k8sw2 -e K3S_URL="$K3S_URL" -e K3S_TOKEN="$K3S_TOKEN" rancher/k3s:latest
  sudo podman run -d --privileged --tmpfs /run --tmpfs /var/run --name $USER.k8sw3 -e K3S_URL="$K3S_URL" -e K3S_TOKEN="$K3S_TOKEN" rancher/k3s:latest

  sudo podman exec -i $USER.k8sm cat /etc/rancher/k3s/k3s.yaml | sed "s,server: https://127.0.0.1:6443,server: https://$MIP:6443," > secret/kube.config
fi

IMG="centos:7"
test -f secret/id_rsa || ssh-keygen -t rsa -f secret/id_rsa -P '' && chmod 0600 secret/id_rsa

if [ $OS = el7 -o $OS = centos7 ] && sudo podman images | grep centos|grep -q 7-systemd ; then
  IMG=centos:7-systemd
fi

if [ $OS = el8 -o $OS = centos8 ] ; then
  IMG=centos:8
  PYTHON_INT=/usr/bin/python3

  if [ $OS = el8 -o $OS = centos8 ] && sudo podman images | grep centos|grep -q 8-systemd ; then
    IMG=centos:8-systemd
  else
    PACKAGES="$PACKAGES python3"
  fi
fi

if [ $OS = bionic ] ; then
  IMG=ubuntu:bionic
fi

if [ $OS = focal ] ; then
  IMG=ubuntu:focal
fi


:> ansible_hosts
N=0
for i in ${USER}.default $(seq 1 2|sed -e s/^/${USER}.node/); do
  CAP_ADMIN=''
  NODE_HOSTNAME=''

  if [ "x${HOSTNAMES[$i]}" != "x" ] ; then
    NODE_HOSTNAME="--hostname=${HOSTNAMES[$i]}"
  fi

  #sudo podman run -d --security-opt label=type:spc_t --security-opt seccomp=unconfined --name $i centos:7 /sbin/init
  if [ "x$USER.$SAMBA_NODE" = "x$i" ] && [ $OS = el7 ] && sudo podman images | grep centos|grep -q 7-samba ; then
    IMG=centos:7-samba
    CAP_ADMIN='--cap-add SYS_ADMIN'
  fi

  sudo podman run -d $CAP_ADMIN $NODE_HOSTNAME --name $i $IMG /sbin/init

  sudo podman cp $PWD/secret/id_rsa.pub $i:/root/.ssh/authorized_keys
  sudo podman cp $PWD/tools/node_ip.sh $i:/usr/bin/node_ip.sh
  sudo podman exec $i bash -c "test -f /usr/bin/rsync || yum install -y sudo openssh-server iproute rsync $PACKAGES; chmod -R og-rwx /root/.ssh;sed -i -e 's/#UseDNS yes/UseDNS no/' -e 's/#PermitRootLogin.*$/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config;sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd;systemctl enable sshd;systemctl restart sshd"

  IP=$(sudo podman exec $i /bin/bash /usr/bin/node_ip.sh)
  #echo "$i ansible_connection=podman ansible_python_interpreter=/usr/bin/python2.7" >> ansible_hosts
  echo "$i ansible_connection=ssh ansible_user=root ansible_ssh_private_key_file=secret/id_rsa ansible_host=$IP ansible_python_interpreter=$PYTHON_INT ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> ansible_hosts
  ((N=N+1))
  if [ $N -eq $NUM_NODES ] ; then break ; fi
done

if [ "x$PMM" != "x" ] ; then
  sudo podman run -d -p $PMM_PORT:443 --name $USER.pmm-server percona/pmm-server:$PMM
fi
