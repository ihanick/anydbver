def arg_help(name):
  all_subargs = {
      "percona-server": "percona-server:ver,docker-image,mysql-router,master=NODE,leader=NODE",
      "k8s-pg": "k8s-pg:ver,tls,cluster-name=NAME,namespace=NS,backup-type=[gcs|s3],bucket=BUCKET,gcs-key=PATH_TO_JSON,replicas=N,db-version=DOCKER_IMAGE,memory=SIZE,sql=FILE,standby,helm,helm-values=VALUES_YAML",
      "pmm": "pmm:ver,docker-image,port=PORT_OR_LISTENADDR:PORT,dns=DOMAIN_NAME,certs=self-signed,namespace=K8S_NAMESPACE,helm=percona-helm-charts:CHART_VERSION",
      "pmm-client": "pmm-client:ver,server=URL_OR_NODE",
      "k3d": "k3d:ver,cluster-domain=K8S_CLUSTER_DOMAIN,ingress=PORT,ingress-type=[nginx|traefik|traefik-metallb|istio,feature-gates=VAL=[true|false]",
      "percona-server-mongodb": "psmdb:version shardsrv configsrv replica-set:FIRST_SERVER mongos-cfg:RS/NODE,NODE,NODE mongos-shard:RS0/NODE,NODE,RS1/NODE,NODE...",
      "ldap": "ldap, ldap-master:NODE",
      }
  examples = {
      "percona-server": "anydbver deploy ps:5.7.35 node1 ps:5.7.35,master=node0",
      "k8s-pg": "anydbver deploy k3d cert-manager k8s-pg:1.3.0,tls",
      "pmm": "anydbver deploy node0 pmm:latest,docker-image,port=0.0.0.0:10443 node1 ps:5.7 pmm-client:2.37.1-6,server=node0\nanydbver deploy pmm:latest,docker-image=perconalab/pmm-server:dev-latest,port=0.0.0.0:9443,memory=1g node1 ps:5.7 pmm-client:2.37.1-6,server=node0\nLXD: anydbver deploy node0 pmm:2.37.1 node1 psmdb replica-set:rs0 pmm-client:2.37.1-6,server=node0",
      "pmm-client": "anydbver deploy node0 pmm:latest,docker-image,port=0.0.0.0:10443 node1 ps:5.7 pmm-client:2.37.1-6,server=node0",
      "k3d": "anydbver deploy k3d:latest,cluster-domain=percona.local,ingress=443,ingress-type=nginx,nodes=3,feature-gates=MaxUnavailableStatefulSet=true cert-manager k8s-mongo:1.14.0,cluster-name=db1\nanydbver deploy k3d:latest,ingress=443,ingress-type=nginx,nodes=3 pmm:2.38.1,helm=percona-helm-charts:1.2.4,certs=self-signed,namespace=monitoring,dns=pmm.192.168.0.3.nip.io cert-manager k8s-pg:2.2.0",
      "percona-server-mongodb": "anydbver deploy psmdb replica-set:rs0 shardsrv  node1 psmdb master:default replica-set:rs0 shardsrv  node2 psmdb master:default replica-set:rs0 shardsrv node3 psmdb replica-set:rs1 shardsrv node4 psmdb replica-set:rs1 shardsrv master:node3 node5 psmdb replica-set:rs1 shardsrv master:node3 node6 psmdb configsrv replica-set:cfg0  node7 psmdb configsrv replica-set:cfg0 master:node6  node8 psmdb configsrv replica-set:cfg0 master:node6  node9 psmdb mongos-cfg:cfg0/node6,node7,node8 mongos-shard:rs0/default,node1,node2,rs1/node3,node4,node5",
      "ldap": "anydbver deploy ldap node1 ldap-master:default psmdb:5.0",
      }
  if name in all_subargs and name in examples:
    return "R|{}\nEx. {}".format(all_subargs[name], examples[name])
  elif name in examples:
    return "R|Ex. {}".format(examples[name])
  elif name in examples:
    return "R|{}".format(all_subargs[name])
  return ""
