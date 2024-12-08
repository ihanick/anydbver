#!/usr/bin/env python3
import logging
import os
import re
import sys
import argparse
import itertools
import subprocess
from pathlib import Path
import sqlite3
import urllib.parse
import anydbver_tests
from anydbver_run_tools import run_fatal, run_get_line, soft_params
from anydbver_updater import update_versions
from anydbver_help import arg_help
from anydbver_unmodified_docker import deploy_unmodified_docker_images, setup_unmodified_docker_images

COMMAND_TIMEOUT=600
DEFAULT_PASSWORD='verysecretpassword1^'
FORMAT = '%(asctime)s %(levelname)s %(message)s'
ANYDBVER_DIR = os.path.dirname(os.path.realpath(__file__))
logging.basicConfig(format=FORMAT)
logger = logging.getLogger('AnyDbVer')
logger.setLevel(logging.INFO)

class SmartFormatter(argparse.HelpFormatter):
  def _split_lines(self, text, width):
    if text.startswith('R|'):
      return text[2:].splitlines()  
    # this is the RawTextHelpFormatter._split_lines
    return argparse.HelpFormatter._split_lines(self, text, width)


def get_servers_list(provider, net):
  return list(run_get_line(logger, [provider, "ps", "-a", "--filter", "network="+net, "--format", "{{.ID}}"],
    "Can't get containers list").splitlines())

def download_dependencies():
  if not Path("tools/yq").is_file():
    run_fatal(logger, ["bash", "-c", "curl -L -s --output tools/yq https://github.com/mikefarah/yq/releases/download/v4.24.2/yq_linux_amd64 && chmod +x tools/yq"], "Can't download yq")


def destroy(args):
  logger.info("Removing nodes")
  if args.provider == "docker":
    destroy_docker(args)
  elif args.provider == "lxd":
    destroy_lxd(args)
  elif args.provider == "kubectl":
    pass

def destroy_lxd(args):
  ns_prefix = args.namespace
  if ns_prefix != "":
    ns_prefix = ns_prefix + "-"

  container_name_prefix = "{ns_prefix}{user}-".format(ns_prefix=ns_prefix, user=args.user)
  container_name_prefix = container_name_prefix.replace(".","-")
  names = []
  result = subprocess.run(['lxc', 'list', '--format=csv'], stdout=subprocess.PIPE)
  for l in result.stdout.decode('utf-8').splitlines():
    container_name = l.split(',', 1)[0]
    if container_name.startswith(container_name_prefix):
      names.append(container_name)
  if names:
    run_fatal(logger, ["lxc", "delete", "-f"] + names, "Can't remove LXD containers")
  else:
    logger.info("No nodes to delete")

def destroy_docker(args):
  ns_prefix = args.namespace
  if ns_prefix != "":
    ns_prefix = ns_prefix + "-"
  net = "{}{}-anydbver".format(ns_prefix, args.user)
  cluster = "{}{}-cluster1".format(ns_prefix, args.user)
  if args.provider == "docker" and Path("tools/k3d").is_file():
    run_fatal(logger, ["tools/k3d", "cluster", "delete", cluster], "Can't remove k3d cluster")
  for c in get_servers_list(args.provider, net):
    if c != "":
      run_fatal(logger, [args.provider, "rm", "-f", c], "Can't remove container")
  run_fatal(logger, [args.provider, "network", "rm", net], "Can't remove network", r"No such network:|network .* not found")
  if (Path(os.getcwd()) / "data").is_dir():
    run_fatal(logger, [args.provider, "run", "-i", "--rm", "-v",
      str((Path(os.getcwd()) / "data").resolve())+":/data",
      "busybox", "sh", "-c", "rm -rf -- /data/nfs"], "Can't clean data directory")
    clean_data_needed = False
    if clean_data_needed:
      run_fatal(logger, [args.provider, "run", "-i", "--rm", "-v",
        str((Path(os.getcwd()) / "data").resolve())+":/data",
        "busybox", "sh", "-c", "rm -rf -- /data/*"], "Can't clean data directory")
  try:
    os.unlink("{ns}ssh_config".format(ns=ns_prefix))
    os.unlink("{ns}ansible_hosts".format(ns=ns_prefix))
    os.unlink("{ns}ansible_hosts_run".format(ns=ns_prefix))
    os.unlink("{ns}screenrc".format(ns=ns_prefix))
  except:
    pass


def read_latest_version_from_sqlite(name):
  db_file = 'anydbver_version.db'
  try:
    conn = sqlite3.connect(db_file)
    conn.row_factory = sqlite3.Row
  except sqlite3.Error as e:
    print(e)
    return ""
  cur = conn.cursor()
  sql = "SELECT version FROM k8s_operators_version WHERE name=? ORDER BY CAST(SUBSTR(version,1,INSTR(version,'.')-1) as integer) DESC, CAST(SUBSTR(version,INSTR(version,'.')+1, INSTR(SUBSTR(version,INSTR(version,'.')+1),'.')-1 ) AS INTEGER) DESC, CAST( SUBSTR(version, INSTR(version,'.')+1+ INSTR(SUBSTR(version,INSTR(version,'.')+1),'.')  ) AS INTEGER) DESC LIMIT 1"
  cur.execute(sql, (name,))
  rows = cur.fetchall()
  return rows[0]["version"]

def general_version_from_sqlite(ver,program,osver,arch):
  db_file = 'anydbver_version.db'
  try:
    conn = sqlite3.connect(db_file)
    conn.row_factory = sqlite3.Row
  except sqlite3.Error as e:
    print(e)
    return ""
  cur = conn.cursor()
  if ver in ("latest","True"):
    ver = "%"
  sql = "SELECT version FROM general_version WHERE version like '"+ver+"%' and program=? and os=? and arch=? ORDER BY CAST(SUBSTR(version,1,INSTR(version,'.')-1) as integer) DESC, CAST(SUBSTR(version,INSTR(version,'.')+1, INSTR(SUBSTR(version,INSTR(version,'.')+1),'.')-1 ) AS INTEGER) DESC, CAST( SUBSTR(version, INSTR(version,'.')+1+ INSTR(SUBSTR(version,INSTR(version,'.')+1),'.')  ) AS INTEGER) DESC, CAST( SUBSTR(version, INSTR(version,'-')+1+ INSTR(SUBSTR(version,INSTR(version,'-')+1),'-')  ) AS INTEGER) DESC LIMIT 1"
  cur.execute(sql, (program,osver,arch))
  rows = cur.fetchall()
  return rows[0]["version"]



def is_unmodified_docker_image(node):
  for record in vars(node).values():
    if record is None:
      continue
    if "docker-image" in record:
      return True
  return False

