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
import base64

COMMAND_TIMEOUT=600

FORMAT = '%(asctime)s %(levelname)s %(message)s'
logging.basicConfig(format=FORMAT)
logger = logging.getLogger('run k8s operator')
logger.setLevel(logging.INFO)

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

def k8s_check_ready(ns, labels):
  if run_fatal(["kubectl", "wait", "--for=condition=ready", "-n", ns, "pod", "-l", labels],
      "Pod ready wait problem",
      r"error: timed out waiting for the condition on|error: no matching resources found", False) == 0:
    return True
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
    run_fatal(["git", "reset", "--hard"], "Can't reset operator repository")
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
  run_fatal(["sed", "-i", "-re", r"s/namespace: pgo\>/namespace: {}/".format(ns), "./deploy/operator.yaml"], "fix namespace in yaml")
  run_fatal(["sed", "-i", "-re", r"s/namespace: pgo\>/namespace: {}/".format(ns), "./deploy/cr.yaml"], "fix namespace in yaml")
  run_fatal(["kubectl", "apply", "-n", ns, "-f", "./deploy/operator.yaml"], "Can't deploy operator")
  if not k8s_wait_for_ready(ns, "name=postgres-operator"):
    raise Exception("Kubernetes operator is not starting")
  time.sleep(30)
  run_fatal(["kubectl", "apply", "-n", ns, "-f", "./deploy/cr.yaml"], "Can't deploy cluster")
  if not k8s_wait_for_ready(ns, "name=cluster1"):
    raise Exception("cluster is not starting")

def op_labels(op, op_ver):
  if op in ("percona-xtradb-cluster-operator", "pxc-operator") and StrictVersion(op_ver) > StrictVersion("1.6.0"):
    return "app.kubernetes.io/name="+op
  else:
    return "name="+op

def cluster_labels(op, op_ver):
  if op == "percona-xtradb-cluster-operator":
    return "app.kubernetes.io/instance=cluster1,app.kubernetes.io/component=pxc"
  elif op == "percona-server-mongodb-operator":
    return "app.kubernetes.io/instance=my-cluster-name,app.kubernetes.io/component=mongod"

def run_percona_operator(ns, op, op_ver):
  run_fatal(["kubectl", "apply", "-n", ns, "-f", "./deploy/bundle.yaml"], "Can't deploy operator", ignore_msg=r"is invalid: status.storedVersions\[[0-9]+\]: Invalid value")
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
  if not k8s_wait_for_ready("cert-manager", "app.kubernetes.io/name=webhook"):
    raise Exception("Cert-manager is not starting webhook")
  if not k8s_wait_for_ready("cert-manager", "app.kubernetes.io/name=cainjector"):
    raise Exception("Cert-manager is not starting cainjector")


def get_operator_ns(operator_name):
  if operator_name == "percona-server-mongodb-operator":
    return "psmdb"
  if operator_name == "percona-postgresql-operator":
    return "pgo"
  if operator_name == "percona-xtradb-cluster-operator":
    return "pxc"
  return "default"

def run_helm(helm_path, cmd, msg):
  helm_env = os.environ.copy()
  helm_env["HELM_CACHE_HOME"] = (helm_path / 'cache').resolve()
  helm_env["HELM_CONFIG_HOME"] = (helm_path / 'config').resolve()
  helm_env["HELM_DATA_HOME"] = (helm_path / 'data').resolve()
  environ_txt = "export"
  for key in ("HELM_CACHE_HOME","HELM_CONFIG_HOME","HELM_DATA_HOME"):
      environ_txt = environ_txt + " " + key + "=" + subprocess.list2cmdline([helm_env[key] ])
  logger.info(environ_txt)
  run_fatal(cmd, msg, ignore_msg="cannot re-use a name that is still in use", env=helm_env)

def run_pmm_server(helm_path, pmm_version, pmm_password):
  if k8s_check_ready("default", "app=monitoring,component=pmm"):
    return
  run_fatal(["mkdir", "-p", helm_path / "cache", helm_path / "config", helm_path / "data"], "can't create directories for helm")
  run_helm(helm_path, ["helm", "repo", "add", "percona", "https://percona-charts.storage.googleapis.com"], "helm repo add problem")
  run_helm(helm_path, ["helm", "repo", "update"], "helm repo update problem")
  run_helm(helm_path, ["helm", "install", "monitoring", "percona/pmm-server",
    "--set", "credentials.username=admin", "--set", "credentials.password="+pmm_password,
    "--set", "imageTag="+pmm_version, "--set", "platform=kubernetes"],
    "helm pmm install problem")
  if not k8s_wait_for_ready("default", "app=monitoring,component=pmm"):
    raise Exception("PMM Pod is not starting")
  time.sleep(10)
  run_fatal(["kubectl", "-n", "default",
      "exec", "-it", "monitoring-0", "--", "bash", "-c",
      "grafana-cli --homepath /usr/share/grafana --configOverrides cfg:default.paths.data=/srv/grafana admin reset-admin-password \"$ADMIN_PASSWORD\""],
      "can't fix pmm password")


