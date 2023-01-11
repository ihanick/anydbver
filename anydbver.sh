#!/bin/bash
[ -f .anydbver ] && source .anydbver

print_help() {
  echo "Usage: "
  echo "$0 configure provider:lxd"
  echo "$0 fix ip # update container ip addresses"
  echo "$0 ssh default or $0 ssh node1"
  echo "$0 update # refresh version information"
  echo "$0 destroy # remove containers and cleanup"
  echo "$0 list # show currently running containers"
  echo "$0 list-caches # show available caches"
  echo "$0 deploy help"
  echo "$0 add nodeN node_definition # spawn additional node and deploy software on it"
  echo "$0 replace nodeN node_definition # delete existing node, spawn additional and deploy software on it"
  echo "$0 apply nodeN node_definition # deploy software on existing node"
  echo "$0 --namespace mynsp <ssh|list|deploy|add|replace|apply> ... # separate deployments operations"
  echo "$0 port forward # forward port from lxc to Vagrant VM"
  echo "Bash completion: source <($0 completion bash)"
  exit 0
}

if [ "x$1" = "xhelp" -o "x$1" = "x--help" ] ; then
  print_help
fi

if [[ "$1" == "completion" && "$2" == "bash" ]] ; then
  echo "complete -C './anydbver complete bash' ./anydbver"
  exit 0
fi

print_completion_variants() {
  #echo "'$COMP_LINE'" >> ./completion.log
  local PROG=''
  local CMD=''
  local NODE=''
  local valid_commands=(deploy configure fix ssh update destroy list list-caches add replace apply --namespace --dry-run)
  local valid_targets=(anydbver backup backend-ip cache cert-manager certmanager channel cluster clustercheck configsrv debug development docker docker-registry etcd-ip galera-master garbd group-replication gtid haproxy-galera haproxy-postgresql haproxy-pg haproxy hostname hn install k3s-master k3s-leader k3s k8s kubernetes k8s-minio k8s-mongo k8s-pg k8s-pg-zalando k8s-pmm k8s-pxc kube-config ldap-master ldap-leader ldap-server ldap ldap-simple logical mariadb-galera mariadb maria master_ip leader minio minio-ip mongo-community mongos-cfg mongos-shard mydumper mysql-jdbc mysql-router mysql mysql-ndb-data mysql-ndb-management ps percona-server pxc pxc: percona-xtradb-cluster percona-xtradb-cluster:)
  for w in $COMP_LINE ; do
    if [[ "$PROG" == "" ]] ; then
      PROG="$w"
      #echo "Command: '$PROG'" >> ./completion.log
      continue
    fi
    if [[ "$CMD" == ""  ]] ; then
      if [[ " ${valid_commands[@]} " =~ " ${w} " ]] ; then
        CMD="$w"
        #echo "Valid command: '$CMD'" >> ./completion.log
        continue
      fi
    fi

    if [[ "$w" == "node"[0-9] || "$w" == "node"[0-9][0-9] ]] ; then
      NODE="$w"
    fi
  done

  if [[ "${COMP_LINE:$((${#COMP_LINE}-1))}" == " " ]] ; then
    w=''
  fi

  if [[ "$CMD" == ""  ]] ; then
    for i in "${valid_commands[@]}" ; do
      if [[ "$i" == "$w"* ]] ; then
        echo "$i"
      fi
    done
  fi

  if [[ "$CMD" == "deploy"  ]] ; then
    local NEXT_NODE=''
    if [[ "$NODE" == "" ]] ; then
      NEXT_NODE=node0
    else
      NEXT_NODE=node$(( ${NODE/node/} + 1 ))
    fi
    #echo "Last node: $NODE" >> ./completion.log
    #echo "Last word: $w" >> ./completion.log
    for i in $NEXT_NODE "${valid_targets[@]}" ; do
      if [[ "$i" == "$w"* ]] ; then
        echo "$i"
      fi
    done
  fi

}

if [[ "$1" == "complete" && "$2" == "bash" ]] ; then
  print_completion_variants
  exit 0
fi


if [ "x$1" = "xdeploy" ] && ([ "x$2" = "xpsmdb" -o "x$2" = "xmongo" -o "x$2" = "xmongodb"  ] ) && [ "x$3" = "xhelp" -o "x$3" = "x--help" ] ; then
    echo "Deploy mongodb/psmdb: "
    echo "$0 deploy psmdb"
    echo "$0 deploy psmdb replica-set:rs0 node1 psmdb master:default replica-set:rs0 node2 psmdb master:default replica-set:rs0"
    echo "$0 deploy node0 mongo-community replica-set:rs0 node1 mongo-community master:default replica-set:rs0 node2 mongo-community master:default replica-set:rs0"
    echo -e $0' deploy \\\n  psmdb:4.2 replica-set:rs0 shardsrv \\\n  node1 psmdb:4.2 master:default replica-set:rs0 shardsrv \\\n  node2 psmdb:4.2 master:default replica-set:rs0 shardsrv \\\n  node3 psmdb:4.2 configsrv replica-set:cfg0 \\\n  node4 psmdb:4.2 configsrv replica-set:cfg0 master:node3 \\\n  node5 psmdb:4.2 configsrv replica-set:cfg0 master:node3 \\\n  node6 psmdb:4.2 mongos-cfg:cfg0/node3,node4,node5 mongos-shard:rs0/default,node1,node2'
    echo "$0 deploy ldap node1 ldap-master:default psmdb:4.2"
    echo "$0 deploy samba node1 psmdb:4.2 samba-dc:default"
    echo "Deploy multiple shards:"

cat <<EOF
openssl rand -base64 756 > secret/cfg0-keyfile
for keyfile in rs{0,1,2}-keyfile ; do cp -L secret/cfg0-keyfile secret/\$keyfile; done
$0 deploy install psmdb:4.2.12 cache:psmdb-4.2.12
$0 deploy \\
  default hostname:rs0-0  cache:psmdb-4.2.12 \\
  node1   hostname:rs0-1  cache:psmdb-4.2.12 \\
  node2   hostname:rs0-2  cache:psmdb-4.2.12 \\
  node3   hostname:rs1-0  cache:psmdb-4.2.12 \\
  node4   hostname:rs1-1  cache:psmdb-4.2.12 \\
  node5   hostname:rs1-2  cache:psmdb-4.2.12 \\
  node6   hostname:rs2-0  cache:psmdb-4.2.12 \\
  node7   hostname:rs2-1  cache:psmdb-4.2.12 \\
  node8   hostname:rs2-2  cache:psmdb-4.2.12 \\
  node9   hostname:cfg0-0 cache:psmdb-4.2.12 \\
  node10  hostname:cfg0-1 cache:psmdb-4.2.12 \\
  node11  hostname:cfg0-2 cache:psmdb-4.2.12 \\
  node12  hostname:route1 cache:psmdb-4.2.12 \\
  node13  hostname:route1 cache:psmdb-4.2.12 \\
  node14  hostname:route1 cache:psmdb-4.2.12 \\
  \\
  default psmdb:4.2.12               replica-set:rs0  shardsrv \\
  node1   psmdb:4.2.12 master:rs0-0  replica-set:rs0  shardsrv \\
  node2   psmdb:4.2.12 master:rs0-0  replica-set:rs0  shardsrv \\
  node3   psmdb:4.2.12               replica-set:rs1  shardsrv \\
  node4   psmdb:4.2.12 master:rs1-0  replica-set:rs1  shardsrv \\
  node5   psmdb:4.2.12 master:rs1-0  replica-set:rs1  shardsrv \\
  node6   psmdb:4.2.12               replica-set:rs2  shardsrv \\
  node7   psmdb:4.2.12 master:rs2-0  replica-set:rs2  shardsrv \\
  node8   psmdb:4.2.12 master:rs2-0  replica-set:rs2  shardsrv \\
  node9   psmdb:4.2.12               replica-set:cfg0 configsrv \\
  node10  psmdb:4.2.12 master:cfg0-0 replica-set:cfg0 configsrv \\
  node11  psmdb:4.2.12 master:cfg0-0 replica-set:cfg0 configsrv \\
  node12  psmdb:4.2.12 mongos-cfg:cfg0/cfg0-0,cfg0-1,cfg0-2 mongos-shard:rs0/rs0-0,rs0-1,rs0-2,rs1/rs1-0,rs1-1,rs1-2,rs2/rs2-0,rs2-1,rs2-2 \\
  node13  psmdb:4.2.12 mongos-cfg:cfg0/cfg0-0,cfg0-1,cfg0-2 \\
  node14  psmdb:4.2.12 mongos-cfg:cfg0/cfg0-0,cfg0-1,cfg0-2
$0 deploy mongo pbm
$0 deploy mongo percona-backup-mongodb

$0 deploy \\
  --shared-directory \\
  node0 psmdb replica-set:rs0 pbm pbm-agent \\
  node1 psmdb master:default replica-set:rs0 pbm pbm-agent \\
  node2 psmdb master:default replica-set:rs0 pbm pbm-agent

# mongodb sharded cluster with Percona Backup
./anydbver deploy \\
  --shared-directory \\
  default hostname:rs0-0  cache:psmdb-4.2.12 \\
  node1   hostname:rs0-1  cache:psmdb-4.2.12 \\
  node2   hostname:rs0-2  cache:psmdb-4.2.12 \\
  node3   hostname:rs1-0  cache:psmdb-4.2.12 \\
  node4   hostname:rs1-1  cache:psmdb-4.2.12 \\
  node5   hostname:rs1-2  cache:psmdb-4.2.12 \\
  node6   hostname:rs2-0  cache:psmdb-4.2.12 \\
  node7   hostname:rs2-1  cache:psmdb-4.2.12 \\
  node8   hostname:rs2-2  cache:psmdb-4.2.12 \\
  node9   hostname:cfg0-0 cache:psmdb-4.2.12 \\
  node10  hostname:cfg0-1 cache:psmdb-4.2.12 \\
  node11  hostname:cfg0-2 cache:psmdb-4.2.12 \\
  node12  hostname:route1 cache:psmdb-4.2.12 \\
  \\
  default psmdb:4.2.12               replica-set:rs0  shardsrv \\
  node1   psmdb:4.2.12 master:rs0-0  replica-set:rs0  shardsrv \\
  node2   psmdb:4.2.12 master:rs0-0  replica-set:rs0  shardsrv \\
  node3   psmdb:4.2.12               replica-set:rs1  shardsrv \\
  node4   psmdb:4.2.12 master:rs1-0  replica-set:rs1  shardsrv \\
  node5   psmdb:4.2.12 master:rs1-0  replica-set:rs1  shardsrv \\
  node6   psmdb:4.2.12               replica-set:rs2  shardsrv \\
  node7   psmdb:4.2.12 master:rs2-0  replica-set:rs2  shardsrv \\
  node8   psmdb:4.2.12 master:rs2-0  replica-set:rs2  shardsrv \\
  node9   psmdb:4.2.12               replica-set:cfg0 configsrv pbm pbm-agent \\
  node10  psmdb:4.2.12 master:cfg0-0 replica-set:cfg0 configsrv pbm pbm-agent \\
  node11  psmdb:4.2.12 master:cfg0-0 replica-set:cfg0 configsrv pbm pbm-agent \\
  node12  psmdb:4.2.12 mongos-cfg:cfg0/cfg0-0,cfg0-1,cfg0-2 mongos-shard:rs0/rs0-0,rs0-1,rs0-2,rs1/rs1-0,rs1-1,rs1-2,rs2/rs2-0,rs2-1,rs2-2 \\
  node0   pbm pbm-agent \\
  node1   pbm pbm-agent \\
  node2   pbm pbm-agent \\
  node3   pbm pbm-agent \\
  node4   pbm pbm-agent \\
  node5   pbm pbm-agent \\
  node6   pbm pbm-agent \\
  node7   pbm pbm-agent \\
  node8   pbm pbm-agent
EOF

    exit 0
fi

if [ "x$1" = "xdeploy" ] && ([ "x$2" = "xmysql" -o "x$2" = "xpercona-server" -o "x$2" = "xmariadb"  ] ) && [ "x$3" = "xhelp" -o "x$3" = "x--help" ] ; then
    echo "Deploy MySQL/Percona Server/MariaDB: "
    echo "$0 deploy percona-server:8.0.16"
    echo "$0 deploy percona-server:8.0"
    echo "$0 deploy percona-server"
    echo "$0 deploy percona-server rocksdb"
    echo "$0 deploy ps:5.7"
    echo "$0 deploy ps:5.7 mydumper"
    echo "$0 deploy ps:8.0.22 xtrabackup"
    echo "$0 deploy ps:5.7 perf devel"
    echo "$0 deploy ps node1 sysbench sysbench-mysql:default oltp_read_write"
    echo "$0 deploy hn:vault.percona.local vault node1 ps:8.0 vault-server:vault.percona.local"
    echo "$0 deploy ps:5.7 percona-toolkit"
    echo "$0 deploy ps:8.0.22 hn:ps0 node1 ps:8.0.22 hn:ps1 node2 ps:8.0.22 hn:ps2 master:ps0 node2 ps:8.0.22 master:ps1 channel:ps1ch"
    echo "$0 deploy mysql"
    echo -e $0' deploy \\\n  hn:mysql_rs0_gr0 mysql:8.0.18 group-replication \\\n  node1 hn:mysql_rs0_gr1 mysql:8.0.18 group-replication master:default \\\n  node2 hn:mysql_rs0_gr2 mysql:8.0.18 group-replication master:default \\\n  node3 hn:mysql_rs0_router mysql-router:8.0.18 master:default'
    echo -e $0' deploy \\\n  node0 mysql-ndb-management ndb-data-nodes:node1,node2 ndb-sql-nodes:node3 ndb-connectstring:node0 hn:mgm \\\n  node1 mysql-ndb-data ndb-connectstring:node0 hn:data1 \\\n  node2 mysql-ndb-data ndb-connectstring:node0 hn:data2 \\\n  node3 mysql-ndb-sql ndb-connectstring:node0 hn:sql'
    echo "$0 deploy mariadb:10.4"
    echo "$0 deploy maria:10.4"
    echo "$0 deploy mariadb node1 mariadb master:default"
    echo "$0 deploy mariadb node1 mariadb master:default default mariadb master:node1 node2 mariadb master:node1"
    echo "$0 deploy mariadb-cluster:10.3.26:25.3.30"
    echo "$0 deploy mariadb-cluster:10.4 node1 mariadb-cluster:10.4 galera-master:default node2 mariadb-cluster:10.4 galera-master:default"
    echo "$0 deploy ldap node1 ldap-master:default ps:5.7"
    echo "$0 deploy ps:5.7 node1 ps:5.7 master:default node2 ps:5.7 master:node1"
    echo "$0 deploy ps:5.7 hostname:leader.percona.local node1 ps:5.7 hostname:follower.percona.local leader:default"
    echo "$0 deploy ps:8.0 utf8 node1 ps:5.7 master:default node2 ps:5.6 master:node1 row"
    echo "$0 deploy hn:ps0 ps:5.7 node1 hn:ps1 ps:5.7 master:default node2 hn:ps2 ps:5.7 master:node1 node3 hn:orc orchestrator master:default"
    echo "$0 deploy hn:ps0 ps:5.7 node1 hn:ps1 ps:5.7 master:default node2 hn:ps2 ps:5.7 master:node1 node3 hn:orc percona-orchestrator master:default"
    echo "$0 deploy samba node1 ps samba-dc:default"
    echo "$0 deploy pxc:5.7 node1 pxc:5.7 galera-master:default node2 pxc:5.7 galera-master:default"
    echo -e $0' deploy \\\n pxc:5.7 node1 pxc:5.7 galera-master:default node2 pxc:5.7 galera-master:default \\\n node3 pxc:5.7 cluster:cluster2 node4 pxc:5.7 cluster:cluster2 galera-master:node3 node5 pxc:5.7 cluster:cluster2 galera-master:node3'
    echo "$0 deploy pxc:5.7 node1 pxc:5.7 galera-master:default node2 pxc:5.7 garbd galera-master:default"
    echo -e $0' deploy \\\n  haproxy-galera:node1,node2,node3 \\\n  node1 pxc clustercheck \\\n  node2 pxc galera-master:node1 clustercheck \\\n  node3 pxc galera-master:node1 clustercheck'
    echo "$0 deploy ps:8.0 group-replication node1 ps:8.0 group-replication master:default node2 ps:8.0 group-replication master:default"
    cat <<EOF