def deploy(args, node_actions):
  logger.info("Deploy")
  ns_prefix = args.namespace
  if ns_prefix != "":
    ns_prefix = ns_prefix + "-"
  net = "{}{}-anydbver".format(ns_prefix, args.user)
  cluster = "{}{}-cluster1".format(ns_prefix, args.user)
  for node_action in node_actions:
    #print("Applying node: ", node_action)
    node = node_action[1]

    old_provider = args.provider

    if node.k8s_context:
      run_fatal(logger, ["kubectl", "config", "use-context", node.k8s_context], "Can't change kubectl context")
      args.provider = 'kubectl'

    run_k8s_operator_cmd = ['python3', 'tools/run_k8s_operator.py']
    if args.provider == "docker":
      if not node.k3d and (node.k8s_pxc or node.k8s_pg or node.k8s_ps or node.k8s_mongo):
        node.k3d = 'True'
      if node.k3d:
        params = soft_params(node.k3d)

        if not Path("tools/k3d").is_file():
          run_fatal(logger, ["bash", "-c", "curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | PATH=$PATH:{adir} K3D_INSTALL_DIR={adir} USE_SUDO=false bash".format(adir=str((Path(ANYDBVER_DIR) / "tools").resolve()))], "Can't download k3d")

        if params["version"] == 'True':
          params["version"] = 'latest'
        if "cluster-domain" not in params and node.k8s_cluster_domain is None:
          params["cluster-domain"] = "cluster.local"

        k3d_agents = 2
        if "nodes" in params:
          k3d_agents = int(params["nodes"]) - 1
        if k3d_agents <= 0:
          k3d_agents = 0
        k3d_create_cmd = ["tools/k3d", "cluster", "create", "-i", "rancher/k3s:{}".format(params["version"]) , "--network", net, "-a", str(k3d_agents)]

        k3d_create_cmd.extend([
            '--k3s-arg', '--kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%@server:*',
            '--k3s-arg', '--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1%,nodefs.available=1%@server:*',
            '--k3s-arg', '--kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%@agent:*',
            '--k3s-arg', '--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1%,nodefs.available=1%@agent:*',
           ])

        if "ingress" in params:
          node.ingress = params["ingress"]
          node.ingress_port = params["ingress"]
        if "ingress-type" in params:
          node.ingress_type = params["ingress-type"]
        if "cluster-domain" in params:
          node.k8s_cluster_domain = params["cluster-domain"]
          node.cluster_domain=params["cluster-domain"]

        if "feature-gates" in params:
          k3d_create_cmd.append("--k3s-arg")
          k3d_create_cmd.append("--kube-apiserver-arg=feature-gates={}@server:*".format(params["feature-gates"]))

        if "storage-path" in params:
          k3d_create_cmd.append("--volume")
          k3d_create_cmd.append("{}:/var/lib/rancher/k3s/storage@all".format(params["storage-path"]))

        registry_cache_conf = ""
        if node.registry_cache:
          registry_cache_conf =  """\
  docker.io:
    endpoint:
      - "{}"
""".format(node.registry_cache)
        private_registry_conf = ""
        if node.private_registry:
          (name, url) = node.private_registry.split('=', 1)
          private_registry_conf = """\
  {}:
    endpoint:
      - "{}" 
""".format(name, url)
        if node.private_registry or node.registry_cache:
          registries_path = str((Path(os.getcwd()) / "data/my-registries.yaml").resolve())
          with open( registries_path, "w") as f:
            f.write("""\
mirrors:
{}
{}
""".format(registry_cache_conf, private_registry_conf))
            k3d_create_cmd.append("--registry-config")
            k3d_create_cmd.append(registries_path)

        if node.k8s_cluster_domain:
          k3d_create_cmd.append("--k3s-arg")
          k3d_create_cmd.append("--cluster-domain={}@server:0".format(node.k8s_cluster_domain))

        internal_lb = True
        if  "metallb" in params:
          #k3d_create_cmd.append("--k3s-arg")
          #k3d_create_cmd.append("--disable=traefik@server:0")
          #k3d_create_cmd.append("--k3s-arg")
          #k3d_create_cmd.append("--kube-proxy-arg=--ipvs-strict-arp=true@server:*")
          k3d_create_cmd.append("--no-lb")
          internal_lb = False

        if node.ingress:
          params = soft_params(node.ingress)
          node.ingress_port = params["version"]

          if not node.ingress_type:
            if "traefik" in params:
              node.ingress_type = "traefik"
            elif "nginx" in params:
              node.ingress_type = "nginx"
            elif "nginxinc" in params:
              node.ingress_type = "nginxinc"
            elif "istio" in params:
              node.ingress_type = "istio"
            else:
              node.ingress_type = "nginx"

          if node.ingress_type is None or node.ingress_type == "":
            node.ingress_type = 'traefik'
          if node.ingress_type != 'traefik':
            k3d_create_cmd.append("--k3s-arg")
            k3d_create_cmd.append("--disable=traefik@server:0")
            run_k8s_operator_cmd.append("--ingress={}".format(node.ingress_type))

          if node.ingress_type in ("nginx", "nginxinc", "traefik", "istio"):
            if internal_lb:
              k3d_create_cmd.append("-p")
              k3d_create_cmd.append("{ingress_port}:{ingress_port}@loadbalancer".format(ingress_port=node.ingress_port))
              k3d_create_cmd.append("-p")
              k3d_create_cmd.append("{ingress_port}:{ingress_port}/udp@loadbalancer".format(ingress_port=node.ingress_port))
              if "http" in params:
                k3d_create_cmd.append("-p")
                k3d_create_cmd.append("{port}:80@loadbalancer".format(port=params["http"]))
          run_k8s_operator_cmd.append("--ingress-port={}".format(node.ingress_port))
        k3d_create_cmd.append(cluster)
        run_fatal(logger, k3d_create_cmd, "Can't create k3d cluster")
        run_fatal(logger, ["sh", "-c", """kubectl get sc local-path -o yaml | sed -r -e 's/name: local-path/name: standard/g' -e '/(uid|creationTimestamp|resourceVersion):/d' -e 's/is-default-class: "true"/is-default-class: "false"/' | kubectl apply -f -"""], "Can't create 'standard' storage class for local-path provisioner")
        args.provider = "kubectl"
        #run_fatal(logger, ["kubectl", "apply", "-f", "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"], "Can't install metrics server")
        if "metallb" in params:
          if type(params["metallb"]) != str:
            params["metallb"] = "0.13.11"
          run_fatal(logger, ["bash", "{}/tools/setup_metallb.sh".format(ANYDBVER_DIR), net, params["metallb"] ], "Can't setup metallb")
        
    if args.provider == "kubectl":
      if node.k8s_namespace:
        run_k8s_operator_cmd.append("--namespace={}".format(node.k8s_namespace))
      if node.pmm:
        if node.pmm == "True":
          node.pmm = "2.31.0,helm=percona-helm-charts:0.3.9,certs=self-signed,namespace=monitoring"
        run_k8s_operator_cmd.append("--pmm={}".format(node.pmm))
        
      if node.cluster_name:
        run_k8s_operator_cmd.append("--cluster-name={}".format(node.cluster_name))

      if node.k8s_minio:
        if node.minio_certs or "certs=" in node.k8s_minio:
          run_k8s_operator_cmd.append("--minio-certs={}".format(node.minio_certs))
          if not node.cert_manager:
            node.cert_manager='True'

        if str(node.k8s_minio) == 'True':
          run_k8s_operator_cmd.append("--minio=2023.2.27,helm=bitnami")
        elif node.k8s_minio[0].isdigit():
          run_k8s_operator_cmd.append("--minio={}".format(node.k8s_minio))
        else:
          run_k8s_operator_cmd.append("--minio=2023.2.27,{}".format(node.k8s_minio))

      if node.loki:
        run_k8s_operator_cmd.append("--loki")

      if node.kube_fledged:
        run_k8s_operator_cmd.append("--kube-fledged={}".format(node.kube_fledged))

      if node.db_version:
          run_k8s_operator_cmd.append("--db-version={}".format(node.db_version))

      if node.cert_manager:
        if str(node.cert_manager) == 'True':
          CERT_MANAGER_DEFAULT_VERSION='1.7.2'
          run_k8s_operator_cmd.append("--cert-manager={}".format(CERT_MANAGER_DEFAULT_VERSION))
        else:
          run_k8s_operator_cmd.append("--cert-manager={}".format(node.cert_manager))

      if node.s3sql:
          run_k8s_operator_cmd.append("--sql={}".format(node.s3sql))

      if (node.ingress_port or node.pmm or node.k8s_minio or node.loki or node.cert_manager):
        run_fatal(logger, run_k8s_operator_cmd, "Can't run the operator")

      if node.helm:
        run_k8s_operator_cmd.append("--helm")

      if node.sql_file:
        run_k8s_operator_cmd.append("--sql={}".format(node.sql_file))
 
      if node.k8s_pxc:
        for pxc in node.k8s_pxc:
          run_cmd = run_k8s_operator_cmd.copy()
          logger.info("Starting PXC in kubernetes managed by Percona operator {}, '{}'".format(pxc, run_cmd))
          run_cmd.append("--operator=percona-xtradb-cluster-operator")
          params = soft_params(pxc)
          if params["version"] in ("True", "latest"):
            params["version"] = read_latest_version_from_sqlite("percona/percona-xtradb-cluster-operator")
          run_cmd.append("--version={}".format(params["version"]))
          if "cluster-name" in params:
            run_cmd.append("--cluster-name={}".format(params["cluster-name"]))
          if "namespace" in params:
            run_cmd.append("--namespace={}".format(params["namespace"]))
          if "sql" in params:
            run_cmd.append("--sql={}".format(params["sql"]))
          if "proxysql" in params and params["proxysql"]:
            run_cmd.append("--proxysql")
          if "db-version" in params and params["db-version"]:
            run_cmd.append("--db-version={}".format(params["db-version"]))
          if "helm" in params and params["helm"]:
            run_cmd.append("--helm")
          if "helm-values" in params and params["helm-values"]:
            run_cmd.append("--helm-values={}".format(params["helm-values"]))
          if "updateStrategy" in params and params["updateStrategy"]:
            run_cmd.append("--update-strategy={}".format(params["updateStrategy"]))
          if "expose" in params:
            run_cmd.append("--expose")
          run_fatal(logger, run_cmd, "Can't run the operator")


      if node.k8s_pg:
        for pg in node.k8s_pg:
          run_cmd = run_k8s_operator_cmd.copy()
          logger.info("Starting postgresql in kubernetes managed by Percona operator {}, '{}'".format(pg, run_cmd))
          run_cmd.append("--operator=percona-postgresql-operator")
          params = soft_params(pg)
          if params["version"] in ("True","latest"):
            params["version"] = read_latest_version_from_sqlite("percona/percona-postgresql-operator")
          run_cmd.append("--version={}".format(params["version"]))
          if "cluster-name" in params:
            run_cmd.append("--cluster-name={}".format(params["cluster-name"]))
          if "namespace" in params:
            run_cmd.append("--namespace={}".format(params["namespace"]))
          if "backup-type" in params:
            run_cmd.append("--backup-type={}".format(params["backup-type"]))
          if "backup-url" in params:
            run_cmd.append("--backup-url={}".format(params["backup-url"]))
          if "bucket" in params:
            run_cmd.append("--bucket={}".format(params["bucket"]))
          if "gcs-key" in params:
            run_cmd.append("--gcs-key={}".format(params["gcs-key"]))
          if "replicas" in params:
            run_cmd.append("--db-replicas={}".format(params["replicas"]))
          if "db-version" in params:
            run_cmd.append("--db-version={}".format(params["db-version"]))
          if "memory" in params:
            run_cmd.append("--memory={}".format(params["memory"]))
          if "sql" in params:
            run_cmd.append("--sql={}".format(params["sql"]))
          if "standby" in params and params["standby"]:
            run_cmd.append("--standby")
          if "helm" in params and params["helm"]:
            run_cmd.append("--helm")
          if "helm-values" in params and params["helm-values"]:
            run_cmd.append("--helm-values={}".format(params["helm-values"]))
          if "tls" in params:
            run_cmd.append("--cluster-tls")
          if "archive-push-async" in params:
            run_cmd.append("--archive-push-async")
          if "expose" in params:
            run_cmd.append("--expose")
          run_fatal(logger, run_cmd, "Can't run the operator")

      if node.k8s_ps:
        run_cmd = run_k8s_operator_cmd.copy()
        params = soft_params(node.k8s_ps)
        if params["version"] == "True":
          params["version"] = read_latest_version_from_sqlite("percona/percona-server-mysql-operator")
        run_cmd.append("--version={}".format(params["version"]))
        if "cluster-name" in params:
          run_cmd.append("--cluster-name={}".format(params["cluster-name"]))
        if "namespace" in params:
          run_cmd.append("--namespace={}".format(params["namespace"]))
        if "helm" in params and params["helm"]:
          run_cmd.append("--helm")
        if "helm-values" in params and params["helm-values"]:
          run_cmd.append("--helm-values={}".format(params["helm-values"]))
        if "db-version" in params:
          run_cmd.append("--db-version={}".format(params["db-version"]))
        elif node.db_version:
          run_cmd.append("--db-version={}".format(node.db_version))
        if "expose" in params:
          run_cmd.append("--expose")

        logger.info("Starting Percona Server for MySQL in kubernetes managed by Percona operator {}".format(node.k8s_ps))
        run_cmd.append("--operator=percona-server-mysql-operator")
        run_fatal(logger, run_cmd, "Can't run the operator")

      if node.k8s_mongo:
        run_cmd = run_k8s_operator_cmd.copy()
        params = soft_params(node.k8s_mongo)
        if params["version"] == "True":
          params["version"] = read_latest_version_from_sqlite("percona/percona-server-mongodb-operator")
        run_cmd.append("--version={}".format(params["version"]))
        if "cluster-name" in params:
          run_cmd.append("--cluster-name={}".format(params["cluster-name"]))
        if "namespace" in params:
          run_cmd.append("--namespace={}".format(params["namespace"]))
        if "helm" in params and params["helm"]:
          run_cmd.append("--helm")
        if "helm-values" in params and params["helm-values"]:
          run_cmd.append("--helm-values={}".format(params["helm-values"]))
        if "db-version" in params:
          run_cmd.append("--db-version={}".format(params["db-version"]))
        if "memory" in params:
          run_cmd.append("--memory={}".format(params["memory"]))
        elif node.db_version:
          run_cmd.append("--db-version={}".format(node.db_version))
        if node.k8s_cluster_domain != "":
          run_cmd.append("--cluster-domain={}".format(node.k8s_cluster_domain))
        if "expose" in params:
          run_cmd.append("--expose")
        logger.info("Starting Percona Server for MongoDB in kubernetes managed by Percona operator {}".format(node.k8s_mongo))
        run_cmd.append("--operator=percona-server-mongodb-operator")
        run_fatal(logger, run_cmd, "Can't run the operator")
    args.provider = old_provider
  if args.provider == "docker" and args.simple:
    net = "{}{}-anydbver".format(ns_prefix, args.user)
    run_fatal(logger,
              ["docker", "run", "-i", "--rm", "--name","{}{}-ansible".format(ns_prefix, args.user),
               "--network", net,
               "-v", "{}:/vagrant".format(ANYDBVER_DIR),
               "rockylinux:8-anydbver-ansible-{}".format(args.user),
               "bash", "-c",
               "cd /vagrant;until ansible -m ping -i {nsp}ansible_hosts all &>/dev/null ; do sleep 1; done ; ansible-playbook -i {nsp}ansible_hosts_run --forks 16 playbook.yml".format(nsp=ns_prefix)],
              "Error running playbook")
  elif args.provider != "kubectl":
    run_fatal(logger, ["bash", "-c", "until ansible -m ping -i {nsp}ansible_hosts all &>/dev/null ; do sleep 1; done".format(nsp=ns_prefix)], "Error running playbook")
    run_fatal(logger, ["ansible-playbook", "-i", "{}ansible_hosts_run".format(ns_prefix), "--forks", "16", "playbook.yml"], "Error running playbook")

