#!/usr/bin/env python3
import os
import subprocess
import logging
from pathlib import Path
import shutil
import time
import datetime
import re
from distutils.version import StrictVersion
import argparse
import base64
import urllib
import urllib.parse
import json

COMMAND_TIMEOUT=600

FORMAT = '%(asctime)s %(levelname)s %(message)s'
logging.basicConfig(format=FORMAT)
logger = logging.getLogger('run k8s operator')
logger.setLevel(logging.INFO)
yq_path = str((Path(__file__).parents[0] / 'yq').resolve())

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
    raise Exception((err_msg+" '{}'").format(subprocess.list2cmdline(args)))
  return ret_code

def set_yaml(yq_cmd, err_msg, yaml_file = "./deploy/cr.yaml"):
  run_fatal( [ yq_path, yq_cmd, "-i", yaml_file], err_msg)

def run_get_line(args,err_msg, ignore_msg=None, print_cmd=True, env=None, keep_stderr=True):
  if print_cmd:
    logger.info(subprocess.list2cmdline(args))
  stderr_stream = None
  if keep_stderr: 
    stderr_stream = subprocess.STDOUT
  process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=stderr_stream, close_fds=True, env=env)
  ret_code = process.wait(timeout=COMMAND_TIMEOUT)
  output = process.communicate()[0].decode('utf-8')
  if ignore_msg and re.search(ignore_msg, output):
    return output
  if ret_code:
    logger.error(output)
    raise Exception((err_msg+" '{}'").format(subprocess.list2cmdline(args)))
  return output
  