# Create MySQL NDB Cluster HA setup: 3 Management nodes, 6 Data nodes, 2 SQL nodes
$0 deploy \
  node0 mysql-ndb-management ndb-data-nodes:node3,node4,node5,node6,node7,node8 ndb-sql-nodes:node9,node10 ndb-connectstring:node0,node1,node2 hn:mgm1 \\
  node1 mysql-ndb-management ndb-data-nodes:node3,node4,node5,node6,node7,node8 ndb-sql-nodes:node9,node10 ndb-connectstring:node0,node1,node2 hn:mgm2 \\
  node2 mysql-ndb-management ndb-data-nodes:node3,node4,node5,node6,node7,node8 ndb-sql-nodes:node9,node10 ndb-connectstring:node0,node1,node2 hn:mgm3 \\
  node3 mysql-ndb-data ndb-connectstring:node0,node1,node2 hn:data1 \\
  node4 mysql-ndb-data ndb-connectstring:node0,node1,node2 hn:data2 \\
  node5 mysql-ndb-data ndb-connectstring:node0,node1,node2 hn:data3 \\
  node6 mysql-ndb-data ndb-connectstring:node0,node1,node2 hn:data4 \\
  node7 mysql-ndb-data ndb-connectstring:node0,node1,node2 hn:data5 \\
  node8 mysql-ndb-data ndb-connectstring:node0,node1,node2 hn:data6 \\
  node9 mysql-ndb-sql ndb-connectstring:node0,node1,node2 hn:sql1 \\
  node10 mysql-ndb-sql ndb-connectstring:node0,node1,node2 hn:sql2
EOF

    exit 0
fi


if [ "x$2" = "xhelp" -o "x$2" = "x--help" ] ; then
  if [ "x$1" = "xdeploy" ] ; then
    echo "Deploy: "
    echo "$0 deploy percona-server:8.0.16"
    echo "$0 deploy percona-server:8.0"
    echo "$0 deploy percona-server"
    echo "$0 deploy ps:5.7"
    echo "$0 deploy ps:5.7 mydumper"
    echo "$0 deploy ps:8.0.22 xtrabackup"
    echo "$0 deploy ps:5.7 perf devel"
    echo "$0 deploy ps node1 sysbench sysbench-mysql:default oltp_read_write"
    echo "$0 deploy hn:vault.percona.local vault node1 ps:8.0 vault-server:vault.percona.local"
    echo "$0 deploy ps:5.7 percona-toolkit"
    echo "$0 deploy ps:8.0.22 hn:ps0 node1 ps:8.0.22 hn:ps1 node2 ps:8.0.22 hn:ps2 master:ps0 node2 ps:8.0.22 master:ps1 channel:ps1ch"
    echo "$0 deploy mysql"
    echo -e $0' deploy \\\n  hn:mysql_rs0_gr0 mysql:8.0.18 group-replication \\\n  node1 hn:mysql_rs0_gr1 mysql:8.0.18 group-replication master:default \\\n  node2 hn:mysql_rs0_gr2 mysql:8.0.18 group-replication master:default \\\n  node3 hn:mysql_rs0_router mysql-router:8.0.18 master:default'
    echo -e $0' deploy \\\n  node0 mysql-ndb-management ndb-data-nodes:node1,node2 ndb-sql-nodes:node3 ndb-connectstring:node0 hn:mgm \\\n  node1 mysql-ndb-data ndb-connectstring:node0 hn:data1 \\\n  node2 mysql-ndb-data ndb-connectstring:node0 hn:data2 \\\n  node3 mysql-ndb-sql ndb-connectstring:node0 hn:sql'
    echo "$0 deploy mariadb:10.4"
    echo "$0 deploy maria:10.4"
    echo "$0 deploy mariadb node1 mariadb master:default"
    echo "$0 deploy mariadb node1 mariadb master:default default mariadb master:node1 node2 mariadb master:node1"
    echo "$0 deploy mariadb-cluster:10.3.26:25.3.30"
    echo "$0 deploy mariadb-cluster:10.4 node1 mariadb-cluster:10.4 galera-master:default node2 mariadb-cluster:10.4 galera-master:default"
    echo "$0 deploy ldap node1 ldap-master:default ps:5.7"
    echo "$0 deploy ps:5.7 node1 ps:5.7 master:default node2 ps:5.7 master:node1"
    echo "$0 deploy ps:5.7 hostname:leader.percona.local node1 ps:5.7 hostname:follower.percona.local leader:default"
    echo "$0 deploy ps:8.0 utf8 node1 ps:5.7 master:default node2 ps:5.6 master:node1 row"
    echo "$0 deploy hn:ps0 ps:5.7 node1 hn:ps1 ps:5.7 master:default node2 hn:ps2 ps:5.7 master:node1 node3 hn:orc orchestrator master:default"
    echo "$0 deploy samba node1 ps samba-dc:default"
    echo "$0 deploy pxc:5.7 node1 pxc:5.7 galera-master:default node2 pxc:5.7 galera-master:default"
    echo -e $0' deploy \\\n pxc:5.7 node1 pxc:5.7 galera-master:default node2 pxc:5.7 galera-master:default \\\n node3 pxc:5.7 cluster:cluster2 node4 pxc:5.7 cluster:cluster2 galera-master:node3 node5 pxc:5.7 cluster:cluster2 galera-master:node3'
    echo "$0 deploy pxc:5.7 node1 pxc:5.7 galera-master:default node2 pxc:5.7 garbd galera-master:default"
    echo -e $0' deploy \\\n  haproxy-galera:node1,node2,node3 \\\n  node1 pxc clustercheck \\\n  node2 pxc galera-master:node1 clustercheck \\\n  node3 pxc galera-master:node1 clustercheck'
    echo "$0 deploy ps:8.0 group-replication node1 ps:8.0 group-replication master:default node2 ps:8.0 group-replication master:default"
    echo "$0 deploy node0 docker kubeadm hn:master1.percona.local virtual-machine cpu:2 mem:3GB node1 kubeadm-url:master1.percona.local  docker hn:worker1.percona.local virtual-machine cpu:2 mem:3GB node2 kubeadm-url:master1.percona.local docker hn:worker2.percona.local virtual-machine cpu:2 mem:3GB node3  kubeadm-url:master1.percona.local docker hn:worker3.percona.local virtual-machine cpu:2 mem:3GB node0 k8s-pxc kubeadm"
    echo "$0 deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default"
    echo "$0 deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default k8s-mongo"
    echo "$0 deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default k8s-minio k8s-mongo"
    echo "$0 deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default k8s-pxc"
    echo "$0 deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default cert-manager k8s-pxc"
    echo "$0 deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default node4 k3s-master:default default vites"
    echo "$0 deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default k8s-minio k8s-pmm k8s-pxc backup"
    echo "$0 deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default k8s-minio k8s-pxc backup pxc57"
    echo "$0 deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default k8s-pg"
    echo "$0 deploy k3s node1 k3s-master:default node2 k3s-master:default node3 k3s-master:default default k8s-pg-zalando"
    echo "$0 deploy pg:12.3"
    echo "$0 deploy pg:12.3 node1 pg:12.3 master:default"
    echo "$0 deploy pg pgbackrest"
    echo "$0 deploy node0 hn:minio.percona.local minio node1 minio-ip:minio.percona.local pg pgbackrest"
    echo "$0 deploy node0 hn:minio.percona.local minio node1 minio-ip:minio.percona.local pg wal-g"
    echo "$0 deploy pg node1 pg master:default default pg pgpool backend-ip:default"
    echo "$0 deploy pg:13 patroni node1 pg:13 master:default patroni etcd-ip:default node2 pg:13 master:default patroni etcd-ip:default"
    echo "$0 deploy haproxy-pg:node1,node2,node3 node1 pg clustercheck node2 pg clustercheck master:node1 node3 pg clustercheck master:node1"
    echo "$0 deploy node0 pmm node1 pmm-client pmm-server:node0 pg pg_stat_monitor development"
    echo "$0 deploy pmm node1 ppg pmm-client pmm-server:default"
    echo "$0 deploy postgresql sysbench sysbench-pg:default oltp_read_write"
    echo -e $0' deploy percona-postgresql \\\n  sysbench sysbench-pg:default oltp_read_write # prepare, execute run_sysbench.sh to start sysbench'
    echo -e $0' deploy \\\n        postgresql sysbench sysbench-pg:default oltp_read_write  \\\n  node1 postgresql master:default logical:sbtest  \\\n  node2 postgresql master:default logical:sbtest'
    echo "$0 deploy psmdb"
    echo "$0 deploy mongo pbm"
    echo "$0 deploy psmdb replica-set:rs0 node1 psmdb master:default replica-set:rs0 node2 psmdb master:default replica-set:rs0"
    echo -e $0' deploy \\\n psmdb:4.2 replica-set:rs0 shardsrv \\\n node1 psmdb:4.2 master:default replica-set:rs0 shardsrv \\\n node2 psmdb:4.2 master:default replica-set:rs0 shardsrv \\\n node3 psmdb:4.2 configsrv replica-set:cfg0 \\\n node4 psmdb:4.2 configsrv replica-set:cfg0 master:node3 \\\n node5 psmdb:4.2 configsrv replica-set:cfg0 master:node3 \\\n node6 psmdb:4.2 mongos-cfg:cfg0/node3,node4,node5 mongos-shard:rs0/default,node1,node2'
    echo "$0 deploy ldap node1 ldap-master:default psmdb:4.2"
    echo "$0 deploy samba node1 psmdb:4.2 samba-dc:default"
    echo "$0 deploy sysbench"
    echo "$0 deploy ps:5.7 node1 ps:5.7 master:default node2 ps:5.7 master:default node3 proxysql master:default"
    echo -e $0' deploy ps:5.7 node1 ps:5.7 master:default node2 ps:5.7 master:default \\\n  node3 proxysql master:default node4 proxysql proxysql-ip:node3 node5 proxysql proxysql-ip:node3'
    echo "$0 deploy pxc:5.7 node1 pxc:5.7 galera-master:default node2 pxc:5.7 galera-master:default node3 proxysql galera-master:default"
    echo "$0 deploy pxc node1 pxc galera-master:default node2 pxc galera-master:default node3 proxysql galera-master:default"
    echo "$0 deploy pmm node1 ps:5.7 pmm-client pmm-server:default"
    echo "$0 deploy pmm:1.17.4 node1 ps:5.7 pmm-client:1.17.4 pmm-server:default"
    echo "$0 deploy docker"
    echo "$0 deploy docker docker-registry hn:registry.percona.local"
    echo "$0 deploy node0 docker docker-registry hn:registry.percona.local node1 k3s k3s-registry:node0 node2 k3s-master:node1 k3s-registry:node0 node3 k3s-master:node1 k3s-registry:node0 node4 k3s-master:node1 k3s-registry:node0"
    echo "$0 deploy mongo help"
    echo "$0 deploy mysql help"
    echo "$0 deploy psmdb help"
    exit 0
  fi
fi

NAMESPACE_CMD=''
NAMESPACE=''
SHARED_DIRECTORY=0
DRY_RUN=0

if [ "x$1" = "xdeploy" ] && [ "x$2" = "x--dry-run"  ] ; then
  DRY_RUN=1
fi

opts=$(getopt \
    --longoptions "dry-run,destroy,namespace:,provider:,os:,shared-directory" \
    --name "$(basename "$0")" \
    --options "-n:" \
    -- "$@"
)

eval set --"$opts"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --namespace | -n)
      NAMESPACE="$2-"
      NAMESPACE_CMD="--namespace $2"
      shift 2
      ;;
    --provider)
      PROVIDER="$2"
      shift 2
      ;;
    --os)
      NODE_OS="$2"
      shift 2
      ;;
    --destroy)
      DESTROY=1
      shift
      ;;
    --shared-directory)
      SHARED_DIRECTORY=1
      shift
      ;;
      *)
      break
      ;;
  esac
done

if [[ "$1" == "--" ]] ; then
  shift
fi

setup_existing_hosts() {
  PYTHON_INT=/usr/bin/python

  :> ${NAMESPACE}ansible_hosts

  for w in ${ANSIBLE_WORKERS//,/ } ; do
    NODE=${USER}.${w//:*/}
    IP=${w//*:/}

    if [ "x$NODE" = "x${USER}.node0" ] ; then
      echo "${USER}.default ansible_connection=ssh ansible_user=root ansible_ssh_private_key_file=secret/id_rsa ansible_host=$IP ansible_python_interpreter=$PYTHON_INT ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand=none'" >> ${NAMESPACE}ansible_hosts
    fi

    echo "$NODE ansible_connection=ssh ansible_user=root ansible_ssh_private_key_file=secret/id_rsa ansible_host=$IP ansible_python_interpreter=$PYTHON_INT ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand=none'" >> ${NAMESPACE}ansible_hosts


    cat >> ${NAMESPACE}ssh_config <<EOF
Host ${NODE/$USER./}
   User root
   HostName $IP
   StrictHostKeyChecking no
   UserKnownHostsFile /dev/null
   IdentityFile ~/.ssh/id_rsa
   ProxyCommand none
EOF

  done
}

if [ "x$1" = "xconfigure" ] ; then
  while (( "$#" )); do
    if [[ "$1" == provider:* ]] ; then
      PROVIDER=$(echo "$1"|cut -d: -f 2)
      case "$PROVIDER" in
        vagrant)
          ;;
        lxdock)
          ;;
        podman)
          ;;
        lxd)
          ;;
        docker)
          ;;
        existing)
          setup_existing_hosts
          ;;
        *)
          echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
          exit 1
      esac
    fi
    shift
  done

  :> .anydbver
  echo "PROVIDER=$PROVIDER" >> .anydbver
  echo "LXD_PROFILE=$LXD_PROFILE" >> .anydbver

  exit 0
fi


if [ "x$1" = "xssh" ] ; then
  shift
  NODE="$1"
  if [[ "$NODE" == "" || "$NODE" == "--" ]] ; then
    NODE=default
  else
    shift
  fi
  case "$PROVIDER" in
    vagrant)
      exec vagrant ssh "$NODE" "$@"
      ;;
    lxdock)
      ;;
    podman)
      exec ./podmanctl ssh "$NODE" "$@"
      ;;
    lxd)
      exec ./lxdctl $NAMESPACE_CMD ssh "$NODE" "$@"
      ;;
    docker)
      exec ./lxdctl $NAMESPACE_CMD ssh "$NODE" "$@"
      ;;
    existing)
      exec ./lxdctl $NAMESPACE_CMD ssh "$NODE" "$@"
      ;;
    *)
      echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
      exit 1
  esac
fi
if [ "x$1" = "xlist" ] || [ "x$1" = "xls" ] ; then
  case "$PROVIDER" in
    podman)
      exec ./podmanctl list
      ;;
    lxd)
      exec ./lxdctl $NAMESPACE_CMD list
      ;;
    existing)
      echo $ANSIBLE_WORKERS
      ;;
    *)
      echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
      exit 1
  esac
  exit 0
fi
if [ "x$1" = "xlist-caches" ] ; then
  case "$PROVIDER" in
    podman)
      exec ./podmanctl list-caches
      ;;
    lxd)
      exec ./lxdctl $NAMESPACE_CMD list-caches
      ;;
    existing)
      ;;
    *)
      echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
      exit 1
  esac
  exit 0