def load_sett_file(provider, echo=True):
  if not Path(".anydbver").is_file():
    logger.info("Creating new settings file .anydbver with provider {}".format(provider))
    with open(".anydbver", "w") as file:
      file.write("PROVIDER={}".format(provider))

  sett = {}
  with open(".anydbver") as file:
   for l in file.readlines():
     if '=' in l:
       (k,v) = l.split('=',1)
       sett[k] = v.strip()
  if echo:
    print("Loaded settings: ", sett)
  return sett

def detect_provider(args, echo=True):
  if args.provider == "":
    sett = load_sett_file("docker", echo)
    if "PROVIDER" in sett:
      args.provider = sett["PROVIDER"]

  if args.provider in ("kubectl", "kubernetes", "k8s"):
      if re.search(
          r"Server Version",
          run_get_line(logger, ["kubectl", "version"],
            "Can't find kubernetes server",
            r"the server could not find the requested resource")):
        logger.info("Found kubernetes server")
        args.provider = "kubectl"
        return
      else:
        args.provider=""
  if args.provider == "" or args.provider == "docker":
    try:
      if re.search(
          r"Docker Engine .",
          run_get_line(logger, ["docker", "version", "-f", "Docker Engine {{.Server.Version}}"],
            "Can't find docker",
            r"Cannot connect to the Docker", print_cmd = False)):
        if args.provider == "":
          logger.info("Found docker server")
        args.provider="docker"
      else:
        args.provider = ""
    except FileNotFoundError as _:
      args.provider=""
      return
  elif args.provider=="lxd":
    pass
  else:
    args.provider=""

  sett = load_sett_file("docker", echo)
  if args.provider == "lxd" and "LXD_PROFILE" in sett:
    args.user = sett["LXD_PROFILE"]
  elif "USER" in os.environ:
    args.user = os.environ["USER"]
  else:
    args.user = os.getlogin()


def container_name_prefix(args):
  if args.provider=="kubectl":
    return ""
  return "{}{}-".format(args.namespace, args.user)

def run_mysql_cli(args):
  c = "{}{}".format(container_name_prefix(args), args.mysql_cli)
  if args.provider=="kubectl":
    os.execl("/usr/bin/env", "/usr/bin/env", args.provider, 'exec', '-it', c, '--', 'env', 'LANG=en_US.UTF-8', 'mysql', '-uroot', '-psecret')
  else:
    os.execl("/usr/bin/env", "/usr/bin/env", args.provider, 'exec', '-e', 'LANG=en_US.UTF-8', '-it', c, 'mysql', '-uroot', '-psecret')


