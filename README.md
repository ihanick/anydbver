# anydbver
Vagrant+Ansible setup to install Percona database products with exact version specified. Best experience LXC provider

## Allows to install a specific version of:

* Percona Server
* Percona XtraDB Cluster
* PMM Server and clients
* Percona Server for MongoDB
* Percona Distribution for PostgreSQL

## Installation

```bash
vagrant plugin install vagrant-lxc

git clone https://github.com/ihanick/anydbver.git ${USER}-anydbver
cd ${USER}-anydbver
ENV1=ver ENV2=ver ... vagrant up --provider=lxc
```

You can also use lxd if you have issues with old lxc version/setup:

```bash
vagrant plugin install vagrant-lxd
...
ENV1=ver ENV2=ver ... vagrant up --provider=lxd

# Select provider:
# You can select Vagrant provider with several different ways:
# A) create an environment variable for current session:
export VAGRANT_DEFAULT_PROVIDER=lxd
# A) create an environment variable for current all further sessions, add a variable in your .bashrc
export VAGRANT_DEFAULT_PROVIDER=lxd
# B) create environment variable for particular vagrant command
VAGRANT_DEFAULT_PROVIDER=lxd .... vagrant up
# C) Use --provider= option to up command
vagrant up --provider=lxd ....

# Specify LXD profile. It's important on servers with shared lxd environment
# In order to use non-default storage or network you should create a profile:
lxc storage create $USER dir source=/home/$USER/lxc
lxc profile copy default $USER
# replace pool: "your_storage_name", e.g with above $USER suggestion put your unix username instead of your_storage_name
lxc profile edit $USER
# it's better to add LXD_PROFILE also to your .bashrc to avoid using default storage pool
export LXD_PROFILE=$USER
```

## Kubernetes, PMM

Nested containers support is required for PMM server and Kubernetes operators.
If your current setup is not able to run k3s, check https://github.com/corneliusweig/kubernetes-lxd/blob/master/README-k3s.md for lxd

In addition kubernetes requires /etc/sysctl.conf:

```ini
vm.overcommit_memory = 1
kernel.panic = 10
kernel.panic_on_oops = 1
```

Running Percona Kubernetes Operator for Percona XtraDB Cluster (pxc) in single-k8s-node environment:

```bash
PKO4PXC='1.4.0' VAGRANT_DEFAULT_PROVIDER=lxc vagrant up
```

The same for  Percona server for MongoDB on Kubernetes
```bash
PKO4PSMDB='1.4.0' VAGRANT_DEFAULT_PROVIDER=lxc vagrant up
```

## Kubernetes, Multiple nodes

```bash
export VAGRANT_DEFAULT_PROVIDER=lxc
# 4 workers in total
PKO4PXC='1.4.0' vagrant up
K3S_TOKEN=$(vagrant ssh default -- sudo cat /var/lib/rancher/k3s/server/node-token) K3S_URL="https://$( vagrant ssh default -- hostname -I | cut -d' ' -f1):6443" vagrant up node1 node2 node3
```

## Typical usage

Start two "servers" one with Percona Server 8.0, XtraBackup, Percona Monitoring and Management client utility and the second one will run PMM server.

```bash
[anydbver]$ export VAGRANT_DEFAULT_PROVIDER=lxc
[anydbver]$ PT=3.2.0-1 PXB=8.0.10-1 PS=8.0.18-9.1 DB_PASS=secret PMM_CLIENT=2.5.0-6 vagrant up
[anydbver]$ PMM_SERVER=2.5.0 vagrant up node1
[anydbver]$ vagrant ssh node1 -- sudo podman ps
CONTAINER ID  IMAGE                               COMMAND               CREATED             STATUS                 PORTS               NAMES
62553a08bdcb  docker.io/percona/pmm-server:2.5.0  /opt/entrypoint.s...  About a minute ago  Up About a minute ago  0.0.0.0:80->80/tcp  pmm-server
[anydbver]$ vagrant ssh default -- /usr/sbin/mysqld --version
/usr/sbin/mysqld  Ver 8.0.18-9 for Linux on x86_64 (Percona Server (GPL), Release 9, Revision 53e606f)
# vagrant ssh default
# vagrant ssh node1
# Cleanup
vagrant destroy -f
```

You can find more examples in `test-all.sh` script.

## Custom configuration files

You can use existing database configuration files parts from `configs/dbengine/configfilename`.
```bash
DB_USER=root DB_PASS=secret START=1 PS=5.6.47-rel87.0.1 DB_OPTS=mysql/async-repl-gtid.cnf VAGRANT_DEFAULT_PROVIDER=lxc vagrant up
# or
DB_USER=root DB_PASS=secret START=1 PS=5.7.29-32.1      DB_OPTS=mysql/async-repl-gtid.cnf VAGRANT_DEFAULT_PROVIDER=lxc vagrant up
# or
DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1      DB_OPTS=mysql/async-repl-gtid.cnf VAGRANT_DEFAULT_PROVIDER=lxc vagrant up
```

## Running multiple nodes

You can initialize all containers/VMs at once and configure each node individually by setting proper environment variables for each `vagrant provision _list_of_nodes_` call.

```bash
# start 4 nodes
export VAGRANT_DEFAULT_PROVIDER=lxc 
vagrant up default node1 node2 node3
# apply configuration changes individually to each node or group several nodes for parallel apply
PSMDB=4.2.3-4   PMM_CLIENT=2.5.0-6 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf vagrant provision node1 node2
PSMDB=4.0.17-10 PMM_CLIENT=2.5.0-6 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf vagrant provision node3
PMM_SERVER=2.5.0  vagrant provision default
```

## Initial support for different OS

There is an initial support for Ubuntu 18.04. Only percona-release package is installed.
```bash
OS=ubuntu/bionic64 DB_USER=root DB_PASS=secret START=1 PS=8.0.16-7-1    DB_OPTS=mysql/async-repl-gtid.cnf vagrant up # starts Ubuntu 18.04
vagrant up node1 # starts centos/7
OS=centos/8 vagrant up node2 # start CentOS 8
```

## Known issues and limitation

* There is no support for outdated branches like Percona Server 5.5
* Containters/VM machines using CentOS 7
* There is no support for configuring replication and sharding, work in progress
* There is no support for non-Percona database products, work in progress
* Everything is tested with vagrant-lxc (privileged/root), vagrant-lxd (nesting,privileged) and virtualbox providers, but may also work with other providers like Azure, AWS
* Full VM virtualization with VirtualBox requires more memory and usually slower for disk access, please consider LXC or LXD.
* In order to use multi-node networking with VirtualBox, you can get ip address for each node with `vagrant ssh default -- hostname -I | cut -d' ' -f2`
* The project is intended for fast bugs/issues reproduction, performance issues, security concerns are not primary goals.
* Currently only percona repositories are configured if you are not specifying any version with environment variable, could be changed in future with other databases support
