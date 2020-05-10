#!/bin/bash
export PROV=lxc
# use export PROV=lxd for vagrant-lxd
for psver in "5.6.47-rel87.0.1" "5.7.29-32.1" "8.0.18-9.1"; do
    PS=$psver vagrant up --provider=$PROV
    vagrant destroy -f
done

for pxcver in "5.6.45-28.36.1" "5.7.22-29.26.1" "8.0.18-9.3"; do
    PXC=$pxcver vagrant up --provider=$PROV
    vagrant destroy -f
done

DB_USER=root DB_PASS=secret PXC=5.7.28-31.41.2 vagrant up --provider=$PROV ; vagrant destroy -f
DB_USER=root DB_PASS=secret PS=5.7.29-32.1 vagrant up --provider=$PROV ; vagrant destroy -f
DB_USER=root DB_PASS=secret PS=5.6.20-rel68.0 vagrant up --provider=$PROV
DB_USER=root DB_PASS=secret PS=8.0.19-10.1 vagrant up --provider=$PROV ; vagrant destroy -f
DB_USER=root DB_PASS=secret PXC=8.0.18-9.3 vagrant up --provider=$PROV ; vagrant destroy -f
 
# Test separate xtrabackup installation
PXB=2.3.9-1 vagrant up --provider=$PROV; vagrant destroy -f
PXB=2.4.14-1 vagrant up --provider=$PROV; vagrant destroy -f
PXB=8.0.10-1 vagrant up --provider=$PROV; vagrant destroy -f

# Test mongodb
PSMDB=3.6.16-3.6 DB_PASS=secret vagrant up --provider=$PROV ; vagrant destroy -f
PSMDB=4.0.17-10 DB_PASS=secret vagrant up --provider=$PROV ; vagrant destroy -f
PSMDB=4.2.3-4 DB_PASS=secret vagrant up --provider=$PROV ; vagrant destroy -f

PBM=1.1.1-1 vagrant up --provider=$PROV ; vagrant destroy -f

# PMM client
PMM_CLIENT=1.17.3-1 vagrant up --provider=$PROV ; vagrant destroy -f
PMM_CLIENT=2.5.0-6 vagrant up --provider=$PROV ; vagrant destroy -f

# PMM server running inside podman (easier to setup compare to docker)
PMM_SERVER=1.17.3 vagrant up --provider=$PROV ; vagrant destroy -f
PMM_SERVER=2.5.0 vagrant up --provider=$PROV ; vagrant destroy -f

# Postresql
PPGSQL=11.5-1 DB_PASS=secret vagrant up --provider=$PROV ; vagrant destroy -f
PPGSQL=11.6-2 DB_PASS=secret vagrant up --provider=$PROV ;  vagrant destroy -f
PPGSQL=11.7-2 DB_PASS=secret vagrant up --provider=$PROV ; vagrant destroy -f
PPGSQL=12.2-4 DB_PASS=secret vagrant up --provider=$PROV ; vagrant destroy -f

# percona toolkit
PT=3.2.0-1 vagrant up --provider=$PROV ; vagrant destroy -f

# Multi-node setup
PXC=8.0.18-9.3 vagrant up --provider=$PROV
for i in `seq 1 3` ; do PT=3.2.0-1 PXC=8.0.18-9.3 PMM_CLIENT=2.5.0-6 vagrant up --provider=$PROV node$i ; done
PMM_SERVER=2.5.0 vagrant up --provider=$PROV node4
for i in default node1 node2 node3 ; do vagrant ssh $i -- 'hostname;/sbin/ip addr ls|grep "inet "|grep -v "inet 127";rpm -qa|grep -i percona|xargs' ; done
vagrant destroy -f

# Percona XtraDB Cluster (PXC) Kubernetes, using k3s one-file distribution
PKO4PXC='1.4.0' vagrant up --provider=$PROV
# cluster creation requires a few minutes
vagrant destroy -f

# MongoDB in Kubernetes, using k3s one-file distribution
PKO4PSMDB='1.4.0' vagrant up --provider=$PROV
# cluster creation requires a few minutes
vagrant destroy -f