fi
if [ "x$1" = "xfix" ] && [ "x$2" = "xip" ] ; then
  exec ./lxdctl $NAMESPACE_CMD --fix-ip
  exit 0
fi

if [ "x$1" = "xdestroy" ] || [[ "$DESTROY" == 1 ]] ; then
  shift
  NODE="$1"
  if [[ "x$NODE" != "x" ]] ; then
    shift
  fi
  case "$PROVIDER" in
    vagrant)
      exec vagrant destroy -f
      ;;
    lxdock)
      exec lxdock destroy -f
      ;;
    podman)
      exec ./podmanctl --destroy
      ;;
    lxd)
      exec ./lxdctl $NAMESPACE_CMD --destroy $NODE
      ;;
    docker)
      exec ./docker_container.py --nodes=3 --destroy
      ;;
    existing)
      echo "Please destroy $ANSIBLE_WORKERS manually"
      ;;
    *)
      echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
      exit 1
  esac
fi


get_version() {
  if [[ $i == *':'* ]] ; then
    echo "$1" | cut -d: -f2
  else
    echo "$1" | cut -d= -f2
  fi
}

get_2nd_version() {
  if [[ $i == *':'* ]] ; then
    echo "$1" | cut -d: -f3
  else
    echo "$1" | cut -d= -f3
  fi
}

search_for_latest_version() {
  local prod=$1
  local user_ver=$2
  if [[ $user_ver == *':'* ]] || [[ $user_ver == *'='* ]] ; then
    VER=$(get_version "$user_ver")
    VER=$(grep "^$VER" .version-info/${prod}.${NODE_OS}.txt |tail -n 1)
  else
    VER=$(tail -n 1 .version-info/${prod}.${NODE_OS}.txt)
  fi
  if [ "x$VER" == "x" ] ; then
    echo "No such version ${prod} for $NODE_OS: '$user_ver'" >&2
    exit 1
  fi
}