def fix_main_commands(args):
  for cmd_idx, cmd in enumerate(args):
    if cmd in ('deploy', 'add', 'replace', 'destroy', 'delete', 'update', 'ssh', 'exec', 'screen', 'test'):
      args[cmd_idx] = '--' + cmd

def fix_missing_node_commands(args):
  is_deploy = False
  for cmd_idx, cmd in enumerate(args):
    if cmd == '--deploy' or cmd == 'deploy':
      is_deploy = True
      continue
    if is_deploy and (not cmd.startswith('--') ):
      if not cmd.startswith('node'):
        args.insert(cmd_idx, 'node0')
      break

def replace_version_in_command(cmd, ver):
  ver = ver.rstrip()

  if "," in cmd:
    (program_version, program_params) = cmd.split(",",1)
    if '=' in program_version:
      return ver + "," + cmd
    else:
      return ver + "," + program_params
  else:
    if '=' in cmd:
      return ver + "," + cmd
    else:
      return ver

def find_version(args):
  osver = "el8"
  if args.os is not None:
    if args.os == "rocky8":
      osver = "el8"
    elif args.os in ("centos7", "el7", "rhel7"):
      osver = "el7"
    elif args.os == "rocky9":
      osver = "el9"


  if args.percona_server_mongodb:
    params = soft_params(args.percona_server_mongodb)
    if params["version"] in ('True','latest'):
      args.percona_server_mongodb = replace_version_in_command(args.percona_server_mongodb, '7.0')
  if args.percona_server:
    params = soft_params(args.percona_server)
    if args.percona_server in ('True', 'latest', '8'):
      args.percona_server = replace_version_in_command(args.percona_server, '8.0')
  if args.sysbench:
    params = soft_params(args.sysbench)
    version = general_version_from_sqlite(params["version"],'sysbench',osver,'x86_64')
    args.sysbench = replace_version_in_command(args.sysbench, version)

  if args.mariadb:
    params = soft_params(args.mariadb)
    if args.sysbench in ('True', 'latest'):
      args.mariadb = replace_version_in_command(args.mariadb, '10.11')
    else:
      args.mariadb = replace_version_in_command(args.mariadb, params["version"])
  if args.percona_xtrabackup == 'True':
    args.percona_xtrabackup = '8.0'
  if args.percona_xtradb_cluster:
    params = soft_params(args.percona_xtradb_cluster)
    if params["version"] in ('True', 'latest', '8'):
      args.percona_xtradb_cluster = replace_version_in_command(args.percona_xtradb_cluster, '8.0')
  if args.proxysql:
    vers = list(open(".version-info/proxysql.{os}.txt".format(os=osver)))
    version = vers[-1]
    for line in reversed(vers):
      ver = line.rstrip()
      if ver.startswith(args.proxysql):
        version = ver
        break
    args.proxysql = version.rstrip()
  if args.percona_backup_mongodb:
    params = soft_params(args.percona_backup_mongodb)
    if params["version"] in ('True', 'latest', '2'):
      args.percona_backup_mongodb = replace_version_in_command(args.percona_backup_mongodb, '2')
  if args.mysql_server == 'True':
    args.mysql_server = '8.0'
  if args.k3s == 'True':
    args.k3s = "latest"

  if args.percona_postgresql:
    params = soft_params(args.percona_postgresql)
    default_ver = '16'
    if "docker-image" in params:
      default_ver = 'latest'
    if params["version"] in ('True', 'latest'):
      args.percona_postgresql = replace_version_in_command(args.percona_postgresql, default_ver)
  if args.postgresql:
    params = soft_params(args.postgresql)
    default_ver = '16'
    if "docker-image" in params:
      default_ver = 'latest'
    if params["version"] in ('True', 'latest'):
      args.postgresql = replace_version_in_command(args.postgresql, default_ver)
  if args.mysql_router:
    vers = list(open(".version-info/mysql.{os}.txt".format(os=osver)))
    version = vers[-1]
    for line in reversed(vers):
      ver = line.rstrip()
      if ver.startswith(args.mysql_router):
        version = ver
        break
    args.mysql_router = replace_version_in_command(args.mysql_router, version)
  if args.percona_proxysql:
    params = soft_params(args.percona_proxysql)
    version = general_version_from_sqlite(params["version"],'percona-proxysql',osver,'x86_64')
    args.percona_proxysql = replace_version_in_command(args.percona_proxysql, version)
 
  if args.percona_orchestrator:
    params = soft_params(args.percona_orchestrator)
    version = general_version_from_sqlite(params["version"],'percona-orchestrator',osver,'x86_64')
    args.percona_orchestrator = replace_version_in_command(args.percona_orchestrator, version)
  if args.mysql_jdbc:
    vers = list(open(".version-info/mysql-jdbc.txt".format(os=osver)))
    version = vers[-1]
    for line in reversed(vers):
      ver = line.rstrip()
      if ver.startswith(args.mysql_jdbc):
        version = ver
        break
    args.mysql_jdbc = version.rstrip()


