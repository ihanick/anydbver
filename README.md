# anydbver
Configuring MySQL, Percona MySQL/Postgresql/Mongo, MongoDB with ansible scripts.
Running multi-node replication clusters in Docker, LXD and Kubernetes.

## Non-linux/Easy setup
Vagrant allows to setup a virtual machine and run all required preparation steps.
Following procedure setups everything in a virtual machine pre-configured with 8GB RAM and two CPU cores.
If you need more resources, edit Vagrantfile accordingly.
```bash
git clone https://github.com/ihanick/anydbver.git
cd anydbver
vagrant up
vagrant ssh default
```

## Simple usage with Docker:
While the Vagrant installation variant is simple and easy to implement, you should use anydbver without virtual machines for better performance/host utilization.

Clone and install sqlite ansible dependency:
```bash
git clone https://github.com/ihanick/anydbver.git
cd anydbver
ansible-galaxy collection install theredgreek.sqlite
```

Create .anydbver file containing:
```bash
PROVIDER=docker
```
Build docker images with systemd and sshd, simulating standalone physical servers:
```bash
cd images-build
./build.sh
cd ..
```

Start Percona Server 5.7 on RockyLinux 8:
```bash
cd anydbver
./anydbver deploy ps:5.7
```
Login to container with Percona Server and connect with mysql command:
```bash
./anydbver ssh
mysql
```

### Pre-requirements
* git
* ansible (not just ansible-core)
* Redhat 7 systemd containers require `systemd.unified_cgroup_hierarchy=0` kernel boot parameter in grub

## Multi-node Kubernetes cluster inside Docker
### Percona Postgresql Operator
* Start two 3 node clusters replicated  via S3 bucket (MinIO Server), load sample database, cache docker images locally with proxying registry
`./anydbver deploy k3d registry-cache:http://172.17.0.1:5000 cert-manager:1.7.2 k8s-minio minio-certs:self-signed k8s-pg:1.3.0,namespace=pgo,sql="http://UIdgE4sXPBTcBB4eEawU:7UdlDzBF769dbIOMVILV@172.17.0.1:9000/sampledb/pagila.sql" k8s-pg:1.3.0,namespace=pgo1,standby`
  * The script starting S3 server with sql database example could be found at: `tools/create_backup_server.sh`
  * The script starting caching docker registry: `tools/docker_registry_cache.sh`
* Postgresql and backups to Google GCS
```bash
anydbver deploy k3d k8s-pg:1.3.0,backup-type=gcs,bucket=my-gcs-bucket,gcs-key=/full/path/to/gcloud/key.json
anydbver deploy k3d k8s-pg:2.1.0,replicas=1
```
* 2.2.0:
```./anydbver deploy k3d  cert-manager:1.11.0 k8s-minio minio-certs:self-signed k8s-pg:2.2.0,namespace=pgo k8s-pg:2.2.0,namespace=pgo1,standby```

### Percona XtraDB cluster
* Start PXC cluster with ProxySQL, PMM, Loki, load `world` database, allow access local IP address 192.168.1.102 by domain name https://pmm.192-168-1-102.nip.io/
```bash
./anydbver deploy k3d registry-cache:http://172.17.0.1:5000 cert-manager:1.7.2 k8s-pxc:1.12.0,name=world,ns=db1,s3sql="http://UIdgE4sXPBTcBB4eEawU:7UdlDzBF769dbIOMVILV@172.17.0.1:9000/sampledb/world.sql",proxysql pmm:2.35.0,helm=percona-helm-charts:1.0.1,certs=self-signed,namespace=monitoring,dns=pmm.192-168-1-102.nip.io nginx-ingress:443 loki
```

### Private Docker registry
* create image
```bash
cat > Dockerfile <<EOF
FROM busybox:latest
EOF
docker build . -t localhost:5001/ihanick/busybox:latest
docker run -d -p 5001:5000 --restart=always --name ihanick-registry registry:2
docker push localhost:5001/ihanick/busybox:latest
```
* Run kubernetes and start the container using the image
```bash
./anydbver deploy k3d private-registry:ihanick-registry.example.com=http://172.17.0.1:5001
kubectl run -it --rm --image=ihanick-registry.example.com/ihanick/busybox:latest busybox -- sh
```

### LoadBalancer
In order to access kubernetes LoadBalancer Services you can dedicate last 255 addresses from the docker network with MetalLB L2 load balancing.
```bash
./anydbver deploy k3d:latest,metallb k8s-mongo:1.14.0,expose
```


## Simple usage with LXD:

Create .anydbver file containing (replace ihanick with your `$USER`):
```bash
PROVIDER=lxd
LXD_PROFILE=ihanick
```
Build docker images with systemd and sshd, simulating standalone physical servers:
```bash
cd images-build;
./build-lxd.sh
cd ..
```

### Start Percona Server 5.7
```bash
cd anydbver
./anydbver deploy ps:5.6
```
Login to container with Percona Server and connect with mysql command:
```bash
./anydbver ssh
mysql
```

## MongoDB
* Create a sharding cluster with 3-member replicasets (first shard, second shard, config servers) and mongos.
```bash
./anydbver deploy \
           psmdb:latest,replica-set=rs0,role=shard \
     node1 psmdb:latest,replica-set=rs0,role=shard,master=node0 \
     node2 psmdb:latest,replica-set=rs0,role=shard,master=node0 \
     node3 psmdb:latest,replica-set=rs1,role=shard
     node4 psmdb:latest,replica-set=rs1,role=shard,master=node3 \
     node5 psmdb:latest,replica-set=rs1,role=shard,master=node3 \
     node6 psmdb:latest,replica-set=cfg0,role=cfg
     node7 psmdb:latest,replica-set=cfg0,role=cfg,master=node6 \
     node8 psmdb:latest,replica-set=cfg0,role=cfg,master=node6 \
     node9 psmdb:latest mongos-cfg:cfg0/node6,node7,node8 mongos-shard:rs0/default,node1,node2,rs1/node3,node4,node5
```
* Same with backup to S3 storage (minio)

