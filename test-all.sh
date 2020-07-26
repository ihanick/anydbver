#!/bin/bash
DESTROY=${3:-yes}
if [[ "x$2" = "" || "x$2" = "xold_tests" ]] ; then
#export VAGRANT_DEFAULT_PROVIDER=lxc
# export VAGRANT_DEFAULT_PROVIDER=lxd
# export LXD_PROFILE=$USER

# use export PROV=lxd for vagrant-lxd
for psver in "5.6.47-rel87.0.1" "5.7.29-32.1" "8.0.18-9.1"; do
    PS=$psver vagrant up
   vagrant destroy -f || true
done

for pxcver in "5.6.45-28.36.1" "5.7.22-29.26.1" "8.0.18-9.3"; do
    PXC=$pxcver vagrant up
   vagrant destroy -f || true
done

DB_USER=root DB_PASS=secret PS=5.7.29-32.1 vagrant up
vagrant destroy -f || true
DB_USER=root DB_PASS=secret PS=5.6.20-rel68.0 vagrant up
vagrant destroy -f || true
DB_USER=root DB_PASS=secret PS=8.0.19-10.1 vagrant up
vagrant destroy -f || true

DB_USER=root DB_PASS=secret START=1 PXC=5.6.45-28.36.1 PXB=2.3.9-1 DB_OPTS=mysql/async-repl-gtid.cnf vagrant up
vagrant destroy -f || true
# should produce error: DB_USER=root DB_PASS=secret START=1 PXC=5.6.45-28.36.1 PXB=2.4.20-1 DB_OPTS=mysql/async-repl-gtid.cnf vagrant up
vagrant destroy -f || true
DB_USER=root DB_PASS=secret START=1 PXC=5.6.45-28.36.1 DB_OPTS=mysql/async-repl-gtid.cnf vagrant up
vagrant destroy -f || true
DB_USER=root DB_PASS=secret START=1 PXC=5.7.28-31.41.2 DB_OPTS=mysql/async-repl-gtid.cnf vagrant up
vagrant destroy -f || true
DB_USER=root DB_PASS=secret START=1 PXC=8.0.18-9.3     DB_OPTS=mysql/async-repl-gtid.cnf vagrant up
vagrant destroy -f || true

# start and config files
DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1    DB_OPTS=mysql/async-repl-gtid.cnf vagrant up
vagrant destroy -f || true
DB_USER=root DB_PASS=secret START=1 PS=5.7.29-32.1    DB_OPTS=mysql/async-repl-gtid.cnf vagrant up
vagrant destroy -f || true
DB_USER=root DB_PASS=secret START=1 PS=5.6.20-rel68.0 DB_OPTS=mysql/async-repl-gtid.cnf vagrant up
vagrant destroy -f || true
DB_USER=root DB_PASS=secret START=1 PS=5.6.23-rel72.1 DB_OPTS=mysql/async-repl-gtid.cnf vagrant up
vagrant destroy -f || true
 
# Test separate xtrabackup installation
PXB=2.3.9-1 vagrant up;vagrant destroy -f || true
PXB=2.4.14-1 vagrant up;vagrant destroy -f || true
PXB=8.0.10-1 vagrant up;vagrant destroy -f || true

# Test mongodb
PSMDB=3.6.16-3.6 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf vagrant up
vagrant destroy -f || true
PSMDB=4.0.17-10 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf vagrant up
vagrant destroy -f || true
PSMDB=4.2.3-4 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf vagrant up
vagrant destroy -f || true

PBM=1.1.1-1 vagrant up
vagrant destroy -f || true

# PMM client
PMM_CLIENT=1.17.3-1 vagrant up
vagrant destroy -f || true
PMM_CLIENT=2.5.0-6 vagrant up
vagrant destroy -f || true

# PMM server running inside podman (easier to setup compare to docker)
PMM_SERVER=1.17.3 vagrant up
vagrant destroy -f || true
PMM_SERVER=2.5.0 vagrant up
vagrant destroy -f || true

# Postresql
PPGSQL=11.5-1 DB_PASS=secret START=1 vagrant up
vagrant destroy -f || true
PPGSQL=11.6-2 DB_PASS=secret START=1 vagrant up
vagrant destroy -f || true
PPGSQL=11.7-2 DB_PASS=secret START=1 vagrant up
vagrant destroy -f || true
PPGSQL=12.2-4 DB_PASS=secret START=1 vagrant up
vagrant destroy -f || true
PPGSQL=12.2-4 DB_PASS=secret START=1 DB_OPTS=postgresql/novacuum.conf vagrant up
vagrant destroy -f || true

# percona toolkit
PT=3.2.0-1 vagrant up
vagrant destroy -f || true

# Multi-node setup
PXC=8.0.18-9.3 vagrant up
for i in `seq 1 3` ; do PT=3.2.0-1 PXC=8.0.18-9.3 PMM_CLIENT=2.5.0-6 vagrant up node$i ; done
PMM_SERVER=2.5.0 vagrant up node4
for i in default node1 node2 node3 ; do vagrant ssh $i -- 'hostname;/sbin/ip addr ls|grep "inet "|grep -v "inet 127";rpm -qa|grep -i percona|xargs' ; done
vagrant destroy -f || true

# Percona XtraDB Cluster (PXC) Kubernetes, using k3s one-file distribution
PKO4PXC='1.4.0' vagrant up
# cluster creation requires a few minutes
vagrant destroy -f || true

# MongoDB in Kubernetes, using k3s one-file distribution
PKO4PSMDB='1.4.0' vagrant up
# cluster creation requires a few minutes
vagrant destroy -f || true

# PXC + pmm
K3S=latest vagrant up default
K3S_TOKEN=$(vagrant ssh default -- sudo cat /var/lib/rancher/k3s/server/node-token) K3S_URL="https://$( vagrant ssh default -- hostname -I | cut -d' ' -f1):6443" vagrant up node1 node2 node3
K3S=latest PKO4PXC='1.4.0' K8S_PMM=1 DB_PASS=secret vagrant provision default
vagrant destroy -f || true

# MongoDB replicaset
PSMDB=4.0.17-10 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf REPLICA_SET=rs0 vagrant up default
PSMDB=4.0.17-10 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf REPLICA_SET=rs0 DB_IP=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) vagrant up node1 node2
vagrant destroy -f || true

PSMDB=4.2.3-4 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf REPLICA_SET=rs0 vagrant up default
PSMDB=4.2.3-4 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf REPLICA_SET=rs0 DB_IP=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) vagrant up node1 node2
vagrant destroy -f || true

# Ubuntu
OS=ubuntu/bionic64 DB_USER=root DB_PASS=secret START=1 PS=5.6.42-84.2-1    DB_OPTS=mysql/async-repl-gtid.cnf vagrant up
vagrant destroy -f || true

