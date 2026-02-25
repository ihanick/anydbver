# anydbver
Configuring MySQL, Percona MySQL/Postgresql/Mongo, MongoDB with ansible scripts.
Running multi-node replication clusters in Docker and Kubernetes.


# Installation
1. Setup Docker, make sure that your user added to the docker group:
2. Download anydbver binary for Linux (use Darvin for OSX (experimental))
```
mkdir -p ~/.local/bin
cd ~/.local/bin
wget https://github.com/zelmario/anydbver/releases/latest/download/anydbver
chmod +x anydbver
anydbver update
```
3. Usually Linux distributions adding ~/.local/bin to the path and it's enough to login/logout. If not, please put anydbver program to the path

# Upgrades
1. Download the latest version from [releases page](https://github.com/zelmario/anydbver/releases) as mentioned in the Installation section above
2. Execute `anydbver update` to update the version database using the sql file from the head

# Getting examples
Anydbver includes a test suite, you may list all deployment commands and run it/modify as you need:
```
anydbver test list
```
Additional help examples and all deployment commands from test available with:
```
anydbver deploy help
```

# Commands structure
## Nodes
The deployment command contains one or multiple severs (nodes):
```
anydbver deploy node0 [things to install on node0] node1 ... nodeN ...
```
Node names combined from "node" and number.
You can omit node0, anydbver assumes that node0 definition goes right after "deploy"
## Keywords (commands)
Each node could have one or multiple programs installed:
```
anydbver deploy percona-server:8.0
anydbver deploy percona-server
anydbver deploy ps
anydbver deploy minio:docker-image node1 pg pgbackrest:s3=node0
```

There is a current list of all keywords:
```
anydbver deploy help keywords
```
```
Keyword                          Description
-------------------------------  ----------------------------------------------------------------------------------------------
haproxy-pg                       Installs haproxy and configures it to be used with postgresql
ldap                             Installs openldap server
ldap-master                      Allows to specify where is ldap server on the client node
mariadb                          Installs Mariadb
mongos-cfg                       Allows to specify which nodes are MongoDB config servers
mongos-shard                     Allows to specify replica sets and config servers for MongoDB clusters
mysql                            Installs Oracle MySQL Community version
patroni                          Installs patroni
percona-backup-mongodb           Installs Percona Backup for MongoDB
percona-orchestrator             Installs MySQL Orchestrator, using Percona's packages
percona-postgresql               Installs Percona Postgresql distribution
percona-proxysql                 Installs ProxySQL from Percona's packages
percona-server                   Installs Percona Server for MySQL
percona-server-mongodb           Installs Percona Server for MongoDB
percona-xtradb-cluster           Installs Percona XtraDB Cluster (Percona Server patched to support Galera replication)
pgbackrest                       Installs pgbackrest
pmm-client                       Installs Percona Monitoring and Management client
postgresql                       Installs Postgresql from PGDG packages
repmgr                           Installs repmgr, Postgresql replication management solution
sysbench                         Installs sysbench to measure database performance
valkey                           Installs Valkey
cert-manager                     Installs cert-manager.io TLS certificates management and generation software for Kubernetes
k3d                              Using a specified node as a multi-server Kubernetes installation (Kubernetes nodes as nested Docker containers)
k8s-minio                        Installs MinIO S3 Server inside Kubernetes
k8s-pmm                          Installs Percona Monitoring and Management inside Kubernetes
percona-postgresql-operator      Installs Percona Postgresql Operator and creates a postgresql cluster in Kubernetes
percona-server-mongodb-operator  Installs Percona Server for MongoDB Operator and creates a PSMDB cluster in Kubernetes
percona-server-mysql-operator    Installs Percona Server for MySQL Operator (Group replication) and creates a MySQL cluster in Kubernetes
percona-xtradb-cluster-operator  Installs Percona XtraDB Cluster Operator and creates PXC cluster in Kubernetes
```
## Help for specific keyword, keyword aliases
It could be annoying to write long names like `percona-server-mongodb-operator` and you can use `k8s-psmdb`` alias instead.
There is an example for PSMDB operator, but you can use it for any keyword or alias.
```
$ anydbver deploy help percona-server-mongodb-operator
percona-server-mongodb-operator

Aliases for command(software) percona-server-mongodb-operator
k8s-mongo
k8s-psmdb

Subcommands (parameters) for command percona-server-mongodb-operator

cluster-name
helm
namespace
replicas
shards
version

anydbver deploy k3d:latest,ingress=443,ingress-type=nginxinc,nodes=3,host-alias="172.17.0.1:r1.percona.local|r2.percona.local|r3.percona.local" cert-manager k8s-psmdb:1.16.2,replicas=1,shards=0,namespace=db1 k8s-psmdb:1.16.2,replicas=1,shards=0,namespace=db2 k8s-psmdb:1.16.2,replicas=1,shards=0,namespace=db3
anydbver deploy k3d:v1.25.16-k3s4,cluster-domain=percona.local cert-manager:1.14.2 k8s-mongo:1.14.0,cluster-name=db1
```
## Software version specification
You can use just a bare keyword to specify version or put ':' after keyword to specify a version:
```
anydbver deploy ps
anydbver deploy ps:latest
anydbver deploy ps:8.0
anydbver deploy ps:8.0.29
```
## Sub-commands (or parameters for software configuration)
The full structure for the software definition is:
```
cmd:VERSION,subcmd1=VALUE1,subcmd2=VALUE2...
```

You may list all subcommands available for the cmd and usage examples with same:
```
anydbver deploy help percona-server-mongodb-operator
```

## docker-image subcommand
anydbver by default tries to mimic normal bare-metal Linux deployments, but you may need more speed/flexibility by using unmodified docker images for MySQL, Mongo, Postgresql, Valkey, MinIO
```
anydbver deploy valkey:unstable,docker-image node1 valkey:unstable,docker-image,master=node0 node2 valkey:unstable,docker-image,master=node0
anydbver deploy pmm:2.42.0,docker-image,port=12443 node1 ps:latest,group-replication pmm-client:2.42.0-6,server=node0 node2 ps:latest,group-replication,master=node1 pmm-client:2.42.0-6,server=node0 node3 ps:latest,group-replication,master=node1 pmm-client:2.42.0-6,server=node0
anydbver deploy pmm:docker-image=perconalab/pmm-server:dev-latest,port=12443 node1 mysql:latest,docker-image node2 pmm-client:docker-image=perconalab/pmm-client:dev-latest,server=node0,mysql=node1
anydbver deploy minio:docker-image node1 pg pgbackrest:s3=node0
```
Bare use of docker-image without value specified will use version as a tag (if it's numberic). The value could be a full/name:tag

# List nodes after deploy
Show all containers for default namespace (''). Containers have $NAMESPACE-$USER prefix, but all anydbver commands automatically stripping this prefix and you should use just node0 ... nodeN in your anydbver commands.
```
anydbver list
```

# Accessing nodes
The general method, run /bin/sh in a container:
```
anydbver exec node0
```
Containers with /bin/bash installed could use a login shell (like ssh login):
```
anydbver exec node0 -- bash -il
```
You may redirect or pipe STDIN and STDOUT for automation, e.g.
```
echo show variables | anydbver exec node1 -- mysql|grep gtid_mode|grep -q OFF
```

# Destroying environment
anydbver is intended for short-term tests and you can remove all traces for deployment with:
```
anydbver destroy
```
The environment is automatically destroyed if you are doing the deployment while previous deplyment is alive:
```
anydbver deploy os:el8 ps
anydbver deploy os:el9 ps
# now we have a Percona Server installed on Rocky Linux 9, not 8.
```
You can keep existing setup and only add additional items if --keep deployment argument is used:
```
anydbver deploy node0 ps
anydbver deploy --keep node1 ps:master=node0
# MySQL on the node1 is now a replica for node0
```

# Namespaces
You may need to keep existing environment and try something completely different, just put --namespace=ns1 (or use any name instead of ns1) right after anydbver and use it with all commands like deploy/exec/destroy

You can find a list of currently used namespaces with:
```
anydbver namespace list
```

# Kubernetes
anydbver is capable to run kubernetes using K3D project (Kubernetes cluster using nested docker containers). In order to simplify a setup, anydbver uses additional container with kubectl and other tools.
Git repositories for operators are stored under ~/.cache/anydbver/data/k8s
You may use your kubectl directly or exec inside a container with kubectl and helm configured with
```
anydbver shell
```
If you need anydbver with existing kubernetes installation, use `anydbver --provider=kubectl deploy` . It's not capable to destroy resources (currently cleanup is implemented just as docker container deletion).

# Files and directories used by anydbver
```
~/.config/anydbver
~/.cache/anydbver
```

# Previous version, written in python
The previous Python version of anydbver is deprecated and renamed to `anydbver.py`