def parse_node(args, help_cmd=False):
  node = args.pop(0)

  for cmd_idx, cmd in enumerate(args):
    if ':' not in cmd:
      cmd = cmd + ":True"
    if not cmd.startswith("--"):
      cmd = re.sub(r'^', '--', cmd).replace(':','=', 1)
    args[cmd_idx] = cmd

  if help_cmd:
    args.append('-h')

  parser = argparse.ArgumentParser(formatter_class=SmartFormatter)
  parser.add_argument('--mysql-server', '--mysql', '--mysql-community-server', type=str, nargs='?', help=arg_help("mysql-server"))
  parser.add_argument('--mariadb', '--maria', '--mariadb-server', type=str, nargs='?', help=arg_help("mariadb"))
  parser.add_argument('--mysql-router', type=str, nargs='?', help=arg_help("mysql-router"))
  parser.add_argument('--percona-server', '--ps', type=str, nargs='?', help=arg_help("percona-server"))
  parser.add_argument('--percona-xtradb-cluster', '--pxc', type=str, nargs='?', help=arg_help("percona-xtradb-cluster"))
  parser.add_argument('--proxysql', type=str, nargs='?', help=arg_help("proxysql"))
  parser.add_argument('--percona-proxysql', type=str, nargs='?', help=arg_help("percona-proxysql"))
  parser.add_argument('--valkey', type=str, nargs='?', help=arg_help("valkey"))
  parser.add_argument('--sysbench', type=str, nargs='?', help=arg_help("sysbench"))
  parser.add_argument('--haproxy', type=str, nargs='?', help=arg_help("haproxy"))
  parser.add_argument('--haproxy-galera', type=str, nargs='?', help=arg_help("haproxy-galera"))
  parser.add_argument('--clustercheck', type=str, nargs='?', help=arg_help("clustercheck"))
  parser.add_argument('--mysql-jdbc', type=str, nargs='?', help=arg_help("mysql-jdbc"))
  parser.add_argument('--galera-leader', '--galera-master', '--galera-join', type=str, nargs='?', help=arg_help("galera-leader"))
  parser.add_argument('--group-replication', '--innodb-cluster', type=str, nargs='?', help=arg_help("group-replication"))
  parser.add_argument('--cluster-name', '--cluster', type=str, default='cluster1', nargs='?', help=arg_help("cluster-name"))
  parser.add_argument('--ldap', type=str, nargs='?', help=arg_help("ldap"))
  parser.add_argument('--samba', '--active-directory', type=str, nargs='?', help=arg_help("samba"))
  parser.add_argument('--samba-client', type=str, nargs='?', help=arg_help("samba-client"))
  parser.add_argument('--kmip-server', type=str, nargs='?', help=arg_help("kmip-server"))
  parser.add_argument('--percona-server-mongodb', '--psmdb', type=str, nargs='?', help=arg_help("percona-server-mongodb"))
  parser.add_argument('--percona-backup-mongodb', '--pbm', type=str, nargs='?', help=arg_help("percona-backup-mongodb"))
  parser.add_argument('--shardsrv', type=str, nargs='?', help=arg_help("shardsrv"))
  parser.add_argument('--configsrv', type=str, nargs='?', help=arg_help("configsrv"))
  parser.add_argument('--mongos-cfg', type=str, nargs='?', help=arg_help("mongos-cfg"))
  parser.add_argument('--mongos-shard', type=str, nargs='?', help=arg_help("mongos-shard"))
  parser.add_argument('--ldap-master', type=str, nargs='?', help=arg_help("ldap-master"))
  parser.add_argument('--replica-set', type=str, nargs='?', help=arg_help("replica-set"))
  parser.add_argument('--percona-postgresql', '--percona-postgres', '--ppg', type=str, nargs='?', help=arg_help("percona-postgresql"))
  parser.add_argument('--postgresql', '--postgres', '--pg', type=str, nargs='?', help=arg_help("postgresql"))
  parser.add_argument('--pgbackrest', type=str, nargs='?', help=arg_help("pgbackrest"))
  parser.add_argument('--wal', '--postgres-wal', type=str, nargs='?', help=arg_help("wal"))
  parser.add_argument('--pg-stat-monitor','--pg_stat_monitor', type=str, nargs='?', help=arg_help("pg-stat-monitor"))
  parser.add_argument('--patroni', type=str, nargs='?', help=arg_help("patroni"))
  parser.add_argument('--repmgr', type=str, nargs='?', help=arg_help("repmgr"))
  parser.add_argument('--etcd-ip', type=str, nargs='?', help=arg_help("etcd-ip"))
  parser.add_argument('--development', type=str, nargs='?', help=arg_help("development"))
  parser.add_argument('--leader', '--master', '--primary', type=str, nargs='?', help=arg_help("leader"))
  parser.add_argument('--percona-xtrabackup', type=str, nargs='?', help=arg_help("percona-xtrabackup"))
  parser.add_argument('--debug-packages', '--debug', type=str, nargs='?', help=arg_help("debug-packages"))
  parser.add_argument('--rocksdb', type=str, nargs='?', help=arg_help("rocksdb"))
  parser.add_argument('--s3sql', type=str, nargs='?', help=arg_help("s3sql"))
  parser.add_argument('--percona-orchestrator', type=str, nargs='?', help=arg_help("percona-orchestrator"))
  parser.add_argument('--percona-toolkit', type=str, nargs='?', help=arg_help("percona-toolkit"))
  parser.add_argument('--cert-manager', dest="cert_manager", type=str, nargs='?', help=arg_help("cert-manager"))
  parser.add_argument('--k8s-minio', dest="k8s_minio", type=str, nargs='?', help=arg_help("k8s-minio"))
  parser.add_argument('--loki', dest="loki", type=str, nargs='?', help=arg_help("loki"))
  parser.add_argument('--kube-fledged', dest="kube_fledged", type=str, nargs='?', help=arg_help("kube-fledged"))
  parser.add_argument('--minio-certs', dest="minio_certs", type=str, nargs='?', help=arg_help("minio-certs"))
  parser.add_argument('--k3d', type=str, nargs='?', help=arg_help("k3d"))
  parser.add_argument('--k8s-context', type=str, nargs='?', help=arg_help("k8s-context"))
  parser.add_argument('--registry-cache', type=str, nargs='?', help=arg_help("registry-cache"))
  parser.add_argument('--private-registry', type=str, nargs='?', help=arg_help("private-registry"))
  parser.add_argument('--helm', type=str, nargs='?', help=arg_help("helm"))
  parser.add_argument('--os', type=str, default="", help=arg_help("os"))
  parser.add_argument('--k8s-pg',  dest="k8s_pg",  type=str, action='append', nargs='?', help=arg_help("k8s-pg"))
  parser.add_argument('--k8s-ps', dest="k8s_ps", type=str, nargs='?', help=arg_help("k8s-ps"))
  parser.add_argument('--k8s-mongo', dest="k8s_mongo", type=str, nargs='?', help=arg_help("k8s-mongo"))
  parser.add_argument('--k8s-pxc', dest="k8s_pxc", type=str, action='append', nargs='?', help=arg_help("k8s-pxc"))
  parser.add_argument('--alertmanager', dest="alertmanager", type=str, nargs='?', help=arg_help("alertmanager"))
  parser.add_argument('--minio', dest="minio", type=str, nargs='?', help=arg_help("minio"))
  parser.add_argument('--pmm', dest="pmm", type=str, nargs='?', help=arg_help("pmm"))
  parser.add_argument('--pmm-client', dest="pmm_client", type=str, nargs='?', help=arg_help("pmm-client"))
  parser.add_argument('--db-version', dest="db_version", type=str, nargs='?', help=arg_help("db-version"))
  parser.add_argument('--k8s-cluster-domain', type=str, nargs='?', help=arg_help("k8s-cluster-domain"))
  parser.add_argument('--k8s-namespace', type=str, nargs='?', help=arg_help("k8s-namespace"))
  parser.add_argument('--sql', dest="sql_file", type=str, nargs='?', help=arg_help("sql"))
  parser.add_argument('--k3s', dest="k3s", type=str, nargs='?', help=arg_help("k3s"))
  parser.add_argument('--nginx-ingress', '--ingress-port', dest="ingress_port", type=str, nargs='?', help=arg_help("nginx-ingress"))
  parser.add_argument('--ingress', type=str, nargs='?', help=arg_help("ingress"))
  args = parser.parse_args(args)

  find_version(args)

  return node,args

def resolve_hostname(ns, host, user, provider):
  if ns != "":
    ns = ns + "-"
  if host == "node0":
    host = "default"
  if Path("{}ansible_hosts".format(ns)).is_file():
    for line in list(open("{}ansible_hosts".format(ns))):
      result = re.search(r"[.]{host} .*ansible_host=([^ ]+)".format(host=host), line)
      if result:
        return result.groups()[0]
  if provider == "docker":
    container_name =  "{ns}{user}-{host}".format(ns=ns, user=user, host=host)
    return list(run_get_line(logger,
                             ["docker", "inspect", "-f", "{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}", container_name],
                             "Can't get node ip", print_cmd=False).splitlines())[0]

  raise Exception("Can't get node {host} ip".format(host=host))