refresh_percona_server_version_info() {
  [ -d .version-info ] || mkdir .version-info
  curl -sL https://repo.percona.com/percona/yum/release/7/RPMS/x86_64/|perl -ne '/Percona-Server-server-\d\d-([^"]*).el7.x86_64.rpm/ and print "$1\n"' > .version-info/percona-server.el7.txt

  curl -sL https://www.percona.com/downloads/Percona-Server-LATEST/ > .version-info/percona-server-80.html
  for VER in $( cat .version-info/percona-server-80.html |perl -ne 'm,option value=\"Percona-Server-LATEST/Percona-Server-([^/]*?)\", and print "$1\n"'|sort -n ) ; do
    curl -sL https://www.percona.com/downloads/Percona-Server-LATEST/Percona-Server-"$VER"/binary/redhat/7/ |grep "$VER"|perl -ne '/percona-server-server-(.*?).el7.x86_64.rpm/ and print "$1\n"'
  done >> .version-info/percona-server.el7.txt

  curl -sL https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/|perl -ne '/Percona-Server-server-\d\d-([^"]*).el8.x86_64.rpm/ and print "$1\n"' | grep -v debuginfo > .version-info/percona-server.el8.txt
  for VER in $( cat .version-info/percona-server-80.html |perl -ne 'm,option value=\"Percona-Server-LATEST/Percona-Server-([^/]*?)\", and print "$1\n"'|sort -n ) ; do
    curl -sL https://www.percona.com/downloads/Percona-Server-LATEST/Percona-Server-"$VER"/binary/redhat/8/ |grep "$VER"|perl -ne '/percona-server-server-(.*?).el8.x86_64.rpm/ and print "$1\n"'
  done >> .version-info/percona-server.el8.txt

  rm -f .version-info/percona-server-80.html

  curl -sL https://repo.percona.com/ps-57/apt/pool/main/p/percona-server-5.7/ \
    | perl -ne  '/percona-server-server-\d.\d_([^"]*).focal_amd64.deb/ and print "$1\n"' > .version-info/percona-server.focal.txt
  curl -sL https://repo.percona.com/ps-80/apt/pool/main/p/percona-server/ \
    | perl -ne  '/percona-server-server_([^"]*).focal_amd64.deb/ and print "$1\n"' >> .version-info/percona-server.focal.txt
  curl -sL https://repo.percona.com/percona/apt/pool/main/p/percona-xtradb-cluster-5.7/ \
    | perl -ne  '/percona-xtradb-cluster-server-5.7_([^"]*).focal_amd64.deb/ and print "$1\n"' > .version-info/percona-xtradb-cluster.focal.txt
  curl -sL https://repo.percona.com/pxc-80/apt/pool/main/p/percona-xtradb-cluster/ \
    | perl -ne  '/percona-xtradb-cluster-server_([^"]*).focal_amd64.deb/ and print "$1\n"' >> .version-info/percona-xtradb-cluster.focal.txt

  for os in bionic stretch buster ; do
    curl -sL https://repo.percona.com/percona/apt/pool/main/p/percona-server-5.6/ https://repo.percona.com/percona/apt/pool/main/p/percona-server-5.7/ \
      | perl -ne  '/percona-server-server-\d.\d_([^"]*).'$os'_amd64.deb/ and print "$1\n"' | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/percona-server.$os.txt
    curl -sL https://repo.percona.com/ps-80/apt/pool/main/p/percona-server/ \
      | perl -ne  '/percona-server-server_([^"]*).'$os'_amd64.deb/ and print "$1\n"' >> .version-info/percona-server.$os.txt
    curl -sL https://repo.percona.com/percona/apt/pool/main/p/percona-xtradb-cluster-5.6/ \
      | perl -ne  '/percona-xtradb-cluster-server-5.?6_([^"]*).'$os'_amd64.deb/ and print "$1\n"' > .version-info/percona-xtradb-cluster.$os.txt
    curl -sL https://repo.percona.com/percona/apt/pool/main/p/percona-xtradb-cluster-5.7/ \
      | perl -ne  '/percona-xtradb-cluster-server-5.7_([^"]*).'$os'_amd64.deb/ and print "$1\n"' >> .version-info/percona-xtradb-cluster.$os.txt
    curl -sL https://repo.percona.com/pxc-80/apt/pool/main/p/percona-xtradb-cluster/ \
      | perl -ne  '/percona-xtradb-cluster-server_([^"]*).'$os'_amd64.deb/ and print "$1\n"' >> .version-info/percona-xtradb-cluster.$os.txt
  done

  curl -sL https://repo.percona.com/percona/yum/release/7/RPMS/x86_64/|perl -ne '/Percona-XtraDB-Cluster-\d\d-([0-9.-]*).el7.x86_64.rpm/ and print "$1\n"' > .version-info/percona-xtradb-cluster.el7.txt
  curl -sL https://repo.percona.com/pxc-80/yum/release/7/RPMS/x86_64/|perl -ne '/percona-xtradb-cluster-([0-9.-]*).el7.x86_64.rpm/ and print "$1\n"' >> .version-info/percona-xtradb-cluster.el7.txt
  # el8
  curl -sL https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/|perl -ne '/Percona-XtraDB-Cluster-\d\d-([0-9.-]*).el8.x86_64.rpm/ and print "$1\n"' > .version-info/percona-xtradb-cluster.el8.txt
  curl -sL https://repo.percona.com/pxc-80/yum/release/8/RPMS/x86_64/|perl -ne '/percona-xtradb-cluster-([0-9.-]*).el8.x86_64.rpm/ and print "$1\n"' >> .version-info/percona-xtradb-cluster.el8.txt

  curl -sL https://repo.percona.com/percona/yum/release/7/RPMS/x86_64/ \
   | perl -ne '/proxysql[0-9]*-([0-9.-]*).el7.x86_64.rpm/ and print "$1\n"' \
   | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/percona-proxysql.el7.txt
  curl -sL https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/ \
   | perl -ne '/proxysql[0-9]*-([0-9.-]*).el8.x86_64.rpm/ and print "$1\n"' \
   | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/percona-proxysql.el8.txt

  curl -sL https://repo.percona.com/percona/yum/release/7/RPMS/x86_64/ \
    | perl -ne '/percona-xtrabackup(?:-[0-9]+)-([0-9.-]*).el7.x86_64.rpm/ and print "$1\n"' \
    | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/xtrabackup.el7.txt
  curl -sL https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/ \
    | perl -ne '/percona-xtrabackup(?:-[0-9]+)-([0-9.-]*).el8.x86_64.rpm/ and print "$1\n"' \
    | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/xtrabackup.el8.txt


  :> .version-info/mariadb.el7.txt
  :> .version-info/mariadb.el8.txt

  for i in $(curl -sL https://archive.mariadb.org/|grep -F mariadb-10.|sed -re 's,^.*href="mariadb-(10\.[0-9]+\.[0-9]+)/.*$,\1,'|grep -v '[a-zA-Z]') ; do echo https://archive.mariadb.org/mariadb-$i/yum/centos7-amd64/rpms/ ; done|xargs curl -sL |sort -u > .version-info/mariadb-pkg.list.txt
  perl -ne '/MariaDB-server-(\d[^"]*).el7.centos.x86_64.rpm/ and print "$1\n"' .version-info/mariadb-pkg.list.txt|sort -n -t . -k1,1 -k2,2 -k3,3|uniq > .version-info/mariadb.el7.txt
  rm -f .version-info/mariadb-pkg.list.txt
  for ver in $(grep 10.[3-6] .version-info/mariadb.el7.txt) ; do
    short_ver=$(echo $ver|sed -re 's/-[0-9]+$//')
    for galera_ver in $( curl -sL https://archive.mariadb.org/mariadb-$short_ver/yum/centos7-amd64/rpms/ |grep galera|perl -pe 's/^.*<a href="galera-([0-9]+-)?([^>]+)\.rhel7\.el7\.centos\.x86_64\.rpm" title=.*$/\2/;s/^.*<a href="galera-([0-9]+-)?([^>]+)\.el7\.centos\.x86_64\.rpm" title=.*$/\2/' | egrep -v '[a-zA-Z]' ) ; do
      echo -n "$ver "
      echo $galera_ver
    done
  done > .version-info/mariadb-galera.el7.txt

  for maver in 10.3 10.4 10.5 ; do
    curl -sL http://yum.mariadb.org/$maver/centos8-amd64/rpms/| perl -ne '/MariaDB-server-(\d[^"]*).el8.x86_64.rpm/ and print "$1\n"' >> .version-info/mariadb.el8.txt
  done

  for ver in $(grep 10.[3-5] .version-info/mariadb.el8.txt) ; do
    short_ver=$(echo $ver|sed -re 's/-[0-9]+$//')
    for galera_ver in $( curl -sL https://mirrors.ukfast.co.uk/sites/mariadb/mariadb-${short_ver}/yum/centos8-amd64/rpms/|grep galera|grep -v rhel8|sed -re 's/<a href="galera-([0-9]+-)?([^>]+)\.el8\.x86_64\.rpm">.*$/\2/' ) ; do
      echo -n "$ver "
      echo $galera_ver
    done
  done > .version-info/mariadb-galera.el8.txt

  curl -s \
    https://repo.mysql.com/yum/mysql-5.6-community/el/7/x86_64/ \
    https://repo.mysql.com/yum/mysql-5.7-community/el/7/x86_64/ \
    https://repo.mysql.com/yum/mysql-8.0-community/el/7/x86_64/ \
    | sed -rne 's/^.*HREF="mysql-community-server-([0-9].*)\.el.\.x86_64\.rpm".*$/\1/p' \
    | sort -t. -k 1,1n -k 2,2n -k 3,3n \
    > .version-info/mysql.el7.txt
  curl -s \
    https://repo.mysql.com/yum/mysql-8.0-community/el/8/x86_64/ \
    | sed -rne 's/^.*HREF="mysql-community-server-([0-9].*)\.el.\.x86_64\.rpm".*$/\1/p' \
    | sort -t. -k 1,1n -k 2,2n -k 3,3n \
    > .version-info/mysql.el8.txt

  curl -sL https://repo.mysql.com/apt/ubuntu/pool/mysql-5.6/m/mysql-community/ https://repo.mysql.com/apt/ubuntu/pool/mysql-5.7/m/mysql-community/ https://repo.mysql.com/apt/ubuntu/pool/mysql-8.0/m/mysql-community/ > .version-info/mysql-ubuntu-versions.txt
  sed -rne 's/^.*HREF="mysql-community-server_([0-9].*)ubuntu18.04_amd64\.deb.*$/\1/p' .version-info/mysql-ubuntu-versions.txt | sort -t. -k 1,1n -k 2,2n -k 3,3n > .version-info/mysql.bionic.txt
  sed -rne 's/^.*HREF="mysql-community-server_([0-9].*)ubuntu20.04_amd64\.deb.*$/\1/p' .version-info/mysql-ubuntu-versions.txt | sort -t. -k 1,1n -k 2,2n -k 3,3n > .version-info/mysql.focal.txt
  rm .version-info/mysql-ubuntu-versions.txt

  curl -sL https://repo.mysql.com/apt/debian/pool/mysql-5.6/m/mysql-community/ https://repo.mysql.com/apt/debian/pool/mysql-5.7/m/mysql-community/ https://repo.mysql.com/apt/debian/pool/mysql-8.0/m/mysql-community/|egrep -i 'mysql-server_.*(debian9|debian10)_amd64.deb' > .version-info/mysql-debian-versions.txt
  grep debian9 .version-info/mysql-debian-versions.txt|sed -re 's,^.*A HREF="mysql-server_([^"]+)debian.*$,\1,' | egrep -v 'rc|dmr' > .version-info/mysql.stretch.txt
  grep debian10 .version-info/mysql-debian-versions.txt|sed -re 's,^.*A HREF="mysql-server_([^"]+)debian.*$,\1,' | egrep -v 'rc|dmr' > .version-info/mysql.buster.txt
  rm .version-info/mysql-debian-versions.txt

  curl -s \
    https://repo.mysql.com/yum/mysql-cluster-7.5-community/el/7/x86_64/ \
    https://repo.mysql.com/yum/mysql-cluster-7.6-community/el/7/x86_64/ \
    https://repo.mysql.com/yum/mysql-cluster-8.0-community/el/7/x86_64/ \
    | grep mysql-cluster-community-server | grep -v debuginfo \
    | sed -re 's/^.*HREF="mysql-cluster-community-server-(.[-.0-9]+).el.*/\1/i' \
    | sort -t. -k 1,1n -k 2,2n -k 3,3n \
    > .version-info/mysql_ndb.el7.txt


if test -f /usr/bin/which && which jq &>/dev/null ; then
  curl -s 'https://hub.docker.com/v2/repositories/percona/pmm-server/tags/?page_size=10000' \
    | jq -r '.results|.[]|.name'|egrep '[0-9]*\.[0-9]*\.[0-9]*' \
    | sort -t. -k 1,1n -k 2,2n -k 3,3n \
    > .version-info/pmm-server.txt
else
  cat > .version-info/pmm-server.txt <<EOF
1.17.1
1.17.2
1.17.3
1.17.4
2.0.0
2.0.1
2.1.0
2.2.0
2.2.1
2.2.2
2.3.0
2.4.0
2.5.0
2.6.0
2.6.1
2.8.0
2.9.1
2.10.0
2.10.1
2.11.0
2.11.1
2.12.0
2.13.0
2.14.0
2.15.0
2.15.1
EOF
fi

  curl -sL https://repo.percona.com/percona/yum/release/7/RPMS/x86_64/ \
    | perl -ne '/percona-toolkit-([0-9.-]*).el7.x86_64.rpm/ and print "$1\n"' | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/percona-toolkit.el7.txt
  curl -sL https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/ \
    | perl -ne '/percona-toolkit-([0-9.-]*).el8.x86_64.rpm/ and print "$1\n"' | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/percona-toolkit.el8.txt
  curl -sL https://repo.percona.com/pt/apt/pool/main/p/percona-toolkit/ \
    | perl -ne  '/percona-toolkit_([^"]*).focal_amd64.deb/ and print "$1\n"' | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/percona-toolkit.focal.txt

  curl -sL https://repo.percona.com/percona/yum/release/7/RPMS/x86_64/     | perl -ne '/pmm2?-client-([0-9.-]*).el7.x86_64.rpm/ and print "$1\n"' | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/pmm-client.el7.txt
  curl -sL https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/     | perl -ne '/pmm2?-client-([0-9.-]*).el8.x86_64.rpm/ and print "$1\n"' | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/pmm-client.el8.txt

  cat > .version-info/ppg.el7.txt <<EOF
12.2-4
12.3-1
12.4-2
12.5-1
12.6-1
12.7-1
12.8-1
12.9-2
13.0-1
13.1-1
13.2-2
13.3-2
13.4-1
13.5-1
13.5-2
EOF
  cp .version-info/ppg.el7.txt .version-info/ppg.el8.txt
  cat > .version-info/ppg2.el8.txt <<EOF
13.0-1 221-1
13.1-1 223-1
13.2-2 223-1
13.3-2 226-1
13.4-1 226-2
13.5-1 230-1
13.5-2 230-2
EOF

  cat > .version-info/ppg.focal.txt <<EOF
13-1.1
13-2.2
13-3.2
13-4.1
13.5-2
EOF
  cat > .version-info/ppg2.focal.txt <<EOF
13-1.1 223-1
13-2.2 225-1
13-3.2 226-1
13-4.1 226-3
13.5-2 230-2
EOF

curl -sL https://download.postgresql.org/pub/repos/yum/9.5/redhat/rhel-7-x86_64/ https://download.postgresql.org/pub/repos/yum/9.6/redhat/rhel-7-x86_64/ https://download.postgresql.org/pub/repos/yum/10/redhat/rhel-7-x86_64/ https://download.postgresql.org/pub/repos/yum/11/redhat/rhel-7-x86_64/ https://download.postgresql.org/pub/repos/yum/12/redhat/rhel-7-x86_64/ https://download.postgresql.org/pub/repos/yum/13/redhat/rhel-7-x86_64/ https://download.postgresql.org/pub/repos/yum/14/redhat/rhel-7-x86_64/ |sed -nre 's/^.*href="postgresql[0-9.]+-server-(.*)PGDG.*.rpm".*$/\1/p' | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/pg.el7.txt
curl -sL https://download.postgresql.org/pub/repos/yum/9.6/redhat/rhel-8-x86_64/ https://download.postgresql.org/pub/repos/yum/10/redhat/rhel-8-x86_64/ https://download.postgresql.org/pub/repos/yum/11/redhat/rhel-8-x86_64/ https://download.postgresql.org/pub/repos/yum/12/redhat/rhel-8-x86_64/ https://download.postgresql.org/pub/repos/yum/13/redhat/rhel-8-x86_64/ https://download.postgresql.org/pub/repos/yum/14/redhat/rhel-8-x86_64/ |sed -nre 's/^.*href="postgresql[0-9.]+-server-(.*)PGDG.*.rpm".*$/\1/p' | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/pg.el8.txt


# curl -s https://apt-archive.postgresql.org/pub/repos/apt/dists/focal-pgdg-archive/main/binary-amd64/Packages.bz2 | bzcat
  cat > .version-info/pg.focal.txt <<EOF
13.0-1.pgdg20.04+1
13.1-1.pgdg20.04+1
13.2-1.pgdg20.04+1
13.3-1.pgdg20.04+1
13.4-1.pgdg20.04+1
13.4-4.pgdg20.04+1
13.5-1.pgdg20.04+1
13.5-2.pgdg20.04+1
EOF
  cat > .version-info/pg2.focal.txt <<EOF
13.0-1.pgdg20.04+1 220.pgdg20.04+1
13.1-1.pgdg20.04+1 225.pgdg20.04+1
13.2-1.pgdg20.04+1 225.pgdg20.04+1
13.3-1.pgdg20.04+1 226.pgdg20.04+1
13.4-1.pgdg20.04+1 226.pgdg20.04+1
13.4-4.pgdg20.04+1 226.pgdg20.04+1
13.5-1.pgdg20.04+1 226.pgdg20.04+1
13.5-2.pgdg20.04+1 226.pgdg20.04+1
EOF
  cat > .version-info/pko4psmdb.txt <<EOF
master
main
0.1.0
0.2.0
0.2.1
0.3.0
1.0.0
1.1.0
1.2.0
1.3.0
1.4.0
1.5.0
1.6.0
1.7.0
1.8.0
1.9.0
1.10.0
1.11.0
1.12.0
1.13.0
EOF
  cat > .version-info/pko4ps.txt <<EOF
main
0.1.0
0.2.0
EOF
  cat > .version-info/pko4pxc.txt <<EOF
master
main
0.1.0
0.2.0
0.3.0
1.0.0
1.1.0
1.2.0
1.3.0
1.4.0
1.5.0
1.6.0
1.7.0
1.8.0
1.9.0
1.10.0
1.11.0
EOF
  cat > .version-info/percona_postgres_op.txt << EOF
master
main
0.1.0
0.2.0
1.0.0
1.1.0
1.2.0
1.3.0
EOF
  cat > .version-info/zalando_pg.txt <<EOF
1.0.0
1.1.0
1.2.0
1.3.0
1.3.1
1.4.0
1.5.0
1.6.0
1.6.1
1.6.2
1.6.3
1.7.0
1.7.1
EOF

  cat > .version-info/vites.txt <<EOF
10.0.2
EOF

  cat > .version-info/pgpool.el7.txt <<EOF
4.2.0-1
4.2.1-1
4.2.2-1
EOF
  cat > .version-info/odyssey.el8.txt <<EOF
1.1
EOF
  cat > .version-info/walg.el7.txt <<EOF
0.2.15
0.2.16
0.2.19
EOF
  cat > .version-info/sysbench.el7.txt <<EOF
1.0.20-6
EOF
  cp .version-info/sysbench.el7.txt .version-info/sysbench.el8.txt
  cp .version-info/sysbench.el7.txt .version-info/sysbench.focal.txt

 cat > .version-info/proxysql.el7.txt <<EOF
1.3.10-1
EOF

  curl -sL \
    https://repo.proxysql.com/ProxySQL/proxysql-1.4.x/centos/7/ \
    https://repo.proxysql.com/ProxySQL/proxysql-2.0.x/centos/7/ \
    https://repo.proxysql.com/ProxySQL/proxysql-2.1.x/centos/7/ \
    | perl -ne '/proxysql-([0-9.-]*).centos7.x86_64.rpm/ and print "$1\n"' \
    | sort -n -t . -k1,1 -k2,2 -k3,3 \
    >> .version-info/proxysql.el7.txt
  curl -sL \
    https://repo.proxysql.com/ProxySQL/proxysql-1.4.x/centos/8/ \
    https://repo.proxysql.com/ProxySQL/proxysql-2.0.x/centos/8/ \
    https://repo.proxysql.com/ProxySQL/proxysql-2.1.x/centos/8/ \
    | perl -ne '/proxysql-([0-9.-]*).centos8.x86_64.rpm/ and print "$1\n"' \
    | sort -n -t . -k1,1 -k2,2 -k3,3 \
    > .version-info/proxysql.el8.txt
  curl -sL \
    https://repo.proxysql.com/ProxySQL/proxysql-2.0.x/focal/ \
    https://repo.proxysql.com/ProxySQL/proxysql-2.1.x/focal/ \
    | perl -ne '/proxysql_([0-9.-]*)-ubuntu20_amd64.deb/ and print "$1\n"' \
    | sort -n -t . -k1,1 -k2,2 -k3,3 \
    > .version-info/proxysql.focal.txt


  curl -sL https://api.github.com/repos/maxbube/mydumper/releases|sed -nr -e 's/^.*name.*mydumper-(.*)\.el7\.x86_64\.rpm.*$/\1/p' | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/mydumper.el7.txt
  curl -sL https://api.github.com/repos/maxbube/mydumper/releases|sed -nr -e 's/^.*name.*mydumper-(.*)\.el8\.x86_64\.rpm.*$/\1/p' | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/mydumper.el8.txt

 cat > .version-info/mydumper.focal.txt <<EOF
10.1-2
EOF

 cat > .version-info/mysql-jdbc.txt <<EOF
8.0.17-1
8.0.18-1
8.0.19-1
8.0.20-1
8.0.21-1
8.0.22-1
8.0.23-1
EOF


 cat > .version-info/percona-orchestrator.el7.txt <<EOF
3.2.6-6
EOF
cp .version-info/percona-orchestrator.el7.txt .version-info/percona-orchestrator.el8.txt
cp .version-info/percona-orchestrator.el7.txt .version-info/percona-orchestrator.el9.txt

for osver in 7 8 9 ; do
 curl -sL https://repo.percona.com/pdps-8.0/yum/release/$osver/RPMS/x86_64/ \
    | perl -ne  '/percona-orchestrator-(\d[^"]*).el'$osver'.x86_64.rpm/ and print "$1\n"' | sort -n -t . -k1,1 -k2,2 -k3,3 > .version-info/percona-orchestrator.el$osver.txt
done


 cat > .version-info/orchestrator.el7.txt <<EOF
3.0.3-1
3.0.5-1
3.0.6-1
3.0.7-1
3.0.8-1
3.0.9-1
3.0.10-1
3.0.11-1
3.0.12-1
3.0.13-1
3.0.14-1
3.1.0-1
3.1.2-1
3.1.3-1
3.1.4-1
3.2.2-1
3.2.3-1
3.2.4-1
EOF
 cat .version-info/orchestrator.el7.txt > .version-info/orchestrator.el8.txt
 sed -e 's/-1//' .version-info/orchestrator.el7.txt > .version-info/orchestrator.focal.txt
 sed -e 's/-1//' .version-info/orchestrator.el7.txt > .version-info/orchestrator.bionic.txt

  curl -sL https://repo.percona.com/pbm/yum/release/7/RPMS/x86_64/ \
    | perl -ne '/percona-backup-mongodb-([^"]*).el7.x86_64.rpm/ and print "$1\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 > .version-info/pbm.el7.txt
  curl -sL https://repo.percona.com/pbm/yum/release/7/RPMS/x86_64/ \
    | perl -ne '/percona-backup-mongodb-([^"]*).el8.x86_64.rpm/ and print "$1\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 > .version-info/pbm.el8.txt


  curl -sL https://repo.percona.com/percona/yum/release/7/RPMS/x86_64/ \
    | perl -ne '/Percona-Server-MongoDB(-\d\d)?-server-([^"]*).el7.x86_64.rpm/ and print "$2\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 > .version-info/psmdb.el7.txt
  curl -sL https://repo.percona.com/psmdb-40/yum/release/7/RPMS/x86_64/ \
    | perl -ne '/percona-server-mongodb(-\d\d)?-server-([^"]*).el7.x86_64.rpm/ and print "$2\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 >> .version-info/psmdb.el7.txt
  curl -sL https://repo.percona.com/pdmdb-4.2/yum/release/7/RPMS/x86_64/ \
    | perl -ne '/percona-server-mongodb(-\d\d)?-server-([^"]*).el7.x86_64.rpm/ and print "$2\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 >> .version-info/psmdb.el7.txt
  curl -sL https://repo.percona.com/pdmdb-4.4/yum/release/7/RPMS/x86_64/ \
    | perl -ne '/percona-server-mongodb(-\d\d)?-server-([^"]*).el7.x86_64.rpm/ and print "$2\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 >> .version-info/psmdb.el7.txt
  curl -sL https://repo.percona.com/pdmdb-5.0/yum/release/7/RPMS/x86_64/ https://repo.percona.com/pdmdb-5.0/yum/testing/7/RPMS/x86_64/ \
    | perl -ne '/percona-server-mongodb(-\d\d)?-server-([^"]*).el7.x86_64.rpm/ and print "$2\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 >> .version-info/psmdb.el7.txt
# el8
  curl -sL https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/ \
    | perl -ne '/Percona-Server-MongoDB(-\d\d)?-server-([^"]*).el8.x86_64.rpm/ and print "$2\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 > .version-info/psmdb.el8.txt
  curl -sL https://repo.percona.com/psmdb-40/yum/release/8/RPMS/x86_64/ \
    | perl -ne '/percona-server-mongodb(-\d\d)?-server-([^"]*).el8.x86_64.rpm/ and print "$2\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 >> .version-info/psmdb.el8.txt
  curl -sL https://repo.percona.com/pdmdb-4.2/yum/release/8/RPMS/x86_64/ \
    | perl -ne '/percona-server-mongodb(-\d\d)?-server-([^"]*).el8.x86_64.rpm/ and print "$2\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 >> .version-info/psmdb.el8.txt
  curl -sL https://repo.percona.com/pdmdb-4.4/yum/release/8/RPMS/x86_64/ \
    | perl -ne '/percona-server-mongodb(-\d\d)?-server-([^"]*).el8.x86_64.rpm/ and print "$2\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 >> .version-info/psmdb.el8.txt

  cat > .version-info/psmdb.stretch.txt <<EOF
3.6.21-11.0
3.6.22-12.0
4.0.22-17
4.0.23-18
4.2.11-12
4.2.12-13
4.4.0-1
4.4.1-2
4.4.1-3
4.4.2-4
4.4.3-5
4.4.4-6
EOF

curl -sL https://repo.mongodb.org/yum/redhat/7/mongodb-org/3.0/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/3.1/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/3.2/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/3.3/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/3.4/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/3.5/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/3.6/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/3.7/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/4.0/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/4.1/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/4.2/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/4.3/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/4.4/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/7/mongodb-org/5.0/x86_64/RPMS/ | perl -ne '/mongodb-org-server-([^>]*).el7.x86_64.rpm/ and print "$1\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 > .version-info/mongo-org.el7.txt
curl -sL https://repo.mongodb.org/yum/redhat/8/mongodb-org/3.0/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/3.1/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/3.2/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/3.3/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/3.4/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/3.5/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/3.6/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/3.7/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/4.0/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/4.1/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/4.2/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/4.3/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/4.4/x86_64/RPMS/ https://repo.mongodb.org/yum/redhat/8/mongodb-org/5.0/x86_64/RPMS/ | perl -ne '/mongodb-org-server-([^>]*).el8.x86_64.rpm/ and print "$1\n"'|sort -n --field-separator=. -k 1,1 -k 2,2 -k 3,3 > .version-info/mongo-org.el8.txt

cat > .version-info/vault.txt <<EOF
1.6.1
EOF

  for i in .version-info/*.el7.txt ; do cp $i ${i/.el7.txt/.oel7.txt} ; done
  for i in .version-info/*.el8.txt ; do cp $i ${i/.el8.txt/.oel8.txt} ; cp $i ${i/.el8.txt/.rocky8.txt} ; done

}


if [ "x$1" = "xupdate" ] ; then
  refresh_percona_server_version_info
  exit 0
fi


join_ws()  { local IFS=; local s="${*/#/$1}"; echo "${s#"$1$1$1"}"; }


check_os() {
  if [[ $i == "os:"* ]] || [[ $i == "operating-system:"* ]] ; then
    NODE_OS=$(get_version "$i")
    case "$NODE_OS" in
      el7)
        NODE_OS=el7
        ;;
      centos7)
        NODE_OS=el7
        ;;
      centos-7)
        NODE_OS=el7
        ;;
      CentOS7)
        NODE_OS=el7
        ;;
      CentOS-7)
        NODE_OS=el7
        ;;
      el8)
        NODE_OS=el8
        ;;
      centos8)
        NODE_OS=el8
        ;;
      centos-8)
        NODE_OS=el8
        ;;
      CentOS8)
        NODE_OS=el8
        ;;
      CentOS-8)
        NODE_OS=el8
        ;;
      focal)
        NODE_OS=focal
  ;;
      *)
        :
    esac
    DEP_ENV="$DEP_ENV NODE_OS=$NODE_OS"
 fi
}