OS=ubuntu/bionic64 DB_USER=root DB_PASS=secret START=1 PS=5.7.25-28-1    DB_OPTS=mysql/async-repl-gtid.cnf vagrant up
vagrant destroy -f || true

OS=ubuntu/bionic64 DB_USER=root DB_PASS=secret START=1 PS=8.0.16-7-1    DB_OPTS=mysql/async-repl-gtid.cnf vagrant up
vagrant destroy -f || true

# OS is not needed for vagrant provision run
OS=ubuntu/bionic64 DB_USER=root DB_PASS=secret START=1 PS=5.6.42-84.2-1 DB_OPTS=mysql/async-repl-gtid.cnf vagrant up default node1 node2
DB_USER=root DB_PASS=secret START=1 PS=5.6.42-84.2-1 DB_IP=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/async-repl-gtid.cnf vagrant provision node1 node2

OS=ubuntu/bionic64 DB_USER=root DB_PASS=secret START=1 PS=5.7.25-28-1 DB_OPTS=mysql/async-repl-gtid.cnf vagrant up default node1 node2
DB_USER=root DB_PASS=secret START=1 PS=5.7.25-28-1 DB_IP=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/async-repl-gtid.cnf vagrant provision node1 node2

OS=ubuntu/bionic64 DB_USER=root DB_PASS=secret START=1 PS=8.0.16-7-1    DB_OPTS=mysql/async-repl-gtid.cnf vagrant up default node1 node2
DB_USER=root DB_PASS=secret START=1 PS=8.0.16-7-1 DB_IP=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/async-repl-gtid.cnf vagrant provision node1 node2
vagrant destroy -f || true

OS=ubuntu/bionic64 DB_USER=root DB_PASS=secret START=1 PXC=8.0.18-9-3     DB_OPTS=mysql/async-repl-gtid.cnf vagrant up default node1 node2
vagrant ssh default -- sudo tar cz /var/lib/mysql/ca.pem /var/lib/mysql/ca-key.pem /var/lib/mysql/client-cert.pem /var/lib/mysql/client-key.pem /var/lib/mysql/server-cert.pem /var/lib/mysql/server-key.pem > secret/pxc-cluster-ssl.tar.gz
DB_USER=root DB_PASS=secret PXC=8.0.18-9-3 REPLICATION_TYPE=galera DB_IP=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/async-repl-gtid.cnf vagrant provision node1
DB_USER=root DB_PASS=secret PXC=8.0.18-9-3 REPLICATION_TYPE=galera DB_IP=$( vagrant ssh default -- hostname -I | cut -d' ' -f1 ) DB_OPTS=mysql/async-repl-gtid.cnf vagrant provision node2
vagrant destroy -f || true


# lxdock
PSMDB=4.2.3-4 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf REPLICA_SET=rs0 lxdock provision default
PSMDB=4.2.3-4 DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf REPLICA_SET=rs0 DB_IP=$( lxdock shell default -c hostname -I | cut -d' ' -f1 ) lxdock provision node1
test $DESTROY = yes && lxdock destroy -f

K3S=latest lxdock provision default


./gen_lxdock.sh anydbver centos/7
PROXYSQL=2.0.12-1 lxdock up default
test $DESTROY = yes && lxdock destroy -f || true

./gen_lxdock.sh anydbver centos/8
PROXYSQL=2.0.12-1 lxdock up default
test $DESTROY = yes && lxdock destroy -f || true

./gen_lxdock.sh anydbver ubuntu/bionic
PROXYSQL=2.0.12 lxdock up default
test $DESTROY = yes && lxdock destroy -f || true



PROXYSQL=2.0.12-1 vagrant up default
vagrant destroy -f || true

OS=centos/8 PROXYSQL=2.0.12-1 vagrant up default
vagrant destroy -f || true

OS=ubuntu/bionic64 PROXYSQL=2.0.12 vagrant provision default
vagrant destroy -f

# MariaDB
MARIADB=10.4.12-1 lxdock provision default
MARIADB=10.4.12-1 DB_USER=root DB_PASS=secret START=1 DB_OPTS=mariadb/async-repl-gtid.cnf lxdock up default


# Vanilla MySQL 8.0
./gen_lxdock.sh anydbver centos/7
MYSQL=8.0.20-1 DB_USER=root DB_PASS=secret START=1 DB_OPTS=mysql/async-repl-gtid.cnf lxdock up default
test $DESTROY = yes && lxdock destroy -f

./gen_lxdock.sh anydbver centos/8
MYSQL=8.0.20-1 DB_USER=root DB_PASS=secret START=1 DB_OPTS=mysql/async-repl-gtid.cnf lxdock up default
test $DESTROY = yes && lxdock destroy -f

./gen_lxdock.sh anydbver centos/7
ROCKSDB=1 DB_USER=root DB_PASS=secret START=1 PS=5.7.29-32.1 DB_OPTS=mysql/async-repl-gtid.cnf lxdock up
test $DESTROY = yes && lxdock destroy -f

./gen_lxdock.sh anydbver centos/7 3
PMM_SERVER=2.5.0 lxdock up node2
PMM_CLIENT=2.5.0-6 PMM_URL="https://admin:admin@$(lxdock shell node2 -c hostname -I |cut -d' ' -f 2):443"  lxdock up default
test $DESTROY = yes && lxdock destroy -f

./gen_lxdock.sh anydbver centos/7 1
DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1    DB_OPTS=mysql/async-repl-gtid.cnf lxdock up default
test $DESTROY = yes && lxdock destroy -f

for MVER in 5.7.29-32.1 8.0.19-10.1 ; do
    ./gen_lxdock.sh anydbver centos/7 2
    DB_USER=root DB_PASS=secret START=1 PS=$MVER DB_OPTS=mysql/async-repl-gtid.cnf lxdock up default
    SYSBENCH=1.0.20-6 lxdock up node1
    lxdock shell node1 -c /vagrant/tools/sysbench_oltp_ro.sh $( lxdock shell default -c hostname -I | cut -d' ' -f1 ) root secret sbtest 2 10000 4 100
    test $DESTROY = yes && lxdock destroy -f
done
# 5.7.29-32.1 queries:                             3281712 (32815.00 per sec.)
# 8.0.19-10.1 queries:                             2575440 (25752.72 per sec.)

# PG physical replication
./gen_lxdock.sh anydbver centos/7 2
PPGSQL=12.2-4 DB_PASS=secret START=1 lxdock up default
PPGSQL=12.2-4 DB_PASS=secret START=1 DB_IP=$( lxdock shell default -c hostname -I | cut -d' ' -f1 ) lxdock up node1


# install https://github.com/Percona-Lab/mysql_random_data_load/
MYSQL_RANDOM_DATA=0.1.12 lxdock up default
test $DESTROY = yes && lxdock destroy -f


# K8S PXC cluster with slave server outside 
./gen_lxdock.sh anydbver centos/7 5