def run_minio_server(args):
  tls_key_path = Path(args.anydbver_path) / args.minio_certs / "tls.key"
  tls_crt_path = Path(args.anydbver_path) / args.minio_certs / "tls.crt"
  if args.minio_certs != "" and args.minio_certs != "self-signed":
    logger.info("Loading minio secrets from {} and {}".format(str(tls_key_path.resolve()), str(tls_crt_path.resolve())))

  args.minio_custom_ssl = (args.minio_certs != "" 
      and args.minio_certs != "self-signed"
      and tls_key_path.is_file()
      and tls_crt_path.is_file())

  if args.cert_manager != "" and args.minio_certs == "self-signed":
    run_fatal(["kubectl", "apply", "-f", str((Path(args.conf_path) / "minio-certs.yaml").resolve())],
        "Can't create minio certificates")
  elif args.minio_custom_ssl:
    run_fatal(["kubectl", "create", "secret", "tls", "tls-minio",
      "--key="+str(tls_key_path.resolve()),
      "--cert="+str(tls_crt_path.resolve())],
      "can't create minio tls secret", "already exists")

  run_fatal(["mkdir", "-p",
    args.helm_path / "cache",
    args.helm_path / "config",
    args.helm_path / "data"], "can't create directories for helm")
  run_helm(args.helm_path, ["helm", "repo", "add", "minio", "https://helm.min.io/"], "helm repo add problem")
  run_helm(args.helm_path, ["helm", "repo", "update"], "helm repo update problem")
  if (args.cert_manager != "" and args.minio_certs == "self-signed") or args.minio_custom_ssl:
    run_helm(args.helm_path, ["helm", "install", "minio-service", "minio/minio",
      "--set", "accessKey=REPLACE-WITH-AWS-ACCESS-KEY", "--set", "secretKey=REPLACE-WITH-AWS-SECRET-KEY",
      "--set", "service.type=ClusterIP", "--set", "configPath=/tmp/.minio/",
      "--set", "persistence.size=2G", "--set", "buckets[0].name=operator-testing",
      "--set", "buckets[0].policy=none", "--set", "buckets[0].purge=false",
      "--set", "environment.MINIO_REGION=us-east-1",
      "--set", "service.port=443",
      "--set", "tls.enabled=true,tls.certSecret=tls-minio,tls.publicCrt=tls.crt,tls.privateKey=tls.key"
      ], "helm minio+certs install problem")
  else:
    run_helm(args.helm_path, ["helm", "install", "minio-service", "minio/minio",
      "--set", "accessKey=REPLACE-WITH-AWS-ACCESS-KEY", "--set", "secretKey=REPLACE-WITH-AWS-SECRET-KEY",
      "--set", "service.type=ClusterIP", "--set", "configPath=/tmp/.minio/",
      "--set", "persistence.size=2G", "--set", "buckets[0].name=operator-testing",
      "--set", "buckets[0].policy=none", "--set", "buckets[0].purge=false",
      "--set", "environment.MINIO_REGION=us-east-1"
      ], "helm minio install problem")

def merge_cr_yaml(yq, cr_path, part_path):
  cmd = yq + " ea '. as $item ireduce ({}; . * $item )' " + cr_path + " " + part_path + " > " + cr_path + ".tmp && mv " + cr_path + ".tmp " + cr_path
  logger.info(cmd)
  os.system(cmd)

