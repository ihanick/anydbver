# anydbver
LXD+Ansible setup to install Percona database products with exact version specified.

## Simple usage:

Start VirtualBox VM with LXD configured:
```bash
vagrant up
vagrant ssh
```
Start Percona Server 5.6:
```bash
cd anydbver
./anydbver deploy ps:5.6
```
Login to container with Percona Server and connect with mysql command:
```bash
./anydbver ssh
mysql
```

## Running other database products:

Start the database with required server type and version:
```bash
./anydbver deploy help
Deploy: 
./anydbver deploy percona-server:8.0.16
./anydbver deploy percona-server:8.0
./anydbver deploy percona-server
./anydbver deploy ps:5.7
./anydbver deploy mariadb:10.4
./anydbver deploy maria:10.4
./anydbver deploy mariadb node1 mariadb master:default
./anydbver deploy mariadb node1 mariadb master:default default mariadb master:node1 node2 mariadb master:node1
./anydbver deploy mariadb-cluster:10.4 node1 mariadb-cluster:10.4 galera-master:default node2 mariadb-cluster:10.4 galera-master:default
./anydbver deploy deploy ldap node1 ldap-master:default ps:5.7
./anydbver deploy ps:5.7 node1 ps:5.7 master:default node2 ps:5.7 master:node1
./anydbver deploy ps:8.0 utf8 node1 ps:5.7 master:default node2 ps:5.6 master:node1 row
./anydbver deploy samba node1 ps samba-dc:default
./anydbver deploy pxc:5.7 node1 pxc:5.7 galera-master:default node2 pxc:5.7 galera-master:default
./anydbver deploy ps:8.0 group-replication node1 ps:8.0 group-replication master:default node2 ps:8.0 group-replication master:default
./anydbver deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default
./anydbver deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default k8s-mongo
./anydbver deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default k8s-minio k8s-mongo
./anydbver deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default k8s-pxc
./anydbver deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default k8s-minio k8s-pmm k8s-pxc backup
./anydbver deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default k8s-pg
./anydbver deploy pg:12.3
./anydbver deploy psmdb
./anydbver deploy psmdb replica-set:rs0 node1 psmdb master:default replica-set:rs0 node2 psmdb master:default replica-set:rs0
./anydbver deploy \
  psmdb:4.2 replica-set:rs0 shardsrv \
  node1 psmdb:4.2 master:default replica-set:rs0 shardsrv \
  node2 psmdb:4.2 master:default replica-set:rs0 shardsrv \
  node3 psmdb:4.2 configsrv replica-set:cfg0 \
  node4 psmdb:4.2 configsrv replica-set:cfg0 master:node3 \
  node5 psmdb:4.2 configsrv replica-set:cfg0 master:node3 \
  node6 psmdb:4.2 mongos-cfg:cfg0/node3,node4,node5 mongos-shard:rs0/default,node1,node2
./anydbver deploy sysbench
./anydbver deploy ps:5.7 node1 ps:5.7 master:default node2 ps:5.7 master:default node3 proxysql master:default
./anydbver deploy \
  haproxy-galera:node1,node2,node3 \
  node1 pxc clustercheck \
  node2 pxc galera-master:node1 clustercheck \
  node3 pxc galera-master:node1 clustercheck

./anydbver deploy mongo help
```

## Connect to selected node via ssh:

Complex anydbver setups including multiple linux containers. The first container has a `default` name, others `node1`, `node2`.... You can connect to any node with ssh:
```bash
./anydbver ssh # connects to default node
./anydbver ssh node1
```

## Specifying host names for nodes

In complex setups each node could have individual name. The name is specified as a linux hostname, could be used for ssh, replication source, ldap server name.
```bash
./anydbver deploy ps:5.6 hostname:ps0.percona.local node1 ps:5.6 hostname:ps1.percona.local leader:ps0
./anydbver ssh ps0
./anydbver ssh ps1.percona.local
```

## Updating version information

anydbver stores lists of version for each database product in temporary files. You can update it with latest values by running:

```bash
./anydbver update
```

## Container OS image

By default, containers are based on CentOS 7. Newer distributions are not supporting all old database versions, but you still can use CentOS 8, Oracle Enterprise linux 7 and 8 or Ubuntu 20.04 Focal Fossa:

```bash
./anydbver deploy \
  ps:5.7 os:el7 \
  node1 ps:5.7 os:el8 master:default \
  node2 ps:5.7 os:focal master:default \
  node3 ps:5.7 os:oel7 master:default \
  node4 ps:5.7 os:oel8 master:default \
  node5 ps:5.7 os:bionic master:default

for i in default node{1,2,3,4,5} ; do ./anydbver ssh $i grep PRETTY_NAME /etc/os-release ; done
PRETTY_NAME="CentOS Linux 7 (Core)"
PRETTY_NAME="CentOS Linux 8"
PRETTY_NAME="Ubuntu 20.04.2 LTS"
PRETTY_NAME="Oracle Linux Server 7.9"
PRETTY_NAME="Oracle Linux Server 8.3"
PRETTY_NAME="Ubuntu 18.04.5 LTS"
```

Default os could be changed with `--os osname`. Put it right after deploy keyword:
```bash
./anydbver deploy --os el8 ps node1 ps master:default
```
Default OS is not disabling explicit os specification:
```
./anydbver deploy --os el8 ps node1 ps master:default node2 os:el7 ps
```


## Allows to install a specific version of:

* Percona Server
* Percona XtraDB Cluster
* PMM Server and clients
* Percona Server for MongoDB
* Percona Distribution for PostgreSQL
* Community Postgresql Server
* K3S kubernetes distribution

## Advanced Installation

If you are able to run LXD on your linux server, there is no need to run additional virtual machines. Anydbver can re-use your LXD installation and run without vagrant.

```bash
# Specify LXD profile. It's important on servers with shared lxd environment
# In order to use non-default storage or network you should create a profile:
lxc storage create $USER dir source=/home/$USER/lxc
lxc profile copy default $USER
# replace pool: "your_storage_name", e.g with above $USER suggestion put your unix username instead of your_storage_name
lxc profile edit $USER
# add LXD_PROFILE also to your .bashrc to avoid using default storage pool
export LXD_PROFILE=$USER
```

Clone the repository and configure default provider:
```bash
git clone https://github.com/ihanick/anydbver.git
cd anydbver
./anydbver configure provider:lxd
./anydbver update
```

## Kubernetes, PMM

Nested containers support is required for PMM server and Kubernetes operators.
If your current setup is not able to run k3s, check https://github.com/corneliusweig/kubernetes-lxd/blob/master/README-k3s.md for lxd

In addition kubernetes requires /etc/sysctl.conf:

```ini
vm.overcommit_memory = 1
vm.overcommit_ratio = 10000
kernel.panic = 10
kernel.panic_on_oops = 1
```

In order to prevent dns issues inside k8s containers: https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/
`reply from unexpected source` problem could be solved with loading `br_netfilter` module
```
modprobe br_netfilter
modprobe overlay
```

You may have problems with flannel using vxlan network. Enable host-gw instead, add to your .bashrc:
```bash
export K3S_FLANNEL_BACKEND=host-gw
```

### LXD 4.10 incompatibility with K3S
LXD 4.10 breaks compabibility with K3S. LXD ignores `net.netfilter.nf_conntrack_tcp_timeout_established` value on the host and uses default 5 days instead of 86400 seconds required for K3S.
You can downgrade it, but LXD looses all settings:
```bash
# assuming you have LXD 4.10, do not run these commands on previous versions:
snap remove lxd
snap install lxd --channel=4.9/stable
# remove old storage and re-create profile
sudo rm -rf /home/$USER/lxc/*
lxc storage create $USER dir source=/home/$USER/lxc
lxc profile create $USER
lxc profile device add $USER root disk type=disk pool=$USER path=/
lxc network create lxdbr0
lxc profile device add $USER eth0 nic name=eth0 network=lxdbr0 type=nic
```
