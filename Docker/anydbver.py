#!/usr/bin/env python3
import logging
import os
import re
import sys
import argparse
import itertools
import subprocess
from pathlib import Path
import time
import datetime

COMMAND_TIMEOUT=600
FORMAT = '%(asctime)s %(levelname)s %(message)s'
logging.basicConfig(format=FORMAT)
logger = logging.getLogger('AnyDbVer')
logger.setLevel(logging.INFO)

def run_fatal(args, err_msg, ignore_msg=None, print_cmd=True, env=None):
  if print_cmd:
    logger.info(subprocess.list2cmdline(args))
  process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, close_fds=True, env=env)
  output = ''
  while process.poll() is None:
    text = process.stdout.readline().decode('utf-8')
    output = output + text
    #log.write(text)
    if print_cmd:
      sys.stdout.write(text)
  ret_code = process.wait(timeout=COMMAND_TIMEOUT)
  #output = process.communicate()[0].decode('utf-8')
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
  
def get_servers_list(provider, net):
  return list(run_get_line([provider, "ps", "-a", "--filter", "network="+net, "--format", "{{.ID}}"],
    "Can't get containers list").splitlines())

def destroy(args):
  logger.info("Removing nodes")
  net = "{}{}-anydbver".format(args.namespace, args.user)
  cluster = "{}-cluster1".format(args.user)
  if args.provider == "docker":
    run_fatal(["tools/k3d", "cluster", "delete", cluster], "Can't remove k3d cluster")
  for c in get_servers_list(args.provider, net):
    if c != "":
      run_fatal([args.provider, "rm", "-f", c], "Can't remove container")
  run_fatal([args.provider, "network", "rm", net], "Can't remove network", r"No such network:")
  run_fatal([args.provider, "run", "-i", "--rm", "-v",
    str((Path(os.getcwd()) / "data").resolve())+":/data",
    "busybox", "sh", "-c", "rm -rf -- /data/*"], "Can't clean data directory")

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
  return sett