K3S=latest K8S_MINIO=yes lxdock up default
until [ "x" != "x$IP" ]; do
IP=$(lxdock shell default -c hostname -I | cut -d' ' -f3)
sleep 1
done
echo "K8S master IP: $IP"
K3S_TOKEN=$(lxdock shell default -c cat /var/lib/rancher/k3s/server/node-token) K3S_URL="https://$(lxdock shell default -c hostname -I | cut -d' ' -f3):6443" lxdock up node1 node2 node3
# there are dns resolution issues for "too fast start"
sleep 30
K3S=latest PKO4PXC='1.4.0' K8S_PMM=1 DB_FEATURES="gtid,master,backup,pxc57" lxdock provision default
lxdock shell default -c kubectl apply -f /vagrant/configs/k8s/svc-replication-master.yaml
DB_IP=$( lxdock shell default -c bash -c "kubectl get svc cluster1-pxc-0 -o yaml | yq r - 'status.loadBalancer.ingress[0].ip'" ) \
DB_USER=root DB_PASS=root_password START=1 PS=5.7.29-32.1 DB_OPTS=mysql/async-repl-gtid.cnf lxdock up node4

test $DESTROY = yes && lxdock destroy -f

fi # endif old tests

# MySQL Connector Java test
if [[ "x$2" = "" || "x$2" = "xmysql_connector_java" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
  ./gen_lxdock.sh anydbver centos/7 2
  DB_USER=root DB_PASS=secret START=1 PS=5.7.29-32.1 DB_OPTS=mysql/async-repl-gtid.cnf lxdock up default
  DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) DB_PASS=secret DB_USER=root MYSQL_JAVA=8.0.17-1 lxdock up node1
  lxdock shell node1 -c bash -c 'cd /srv/java && sudo javac ConnectorTest.java && java -classpath "./:/usr/share/java/mysql-connector-java.jar:/usr/share/java/" ConnectorTest'
  test $DESTROY = yes && lxdock destroy -f
  else
  DB_USER=root DB_PASS=secret START=1 PS=5.7.29-32.1 DB_OPTS=mysql/async-repl-gtid.cnf vagrant up default
  DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) DB_PASS=secret DB_USER=root MYSQL_JAVA=8.0.17-1 vagrant up node1
  vagrant ssh node1 -c bash -c 'cd /srv/java && sudo javac ConnectorTest.java && java -classpath "./:/usr/share/java/mysql-connector-java.jar:/usr/share/java/" ConnectorTest'
  vagrant destroy -f
  fi
fi

# innodb_ruby
if [[ "x$2" = "" || "x$2" = "xinnodb_ruby" ]] ; then
if [[ "x$1" = "xlxdock" ]] ; then
./gen_lxdock.sh anydbver centos/7 1
DB_USER=root DB_PASS=root_password START=1 PS=5.7.29-32.1 INNODB_RUBY=1 lxdock up default
lxdock shell default -c innodb_space --help
test $DESTROY = yes && lxdock destroy -f
else
:
fi
fi

# InnoDB Cluster
if [[ "x$2" = "" || "x$2" = "xinnodb_cluster" ]] ; then
if [[ "x$1" = "xlxdock" ]] ; then
./gen_lxdock.sh anydbver centos/7 3
DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1 REPLICATION_TYPE=group CLUSTER=cluster1 DB_OPTS=mysql/gr.cnf lxdock up default
DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1 REPLICATION_TYPE=group CLUSTER=cluster1 DB_OPTS=mysql/gr.cnf lxdock up node1
DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1 REPLICATION_TYPE=group CLUSTER=cluster1 DB_OPTS=mysql/gr.cnf lxdock up node2
test $DESTROY = yes && lxdock destroy -f
else
DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1 REPLICATION_TYPE=group CLUSTER=cluster1 DB_OPTS=mysql/gr.cnf vagrant up default
DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1 REPLICATION_TYPE=group CLUSTER=cluster1 DB_OPTS=mysql/gr.cnf vagrant up node1
DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1 REPLICATION_TYPE=group CLUSTER=cluster1 DB_OPTS=mysql/gr.cnf vagrant up node2
vagrant destroy -f || true
fi
fi

# InnoDB cluster MySQL Community
if [[ "x$2" = "" || "x$2" = "xmysql_innodb_cluster" ]] ; then
if [[ "x$1" = "xlxdock" ]] ; then
./gen_lxdock.sh anydbver centos/7 3
DB_USER=root DB_PASS=secret START=1 MYSQL=8.0.20-1 REPLICATION_TYPE=group CLUSTER=cluster1 DB_OPTS=mysql/gr.cnf lxdock up default
DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
DB_USER=root DB_PASS=secret START=1 MYSQL=8.0.20-1 REPLICATION_TYPE=group CLUSTER=cluster1 DB_OPTS=mysql/gr.cnf lxdock up node1
DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
DB_USER=root DB_PASS=secret START=1 MYSQL=8.0.20-1 REPLICATION_TYPE=group CLUSTER=cluster1 DB_OPTS=mysql/gr.cnf lxdock up node2
test $DESTROY = yes && lxdock destroy -f
else
DB_USER=root DB_PASS=secret START=1 MYSQL=8.0.20-1 REPLICATION_TYPE=group CLUSTER=cluster1 DB_OPTS=mysql/gr.cnf vagrant up default
DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
DB_USER=root DB_PASS=secret START=1 MYSQL=8.0.20-1 REPLICATION_TYPE=group CLUSTER=cluster1 DB_OPTS=mysql/gr.cnf vagrant up node1
DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
DB_USER=root DB_PASS=secret START=1 MYSQL=8.0.20-1 REPLICATION_TYPE=group CLUSTER=cluster1 DB_OPTS=mysql/gr.cnf vagrant up node2
vagrant destroy -f || true
fi
fi

