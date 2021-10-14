#!/bin/bash

NODE_TYPE="$1"

[ -d /etc/docker ] || mkdir /etc/docker
cat <<EOF | tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
systemctl enable docker
systemctl daemon-reload
systemctl restart docker


cat <<EOF | tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

# Set SELinux in permissive mode (effectively disabling it)
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

systemctl enable --now kubelet

mkdir /opt/local-path-provisioner
chmod ogu+rw /opt/local-path-provisioner

yum install -y gdisk cloud-utils-growpart e2fsprogs
growpart /dev/sda 2
resize2fs /dev/sda2

if [[ "$NODE_TYPE" == "master" ]] ; then
  kubeadm init
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

  kubeadm token create --print-join-command > /root/join_cmd.sh
  kubectl apply -f https://docs.projectcalico.org/v3.20/manifests/calico.yaml
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
  kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

  COREDNS_VER=$(kubectl -n kube-system get deployments.apps coredns -o yaml | yq r - 'spec.template.spec.containers[0].image'|cut -d: -f 2)
  if [[ "$COREDNS_VER" == "v1.8.4" ]] ; then
    kubectl -n kube-system patch deployment coredns \
        -p'{"spec":{"template":{"spec":{"containers":[{"name":"coredns","image":"rancher/coredns-coredns:1.8.3"}]}}}}'
  fi
else
  ssh -o StrictHostKeyChecking=no -i /vagrant/secret/id_rsa "$NODE_TYPE" cat /root/join_cmd.sh | bash -x 
fi
true
