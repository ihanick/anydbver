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

In case of dns issues inside k8s containers: https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/
`reply from unexpected source` problem could be solved with loading `br_netfilter` module
```
modprobe br_netfilter
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
K3S=latest vagrant up
K3S_TOKEN=$(vagrant ssh default -- sudo cat /var/lib/rancher/k3s/server/node-token) K3S_URL="https://$( vagrant ssh default -- hostname -I | cut -d' ' -f1):6443" vagrant up node1 node2 node3
# unmodified cr.yaml
PKO4PXC='1.4.0' vagrant provision default
# or with PMM enabled:
K3S=latest PKO4PXC='1.4.0' K8S_PMM=1 DB_PASS=secret vagrant provision default
```

## Typical usage

Start two "servers" one with Percona Server 8.0, XtraBackup, Percona Monitoring and Management client utility and the second one will run PMM server.

```bash
[anydbver]$ export VAGRANT_DEFAULT_PROVIDER=lxc
[anydbver]$ PT=3.2.0-1 PXB=8.0.10-1 PS=8.0.18-9.1 DB_PASS=secret PMM_CLIENT=2.5.0-6 vagrant up
[anydbver]$ PMM_SERVER=2.6.1 DB_PASS=secret vagrant up node1
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

## Replication

```bash
export VAGRANT_DEFAULT_PROVIDER=lxc
DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1    DB_OPTS=mysql/async-repl-gtid.cnf vagrant up default node1 node2
DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1 MASTER=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/async-repl-gtid.cnf vagrant provision node1 node2
```

## Galera

```bash
DB_USER=root DB_PASS=secret START=1 PXC=8.0.18-9.3     DB_OPTS=mysql/async-repl-gtid.cnf vagrant up default node1 node2
vagrant ssh default -- sudo tar cz /var/lib/mysql/ca.pem /var/lib/mysql/ca-key.pem /var/lib/mysql/client-cert.pem /var/lib/mysql/client-key.pem /var/lib/mysql/server-cert.pem /var/lib/mysql/server-key.pem > secret/pxc-cluster-ssl.tar.gz
DB_USER=root DB_PASS=secret PXC=8.0.18-9.3 REPLICATION_TYPE=galera MASTER=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/async-repl-gtid.cnf vagrant provision node1
DB_USER=root DB_PASS=secret PXC=8.0.18-9.3 REPLICATION_TYPE=galera MASTER=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/async-repl-gtid.cnf vagrant provision node2
```

5.7 and 5.6 requires different configuration file for xtrabackup user and password specification:
```bash
DB_USER=root DB_PASS=secret START=1 PXC=5.7.28-31.41.2 DB_OPTS=mysql/pxc5657.cnf vagrant up default node1 node2
DB_USER=root DB_PASS=secret PXC=5.7.28-31.41.2 REPLICATION_TYPE=galera MASTER=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/pxc5657.cnf vagrant provision node1
DB_USER=root DB_PASS=secret PXC=5.7.28-31.41.2 REPLICATION_TYPE=galera MASTER=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/pxc5657.cnf vagrant provision node2
```

###

lxdock and PXC

#### PXC 5.7

```bash
./gen_lxdock.sh  pxcinst centos/7 3
DB_USER=root DB_PASS=secret START=1 PXC=5.7.28-31.41.2 DB_OPTS=mysql/pxc5657.cnf lxdock up default
DB_USER=root DB_PASS=secret START=1 PXC=5.7.28-31.41.2 REPLICATION_TYPE=galera MASTER=$(lxdock shell default -c hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/pxc5657.cnf lxdock up node1
DB_USER=root DB_PASS=secret START=1 PXC=5.7.28-31.41.2 REPLICATION_TYPE=galera MASTER=$(lxdock shell default -c hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/pxc5657.cnf lxdock up node2
```

#### PXC 8.0

```bash
./gen_lxdock.sh  pxcinst centos/7 3
DB_USER=root DB_PASS=secret START=1 PXC=8.0.18-9.3     DB_OPTS=mysql/async-repl-gtid.cnf lxdock up default
lxdock shell default -c tar cz /var/lib/mysql/ca.pem /var/lib/mysql/ca-key.pem /var/lib/mysql/client-cert.pem /var/lib/mysql/client-key.pem /var/lib/mysql/server-cert.pem /var/lib/mysql/server-key.pem > secret/pxc-cluster-ssl.tar.gz
DB_USER=root DB_PASS=secret START=1 PXC=8.0.18-9.3 REPLICATION_TYPE=galera MASTER=$(lxdock shell default -c hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/async-repl-gtid.cnf lxdock up node1
DB_USER=root DB_PASS=secret START=1 PXC=8.0.18-9.3 REPLICATION_TYPE=galera MASTER=$(lxdock shell default -c hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/async-repl-gtid.cnf lxdock up node2
```

## MariaDB

You can install a specific version of MariaDB on CentOS/RHEL 7,8. If `DB_PASS` is specified you can start daemon with `START=1` and specify configuration options with `DB_OPTS`
```
./gen_lxdock.sh anydbver centos/7 2
MARIADB=10.4.12-1 DB_USER=root DB_PASS=secret START=1 DB_OPTS=mariadb/async-repl-gtid.cnf lxdock up default
lxdock destroy -f
```

```
MARIADB=10.4.12-1 DB_USER=root DB_PASS=secret START=1 DB_OPTS=mariadb/async-repl-gtid.cnf vagrant up default
vagrant destroy -f
```


## MongoDB replica set

```bash
export VAGRANT_DEFAULT_PROVIDER=lxc
openssl rand -base64 756 > secret/rs0-keyfile
PSMDB=4.2.3-4 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf REPLICA_SET=rs0 vagrant up default
PSMDB=4.2.3-4 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf REPLICA_SET=rs0 MASTER=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) vagrant up node1 node2
```

## ProxySQL

Package installation
```bash
PROXYSQL=2.0.12-1 vagrant up default
```

## Support for different OS

There is an initial support for Ubuntu 18.04. Only percona-release package is installed.
```bash
OS=ubuntu/bionic64 DB_USER=root DB_PASS=secret START=1 PS=8.0.16-7-1    DB_OPTS=mysql/async-repl-gtid.cnf vagrant up # starts Ubuntu 18.04
vagrant up node1 # starts centos/7
OS=centos/8 vagrant up node2 # start CentOS 8
```

## LXDock
If you are using LXD and not happy with vagrant performance you can use [LXDock](https://github.com/lxdock/lxdock).
It has many up-to-date images: https://uk.images.linuxcontainers.org/ and significantly reduces startup time for containers.

```bash
# ./gen_lxdock.sh container_name_prefix image_name number_of_nodes
./gen_lxdock.sh anydbver centos/7 2
# start all at once
lxdock up
# or you can start individually: lxdock up node1
PS=8.0.16-7.1 lxdock provision
# or provision individually: PS=8.0.16-7.1 lxdock provision node1
# cleanup
lxdock destroy -f
```

You can also setup databases and replication
```bash
PSMDB=4.2.3-4 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf REPLICA_SET=rs0 lxdock provision default
PSMDB=4.2.3-4 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf REPLICA_SET=rs0 MASTER=$( lxdock shell default -c hostname -I | cut -d' ' -f1 ) lxdock provision node1
lxdock destroy -f
```

lxdock command could produce warnings like:
```
UserWarning: Attempted to set unknown attribute "type" on instance of "Container"
```
Such warnings could be disabled by exporting following variable:
```
export PYLXD_WARNINGS=none
```

In the same way as for vagrant-lxd you may create lxd profile $USER. ./gen_lxdock.sh uses such profiles automatically.

## Postgresql

Percona distribution for Postgresql could be installed in the same way as other databases.
You can also setup streaming physical replication with slots:
```bash
./gen_lxdock.sh anydbver centos/7 2
PPGSQL=12.2-4 DB_PASS=secret START=1 lxdock up default
PPGSQL=12.2-4 DB_PASS=secret START=1 MASTER=$( lxdock shell default -c hostname -I | cut -d' ' -f1 ) lxdock up node1
```

## Known issues and limitation

* There is no support for outdated branches like Percona Server 5.5
* Containters/VM machines using CentOS 7
* There is no support for configuring replication PG and sharding Mongo, work in progress
* There is no support for non-Percona database products, work in progress
* Everything is tested with vagrant-lxc (privileged/root), vagrant-lxd (nesting,privileged) and virtualbox providers, but may also work with other providers like Azure, AWS
* Full VM virtualization with VirtualBox requires more memory and usually slower for disk access, please consider LXC or LXD.
* In order to use multi-node networking with VirtualBox, you can get ip address for each node with `vagrant ssh default -- hostname -I | cut -d' ' -f2`
* The project is intended for fast bugs/issues reproduction, performance issues, security concerns are not primary goals.
* Currently only percona repositories are configured if you are not specifying any version with environment variable, could be changed in future with other databases support