# PXC
if [[ "x$2" = "" || "x$2" = "xpxc56" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 3
    DB_USER=root DB_PASS=secret START=1 PXC=5.6.45-28.36.1 CLUSTER=pxc-cluster DB_OPTS=mysql/pxc5657.cnf lxdock up default node1 node2
    DB_USER=root DB_PASS=secret PXC=5.6.45-28.36.1 CLUSTER=pxc-cluster REPLICATION_TYPE=galera DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) DB_OPTS=mysql/pxc5657.cnf lxdock provision node1
    DB_USER=root DB_PASS=secret PXC=5.6.45-28.36.1 CLUSTER=pxc-cluster REPLICATION_TYPE=galera DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) DB_OPTS=mysql/pxc5657.cnf lxdock provision node2
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh
    DB_USER=root DB_PASS=secret START=1 PXC=5.6.45-28.36.1 CLUSTER=pxc-cluster DB_OPTS=mysql/pxc5657.cnf \
      ansible-playbook -i ansible_hosts playbook.yml
    DB_USER=root DB_PASS=secret PXC=5.6.45-28.36.1 CLUSTER=pxc-cluster REPLICATION_TYPE=galera \
    DB_IP=$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      DB_OPTS=mysql/pxc5657.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.node1 playbook.yml
    DB_USER=root DB_PASS=secret PXC=5.6.45-28.36.1 CLUSTER=pxc-cluster REPLICATION_TYPE=galera \
    DB_IP=$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      DB_OPTS=mysql/pxc5657.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.node2 playbook.yml
    test $DESTROY = yes && sudo podman rm -f $USER.default $USER.node1 $USER.node2
  else
    DB_USER=root DB_PASS=secret START=1 PXC=5.6.45-28.36.1 CLUSTER=pxc-cluster DB_OPTS=mysql/pxc5657.cnf \
      vagrant up default node1 node2
    DB_USER=root DB_PASS=secret PXC=5.6.45-28.36.1 CLUSTER=pxc-cluster REPLICATION_TYPE=galera \
      DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) DB_OPTS=mysql/pxc5657.cnf vagrant provision node1
    DB_USER=root DB_PASS=secret PXC=5.6.45-28.36.1 CLUSTER=pxc-cluster REPLICATION_TYPE=galera \
      DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) DB_OPTS=mysql/pxc5657.cnf vagrant provision node2
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi

if [[ "x$2" = "" || "x$2" = "xpxc57" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 3
    DB_USER=root DB_PASS=secret START=1 PXC=5.7.28-31.41.2 CLUSTER=pxc-cluster DB_OPTS=mysql/pxc5657.cnf \
      lxdock up default node1 node2
    DB_USER=root DB_PASS=secret PXC=5.7.28-31.41.2 CLUSTER=pxc-cluster REPLICATION_TYPE=galera \
      DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_OPTS=mysql/pxc5657.cnf \
      lxdock provision node1
    DB_USER=root DB_PASS=secret PXC=5.7.28-31.41.2 CLUSTER=pxc-cluster REPLICATION_TYPE=galera \
      DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) DB_OPTS=mysql/pxc5657.cnf lxdock provision node2
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh
    DB_USER=root DB_PASS=secret START=1 PXC=5.7.28-31.41.2 CLUSTER=pxc-cluster DB_OPTS=mysql/pxc5657.cnf \
      ansible-playbook -i ansible_hosts playbook.yml
    DB_USER=root DB_PASS=secret PXC=5.7.28-31.41.2 CLUSTER=pxc-cluster REPLICATION_TYPE=galera \
    DB_IP=$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      DB_OPTS=mysql/pxc5657.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.node1 playbook.yml
    DB_USER=root DB_PASS=secret PXC=5.7.28-31.41.2 CLUSTER=pxc-cluster REPLICATION_TYPE=galera \
    DB_IP=$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      DB_OPTS=mysql/pxc5657.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.node2 playbook.yml
    test $DESTROY = yes && sudo podman rm -f $USER.default $USER.node1 $USER.node2
  else
    DB_USER=root DB_PASS=secret START=1 PXC=5.7.28-31.41.2 CLUSTER=pxc-cluster DB_OPTS=mysql/pxc5657.cnf \
      vagrant up default node1 node2
    DB_USER=root DB_PASS=secret PXC=5.7.28-31.41.2 CLUSTER=pxc-cluster REPLICATION_TYPE=galera \
      DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_OPTS=mysql/pxc5657.cnf \
      vagrant provision node1
    DB_USER=root DB_PASS=secret PXC=5.7.28-31.41.2 CLUSTER=pxc-cluster REPLICATION_TYPE=galera DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) DB_OPTS=mysql/pxc5657.cnf vagrant provision node2
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi

if [[ "x$2" = "" || "x$2" = "xpxc8" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 3
    DB_USER=root DB_PASS=secret START=1 PXC=8.0.18-9.3 CLUSTER=pxc-cluster DB_OPTS=mysql/pxc8-repl-gtid.cnf lxdock up default node1 node2
    lxdock shell default -c tar cz /var/lib/mysql/ca.pem /var/lib/mysql/ca-key.pem /var/lib/mysql/client-cert.pem /var/lib/mysql/client-key.pem /var/lib/mysql/server-cert.pem /var/lib/mysql/server-key.pem > secret/pxc-cluster-ssl.tar.gz
    DB_USER=root DB_PASS=secret PXC=8.0.18-9.3 REPLICATION_TYPE=galera CLUSTER=pxc-cluster \
      DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_OPTS=mysql/pxc8-repl-gtid.cnf \
      lxdock provision node1
    DB_USER=root DB_PASS=secret PXC=8.0.18-9.3 REPLICATION_TYPE=galera CLUSTER=pxc-cluster \
      DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_OPTS=mysql/pxc8-repl-gtid.cnf \
      lxdock provision node2
     test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh
    DB_USER=root DB_PASS=secret START=1 PXC=8.0.18-9.3 CLUSTER=pxc-cluster DB_OPTS=mysql/pxc8-repl-gtid.cnf \
      ansible-playbook -i ansible_hosts playbook.yml
    sudo podman exec -i $USER.default tar cz /var/lib/mysql/ca.pem /var/lib/mysql/ca-key.pem /var/lib/mysql/client-cert.pem /var/lib/mysql/client-key.pem /var/lib/mysql/server-cert.pem /var/lib/mysql/server-key.pem > secret/pxc-cluster-ssl.tar.gz
    DB_USER=root DB_PASS=secret PXC=8.0.18-9.3 REPLICATION_TYPE=galera CLUSTER=pxc-cluster \
      DB_IP=$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      DB_OPTS=mysql/pxc8-repl-gtid.cnf \
      SYNC=1 \
      ansible-playbook -i ansible_hosts --limit $USER.node1 playbook.yml
    DB_USER=root DB_PASS=secret PXC=8.0.18-9.3 REPLICATION_TYPE=galera CLUSTER=pxc-cluster \
      DB_IP=$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      DB_OPTS=mysql/pxc8-repl-gtid.cnf \
      SYNC=1 \
      ansible-playbook -i ansible_hosts --limit $USER.node2 playbook.yml
    test $DESTROY = yes && sudo podman rm -f $USER.default $USER.node1 $USER.node2
  else
    DB_USER=root DB_PASS=secret START=1 PXC=8.0.18-9.3 CLUSTER=pxc-cluster DB_OPTS=mysql/pxc8-repl-gtid.cnf vagrant up default node1 node2
    vagrant ssh default -- sudo tar cz /var/lib/mysql/ca.pem /var/lib/mysql/ca-key.pem /var/lib/mysql/client-cert.pem /var/lib/mysql/client-key.pem /var/lib/mysql/server-cert.pem /var/lib/mysql/server-key.pem > secret/pxc-cluster-ssl.tar.gz
    DB_USER=root DB_PASS=secret PXC=8.0.18-9.3 REPLICATION_TYPE=galera CLUSTER=pxc-cluster DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) DB_OPTS=mysql/pxc8-repl-gtid.cnf vagrant provision node1
    DB_USER=root DB_PASS=secret PXC=8.0.18-9.3 REPLICATION_TYPE=galera CLUSTER=pxc-cluster DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) DB_OPTS=mysql/pxc8-repl-gtid.cnf vagrant provision node2
    vagrant destroy -f || true
  fi
