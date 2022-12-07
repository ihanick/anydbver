#!/usr/bin/env python3
import logging
import os
import re
import sys
import argparse
import itertools
import subprocess
from pathlib import Path
import urllib.request

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
  if args.provider == "docker" and Path("tools/k3d").is_file():
    run_fatal(["tools/k3d", "cluster", "delete", cluster], "Can't remove k3d cluster")
  for c in get_servers_list(args.provider, net):
    if c != "":
      run_fatal([args.provider, "rm", "-f", c], "Can't remove container")
  run_fatal([args.provider, "network", "rm", net], "Can't remove network", r"No such network:")
  run_fatal([args.provider, "run", "-i", "--rm", "-v",
    str((Path(os.getcwd()) / "data").resolve())+":/data",
    "busybox", "sh", "-c", "rm -rf -- /data/*"], "Can't clean data directory")

def deploy(args, node_actions):
  logger.info("Deploy")
  net = "{}{}-anydbver".format(args.namespace, args.user)
  cluster = "{}-cluster1".format(args.user)
  for node_action in node_actions:
    print("Applying node: ", node_action)
    node = node_action[1]

    run_k8s_operator_cmd = ['python3', 'tools/run_k8s_operator.py']
    if args.provider == "docker":
      if node.k3d:
        if not Path("tools/k3d").is_file():
          run_fatal(["bash", "-c", "curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | PATH=$PATH:/home/ihanick/anydbver/Docker/tools K3D_INSTALL_DIR=$PWD/tools USE_SUDO=false bash"], "Can't download k3d")
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

def append_versions_from_url(vers, url, r):
  with urllib.request.urlopen(url) as response:
    m = re.findall(r, response.read().decode('utf-8'))
    for i in m:
      vers.append(i[1])

def update_versions():
  versions = []
  if not os.path.exists(".version-info"):
    os.makedirs(".version-info")
  append_versions_from_url(versions,
    "https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/",
    r'Percona-Server-MongoDB(-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm')
  append_versions_from_url(versions,
    "https://repo.percona.com/psmdb-40/yum/release/8/RPMS/x86_64/",
    r'percona-server-mongodb(-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm')
  append_versions_from_url(versions,
    "https://repo.percona.com/psmdb-42/yum/release/8/RPMS/x86_64/",
    r'percona-server-mongodb(-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm')
  append_versions_from_url(versions,
    "https://repo.percona.com/psmdb-44/yum/release/8/RPMS/x86_64/",
    r'percona-server-mongodb(-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm')
  append_versions_from_url(versions,
    "https://repo.percona.com/psmdb-50/yum/release/8/RPMS/x86_64/",
    r'percona-server-mongodb(-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm')
  with open(".version-info/psmdb.el8.txt", "w") as f:
    f.write("\n".join(versions))

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
    if cmd in ('deploy', 'add', 'replace', 'destroy', 'delete', 'update', 'ssh'):
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

def find_version(args):
  for p in ('psmdb',):
    if args.percona_server_mongodb:
      vers = list(open(".version-info/psmdb.el8.txt"))
      version = vers[-1]
      for line in reversed(vers):
        ver = line.rstrip()
        if ver.startswith(args.percona_server_mongodb):
          version = ver
          break
      args.percona_server_mongodb = version
      #print('looking psmdb version {} in .version-info/psmdb.el8.txt, found: {}'.format(args.percona_server_mongodb, version))

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
  parser.add_argument('--ldap', type=str, nargs='?')
  parser.add_argument('--percona-server-mongodb', '--psmdb', type=str, nargs='?')
  parser.add_argument('--ldap-master', type=str, nargs='?')
  parser.add_argument('--replica-set', type=str, nargs='?')
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

  find_version(args)

  return node,args

def resolve_hostname(host):
  return run_get_line(["bash", "./anydbver", "ip", host ], "Can't get node ip").rstrip()

