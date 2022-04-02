#!/usr/bin/env python3
import os
import subprocess
import logging
from pathlib import Path
import shutil
import time
import datetime
import re
import sys
from distutils.version import StrictVersion
import argparse

COMMAND_TIMEOUT=600

FORMAT = '%(asctime)s %(levelname)s %(message)s'
logging.basicConfig(format=FORMAT)
logger = logging.getLogger('run k8s operator')
logger.setLevel(logging.INFO)

#if not data_path.is_dir():
#  raise Exception("Data directory not exists: {}".format(data_path.resolve()))
def run_fatal(args, err_msg, ignore_msg=None, print_cmd=True, env=None):
  if print_cmd:
    logger.info(subprocess.list2cmdline(args))
  process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, close_fds=True, env=env)
  ret_code = process.wait(timeout=COMMAND_TIMEOUT)
  output = process.communicate()[0].decode('utf-8')
  if ignore_msg and re.search(ignore_msg, output):
    return ret_code
  if ret_code:
    logger.error(output)
    raise Exception((err_msg+" '{}'").format(subprocess.list2cmdline(process.args)))
  return ret_code

def run_get_line(args,err_msg, ignore_msg=None, print_cmd=True):
  if print_cmd:
    logger.info(subprocess.list2cmdline(args))
  process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, close_fds=True)
  ret_code = process.wait(timeout=COMMAND_TIMEOUT)
  output = process.communicate()[0].decode('utf-8')
  if ignore_msg and re.search(ignore_msg, output):
    return output
  if ret_code:
    logger.error(output)
    raise Exception((err_msg+" '{}'").format(subprocess.list2cmdline(process.args)))
  return output
  