deploy_node() {
  [ -f .version-info/percona-server.el7.txt ] || refresh_percona_server_version_info
  NODE="$1"
  DEP_ENV=""
  shift
  arr=("$@")
  ROW_REPLICATION=0
  UTF8ENC=0
  NODE_OS="${NODE_OS:-el7}"
  FEATURES=()
  SAMPLE_DB=()

  for i in "${arr[@]}"; do check_os; done

  for i in "${arr[@]}";
  do
    if [[ $i == "hostname:"* ]] || [[ $i == "hn:"* ]] || [[ $i == "name:"* ]] ; then
      HOST=$(get_version "$i")
      DEP_ENV="$DEP_ENV HOSTNAME=$HOST"
    fi

    if [[ $i == "virtual-machine" ]] ; then
      DEP_ENV="$DEP_ENV NODE_VM=1"
    fi
    if [[ $i == "mem:"* || $i == "memory:"* ]] ; then
      MEMORY=$(get_version "$i")
      DEP_ENV="$DEP_ENV NODE_MEM=$MEMORY"
    fi
    if [[ $i == "cpu:"* ]] ; then
      CPU=$(get_version "$i")
      DEP_ENV="$DEP_ENV NODE_CPU=$CPU"
    fi
    if [[ $i == "parallel" ]] ; then
      DEP_ENV="$DEP_ENV PARALLEL=1"
    fi

    if [[ $i == "cache:"* ]] ; then
      CACHE_IMG=$(get_version "$i")
      DEP_ENV="$DEP_ENV CACHE_IMG=${CACHE_IMG} "
    fi

    if [[ $i == "percona-server" ]] || [[ $i == "percona-server:"* ]] || [[ $i == "ps" ]] || [[ $i == "ps:"* ]] ; then
      search_for_latest_version percona-server "$i"
      DEP_ENV="$DEP_ENV PS=$VER"
    fi
    if [[ $i == "mysql" ]] || [[ $i == "mysql:"* ]] ; then
      search_for_latest_version mysql "$i"
      DEP_ENV="$DEP_ENV MYSQL=$VER"
    fi
    if [[ $i == "mysql-ndb-sql" ]] || [[ $i == "mysql-ndb-sql:"* ]] ; then
      search_for_latest_version mysql_ndb "$i"
      DEP_ENV="$DEP_ENV MYSQL_NDB_SQL=$VER"
    fi
    if [[ $i == "mysql-ndb-data" ]] || [[ $i == "mysql-ndb-data:"* ]] ; then
      search_for_latest_version mysql_ndb "$i"
      DEP_ENV="$DEP_ENV MYSQL_NDB_DATA=$VER"
    fi
    if [[ $i == "mysql-ndb-management" ]] || [[ $i == "mysql-ndb-management:"* ]] ; then
      search_for_latest_version mysql_ndb "$i"
      DEP_ENV="$DEP_ENV MYSQL_NDB_MANAGEMENT=$VER"
    fi
    if [[ $i == "mysql-router" ]] || [[ $i == "mysql-router:"* ]] ; then
      search_for_latest_version mysql "$i"
      DEP_ENV="$DEP_ENV MYSQL_ROUTER=$VER"
    fi
    if [[ $i == "sysbench" ]] || [[ $i == "sysbench:"* ]] ; then
      search_for_latest_version sysbench "$i"
      DEP_ENV="$DEP_ENV SYSBENCH=$VER"
    fi
    if [[ $i == "proxysql" ]] || [[ $i == "proxysql:"* ]] ; then
      search_for_latest_version proxysql "$i"
      DEP_ENV="$DEP_ENV PROXYSQL=$VER"
    fi
    if [[ $i == "pgpool" ]] || [[ $i == "pgpool:"* ]] ; then
      search_for_latest_version pgpool "$i"
      DEP_ENV="$DEP_ENV PGPOOL=$VER"
    fi
    if [[ $i == "pg_stat_monitor" ]] || [[ $i == "pg_stat_monitor:"* ]] ; then
      DEP_ENV="$DEP_ENV PG_STAT_MONITOR=1"
    fi
    if [[ $i == "pgbackrest" ]] || [[ $i == "pgbackrest:"* ]] ; then
      #search_for_latest_version pgbackrest "$i"
      VER=1
      DEP_ENV="$DEP_ENV PGBACKREST=$VER"
    fi
    if [[ $i == "odyssey" ]] || [[ $i == "odyssey:"* ]] ; then
      search_for_latest_version odyssey "$i"
      DEP_ENV="$DEP_ENV ODYSSEY=$VER"
    fi
    if [[ $i == "wal-g" ]] || [[ $i == "wal-g:"* ]] ; then
      search_for_latest_version walg "$i"
      DEP_ENV="$DEP_ENV WALG=$VER"
    fi
    if [[ $i == "minio-ip" ]] || [[ $i == "minio-ip:"* ]] ; then
      MINIO_HOST=$(get_version "$i")
      DEP_ENV="$DEP_ENV MINIO_URL=$MINIO_HOST"
    fi

    if [[ $i == "xtrabackup" ]] || [[ $i == "xtrabackup:"* ]] || [[ $i == "percona-xtrabackup" ]] || [[ $i == "percona-xtrabackup:"* ]] || [[ $i == "pxb" ]] || [[ $i == "pxb:"* ]] ; then
      search_for_latest_version xtrabackup "$i"
      DEP_ENV="$DEP_ENV PXB=$VER"
    fi
    if [[ $i == "haproxy" ]] ; then
      DEP_ENV="$DEP_ENV HAPROXY=1"
    fi
    if [[ $i == "debug" ]] ; then
      DEP_ENV="$DEP_ENV DEBUG_PACKAGES=1"
    fi
    if [[ $i == "docker" ]] ; then
      DEP_ENV="$DEP_ENV DOCKER=1"
    fi
    if [[ $i == "rocksdb" ]] ; then
      DEP_ENV="$DEP_ENV ROCKSDB=1"
    fi
    if [[ $i == "tests" ]] ; then
      DEP_ENV="$DEP_ENV TESTS=1"
    fi
    if [[ $i == "mariabackup" ]] ; then
      DEP_ENV="$DEP_ENV MARIABACKUP=1"
    fi
    if [[ $i == "anydbver" ]] ; then
      DEP_ENV="$DEP_ENV ANYDBVER=1"
    fi
    if [[ $i == "podman" ]] ; then
      DEP_ENV="$DEP_ENV PODMAN=1"
    fi
    if [[ $i == "docker-registry" ]] ; then
      DEP_ENV="$DEP_ENV DOCKER_REGISTRY=1"
    fi
    if [[ $i == "perf" ]] ; then
      DEP_ENV="$DEP_ENV PERF=1"
    fi
    if [[ $i == "haproxy-galera:"* ]] ; then
      HAPROXY_HOSTS=$(get_version "$i")
      DEP_ENV="$DEP_ENV HAPROXY_GALERA=$HAPROXY_HOSTS"
    fi
    if [[ $i == "haproxy-postgresql:"* || $i == "haproxy-pg:"* ]] ; then
      HAPROXY_HOSTS=$(get_version "$i")
      DEP_ENV="$DEP_ENV HAPROXY_PG=$HAPROXY_HOSTS"
    fi

    if [[ $i == "percona-proxysql" ]] || [[ $i == "percona-proxysql:"* ]] ; then
      search_for_latest_version percona-proxysql "$i"
      DEP_ENV="$DEP_ENV PERCONA_PROXYSQL=$VER"
    fi
    if [[ $i == "mydumper" ]] || [[ $i == "mydumper:"* ]] ; then
      search_for_latest_version mydumper "$i"
      DEP_ENV="$DEP_ENV MYDUMPER=$VER"
    fi
    if [[ $i == "mysql-jdbc:"* || $i == "mysql-jdbc" ]] ; then
      if [[ $i == *':'* || $i == *'='* ]] ; then
        VER=$(get_version "$i")
        VER=$(grep "^$VER" .version-info/mysql-jdbc.txt |tail -n 1)
      else
        VER=$(tail -n 1 .version-info/mysql-jdbc.txt)
      fi
      DEP_ENV="$DEP_ENV MYSQL_JAVA=$VER"
    fi
    if [[ $i == "mysql.net" ]] ; then
      VER="8.0.30"
      DEP_ENV="$DEP_ENV MYSQL_DOTNET=$VER"
    fi
    if [[ $i == "percona-toolkit" ]] || [[ $i == "percona-toolkit:"* ]] ; then
      search_for_latest_version percona-toolkit "$i"
      DEP_ENV="$DEP_ENV PT=$VER"
    fi
    if [[ $i == "orchestrator" ]] || [[ $i == "orchestrator:"* ]] ; then
      search_for_latest_version orchestrator "$i"
      DEP_ENV="$DEP_ENV ORCHESTRATOR=$VER"
    fi
    if [[ $i == "percona-orchestrator" ]] || [[ $i == "percona-orchestrator:"* ]] ; then
      search_for_latest_version percona-orchestrator "$i"
      DEP_ENV="$DEP_ENV PERCONA_ORCHESTRATOR=$VER"
    fi
    if [[ $i == "percona-xtradb-cluster" ]] || [[ $i == "percona-xtradb-cluster:"* ]] || [[ $i == "pxc" ]] || [[ $i == "pxc:"* ]] ; then
      search_for_latest_version percona-xtradb-cluster "$i"
      DEP_ENV="$DEP_ENV PXC=$VER "
    fi
    if [[ $i == "psmdb" ]] || [[ $i == "psmdb:"* ]] || [[ $i == "mongo" ]] || [[ $i == "mongo:"* ]] ; then
      search_for_latest_version psmdb "$i"
      DEP_ENV="$DEP_ENV PSMDB=$VER DB_USER=dba DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf"
    fi
    if [[ $i == "pbm" ]] || [[ $i == "pbm:"* ]] || [[ $i == "percona-backup-mongodb" ]] || [[ $i == "percona-backup-mongodb:"* ]] ; then
      search_for_latest_version pbm "$i"
      DEP_ENV="$DEP_ENV PBM=$VER "
    fi
    if [[ $i == "mongo-community" ]] || [[ $i == "mongo-community:"* ]] ; then
      search_for_latest_version mongo-org "$i"
      DEP_ENV="$DEP_ENV MONGO_ORG=$VER DB_USER=dba DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf"
    fi

    if [[ $i == "mongos-cfg:"* ]] ; then
      MONGOS_CFG=$(get_version "$i")
      DEP_ENV="$DEP_ENV MONGOS_CFG=$MONGOS_CFG "
    fi
    if [[ $i == "mongos-shard:"* ]] ; then
      MONGOS_SHARD=$(get_version "$i")
      DEP_ENV="$DEP_ENV MONGOS_SHARD=$MONGOS_SHARD "
    fi

    if [[ $i == "mariadb" ]] || [[ $i == "mariadb:"* ]] || [[ $i == "maria" ]] || [[ $i == "maria:"* ]] ; then
      search_for_latest_version mariadb "$i"
      DEP_ENV="$DEP_ENV MARIADB=$VER"
    fi
    if [[ $i == "mariadb-galera" ]] || [[ $i == "mariadb-galera:"* ]] || [[ $i == "mariadb-cluster" ]] || [[ $i == "mariadb-cluster:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VER=$(get_version "$i")
        VER=$(grep "$VER" .version-info/mariadb.${NODE_OS}.txt |tail -n 1)
        GALERA_VER=$(get_2nd_version "$i")
        if [ "x$GALERA_VER" == "x" ] ; then
          GALERA_VER=$(grep "$VER" .version-info/mariadb-galera.${NODE_OS}.txt|cut -d' ' -f2|tail -n 1 )
        else
          GALERA_VER=$(grep "$GALERA_VER" .version-info/mariadb-galera.${NODE_OS}.txt|cut -d' ' -f2|tail -n 1 )
        fi

        DEP_ENV="$DEP_ENV MARIADB=$VER GALERA=$GALERA_VER "
      else
        VER=$(tail -n 1 .version-info/mariadb.${NODE_OS}.txt)
        GALERA_VER=$(grep "$VER" .version-info/mariadb-galera.${NODE_OS}.txt|cut -d' ' -f2|tail -n 1 )
        DEP_ENV="$DEP_ENV MARIADB=$VER GALERA=$GALERA_VER "
      fi
    fi
    if [[ $i == "postgresql" ]] || [[ $i == "postgresql:"* ]] || [[ $i == "pg" ]] || [[ $i == "pg:"* ]] ; then
      search_for_latest_version pg "$i"
      test -f .version-info/pg2.${NODE_OS}.txt && PG_VER2=$(grep "$VER" .version-info/pg2.${NODE_OS}.txt|cut -d' ' -f2|tail -n 1 )
      if [ "x$PG_VER2" != "x" ] ; then
        DEP_ENV="$DEP_ENV PG=$VER PG2=$PG_VER2"
      else
        DEP_ENV="$DEP_ENV PG=$VER"
      fi
    fi
    if [[ $i == "percona-postgresql" ]] || [[ $i == "percona-postgresql:"* ]] || [[ $i == "ppg" ]] || [[ $i == "ppg:"* ]] ; then
      search_for_latest_version ppg "$i"
      test -f .version-info/ppg2.${NODE_OS}.txt && PPG_VER2=$(grep "$VER" .version-info/ppg2.${NODE_OS}.txt|cut -d' ' -f2|tail -n 1 )
      if [ "x$PPG_VER2" != "x" ] ; then
        DEP_ENV="$DEP_ENV PPGSQL=$VER PPGSQL2=$PPG_VER2"
      else
        DEP_ENV="$DEP_ENV PPGSQL=$VER"
      fi
    fi
    if [[ $i == "k8s-namespace:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VER=$(get_version "$i")
        DEP_ENV="$DEP_ENV K8S_NAMESPACE=$VER"
      fi
    fi

    if [[ $i == "k8s-mongo" ]] || [[ $i == "k8s-mongo:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VER=$(get_version "$i")
        VER=$(grep "$VER" .version-info/pko4psmdb.txt |tail -n 1)
        DEP_ENV="$DEP_ENV PKO4PSMDB=$VER"
      else
        VER=$(tail -n 1 .version-info/pko4psmdb.txt)
        DEP_ENV="$DEP_ENV PKO4PSMDB=$VER"
      fi
    fi
    if [[ $i == "k8s-pxc" ]] || [[ $i == "k8s-pxc:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VER=$(get_version "$i")
        VER=$(grep "$VER" .version-info/pko4pxc.txt |tail -n 1)
        DEP_ENV="$DEP_ENV PKO4PXC=$VER"
      else
        VER=$(tail -n 1 .version-info/pko4pxc.txt)
        DEP_ENV="$DEP_ENV PKO4PXC=$VER"
      fi
    fi
    if [[ $i == "k8s-ps" ]] || [[ $i == "k8s-ps:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VER=$(get_version "$i")
        VER=$(grep "$VER" .version-info/pko4ps.txt |tail -n 1)
        DEP_ENV="$DEP_ENV PKO4PS=$VER"
      else
        VER=$(tail -n 1 .version-info/pko4ps.txt)
        DEP_ENV="$DEP_ENV PKO4PS=$VER"
      fi
    fi
    if [[ $i == "k8s-minio" ]] ; then
        DEP_ENV="$DEP_ENV K8S_MINIO=yes"
    fi
    if [[ $i == "minio" ]] ; then
        DEP_ENV="$DEP_ENV MINIO=yes"
    fi

    if [[ $i == "cert-manager" ]] || [[ $i == "certmanager" ]] ; then
        DEP_ENV="$DEP_ENV CERT_MANAGER=yes"
    fi
    if [[ $i == "k8s-pmm" ]] || [[ $i == "k8s-pmm:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VER=$(get_version "$i")
        VER=$(grep "$VER" .version-info/pmm-server.txt |tail -n 1)
      else
        VER=$(tail -n 1 .version-info/pmm-server.txt)
      fi
      DEP_ENV="$DEP_ENV K8S_PMM=$VER"
    fi
    if [[ $i == "replica-set:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        RSNAME=$(get_version "$i")
      else
        RSNAME="rs0"
      fi
      DEP_ENV="$DEP_ENV REPLICA_SET=$RSNAME"
      test -f secret/"$RSNAME"-keyfile || openssl rand -base64 756 > secret/"$RSNAME"-keyfile
    fi
    if [[ $i == "k8s-pg" ]] || [[ $i == "k8s-pg:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VER=$(get_version "$i")
        VER=$(grep "$VER" .version-info/percona_postgres_op.txt |tail -n 1)
        DEP_ENV="$DEP_ENV K8S_PG=$VER"
      else
        VER=$(tail -n 1   .version-info/percona_postgres_op.txt)
        DEP_ENV="$DEP_ENV K8S_PG=$VER"
      fi
    fi
    if [[ $i == "vites" ]] || [[ $i == "vites:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VER=$(get_version "$i")
        VER=$(grep "$VER" .version-info/vites.txt |tail -n 1)
        DEP_ENV="$DEP_ENV VITES=$VER"
      else
        VER=$(tail -n 1   .version-info/vites.txt)
        DEP_ENV="$DEP_ENV VITES=$VER"
      fi
    fi
    if [[ $i == "k8s-pg-zalando" ]] || [[ $i == "k8s-pg-zalando:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VER=$(get_version "$i")
        VER=$(grep "$VER" .version-info/zalando_pg.txt |tail -n 1)
        DEP_ENV="$DEP_ENV K8S_PG_ZALANDO=$VER"
      else
        VER=$(tail -n 1   .version-info/zalando_pg.txt)
        DEP_ENV="$DEP_ENV K8S_PG_ZALANDO=$VER"
      fi
    fi
    if [[ $i == "channel:"* ]] ; then
      CHANNEL=$(get_version "$i")
      DEP_ENV="$DEP_ENV CHANNEL=$CHANNEL"
    fi
    if [[ $i == "master_ip" ]] || [[ $i == "master_ip:"* ]] || [[ $i == "master" ]] || [[ $i == "master:"* ]] || [[ $i == "leader:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        MASTER_NODE=$(get_version "$i")
        DEP_ENV="$DEP_ENV DB_IP=$MASTER_NODE "
      else
        DEP_ENV="$DEP_ENV DB_IP=default "
      fi
    fi

    if [[ $i == "s3sql:"* ]] ; then
      S3SQL=$(echo "$i" | cut -d: -f2-100)
      DEP_ENV="$DEP_ENV S3SQL=$S3SQL "
    fi

    if [[ $i == "etcd-ip:"* ]] ; then
        ETCD_NODE=$(get_version "$i")
        DEP_ENV="$DEP_ENV ETCD_IP=$ETCD_NODE "
    fi
    if [[ $i == "backend-ip:"* ]] ; then
        BACKEND_NODE=$(get_version "$i")
        DEP_ENV="$DEP_ENV BACKEND_IP=$BACKEND_NODE "
    fi
    if [[ $i == "proxysql-ip:"* ]] ; then
        PROXYSQL_NODE=$(get_version "$i")
        DEP_ENV="$DEP_ENV PROXYSQL_IP=$PROXYSQL_NODE "
    fi

    if [[ $i == "group-replication" ]] ; then
      DEP_ENV="$DEP_ENV REPLICATION_TYPE=group "
    fi
    if [[ $i == "logical:"* ]] ; then
        DB_NAME=$(get_version "$i")
        DEP_ENV="$DEP_ENV PG_LOGICAL_DB=$DB_NAME REPLICATION_TYPE=logical "
    fi

    if [[ $i == "cluster:"* ]] ; then
        CLUSTER_NAME=$(get_version "$i")
        DEP_ENV="$DEP_ENV CLUSTER=$CLUSTER_NAME "
    fi

    if [[ $i == "galera-master" ]] || [[ $i == "galera-master:"* ]] || [[ $i == "galera-leader:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        MASTER_NODE=$(get_version "$i")
        DEP_ENV="$DEP_ENV DB_IP=$MASTER_NODE REPLICATION_TYPE=galera "
      else
        DEP_ENV="$DEP_ENV DB_IP=default REPLICATION_TYPE=galera "
      fi
    fi
    if [[ $i == "samba-ad" ]] || [[ $i == "samba" ]] ; then
        DEP_ENV="$DEP_ENV SAMBA_AD=1 "
    fi
    if [[ $i == "samba-dc:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        MASTER_NODE=$(get_version "$i")
        DEP_ENV="$DEP_ENV SAMBA_IP=$MASTER_NODE SAMBA_PASS=\"verysecretpassword1^\" DB_USER=dba DB_PASS=secret "
      else
        DEP_ENV="$DEP_ENV SAMBA_IP=default "
      fi
    fi
    if [[ $i == "vault" ]] || [[ $i == "vault:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VER=$(get_version "$i")
        VER=$(grep "$VER" .version-info/vault.txt |tail -n 1)
      else
        VER=$(tail -n 1   .version-info/vault.txt)
      fi
      DEP_ENV="$DEP_ENV VAULT=$VER"
    fi

    if [[ $i == "patroni" ]] ; then
      # FEATURES+=( development )
      DEP_ENV="$DEP_ENV PATRONI=1"
    fi
    if [[ $i == "rbr" ]] || [[ $i == "row" ]] || [[ $i == "row-based-replication" ]] || [[ $i == "row_based_replication" ]] ; then
      ROW_REPLICATION=1
    fi
    if [[ $i == "oltp_read_write" ]] ; then
      FEATURES+=( sysbench_oltp_read_write )
    fi
    if [[ $i == "world" ]] ; then
      SAMPLE_DB+=( world )
    fi
    if [[ $i == "sakila" ]] ; then
      SAMPLE_DB+=( sakila )
    fi
    if [[ $i == "pagila" ]] ; then
      SAMPLE_DB+=( pagila )
    fi
    if [[ $i == "employees" ]] ; then
      SAMPLE_DB+=( employees )
    fi

    if [[ $i == "ldap-simple" ]] ; then
      FEATURES+=( ldap_simple )
    fi
    if [[ $i == "clustercheck" ]] ; then
      FEATURES+=( clustercheck )
    fi
    if [[ $i == "backup" ]] ; then
      FEATURES+=( backup )
    fi
    if [[ $i == "pxc57" ]] ; then
      FEATURES+=( pxc57 )
    fi
    if [[ $i == "gtid" ]] ; then
      FEATURES+=( gtid )
    fi
    if [[ $i == "garbd" ]] ; then
      FEATURES+=( garbd )
    fi
    if [[ $i == "development" || $i == "devel" ]] ; then
      FEATURES+=( development )
    fi
    if [[ $i == "master" ]] ; then
      FEATURES+=( master )
    fi
    if [[ $i == "utf8" ]] || [[ $i == "utf8mb3" ]] ; then
      UTF8ENC=1
    fi
    if [[ $i == "install" ]] ; then
      DEP_ENV="$DEP_ENV INSTALL_ONLY=1"
    fi

    if [[ $i == "ndb-data-nodes:"* ]] ; then
      NODES=$(get_version "$i")
      DEP_ENV="$DEP_ENV NDB_DATA_NODES=$NODES"
    fi
    if [[ $i == "ndb-sql-nodes:"* ]] ; then
      NODES=$(get_version "$i")
      DEP_ENV="$DEP_ENV NDB_SQL_NODES=$NODES"
    fi
    if [[ $i == "ndb-connectstring:"* ]] ; then
      MGMT_NODES=$(get_version "$i")
      DEP_ENV="$DEP_ENV NDB_MGMT_NODES=$MGMT_NODES"
    fi


    if [[ $i == "configsrv" ]] ; then
      DEP_ENV="$DEP_ENV MONGO_CONFIGSRV=1"
    fi
    if [[ $i == "shardsrv" ]] ; then
      DEP_ENV="$DEP_ENV MONGO_SHARDSRV=1"
    fi
    if [[ $i == "pbm-agent" ]] ; then
      DEP_ENV="$DEP_ENV PBM_AGENT=1"
    fi

    if [[ $i == "pmm" ]] || [[ $i == "pmm:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VER=$(get_version "$i")
        if [[ $VER == *'/'* ]] ; then
          VER="${i/pmm:/}"
        else
          VER=$(grep "$VER" .version-info/pmm-server.txt |tail -n 1)
        fi
      else
        VER=$(tail -n 1 .version-info/pmm-server.txt)
      fi
      DEP_ENV="$DEP_ENV PMM_SERVER=$VER DB_PASS=verysecretpassword1^"
    fi
    if [[ $i == "pmm-client" ]] || [[ $i == "pmm-client:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VER=$(get_version "$i")
        VER=$(grep "$VER" .version-info/pmm-client.el7.txt |tail -n 1)
      else
        VER=$(tail -n 1 .version-info/pmm-client.el7.txt)
      fi
      DEP_ENV="$DEP_ENV PMM_CLIENT=$VER"
    fi
    if [[ $i == "pmm-server" ]] || [[ $i == "pmm-server:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        PMM_NODE=$(get_version "$i")
      else
        PMM_NODE=default
      fi
      DEP_ENV="$DEP_ENV PMM_URL=$PMM_NODE"
    fi
    if [[ $i == "vault-server" ]] || [[ $i == "vault-server:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        VAULT_NODE=$(get_version "$i")
      else
        VAULT_NODE=default
      fi
      DEP_ENV="$DEP_ENV VAULT_URL=$VAULT_NODE"
    fi
    if [[ $i == "sysbench-pg" ]] || [[ $i == "sysbench-pg:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        SYSBENCH_PG=$(get_version "$i")
      else
        SYSBENCH_PG=default
      fi
      DEP_ENV="$DEP_ENV SYSBENCH_PG=$SYSBENCH_PG"
    fi
    if [[ $i == "sysbench-mysql" ]] || [[ $i == "sysbench-mysql:"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        SYSBENCH_MYSQL=$(get_version "$i")
      else
        SYSBENCH_MYSQL=default
      fi
      DEP_ENV="$DEP_ENV SYSBENCH_MYSQL=$SYSBENCH_MYSQL"
    fi

    if [[ $i == "ldap" ]] || [[ $i == "ldap-server"* ]] ; then
      DEP_ENV="$DEP_ENV LDAP_SERVER=1 DB_USER=dba DB_PASS=secret"
    fi
    if [[ $i == "ldap-master" ]] || [[ $i == "ldap-master"* ]] || [[ $i == "ldap-leader"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        LDAP_NODE=$(get_version "$i")
      else
        LDAP_NODE=default
      fi
      DEP_ENV="$DEP_ENV LDAP_IP=$LDAP_NODE DB_USER=dba DB_PASS=secret"
    fi
    if [[ $i == "k3s-master" ]] || [[ $i == "k3s-master"* ]] || [[ $i == "k3s-leader"* ]] ; then
      if [[ $i == *':'* ]] || [[ $i == *'='* ]] ; then
        MASTER_NODE=$(get_version "$i")
      else
        MASTER_NODE=default
      fi
      DEP_ENV="$DEP_ENV K3S_URL=$MASTER_NODE "
    fi
    if [[ $i == "k3s-registry:"* ]] ; then
      MASTER_NODE=$(get_version "$i")
      DEP_ENV="$DEP_ENV K3S_REGISTRY=$MASTER_NODE "
    fi
    if [[ $i == "k3s" ]] || [[ $i == "k3s:"* ]] || [[ $i == "k8s" ]] || [[ $i == "kubernetes" ]] ; then
      DEP_ENV="$DEP_ENV K3S=latest"
    fi
    if [[ $i == "kubeadm" ]] ; then
      DEP_ENV="$DEP_ENV KUBEADM=latest"
    fi
    if [[ $i == "kubeadm-url:"* ]] ; then
      KUBE_CTRL=$(get_version "$i")
      DEP_ENV="$DEP_ENV KUBEADM_URL=$KUBE_CTRL"
    fi
    if [[ $i == "kube-config:"* ]] ; then
      KUBE_CONFIG=$(get_version "$i")
      DEP_ENV="$DEP_ENV KUBE_CONFIG=$KUBE_CONFIG"
    fi
  done

  if [[ "$DEP_ENV" != *DB_USER* && "$DEP_ENV" == *'PG='* ]] ; then
    DEP_ENV="$DEP_ENV DB_USER=postgres"
  elif [[ "$DEP_ENV" != *DB_USER* ]] ; then
    DEP_ENV="$DEP_ENV DB_USER=root"
  fi
  [[ "$DEP_ENV" == *DB_PASS* ]] || DEP_ENV="$DEP_ENV DB_PASS=verysecretpassword1^"
  [[ "$DEP_ENV" == *START* ]] || DEP_ENV="$DEP_ENV START=1"
  if [[ "$DEP_ENV" != *'HAPROXY_GALERA='* && "$DEP_ENV" == *'GALERA='* ]] || [[ "$DEP_ENV" == *'PXC='* ]] ; then
    [[ "$DEP_ENV" == *CLUSTER=* ]] || DEP_ENV="$DEP_ENV CLUSTER=cluster1"
    CLUSTER_NAME=$(echo "$DEP_ENV" | sed -re 's/^.*CLUSTER=([^ ]+).*$/\1/' )
    test -f secret/${CLUSTER_NAME}-ssl.tar.gz && rm -f secret/${CLUSTER_NAME}-ssl.tar.gz
  fi
  if [[ "$DEP_ENV" == *'PATRONI='* ]] ; then
    [[ "$DEP_ENV" == *CLUSTER=* ]] || DEP_ENV="$DEP_ENV CLUSTER=cluster1"
  fi
  if  [[ "$DEP_ENV" == *DB_OPTS* ]] ; then
    :
  elif [[ "$DEP_ENV" != *'HAPROXY_GALERA='* && "$DEP_ENV" == *'GALERA='* ]] && [[ "$DEP_ENV" == *'MARIADB=10.3'* ]] ; then
    DEP_ENV="$DEP_ENV DB_OPTS=mariadb/galera3.cnf"
  elif [[ "$DEP_ENV" != *'HAPROXY_GALERA='* && "$DEP_ENV" == *'GALERA='* ]] ; then
    DEP_ENV="$DEP_ENV DB_OPTS=mariadb/galera.cnf"
  elif [[ "$DEP_ENV" == *'PXC=5'* ]] ; then
    DEP_ENV="$DEP_ENV DB_OPTS=mysql/pxc5657.cnf"
  elif [[ "$DEP_ENV" == *'PXC=8'* ]] ; then
    DEP_ENV="$DEP_ENV DB_OPTS=mysql/pxc8-repl-gtid.cnf"
  elif [[ "$DEP_ENV" == *'REPLICATION_TYPE=group'* ]] ; then
    DEP_ENV="$DEP_ENV DB_OPTS=mysql/gr.cnf"
  elif [[ "$DEP_ENV" == *'PS='* && $ROW_REPLICATION == 1 ]] ; then
    DEP_ENV="$DEP_ENV DB_OPTS=mysql/async-repl-gtid-row.cnf"
  elif [[ "$DEP_ENV" == *'PS='* && $UTF8ENC == 1 ]] ; then
    DEP_ENV="$DEP_ENV DB_OPTS=mysql/async-repl-gtid-utf8.cnf"
  elif [[ "$DEP_ENV" == *'PS='* || "$DEP_ENV" == *'MYSQL='* ]] ; then
    DEP_ENV="$DEP_ENV DB_OPTS=mysql/async-repl-gtid.cnf"
  elif [[ "$DEP_ENV" == *'MARIADB='* && $ROW_REPLICATION == 1 ]] ; then
    DEP_ENV="$DEP_ENV DB_OPTS=mariadb/async-repl-gtid-row.cnf"
  elif [[ "$DEP_ENV" == *'MARIADB='* ]] ; then
    DEP_ENV="$DEP_ENV DB_OPTS=mariadb/async-repl-gtid.cnf"
  elif [[ "$DEP_ENV" == *'PG=9'* ]] || [[ "$DEP_ENV" == *'PG=10'* ]] || [[ "$DEP_ENV" == *'PG=11'* ]] ; then
    DEP_ENV="$DEP_ENV DB_OPTS=postgresql/logical9.conf"
  elif [[ "$DEP_ENV" == *'PG='* ]] ; then
    DEP_ENV="$DEP_ENV DB_OPTS=postgresql/logical.conf"
  fi

  if [[ ${#FEATURES[@]} != 0 ]] ; then
    DB_FEATURES=$( join_ws , "${FEATURES[@]}" )
    DEP_ENV="$DEP_ENV DB_FEATURES=$DB_FEATURES"
  fi

  if [[ ${#SAMPLE_DB[@]} != 0 ]] ; then
    SAMPLE_DB_LIST=$( join_ws , "${SAMPLE_DB[@]}" )
    DEP_ENV="$DEP_ENV SAMPLE_DB=$SAMPLE_DB_LIST"
  fi

  case "$PROVIDER" in
    vagrant)
      echo "$DEP_ENV vagrant provision $NODE"
      ;;
    lxdock)
      echo "$DEP_ENV lxdock provision $NODE"
      ;;
    podman)
      echo "$DEP_ENV ansible-playbook -i ansible_hosts --limit $USER.$NODE playbook.yml"
      ;;
    lxd)
      echo "$DEP_ENV ansible-playbook -i ${NAMESPACE}ansible_hosts --limit $USER.$NODE $ANSIBLE_VERBOSE playbook.yml"
      ;;
    docker)
      echo "$DEP_ENV ansible-playbook -i ${NAMESPACE}ansible_hosts --limit $USER.$NODE $ANSIBLE_VERBOSE playbook.yml"
      ;;
    existing)
      echo "$DEP_ENV ansible-playbook -i ${NAMESPACE}ansible_hosts --limit $USER.$NODE playbook.yml"
      ;;
    *)
      echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
      exit 1
  esac
}

getip() {
  NODE="$1"
  [ "x$NODE" = "xnode0" ] && NODE=default
  IP="$(sed -ne '/\<'$NODE'\>/ {s/^.*ansible_host=//;s/ .*$//;p}' ${NAMESPACE}ansible_hosts 2>/dev/null | head -n 1)"
  if [ "x$IP" = "x" ] ; then
    IP="$(sed -ne '/\<'$NODE'\>/ {s/ .*$//;p}' configs/${NAMESPACE}hosts 2>/dev/null|head -n 1)"
  fi
}

find_node_ip() {
  NODE="$1"
  [ "x$NODE" = "xnode0" ] && NODE=default
  case "$PROVIDER" in
    vagrant)
      vagrant ssh $NODE -c /vagrant/tools/node_ip.sh 2>/dev/null
      ;;
    lxdock)
      lxdock shell $NODE -c /vagrant/tools/node_ip.sh 2>/dev/null
      ;;
    podman)
      sed -ne '/'$NODE'/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts
      ;;
    lxd)
      ./lxdctl $NAMESPACE_CMD ip $NODE
      ;;
    docker)
      ./lxdctl $NAMESPACE_CMD ip $NODE
      ;;
    existing)
      getip $NODE
      echo $IP
      ;;
    *)
      echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
      exit 1
  esac
}

if [ "x$1" = "xip" ] ; then
  shift
  NODE="$1"
  if [ "x$NODE" = "x" ] || [ "x$NODE" = "xnode0" ] ; then
    NODE=default
  else
    shift
  fi
  find_node_ip "$NODE"
  exit 0
fi


if [ "x$1" = "xmount" ] ; then
  case "$PROVIDER" in
    podman)
      ./podmanctl $NAMESPACE_CMD "$@"
      ;;
    lxd)
      ./lxdctl $NAMESPACE_CMD "$@"
      ;;
    *)
      echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
      exit 1
  esac
  exit 0
fi


find_samba_sid() {
  NODE="$1"
  SAMBA_IP=$(find_node_ip $NODE)
  case "$PROVIDER" in
    podman)
      ssh -i secret/id_rsa root@$SAMBA_IP -o StrictHostKeyChecking=no /opt/samba/bin/wbinfo -D PERCONA|grep SID|awk '{print $3}' 2>/dev/null
      ;;
    lxd)
      ./anydbver $NAMESPACE_CMD ssh $NODE -- /opt/samba/bin/wbinfo -D PERCONA|grep SID|awk '{print $3}' 2>/dev/null
      ;;
    existing)
      ./anydbver $NAMESPACE_CMD ssh $NODE -- /opt/samba/bin/wbinfo -D PERCONA|grep SID|awk '{print $3}' 2>/dev/null
      ;;
    *)
      echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
      exit 1
  esac
}


find_node_token() {
  NODE="$1"
  case "$PROVIDER" in
    lxdock)
      lxdock shell $NODE -c cat /var/lib/rancher/k3s/server/node-token
      ;;
    lxd)
      MASTER_IP=$(find_node_ip $NODE)
      ./anydbver $NAMESPACE_CMD ssh $NODE -- cat /var/lib/rancher/k3s/server/node-token
      ;;
    existing)
      MASTER_IP=$(find_node_ip $NODE)
      ./anydbver $NAMESPACE_CMD ssh $NODE -- cat /var/lib/rancher/k3s/server/node-token
      ;;
    *)
      echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
      exit 1
  esac
}

pre_deploy_hook() {
  i="$i"
  if echo "$i" | grep -q DB_IP ; then
    MASTER_NODE=$(echo "$i" | perl -ne '/DB_IP=(\S*) / and print $1')
    MASTER_IP=$(find_node_ip $MASTER_NODE)
    i=$(echo "$i"|sed -e "s/DB_IP=$MASTER_NODE/DB_IP=$MASTER_IP/g")
  fi
  if echo "$i" | grep -q LDAP_IP ; then
    LDAP_NODE=$(echo "$i" | perl -ne '/LDAP_IP=(\S*) / and print $1')
    LDAP_IP=$(find_node_ip $LDAP_NODE)
    i=$(echo "$i"|sed -e "s/LDAP_IP=$LDAP_NODE/LDAP_IP=$LDAP_IP/g")
  fi
  if echo "$i" | grep -q MINIO_URL ; then
    MINIO_NODE=$(echo "$i" | perl -ne '/MINIO_URL=(\S*) / and print $1')
    #MINIO_URL=$(find_node_ip $MINIO_NODE)
    i=$(echo "$i"|sed -e "s,MINIO_URL=$MINIO_NODE,MINIO_URL=https://$MINIO_NODE:9443,g")
  fi
  if echo "$i" | grep -q SYSBENCH_PG ; then
    SYSBENCH_NODE=$(echo "$i" | perl -ne '/SYSBENCH_PG=(\S*) / and print $1')
    SYSBENCH_PG=$(find_node_ip $SYSBENCH_NODE)
    i=$(echo "$i"|sed -e "s/SYSBENCH_PG=$SYSBENCH_NODE/SYSBENCH_PG=$SYSBENCH_PG/g")
  fi
  if echo "$i" | grep -q SYSBENCH_MYSQL ; then
    SYSBENCH_NODE=$(echo "$i" | perl -ne '/SYSBENCH_MYSQL=(\S*) / and print $1')
    SYSBENCH_MYSQL=$(find_node_ip $SYSBENCH_NODE)
    i=$(echo "$i"|sed -e "s/SYSBENCH_MYSQL=$SYSBENCH_NODE/SYSBENCH_MYSQL=$SYSBENCH_MYSQL/g")
  fi
  if echo "$i" | grep -q ETCD_IP ; then
    ETCD_NODE=$(echo "$i" | perl -ne '/ETCD_IP=(\S*) / and print $1')
    ETCD_IP=$(find_node_ip $ETCD_NODE)
    i=$(echo "$i"|sed -e "s/ETCD_IP=$ETCD_NODE/ETCD_IP=$ETCD_IP/g")
  fi
  if echo "$i" | grep -q BACKEND_IP ; then
    BACKEND_NODE=$(echo "$i" | perl -ne '/BACKEND_IP=(\S*) / and print $1')
    BACKEND_IP=$(find_node_ip $BACKEND_NODE)
    i=$(echo "$i"|sed -e "s/BACKEND_IP=$BACKEND_NODE/BACKEND_IP=$BACKEND_IP/g")
  fi
  if echo "$i" | grep -q PROXYSQL_IP ; then
    PROXYSQL_NODE=$(echo "$i" | perl -ne '/PROXYSQL_IP=(\S*) / and print $1')
    PROXYSQL_IP=$(find_node_ip $PROXYSQL_NODE)
    i=$(echo "$i"|sed -e "s/PROXYSQL_IP=$PROXYSQL_NODE/PROXYSQL_IP=$PROXYSQL_IP/g")
  fi
  if echo "$i" | grep -q K3S_URL ; then
    MASTER_NODE=$(echo "$i" | perl -ne '/K3S_URL=(\S*) / and print $1')
    MASTER_IP=$(find_node_ip $MASTER_NODE)
    MASTER_TOKEN=$(find_node_token $MASTER_NODE)
    i=$(echo "$i"|sed -e "s,K3S_URL=$MASTER_NODE,K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN=$MASTER_TOKEN,g")
  fi
  if echo "$i" | grep -q K3S_REGISTRY ; then
    MASTER_NODE=$(echo "$i" | perl -ne '/K3S_REGISTRY=(\S*) / and print $1')
    MASTER_IP=$(find_node_ip $MASTER_NODE)
    i=$(echo "$i"|sed -e "s,K3S_REGISTRY=$MASTER_NODE,K3S_REGISTRY=\"https://reg:secret@registry.$MASTER_IP.nip.io\",g")
  fi
  if echo "$i" | grep -q PMM_URL ; then
    PMM_NODE=$(echo "$i" | perl -ne '/PMM_URL=(\S*) / and print $1')
    PMM_IP=$(find_node_ip $PMM_NODE)
    i=$(echo "$i"|sed -e "s,PMM_URL=$PMM_NODE,PMM_URL=https://admin:secret@$PMM_IP:443,g")
  fi
  if echo "$i" | grep -q SAMBA_IP ; then
    MASTER_NODE=$(echo "$i" | perl -ne '/SAMBA_IP=(\S*) / and print $1')
    MASTER_IP=$(find_node_ip $MASTER_NODE)
    SAMBA_SID=$(find_samba_sid $MASTER_NODE)
    i=$(echo "$i"|sed -e "s/SAMBA_IP=$MASTER_NODE/SAMBA_IP=$MASTER_IP SAMBA_SID=$SAMBA_SID/g")
  fi
  if echo "$i" | grep -q HAPROXY_PG ; then
    HAPROXY_NODES_LIST=( )
    HAPROXY_NODES=$(echo "$i" | perl -ne '/HAPROXY_PG=(\S*) / and print $1')
    for n in $(echo "$HAPROXY_NODES"|tr , '\n')
    do
      n_ip=$(find_node_ip $n)
      HAPROXY_NODES_LIST+=( ${n_ip} )
    done
    HAPROXY_PG=$( join_ws , "${HAPROXY_NODES_LIST[@]}" )
    i=$(echo "$i"|sed -e "s|HAPROXY_PG=$HAPROXY_NODES|HAPROXY_PG=$HAPROXY_PG|g")
  fi
  if echo "$i" | grep -q HAPROXY_GALERA ; then
    HAPROXY_NODES_LIST=( )
    HAPROXY_NODES=$(echo "$i" | perl -ne '/HAPROXY_GALERA=(\S*) / and print $1')
    for n in $(echo "$HAPROXY_NODES"|tr , '\n')
    do
      n_ip=$(find_node_ip $n)
      HAPROXY_NODES_LIST+=( ${n_ip} )
    done
    HAPROXY_GALERA=$( join_ws , "${HAPROXY_NODES_LIST[@]}" )
    i=$(echo "$i"|sed -e "s|HAPROXY_GALERA=$HAPROXY_NODES|HAPROXY_GALERA=$HAPROXY_GALERA|g")
  fi

  if echo "$i" | grep -q NDB_MGMT_NODES ; then
    NDB_NODES_LIST=( )
    NDB_NODES=$(echo "$i" | perl -ne '/NDB_MGMT_NODES=(\S*) / and print $1')
    for n in $(echo "$NDB_NODES"|tr , '\n')
    do
      n_ip=$(find_node_ip $n)
      NDB_NODES_LIST+=( ${n_ip} )
    done
    NDB_MGMT_NODES=$( join_ws , "${NDB_NODES_LIST[@]}" )
    i=$(echo "$i"|sed -e "s|NDB_MGMT_NODES=$NDB_NODES|NDB_MGMT_NODES=$NDB_MGMT_NODES|g")
  fi
  if echo "$i" | grep -q NDB_SQL_NODES ; then
    NDB_NODES_LIST=( )
    NDB_NODES=$(echo "$i" | perl -ne '/NDB_SQL_NODES=(\S*) / and print $1')
    for n in $(echo "$NDB_NODES"|tr , '\n')
    do
      n_ip=$(find_node_ip $n)
      NDB_NODES_LIST+=( ${n_ip} )
    done
    NDB_SQL_NODES=$( join_ws , "${NDB_NODES_LIST[@]}" )
    i=$(echo "$i"|sed -e "s|NDB_SQL_NODES=$NDB_NODES|NDB_SQL_NODES=$NDB_SQL_NODES|g")
  fi
  if echo "$i" | grep -q NDB_DATA_NODES ; then
    NDB_NODES_LIST=( )
    NDB_NODES=$(echo "$i" | perl -ne '/NDB_DATA_NODES=(\S*) / and print $1')
    for n in $(echo "$NDB_NODES"|tr , '\n')
    do
      n_ip=$(find_node_ip $n)
      NDB_NODES_LIST+=( ${n_ip} )
    done
    NDB_DATA_NODES=$( join_ws , "${NDB_NODES_LIST[@]}" )
    i=$(echo "$i"|sed -e "s|NDB_DATA_NODES=$NDB_NODES|NDB_DATA_NODES=$NDB_DATA_NODES|g")
  fi

  if echo "$i" | grep -q MONGOS_CFG ; then
    CFG_NODES_LIST=( )
    CFG_NODES_FULL=$(echo "$i" | perl -ne '/MONGOS_CFG=(\S*) / and print $1')
    CFG_NODES_RS=$(echo "$i" | perl -ne '/MONGOS_CFG=(\S*)\/(\S*) / and print $1')
    CFG_NODES=$(echo "$i" | perl -ne '/MONGOS_CFG=(\S*)\/(\S*) / and print $2')
    for n in ${CFG_NODES//,/ }
    do
      n_ip=$(find_node_ip $n)
      CFG_NODES_LIST+=( ${n_ip}:27017 )
    done
    MONGOS_CFG=$( join_ws , "${CFG_NODES_LIST[@]}" )
    i=$(echo "$i"|sed -e "s|MONGOS_CFG=$CFG_NODES_FULL|MONGOS_CFG=$CFG_NODES_RS/$MONGOS_CFG|g")
  fi
  if echo "$i" | grep -q MONGOS_SHARD ; then
    SHARD_NODES_FULL=$(echo "$i" | perl -ne '/MONGOS_SHARD=(\S*) / and print $1')
    SHARD_RESOLVED_NODES=''
    FULL_NEW_SEP=$(echo "$SHARD_NODES_FULL"|sed -re 's|,([^/^,]+/)|;\1|g')
    OLDIFS="$IFS"
    IFS=";"

    for SHARD_ITEM in $FULL_NEW_SEP ; do
      SHARD_NODES_LIST=( )
      SHARD_NODES_RS=$(echo "$SHARD_ITEM"|cut -d/ -f 1)
      SHARD_NODES=$(echo "$SHARD_ITEM"|cut -d/ -f 2)
      for n in $(echo "$SHARD_NODES"|tr , ';')
      do
        n_ip=$(find_node_ip $n)
        SHARD_NODES_LIST+=( ${n_ip}:27017 )
      done
      MONGOS_SHARD=$( join_ws , "${SHARD_NODES_LIST[@]}" )
      [ "x$SHARD_RESOLVED_NODES" != "x" ] && SHARD_RESOLVED_NODES="$SHARD_RESOLVED_NODES,"
      SHARD_RESOLVED_NODES="$SHARD_RESOLVED_NODES$SHARD_NODES_RS/$MONGOS_SHARD"
    done

    IFS="$OLDIFS"

    i=$(echo "$i"|sed -e "s|MONGOS_SHARD=$SHARD_NODES_FULL|MONGOS_SHARD=$SHARD_RESOLVED_NODES|g")
  fi

}

post_deploy_hook() {
  i="$i"
  NODE=$(echo "$i" |sed -re 's/^.*--limit .+\.([^.]+)\s+playbook\.yml.*$/\1/')

  # after reploy node actions
  if echo "$i" | grep -q CLUSTER= && echo "$i" | grep -q PXC=8. ; then
    CLUSTER_NAME=$(echo "$i" | sed -re 's/^.*CLUSTER=([^ ]+).*$/\1/' )
    test -f secret/${CLUSTER_NAME}-ssl.tar.gz || ./anydbver ${NAMESPACE_CMD} \
      ssh $NODE tar cz \
        /var/lib/mysql/ca.pem \
        /var/lib/mysql/ca-key.pem \
        /var/lib/mysql/client-cert.pem \
        /var/lib/mysql/client-key.pem \
        /var/lib/mysql/server-cert.pem \
        /var/lib/mysql/server-key.pem > secret/${CLUSTER_NAME}-ssl.tar.gz 2>/dev/null
  fi
  if echo "$i" | grep -q MINIO= ; then
    ./anydbver ${NAMESPACE_CMD} ssh $NODE tar cz /etc/minio/certs 2>/dev/null > secret/minio-certs.tar.gz
  fi

  if echo "$i" | grep -q VAULT= && ! echo "$i"|grep -q INSTALL_ONLY=1 ; then
    ./anydbver ${NAMESPACE_CMD} ssh $NODE tar c /etc/vault.d/ca.crt /root/.vault-token 2>/dev/null > secret/vault-client.tar
  fi
}

post_deploy_hook_after_all_nodes() {
  i="$i"
  NODE=$(echo "$i" |sed -re 's/^.*--limit .+\.([^.]+)\s+playbook\.yml.*$/\1/')

  # after all nodes deploy
  if [[ $i != *PKO4PXC=* && $i != *PKO4PS* && $i == *CLUSTER=* && $i == *PXC=* ]] || [[ $i == *CLUSTER=* && $i == *GALERA=* ]] ; then
    [[ $DRY_RUN == 0 ]] && ./anydbver ssh $NODE -- bash /vagrant/tools/fix_wsrep_cluster_address.sh </dev/null
  fi
}



start_all_nodes() {
  case "$PROVIDER" in
    vagrant)
      ;;
    lxdock)
      ;;
    podman)
      ./podmanctl --destroy
      ./podmanctl --nodes ${#ALL_NODES[@]}
      ;;
    lxd)
      echo "./lxdctl $NAMESPACE_CMD --destroy"
      [[ $DRY_RUN == 0 ]] && ./lxdctl $NAMESPACE_CMD --destroy
      if [[ $PRIV_CONTAINER_REQUIRED == 1 ]] ; then
        echo "./lxdctl $NAMESPACE_CMD --nodes ${#ALL_NODES[@]} --privileged $HOSTNAMES_CMD $OS_CMD $VM_CMD $CACHE_IMG_CMD $NODE_MEM_CMD $NODE_CPU_CMD"
        [[ $DRY_RUN == 0 ]] && ./lxdctl $NAMESPACE_CMD --nodes ${#ALL_NODES[@]} --privileged $HOSTNAMES_CMD $OS_CMD $VM_CMD $CACHE_IMG_CMD $NODE_MEM_CMD $NODE_CPU_CMD
      else
        echo "./lxdctl $NAMESPACE_CMD --nodes ${#ALL_NODES[@]} $HOSTNAMES_CMD $OS_CMD $VM_CMD $CACHE_IMG_CMD $NODE_MEM_CMD $NODE_CPU_CMD"
        [[ $DRY_RUN == 0 ]] && ./lxdctl $NAMESPACE_CMD --nodes ${#ALL_NODES[@]} $HOSTNAMES_CMD $OS_CMD $VM_CMD $CACHE_IMG_CMD $NODE_MEM_CMD $NODE_CPU_CMD
      fi
      ;;
    existing)
      ;;
    docker)
      ./docker_container.py --deploy --destroy  $NAMESPACE_CMD --nodes ${#ALL_NODES[@]}
      ;;
    *)
      echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
      exit 1
  esac
}

start_node() {
  NODE="$1"
  case "$PROVIDER" in
    vagrant)
      ;;
    lxdock)
      ;;
    podman)
      ./podmanctl --destroy
      ./podmanctl --nodes ${#ALL_NODES[@]}
      ;;
    lxd)
      if [[ $PRIV_CONTAINER_REQUIRED == 1 ]] ; then
        echo "./lxdctl $NAMESPACE_CMD --only-node $NODE --nodes ${#ALL_NODES[@]} --privileged $HOSTNAMES_CMD $OS_CMD $VM_CMD $CACHE_IMG_CMD $NODE_MEM_CMD $NODE_CPU_CMD"
        [[ $DRY_RUN == 0 ]] && ./lxdctl $NAMESPACE_CMD --only-node $NODE  --nodes ${#ALL_NODES[@]} --privileged $HOSTNAMES_CMD $OS_CMD $VM_CMD $CACHE_IMG_CMD $NODE_MEM_CMD $NODE_CPU_CMD
      else
        echo "./lxdctl $NAMESPACE_CMD --only-node $NODE --nodes ${#ALL_NODES[@]} $HOSTNAMES_CMD $OS_CMD $VM_CMD $CACHE_IMG_CMD $NODE_MEM_CMD $NODE_CPU_CMD"
        [[ $DRY_RUN == 0 ]] && ./lxdctl $NAMESPACE_CMD --only-node $NODE --nodes ${#ALL_NODES[@]} $HOSTNAMES_CMD $OS_CMD $VM_CMD $CACHE_IMG_CMD $NODE_MEM_CMD $NODE_CPU_CMD
      fi
      ;;
    existing)
      ;;
    *)
      echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
      exit 1
  esac
}

if [ "x$1" = "xdeploy" ] ; then
  PRIV_CONTAINER_REQUIRED=0
  HOSTNAMES_CMD=''
  OS_CMD=''
  VM_CMD=''
  CACHE_IMG_CMD=''
  DEPLARGS=()
  DEPLOY_CMDS=()
  NODE=default
  declare -A ALL_NODES
  ALL_NODES[$NODE]=1
  shift

  if [[ "$1" == "--dry-run" ]] ; then
    DRY_RUN=1
    shift
  fi

  if [[ "$1" == default ]] || [[ "$1" == node0 ]] ; then
    shift
  fi

  while (( "$#" )); do
    while (( "$#" )); do
      if [[ "$1" == node* ]] || [[ "$1" == default && NODE != default ]] ; then
        break
      fi
      DEPLARGS+=("$1")
      shift
    done
    DEPCMD=$(deploy_node $NODE "${DEPLARGS[@]}")
    if [ $? != 0 ] ; then
      exit 1
    fi
    echo "$DEPCMD"|egrep -q 'PMM_SERVER|K8S|K3S|PKO|SAMBA_AD|PERF|DOCKER|PODMAN' && PRIV_CONTAINER_REQUIRED=1
    if [[ "$DEPCMD" == *"HOSTNAME="* ]] ; then
      HOSTNAMES_CMD="$HOSTNAMES_CMD --hostname $NODE="$(echo "$DEPCMD"| sed -re 's/^.*HOSTNAME=([^ ]+) .*/\1/')
    fi
    if [[ "$DEPCMD" == *"CACHE_IMG="* ]] ; then
      CACHE_IMG_CMD="$CACHE_IMG_CMD --cache $NODE="$(echo "$DEPCMD"| sed -re 's/^.*CACHE_IMG=([^ ]+) .*/\1/')
    fi
    if [[ "$DEPCMD" == *"NODE_OS="* ]] ; then
      OS_CMD="$OS_CMD --os $NODE="$(echo "$DEPCMD"| sed -re 's/^.*NODE_OS=([^ ]+) .*/\1/')
    elif [[ "x$NODE_OS" != "x" && $NODE_OS != "el7" ]] ; then
      OS_CMD="$OS_CMD --os $NODE=$NODE_OS"
    fi
    if [[ "$DEPCMD" == *"NODE_VM="* ]] ; then
      VM_CMD="$VM_CMD --vm $NODE"
    fi
    if [[ "$DEPCMD" == *"NODE_MEM="* ]] ; then
      NODE_MEM="$(echo "$DEPCMD"| sed -re 's/^.*NODE_MEM=([^ ]+) .*/\1/')"
      NODE_MEM_CMD="$NODE_MEM_CMD --mem $NODE=$NODE_MEM"
    fi
    if [[ "$DEPCMD" == *"NODE_CPU="* ]] ; then
      NODE_CPU="$(echo "$DEPCMD"| sed -re 's/^.*NODE_CPU=([^ ]+) .*/\1/')"
      NODE_CPU_CMD="$NODE_CPU_CMD --cpu $NODE=$NODE_CPU"
    fi

    DEPLOY_CMDS+=("$DEPCMD")
    ALL_NODES[$NODE]=1
    if [[ "$1" == default ]] || [[ "$1" == node0 ]] ; then
      NODE=default
      shift
    elif [[ "$1" == node* ]] ; then
      NODE="$1"
      shift
    fi

    DEPLARGS=()
  done

  start_all_nodes


  if [[ $SHARED_DIRECTORY == 1 ]] ; then
    for i in "${!ALL_NODES[@]}"; do
      SH_DIR="$PWD/tmp/shared_dir"
      if ! [ -d "$PWD/tmp/shared_dir" ] ; then
        mkdir -p "$SH_DIR"
        chmod ogu+rwX "$SH_DIR"
      fi
      if [[ $DRY_RUN == 0 ]] ; then
        ./anydbver $NAMESPACE_CMD mount "$SH_DIR" $i:/nfs
      else
        echo ./anydbver $NAMESPACE_CMD mount "$SH_DIR" $i:/nfs
      fi
    done
  fi

  for i in "${DEPLOY_CMDS[@]}"; do
    pre_deploy_hook "$i"
    printf "%s\n" "$i"

    CACHE_IMG=$(echo "$i"| sed -re 's/^.*CACHE_IMG=([^ ]+) .*/\1/')
    if [[ "$i" == *CACHE_IMG=* ]] && [ "x$CACHE_IMG" != "x" ] && ./lxdctl $NAMESPACE_CMD --has-cache $CACHE_IMG ; then
      echo "Using existing cache image $CACHE_IMG skipping ansible run"
    elif [[ "$i" == *PARALLEL=1* && $DRY_RUN == 0  ]] ; then
      bash -c "$i" &> $( mktemp deploy.log.XXXXXX ) &
    elif [[ $DRY_RUN == 0 ]] ; then
      wait
      bash -c "$i"
      if [[ "$i" == *CACHE_IMG=* ]] && [ "x$CACHE_IMG" != "x" ] ; then
        NODE=$(echo "$i"| sed -re 's/^.*\.([^.]+)[ ]* playbook.yml/\1/')
        echo "Caching $CACHE_IMG on node $NODE"
        ./lxdctl $NAMESPACE_CMD --snapshot $CACHE_IMG $NODE
      fi
    fi
    post_deploy_hook "$i"
  done
  for i in "${DEPLOY_CMDS[@]}"; do
    post_deploy_hook_after_all_nodes "$i"
  done

  wait
  exit 0
fi

if [ "x$1" = "xadd" ] || [ "x$1" = "xapply" ] || [ "x$1" = "xreplace" ] ; then
  CMD_NAME="$1"
  ADD_CMD=0
  REPLACE_CMD=0

  if [ "x$1" = "xreplace" ] ; then
    ADD_CMD=1
    REPLACE_CMD=1
  fi
  if [ "x$1" = "xadd" ] ; then
    ADD_CMD=1
  fi
  PRIV_CONTAINER_REQUIRED=0
  HOSTNAMES_CMD=''
  OS_CMD=''
  VM_CMD=''
  NODE_MEM_CMD=''
  NODE_CPU_CMD=''
  DEPLARGS=()
  DEPLOY_CMDS=()
  NODE=default
  shift

  if [[ "$1" == default ]] || [[ "$1" == node* ]] ; then
    NODE=$1
    shift
  else
    echo "Please specify node to $CMD_NAME. '$1' should be 'default' or 'nodeN'"
    exit 1
  fi
  declare -A ALL_NODES
  ALL_NODES[$NODE]=1

  while (( "$#" )); do
    if [[ "$1" == node* ]] || [[ "$1" == default && NODE != default ]] ; then
      break
    fi
    DEPLARGS+=("$1")
    shift
  done
  DEPCMD=$(deploy_node $NODE "${DEPLARGS[@]}")
  echo "$DEPCMD"|egrep -q 'PMM_SERVER|K8S|K3S|PKO|SAMBA_AD' && PRIV_CONTAINER_REQUIRED=1
  if [[ "$DEPCMD" == *"HOSTNAME="* ]] ; then
    HOSTNAMES_CMD="$HOSTNAMES_CMD --hostname $NODE="$(echo "$DEPCMD"| sed -re 's/^.*HOSTNAME=([^ ]+) .*/\1/')
  fi
  if [[ "$DEPCMD" == *"NODE_OS="* ]] ; then
    OS_CMD="$OS_CMD --os $NODE="$(echo "$DEPCMD"| sed -re 's/^.*NODE_OS=([^ ]+) .*/\1/')
  fi
  if [[ "$DEPCMD" == *"NODE_VM="* ]] ; then
    VM_CMD="$VM_CMD --vm $NODE"
  fi

  DEPLOY_CMDS+=("$DEPCMD")

  DEPLARGS=()

  if [ $REPLACE_CMD -eq 1 ] ; then
    case "$PROVIDER" in
      podman)
        ./podmanctl --destroy
        ;;
      lxd)
        ./lxdctl $NAMESPACE_CMD --destroy "$NODE"
        ;;
      *)
        echo "Please select VM/Container provider with $0 configure provider:PROVIDERNAME"
        exit 1
    esac
  fi
  if [ $ADD_CMD -eq 1 ] ; then
    start_node "$NODE"
  fi

  for i in "${DEPLOY_CMDS[@]}"; do
    pre_deploy_hook "$i"
    printf "%s\n" "$i"
    [[ $DRY_RUN == 0 ]] && bash -c "$i"
    post_deploy_hook "$i"
  done

  exit 0
fi

if [ "x$1" = "xport" ] ; then
  lxc list
  read -p 'LXC container name: ' lxcname
  read -p 'Host VM port: ' vmport
  read -p 'LXC container port: ' lxcport
  lxc config device add $lxcname $lxcname:$lxcport proxy listen=tcp:0.0.0.0:$vmport connect=tcp:127.0.0.1:$lxcport
  exit 0
fi

print_help