def enable_pmm(args):
  if args.pmm == "":
    return
  deploy_path = Path(args.data_path) / args.operator_name / "deploy" 
  pmm_secret_path = str((deploy_path / "cr-pmm-secret.yaml").resolve()) 
  pmm_enable_path = str((deploy_path / "cr-pmm-enable.yaml").resolve()) 


  pmm_enable_yaml = """
    spec:
      pmm:
        enabled: true
        serverUser: admin
        serverHost: monitoring-service.default.svc.{cluster_domain}""".format(cluster_domain=args.cluster_domain)
  with open(pmm_enable_path,"w+") as f:
            f.writelines(pmm_enable_yaml)
  merge_cr_yaml(args.yq, str((deploy_path / "cr.yaml").resolve()), pmm_enable_path )
  pmm_secrets = ""
  if args.operator_name == "percona-xtradb-cluster-operator":
    pmm_secrets = """
      apiVersion: v1
      kind: Secret
      type: Opaque
      metadata:
        name: my-cluster-secrets
      data:
        clustercheck: SHNOU3VCUERyZU1JMURFUmJLSA==
        monitor: c3ZoN1hvVFB2STNJRUdSZU4xUg==
        operator: ZFNJRkdDTGQyY3drbVJxYzNuTQ==
        pmmserver: {pmm_password}
        proxyadmin: U1ZKWFhRWVFCUnQxc21kcQ==
        replication: bVRmdFNzRmpvR0lyUVNLQVJPaA==
        root: QUR2TzJPR3BLT3h4ZzBRaTN1
        xtrabackup: SFhtcDFVeExLUTE4eDh5a21adw==
      """
  elif args.operator_name == "percona-server-mongodb-operator":
    pmm_secrets = """
      apiVersion: v1
      kind: Secret
      type: Opaque
      metadata:
        name: my-cluster-name-secrets
      data:
        MONGODB_BACKUP_PASSWORD: eERlUDJZS0VOWW4xU2tSQQ==
        MONGODB_BACKUP_USER: YmFja3Vw
        MONGODB_CLUSTER_ADMIN_PASSWORD: ZWJINjdubm9pWFRlOUFnbk5lNQ==
        MONGODB_CLUSTER_ADMIN_USER: Y2x1c3RlckFkbWlu
        MONGODB_CLUSTER_MONITOR_PASSWORD: MTlRellvVGtwQlh3OXljYmhn
        MONGODB_CLUSTER_MONITOR_USER: Y2x1c3Rlck1vbml0b3I=
        MONGODB_USER_ADMIN_PASSWORD: a1lmWlBDdlBvMXRjVG04b3U=
        MONGODB_USER_ADMIN_USER: dXNlckFkbWlu
        PMM_SERVER_USER: YWRtaW4=
        PMM_SERVER_PASSWORD: {pmm_password}
      """
  else:
    return
  with open(pmm_secret_path,"w+") as f:
            f.writelines(pmm_secrets.format(pmm_password=base64.b64encode(bytes(args.pmm_password, 'utf-8')).decode('utf-8')))
  run_fatal(["kubectl", "apply", "-n", args.namespace, "-f", pmm_secret_path ], "Can't apply cluster secret secret with pmmserver")

def enable_minio(args):
  deploy_path = Path(args.data_path) / args.operator_name / "deploy"
  minio_storage_path = str((deploy_path / "cr-minio.yaml").resolve())
  proto = "http"
  minio_port = 9000
  if args.minio_certs != "":
    proto = "https"
    minio_port = 443
  if args.operator_name == "percona-xtradb-cluster-operator":
    minio_storage = """
      spec:
        backup:
          storages:
            minio:
              type: s3
              s3:
                bucket: operator-testing
                region: us-east-1
                credentialsSecret: my-cluster-name-backup-s3
                endpointUrl: {proto}://minio-service.{minio_namespace}.svc.{cluster_domain}:{minio_port}
      """.format(proto=proto, minio_namespace="default", cluster_domain=args.cluster_domain, minio_port=minio_port)
    with open(minio_storage_path,"w+") as f:
      f.writelines(minio_storage)
    run_fatal(["kubectl", "apply", "-n", args.namespace, "-f", "./deploy/backup-s3.yaml"], "Can't apply s3 secrets")
    merge_cr_yaml(args.yq, str((Path(args.data_path) / args.operator_name / "deploy" / "cr.yaml").resolve()), minio_storage_path )
  if args.operator_name == "percona-postgresql-operator":
    if args.minio_certs == "":
      logger.warning("Percona Postgresql Operator MinIO backups requires TLS")
      return

    minio_storage = """
      spec:
        backup:
          storages:
            minio:
              bucket: operator-testing
              endpointUrl: minio-service.{minio_namespace}.svc.{cluster_domain}
              uriStyle: "path"
              region: "us-east-1"
              verifyTLS: false
              type: "s3"
          schedule:
            - name: "sat-night-backup"
              schedule: "0 0 * * 6"
              keep: 3
              type: full
              storage: minio
      """.format(minio_namespace="default", cluster_domain=args.cluster_domain)
    with open(minio_storage_path,"w+") as f:
      f.writelines(minio_storage)
    run_fatal(["kubectl", "apply", "-n", args.namespace, "-f",
      str((Path(args.conf_path) / "cluster1-backrest-repo-config-secret-minio.yaml").resolve()) ], "Can't apply s3 secrets")
    merge_cr_yaml(args.yq,
        str((Path(args.data_path) / args.operator_name / "deploy" / "cr.yaml").resolve()),
        minio_storage_path)