def apply_node_actions(ns, _, actions, user, provider):
  extra_vars = {'extra_db_user': 'dba', 'extra_db_password': 'secret', 'extra_start_db': '1'}
  env = {"DB_USER":"dba", "DB_PASS":"secret", "START":"1"}
  db_features = []
  #print('Node: ', node, 'Actions: ',actions)
  if actions.development is not None:
    db_features.append("development")
  if actions.kmip_server is not None :
    extra_vars["extra_kmip_server"] = "1"
    env["KMIP_SERVER"] = "1"
  if actions.ldap is not None :
    extra_vars["extra_ldap_server"] = "1"
    env["LDAP_SERVER"] = "1"
  if actions.samba_client is not None:
    extra_vars["extra_samba_ip"] = resolve_hostname(ns, actions.samba_client, user, provider)
    extra_vars["extra_samba_pass"] = DEFAULT_PASSWORD
    extra_vars["extra_samba_sid"] = "FIND_WITH_SSH"
  if actions.ldap_master is not None:
    extra_vars["extra_ldap_server_ip"] = resolve_hostname(ns, actions.ldap_master, user, provider)
    env["LDAP_IP"] = extra_vars["extra_ldap_server_ip"]
  if actions.percona_backup_mongodb is not None:
    params = soft_params(actions.percona_backup_mongodb)
    extra_vars["extra_pbm_version"] = params["version"]
    if "s3" in params:
      extra_vars["extra_pbm_s3_url"] = params["s3"]
  if actions.percona_server_mongodb is not None:
    params = soft_params(actions.percona_server_mongodb)
    if "master" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["master"], user, provider)
    extra_vars["extra_psmdb_version"] = params["version"]
    extra_vars["extra_db_opts_file"] = "mongo/enable_wt.conf"
    if "replica-set" in params:
      actions.replica_set = params["replica-set"]
    if "rs" in params:
      actions.replica_set = params["rs"]
    if actions.replica_set is not None:
      extra_vars["extra_mongo_replicaset"] = actions.replica_set
      env["REPLICA_SET"] = actions.replica_set
      os.system("test -f secret/rs0-keyfile || openssl rand -base64 756 > secret/rs0-keyfile; test -f secret/{rs}-keyfile || cp secret/rs0-keyfile secret/{rs}-keyfile".format(rs=actions.replica_set))
    if (actions.shardsrv is not None) or ("role" in params and params["role"] == "shard"):
      extra_vars["extra_mongo_shardsrv"] = "1"
    if (actions.configsrv is not None) or  ("role" in params and params["role"] == "cfg"):
      extra_vars["extra_mongo_configsrv"] = "1"
    if actions.mongos_cfg is not None:
      (rs, servers) = actions.mongos_cfg.split("/",1)
      extra_vars["extra_mongos_cfg"] = rs+"/"+",".join([ resolve_hostname(ns, n, user, provider) +':27017'  for n in servers.split(',')])
    if actions.mongos_shard is not None:
      l = list(filter(None, re.split(r",?([^,/]+/)", actions.mongos_shard)))
      shard_txt = ""
      shard_list = []
      for i in range(0, len(l)//2):
        rs = l[2*i]
        servers = l[2*i+1]
        shard_txt = shard_txt + rs
        shard_list.append(rs+",".join([ resolve_hostname(ns, n, user, provider) +':27017'  for n in servers.split(',')]))
      extra_vars["extra_mongos_shard"] = ",".join(shard_list)
  if actions.percona_server is not None:
    params = soft_params(actions.percona_server)
    actions.percona_server = params["version"]

    extra_vars["extra_percona_server_version"] = actions.percona_server
    extra_vars["extra_db_opts_file"] = "mysql/async-repl-gtid.cnf"

    if "mysql-router" in params:
      actions.mysql_router = 'percona-server'
    if "master" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["master"], user, provider)
      env["DB_IP"] = extra_vars["extra_master_ip"]
    if "leader" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["leader"], user, provider)
      env["DB_IP"] = extra_vars["extra_master_ip"]
    if "group-replication" in params:
      extra_vars["extra_db_opts_file"] = "mysql/gr.cnf"
      extra_vars["extra_replication_type"] = "group"
    if "ldap" in params and params["ldap"] == "simple":
      db_features.append("ldap_simple")
    if "gtid" in params:
      if params["gtid"] == False or params["gtid"] in ("0","off","false") or params["gtid"] == 0:
        extra_vars["extra_replication_type"] = "nogtid"
        extra_vars["extra_db_opts_file"] = "mysql/async-repl-nogtid.cnf"
    if "rocksdb" in params:
      extra_vars["extra_rocksdb_enabled"] = "1"
    if "sql" in params:
      extra_vars["extra_s3sql"] = params["sql"]

    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["PS"] = actions.percona_server
    env["DB_OPTS"] = "mysql/async-repl-gtid.cnf"
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.mariadb is not None:
    params = soft_params(actions.mariadb)
    extra_vars["extra_mariadb_version"] = params["version"]
    if "galera" in params:
      extra_vars["extra_db_opts_file"] = "mariadb/galera.cnf"
      extra_vars["extra_replication_type"] = "galera"
    else:
      extra_vars["extra_db_opts_file"] = "mariadb/async-repl-gtid-row.cnf"
    if "master" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["master"], user, provider)
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
  if actions.k3s is not None:
    extra_vars["extra_k3s_version"] = actions.k3s
  if actions.mysql_server is not None:
    params = soft_params(actions.mysql_server)
    actions.mysql_server = params["version"]
    extra_vars["extra_mysql_version"] = actions.mysql_server
    extra_vars["extra_db_opts_file"] = "mysql/async-repl-gtid.cnf"

    if "mysql-router" in params:
      actions.mysql_router = 'mysql-server'
    if "master" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["master"], user, provider)
      env["DB_IP"] = extra_vars["extra_master_ip"]
    if "leader" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["leader"], user, provider)
      env["DB_IP"] = extra_vars["extra_master_ip"]

    if "gtid" in params:
      if params["gtid"] == False or params["gtid"] in ("0","off","false") or params["gtid"] == 0:
        extra_vars["extra_replication_type"] = "nogtid"
        extra_vars["extra_db_opts_file"] = "mysql/async-repl-nogtid.cnf"

    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["MYSQL"] = actions.mysql_server
    env["DB_OPTS"] = "mysql/async-repl-gtid.cnf"
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.sysbench:
    params = soft_params(actions.sysbench)
    extra_vars["extra_sysbench_version"] = params["version"]
    if "mysql" in params:
      extra_vars["extra_sysbench_mysql"] = resolve_hostname(ns, params["mysql"], user, provider)
      extra_vars["extra_db_user"] = "root"
      if "port" in params:
        extra_vars["extra_sysbench_port"] = params["port"]
    if "postgresql" in params:
      extra_vars["extra_sysbench_pg"] = resolve_hostname(ns, params["postgresql"], user, provider)
      extra_vars["extra_db_user"] = "root"
    if "oltprw" in params or "oltp-rw" in params:
      db_features.append("sysbench_oltp_read_write")
    extra_vars["extra_db_password"] = "verysecretpassword1^"

  if actions.patroni:
    params = soft_params(actions.patroni)
    extra_vars["extra_patroni_version"] = "1"
    if "leader" in params:
      extra_vars["extra_etcd_ip"] = resolve_hostname(ns, params["leader"], user, provider)
    if "primary" in params:
      extra_vars["extra_etcd_ip"] = resolve_hostname(ns, params["primary"], user, provider)
    if "master" in params:
      extra_vars["extra_etcd_ip"] = resolve_hostname(ns, params["master"], user, provider)

  if actions.repmgr:
    params = soft_params(actions.repmgr)
    extra_vars["extra_repmgr_version"] = params["version"]

  if actions.pgbackrest:
    params = soft_params(actions.pgbackrest)
    if "s3" in params:
      extra_vars["extra_minio_url"] = params["s3"]
    extra_vars["extra_pgbackrest_version"] = "1"
  if actions.percona_postgresql is not None:
    params = soft_params(actions.percona_postgresql)
    extra_vars["extra_percona_postgresql_version"] = params["version"]
    extra_vars["extra_db_user"] = "postgres"
    extra_vars["extra_db_password"] = "verysecretpassword1^"

    if actions.wal == "logical" or ("wal" in params and params["wal"]=="logical"):
      extra_vars["extra_db_opts_file"] = "postgresql/logical.conf"
    if "leader" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["leader"], user, provider)
    if "primary" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["primary"], user, provider)
    if "master" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["master"], user, provider)

    if actions.wal == "logical":
      extra_vars["extra_db_opts_file"] = "postgresql/logical.conf"
  if actions.pmm:
    params = soft_params(actions.pmm)
    extra_vars["extra_pmm_server_version"] = params["version"]
    if "password" in params:
      extra_vars["extra_db_password"] = params["password"]
    else:
      extra_vars["extra_db_password"] = "verysecretpassword1^"
    extra_vars["extra_docker"] = "1"
  if actions.pmm_client:
    params = soft_params(actions.pmm_client)
    if params["version"] in ("True","latest"):
      params["version"] = "2"
    extra_vars["extra_pmm_client_version"] = params["version"]
    if "server" not in params:
      params["server"] = "node0"
    if params["server"].startswith("http"):
      extra_vars["extra_pmm_url"] = params["server"]
    else:
      pass_encoded = urllib.parse.quote_plus(DEFAULT_PASSWORD)
      extra_vars["extra_pmm_url"] = "https://admin:{password}@{host}".format(
          password=pass_encoded,
          host=resolve_hostname(ns, params["server"], user, provider))
    if "slowlog" in params:
      db_features.append("slowlog")
    if "perfschema" in params:
      db_features.append("pmm_perfschema")
    if "profiler" in params:
      db_features.append("pmm_profiler")

  if actions.pg_stat_monitor:
    extra_vars["extra_pg_stat_monitor"] = "1"
  if actions.postgresql is not None:
    params = soft_params(actions.postgresql)
    extra_vars["extra_postgresql_version"] = params["version"]
    extra_vars["extra_db_user"] = "postgres"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    if actions.wal == "logical" or ("wal" in params and params["wal"]=="logical"):
      extra_vars["extra_db_opts_file"] = "postgresql/logical.conf"
    if "leader" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["leader"], user, provider)
    if "primary" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["primary"], user, provider)
    if "master" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["master"], user, provider)

  if actions.patroni is not None:
    extra_vars["extra_percona_patroni_version"] = "True" # actions.patroni
  if actions.mysql_router is not None:
    extra_vars["extra_mysql_router_version"] = actions.mysql_router
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["MYSQL_ROUTER"] = actions.mysql_router
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.percona_xtradb_cluster is not None:
    params = soft_params(actions.percona_xtradb_cluster)
    extra_vars["extra_percona_xtradb_cluster_version"] = params["version"]
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"

    env["PXC"] = actions.percona_xtradb_cluster
    if actions.percona_xtradb_cluster.startswith("5.6"):
      extra_vars["extra_db_opts_file"] = "mysql/pxc5657.cnf"
      env["DB_OPTS"] = "mysql/pxc5657.cnf"
    elif actions.percona_xtradb_cluster.startswith("5.7"):
      extra_vars["extra_db_opts_file"] = "mysql/pxc5657.cnf"
      env["DB_OPTS"] = "mysql/pxc5657.cnf"
    elif actions.percona_xtradb_cluster.startswith("8.0"):
      extra_vars["extra_db_opts_file"] = "mysql/pxc8-repl-gtid.cnf"
      env["DB_OPTS"] = "mysql/pxc8-repl-gtid.cnf"
    if "master" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["master"], user, provider)
    if "galera" in params:
      extra_vars["extra_replication_type"] = "galera"

    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.cluster_name:
    extra_vars["extra_cluster_name"] = actions.cluster_name
    env["CLUSTER"] = actions.cluster_name
  if actions.galera_leader:
    extra_vars["extra_master_ip"] = resolve_hostname(ns, actions.galera_leader, user, provider)
    extra_vars["extra_replication_type"] = "galera"
    env["DB_IP"] = extra_vars["extra_master_ip"]
    env["REPLICATION_TYPE"] = "galera"
  if actions.group_replication:
    extra_vars["extra_db_opts_file"] = "mysql/gr.cnf"
    extra_vars["extra_replication_type"] = "group"
    env["DB_OPTS"] = "mysql/gr.cnf"
    env["REPLICATION_TYPE"] = "group"
  if actions.s3sql:
    extra_vars["extra_s3sql"] = actions.s3sql
    env["S3SQL"] = actions.s3sql
  if actions.proxysql is not None:
    extra_vars["extra_proxysql_version"] = actions.proxysql
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["PROXYSQL"] = actions.proxysql
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.percona_proxysql is not None:
    params = soft_params(actions.percona_proxysql)
    if "master" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["master"], user, provider)
    extra_vars["extra_percona_proxysql_version"] = params["version"]
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
  if actions.haproxy_galera is not None: 
    extra_vars["extra_haproxy_galera"] = ','.join([resolve_hostname(ns, node, user, provider) for node in actions.haproxy_galera.split(',') ])
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["HAPROXY_GALERA"] = extra_vars["extra_haproxy_galera"]
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.clustercheck is not None:
    db_features.append("clustercheck")
  if actions.debug_packages is not None:
    extra_vars["extra_debug_packages"] = "1"
    env["DEBUG_PACKAGES"] = "1"
  if actions.rocksdb is not None:
    extra_vars["extra_rocksdb_enabled"] = "1"
    env["ROCKSDB"] = "1"
  if actions.percona_xtrabackup is not None:
    extra_vars["extra_percona_xtrabackup_version"] = actions.percona_xtrabackup
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["PXB"] = actions.percona_xtrabackup
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.mysql_jdbc is not None:
    extra_vars["extra_mysql_connector_java_version"] = actions.mysql_jdbc
    env["MYSQL_JAVA"] = actions.mysql_jdbc
  if actions.percona_orchestrator is not None:
    params = soft_params(actions.percona_orchestrator)
    if "master" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["master"], user, provider)
    extra_vars["extra_percona_orchestrator_version"] = params["version"]
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["PERCONA_ORCHESTRATOR"] = actions.percona_orchestrator
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.percona_proxysql is not None:
    params = soft_params(actions.percona_proxysql)
    if "master" in params:
      extra_vars["extra_master_ip"] = resolve_hostname(ns, params["master"], user, provider)
    extra_vars["extra_percona_proxysql_version"] = params["version"]
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.leader is not None:
    extra_vars["extra_master_ip"] = resolve_hostname(ns, actions.leader, user, provider)
    env["DB_IP"] = extra_vars["extra_master_ip"]
  if actions.etcd_ip is not None:
    extra_vars["extra_etcd_ip"] =  resolve_hostname(ns, actions.etcd_ip, user, provider)
  if len(db_features) > 0:
    extra_vars["extra_db_features"] = ",".join(db_features)
    env["DB_FEATURES"] = extra_vars["extra_db_features"]
  return env, extra_vars