fi

# Postgresql 12 with PGPool-II
if [[ "x$2" = "" || "x$2" = "xpgpool" ]] ; then
if [[ "x$1" = "xlxdock" ]] ; then
./gen_lxdock.sh anydbver centos/7 3
PPGSQL=12.2-4 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 lxdock up default
PPGSQL=12.2-4 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) lxdock up node1
PGPOOL=4.1.2-1 PPGSQL=12.2-4 DB_PASS=secret START=1 DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) lxdock up node2
test $DESTROY = yes && lxdock destroy -f
else
PPGSQL=12.2-4 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 vagrant up default
PPGSQL=12.2-4 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) vagrant up node1
PGPOOL=4.1.2-1 PPGSQL=12.2-4 DB_PASS=secret START=1 DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) vagrant up node2
fi
fi

# Postgresql 12 with PMM
if [[ "x$2" = "" || "x$2" = "xpgpmm" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 3
    PMM_SERVER=2.8.0 DB_PASS=secret lxdock up node2
    PPGSQL=12.3-1 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 PMM_CLIENT=2.8.0-6 PMM_URL="https://admin:secret@$(lxdock shell node2 -c /vagrant/tools/node_ip.sh 2>/dev/null):443"  lxdock up default
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh --pmm 2.8.0
    PMM_URL="https://admin:admin@"$(sudo podman inspect $USER.pmm-server |grep IPAddress|awk '{print $2}'|sed -e 's/[",]//g')":443" \
    PPGSQL=12.3-1 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 PMM_CLIENT=2.8.0-6 \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    test $DESTROY = yes && sudo podman rm -f $USER.default $USER.node1 $USER.pmm-server
  else
    PMM_SERVER=2.8.0 DB_PASS=secret vagrant up node2
    PPGSQL=12.3-1 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 PMM_CLIENT=2.8.0-6 PMM_URL="https://admin:secret@$(vagrant ssh node2 -c /vagrant/tools/node_ip.sh 2>/dev/null):443"  vagrant up default
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi

# LDAP
if [[ "x$2" = "" || "x$2" = "xpgldap" ]] ; then
if [[ "x$1" = "xlxdock" ]] ; then
./gen_lxdock.sh anydbver centos/7 3
DB_USER=dba DB_PASS=secret LDAP_SERVER=1 DB_PASS=secret lxdock up node2
LDAP_IP=$(lxdock shell node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
  PPGSQL=12.3-1 DB_USER=dba DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
  lxdock up default
test $DESTROY = yes && lxdock destroy -f
elif [[ "x$1" = "xpodman" ]] ; then
./start_podman.sh
LDAP_SERVER=1 DB_USER=dba DB_PASS=secret ansible-playbook -i ansible_hosts --limit $USER.node2 playbook.yml
LDAP_IP=$(grep $USER.node2 ansible_hosts |sed -ne '/node2/ {s/^.*ansible_host=//;s/ .*$//;p}') \
  PPGSQL=12.3-1 DB_USER=dba DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
  ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
# check: ldapsearch -x cn=dba -b dc=percona,dc=local
test $DESTROY = yes && sudo podman rm -f $USER.default $USER.node1 $USER.node2
else
LDAP_SERVER=1 DB_USER=dba DB_PASS=secret vagrant up node2
LDAP_IP=$(vagrant ssh node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
  PPGSQL=12.3-1 DB_USER=dba DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
  vagrant up default
test $DESTROY = yes && vagrant destroy -f || true
fi
fi

if [[ "x$2" = "" || "x$2" = "xmongoldap" ]] ; then
if [[ "x$1" = "xlxdock" ]] ; then
./gen_lxdock.sh anydbver centos/7 3
DB_USER=dba DB_PASS=secret LDAP_SERVER=1 DB_PASS=secret lxdock up node2
LDAP_IP=$(lxdock shell node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
  PSMDB=4.2.3-4 DB_USER=dba DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf \
  lxdock up default
test $DESTROY = yes && lxdock destroy -f
elif [[ "x$1" = "xpodman" ]] ; then
./start_podman.sh
LDAP_SERVER=1 DB_USER=dba DB_PASS=secret ansible-playbook -i ansible_hosts --limit $USER.node2 playbook.yml
LDAP_IP=$(grep $USER.node2 ansible_hosts |sed -ne '/node2/ {s/^.*ansible_host=//;s/ .*$//;p}') \
  PSMDB=4.2.3-4 DB_USER=dba DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf \
  ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
# check: ldapsearch -x cn=dba -b dc=percona,dc=local
test $DESTROY = yes && sudo podman rm -f $USER.default $USER.node1 $USER.node2
else
LDAP_SERVER=1 DB_USER=dba DB_PASS=secret vagrant up node2
LDAP_IP=$(vagrant ssh node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
  PSMDB=4.2.3-4 DB_USER=dba DB_PASS=secret START=1 DB_OPTS=mongo/enable_wt.conf \
  vagrant up default
test $DESTROY = yes && vagrant destroy -f || true
fi
fi


if [[ "x$2" = "" || "x$2" = "xpsldap" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 3
    DB_USER=dba DB_PASS=secret LDAP_SERVER=1 DB_PASS=secret lxdock up node2
    LDAP_IP=$(lxdock shell node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1    DB_OPTS=mysql/async-repl-gtid.cnf \
      lxdock up default
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh
    LDAP_SERVER=1 DB_USER=dba DB_PASS=secret ansible-playbook -i ansible_hosts --limit $USER.node2 playbook.yml
    LDAP_IP=$(grep $USER.node2 ansible_hosts |sed -ne '/node2/ {s/^.*ansible_host=//;s/ .*$//;p}') \
      DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1    DB_OPTS=mysql/async-repl-gtid.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    # check: ldapsearch -x cn=dba -b dc=percona,dc=local
    test $DESTROY = yes && sudo podman rm -f $USER.default $USER.node1 $USER.node2
  else
    LDAP_SERVER=1 DB_USER=dba DB_PASS=secret vagrant up node2
    LDAP_IP=$(vagrant ssh node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1    DB_OPTS=mysql/async-repl-gtid.cnf \
      vagrant up default
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi



# multi-node k8s cluster
if [[ "x$2" = "" || "x$2" = "xk8spmmminio" ]] ; then
if [[ "x$1" = "xlxdock" ]] ; then
K3S=latest K8S_MINIO=yes lxdock up default
K3S_TOKEN=$(lxdock shell default -c cat /var/lib/rancher/k3s/server/node-token) K3S_URL="https://$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null):6443" lxdock up node1 node2
K3S=latest PKO4PXC='1.4.0' K8S_PMM=1 DB_FEATURES="gtid,master,backup" lxdock provision default
test $DESTROY = yes && lxdock destroy -f
else
K3S=latest K8S_MINIO=yes vagrant up default
K3S_TOKEN=$(vagrant ssh default -- cat /var/lib/rancher/k3s/server/node-token) K3S_URL="https://$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null):6443" vagrant up node1 node2
K3S=latest PKO4PXC='1.4.0' K8S_PMM=1 DB_FEATURES="gtid,master,backup" vagrant provision default
test $DESTROY = yes && vagrant destroy -f || true
fi
fi

# Standalone MySQL
if [[ "x$2" = "" || "x$2" = "xps57" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 1
    DB_USER=root DB_PASS=secret START=1 PS=5.7.30-33.1 \
      DB_OPTS=mysql/async-repl-gtid.cnf \
      lxdock up default
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh --nodes 1
    DB_USER=root DB_PASS=secret START=1 PS=5.7.30-33.1 \
      DB_OPTS=mysql/async-repl-gtid.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    DB_USER=root DB_PASS=secret START=1 PS=5.7.30-33.1 \
      DB_OPTS=mysql/async-repl-gtid.cnf \
      vagrant up default
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi



# MySQL Async replication
if [[ "x$2" = "" || "x$2" = "xps56arep" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    DB_USER=root DB_PASS=secret START=1 PS=5.6.23-rel72.1 \
      DB_OPTS=mysql/async-repl-gtid.cnf lxdock up default node1 node2
    DB_USER=root DB_PASS=secret START=1 PS=5.6.23-rel72.1 \
      DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_OPTS=mysql/async-repl-gtid.cnf lxdock provision node1 node2
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh
    DB_USER=root DB_PASS=secret START=1 PS=5.6.23-rel72.1 \
      DB_OPTS=mysql/async-repl-gtid.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    DB_USER=root DB_PASS=secret START=1 PS=5.6.23-rel72.1 \
    DB_IP=$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      DB_OPTS=mysql/async-repl-gtid.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.node1 playbook.yml
    test $DESTROY = yes && sudo podman rm -f $USER.default $USER.node1 $USER.node2
  else
    DB_USER=root DB_PASS=secret START=1 PS=5.6.23-rel72.1    DB_OPTS=mysql/async-repl-gtid.cnf vagrant up default node1 node2
    DB_USER=root DB_PASS=secret START=1 PS=5.6.23-rel72.1 \
      DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_OPTS=mysql/async-repl-gtid.cnf vagrant provision node1 node2
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi

if [[ "x$2" = "" || "x$2" = "xps57arep" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    DB_USER=root DB_PASS=secret START=1 PS=5.7.29-32.1 \
      DB_OPTS=mysql/async-repl-gtid.cnf lxdock up default node1 node2
    DB_USER=root DB_PASS=secret START=1 PS=5.7.29-32.1 \
      DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_OPTS=mysql/async-repl-gtid.cnf lxdock provision node1 node2
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh
    DB_USER=root DB_PASS=secret START=1 PS=5.7.29-32.1 \
      DB_OPTS=mysql/async-repl-gtid.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    DB_USER=root DB_PASS=secret START=1 PS=5.7.29-32.1 \
    DB_IP=$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      DB_OPTS=mysql/async-repl-gtid.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.node1 playbook.yml
    test $DESTROY = yes && sudo podman rm -f $USER.default $USER.node1 $USER.node2
  else
    DB_USER=root DB_PASS=secret START=1 PS=5.7.29-32.1    DB_OPTS=mysql/async-repl-gtid.cnf vagrant up default node1 node2
    DB_USER=root DB_PASS=secret START=1 PS=5.7.29-32.1 \
      DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_OPTS=mysql/async-repl-gtid.cnf vagrant provision node1 node2
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi
if [[ "x$2" = "" || "x$2" = "xps80arep" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 3
    DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1 \
      DB_OPTS=mysql/async-repl-gtid.cnf lxdock up default node1 node2
    DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1 \
      DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_OPTS=mysql/async-repl-gtid.cnf lxdock provision node1 node2
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh
    DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1 \
      DB_OPTS=mysql/async-repl-gtid.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1 \
    DB_IP=$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      DB_OPTS=mysql/async-repl-gtid.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.node1 playbook.yml
    test $DESTROY = yes && sudo podman rm -f $USER.default $USER.node1 $USER.node2
  else
    DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1    DB_OPTS=mysql/async-repl-gtid.cnf vagrant up default node1 node2
    DB_USER=root DB_PASS=secret START=1 PS=8.0.19-10.1 \
      DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_OPTS=mysql/async-repl-gtid.cnf vagrant provision node1 node2
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi


if [[ "x$2" = "" || "x$2" = "xmydumper" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7
    MYDUMPER=0.9.5-2 lxdock up default
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh
    MYDUMPER=0.9.5-2 \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    MYDUMPER=0.9.5-2 vagrant up default
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi

# Postgresql 12 with PGPool-II and sybench
if [[ "x$2" = "" || "x$2" = "xpgpoolsysbench" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 3
    PPGSQL=12.2-4 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
      lxdock up default
    SYSBENCH=1.0.20-6 lxdock up node1
    PGPOOL=4.1.2-1 PPGSQL=12.2-4 DB_PASS=secret START=1 \
      DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      lxdock up node2
	  lxdock shell node1 -c \
      /bin/bash /vagrant/tools/sysbench_pg_oltp_ro.sh \
        $(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
        postgres secret postgres 2 10000 4 100
    echo "benchmarking with pgpool"
    lxdock shell node1 -c \
      /bin/bash /vagrant/tools/sysbench_pg_oltp_ro.sh \
        $(lxdock shell node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
        postgres secret postgres 2 10000 4 100
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh
    PPGSQL=12.2-4 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    SYSBENCH=1.0.20-6 \
      ansible-playbook -i ansible_hosts --limit $USER.node1 playbook.yml
    PGPOOL=4.1.2-1 PPGSQL=12.2-4 DB_PASS=secret START=1 \
      DB_IP=$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      ansible-playbook -i ansible_hosts --limit $USER.node2 playbook.yml
    ansible -i ansible_hosts $USER.node1 -a "/bin/bash /vagrant/tools/sysbench_pg_oltp_ro.sh "$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts)" postgres secret postgres 2 10000 4 100"
    echo "benchmarking with pgpool"
    ansible -i ansible_hosts $USER.node1 -a "/bin/bash /vagrant/tools/sysbench_pg_oltp_ro.sh "$(sed -ne '/node2/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts)" postgres secret postgres 2 10000 4 100"
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    PPGSQL=12.2-4 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
      vagrant up default
    SYSBENCH=1.0.20-6 vagrant up node1
    PGPOOL=4.1.2-1 PPGSQL=12.2-4 DB_PASS=secret START=1 \
      DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      vagrant up node2
    vagrant ssh node1 -- \
      /bin/bash /vagrant/tools/sysbench_pg_oltp_ro.sh \
        $(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
        postgres secret postgres 2 10000 4 100
    echo "benchmarking with pgpool"
    vagrant ssh node1 -- \
      sudo /bin/bash /vagrant/tools/sysbench_pg_oltp_ro.sh \
        $(vagrant ssh node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
        postgres secret postgres 2 10000 4 100
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi

# Postgresql Odyssey + PG
if [[ "x$2" = "" || "x$2" = "xodyssey" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/8 3
    PG=12.2 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
      lxdock up default
    SYSBENCH=1.0.20-6 lxdock up node1
    ODYSSEY=1.1 DB_PASS=secret \
      DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      lxdock up node2
	  lxdock shell node1 -c \
      /bin/bash /vagrant/tools/sysbench_pg_oltp_ro.sh \
        $(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
        postgres secret postgres 2 10000 4 100 yes
    echo "benchmarking with pgpool"
    lxdock shell node1 -c \
      /bin/bash /vagrant/tools/sysbench_pg_oltp_ro.sh \
        $(lxdock shell node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
        postgres secret postgres 2 10000 4 100 yes
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh --os centos8
    PG=12.2 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    SYSBENCH=1.0.20-6 \
      ansible-playbook -i ansible_hosts --limit $USER.node1 playbook.yml
    ODYSSEY=1.1 DB_PASS=secret \
      DB_IP=$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      ansible-playbook -i ansible_hosts --limit $USER.node2 playbook.yml
    ansible -i ansible_hosts $USER.node1 -a "/bin/bash /vagrant/tools/sysbench_pg_oltp_ro.sh "$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts)" postgres secret postgres 2 10000 4 100 yes"
    echo "benchmarking with odyssey"
    ansible -i ansible_hosts $USER.node1 -a "/bin/bash /vagrant/tools/sysbench_pg_oltp_ro.sh "$(sed -ne '/node2/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts)" postgres secret postgres 2 10000 4 100 yes"
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    PG=12.2 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
      vagrant up default
    SYSBENCH=1.0.20-6 vagrant up node1
    OS=centos/8 \
    ODYSSEY=1.1 DB_PASS=secret \
      DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      vagrant up node2
    vagrant ssh node1 -- \
      /bin/bash /vagrant/tools/sysbench_pg_oltp_ro.sh \
        $(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
        postgres secret postgres 2 10000 4 100 yes
    echo "benchmarking with pgpool"
    vagrant ssh node1 -- \
      sudo /bin/bash /vagrant/tools/sysbench_pg_oltp_ro.sh \
        $(vagrant ssh node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
        postgres secret postgres 2 10000 4 100 yes
    test $DESTROY = yes && vagrant destroy -f
  fi
fi

# Community Postgresql 12
if [[ "x$2" = "" || "x$2" = "xpg12" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 3
    PG=12.2 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
      lxdock up default
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh
    PG=12.2 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    PG=12.2 DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
      vagrant up default
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi

# Percona K8S Operator for PXC
if [[ "x$2" = "" || "x$2" = "xpopxc" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 4
    K3S=latest K8S_MINIO=yes lxdock up default
    until [ "x" != "x$IP" ]; do
      IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null)
      sleep 1
    done
    echo "K8S master IP: $IP"
    K3S_TOKEN=$(lxdock shell default -c cat /var/lib/rancher/k3s/server/node-token) \
      K3S_URL="https://$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null):6443" \
      lxdock up node1 node2 node3
    # there are dns resolution issues for "too fast start"
    sleep 30
    K3S=latest PKO4PXC='1.4.0' K8S_PMM=1 DB_FEATURES="backup" lxdock provision default
    lxdock shell default -c kubectl apply -f /vagrant/configs/k8s/svc-replication-master.yaml

    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh --k8s
    KUBE_CONFIG=kube.config PKO4PXC='1.4.0' K8S_PMM=1 K8S_MINIO=1 \
      DB_FEATURES="backup" \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    test $DESTROY = yes && sudo podman rm -f ihanick.node2 ihanick.default ihanick.k8sw1 ihanick.k8sw3 ihanick.k8sm ihanick.node1 ihanick.k8sw2
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    K3S=latest K8S_MINIO=yes vagrant up default
    until [ "x" != "x$IP" ]; do
      IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null)
      sleep 1
    done
    echo "K8S master IP: $IP"
    K3S_TOKEN=$(vagrant ssh default -c cat /var/lib/rancher/k3s/server/node-token) \
      K3S_URL="https://$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null):6443" \
      vagrant up node1 node2 node3
    # there are dns resolution issues for "too fast start"
    sleep 30
    K3S=latest PKO4PXC='1.4.0' K8S_PMM=1 DB_FEATURES="backup" vagrant provision default
    vagrant default -c kubectl apply -f /vagrant/configs/k8s/svc-replication-master.yaml
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi


if [[ "x$2" = "" || "x$2" = "xc8my8" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/8
    MYSQL=8.0.21-1 DB_USER=root DB_PASS=secret START=1 DB_OPTS=mysql/async-repl-gtid.cnf \
      lxdock up default
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh --os centos8
    MYSQL=8.0.21-1 DB_USER=root DB_PASS=secret START=1 DB_OPTS=mysql/async-repl-gtid.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    MYSQL=8.0.21-1 DB_USER=root DB_PASS=secret START=1 DB_OPTS=mysql/async-repl-gtid.cnf \
      OS=centos/8 \
      vagrant up default
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi

if [[ "x$2" = "" || "x$2" = "xc8my8pxb8" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/8
    MYSQL=8.0.21-1 DB_USER=root DB_PASS=secret START=1 DB_OPTS=mysql/async-repl-gtid.cnf \
      PXB=8.0.13-1 \
      lxdock up default
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh --os centos8
    MYSQL=8.0.21-1 DB_USER=root DB_PASS=secret START=1 DB_OPTS=mysql/async-repl-gtid.cnf \
      PXB=8.0.13-1 \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    MYSQL=8.0.21-1 DB_USER=root DB_PASS=secret START=1 DB_OPTS=mysql/async-repl-gtid.cnf \
      PXB=8.0.13-1 \
      OS=centos/8 \
      vagrant up default
    test $DESTROY = yes && vagrant destroy -f || true
  fi
fi

# MySQL Connector Java test LDAP
if [[ "x$2" = "" || "x$2" = "xmysql_connector_java_ldap" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 3
    LDAP_SERVER=1 DB_USER=dba DB_PASS=secret \
      lxdock up node2
    LDAP_IP=$(lxdock shell node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_USER=dba DB_PASS=secret START=1 PS=5.7.26-29.1 DB_OPTS=mysql/async-repl-gtid.cnf \
      lxdock up default
    LDAP_IP=$( lxdock shell node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_IP=$(lxdock shell default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_PASS=secret DB_USER=dba MYSQL_JAVA=8.0.17-1 \
      lxdock up node1
    lxdock shell node1 -c bash -c 'cd /srv/java && sudo javac ConnectorTest.java && java -classpath "./:/usr/share/java/mysql-connector-java.jar:/usr/share/java/" ConnectorTest'
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh
    LDAP_SERVER=1 DB_USER=dba DB_PASS=secret ansible-playbook -i ansible_hosts --limit $USER.node2 playbook.yml
    LDAP_IP=$(sed -ne '/node2/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      DB_USER=dba DB_PASS=secret START=1 PS=5.7.26-29.1 DB_OPTS=mysql/async-repl-gtid.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    LDAP_IP=$(sed -ne '/node2/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
    DB_IP=$(sed -ne '/default/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      DB_USER=dba DB_PASS=secret MYSQL_JAVA=8.0.17-1 \
      ansible-playbook -i ansible_hosts --limit $USER.node1 playbook.yml
    ssh -i secret/id_rsa \
      root@$(sed -ne '/node1/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) \
      bash -c 'cd /srv/java && sudo javac ConnectorTest.java && java -classpath "./:/usr/share/java/mysql-connector-java.jar:/usr/share/java/" ConnectorTest'
    test $DESTROY = yes && sudo podman rm -f $USER.default $USER.node1 $USER.node2
  else
    LDAP_SERVER=1 DB_USER=dba DB_PASS=secret \
      vagrant up node2
    LDAP_IP=$(vagrant ssh node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_USER=dba DB_PASS=secret START=1 PS=5.7.26-29.1 DB_OPTS=mysql/async-repl-gtid.cnf \
      vagrant up default
    LDAP_IP=$(vagrant ssh node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_IP=$(vagrant ssh default -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      DB_PASS=secret DB_USER=dba MYSQL_JAVA=8.0.17-1 \
      vagrant up node1
    vagrant ssh node1 -c bash -c 'cd /srv/java && sudo javac ConnectorTest.java && java -classpath "./:/usr/share/java/mysql-connector-java.jar:/usr/share/java/" ConnectorTest'
    test $DESTROY = yes && vagrant destroy -f
  fi
fi

# WAL-G
if [[ "x$2" = "" || "x$2" = "xwalg" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 1
    WALG=0.2.16 \
      lxdock up default
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh
    WALG=0.2.16 \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    WALG=0.2.16 \
      vagrant up default
    test $DESTROY = yes && vagrant destroy -f
  fi
fi

# Samba
if [[ "x$2" = "" || "x$2" = "xsamba" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 3
    SAMBA_AD=1 \
      lxdock up node2
    SAMBA_IP=$(lxdock shell node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      SAMBA_SID=$(lxdock shell node2 -c bash -c "/opt/samba/bin/wbinfo -D PERCONA|grep SID|awk '{print \$3}'") \
      SAMBA_PASS="verysecretpassword1^" \
      DB_USER=dba DB_PASS=secret START=1 \
      PS=5.7.26-29.1 DB_OPTS=mysql/async-repl-gtid.cnf \
      lxdock up default
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh --samba=node2
    SAMBA_AD=1 \
      ansible-playbook -i ansible_hosts --limit $USER.node2 playbook.yml

    SAMBA_IP="$(sed -ne '/node2/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts)" \
      SAMBA_SID="$(ssh -i secret/id_rsa root@$(sed -ne '/node2/ {s/^.*ansible_host=//;s/ .*$//;p}' ansible_hosts) -o StrictHostKeyChecking=no /opt/samba/bin/wbinfo -D PERCONA|grep SID|awk '{print $3}')" \
      SAMBA_PASS="verysecretpassword1^" \
      DB_USER=dba DB_PASS=secret START=1 \
      PS=5.7.26-29.1 DB_OPTS=mysql/async-repl-gtid.cnf \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    SAMBA_AD=1 \
      vagrant up node2
    SAMBA_IP=$(vagrant ssh node2 -c /vagrant/tools/node_ip.sh 2>/dev/null) \
      SAMBA_SID=$(vagrant ssh node2 -- "/opt/samba/bin/wbinfo -D PERCONA|grep SID|awk '{print \$3}'" ) \
      SAMBA_PASS="verysecretpassword1^" \
      DB_USER=dba DB_PASS=secret START=1 \
      PS=5.7.26-29.1 DB_OPTS=mysql/async-repl-gtid.cnf \
      vagrant up default
    test $DESTROY = yes && vagrant destroy -f
  fi
fi

if [[ "x$2" = "" || "x$2" = "xperconatoolkit" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    ./gen_lxdock.sh anydbver centos/7 1
    PT=3.2.0-1 \
      PS=5.7.30-33.1 DB_OPTS=mysql/async-repl-gtid.cnf \
      DB_USER=dba DB_PASS=secret START=1 \
      lxdock up default
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh --nodes 1
    PT=3.2.0-1 \
      PS=5.7.30-33.1 DB_OPTS=mysql/async-repl-gtid.cnf \
      DB_USER=dba DB_PASS=secret START=1 \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    PT=3.2.0-1 \
      PS=5.7.30-33.1 DB_OPTS=mysql/async-repl-gtid.cnf \
      DB_USER=dba DB_PASS=secret START=1 \
      vagrant up default
    test $DESTROY = yes && vagrant destroy -f
  fi
fi

# Set hostnames for containers
if [[ "x$2" = "" || "x$2" = "xdns" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh --hostname default=dns.percona.local --hostname node2=pdc.percona.local
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    test $DESTROY = yes && vagrant destroy -f
  fi
fi

# Kerberos and PG
if [[ "x$2" = "" || "x$2" = "xkerberos" ]] ; then
  if [[ "x$1" = "xlxdock" ]] ; then
    test $DESTROY = yes && lxdock destroy -f
  elif [[ "x$1" = "xpodman" ]] ; then
    ./start_podman.sh \
      --hostname default=pg.percona.local \
      --hostname node1=client.percona.local \
      --hostname node2=kdc.percona.local
    KERBEROS=1 \
      DB_USER=dba DB_PASS=secret \
      ansible-playbook -i ansible_hosts --limit $USER.node2 playbook.yml

    KERBEROS_CLIENT=1 \
      PG=12.2 DB_USER=dba DB_PASS=secret DB_OPTS=postgresql/logical.conf START=1 \
      ansible-playbook -i ansible_hosts --limit $USER.default playbook.yml
    KERBEROS_CLIENT=1 \
      DB_USER=dba DB_PASS=secret \
      ansible-playbook -i ansible_hosts --limit $USER.node1 playbook.yml
    test $DESTROY = yes && ./start_podman.sh --destroy
  else
    test $DESTROY = yes && vagrant destroy -f
  fi
fi