def docker_mysql_wait_for_ready(node, net, timeout=COMMAND_TIMEOUT):
  logger.info("Waiting for mysql ready on: {}".format(node))
  for i in range(timeout // 2):
    s = datetime.datetime.now()
    if run_fatal(["docker", "run", "--rm", "--network", net, "percona/percona-server:8.0", "mysql", "-uroot", "-psecret", "-h", node, "-e", "SELECT 1"],
        "Pod ready wait problem",
        r"Unknown MySQL server host|Can't connect to MySQL server on", False) == 0:
      return True
    if (datetime.datetime.now() - s).total_seconds() < 1.5:
      time.sleep(2)
  return False


def deploy(args, node_actions):
  logger.info("Deploy")
  net = "{}{}-anydbver".format(args.namespace, args.user)
  cluster = "{}-cluster1".format(args.user)

  if args.provider == "docker":
    run_fatal([args.provider, "network", "create", net], "Failed to create a docker network")
  for node_action in node_actions:
    print("Applying node: ", node_action)
    node_name = node_action[0]
    node = node_action[1]

    run_k8s_operator_cmd = ['python3', 'tools/run_k8s_operator.py']
    if args.provider == "docker":
      if node.percona_xtradb_cluster:
        sett = parse_settings('percona_xtradb_cluster', node.percona_xtradb_cluster)
        img = 'percona/percona-xtradb-cluster:' + sett['version']
        node_dir = str((Path(os.getcwd()) / "data" / "node0").resolve())
        my_cnf = str((Path(node_dir) / "mysqld.cnf").resolve())
        if not Path(my_cnf).is_file():
          run_fatal(["mkdir", "-p", node_dir], "can't a create directory for node")
          with open(my_cnf,"w+") as f:
                    f.writelines("""\
[mysqld]
pxc-encrypt-cluster-traffic=OFF""")



        container_name = "{}-{}".format(args.user, node_name)
        pxc_run_cmd = [args.provider, "run", "-d",
                       "-e", "CLUSTER_NAME=cluster1",
                       "-e", "MYSQL_ROOT_PASSWORD=secret",
                       "-v", my_cnf + ":/etc/my.cnf.d/mysqld.cnf:ro",
                       "--network", net,
                       "--name", container_name]

        if 'join' in sett:
          pxc_run_cmd.append('-e')
          pxc_run_cmd.append('CLUSTER_JOIN={}-'.format(args.user) + sett['join'])

        pxc_run_cmd.append(img)
        run_fatal(pxc_run_cmd, "failed to start pxc node")
        docker_mysql_wait_for_ready(container_name, net)

         #docker run -d -e MYSQL_ROOT_PASSWORD=secret -e CLUSTER_NAME=cluster1 -v $PWD/data/node0/mysqld.cnf:/etc/my.cnf.d/mysqld.cnf:ro --name ihanick-node0 --network ihanick-anydbver percona/percona-xtradb-cluster:8.0
         #docker run -d -e MYSQL_ROOT_PASSWORD=secret -e CLUSTER_NAME=cluster1 -e CLUSTER_JOIN=172.24.0.7 -v $PWD/data/node0/mysqld.cnf:/etc/my.cnf.d/mysqld.cnf:ro --name ihanick-node1 --network ihanick-anydbver percona/percona-xtradb-cluster:8.0
         #docker run -d -e MYSQL_ROOT_PASSWORD=secret -e CLUSTER_NAME=cluster1 -e CLUSTER_JOIN=172.24.0.7 -v $PWD/data/node0/mysqld.cnf:/etc/my.cnf.d/mysqld.cnf:ro --name ihanick-node2 --network ihanick-anydbver percona/percona-xtradb-cluster:8.0

      if node.k3d:
        if not Path("tools/k3d").is_file():
          run_fatal(["bash", "-c", "curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | PATH=$PATH:/home/zelmar/anydbver/Docker/tools K3D_INSTALL_DIR=$PWD/tools USE_SUDO=false bash"], "Can't download k3d")
        k3d_agents = "3"
        if node.k3d == 'True':
          node.k3d = 'latest'
        k3d_create_cmd = ["tools/k3d", "cluster", "create", "-i", "rancher/k3s:{}".format(node.k3d) , "--network", net, "-a", k3d_agents]
        if node.k8s_cluster_domain:
          k3d_create_cmd.append("--k3s-arg")
          k3d_create_cmd.append("--cluster-domain={}@server:0".format(node.k8s_cluster_domain))
        if node.ingress_port:
          k3d_create_cmd.append("--k3s-arg")
          k3d_create_cmd.append("--disable=traefik@server:0")
          k3d_create_cmd.append("-p")
          k3d_create_cmd.append("{ingress_port}:{ingress_port}@loadbalancer".format(ingress_port=node.ingress_port))
          run_k8s_operator_cmd.append("--ingress=nginx")
          run_k8s_operator_cmd.append("--ingress-port={}".format(node.ingress_port))
        k3d_create_cmd.append(cluster)
        run_fatal(k3d_create_cmd, "Can't create k3d cluster")
        run_fatal(["sh", "-c", """kubectl get sc local-path -o yaml | sed -r -e 's/name: local-path/name: standard/g' -e '/(uid|creationTimestamp|resourceVersion):/d' -e 's/is-default-class: "true"/is-default-class: "false"/' | kubectl apply -f -"""], "Can't create 'standard' storage class for local-path provisioner")
        args.provider = "kubectl"
        #run_fatal(["kubectl", "apply", "-f", "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"], "Can't install metrics server")
        
    if args.provider == "kubectl":
      if node.helm:
        run_k8s_operator_cmd.append("--helm")
      if node.k8s_namespace:
        run_k8s_operator_cmd.append("--namespace={}".format(node.k8s_namespace))
      if node.pmm:
        if node.pmm == "True":
          node.pmm = "2.31.0,helm=percona-helm-charts:0.3.9,certs=self-signed,namespace=monitoring"
        run_k8s_operator_cmd.append("--pmm={}".format(node.pmm))
      if node.cluster_name:
        run_k8s_operator_cmd.append("--cluster-name={}".format(node.cluster_name))
      if node.k8s_pxc:
        logger.info("Starting PXC in kubernetes managed by Percona operator {}".format(node.k8s_pxc))
        run_k8s_operator_cmd.append("--operator=percona-xtradb-cluster-operator")
        run_k8s_operator_cmd.append("--version={}".format(node.k8s_pxc))
        if node.db_version:
          run_k8s_operator_cmd.append("--db-version={}".format(node.db_version))
      if node.k8s_pg:
        logger.info("Starting postgresql in kubernetes managed by Percona operator {}".format(node.k8s_pg))
        run_k8s_operator_cmd.append("--operator=percona-postgresql-operator")
        if "," in node.k8s_pg:
          s = node.k8s_pg.split(',', 1)
          logger.info("version: {} params: {}".format(s[0],s[1]))
          run_k8s_operator_cmd.append("--version={}".format(s[0]))
          run_k8s_operator_cmd.append("--operator-options={}".format(s[1]))
        else:
          run_k8s_operator_cmd.append("--version={}".format(node.k8s_pg))
        if node.db_version:
          run_k8s_operator_cmd.append("--db-version={}".format(node.db_version))
      if node.k8s_ps:
        logger.info("Starting Percona Server for MySQL in kubernetes managed by Percona operator {}".format(node.k8s_ps))
        run_k8s_operator_cmd.append("--operator=percona-server-mysql-operator")
        run_k8s_operator_cmd.append("--version={}".format(node.k8s_ps))
        if node.db_version:
          run_k8s_operator_cmd.append("--db-version={}".format(node.db_version))
      if node.k8s_mongo:
        logger.info("Starting Percona Server for MongoDB in kubernetes managed by Percona operator {}".format(node.k8s_mongo))
        run_k8s_operator_cmd.append("--operator=percona-server-mongodb-operator")
        run_k8s_operator_cmd.append("--version={}".format(node.k8s_mongo))
        if node.db_version:
          run_k8s_operator_cmd.append("--db-version={}".format(node.db_version))

      if node.cert_manager:
        if str(node.cert_manager) == 'True':
          run_k8s_operator_cmd.append("--cert-manager")
        else:
          run_k8s_operator_cmd.append("--cert-manager={}".format(node.cert_manager))

      if node.sql_file:
        run_k8s_operator_cmd.append("--sql={}".format(node.sql_file))

      if node.k8s_minio:
        if node.minio_certs:
          run_k8s_operator_cmd.append("--minio-certs={}".format(node.minio_certs))

        if str(node.k8s_minio) == 'True':
          run_k8s_operator_cmd.append("--minio")
        else:
          run_k8s_operator_cmd.append("--minio={}".format(node.k8s_minio))

      if node.ingress_port or node.k8s_pg or node.k8s_pxc or node.k8s_ps or node.k8s_mongo or node.pmm:
        run_fatal(run_k8s_operator_cmd, "Can't run the operator")

def detect_provider(args):
  if args.provider in ("kubectl", "kubernetes", "k8s"):
      if re.search(
          r"Server Version",
          run_get_line(["kubectl", "version"],
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
          r"Server: Docker",
          run_get_line(["docker", "version"],
            "Can't find docker",
            r"Cannot connect to the Docker")):
        logger.info("Found docker server")
        args.provider="docker"
      else:
        args.provider = ""
    except FileNotFoundError as e:
      args.provider=""
      return
  else:
    args.provider=""

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
  sys.exit(0)


def fix_main_commands(args):
  for cmd_idx, cmd in enumerate(args):
    if cmd in ('deploy', 'add', 'replace', 'destroy', 'delete'):
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

def parse_node(args):
  node = args.pop(0)

  for cmd_idx, cmd in enumerate(args):
    if ':' not in cmd:
      cmd = cmd + ":True"
    if not cmd.startswith("--"):
      cmd = re.sub(r'^', '--', cmd).replace(':','=', 1)
    args[cmd_idx] = cmd

  parser = argparse.ArgumentParser()
  parser.add_argument('--percona-server', '--ps', type=str, nargs='?')
  parser.add_argument('--percona-xtradb-cluster', '--pxc', type=str, nargs='?')
  parser.add_argument('--percona-postgresql', '--percona-postgres', '--ppg', type=str, nargs='?')
  parser.add_argument('--leader', '--master', '--primary', type=str, nargs='?')
  parser.add_argument('--percona-xtrabackup', type=str, nargs='?')
  parser.add_argument('--percona-toolkit', type=str, nargs='?')
  parser.add_argument('--cert-manager', dest="cert_manager", type=str, nargs='?')
  parser.add_argument('--k8s-minio', dest="k8s_minio", type=str, nargs='?')
  parser.add_argument('--minio-certs', dest="minio_certs", type=str, nargs='?')
  parser.add_argument('--k3d', type=str, nargs='?')
  parser.add_argument('--helm', type=str, nargs='?')
  parser.add_argument('--k8s-pg', dest="k8s_pg", type=str, nargs='?')
  parser.add_argument('--k8s-ps', dest="k8s_ps", type=str, nargs='?')
  parser.add_argument('--k8s-mongo', dest="k8s_mongo", type=str, nargs='?')
  parser.add_argument('--k8s-pxc', dest="k8s_pxc", type=str, nargs='?')
  parser.add_argument('--pmm', dest="pmm", type=str, nargs='?')
  parser.add_argument('--db-version', dest="db_version", type=str, nargs='?')
  parser.add_argument('--cluster-name', dest="cluster_name", type=str, nargs='?')
  parser.add_argument('--k8s-cluster-domain', type=str, nargs='?')
  parser.add_argument('--k8s-namespace', type=str, nargs='?')
  parser.add_argument('--sql', dest="sql_file", type=str, nargs='?')
  parser.add_argument('--nginx-ingress', '--ingress-port', dest="ingress_port", type=str, nargs='?')
  args = parser.parse_args(args)
  return node,args

def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--namespace', dest="namespace", type=str, default="")
  parser.add_argument('--provider', dest="provider", type=str, default="")
  parser.add_argument('--dry-run', dest="dry_run", action='store_true')
  parser.add_argument('--destroy', dest="destroy", action='store_true')
  parser.add_argument('--mysql', dest="mysql_cli", type=str, default="")
  parser.add_argument('--deploy', dest="deploy", action='store_true')

  node_usage_index = 1

  def groupargs(arg,currentarg=[None]):
    nonlocal node_usage_index
    if re.match("^node[0-9]+",arg):
      currentarg[0]= "{}-{}".format(arg, node_usage_index)
      node_usage_index = node_usage_index + 1
    print("groupargs:", arg, currentarg)
    return currentarg[0]

  raw_args = sys.argv
  fix_missing_node_commands(raw_args)

  nodelines = [list(args) for cmd,args in itertools.groupby(raw_args,groupargs)]

  main_args = nodelines.pop(0)
  main_args.pop(0)
  fix_main_commands(main_args)
  args = parser.parse_args(main_args)

  node_actions = []
  for nodeline in nodelines:
    node_actions.append(parse_node(nodeline))

  print(args)
  print(node_actions)
  #sys.exit(0)

  args.user = os.getlogin()

  detect_provider(args)

  if args.provider == "":
    logger.fatal("No working providers found")
    sys.exit(1)

  if args.mysql_cli != "":
    run_mysql_cli(args)

  if args.destroy:
    destroy(args)

  if args.deploy:
    deploy(args, node_actions)

if __name__ == '__main__':
  main()