def k8s_wait_for_ready(ns, labels, timeout=COMMAND_TIMEOUT):
  logger.info("Waiting for: kubectl wait --for=condition=ready -n {} pod -l {}".format(ns, labels))
  for _ in range(timeout // 2):
    s = datetime.datetime.now()
    if run_fatal(["kubectl", "wait", "--timeout=2s", "--for=condition=ready", "-n", ns, "pod", "-l", labels],
        "Pod ready wait problem",
        r"timed out waiting for the condition on|no matching resources found", False) == 0:
      return True
    if (datetime.datetime.now() - s).total_seconds() < 1.5:
      time.sleep(2)
  return False

def k8s_wait_for_job_complete(ns, jobname, timeout=COMMAND_TIMEOUT):
  logger.info("Waiting for: kubectl wait --for=condition=complete -n {} {}".format(ns, jobname))
  for _ in range(timeout // 2):
    s = datetime.datetime.now()
    if run_fatal(["kubectl", "-n", ns, "wait", "--for=condition=complete", jobname], "Job complete wait failed",
        r"not found|timed out waiting for the condition|no matching resources found", False) == 0:
      return True
    if (datetime.datetime.now() - s).total_seconds() < 1.5:
      time.sleep(2)
  return False

def k8s_wait_for_job_complete_label(ns, label, timeout=COMMAND_TIMEOUT):
  logger.info("Waiting for: kubectl wait --for=condition=complete -n  {} job -l {}".format(ns, label))
  for _ in range(timeout // 2):
    s = datetime.datetime.now()
    if run_fatal(["kubectl", "-n", ns, "wait", "--for=condition=complete", "job", "-l", label], "Job complete wait failed",
        r"not found|timed out waiting for the condition|no matching resources found", False) == 0:
      return True
    if (datetime.datetime.now() - s).total_seconds() < 1.5:
      time.sleep(2)
  return False

def wait_for_success(cmd_with_args, fail_with_msg,ignore_error_pattern, timeout=COMMAND_TIMEOUT):
  logger.info("Waiting for: {}".format(subprocess.list2cmdline(cmd_with_args)))
  for _ in range(timeout // 2):
    s = datetime.datetime.now()
    if run_fatal(cmd_with_args,
        fail_with_msg,
        ignore_error_pattern, False) == 0:
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
  if ver == 'main' or ver[0] == 'v' or ('.' not in ver) or (not ver[0].isdigit()):
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
    run_fatal(["git", "fetch", "--all"], "Can't fetch new changes from operator repository at {}".format(os.getcwd()))
    run_fatal(["git", "reset", "--hard"], "Can't reset operator repository")
    run_fatal(["git", "checkout", branch_name(operator_version)], "Can't checkout operator repository")

def get_containers_list(ns,labels):
  return list(run_get_line(["kubectl", "get", "pods", "-n", ns, "-l", labels, "-o", r'jsonpath={range .items[*]}{.metadata.name }{"\n"}{end}'], "Can't get pod name").splitlines())

def info_pg_operator(ns,cluster_name):
  print("kubectl -n {} get PerconaPGCluster {}".format(subprocess.list2cmdline([ns]), subprocess.list2cmdline([cluster_name])))
  for container in get_containers_list(ns,"name={}".format(cluster_name)) + get_containers_list(ns,"name={}-replica".format(cluster_name)):
    if container != "":
      print("kubectl -n {} exec -it {} -- env PSQL_HISTORY=/tmp/.psql_history psql -U postgres".format(
        subprocess.list2cmdline([ns]), container))

def run_pg_operator(ns, op, db_ver, cluster_name, op_ver, standby, backup_type, bucket, gcs_key, db_replicas, tls):
  if op_ver.startswith("1.") or op_ver.startswith("2.0.") or op_ver.startswith("2.1."):
    run_fatal(["sed", "-i", "-re", r"s/namespace: pgo\>/namespace: {}/".format(ns), "./deploy/operator.yaml"], "fix namespace in yaml")
    run_fatal(["sed", "-i", "-re", r's/namespace: "pgo"/namespace: "{}"/'.format(ns), "./deploy/operator.yaml"], "fix namespace in yaml")
  run_fatal(["sed", "-i", "-re", r"s/namespace: pgo\>/namespace: {}/".format(ns), "./deploy/cr.yaml"], "fix namespace in yaml")
  if standby:
    run_fatal(["sed", "-i", "-re", r"s/standby: false\>/standby: true/", "./deploy/cr.yaml"], "enable standby in yaml")
  if db_ver != "":
    run_fatal(["sed", "-i", "-re", r"s/ppg[0-9.]+/ppg{}/".format(db_ver), "./deploy/cr.yaml"], "change PG major version in images")
    set_yaml('.spec.postgresVersion={dbver}'.format(dbver=db_ver),"change PG major version")
  if tls and op_ver.startswith("1"):
    set_yaml('.spec.tlsOnly=true \
        | .spec.sslCA="{name}-ssl-ca" \
        | .spec.sslSecretName="{name}-ssl-keypair" \
        | .spec.sslReplicationSecretName="{name}-ssl-keypair"'.format(name=cluster_name),
             "enable TLS encryption")

  if db_replicas and op_ver.startswith("1"):
    set_yaml('.spec.pgReplicas.hotStandby.size={replicas}'.format(replicas=db_replicas),"Change number of replicas")
  if db_replicas and op_ver.startswith("2"):
    set_yaml('.spec.instances[0].replicas={replicas}'.format(replicas=int(db_replicas)+1),
             "Change number of replicas")

  if backup_type == "gcs":
    run_fatal(["kubectl", "-n", ns, "create", "secret", "generic", "{}-backrest-repo-config".format(cluster_name), "--from-file=gcs-key={}".format(gcs_key)], "Can't create gcs secrets from file")
    set_yaml('.spec.backup.storages["my-gcs"].type = "gcs", .spec.backup.storages["my-gcs"].bucket = "{bucket}" '.format(bucket=bucket),
             "Enable GCS backups")
  if file_contains('./deploy/cr.yaml','.percona.com/v2'):
    op_env = os.environ.copy()
    op_env["PGO_NAMESPACE"] = ns
    op_env["PGO_TARGET_NAMESPACE"] = ns
    run_fatal(["kubectl", "create", "-n", ns, "-f", "./deploy/bundle.yaml"], "Can't deploy operator", r"already exists", env=op_env)
    if StrictVersion(op_ver) > StrictVersion("2.1.0"):
      if not k8s_wait_for_ready(ns, "pgv2.percona.com/control-plane=postgres-operator"):
        raise Exception("Kubernetes operator is not starting")
    elif not k8s_wait_for_ready(ns, "pg.percona.com/control-plane=postgres-operator"):
      raise Exception("Kubernetes operator is not starting")
  else:
    run_fatal(["kubectl", "apply", "-n", ns, "-f", "./deploy/operator.yaml"], "Can't deploy operator")
    if not k8s_wait_for_ready(ns, "name=postgres-operator"):
      raise Exception("Kubernetes operator is not starting")
    time.sleep(30)

  run_fatal(["kubectl", "apply", "-n", ns, "-f", "./deploy/cr.yaml"], "Can't deploy cluster")
  if not k8s_wait_for_ready(ns, cluster_labels(op, op_ver, cluster_name)):
    raise Exception("cluster is not starting")

def op_labels(op, op_ver):
  if (op in ("percona-xtradb-cluster-operator", "pxc-operator")
      and (not re.match(r'^[0-9\.]*$', op_ver)
           or StrictVersion(op_ver) > StrictVersion("1.6.0") ) ):
    return "app.kubernetes.io/name="+op
  elif op == "ps-operator":
    return "app.kubernetes.io/name=ps-operator"
  elif op == "percona-server-mysql-operator":
    return "app.kubernetes.io/name=percona-server-mysql-operator"
  elif op == "psmdb-operator":
    return "app.kubernetes.io/name=psmdb-operator"
  else:
    return "name="+op

def cluster_labels(op, op_ver, cluster_name):
  if op == "percona-xtradb-cluster-operator":
    return "app.kubernetes.io/instance={},app.kubernetes.io/component=pxc".format(cluster_name)
  elif op == "percona-server-mysql-operator":
    return "statefulset.kubernetes.io/pod-name=cluster1-mysql-0"
  elif op == "percona-server-mongodb-operator":
    return "app.kubernetes.io/instance={},app.kubernetes.io/component=mongod".format(cluster_name)
  elif op == "percona-postgresql-operator":
    if op_ver.startswith("2"):
      return "postgres-operator.crunchydata.com/cluster={},postgres-operator.crunchydata.com/role=master".format(cluster_name)
    else:
      return "name={}".format(cluster_name)


def file_contains(file, s):
  with open(file) as f:
    if s in f.read():
      return True
  return False

def run_percona_operator(ns, op, op_ver, cluster_name):
  run_fatal(["kubectl", "apply", "--server-side=true", "-n", ns, "-f", "./deploy/bundle.yaml"], "Can't deploy operator", ignore_msg=r"is invalid: status.storedVersions\[[0-9]+\]: Invalid value")
  if not k8s_wait_for_ready(ns, op_labels(op, op_ver)):
    raise Exception("Kubernetes operator is not starting")
  run_fatal(["kubectl", "apply", "-n", ns, "-f", "./deploy/cr.yaml"], "Can't deploy cluster")
  if not k8s_wait_for_ready(ns, cluster_labels(op, op_ver, cluster_name)):
    raise Exception("cluster is not starting")

def cert_manager_ver_compat(operator_name, operator_version, cert_manager):
  if StrictVersion(cert_manager) <= StrictVersion("1.5.5"):
    return cert_manager
  if operator_name == "percona-server-mongodb-operator" and operator_version != "main" and StrictVersion(operator_version) < StrictVersion("1.12.0"):
    logger.info("Downgrading cert manager version to v1.5.5 supported by {} {}".format(operator_name, operator_version))
    return "1.5.5"
  else:
    return cert_manager

def run_cert_manager(ver):
  run_fatal(["kubectl", "apply", "--server-side=true", "-f", "https://github.com/cert-manager/cert-manager/releases/download/v{}/cert-manager.crds.yaml".format(ver)], "Can't deploy cert-manager.crds.yaml:"+ver)
  run_fatal(["kubectl", "apply", "--server-side=true", "-f", "https://github.com/cert-manager/cert-manager/releases/download/v{}/cert-manager.yaml".format(ver)], "Can't deploy cert-manager:"+ver)
  if not k8s_wait_for_ready("cert-manager", "app.kubernetes.io/name=cert-manager"):
    raise Exception("Cert-manager is not starting")
  if not k8s_wait_for_ready("cert-manager", "app.kubernetes.io/name=webhook"):
    raise Exception("Cert-manager is not starting webhook")
  if not k8s_wait_for_ready("cert-manager", "app.kubernetes.io/name=cainjector"):
    raise Exception("Cert-manager is not starting cainjector")
  msg = run_get_line(
    [
      "kubectl", "run", "-i", "--rm", "--restart=Never", "cert-manager-webook-test", "--image=curlimages/curl", "--",
      "curl", "-ks", "https://cert-manager-webhook.cert-manager.svc:443/mutate"],
      "call cert-manager webhook", r"Bad Request")
  logger.info("cert-manager webhook returns: {}".format(msg))


def run_kube_fledged_helm(helm_path):
  run_fatal(["kubectl", "create", "namespace", "kube-fledged" ], "Can't create a namespace for kube-fledged")
  run_helm(helm_path, ["helm", "repo", "add", "kubefledged-charts", "https://senthilrch.github.io/kubefledged-charts/"], "helm repo add problem")
  run_helm(helm_path, ["helm", "install", "kube-fledged", "-n", "kube-fledged", "--wait", "kubefledged-charts/kube-fledged"], "helm kube-fledged install problem")

def run_cert_manager_helm(helm_path, ver):
  run_helm(helm_path, ["helm", "repo", "add", "jetstack", "https://charts.jetstack.io"], "helm repo add problem")
  run_helm(helm_path, ["helm", "repo", "update", "jetstack"], "helm repo update problem")
  run_helm(helm_path, ["helm", "install", "cert-manager", "jetstack/cert-manager",
    "--namespace", "cert-manager",
    "--create-namespace",
    "--version", ver,
    "--set", "installCRDs=true" ],
    "helm cert-manager install problem")
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
  run_fatal(["mkdir", "-p", str(helm_path / "cache"), str(helm_path / "config"), str(helm_path / "data")], "can't create directories for helm")
  helm_env = os.environ.copy()
  helm_env["HELM_CACHE_HOME"] = str((helm_path / 'cache').resolve())
  helm_env["HELM_CONFIG_HOME"] = str((helm_path / 'config').resolve())
  helm_env["HELM_DATA_HOME"] = str((helm_path / 'data').resolve())
  environ_txt = "export"
  for key in ("HELM_CACHE_HOME","HELM_CONFIG_HOME","HELM_DATA_HOME"):
      environ_txt = environ_txt + " " + key + "=" + subprocess.list2cmdline([helm_env[key] ])
  logger.info(environ_txt)
  run_fatal(cmd, msg, ignore_msg="cannot re-use a name that is still in use", env=helm_env)

def gen_wildcard_ns_self_signed_cert(args, ns):
  svc_name = "ingress-default"
  cert_name = "ingress-default"
  svc_fqdn = "{ns}.svc.{cluster_domain}".format(ns=ns, cluster_domain=args.cluster_domain)
  cert_yaml_path = str((Path(args.data_path) / (cert_name+".yaml")).resolve())
  os.makedirs(args.data_path, exist_ok=True)
  cert_yaml = """apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigning-issuer
spec:
  selfSigned: {{}}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {svc_name}-tls
spec:
  commonName: {svc_fqdn}
  secretName: {svc_name}-tls
  dnsNames:
    # Ingress domain
    - {svc_fqdn}
    # Internal domain
    - "*.{ns}.svc.{cluster_domain}"
    - "{ns}.svc.{cluster_domain}"
    - "*.{cluster_domain}"
  issuerRef:
    name: selfsigning-issuer""".format(svc_fqdn=svc_fqdn, svc_name=svc_name, ns=ns, cluster_domain=args.cluster_domain)
  with open(cert_yaml_path,"w+") as f:
            f.writelines(cert_yaml)

  run_fatal(["kubectl", "apply", "-f", cert_yaml_path], "Can't create {} certificates".format(svc_name))



def gen_self_signed_cert(args, svc_fqdn, ns, svc_name, cert_name):
  cert_yaml_path = str((Path(args.data_path) / (cert_name+".yaml")).resolve())
  os.makedirs(args.data_path, exist_ok=True)
  cert_yaml = """apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigning-issuer
spec:
  selfSigned: {{}}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {svc_name}-tls
spec:
  commonName: {svc_fqdn}
  secretName: {svc_name}-tls
  dnsNames:
    # Ingress domain
    - {svc_fqdn}
    # Internal domain
    - "{svc_name}.{ns}.svc.{cluster_domain}"
  issuerRef:
    name: selfsigning-issuer""".format(svc_fqdn=svc_fqdn, svc_name=svc_name, ns=ns, cluster_domain=args.cluster_domain)
  with open(cert_yaml_path,"w+") as f:
            f.writelines(cert_yaml)

  run_fatal(["kubectl", "--namespace", ns, "apply", "-f", cert_yaml_path], "Can't create {} certificates".format(svc_name))

def run_pmm_server(args, helm_path, pmm):
  if args.operator_name != "":
    return
  tls_key_path = ""
  tls_crt_path = ""

  if "certificates" in pmm:
    tls_key_path = Path(args.anydbver_path) / pmm["certificates"] / "tls.key"
    tls_crt_path = Path(args.anydbver_path) / pmm["certificates"] / "tls.crt"

  if "namespace" in pmm:
    run_fatal(["kubectl", "create", "namespace", pmm["namespace"] ],
        "Can't create a namespace for the cluster", r"from server \(AlreadyExists\)")
  else:
    pmm["namespace"] = "default";

  args.pmm_custom_ssl = ("certificates" in pmm 
      and pmm["certificates"] != "self-signed"
      and isinstance(tls_key_path, Path) and tls_key_path.is_file()
      and isinstance(tls_crt_path, Path) and tls_crt_path.is_file())

  if args.cert_manager != "" and pmm["certificates"] == "self-signed":
    gen_self_signed_cert(args, "pmm." + args.cluster_domain, pmm["namespace"], "monitoring-service", "pmm-certs")
  elif args.pmm_custom_ssl and isinstance(tls_key_path, Path) and isinstance(tls_crt_path, Path):
    run_fatal(["kubectl", "create", "secret", "tls", "monitoring-service-tls",
      "--key="+str(tls_key_path.resolve()),
      "--cert="+str(tls_crt_path.resolve())],
      "can't create minio tls secret", "already exists")

  if k8s_check_ready(pmm["namespace"], "app=monitoring,component=pmm"):
    return
  run_helm(helm_path, ["helm", "repo", "add", pmm["helm_repo_name"], pmm["helm_repo_url"] ], "helm repo add problem")
  run_helm(helm_path, ["helm", "repo", "update", pmm["helm_repo_name"] ], "helm repo update problem")

  if pmm["helm_repo_name"] == "percona":
    helm_pmm_install_cmd = ["helm", "install", "monitoring", "percona/pmm",
      "--set", "secret.pmm_password="+pmm["password"],
      "--set", "service.type=ClusterIP",
      "--set", "image.tag="+pmm["version"] ]
  else:
    helm_pmm_install_cmd = ["helm", "install", "monitoring", "perconalab/pmm-server",
      "--set", "credentials.username=admin", "--set", "credentials.password="+pmm["password"],
      "--set", "service.type=ClusterIP",
      "--set", "imageTag="+pmm["version"], "--set", "platform=kubernetes"]

  helm_env = os.environ.copy()
  helm_env["HELM_CACHE_HOME"] = str((helm_path / 'cache').resolve())
  helm_env["HELM_CONFIG_HOME"] = str((helm_path / 'config').resolve())
  helm_env["HELM_DATA_HOME"] = str((helm_path / 'data').resolve())


  # get latest chart minor version:
  # helm search repo perconalab/pmm-server --versions -o yaml | yq '[.[] | sort_keys(.version) | select( .version == "2.29.*")][0].version
  if "helm_chart_version" not in pmm:
    if pmm["helm_repo_name"] == "percona":
      pmm["helm_chart_version"] = run_get_line(["bash", "-c", r"""helm search repo {repo} --versions -o yaml | {yq} '[.[] | sort_keys(.app_version) | select( .app_version == "{ver}")][0].version'""".format(yq=args.yq,repo="percona/pmm",ver=pmm["version"] )],
        "Can't get latest chart version", env=helm_env).rstrip()
    elif StrictVersion(pmm["version"]) == StrictVersion("2.27.0"):
      pmm["helm_chart_version"] = "2.26.1"
    else:
      pmm["helm_chart_version"] = run_get_line(["bash", "-c", "helm search repo {repo} --versions -o yaml | {yq} '[.[] | sort_keys(.version) | select( .version == \"{ver}.*\")][0].version'".format(yq=args.yq,repo="perconalab/pmm-server",ver=pmm["version"][:pmm["version"].rfind(".")])],
        "Can't get latest chart version", env=helm_env).rstrip()

  helm_pmm_install_cmd.append("--version")
  helm_pmm_install_cmd.append(pmm["helm_chart_version"])

  if "namespace" in pmm:
    helm_pmm_install_cmd.append("--namespace")
    helm_pmm_install_cmd.append(pmm["namespace"])
  else:
    helm_pmm_install_cmd.append("--namespace")
    helm_pmm_install_cmd.append("default")

  if pmm["dbaas"]:
    helm_pmm_install_cmd.append("--set-string")
    helm_pmm_install_cmd.append('pmmEnv.ENABLE_DBAAS=1')
    helm_pmm_install_cmd.append("--set-string")
    helm_pmm_install_cmd.append('pmmEnv.ENABLE_BACKUP_MANAGEMENT=1')

  run_helm(helm_path, helm_pmm_install_cmd,
    "helm pmm install problem")
  if not k8s_wait_for_ready(pmm["namespace"], pmm["labels"]):
    raise Exception("PMM Pod is not starting")
  if pmm["helm_repo_name"] != "percona":
    time.sleep(10)
    run_fatal(["kubectl", "-n", pmm["namespace"],
        "exec", "-it", "monitoring-0", "--", "bash", "-c",
        "grafana-cli --homepath /usr/share/grafana --configOverrides cfg:default.paths.data=/srv/grafana admin reset-admin-password \"$ADMIN_PASSWORD\""],
        "can't fix pmm password")

  pass_encoded = urllib.parse.quote_plus(args.pmm["password"])
  if args.loki:
    msg = run_get_line(
      [
        "kubectl", "run", "-i", "--rm", "--restart=Never", "loki-pmm-setup", "--image=curlimages/curl", "--",
        "curl", "-i", "http://admin:"+pass_encoded+"@monitoring-service."+pmm["namespace"]+".svc.cluster.local/graph/api/datasources",
        "-X", "POST", "-H", "Content-Type: application/json;charset=UTF-8",
        "--data-binary", """{"orgId": 1, "name": "Loki", "type": "loki", "typeLogoUrl": "", "access": "proxy", "url": "http://loki-stack.loki-stack.svc.cluster.local:3100", "password": "", "user": "", "database": "", "basicAuth": false, "basicAuthUser": "", "basicAuthPassword": "", "withCredentials": false, "isDefault": false, "jsonData": {}, "secureJsonFields": {}, "version": 1, "readOnly": false }""" ], "can't setup loki datasource", r"data source with the same name already exists")
    logger.info("Added loki to PMM: {}".format(msg))
  if pmm["dbaas"]:
    msg = ""
    # sleep 10; kubectl run -i --rm --restart=Never percona-dbaas-setup --image=curlimages/curl -- curl -i http://admin:"""+pass_encoded+"""@monitoring-service."""+pmm["namespace"]+""".svc.cluster.local/v1/management/DBaaS/Kubernetes/UnRegister --header 'Accept: application/json' --data "{ \\"kubernetes_cluster_name\\": \\"default-pmm-cluster\\" }" ; 
    # kubectl run -i --rm --restart=Never percona-dbaas-setup --image=curlimages/curl -- curl -i http://admin:"""+pass_encoded+"""@monitoring-service."""+pmm["namespace"]+""".svc.cluster.local/v1/Settings/Change --header 'Accept: application/json' --data '{"enable_dbaas": true}';kubectl run -i --rm --restart=Never percona-dbaas-setup --image=curlimages/curl -- curl -i http://admin:"""+pass_encoded+"""@monitoring-service."""+pmm["namespace"]+""".svc.cluster.local/v1/Settings/Change --header 'Accept: application/json' --data '{"enable_backup_management": true}';
    #msg = run_get_line(
    #  ["bash", "-c", """kubectl run -i --rm --restart=Never percona-dbaas-setup --image=curlimages/curl -- curl -i http://admin:"""+pass_encoded+"""@monitoring-service."""+pmm["namespace"]+""".svc.cluster.local/v1/management/DBaaS/Kubernetes/Register --header 'Accept: application/json' --data "{ \\"kubernetes_cluster_name\\": \\"my-cluster\\", \\"kube_auth\\": { \\"kubeconfig\\": \\"$(kubectl config view --flatten --minify | sed -e ':a' -e 'N' -e '$!ba' -e 's/\\n/\\\\n/g' -re 's/0\.0\.0\.0:[0-9]+/kubernetes.default.svc.cluster.local:443/')\\" }}" """],
    #  "Cann't enable DBaaS"
    #)
    logger.info("Added DBaaS to PMM: {}".format(msg))

def soft_params(opt):
  params = {}
  (operator_version, operator_params) = opt.split(",",1)
  params["version"] = operator_version
  for param in operator_params.split(","):
    if param.startswith("name="):
      params["cluster-name"] = param.split("=",1)[1]
    if param.startswith("helm="):
      params["helm"] = param.split("=",1)[1]
    if param.startswith("dns="):
      params["dns"] = param.split("=",1)[1]
    elif param == "helm":
      params["helm"] = 'True'
    if param.startswith("certs="):
      params["certs"] = param.split("=",1)[1]
    elif param == "certs":
      params["certs"] = 'self-signed'
    if param.startswith("namespace=") or param.startswith("ns=") :
      params["namespace"] = param.split("=",1)[1]
    if param.startswith("sql=") or param.startswith("s3sql=") :
      params["sql"] = param.split("=",1)[1]
    if param.startswith("backup-type=") or param.startswith("backup_type=") :
      params["backup-type"] = param.split("=",1)[1]
    if param.startswith("bucket="):
      params["bucket"] = param.split("=",1)[1]
    if param.startswith("gcs-key="):
      params["gcs-key"] = param.split("=",1)[1]
    if param.startswith("standby"):
      if '=' in param and param.startswith("standby="):
        params["standby"] = param.split("=",1)[1]
      else:
        params["standby"] = True
    if param.startswith("proxysql"):
      if '=' in param and param.startswith("proxysql="):
        params["proxysql"] = param.split("=",1)[1]
      else:
        params["proxysql"] = True

  return params



def run_minio_server(args):
  params = soft_params(args.minio)
  if "certs" in params:
    args.minio_certs = params["certs"]

  if args.operator_name != "":
    return
  logger.info( "Certificates for minio: " + str(args.minio_certs))
  tls_key_path = Path(args.anydbver_path) / args.minio_certs / "tls.key"
  tls_crt_path = Path(args.anydbver_path) / args.minio_certs / "tls.crt"
  if args.minio_certs != "" and args.minio_certs != "self-signed":
    logger.info("Loading minio secrets from {} and {}".format(str(tls_key_path.resolve()), str(tls_crt_path.resolve())))

  args.minio_custom_ssl = (args.minio_certs != "" 
      and args.minio_certs != "self-signed"
      and tls_key_path.is_file()
      and tls_crt_path.is_file())

  if args.cert_manager != "" and args.minio_certs == "self-signed":
    gen_self_signed_cert(args, "s3." + args.cluster_domain, "default", "minio-service", "minio-certs")
  elif args.minio_custom_ssl:
    run_fatal(["kubectl", "create", "secret", "tls", "minio-service-tls",
      "--key="+str(tls_key_path.resolve()),
      "--cert="+str(tls_crt_path.resolve())],
      "can't create minio tls secret", "already exists")

  run_helm(args.helm_path, ["helm", "repo", "add", "bitnami", "https://charts.bitnami.com/bitnami"], "helm repo add problem")
  run_helm(args.helm_path, ["helm", "repo", "update", "bitnami"], "helm repo update problem")
  helm_cmd = ["helm", "install", "minio-service", "bitnami/minio",
      "--set", "fullnameOverride=minio-service",
      "--set", "auth.rootUser=REPLACE-WITH-AWS-ACCESS-KEY",
      "--set", "auth.rootPassword=REPLACE-WITH-AWS-SECRET-KEY",
      "--set", "service.type=ClusterIP",
      "--set", "persistence.size=2G", "--set", "defaultBuckets=operator-testing"
      ]

  if args.ingress != "" and "dns" in params:
    helm_cmd = helm_cmd + [
      "--set", "ingress.enabled=true",
      "--set", "ingress.ingressClassName={}".format(args.ingress),
      "--set", "ingress.tls=true",
      "--set", "ingress.selfSigned=true",
      "--set", "ingress.hostname={}".format(params["dns"])
      ]
  if (args.cert_manager != "" and args.minio_certs == "self-signed") or args.minio_custom_ssl:
    helm_cmd = helm_cmd + ["--set", "tls.enabled=true", "--set", "tls.autoGenerated=true", "--set", "service.ports.api=443"]
    run_helm(args.helm_path, helm_cmd , "helm minio+certs install problem")
    if args.ingress == "nginx" and "dns" in params:
      run_fatal(["kubectl", "annotate", "ing/minio-service", "nginx.org/ssl-services=minio-service"], "Can't annotate ingress to use ssl service")
  else:
    helm_cmd = helm_cmd + ["--set", "tls.enabled=false"]
    run_helm(args.helm_path, helm_cmd, "helm minio install problem")

def merge_cr_yaml(yq, cr_path, part_path):
  cmd = yq + " ea '. as $item ireduce ({}; . * $item )' " + cr_path + " " + part_path + " > " + cr_path + ".tmp && mv " + cr_path + ".tmp " + cr_path
  logger.info(cmd)
  os.system(cmd)

def yq_cmd_cr_yaml(yq, cr_path, yq_cmd):
  cmd = yq + " '" + yq_cmd + "' " + cr_path + " > " + cr_path + ".tmp && mv " + cr_path + ".tmp " + cr_path
  logger.info(cmd)
  os.system(cmd)

def kubectl_run_curl(ns, job_name, curl_args):
  cmd = [
    "kubectl", "-n", ns, "create", "job", job_name , "--image=curlimages/curl", "--"]
  cmd.extend(curl_args)
  run_fatal(cmd,
    "Can't run curl job {}.{}".format(ns,job_name))
  k8s_wait_for_job_complete(ns ,"job/{}".format(job_name))
  resp = run_get_line([
    "kubectl", "-n", ns, "logs", "-l", "job-name={}".format(job_name)],
    "Can't create PMM api key", keep_stderr=False)
  run_fatal([
    "kubectl", "-n", ns, "delete", "job", "--wait", job_name],
    "Can't delete curl job {}.{}".format(ns,job_name))
  return resp

def create_pmm_api_key(args, secret_name, secret_item_name):
  if args.pmm != "":
    pmm_sett = {}
    if type(args.pmm) == str:
      pmm_sett = parse_settings("pmm", args.pmm)
    else:
      pmm_sett = args.pmm

    pmm_ns = "default"
    pmm_pass = "verysecretpassword1^"
    if "namespace" in pmm_sett:
      pmm_ns = pmm_sett["namespace"]
    if "ns" in pmm_sett:
      pmm_ns = pmm_sett["ns"]
    if "password" in pmm_sett:
      pmm_pass = pmm_sett["password"]

    pass_encoded = urllib.parse.quote_plus(pmm_pass)

    pmm_url = "http://admin:{password}@monitoring-service.{ns}.svc.{cluster_domain}/graph".format(
        password=pass_encoded, ns=pmm_ns, cluster_domain=args.cluster_domain)

    #wait_for_success( ["kubectl", "run", "-i", "--rm", "--restart=Never", "wait-for-pmm-startup-{}".format(args.cluster_name), "--image=curlimages/curl", "--", "curl", "-s", "-f", pmm_url + "/api/admin/stats",], "can't access pmm", "")

    resp = ''
    while True:
      resp = kubectl_run_curl(args.namespace, "create-pmm-api-key-{}".format(args.cluster_name), ["curl", "-s", pmm_url + "/api/auth/keys",
        "-X", "POST", "-H", "Content-Type: application/json", "-d", '{"name":"' + re.sub('[^A-Za-z0-9]+', '', secret_name) +'", "role": "Admin"}'])
      logger.info("Generated PMM key: '{}'".format(resp))
      if resp != '':
        break
    apikey = base64.b64encode(bytes(json.loads(resp)["key"], 'utf-8')).decode('utf-8')
    run_fatal([
      "kubectl", "-n", args.namespace, "patch", "secret/{}".format(secret_name),
      "-p", '{"data":{"'+secret_item_name+'": "'+apikey+'"} }' ],
      "Can't set PMM API key")

def enable_pmm(args):
  if args.pmm == "":
    return
  deploy_path = Path(args.data_path) / args.operator_name / "deploy" 
  pmm_secret_path = str((deploy_path / "cr-pmm-secret.yaml").resolve()) 
  pmm_enable_path = str((deploy_path / "cr-pmm-enable.yaml").resolve()) 

  pmm_enable_yaml = ""

  if (args.operator_name == "percona-server-mongodb-operator" and StrictVersion(args.operator_version) >= StrictVersion("1.13.0")) or (args.operator_name == "percona-postgresql-operator" and StrictVersion(args.operator_version) >= StrictVersion("2.2.0")) :
    pmm_enable_yaml = """\
spec:
  pmm:
    enabled: true
    serverHost: monitoring-service.{pmm_namespace}.svc.{cluster_domain}""".format(pmm_namespace=args.pmm["namespace"], cluster_domain=args.cluster_domain)
  else:
    pmm_enable_yaml = """\
spec:
  pmm:
    enabled: true
    serverUser: admin
    serverHost: monitoring-service.{pmm_namespace}.svc.{cluster_domain}""".format(pmm_namespace=args.pmm["namespace"], cluster_domain=args.cluster_domain)

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
        name: {users_secret}
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
  elif args.operator_name == "percona-postgresql-operator":
    pmm_secrets = """\
apiVersion: v1
data:
  password: {pmm_password}
  username: {pmm_user}
kind: Secret
metadata:
  name: {cluster_name}-pmm-secret
  namespace: {namespace}
type: Opaque
""".format(pmm_password=base64.b64encode(bytes(args.pmm["password"], 'utf-8')).decode('utf-8'), pmm_user=base64.b64encode(bytes('admin', 'utf-8')).decode('utf-8'), cluster_name=args.cluster_name, namespace=args.namespace)
  elif args.operator_name == "percona-server-mongodb-operator":
    pmm_secrets = """
      apiVersion: v1
      kind: Secret
      type: Opaque
      metadata:
        name: {users_secret}
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
            f.writelines(pmm_secrets.format(pmm_password=base64.b64encode(bytes(args.pmm["password"], 'utf-8')).decode('utf-8'), users_secret=args.users_secret))
  run_fatal(["kubectl", "apply", "-n", args.namespace, "-f", pmm_secret_path ], "Can't apply cluster secret secret with pmmserver")
  if args.operator_name == "percona-postgresql-operator" and StrictVersion(args.operator_version) >= StrictVersion("2.2.0"):
      create_pmm_api_key(args, "{cluster_name}-pmm-secret".format(cluster_name=args.cluster_name), "PMM_SERVER_KEY")


def enable_minio(args):
  deploy_path = Path(args.data_path) / args.operator_name / "deploy"
  minio_storage_path = str((deploy_path / "cr-minio.yaml").resolve())
  minio_secret_yaml_path = str((deploy_path / "minio-secret.yaml").resolve())
  minio_cred_path = str((deploy_path / "{}-backrest-repo-config-secret-minio.yaml".format(args.cluster_name)).resolve())
  proto = "http"
  minio_port = 9000
  bucket = "operator-testing"
  if args.bucket != "":
    bucket = args.bucket

  if args.minio_certs != "":
    proto = "https"
    minio_port = 443
  if args.operator_name == "percona-xtradb-cluster-operator":
    minio_storage = """
      spec:
        backup:
          storages:
            minio:
              verifyTLS: false
              type: s3
              s3:
                bucket: {bucket}
                region: us-east-1
                credentialsSecret: my-cluster-name-backup-s3
                endpointUrl: {proto}://minio-service.{minio_namespace}.svc.{cluster_domain}:{minio_port}
      """.format(proto=proto, minio_namespace="default", cluster_domain=args.cluster_domain, minio_port=minio_port, bucket=bucket)
    with open(minio_storage_path,"w+") as f:
      f.writelines(minio_storage)
    minio_secret_yaml = """\
apiVersion: v1
kind: Secret
metadata:
  name: my-cluster-name-backup-s3
type: Opaque
data:
  AWS_ACCESS_KEY_ID: UkVQTEFDRS1XSVRILUFXUy1BQ0NFU1MtS0VZ
  AWS_SECRET_ACCESS_KEY: UkVQTEFDRS1XSVRILUFXUy1TRUNSRVQtS0VZ
"""
    with open(minio_secret_yaml_path,"w+") as f:
      f.writelines(minio_secret_yaml)

    run_fatal(["kubectl", "apply", "-n", args.namespace, "-f", minio_secret_yaml_path], "Can't apply s3 secrets")
    merge_cr_yaml(args.yq, str((Path(args.data_path) / args.operator_name / "deploy" / "cr.yaml").resolve()), minio_storage_path )
  if args.operator_name == "percona-server-mongodb-operator":
    minio_storage = """\
spec:
  backup:
    enabled: true
    storages:
      minio:
        type: s3
        s3:
          bucket: {bucket}
          region: us-east-1
          credentialsSecret: my-cluster-name-backup-s3
          endpointUrl: {proto}://minio-service.{minio_namespace}.svc.{cluster_domain}:{minio_port}
          insecureSkipTLSVerify: true
          prefix: ""
    pitr:
      enabled: true
""".format(proto=proto, minio_namespace="default", cluster_domain=args.cluster_domain, minio_port=minio_port, bucket=bucket)
    with open(minio_storage_path,"w+") as f:
      f.writelines(minio_storage)
    run_fatal(["kubectl", "apply", "-n", args.namespace, "-f", "./deploy/backup-s3.yaml"], "Can't apply s3 secrets")
    merge_cr_yaml(args.yq, str((Path(args.data_path) / args.operator_name / "deploy" / "cr.yaml").resolve()), minio_storage_path )
  if args.operator_name == "percona-postgresql-operator" and ( file_contains('./deploy/cr.yaml','pg.percona.com/v2') or file_contains('./deploy/cr.yaml','pgv2.percona.com/v2') ) and args.backup_type != "gcs":
    cr_yaml_path = str((Path(args.data_path) / args.operator_name / "deploy" / "cr.yaml").resolve())
    run_fatal(
      [
        args.yq,
        '(del(.spec.backups.pgbackrest.repos[0].volume))|'
        '(.spec.backups.pgbackrest.configuration[0].secret.name="{cluster_name}-pgbackrest-secrets")|'
        '(.spec.backups.pgbackrest.repos[0].name="repo1")|'
        '(.spec.backups.pgbackrest.repos[0].s3.bucket="{bucket}")|'
        '(.spec.backups.pgbackrest.repos[0].s3.region="us-east-1")|'
        '(.spec.backups.pgbackrest.repos[0].s3.endpoint="{proto}://minio-service.default.svc.{cluster_domain}:{minio_port}")'.format(
          proto="https", cluster_domain=args.cluster_domain, minio_port=443, cluster_name=args.cluster_name, bucket=bucket),
        "-i",
        cr_yaml_path], "enable minio backups")
    minio_cred_path = str((deploy_path / "{}-backrest-secrets.yaml".format(args.cluster_name)).resolve())
    s3_conf="""\
[global]
repo1-s3-key=REPLACE-WITH-AWS-ACCESS-KEY
repo1-s3-key-secret=REPLACE-WITH-AWS-SECRET-KEY
repo1-storage-verify-tls=n
repo1-s3-uri-style=path
"""
    if args.archive_push_async:
      s3_conf = s3_conf + """\
archive-async=y
spool-path=/pgdata

[global:archive-get]
process-max=2

[global:archive-push]
process-max=4
log-level-stderr=info
"""
    pg_minio_secret_repo = """\
apiVersion: v1
data:
  s3.conf: {s3conf}
kind: Secret
metadata:
  name: {cluster_name}-pgbackrest-secrets
type: Opaque
""".format(s3conf = base64.b64encode(bytes(s3_conf, 'utf-8')).decode('utf-8'), cluster_name=args.cluster_name)
    with open(minio_cred_path,"w+") as f:
      f.writelines(pg_minio_secret_repo)
    run_fatal(["kubectl", "apply", "-n", args.namespace, "-f", minio_cred_path], "Can't apply s3 secrets")

  if args.operator_name == "percona-postgresql-operator" and not ( file_contains('./deploy/cr.yaml','pg.percona.com/v2') or file_contains('./deploy/cr.yaml','pgv2.percona.com/v2') ) and args.backup_type != "gcs":
    if args.minio_certs == "":
      logger.warning("Percona Postgresql Operator MinIO backups requires TLS")
      return

    minio_cred = """\
apiVersion: v1
kind: Secret
metadata:
  name: {cluster_name}-backrest-repo-config
type: Opaque
data:
  aws-s3-key: UkVQTEFDRS1XSVRILUFXUy1BQ0NFU1MtS0VZ
  aws-s3-key-secret: UkVQTEFDRS1XSVRILUFXUy1TRUNSRVQtS0VZ
    """.format(cluster_name=args.cluster_name)
    with open(minio_cred_path,"w+") as f:
      f.writelines(minio_cred)

    minio_storage = """
      spec:
        backup:
          storages:
            minio:
              bucket: {bucket}
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
      """.format(minio_namespace="default", cluster_domain=args.cluster_domain, bucket=bucket)
    with open(minio_storage_path,"w+") as f:
      f.writelines(minio_storage)
    run_fatal(["kubectl", "apply", "-n", args.namespace, "-f",
      minio_cred_path ], "Can't apply s3 secrets", print_cmd=True)
    merge_cr_yaml(args.yq,
        str((Path(args.data_path) / args.operator_name / "deploy" / "cr.yaml").resolve()),
        minio_storage_path)

def setup_operator_helm(args):
  if not k8s_wait_for_ready('kube-system', 'k8s-app=kube-dns'):
    raise Exception("Kubernetes cluster is not available")

  run_fatal(["kubectl", "create", "namespace", args.namespace],
      "Can't create a namespace for the cluster", r"from server \(AlreadyExists\)")

  if args.operator_name == "percona-xtradb-cluster-operator":
    if args.operator_version == "1.11.0":
      logger.warning("Helm operator installation for PXC has a bug, use 1.11.1 https://github.com/percona/percona-helm-charts/commit/2babe0b74b3e47c34db8d334110537c5bd6eeb24")

    run_helm(args.helm_path, ["helm", "repo", "add", "percona", "https://percona.github.io/percona-helm-charts/"], "helm repo add problem")
    run_helm(args.helm_path, ["helm", "install", "my-operator", "percona/pxc-operator", "--version", args.operator_version, "--namespace", args.namespace], "Can't start PXC operator with helm")
    if not args.cluster_name:
      args.cluster_name="my-db"
    if not k8s_wait_for_ready(args.namespace, op_labels("pxc-operator", args.operator_version)):
      raise Exception("Kubernetes operator is not starting")
    
    if args.operator_version == "1.11.0":
      run_fatal(["kubectl", "patch", "deployment", "my-operator-pxc-operator", "--namespace", args.namespace,
        "--type=json", "--patch", '[{"op": "replace", "path": "/spec/template/spec/containers/0/name", "value": "percona-xtradb-cluster-operator"}]'],
          "Can't create a namespace for the cluster")

    if not k8s_wait_for_ready(args.namespace, op_labels("pxc-operator", args.operator_version)):
      raise Exception("Kubernetes operator is not starting")

    pxc_helm_install_cmd = ["helm", "install", args.cluster_name, "percona/pxc-db", "--version", args.operator_version, "--namespace", args.namespace]
    if args.helm_values:
      pxc_helm_install_cmd.extend(["-f", args.helm_values])
    if args.cert_manager:
      pxc_helm_install_cmd.extend(["--set", "pxc.certManager=true"])
    if args.update_strategy:
      pxc_helm_install_cmd.extend(["--set", "updateStrategy={}".format(args.update_strategy)])
    run_helm(args.helm_path, pxc_helm_install_cmd, "Can't start PXC with helm")
    args.cluster_name="{}-pxc-db".format(args.cluster_name)
    args.users_secret= args.cluster_name
    if not k8s_wait_for_ready(args.namespace, "app.kubernetes.io/component=pxc,app.kubernetes.io/instance={}".format(args.cluster_name)):
      raise Exception("cluster is not starting")
  if args.operator_name == "percona-server-mysql-operator":
    run_helm(args.helm_path, ["helm", "repo", "add", "percona", "https://percona.github.io/percona-helm-charts/"], "helm repo add problem")
    run_helm(args.helm_path, ["helm", "install", "my-operator", "percona/ps-operator", "--version", args.operator_version, "--namespace", args.namespace], "Can't start PS MySQL operator with helm")
    args.cluster_name="my-db"
    if not k8s_wait_for_ready(args.namespace, op_labels("ps-operator", args.operator_version)):
      raise Exception("Kubernetes operator is not starting")
    ps_helm_install_cmd = ["helm", "install", args.cluster_name, "percona/ps-db", "--namespace", args.namespace]
    if args.helm_values:
      ps_helm_install_cmd.extend(["-f", args.helm_values])
    run_helm(args.helm_path, ps_helm_install_cmd, "Can't start PS MySQL with helm")
    args.cluster_name="{}-ps-db".format(args.cluster_name)
    if not k8s_wait_for_ready(args.namespace, "app.kubernetes.io/component=mysql,statefulset.kubernetes.io/pod-name={}-mysql-0".format(args.cluster_name), timeout=2*COMMAND_TIMEOUT):
      raise Exception("cluster is not starting")
  if args.operator_name == "percona-postgresql-operator":
    run_helm(args.helm_path, ["helm", "repo", "add", "percona", "https://percona.github.io/percona-helm-charts/"], "helm repo add problem")
    run_helm(args.helm_path, ["helm", "install", "my-operator", "percona/pg-operator",
        "--version", args.operator_version, "--namespace", args.namespace,
        "--create-namespace", "--timeout", "{}s".format(COMMAND_TIMEOUT)] , "Can't start Percona Postgresql operator with helm")
    if not args.cluster_name:
      args.cluster_name="my-db"
    if not k8s_wait_for_ready(args.namespace, op_labels("postgres-operator", args.operator_version)):
      raise Exception("Kubernetes operator is not starting")
    pg_helm_install_cmd = ["helm", "install", args.cluster_name, "percona/pg-db", "--namespace", args.namespace, "--timeout", "{}s".format(COMMAND_TIMEOUT), "--version", args.operator_version]
    if args.db_version and args.db_version.startswith("ppg"):
      pg_helm_install_cmd.extend(["--set", "image.pgver={}".format(args.db_version)])
    elif args.db_version:
      pg_helm_install_cmd.extend(["--set", "pgPrimary.image={}".format(args.db_version)])
    if args.db_replicas:
      pg_helm_install_cmd.extend(["--set", "replicas.size={}".format(args.db_replicas)])
    if args.memory and args.operator_version.startswith("1."):
      pg_helm_install_cmd.extend(["--set", "pgPrimary.resources.requests.memory={}".format(args.memory)])
      pg_helm_install_cmd.extend(["--set", "pgPrimary.resources.limits.memory={}".format(args.memory)])
      pg_helm_install_cmd.extend(["--set", "backup.resources.requests.memory={}".format(args.memory)])
      pg_helm_install_cmd.extend(["--set", "backup.resources.limits.memory={}".format(args.memory)])
      pg_helm_install_cmd.extend(["--set", "replicas.resources.requests.memory={}".format(args.memory)])
      pg_helm_install_cmd.extend(["--set", "replicas.resources.limits.memory={}".format(args.memory)])
    if args.helm_values:
      pg_helm_install_cmd.extend(["-f", args.helm_values])
    run_helm(args.helm_path, pg_helm_install_cmd, "Can't start Postgresql with helm")
    args.cluster_name="{}-pg-db".format(args.cluster_name)
    if not k8s_wait_for_ready(args.namespace, "name={}".format(args.cluster_name)):
      raise Exception("cluster is not starting")
  if args.operator_name == "percona-server-mongodb-operator":
    run_helm(args.helm_path, ["helm", "repo", "add", "percona", "https://percona.github.io/percona-helm-charts/"], "helm repo add problem")
    run_helm(args.helm_path, ["helm", "install", "my-operator", "percona/psmdb-operator",
        "--version", args.operator_version, "--namespace", args.namespace,
        "--create-namespace", "--timeout", "{}s".format(COMMAND_TIMEOUT)], "Can't start Percona Postgresql operator with helm")
    if args.cluster_name == "":
      args.cluster_name="my-db"
    if not k8s_wait_for_ready(args.namespace, op_labels("psmdb-operator", args.operator_version)):
      raise Exception("Kubernetes operator is not starting")
    psmdb_helm_install_cmd = ["helm", "install", args.cluster_name, "percona/psmdb-db", "--namespace", args.namespace, "--timeout", "{}s".format(COMMAND_TIMEOUT), "--version", args.operator_version]
    if args.helm_values:
      psmdb_helm_install_cmd.extend(["-f", args.helm_values])
    run_helm(args.helm_path, psmdb_helm_install_cmd, "Can't start Percona Server for Mongodb with helm")
    args.cluster_name="{}-psmdb-db".format(args.cluster_name)
    if not k8s_wait_for_ready(args.namespace, "app.kubernetes.io/instance={}".format(args.cluster_name)):
      raise Exception("cluster is not starting")
    create_pmm_api_key(args, "{}-secrets".format(args.cluster_name), "PMM_SERVER_API_KEY")
    if args.pmm != "":
      pmm_sett = parse_settings("pmm", args.pmm)
      pmm_ns = "default"
      if "namespace" in pmm_sett:
        pmm_ns = pmm_sett["namespace"]
      if "ns" in pmm_sett:
        pmm_ns = pmm_sett["ns"]

      run_fatal(["kubectl", "-n", args.namespace, "patch", "psmdb", args.cluster_name, "--type=merge", "--patch", '{"spec":{"pmm":{"enabled": true, "serverHost": "'+ "monitoring-service.{ns}.svc.{cluster_domain}".format(ns=pmm_ns,cluster_domain=args.cluster_domain)+'"} } }'],
          "Enable mongodb monitoring with PMM")

def parse_settings(key, sett_cmd):
  # 2.31.0,helm=percona-helm-charts:0.3.9,certs=self-signed,namespace=monitoring,password=verysecretpassword1^
  sett = {}
  sett_arr = sett_cmd.split(',')
  sett["version"] = sett_arr.pop(0)
  for s in sett_arr:
    s_pair = s.split('=',1)
    if len(s_pair) == 2:
      sett[s_pair[0]] = s_pair[1]
    else:
      sett[s_pair[0]] = "True"

  if key == "pmm" and "helm" not in sett:
    sett["helm"] = "True"

  if key == "pmm" and "namespace" not in sett and "ns" not in sett:
    sett["namespace"] = "monitoring"

  if "helm" in sett:
    if sett["helm"] == "True":
      if key == "pmm":
        if StrictVersion(sett["version"]) >= StrictVersion("2.28.0"):
          sett["helm"] = "percona-helm-charts"
        else:
          sett["helm"] = "perconalab"
    helm_pair = sett["helm"].split(':')
    if len(helm_pair) > 1:
      sett["helm_chart_version"] = helm_pair[-1]
      sett["helm"] = helm_pair[0]


  if sett["helm"] == "percona-helm-charts" or sett["helm"] == "percona/percona-helm-charts":
    sett["helm_repo_url"] = "https://percona.github.io/percona-helm-charts/"
    sett["helm_repo_name"] = "percona"
    if key == "pmm":
      sett["helm_chart_name"] = "percona/pmm"
      sett["labels"] = "app.kubernetes.io/component=pmm-server"
  elif sett["helm"] == "perconalab":
    if key == "pmm":
      sett["helm_repo_url"] = "https://percona-charts.storage.googleapis.com/"
      sett["helm_repo_name"] = "perconalab"
      sett["labels"] = "app=monitoring,component=pmm"
  else:
    sett["helm_repo_url"] = sett["helm"]

  if "dbaas" in sett:
    sett["dbaas"] = True
  else:
    sett["dbaas"] = False

  if "certs" in sett:
    sett["certificates"] = "self-signed"

  if "password" not in sett:
      sett["password"] = "verysecretpassword1^"

  return sett


def setup_operator(args):
  data_path = args.data_path

  if args.pmm != "":
    args.pmm = parse_settings("pmm", args.pmm)
    run_pmm_server(args, args.helm_path, args.pmm)

  if args.minio:
    run_minio_server(args)

  if args.operator_name == "":
    return

  cr_yaml_path = str((Path(args.data_path) / args.operator_name / "deploy" / "cr.yaml").resolve())
  prepare_operator_repository(data_path.resolve(), args.operator_name, args.operator_version)
  if not args.smart_update and args.operator_name not in ("percona-server-mysql-operator") \
      and not file_contains(cr_yaml_path,'.percona.com/v2'):
    merge_cr_yaml(args.yq, cr_yaml_path, str((Path(args.conf_path) / "cr-smart-update.yaml").resolve()) )

  if not k8s_wait_for_ready('kube-system', 'k8s-app=kube-dns'):
    raise Exception("Kubernetes cluster is not available")
  run_fatal(["kubectl", "create", "namespace", args.namespace],
      "Can't create a namespace for the cluster", r"from server \(AlreadyExists\)")

  if args.operator_name == "percona-xtradb-cluster-operator" and args.helm != True:
    if args.cluster_name == "":
      args.cluster_name = "cluster1"
    else:
      run_fatal(["sed", "-i", "-re", r"s/: cluster1\>/: {}/".format(args.cluster_name), "./deploy/cr.yaml"], "fix cluster name in cr.yaml")
    if args.db_version:
      set_yaml('.spec.pxc.image = "{}"'.format(args.db_version), "Can't set PXC version")
    if re.match(r'^[0-9\.]*$', args.operator_version) and StrictVersion(args.operator_version) < StrictVersion("1.11.0"):
      args.users_secret = "my-cluster-secrets"
    else:
      args.users_secret = args.cluster_name + "-secrets"
    if args.proxysql:
      set_yaml('.spec.haproxy.enabled=false,.spec.proxysql.enabled=true',
               "Enable proxysql",
               str((Path(args.data_path) / args.operator_name / "deploy" / "cr.yaml").resolve()))
    if args.expose:
      set_yaml('.spec.pxc.expose.enabled=true|.spec.pxc.expose.type="LoadBalancer"',
               "expose pxc")

    set_yaml('.spec.pxc.imagePullPolicy="IfNotPresent"|.spec.haproxy.imagePullPolicy="IfNotPresent"', "image pull policy: IfNotPresent")

  if args.operator_name == "percona-postgresql-operator" and args.helm != True:
    args.users_secret = args.cluster_name + "-users"
    if args.cluster_name == "":
      args.cluster_name = "cluster1"
    else:
      run_fatal(["sed", "-i", "-re", r"s/: cluster1\>/: {}/".format(args.cluster_name), "./deploy/cr.yaml"], "fix cluster name in cr.yaml")
    if args.standby and args.operator_version.startswith("1."):
      run_fatal(["sed", "-i", "-re", r"s/standby: false/standby: true/".format(args.cluster_name), "./deploy/cr.yaml"], "fix cluster name in cr.yaml")
    elif args.standby:
      set_yaml(
          '(.spec.standby.enabled=true)|'
          '(.spec.standby.repoName="repo1")',
          "enable minio backups")

    if args.memory and args.operator_version.startswith("1."):
      set_yaml('.spec.pgPrimary.resources.limits.memory="{mem}" | .spec.pgReplicas.resources.limits.memory="{mem}"'.format(mem=args.memory),
          "set memory limit")
    if args.expose and args.operator_version.startswith("1."):
      set_yaml('.spec.pgPrimary.expose.serviceType="LoadBalancer"|\
                .spec.pgReplicas.hotStandby.expose.serviceType="LoadBalancer"|\
                .spec.pgBouncer.expose.serviceType="LoadBalancer"',
               "expose PG svcs")
    elif args.expose:
      set_yaml('.spec.expose.type="LoadBalancer"|\
                .spec.proxy.pgBouncer.expose.type="LoadBalancer"',
               "expose PG svcs")

  if args.operator_name == "percona-server-mongodb-operator" and args.helm != True:
    if args.cluster_name == "":
      args.cluster_name = "my-cluster-name"
    else:
      run_fatal(["sed", "-i", "-re", r"s/: my-cluster-name\>/: {}/".format(args.cluster_name), "./deploy/cr.yaml"], "fix cluster name in cr.yaml")
    args.users_secret = args.cluster_name + "-secrets"

    if args.cluster_domain != "":
      set_yaml('.spec.clusterServiceDNSSuffix="svc.{}"'.format(args.cluster_domain),
               "change cluster domain")
    if args.expose:
      set_yaml('.spec.replsets[0].expose.enabled=true|.spec.replsets[0].expose.exposeType="LoadBalancer"',
               "expose replset")

  enable_pmm(args)

  if args.minio:
    enable_minio(args)

  if args.operator_name == "percona-postgresql-operator":
    run_pg_operator(args.namespace, args.operator_name, args.db_version,
                    args.cluster_name, args.operator_version, args.standby,
                    args.backup_type, args.bucket,args.gcs_key, args.db_replicas, args.cluster_tls)
  elif args.operator_name in ("percona-server-mongodb-operator", "percona-xtradb-cluster-operator", "percona-server-mysql-operator"):
    run_percona_operator(args.namespace, args.operator_name, args.operator_version, args.cluster_name)

def extract_secret_password(ns, secret, user):
  return run_get_line(["kubectl", "get", "secrets", "-n", ns, secret, "-o", r'go-template={{ .data.' + user + r'| base64decode }}'],
      "Can't get pod name")

def info_pxc_operator(ns, helm_enabled, users_secret, cluster_name):
  pxc_users_secret = users_secret
  pxc_node_0 = "{}-pxc-0".format(cluster_name)
  if helm_enabled:
    pxc_users_secret=cluster_name
    pxc_node_0 = cluster_name + "-pxc-0"
  pwd = extract_secret_password(ns, pxc_users_secret, "root")
  root_cluster_pxc = ["kubectl", "-n", ns, "exec", "-it", pxc_node_0, "-c", "pxc", "--", "env", "LANG=C.utf8", "MYSQL_HISTFILE=/tmp/.mysql_history", "mysql", "-uroot", "-p"+pwd]
  print(subprocess.list2cmdline(root_cluster_pxc))

def info_mongo_operator(ns, cluster_name):
  pwd =  extract_secret_password(ns, cluster_name + "-secrets", "MONGODB_CLUSTER_ADMIN_PASSWORD")
  cluster_admin_mongo = ["kubectl", "-n", ns, "exec", "-it", cluster_name + "-rs0-0", "--", "env", "LANG=C.utf8", "HOME=/tmp", "mongo", "-u", "clusterAdmin", "--password="+pwd, "localhost/admin"]
  print(subprocess.list2cmdline(cluster_admin_mongo))

  pwd =  extract_secret_password(ns, cluster_name + "-secrets", "MONGODB_USER_ADMIN_PASSWORD")
  user_admin_mongo = ["kubectl", "-n", ns, "exec", "-it", cluster_name + "-rs0-0", "--", "env", "LANG=C.utf8", "HOME=/tmp", "mongo", "-u", "userAdmin", "--password="+pwd, "localhost/admin"]
  print(subprocess.list2cmdline(user_admin_mongo))


def populate_mongodb(*_):
  pass

def populate_pg_db(ver, ns, cluster_name, sql_file):
  if ver.startswith("1."):
    k8s_wait_for_job_complete(ns ,"job/backrest-backup-{}".format(cluster_name))
  else:
    k8s_wait_for_job_complete_label(ns ,"postgres-operator.crunchydata.com/pgbackrest-backup=replica-create")
  print("kubectl -n {} get PerconaPGCluster cluster1".format(subprocess.list2cmdline([ns])))
  for container in get_containers_list(ns,"name=cluster1"):
    if container != "":
      s = "kubectl -n {} exec -i {} -- env PSQL_HISTORY=/tmp/.psql_history psql -U postgres < {}".format(
          subprocess.list2cmdline([ns]), container, subprocess.list2cmdline([sql_file]))
      run_fatal(["sh", "-c", s], "Can't apply sql file")

def populate_pxc_db(ns, sql_file, helm_enabled, cluster_name):
  pxc_users_secret = cluster_name + "-secrets"
  pxc_node_0 = cluster_name + "-pxc-0"
  pxc_node_2 = cluster_name + "-pxc-2"
  if helm_enabled:
    pxc_users_secret = cluster_name
    pxc_node_0 = cluster_name + "-pxc-0"
    pxc_node_2 = cluster_name + "-pxc-2"

  if not k8s_wait_for_ready(ns, "app.kubernetes.io/component=pxc,app.kubernetes.io/instance={},statefulset.kubernetes.io/pod-name={}".format(cluster_name, pxc_node_2), COMMAND_TIMEOUT*2):
    raise Exception("cluster node2 is not starting")
  if not k8s_wait_for_ready(ns, "app.kubernetes.io/component=pxc,app.kubernetes.io/instance={},statefulset.kubernetes.io/pod-name={}".format(cluster_name, pxc_node_0)):
    raise Exception("cluster node0 is not available")

  pwd = extract_secret_password(ns, pxc_users_secret, "root")
  root_cluster_pxc = ["kubectl", "-n", ns, "exec", "-i", pxc_node_0, "-c", "pxc", "--", "env", "LANG=C.utf8", "MYSQL_HISTFILE=/tmp/.mysql_history", "mysql", "-uroot", "-p" + subprocess.list2cmdline([subprocess.list2cmdline([pwd])])]
  s = subprocess.list2cmdline(root_cluster_pxc) + " < " + subprocess.list2cmdline([sql_file])
  run_fatal(["sh", "-c", s], "Can't apply sql file")

def setup_loki(args):
  if args.operator_name != "":
    return
  run_helm(args.helm_path, ["helm", "repo", "add", "grafana", "https://grafana.github.io/helm-charts"], "helm repo add problem")
  run_helm(args.helm_path, ["helm", "install", "loki-stack", "grafana/loki-stack", "--create-namespace", "--namespace", "loki-stack",
    "--set", "promtail.enabled=true,loki.persistence.enabled=true,loki.persistence.size=1Gi"], "Can't start loki with helm")

def deploy_ingress_nginxinc(args):
  # generate certificate, generate set controller.defaultTLS.secret	and controller.wildcardTLS.secret
  run_helm(args.helm_path, ["helm", "repo", "add", "nginx-stable", "https://helm.nginx.com/stable"], "helm repo add problem")
  nginx_helm_install_cmd = ["helm", "install", "nginx-ingress", "nginx-stable/nginx-ingress",
    "--create-namespace", "--namespace", "ingress-nginx",
    "--set", "controller.service.httpsPort.port={}".format(args.ingress_port)]
  if args.cert_manager:
    gen_wildcard_ns_self_signed_cert(args, "default")
    nginx_helm_install_cmd.extend(["--set", "controller.wildcardTLS.secret=default/ingress-default-tls",
    "--set", "controller.defaultTLS.secret=default/ingress-default-tls"])
  run_helm(args.helm_path, nginx_helm_install_cmd, "Can't nginx ingress with helm")

def deploy_ingress_nginx(args):
  # generate certificate, generate set controller.defaultTLS.secret	and controller.wildcardTLS.secret
  run_helm(args.helm_path, ["helm", "repo", "add", "ingress-nginx", "https://kubernetes.github.io/ingress-nginx"], "helm repo add problem")
  nginx_helm_install_cmd = ["helm", "install", "nginx-ingress", "ingress-nginx/ingress-nginx",
    "--create-namespace", "--namespace", "ingress-nginx",
    "--set", "controller.service.ports.https={}".format(args.ingress_port)]
  if args.cert_manager:
    gen_wildcard_ns_self_signed_cert(args, "default")
    nginx_helm_install_cmd.extend(["--set", "controller.wildcardTLS.secret=default/ingress-default-tls",
    "--set", "controller.defaultTLS.secret=default/ingress-default-tls"])
  run_helm(args.helm_path, nginx_helm_install_cmd, "Can't nginx ingress with helm")

def deploy_ingress_istio(args):
  run_helm(args.helm_path, ["helm", "repo", "add", "istio", "https://istio-release.storage.googleapis.com/charts"], "helm repo add problem")
  run_helm(args.helm_path, ["helm", "install", "istio-base", "istio/base", "-n", "istio-system", "--create-namespace"], "Can't install istio base")
  run_helm(args.helm_path, ["helm", "install", "istiod", "istio/istiod", "-n", "istio-system", "--wait"], "Can't install istiod")
  run_helm(args.helm_path, ["helm", "install", "istio-ingress", "istio/gateway", "-n", "istio-system", "--wait"], "Can't install istio ingress")

def setup_ingress_nginx(args):
  ingress_svc = []
  ingress_ns = {}
  ingress_dns = {}
  ingress_annotations = {}
  if args.pmm and type(args.pmm) is dict and "namespace" in args.pmm:
    ingress_svc.append("monitoring-service")
    ingress_ns["monitoring-service"] = args.pmm["namespace"]
    ingress_annotations["monitoring-service"] = """\
        nginx.org/websocket-services: {svc}""".format(svc="monitoring-service")
  if args.pmm and type(args.pmm) is dict and "dns" in args.pmm:
    ingress_dns["monitoring-service"] = args.pmm["dns"]
  if args.minio:
    ingress_svc.append("minio-service")
    ingress_ns["minio-service"] = "default"
    ingress_annotations["minio-service"] = ""
  ingress_svc_yaml = """
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: ingress-{svc}
      namespace: {ns}
      annotations:
        nginx.org/ssl-services: "{svc}"
{more_annotations}
    spec:
      tls:
      - hosts:
        - {svc}.{ns}.svc.{cluster_domain}
{more_hosts_tls}
        secretName: {svc}-tls
      rules:
      - host: {svc}.{ns}.svc.{cluster_domain}
        http:
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {svc}
                port:
                  number: 443
{more_hosts_rules}
      ingressClassName: nginx"""
  ingress_hosts_tls="""\
        - {dns}"""
  ingress_hosts_rules="""\
      - host: {dns}
        http:
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {svc}
                port:
                  number: 443
"""
  for svc in ingress_svc:
    more_tls = ""
    more_rules = ""
    if svc in ingress_dns:
      more_tls = ingress_hosts_tls.format(dns=ingress_dns[svc])
      more_rules = ingress_hosts_rules.format(dns=ingress_dns[svc],svc=svc)

    ingress_yaml_path = str((Path(args.data_path) / "ingress-{}.yaml".format(svc)).resolve())
    with open(ingress_yaml_path,"w+") as f:
      f.writelines(ingress_svc_yaml.format(cluster_domain=args.cluster_domain, svc=svc,ns=ingress_ns[svc],more_hosts_tls=more_tls,more_hosts_rules=more_rules,more_annotations=ingress_annotations[svc]))
    run_fatal(["kubectl", "apply", "-f", ingress_yaml_path ], "Can't create ingress resource for {}".format(svc))


def populate_db(args):
  if not Path(args.sql_file).is_file():
    dest = str((Path(args.data_path) / "data.sql").resolve())
    script = str((Path(args.anydbver_path) / "tools/download_file_from_s3.sh").resolve())
    s = "{} {} > {}".format(script, subprocess.list2cmdline([args.sql_file]), dest)
    run_fatal(["sh", "-c", s], "Can't download sql file from s3")
    args.sql_file = dest

  if args.operator_name == "percona-server-mongodb-operator":
    populate_mongodb(args.namespace, args.js_file)
  if args.operator_name == "percona-postgresql-operator":
    populate_pg_db(args.operator_version, args.namespace, args.cluster_name, args.sql_file)
  if args.operator_name == "percona-xtradb-cluster-operator":
    populate_pxc_db(args.namespace, args.sql_file, args.helm, args.cluster_name)

def operator_info(args):
  if args.operator_name == "percona-server-mongodb-operator":
    info_mongo_operator(args.namespace, args.cluster_name)
  if args.operator_name == "percona-postgresql-operator":
    info_pg_operator(args.namespace, args.cluster_name)
  if args.operator_name == "percona-xtradb-cluster-operator":
    info_pxc_operator(args.namespace, args.helm, args.users_secret, args.cluster_name)

def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--data-path", dest="data_path", type=str, default="")
  parser.add_argument("--helm-path", dest="helm_path", type=str, default="")
  parser.add_argument("--operator", dest="operator_name", type=str, default="")
  parser.add_argument("--version", dest="operator_version", type=str, default="1.1.0")
  parser.add_argument("--operator-options", dest="operator_options", type=str, default="")
  parser.add_argument("--db-version", dest="db_version", type=str, default="")
  parser.add_argument('--cert-manager', dest="cert_manager", type=str, default="")
  parser.add_argument('--cluster-domain', dest="cluster_domain", type=str, default="cluster.local")
  parser.add_argument('--pmm', dest="pmm", type=str, default="")
  parser.add_argument('--minio', dest="minio", type=str, nargs='?')
  parser.add_argument('--backup-type', dest="backup_type", type=str, default="")
  parser.add_argument('--bucket', dest="bucket", type=str, default="")
  parser.add_argument('--gcs-key', dest="gcs_key", type=str, default="")
  parser.add_argument('--minio-certs', dest="minio_certs", type=str, default="")
  parser.add_argument('--namespace', dest="namespace", type=str, default="")
  parser.add_argument('--cluster-name', dest="cluster_name", type=str, default="")
  parser.add_argument('--ingress', dest="ingress", type=str, default="")
  parser.add_argument('--ingress-port', dest="ingress_port", type=int, default=443)
  parser.add_argument('--sql', dest="sql_file", type=str, default="")
  parser.add_argument('--js', dest="js_file", type=str, default="")
  parser.add_argument('--info-only', dest="info", action='store_true')
  parser.add_argument('--smart-update', dest="smart_update", action='store_true')
  parser.add_argument('--standby', dest="standby", action='store_true')
  parser.add_argument('--expose', dest="expose", action='store_true')
  parser.add_argument('--archive-push-async', dest="archive_push_async", action='store_true')
  parser.add_argument('--cluster-tls', action='store_true')
  parser.add_argument('--db-replicas', dest="db_replicas", type=str, nargs='?')
  parser.add_argument('--update-strategy', dest="update_strategy", type=str, nargs='?')
  parser.add_argument('--helm', dest="helm", action='store_true')
  parser.add_argument("--helm-chart-version", dest="helm_chart_version", type=str, default="")
  parser.add_argument("--helm-values", dest="helm_values", type=str, default="")
  parser.add_argument('--memory', dest="memory", type=str, nargs='?')
  parser.add_argument('--loki', dest="loki", action='store_true')
  parser.add_argument('--kube-fledged', dest="kube_fledged", default="")
  parser.add_argument('--proxysql', dest="proxysql", action='store_true')
  args = parser.parse_args()

  args.anydbver_path = (Path(__file__).parents[1]).resolve()
  if not args.helm_path:
    args.helm_path = (Path(__file__).parents[1] / 'data' / 'helm').resolve()
  else:
    args.helm_path = Path(args.helm_path).resolve()
  if not args.data_path:
    args.data_path = (Path(args.anydbver_path) / 'data' / 'k8s').resolve()
  else:
    args.data_path = (Path(args.data_path)).resolve()
  args.conf_path = (Path(__file__).resolve().parents[1] / 'configs' / 'k8s').resolve()
  args.yq = str((Path(__file__).parents[0] / 'yq').resolve())

  if args.namespace == "":
    args.namespace = get_operator_ns(args.operator_name)


  if not args.info:
    if args.operator_name == "" and args.kube_fledged != "":
      run_kube_fledged_helm(args.helm_path)
    if args.loki:
      setup_loki(args)
    if args.helm:
      if args.cert_manager != "" and args.operator_name == "":
        run_cert_manager_helm(args.helm_path, args.cert_manager) # cert_manager_ver_compat(args.operator_name, args.operator_version, args.cert_manager)
      if args.ingress == "nginxinc" and args.operator_name == "":
        deploy_ingress_nginxinc(args)
      if args.ingress == "nginx" and args.operator_name == "":
        deploy_ingress_nginx(args)
      if args.ingress == "istio" and args.operator_name == "":
        deploy_ingress_istio(args)
      setup_operator_helm(args)
    else:
      if args.cert_manager != "" and args.operator_name == "":
        run_cert_manager(args.cert_manager) # cert_manager_ver_compat(args.operator_name, args.operator_version, args.cert_manager)
      if args.ingress == "nginx" and args.operator_name == "":
        deploy_ingress_nginx(args)
      if args.ingress == "nginxinc" and args.operator_name == "":
        deploy_ingress_nginxinc(args)
      if args.ingress == "istio" and args.operator_name == "":
        deploy_ingress_istio(args)
      setup_operator(args)
    if args.ingress == "nginxinc":
      setup_ingress_nginx(args)
    if args.ingress == "nginx":
      setup_ingress_nginx(args)
    if args.sql_file != "":
      populate_db(args)

  operator_info(args)

  logger.info("Success")

if __name__ == '__main__':
  main()