def apply_node_command(node, env, cmd):
  run_fatal(logger, cmd, "failed to deploy node {}".format(node), env=env)

def create_nodes(provider, nodes_cnt, osver, ns, skip_nodes, priv_nodes):
  if provider == "kubectl":
    return
  create_nodes_cmd = "rm -f ssh_config ansible_hosts; ./docker_container.py --provider={provider} --nodes={nodes} --skip-nodes={skip_nodes} --priv-nodes={priv_nodes} --os={osver} --destroy --deploy".format(provider=provider, nodes=nodes_cnt, skip_nodes=skip_nodes, priv_nodes=priv_nodes, osver=osver)
  if ns != "":
    create_nodes_cmd = "rm -f {ns}-ssh_config {ns}-ansible_hosts; ./docker_container.py --provider={provider} --namespace={ns} --nodes={nodes} --skip-nodes={skip_nodes} --priv-nodes={priv_nodes} --os={os} --destroy --deploy".format(provider=provider, ns=ns, nodes=nodes_cnt, skip_nodes=skip_nodes, priv_nodes=priv_nodes, os=osver)

  logger.info(create_nodes_cmd)
  os.system(create_nodes_cmd)

def ssh_login(namespace, node, exec_command=[]):
  ns = namespace
  if ns != "":
    ns = ns + "-"
  if node == "node0":
    node = "default"
  #os.system("exec ssh -F {}ssh_config -o LogLevel=error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i secret/id_rsa -t root@{}".format(namespace, node))
  cmd_args = [ "/usr/bin/env", 'ssh','-F', "{}ssh_config".format(ns), '-o', 'LogLevel=error', '-t', "root@{}".format(node)]
  cmd_args.extend(exec_command)
  os.execl("/usr/bin/env", *cmd_args)

def screen_run(namespace):
  ns = namespace
  if ns != "":
    ns = ns + "-"
  os.execl("/usr/bin/env", "/usr/bin/env", 'screen','-c', "{}screenrc".format(ns))

def docker_exec(namespace, user, node, exec_command=[]):
  ns = namespace
  if ns != "":
    ns = ns + "-"
  if node == "node0":
    node = "default"
  if not sys.stdin.isatty():
    docker_interactive = "-i"
  else:
    docker_interactive = "-it"
  cmd_args = [ "/usr/bin/env", "docker","exec", docker_interactive, "{ns}{usr}-{n}".format(ns=ns, usr=user, n=node)]
  if len(exec_command):
    cmd_args.extend(exec_command)
  else:
    cmd_args.append("sh")
  os.execl("/usr/bin/env", *cmd_args)

def list_containers(ns, provider, user):
  if ns != "":
    ns = ns + "-"
  net = "{}{}-anydbver".format(ns, user)
  if provider == "docker":
    os.execl("/usr/bin/env", "/usr/bin/env", 'docker', 'ps', '-f', 'network={}'.format(net))

def mysql_cli_run(ns, node):
  if ns != "":
    ns = ns + "-"
  if node == "node0":
    node = "default"
  os.execl("/usr/bin/env", "/usr/bin/env", 'ssh','-F', "{}ssh_config".format(ns), '-o', 'LogLevel=error', '-t', "root@{}".format(node), "mysql")

