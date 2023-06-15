def arg_help(name):
  all_subargs = {
      "percona-server": "percona-server:ver,docker-image,mysql-router,master=NODE,leader=NODE",
      "k8s-pg": "k8s-pg:ver,tls,cluster-name=NAME,namespace=NS,backup-type=[gcs|s3],bucket=BUCKET,gcs-key=PATH_TO_JSON,replicas=N,db-version=DOCKER_IMAGE,memory=SIZE,sql=FILE,standby,helm,helm-values=VALUES_YAML",
      }
  examples = {
      "percona-server": "anydbver deploy ps:5.7.35 node1 ps:5.7.35,master=node0",
      "k8s-pg": "anydbver deploy k3d cert-manager k8s-pg:1.3.0,tls",
      }
  if name in all_subargs and name in examples:
    return "R|{}\nEx. {}".format(all_subargs[name], examples[name])
  elif name in examples:
    return "R|Ex. {}".format(examples[name])
  elif name in examples:
    return "R|{}".format(all_subargs[name])
  return ""