def setup_operator_helm(args):
  if not k8s_wait_for_ready('kube-system', 'k8s-app=kube-dns'):
    raise Exception("Kubernetes cluster is not available")
  run_fatal(["kubectl", "create", "namespace", args.namespace],
      "Can't create a namespace for the cluster", r"from server \(AlreadyExists\)")

  if args.operator_name == "percona-xtradb-cluster-operator":
    run_helm(args.helm_path, ["helm", "repo", "add", "percona", "https://percona.github.io/percona-helm-charts/"], "helm repo add problem")
    run_helm(args.helm_path, ["helm", "install", "my-operator", "percona/pxc-operator", "--version", args.operator_version, "--namespace", args.namespace], "Can't start PXC operator with helm")
    cluster_name="my-db"
    if not k8s_wait_for_ready(args.namespace, op_labels("pxc-operator", args.operator_version)):
      raise Exception("Kubernetes operator is not starting")
    run_helm(args.helm_path, ["helm", "install", cluster_name, "percona/pxc-db", "--namespace", args.namespace], "Can't start PXC with helm")
    if not k8s_wait_for_ready(args.namespace, "app.kubernetes.io/component=pxc,app.kubernetes.io/instance={}-pxc-db".format(cluster_name)):
      raise Exception("cluster is not starting")


def setup_operator(args):
  data_path = Path(__file__).parents[1] / 'data' / 'k8s'

  if args.cert_manager != "":
    run_cert_manager(cert_manager_ver_compat(args.operator_name, args.operator_version, args.cert_manager))
  if args.pmm != "":
    run_pmm_server(args.helm_path, args.pmm, args.pmm_password)

  prepare_operator_repository(data_path.resolve(), args.operator_name, args.operator_version)
  if not args.smart_update:
    merge_cr_yaml(args.yq, str((Path(args.data_path) / args.operator_name / "deploy" / "cr.yaml").resolve()), str((Path(args.conf_path) / "cr-smart-update.yaml").resolve()) )

  if not k8s_wait_for_ready('kube-system', 'k8s-app=kube-dns'):
    raise Exception("Kubernetes cluster is not available")
  run_fatal(["kubectl", "create", "namespace", args.namespace],
      "Can't create a namespace for the cluster", r"from server \(AlreadyExists\)")

  enable_pmm(args)

  if args.minio:
    run_minio_server(args)
    enable_minio(args)


  if args.operator_name == "percona-postgresql-operator":
    run_pg_operator(args.namespace, args.operator_name)
  elif args.operator_name in ("percona-server-mongodb-operator", "percona-xtradb-cluster-operator"):
    run_percona_operator(args.namespace, args.operator_name, args.operator_version)

def extract_secret_password(ns, secret, user):
  return run_get_line(["kubectl", "get", "secrets", "-n", ns, secret, "-o", r'go-template={{ .data.' + user + r'| base64decode }}'],
      "Can't get pod name")

def info_pxc_operator(ns, helm_enabled):
  pxc_users_secret = "my-cluster-secrets"
  pxc_node_0 = "cluster1-pxc-0"
  if helm_enabled:
    pxc_users_secret="my-db-pxc-db"
    pxc_node_0 = "my-db-pxc-db-pxc-0"
  pwd = extract_secret_password(ns, pxc_users_secret, "root")
  root_cluster_pxc = ["kubectl", "-n", ns, "exec", "-it", pxc_node_0, "-c", "pxc", "--", "env", "LANG=C.utf8", "MYSQL_HISTFILE=/tmp/.mysql_history", "mysql", "-uroot", "-p"+pwd]
  print(subprocess.list2cmdline(root_cluster_pxc))

def info_mongo_operator(ns):
  pwd =  extract_secret_password(ns, "my-cluster-name-secrets", "MONGODB_CLUSTER_ADMIN_PASSWORD")
  cluster_admin_mongo = ["kubectl", "-n", ns, "exec", "-it", "my-cluster-name-rs0-0", "--", "env", "LANG=C.utf8", "HOME=/tmp", "mongo", "-u", "clusterAdmin", "--password="+pwd, "localhost/admin"]
  print(subprocess.list2cmdline(cluster_admin_mongo))

  pwd =  extract_secret_password(ns, "my-cluster-name-secrets", "MONGODB_USER_ADMIN_PASSWORD")
  user_admin_mongo = ["kubectl", "-n", ns, "exec", "-it", "my-cluster-name-rs0-0", "--", "env", "LANG=C.utf8", "HOME=/tmp", "mongo", "-u", "userAdmin", "--password="+pwd, "localhost/admin"]
  print(subprocess.list2cmdline(user_admin_mongo))


