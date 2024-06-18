def arg_help(name):
  all_subargs = {
      "alertmanager": "alertmanager:version,docker-image,port=N",
      "percona-server": "percona-server:ver,docker-image,mysql-router,<master=NODE|leader=NODE>,gtid=<0|1>,rocksdb,sql=s3_url_to_sql_dump",
      "mysql-server": "mysql:ver,docker-image,mysql-router,<master=NODE|leader=NODE>,gtid=<0|1>",
      "percona-xtradb-cluster": "./anydbver deploy pxc node1 pxc:VER,master=NODE,galera",
      "percona-orchestrator": "percona-orchestrator:ver,master=NODE",
      "percona-proxysql": "percona-proxysql:ver,master=NODE",
      "sysbench": "sysbench:ver,[mysql=NODE],[postgresql=NODE,[oltp-rw]",
      "postgresql": "pg:VER,<primary|master|leader>=NODE,wal=logical",
      "patroni": "patroni:master=NODE",
      "repmgr": "repmgr",
      "percona-postgresql": "ppg:VER,<primary|master|leader>=NODE,wal=logical",
      "pgbackrest": "pgbackrest:VER",
      "k8s-pg": "k8s-pg:ver,tls,cluster-name=NAME,namespace=NS,backup-type=[gcs|s3],bucket=BUCKET,gcs-key=PATH_TO_JSON,replicas=N,db-version=DOCKER_IMAGE,memory=SIZE,sql=FILE,standby,helm,helm-values=VALUES_YAML",
      "pmm": "pmm:ver,docker-image,port=PORT_OR_LISTENADDR:PORT,dns=DOMAIN_NAME,certs=self-signed,namespace=K8S_NAMESPACE,helm=percona-helm-charts:CHART_VERSION",
      "pmm-client": "pmm-client:ver,server=URL_OR_NODE,slowlog,perfschema",
      "k3d": "k3d:ver,cluster-domain=K8S_CLUSTER_DOMAIN,ingress=PORT,ingress-type=[nginxinc|nginx|traefik|traefik-metallb|istio,feature-gates=VAL=[true|false],metallb",
      "percona-server-mongodb": "psmdb:version,role=<shard|cfg>,replica-set=RSN mongos-cfg:RS/NODE,NODE,NODE mongos-shard:RS0/NODE,NODE,RS1/NODE,NODE...",
      "percona-backup-mongodb": "pbm:version,s3=https://access:secret@endpointurl:port/bucket",
      "ldap": "ldap, ldap-master:NODE",
      "samba": "samba:latest,docker-image,realm=PERCONA.LOCAL",
      "valkey": "valkey:unstable,docker-image,master=NODE",
      }
  examples = {
      "percona-server": "anydbver deploy ps:5.7.35 node1 ps:5.7.35,master=node0\nanydbver deploy ps:8.0,gtid=0 node1 ps:8.0,gtid=0,master=node0\nanydbver deploy ps:8.0,rocksdb,sql=http://UIdgE4sXPBTcBB4eEawU:7UdlDzBF769dbIOMVILV@172.17.0.1:9000/sampledb/world.sql percona-xtrabackup:8.0",
      "mysql-server": "anydbver deploy mysql:5.7.35 node1 mysql:5.7.35,master=node0\nanydbver deploy mysql:8.0,gtid=0 node1 mysql:8.0,gtid=0,master=node0\nanydbver deploy mysql:8.0,docker-image,group-replication node1 mysql:8.0,docker-image,group-replication,master=node0 node2 mysql:8.0,docker-image,group-replication,master=node0",
      "percona-xtradb-cluster": "anydbver deploy pxc node1 pxc:latest,master=node0,galera node2 pxc:latest,master=node0,galera",
      "percona-orchestrator": "anydbver deploy ps:5.7 node1 ps:5.7,master=node0 node2 ps:5.7,master=node1 node3 percona-orchestrator:latest,master=node0",
      "percona-proxysql": "anydbver deploy ps:5.7 node1 ps:5.7,master=node0 node2 percona-proxysql:latest,master=node0",
      "sysbench": "anydbver deploy ps:5.7 node1 sysbench:latest,mysql=node0,oltp-rw\nanydbver deploy ppg:12 sysbench:latest,postgresql=node0,oltp-rw",
      "postgresql": "anydbver deploy node0 pg:latest,wal=logical node1 pg:latest,primary=node0,wal=logical\nanydbver deploy pg:14\nanydbver deploy pg:latest,docker-image node1 pg:latest,docker-image,master=node0",
      "patroni": "anydbver deploy pg patroni node1 pg:master=node0 patroni:master=node0 node2 pg:master=node0 patroni:master=node0",
      "repmgr": "anydbver deploy pg:16 repmgr node1 pg:16,master=node0 repmgr node2 pg:16,master=node0 repmgr",
      "percona-postgresql": "anydbver deploy node0 ppg:latest,wal=logical node1 ppg:latest,primary=node0,wal=logical\nanydbver deploy ppg:14",
      "pgbackrest": "anydbver deploy ppg pgbackrest",
      "k8s-pg": "anydbver deploy k3d cert-manager k8s-pg:1.3.0,tls",
      "pmm": "anydbver deploy node0 pmm:latest,docker-image,port=0.0.0.0:10443 node1 ps:5.7 pmm-client:2.37.1-6,server=node0\nanydbver deploy pmm:latest,docker-image=perconalab/pmm-server:dev-latest,port=0.0.0.0:9443,memory=1g node1 ps:5.7 pmm-client:2.37.1-6,server=node0\nLXD: anydbver deploy node0 pmm:2.37.1 node1 psmdb replica-set:rs0 pmm-client:2.37.1-6,server=node0",
      "pmm-client": "anydbver deploy node0 pmm:latest,docker-image,port=0.0.0.0:10443 node1 ps:5.7 pmm-client:2.37.1-6,server=node0,perfschema",
      "k3d": "anydbver deploy k3d:latest,cluster-domain=percona.local,ingress=443,ingress-type=nginxinc,nodes=3,feature-gates=MaxUnavailableStatefulSet=true cert-manager k8s-mongo:1.14.0,cluster-name=db1\nanydbver deploy k3d:latest,ingress=443,ingress-type=nginxinc,nodes=3 pmm:2.38.1,helm=percona-helm-charts:1.2.4,certs=self-signed,namespace=monitoring,dns=pmm.192.168.0.3.nip.io cert-manager k8s-pg:2.2.0\nanydbver deploy k3d:latest,metallb k8s-mongo:1.14.0,expose # dedicate /24 net from docker network for LoadBalancer ip addresses",
      "percona-server-mongodb": "anydbver deploy psmdb:latest,replica-set=rs0,role=shard node1 psmdb:latest,replica-set=rs0,role=shard,master=node0 node2 psmdb:latest,replica-set=rs0,role=shard,master=node0 node3 psmdb:latest,replica-set=rs1,role=shard node4 psmdb:latest,replica-set=rs1,role=shard,master=node3 node5 psmdb:latest,replica-set=rs1,role=shard,master=node3 node6 psmdb:latest,replica-set=cfg0,role=cfg node7 psmdb:latest,replica-set=cfg0,role=cfg,master=node6 node8 psmdb:latest,replica-set=cfg0,role=cfg,master=node6 node9 psmdb:latest mongos-cfg:cfg0/node6,node7,node8 mongos-shard:rs0/node0,node1,node2,rs1/node3,node4,node5",
      "ldap": "anydbver deploy ldap node1 ldap-master:default psmdb:5.0\nanydbver deploy ldap node1 ldap-master:default ps:8.0,ldap=simple",
      "samba": "anydbver deploy samba:latest,docker-image node1 os:el7 ps samba-client:node0",
      "alertmanager": "anydbver deploy node0 pmm:latest,docker-image,port=0.0.0.0:10443 node1 ps:5.7 pmm-client:2.37.1-6,server=node0 node2 alertmanager:latest,docker-image,port=9093",
      "valkey": "anydbver deploy valkey:unstable,docker-image node1 valkey:unstable,docker-image,master=node0 node2 valkey:unstable,docker-image,master=node0",
      }
  if name in all_subargs and name in examples:
    return "R|{}\nEx. {}".format(all_subargs[name], examples[name])
  elif name in examples:
    return "R|Ex. {}".format(examples[name])
  elif name in examples:
    return "R|{}".format(all_subargs[name])
  return ""
