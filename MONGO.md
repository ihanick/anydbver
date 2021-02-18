# MongoDB cheat sheet

## Setup MongoDB Sharded cluster with shards. Each shared is a 3 node replica set

```
lxc image rm ${USER}-el7-psmdb-4.2.12 # remove old cache
# use same keyfile
openssl rand -base64 756 > secret/cfg0-keyfile
for i in rs{0,1,2}-keyfile ; do echo cp -L cfg0-keyfile $i; done
./anydbver deploy install psmdb:4.2.12 cache:psmdb-4.2.12
./anydbver deploy \
  default hostname:rs0-0  cache:psmdb-4.2.12 \
  node1   hostname:rs0-1  cache:psmdb-4.2.12 \
  node2   hostname:rs0-2  cache:psmdb-4.2.12 \
  node3   hostname:rs1-0  cache:psmdb-4.2.12 \
  node4   hostname:rs1-1  cache:psmdb-4.2.12 \
  node5   hostname:rs1-2  cache:psmdb-4.2.12 \
  node6   hostname:rs2-0  cache:psmdb-4.2.12 \
  node7   hostname:rs2-1  cache:psmdb-4.2.12 \
  node8   hostname:rs2-2  cache:psmdb-4.2.12 \
  node9   hostname:cfg0-0 cache:psmdb-4.2.12 \
  node10  hostname:cfg0-1 cache:psmdb-4.2.12 \
  node11  hostname:cfg0-2 cache:psmdb-4.2.12 \
  node12  hostname:route1 cache:psmdb-4.2.12 \
  \
  default psmdb:4.2.12               replica-set:rs0  shardsrv \
  node1   psmdb:4.2.12 master:rs0-0  replica-set:rs0  shardsrv \
  node2   psmdb:4.2.12 master:rs0-0  replica-set:rs0  shardsrv \
  node3   psmdb:4.2.12               replica-set:rs1  shardsrv \
  node4   psmdb:4.2.12 master:rs1-0  replica-set:rs1  shardsrv \
  node5   psmdb:4.2.12 master:rs1-0  replica-set:rs1  shardsrv \
  node6   psmdb:4.2.12               replica-set:rs2  shardsrv \
  node7   psmdb:4.2.12 master:rs2-0  replica-set:rs2  shardsrv \
  node8   psmdb:4.2.12 master:rs2-0  replica-set:rs2  shardsrv \
  node9   psmdb:4.2.12               replica-set:cfg0 configsrv \
  node10  psmdb:4.2.12 master:cfg0-0 replica-set:cfg0 configsrv \
  node11  psmdb:4.2.12 master:cfg0-0 replica-set:cfg0 configsrv \
  node12  psmdb:4.2.12 mongos-cfg:cfg0/cfg0-0,cfg0-1,cfg0-2 mongos-shard:rs0/rs0-0,rs0-1,rs0-2,rs1/rs1-0,rs1-1,rs1-2,rs2/rs2-0,rs2-1,rs2-2
```
