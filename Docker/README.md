# anydbver - Docker/Podman version

Andbver with LXD allows to start containers and install sofware similar to bare-metal production environment.
This branch is intended to use hub.docker.com images as possible without or with minimal modifications.

The replication/clusters setup is configured with sidecar/init containers.

## Installation
* Install Docker or Podman or setup kubectl with desired default namespace
* Clone anydbver repository
```
git clone https://github.com/zelmario/anydbver.git anydbver
cd ./anydbver/Docker
```

## MySQL and Percona Server
* Use clone and GTID

```
./anydbver deploy ps gtid world node1 ps gtid master:node0
```

* Use clone and binary log file+position

```
./anydbver deploy ps world node1 ps master:node0
```

* Use GTID and offline filesystem copy (works with 5.6, 5.7, 8.0)

```
./anydbver deploy ps:5.6 gtid world node1 ps:5.6 snapshot gtid master:node0
```

* Arguments
```
./anydbver deploy \
  node0 mysql gtid args:--innodb-log-file-size=512M \
  node1 gtid mysql args:'--innodb-log-file-size=1G --innodb-flush-log-at-trx-commit=0'
```

Use `mysql` instead of `ps` for mysql/mysql-server image.

* Server's cli:
```
./anydbver mysql node0
```

### Test upgrades
  * Create MySQL 5.5 instance 
  * Create custom sample database
  * Stop node0, but keep data directory
  * Create MariaDB 10.5 instance with custom startup argument
```
$ cat sampledb/test/dump.sql 
create database test1;
use test1
create table t(id int auto_increment primary key, ts timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp());
INSERT INTO t() VALUES(),(),();
$ ./anydbver deploy node0 mysql:5.5 sampledb:test node0 mariadb:10.5 args:'--mysql56_temporal_format=OFF'
```


## Percona XtraDB Cluster
```
./anydbver.py deploy node0 pxc:8.0 node1 pxc:8.0,join=node0 node2 pxc:8.0,join=node0
```

## Postgresql

* Pagila sample database and physical replication secondary created by offline filesystem copy
```
./anydbver deploy node0 pg pagila node1 pg snapshot master:node0
```

* Pagila sample database and physical replication secondary created by `pg_basebackup`
```
./anydbver deploy node0 pg pagila node1 pg master:node0
```
Destroy:
```
./anydbver destroy
```

* Server's cli:
```
./anydbver psql node0
```

## MongoDB
* Replica set
```
./anydbver deploy \
  node0 mongo:4.4.2 replica-set:rs0 \
  node1 mongo:4.4.2 replica-set:rs0 master:node0 \
  node2 mongo:4.4.2 replica-set:rs0 master:node0
```

* Server's cli:
```
./anydbver mongo node0
```

## Kubernetes

Run mysql master-slave in Kubernetes without operators
```
./anydbver --provider kubernetes deploy node0 mysql node1 mysql master:node0
```

## Using ansible version of anydbver with docker
```
./anydbver deploy node0 ssh node1 ssh node2 ssh node3 ansible-workers:node0,node1,node2
docker exec -it $USER-node3 bash
cd /root/anydbver
./anydbver deploy node0 percona-toolkit
```

## Deploy kubernetes in docker with k3d
```
./anydbver deploy k3d
```
Wait until kube-system pods startup and you can use `./anydbver --provider kubernetes ...`
```
$ ./anydbver --provider kubernetes deploy node0 mysql gtid node1 mysql gtid master:node0
# wait until nodes ready
$ ./anydbver --provider kubernetes mysql node0
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 13
Server version: 8.0.28 MySQL Community Server - GPL

Copyright (c) 2000, 2022, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> show slave hosts;
+-----------+-------+------+-----------+--------------------------------------+
| Server_id | Host  | Port | Master_id | Slave_UUID                           |
+-----------+-------+------+-----------+--------------------------------------+
|        52 | node1 | 3306 |        51 | 4ecd6c24-aa5e-11ec-b11a-0abbd41a65fc |
+-----------+-------+------+-----------+--------------------------------------+
1 row in set, 1 warning (0.00 sec)
```

## Deploy kubernetes operators
### Deploy Postgres operator
```
./anydbver deploy k8s-pg k3d
# support for backups, certs directory should contain a valid certificate for minio-service.default.svc.example.org
./anydbver.py --destroy;./anydbver deploy k3d k8s-cluster-domain:example.org k8s-minio k8s-pg:1.1.0 minio-certs:certs pagila
```

```
./anydbver deploy k3d k8s-minio cert-manager minio-certs:self-signed k8s-pg:1.2.0
```

### Standby Postgresql clusteter managed by Kubernetes operator:
```./anydbver.py deploy node0 k3d k8s-minio minio-certs:self-signed cert-manager:1.7.2 k8s-pg:1.3.0,name=cl1 node0 k8s-pg:1.3.0,name=cl1,namespace=pgo2,standby k8s-minio minio-certs:self-signed cert-manager:1.7.2```

### Deploy PXC operator
```
./anydbver deploy k3d k8s-pxc:1.10.0 world
./anydbver deploy k3d k8s-cluster-domain:example.org k8s-pxc:1.10.0 # use example.org domain in k8s instead of cluster.local
./anydbver deploy k3d k8s-cluster-domain:example.org k8s-minio k8s-pxc:1.10.0 minio-certs:certs # load minio-service.default.svc.example.org certificates (tls.key, tls.crt) from certs subdirectory

# Deploy PXC operator and cluster with percona helm charts
./anydbver deploy k3d k8s-pxc:1.10.0 world

# install Loki to see k8s logs (including PXC)
./anydbver deploy k3d k8s-minio k8s-pxc:1.10.0 k8s-pmm:2.27.0 cert-manager k8s-cluster-domain:percona.local minio-certs:self-signed pmm-certs:self-signed nginx-ingress:9443 loki
```

Run two clusters in different namespaces:
```
./anydbver deploy node0 k3d k8s-pxc:1.10.0 k8s-pmm:2.26.0 node0 k8s-namespace:pxc1 k8s-pxc:1.10.0 k8s-pmm:2.26.0
```

Run cluster with specific name using percona helm charts and older K8s version, load sql file after startup:
```
./anydbver.py deploy k3d:v1.22.8-k3s1 helm k8s-pxc:1.11.1 cluster-name:c1 sql:sampledb/world/world.sql
```

### Deploy Mongo operator
```
./anydbver deploy k3d k8s-mongo:1.11.0 k8s-pmm:2.26.0
```

### PMM
```
./anydbver.py destroy;./anydbver.py deploy k3d pmm:2.28.0
./anydbver.py destroy;./anydbver.py deploy k3d pmm:2.31.0,helm=percona-helm-charts,certs=self-signed,namespace=monitoring cert-manager:1.9.1
./anydbver.py destroy;./anydbver.py deploy k3d pmm:2.31.0,helm=percona/percona-helm-charts:0.3.9,certs=self-signed,namespace=monitoring,password=verysecretpassword1^ cert-manager:1.9.1
```