```bash
# create minio server in docker (outside of anydbver)
tools/create_backup_server.sh
tools/mc mb bkp/pbm-example
export MC_HOST_bkp=http://UIdgE4sXPBTcBB4eEawU:7UdlDzBF769dbIOMVILV@172.17.0.1:9000
./anydbver deploy node0 psmdb:latest,replica-set=rs0,role=shard pbm:s3=$MC_HOST_bkp/pbm-example \
  node1 psmdb:latest,replica-set=rs0,role=shard,master=node0 pbm:s3=$MC_HOST_bkp/pbm-example \
  node2 psmdb:latest,replica-set=rs0,role=shard,master=node0 pbm:s3=$MC_HOST_bkp/pbm-example \
  node3 psmdb:latest,replica-set=rs1,role=shard pbm:s3=$MC_HOST_bkp/pbm-example \
  node4 psmdb:latest,replica-set=rs1,role=shard,master=node3 pbm:s3=$MC_HOST_bkp/pbm-example \
  node5 psmdb:latest,replica-set=rs1,role=shard,master=node3 pbm:s3=$MC_HOST_bkp/pbm-example \
  node6 psmdb:latest,replica-set=cfg0,role=cfg pbm:s3=$MC_HOST_bkp/pbm-example \
  node7 psmdb:latest,replica-set=cfg0,role=cfg,master=node6 pbm:s3=$MC_HOST_bkp/pbm-example \
  node8 psmdb:latest,replica-set=cfg0,role=cfg,master=node6 pbm:s3=$MC_HOST_bkp/pbm-example \
  node9 psmdb:latest mongos-cfg:cfg0/node6,node7,node8 mongos-shard:rs0/node0,node1,node2,rs1/node3,node4,node5
```

## Postgresql
You can run PGDG postgresql distribution `pg`-keyword or Percona's build `ppg`-keyword.
* `primary` instructs node to join as secondary to specified primary
* optional `wal` parameter with logical argument switches `wal_level` to logical

```bash
./anydbver deploy node0 pg:latest,wal=logical node1 pg:latest,primary=node0,wal=logical
```

## More details and usage examples
There are usage examples in the help output:
```bash
./anydbver deploy help
```

Important deployments could be verified with tests:
```bash
./anydbver test all
```
You may review all test deployments with:
```
$ echo 'select cmd from tests'|sqlite3 anydbver_version.db 
./anydbver deploy os:el7 pg:11.12
./anydbver deploy os:el8 pg:11.12
./anydbver deploy os:el7 ppg:13.5
./anydbver deploy os:el8 ppg:13.5
./anydbver deploy k3d k8s-ps:0.5.0
./anydbver deploy psmdb:latest,replica-set=rs0,role=shard node1 psmdb:latest,replica-set=rs0,role=shard,master=node0 node2 psmdb:latest,replica-set=rs0,role=shard,master=node0 node3 psmdb:latest,replica-set=rs1,role=shard node4 psmdb:latest,replica-set=rs1,role=shard,master=node3 node5 psmdb:latest,replica-set=rs1,role=shard,master=node3 node6 psmdb:latest,replica-set=cfg0,role=cfg node7 psmdb:latest,replica-set=cfg0,role=cfg,master=node6 node8 psmdb:latest,replica-set=cfg0,role=cfg,master=node6 node9 psmdb:latest mongos-cfg:cfg0/node6,node7,node8 mongos-shard:rs0/node0,node1,node2,rs1/node3,node4,node5
./anydbver deploy psmdb:4.2,replica-set=rs0,role=shard node1 psmdb:4.2,replica-set=rs0,role=shard,master=node0 node2 psmdb:4.2,replica-set=rs0,role=shard,master=node0 node3 psmdb:4.2,replica-set=rs1,role=shard node4 psmdb:4.2,replica-set=rs1,role=shard,master=node3 node5 psmdb:4.2,replica-set=rs1,role=shard,master=node3 node6 psmdb:4.2,replica-set=cfg0,role=cfg node7 psmdb:4.2,replica-set=cfg0,role=cfg,master=node6 node8 psmdb:4.2,replica-set=cfg0,role=cfg,master=node6 node9 psmdb:4.2 mongos-cfg:cfg0/node6,node7,node8 mongos-shard:rs0/node0,node1,node2,rs1/node3,node4,node5
./anydbver deploy ldap node1 ldap-master:default psmdb:5.0
./anydbver deploy k3d cert-manager:1.7.2 k8s-pg:2.2.0
./anydbver deploy node0 ps:8.0,group-replication node1 ps:8.0,group-replication,master=node0 node2 ps:8.0,mysql-router,master=node0
./anydbver deploy ps:5.7 node1 ps:5.7,master=node0 node2 ps:5.7,master=node1 node3 percona-orchestrator:latest,master=node0
./anydbver deploy pxc node1 pxc:latest,master=node0,galera node2 pxc:latest,master=node0,galera
./anydbver deploy node0 ppg:latest,wal=logical node1 ppg:latest,primary=node0,wal=logical
./anydbver deploy node0 pg:latest,wal=logical node1 pg:latest,primary=node0,wal=logical
```