def k8s_wait_for_ready(ns, labels):
  for i in range(COMMAND_TIMEOUT // 2):
    s = datetime.datetime.now()
    if run_fatal(["kubectl", "wait", "--timeout=2s", "--for=condition=ready", "-n", ns, "pod", "-l", labels],
        "Pod ready wait problem",
        r"error: timed out waiting for the condition on|error: no matching resources found", False) == 0:
      return True
    if (datetime.datetime.now() - s).total_seconds() < 1.5:
      time.sleep(2)
  return False

def branch_name(ver):
  if ver == 'latest':
    return 'main'
  if ver == 'main' or ver[0] == 'v' or ('.' not in ver):
    return ver
  return 'v' + ver

def prepare_operator_repository(data_path, operator_name, operator_version):
  data_path = Path(data_path)
  git_url = "https://github.com/percona/{operator_name}.git".format(operator_name=operator_name)
  os.makedirs(data_path, exist_ok=True)
  os.chdir(data_path)
  if not (data_path / operator_name / '.git').is_dir():
    if (data_path / operator_name).is_dir():
      logger.warning("Operator directory exists, but it's not a git directory, removing it: {}".format(data_path / operator_name))
      shutil.rmtree(data_path / operator_name)

    if '.' in operator_version:
      run_fatal(["git", "clone", "-b", branch_name(operator_version), git_url], "Can't fetch operator repository")
      os.chdir(data_path / operator_name)
    else:
      run_fatal(["git", "clone", git_url], "Can't fetch operator repository")
      os.chdir(data_path / operator_name)
      run_fatal(["git", "checkout", branch_name(operator_version)], "Can't checkout operator repository")
  else:
    os.chdir(data_path / operator_name)
    run_fatal(["git", "fetch"], "Can't fetch new changes from operator repository at {}".format(os.getcwd()))
    run_fatal(["git", "checkout", branch_name(operator_version)], "Can't checkout operator repository")

def get_containers_list(ns,labels):
  return list(run_get_line(["kubectl", "get", "pods", "-n", ns, "-l", labels, "-o", r'jsonpath={range .items[*]}{.metadata.name }{"\n"}{end}'], "Can't get pod name").splitlines())

def info_pg_operator(ns):
  print("kubectl -n {} get PerconaPGCluster cluster1".format(subprocess.list2cmdline([ns])))
  for container in get_containers_list(ns,"name=cluster1") + get_containers_list(ns,"name=cluster1-replica"):
    if container != "":
      print("kubectl -n {} exec -it {} -- env PSQL_HISTORY=/tmp/.psql_history psql -U postgres".format(
        subprocess.list2cmdline([ns]), container))

def run_pg_operator(ns, op):
  run_fatal(["kubectl", "apply", "-n", ns, "-f", "./deploy/operator.yaml"], "Can't deploy operator")
  if not k8s_wait_for_ready(ns, "name=postgres-operator"):
    raise Exception("Kubernetes operator is not starting")
  time.sleep(30)
  run_fatal(["kubectl", "apply", "-n", ns, "-f", "./deploy/cr.yaml"], "Can't deploy cluster")
  if not k8s_wait_for_ready(ns, "name=cluster1"):
    raise Exception("cluster is not starting")

def op_labels(op, op_ver):
  if op == "percona-xtradb-cluster-operator" and StrictVersion(op_ver) > StrictVersion("1.6.0"):
    return "app.kubernetes.io/name="+op
  else:
    return "name="+op

def cluster_labels(op, op_ver):
  if op == "percona-xtradb-cluster-operator":
    return "app.kubernetes.io/instance=cluster1,app.kubernetes.io/component=pxc"
  elif op == "percona-server-mongodb-operator":
    return "app.kubernetes.io/instance=my-cluster-name,app.kubernetes.io/component=mongod"

def run_percona_operator(ns, op, op_ver):
  run_fatal(["kubectl", "apply", "-n", ns, "-f", "./deploy/bundle.yaml"], "Can't deploy operator")
  if not k8s_wait_for_ready(ns, op_labels(op, op_ver)):
    raise Exception("Kubernetes operator is not starting")
  run_fatal(["kubectl", "apply", "-n", ns, "-f", "./deploy/cr.yaml"], "Can't deploy cluster")
  if not k8s_wait_for_ready(ns, cluster_labels(op, op_ver)):
    raise Exception("cluster is not starting")

def cert_manager_ver_compat(operator_name, operator_version, cert_manager):
  if StrictVersion(cert_manager) <= StrictVersion("1.5.5"):
    return cert_manager
  if operator_name == "percona-server-mongodb-operator" and operator_version != "main" and StrictVersion(operator_version) < StrictVersion("1.12.0"):
    logger.info("Downgrading cert manager version to v1.5.5 supported by {} {}".format(operator_name, operator_version))
    return "1.5.5"
  else:
    return "1.7.2"

def run_cert_manager(ver):
  run_fatal(["kubectl", "apply", "-f", "https://github.com/cert-manager/cert-manager/releases/download/v{}/cert-manager.crds.yaml".format(ver)], "Can't deploy cert-manager.crds.yaml:"+ver)
  run_fatal(["kubectl", "apply", "-f", "https://github.com/cert-manager/cert-manager/releases/download/v{}/cert-manager.yaml".format(ver)], "Can't deploy cert-manager:"+ver)
  if not k8s_wait_for_ready("cert-manager", "app.kubernetes.io/name=cert-manager"):
    raise Exception("Cert-manager is not starting")

def get_operator_ns(operator_name):
  if operator_name == "percona-server-mongodb-operator":
    return "psmdb"
  if operator_name == "percona-postgresql-operator":
    return "pgo"
  if operator_name == "percona-xtradb-cluster-operator":
    return "pxc"
  return "default"

def run_helm(cmd, msg):
  helm_path = Path(__file__).parents[1] / 'data' / 'helm'
  helm_env = os.environ.copy()
  helm_env["HELM_CACHE_HOME"] = (helm_path / 'cache').resolve()
  helm_env["HELM_CONFIG_HOME"] = (helm_path / 'config').resolve()
  helm_env["HELM_DATA_HOME"] = (helm_path / 'data').resolve()
  run_fatal(cmd, msg, env=helm_env)

def run_pmm_server(pmm_version):
  run_fatal(["mkdir", "-p", "data/helm/cache", "data/helm/config", "data/helm/data"], "can't create directories for helm")
  run_helm(["helm", "repo", "add", "percona", "https://percona-charts.storage.googleapis.com"], "helm repo add problem")
  run_helm(["helm", "repo", "update"], "helm repo update problem")
  run_helm(["helm", "install", "monitoring", "percona/pmm-server", "--set", "credentials.username=admin" "--set" "credentials.password=verysecretpassword1^", "--set", "imageTag="+pmm_version, "--set", "platform=kubernetes"], "helm pmm install problem")

def run_minio_server():
  run_fatal(["mkdir", "-p", "data/helm/cache", "data/helm/config", "data/helm/data"], "can't create directories for helm")
  run_helm(["helm", "repo", "add", "minio", "https://helm.min.io/"], "helm repo add problem")
  run_helm(["helm", "repo", "update"], "helm repo update problem")
  run_helm(["helm", "install", "minio-service", "minio/minio",
    "--set", "accessKey=REPLACE-WITH-AWS-ACCESS-KEY", "--set", "secretKey=REPLACE-WITH-AWS-SECRET-KEY",
    "--set", "service.type=ClusterIP", "--set", "configPath=/tmp/.minio/",
    "--set", "persistence.size=2G", "--set", "buckets[0].name=operator-testing",
    "--set", "buckets[0].policy=none", "--set", "buckets[0].purge=false",
    "--set", "environment.MINIO_REGION=us-east-1"
    ], "helm pmm install problem")

def setup_pmm_client(args):
  pass
  # tools/yq ea '. as $item ireduce ({}; . * $item )' data/k8s/percona-xtradb-cluster-operator/deploy/cr.yaml ../configs/k8s/cr-pmm.yaml > cr-pmm.yaml

def enable_pmm(args):
  if args.pmm == "":
    return
  #merge_cr_yaml(args.yq, str((Path(args.data_path) / args.operator_name / "deploy" / "cr.yaml").resolve()), str((Path(args.conf_path) / "cr-pmm.yaml").resolve()) )
  # tools/yq ea '. as $item ireduce ({}; . * $item )' data/k8s/percona-xtradb-cluster-operator/deploy/cr.yaml ../configs/k8s/cr-pmm.yaml > data/k8s/percona-xtradb-cluster-operator/deploy/cr-pmm.yaml
  return

def merge_cr_yaml(yq, cr_path, part_path):
  cmd = yq + " ea '. as $item ireduce ({}; . * $item )' " + cr_path + " " + part_path + " > " + cr_path + ".tmp && mv " + cr_path + ".tmp " + cr_path
  logger.info(cmd)
  os.system(cmd)
  pass

def setup_operator(args):
  data_path = Path(__file__).parents[1] / 'data' / 'k8s'

  if args.cert_manager != "":
    run_cert_manager(cert_manager_ver_compat(args.operator_name, args.operator_version), args.cert_manager)
  if args.pmm != "":
    run_pmm_server(args.pmm)

  prepare_operator_repository(data_path.resolve(), args.operator_name, args.operator_version)
  if not args.smart_update:
    merge_cr_yaml(args.yq, str((Path(args.data_path) / args.operator_name / "deploy" / "cr.yaml").resolve()), str((Path(args.conf_path) / "cr-smart-update.yaml").resolve()) )

  if not k8s_wait_for_ready('kube-system', 'k8s-app=kube-dns'):
    raise Exception("Kubernetes cluster is not available")
  run_fatal(["kubectl", "create", "namespace", args.namespace],
      "Can't create a namespace for the cluster", r"from server \(AlreadyExists\)")

  enable_pmm(args)

  if args.minio:
    run_minio_server()
    if args.operator_name == "percona-xtradb-cluster-operator":
      run_fatal(["kubectl", "apply", "-n", args.namespace, "-f", "./deploy/backup-s3.yaml"], "Can't apply s3 secrets")
      merge_cr_yaml(args.yq, str((Path(args.data_path) / args.operator_name / "deploy" / "cr.yaml").resolve()), str((Path(args.conf_path) / "cr-minio.yaml").resolve()) )


  if args.operator_name == "percona-postgresql-operator":
    run_pg_operator(args.namespace, args.operator_name)
  elif args.operator_name in ("percona-server-mongodb-operator", "percona-xtradb-cluster-operator"):
    run_percona_operator(args.namespace, args.operator_name, args.operator_version)

def extract_secret_password(ns, secret, user):
  return run_get_line(["kubectl", "get", "secrets", "-n", ns, secret, "-o", r'go-template={{ .data.' + user + r'| base64decode }}'],
      "Can't get pod name")

def info_pxc_operator(ns):
  pwd = extract_secret_password(ns, "my-cluster-secrets", "root")
  root_cluster_pxc = ["kubectl", "-n", ns, "exec", "-it", "cluster1-pxc-0", "-c", "pxc", "--", "env", "LANG=C.utf8", "MYSQL_HISTFILE=/tmp/.mysql_history", "mysql", "-uroot", "-p"+pwd]
  print(subprocess.list2cmdline(root_cluster_pxc))

def info_mongo_operator(ns):
  pwd =  extract_secret_password(ns, "my-cluster-name-secrets", "MONGODB_CLUSTER_ADMIN_PASSWORD")
  cluster_admin_mongo = ["kubectl", "-n", ns, "exec", "-it", "my-cluster-name-rs0-0", "--", "env", "LANG=C.utf8", "HOME=/tmp", "mongo", "-u", "clusterAdmin", "--password="+pwd, "localhost/admin"]
  print(subprocess.list2cmdline(cluster_admin_mongo))

  pwd =  extract_secret_password(ns, "my-cluster-name-secrets", "MONGODB_USER_ADMIN_PASSWORD")
  user_admin_mongo = ["kubectl", "-n", ns, "exec", "-it", "my-cluster-name-rs0-0", "--", "env", "LANG=C.utf8", "HOME=/tmp", "mongo", "-u", "userAdmin", "--password="+pwd, "localhost/admin"]
  print(subprocess.list2cmdline(user_admin_mongo))

def operator_info(args):
  if args.operator_name == "percona-server-mongodb-operator":
    info_mongo_operator(args.namespace)
  if args.operator_name == "percona-postgresql-operator":
    info_pg_operator(args.namespace)
  if args.operator_name == "percona-xtradb-cluster-operator":
    info_pxc_operator(args.namespace)

def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--operator", dest="operator_name", type=str, default="percona-postgresql-operator")
  parser.add_argument("--version", dest="operator_version", type=str, default="1.1.0")
  parser.add_argument('--cert-manager', dest="cert_manager", type=str, default="")
  parser.add_argument('--pmm', dest="pmm", type=str, default="")
  parser.add_argument('--minio', dest="minio", action='store_true')
  parser.add_argument('--namespace', dest="namespace", type=str, default="")
  parser.add_argument('--info-only', dest="info", action='store_true')
  parser.add_argument('--smart-update', dest="smart_update", action='store_true')
  args = parser.parse_args()

  args.data_path = (Path(__file__).parents[1] / 'data' / 'k8s').resolve()
  args.conf_path = (Path(__file__).resolve().parents[2] / 'configs' / 'k8s').resolve()
  args.yq = str((Path(__file__).parents[0] / 'yq').resolve())

  if args.namespace == "":
    args.namespace = get_operator_ns(args.operator_name)

  if not args.info:
    setup_operator(args)

  operator_info(args)

  logger.info("Success")

if __name__ == '__main__':
  main()
