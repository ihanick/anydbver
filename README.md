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
PKO4PXC='1.4.0' vagrant up --provider=lxc
```

## Typical usage

Start two "servers" one with Percona Server 8.0, XtraBackup, Percona Monitoring and Management client utility and the second one will run PMM server.

```bash
[anydbver]$ PT=3.2.0-1 PXB=8.0.10-1 PS=8.0.18-9.1 DB_PASS=secret PMM_CLIENT=2.5.0-6 vagrant up --provider=lxc
[anydbver]$ PMM_SERVER=2.5.0 vagrant up --provider=lxc node1
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

## Known issues and limitation

* There is no support for outdated branches like Percona Server 5.5
* Containters/VM machines using CentOS 7
* There is no support for configuring replication and sharding, work in progress
* There is no support for non-Percona database products, work in progress
* Everything is tested with vagrant-lxc (privileged/root) and vagrant-lxd (nesting,privileged) providers, but may also work with other providers like Virtualbox, Azure, AWS
* The project is intended for fast bugs/issues reproduction, performance issues, security concerns are not primary goals.
* Currently only percona repositories are configured if you are not specifying any version with environment variable, could be changed in future with other databases support