def apply_node_actions(node, actions):
  env = {"DB_USER":"dba", "DB_PASS":"secret", "START":"1"}
  print('Node: ', node, 'Actions: ',actions)
  if actions.ldap is not None :
    env["LDAP_SERVER"] = "1"
  if actions.ldap_master is not None:
    env["LDAP_IP"] = resolve_hostname(actions.ldap_master)
  if actions.percona_server_mongodb is not None:
    env["PSMDB"] = actions.percona_server_mongodb
    env["DB_OPTS"] = "mongo/enable_wt.conf"
    if actions.replica_set is not None:
      env["REPLICA_SET"] = actions.replica_set
  if actions.leader is not None:
    env["DB_IP"] = resolve_hostname(actions.leader)
  return env

def apply_node_command(node, env, cmd):
  env.update(os.environ.copy())
  run_fatal(cmd, "failed to deploy node {}".format(node), env=env)

def create_nodes(nodes_cnt):
  os.system("rm -f ssh_config ansible_hosts; ./docker_container.py --nodes={} --destroy --deploy".format(nodes_cnt))


def ssh_login(namespace, node):
  if node == "node0":
    node = "default"
  os.system("ssh -F {}ssh_config -o LogLevel=error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i secret/id_rsa -t root@{}".format(namespace, node))

def main():
  if len(sys.argv) > 1 and sys.argv[1] in ("ssh", "--ssh"):
    host = "default"
    if len(sys.argv) > 2:
      host = sys.argv[2]
    ssh_login("", host)
    sys.exit(0)

  parser = argparse.ArgumentParser()
  parser.add_argument('--namespace', dest="namespace", type=str, default="")
  parser.add_argument('--provider', dest="provider", type=str, default="")
  parser.add_argument('--dry-run', dest="dry_run", action='store_true')
  parser.add_argument('--destroy', dest="destroy", action='store_true')
  parser.add_argument('--mysql', dest="mysql_cli", type=str, default="")
  parser.add_argument('--deploy', dest="deploy", action='store_true')
  parser.add_argument('--update', dest="update", action='store_true')
  parser.add_argument('--ssh', dest="ssh", type=str, default="")

  nodes=[]
  for x in range(0,100):
    nodes.append('node%x'%x)

  def groupargs(arg,currentarg=[None]):
      if(arg in nodes):currentarg[0]=arg
      return currentarg[0]

  raw_args = sys.argv
  fix_missing_node_commands(raw_args)

  nodelines = [list(args) for cmd,args in itertools.groupby(raw_args,groupargs)]

  main_args = nodelines.pop(0)
  main_args.pop(0)
  fix_main_commands(main_args)
  args = parser.parse_args(main_args)
  args.user = os.getlogin()

  if args.update:
    update_versions()
    sys.exit(0)

  node_actions = []
  node_names = {}
  for nodeline in nodelines:
    node_actions.append(parse_node(nodeline))
    node = node_actions[-1][0]
    node_names[ node ] = 1

  nodes_cnt = len(node_names)
  create_nodes(nodes_cnt)

  cmds = []
  for n in node_actions:
    node = n[0]
    if node == "node0":
      node = "default"
    env = apply_node_actions(node, n[1])
    if sys.platform == "linux" or sys.platform == "linux2":
      cmds.append(
          (node,
            env,
            ["ansible-playbook", "-i", "ansible_hosts", "--limit", "{}.{}".format(args.user, node), "playbook.yml"])
          )
    else:
      envstr = ""
      for v in env:
        envstr = envstr + " " + v + "=" + env[v]
      ssh_config = open('ssh_config').read()
      ansible_hosts = open('ansible_hosts').read()
      open('playbook_run.sh', "w").write(
"""
cat > /anydbver/ssh_config <<EOF1
{ssh_config}
EOF1
cat > /anydbver/ansible_hosts <<EOF2
{ansible_hosts}
EOF2
cd /anydbver; {env} ansible-playbook -i ansible_hosts --limit {user}.{node} playbook.yml
""".format(ssh_config=ssh_config, ansible_hosts=ansible_hosts, env=envstr, user=args.user, node=node) )
      playbook_cmd = """cat playbook_run.sh | docker run --network {user}-anydbver --rm -i -e USER={user} rockylinux:8-anydbver-ansible bash""".format(user=args.user, node=node)
      os.system(playbook_cmd )
  print(args)
  print(node_actions)
  print(cmds)


  for cmd in cmds:
    apply_node_command(cmd[0], cmd[1], cmd[2])

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