def populate_mongodb(ns, js_file):
  pass

def populate_pg_db(ns, sql_file):
  print("kubectl -n {} get PerconaPGCluster cluster1".format(subprocess.list2cmdline([ns])))
  for container in get_containers_list(ns,"name=cluster1"):
    if container != "":
      s = "kubectl -n {} exec -it {} -- env PSQL_HISTORY=/tmp/.psql_history psql -U postgres < {}".format(
          subprocess.list2cmdline([ns]), container, subprocess.list2cmdline([sql_file]))
      run_fatal(["sh", "-c", s], "Can't apply sql file")

def populate_pxc_db(ns, sql_file, helm_enabled):
  pxc_users_secret = "my-cluster-secrets"
  pxc_node_0 = "cluster1-pxc-0"
  if helm_enabled:
    pxc_users_secret="my-db-pxc-db"
    pxc_node_0 = "my-db-pxc-db-pxc-0"

  pwd = extract_secret_password(ns, pxc_users_secret, "root")
  root_cluster_pxc = ["kubectl", "-n", ns, "exec", "-i", pxc_node_0, "-c", "pxc", "--", "env", "LANG=C.utf8", "MYSQL_HISTFILE=/tmp/.mysql_history", "mysql", "-uroot", "-p"+pwd]
  s = subprocess.list2cmdline(root_cluster_pxc) + " < " + subprocess.list2cmdline([sql_file])
  run_fatal(["sh", "-c", s], "Can't apply sql file")


def populate_db(args):
  if args.operator_name == "percona-server-mongodb-operator":
    populate_mongodb(args.namespace, args.js_file)
  if args.operator_name == "percona-postgresql-operator":
    populate_pg_db(args.namespace, args.sql_file)
  if args.operator_name == "percona-xtradb-cluster-operator":
    populate_pxc_db(args.namespace, args.sql_file, args.helm)

def operator_info(args):
  if args.operator_name == "percona-server-mongodb-operator":
    info_mongo_operator(args.namespace)
  if args.operator_name == "percona-postgresql-operator":
    info_pg_operator(args.namespace)
  if args.operator_name == "percona-xtradb-cluster-operator":
    info_pxc_operator(args.namespace, args.helm)

def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--operator", dest="operator_name", type=str, default="percona-postgresql-operator")
  parser.add_argument("--version", dest="operator_version", type=str, default="1.1.0")
  parser.add_argument('--cert-manager', dest="cert_manager", type=str, default="")
  parser.add_argument('--cluster-domain', dest="cluster_domain", type=str, default="cluster.local")
  parser.add_argument('--pmm', dest="pmm", type=str, default="")
  parser.add_argument('--pmm-password', dest="pmm_password", type=str, default="verysecretpassword1^")
  parser.add_argument('--minio', dest="minio", action='store_true')
  parser.add_argument('--minio-certs', dest="minio_certs", type=str, default="")
  parser.add_argument('--namespace', dest="namespace", type=str, default="")
  parser.add_argument('--sql', dest="sql_file", type=str, default="")
  parser.add_argument('--js', dest="js_file", type=str, default="")
  parser.add_argument('--info-only', dest="info", action='store_true')
  parser.add_argument('--smart-update', dest="smart_update", action='store_true')
  parser.add_argument('--helm', dest="helm", action='store_true')
  args = parser.parse_args()

  args.anydbver_path = (Path(__file__).parents[1]).resolve()
  args.helm_path = (Path(__file__).parents[1] / 'data' / 'helm').resolve()
  args.data_path = (Path(args.anydbver_path) / 'data' / 'k8s').resolve()
  args.conf_path = (Path(__file__).resolve().parents[2] / 'configs' / 'k8s').resolve()
  args.yq = str((Path(__file__).parents[0] / 'yq').resolve())

  if args.namespace == "":
    args.namespace = get_operator_ns(args.operator_name)

  if not args.info:
    if args.helm:
      setup_operator_helm(args)
    else:
      setup_operator(args)

  if args.sql_file != "":
    populate_db(args)
  operator_info(args)

  logger.info("Success")

if __name__ == '__main__':
  main()