def handle_non_deployment_commands():
  for cmd_idx, cmd in enumerate(sys.argv):
    if cmd in ('destroy', 'update', 'test', 'list', 'screen'):
      sys.argv[cmd_idx] = '--' + cmd

  cmd_donot_parse_part = []
  for cmd_idx, cmd in enumerate(sys.argv):
    if cmd == '--':
      cmd_donot_parse_part = sys.argv[cmd_idx+1:]
      sys.argv = sys.argv[0:cmd_idx]
      break
    if cmd in ('delete', 'ssh', 'exec', 'mysql', 'psql', 'ip'):
      sys.argv[cmd_idx] = '--' + cmd
      if cmd_idx+1 >= len(sys.argv) or sys.argv[cmd_idx+1].startswith("--"):
        sys.argv.insert(cmd_idx+1, "default")

  parser = argparse.ArgumentParser()
  parser.add_argument('--namespace', dest="namespace", type=str, default="")
  parser.add_argument('--provider', dest="provider", type=str, default="")
  parser.add_argument('--dry-run', dest="dry_run", action='store_true')
  parser.add_argument('--destroy', dest="destroy", action='store_true')
  parser.add_argument('--list', dest="list", action='store_true')
  parser.add_argument('--delete', dest="delete", action='store_true')
  parser.add_argument('--mysql', dest="mysql_cli", type=str, nargs='?')
  parser.add_argument('--test', dest="test", type=str, nargs='?')
  parser.add_argument('--update', dest="update", action='store_true')
  parser.add_argument('--ssh', dest="ssh", type=str, nargs='?')
  parser.add_argument('--screen', dest="screen", action='store_true')
  parser.add_argument('--exec', dest="exec", type=str, nargs='?')
  parser.add_argument('--ip', dest="ip", type=str, nargs='?')
  parser.add_argument('--tools', dest="tools", type=str, nargs='?')
  args = parser.parse_args()

  if args.provider == "lxd":
    sett = load_sett_file("lxd", False)
    if "LXD_PROFILE" in sett:
      pass
    args.user = sett["LXD_PROFILE"]
  elif "USER" in os.environ:
    args.user = os.environ["USER"]
  else:
    args.user = os.getlogin()

  if args.screen:
    screen_run(args.namespace)
    sys.exit(0)

  if args.ip or args.ssh or args.exec or args.update:
    detect_provider(args, False)
  else:
    detect_provider(args, True)


  if args.ip:
    host = "default"
    if args.ip != "":
      host = args.ip
    print(resolve_hostname(args.namespace, host, args.user, args.provider))
    sys.exit(0)
  if args.ssh:
    host = "default"
    if args.ssh != "":
      host = args.ssh
    ssh_login(args.namespace, host, cmd_donot_parse_part)
    sys.exit(0)
  elif args.exec:
    host = "default"
    if args.exec != "":
      host = args.exec
    if args.provider == "docker":
      docker_exec(args.namespace, args.user, host, cmd_donot_parse_part)
    sys.exit(0)
  elif sys.argv[1] in ("mysql", "--mysql"):
    host = "default"
    if args.mysql_cli == "":
      host = args.mysql
    mysql_cli_run(args.namespace, host)
    sys.exit(0)
  elif args.destroy:
    destroy(args)
  elif args.list:
    list_containers(args.namespace, args.provider, args.user)
    sys.exit(0)
  elif args.test:
    anydbver_tests.test(logger, args.test)
  elif args.tools and args.provider == "docker":
    for tool in args.tools.split(","):
      if tool in ("registry","docker-cache"):
        os.system("bash tools/docker_registry_cache.sh")
      elif tool in ("s3","minio"):
        os.system("bash tools/create_backup_server.sh")
    sys.exit(0)
  if args.update:
    update_versions()
    sys.exit(0)


  sys.exit(0)


def main():
  os.chdir(ANYDBVER_DIR)
  deployment = False
  help_cmd = False
  help_idx = 0
  argv_cnt = 0
  for arg in sys.argv:
    if arg in ("--help"):
        help_cmd = True
        help_idx = argv_cnt
    if arg in ("--deploy","deploy", "--replace", "replace", "--add", "add"):
      deployment = True
    argv_cnt = argv_cnt + 1

  if deployment and help_cmd:
    del(sys.argv[help_idx])

  if not deployment:
    handle_non_deployment_commands()

  if len(sys.argv) > 1:
    if sys.argv[1] in ("ssh", "--ssh"):
      host = "default"
      if len(sys.argv) > 2:
        host = sys.argv[2]
      ssh_login("", host)
      sys.exit(0)
    elif sys.argv[1] in ("mysql", "--mysql"):
      host = "default"
      if len(sys.argv) > 2:
        host = sys.argv[2]
      mysql_cli_run("", host)
      sys.exit(0)

  parser = argparse.ArgumentParser()
  parser.add_argument('--namespace', dest="namespace", type=str, default="")
  parser.add_argument('--provider', dest="provider", type=str, default="")
  parser.add_argument('--dry-run', dest="dry_run", action='store_true')
  parser.add_argument('--destroy', dest="destroy", action='store_true')
  parser.add_argument('--mysql', dest="mysql_cli", type=str, default="")
  parser.add_argument('--deploy', dest="deploy", action='store_true')
  parser.add_argument('--test', dest="test", type=str, default="")
  parser.add_argument('--update', dest="update", action='store_true')
  parser.add_argument('--ssh', dest="ssh", type=str, default="")
  parser.add_argument('--os', dest="os", type=str, default="rocky8")
  parser.add_argument('--simple', dest="simple", action='store_true')

  nodes=[]
  for x in range(0,100):
    nodes.append('node%x'%x)

  def groupargs(arg,currentarg=[None]):
      if(arg in nodes):currentarg[0]=arg
      return currentarg[0]

  raw_args = sys.argv
  fix_missing_node_commands(raw_args)

  nodelines = [list(args) for _,args in itertools.groupby(raw_args,groupargs)]

  main_args = nodelines.pop(0)
  main_args.pop(0)
  fix_main_commands(main_args)
  args = parser.parse_args(main_args)

  if "USER" in os.environ:
    args.user = os.environ["USER"]
  else:
    args.user = os.getlogin()

  detect_provider(args, not deployment)

  ns_prefix = args.namespace
  if ns_prefix != "":
    ns_prefix = ns_prefix + "-"
  node_actions = []
  node_names = {}
  nodes_os = args.os + ","
  args.skip_nodes = ""
  args.priv_nodes = ""
  if len(nodelines) == 0:
    nodelines.append(['node0'])
  for nodeline in nodelines:
    node_actions.append(parse_node(nodeline, help_cmd))
    node = node_actions[-1][0]
    node_names[ node ] = 1
    if (node_actions[-1][1]).os == "":
      (node_actions[-1][1]).os = args.os
    nodes_os = nodes_os + node + "=" + (node_actions[-1][1]).os + ","
    act = node_actions[-1][1]
    if act.k3d or (args.provider == "docker"
                   and (act.k8s_ps or act.k8s_pxc or act.k8s_pg or act.k8s_mongo
                        or is_unmodified_docker_image(act) )):
      if args.skip_nodes == "":
        args.skip_nodes = node
      else:
        args.skip_nodes = args.skip_nodes + "," + node
      if node == "node0":
        args.skip_nodes = args.skip_nodes + "," + "default"
    if args.provider == "lxd" and act.pmm:
      if args.priv_nodes == "":
        args.priv_nodes = node
      else:
        args.priv_nodes = args.priv_nodes + "," + node
      if node == "node0":
        args.priv_nodes = args.priv_nodes + "," + "default"


  if args.destroy or args.deploy:
    destroy(args)


  download_dependencies()

  nodes_cnt = len(node_names)
  if args.deploy and not help_cmd:
    create_nodes(args.provider, nodes_cnt, nodes_os, args.namespace, args.skip_nodes, args.priv_nodes)

  cmds = []

  ansible_hosts_run = open("{}ansible_hosts_run".format(ns_prefix), "w")

  has_net = False

  for n in node_actions:
    node = n[0]
    if node == "node0":
      node = "default"
    if args.provider == "docker" and is_unmodified_docker_image(n[1]):
      node_name = "{}{}-{}".format(ns_prefix,args.user, node)
      net = "{}{}-anydbver".format(ns_prefix, args.user)
      if not has_net:
        run_fatal(logger, ["docker", "network", "create", net], "Can't create a docker network", "already exists")
        has_net = True
      deploy_unmodified_docker_images(args.user, args.namespace, node_name, n[1])


  for n in node_actions:
    node = n[0]
    if node == "node0":
      node = "default"
    if args.provider == "docker" and is_unmodified_docker_image(n[1]):
      node_name = "{}{}-{}".format(ns_prefix,args.user, node)
      setup_unmodified_docker_images(args.user, args.namespace, node_name, n[1])

    (_, extra_vars) = apply_node_actions(args.namespace, node, n[1], args.user, args.provider)

    extrastr = ""
    for v in extra_vars:
      extrastr = extrastr + " " + v + "='" + extra_vars[v] + "'"

    python_path="/usr/bin/python3"

    if n[1].os in ("centos7", "el7"):
        python_path="/usr/bin/python"

    if node not in args.skip_nodes.split(",") and args.provider in ("lxd", "docker"):
      ansible_hosts_run.write(
      "{user}.{node} ansible_connection=ssh ansible_user=root ansible_ssh_private_key_file=secret/id_rsa ansible_host={ip} ansible_python_interpreter={python_path} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o GSSAPIDelegateCredentials=no -o GSSAPIKeyExchange=no -o GSSAPITrustDNS=no -o ProxyCommand=none' {extra_vars}\n".format(
          user=args.user,node=node, python_path=python_path,extra_vars=extrastr, ip=resolve_hostname(args.namespace, node, args.user, args.provider))
      )
      logger.info('Node ' + node + ': ' + extrastr.replace('extra_',''))

  ansible_hosts_run.close()
  for cmd in cmds:
    apply_node_command(cmd[0], cmd[1], cmd[2])

  if args.provider == "":
    logger.fatal("No working providers found")
    sys.exit(1)

  if args.mysql_cli != "":
    run_mysql_cli(args)

  if args.deploy:
    deploy(args, node_actions)

if __name__ == '__main__':
  main()