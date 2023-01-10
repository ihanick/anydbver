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
import sqlite3

COMMAND_TIMEOUT=600
FORMAT = '%(asctime)s %(levelname)s %(message)s'
logging.basicConfig(format=FORMAT)
logger = logging.getLogger('AnyDbVer')
logger.setLevel(logging.INFO)

def run_fatal(args, err_msg, ignore_msg=None, print_cmd=True, env={}):
  if print_cmd:
    envstr = ""
    for v in env:
      envstr = envstr + " " + v + "=" + env[v]
    logger.info(envstr + " " + subprocess.list2cmdline(args))
  env.update(os.environ.copy())
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

  run_fatal(["ansible-playbook", "-i", "ansible_hosts_run", "playbook.yml"], "Error running playbook")

def append_versions_from_url(vers, url, r):
  with urllib.request.urlopen(url) as response:
    m = re.findall(r, response.read().decode('utf-8'))
    for i in m:
      vers.append(i)

def generate_versions_file(filename, src_info):
  versions = []
  for prg in src_info:
    append_versions_from_url(versions, prg["url"], prg["pattern"])
  # keep only unique versions
  versions = list(dict.fromkeys(versions))
  with open( str((Path(os.getcwd()) / ".version-info" / filename).resolve()), "w") as f:
    f.write("\n".join(versions) + "\n")
    

def save_mysql_server_versions_to_sqlite(osver):
  db_file = 'anydbver_version.db'
  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except Error as e:
    print(e)
    return
  cur = conn.cursor()
  vers = list(open(".version-info/mysql.{os}.txt".format(os=osver)))
  sql = """\
INSERT OR REPLACE INTO mysql_server_version(
  version, os, repo_url, repo_file, repo_enable_str,
  systemd_service, cnf_file, packages,
  debug_packages,
  tests_packages, mysql_shell_packages
)
VALUES (?,?,?,?,?,?,?,?,?,?,?)
"""
  for line in vers:
    ver = line.rstrip()
    project = ()
    if osver.startswith('el'):
      pkgs = ["mysql-community-common", "mysql-community-libs", "mysql-community-client", "mysql-community-server"]
      dbg_pkg = ['gdb']
      if ver.startswith('8.0'):
        dbg_pkg.append('https://cdn.mysql.com//Downloads/MySQL-8.0/mysql-community-debuginfo-{ver}.{osver}.x86_64.rpm'.format(ver=ver,osver=osver))
      if ver.startswith('5.7'):
        dbg_pkg.append('https://cdn.mysql.com//Downloads/MySQL-5.7/mysql-community-debuginfo-{ver}.{osver}.x86_64.rpm'.format(ver=ver,osver=osver))
      if ver.startswith('5.6'):
        dbg_pkg.append('https://cdn.mysql.com//Downloads/MySQL-5.6/mysql-community-debuginfo-{ver}.{osver}.x86_64.rpm'.format(ver=ver,osver=osver))
      if osver == 'el7':
        repo_url = 'http://repo.mysql.com/mysql80-community-release-el7-7.noarch.rpm'
      elif osver == 'el8':
        repo_url = 'http://repo.mysql.com/mysql80-community-release-el8-4.noarch.rpm'
      elif osver == 'el9':
        repo_url = 'http://repo.mysql.com/mysql80-community-release-el9-1.noarch.rpm'

      mysql_shell_pkg = 'https://cdn.mysql.com/archives/mysql-shell/mysql-shell'
      if ver.startswith('8.0.31'):
        mysql_shell_pkg = 'http://cdn.mysql.com/Downloads/MySQL-Shell/mysql-shell'
      mysql_shell_pkg = '{url}-{ver}.{osver}.x86_64.rpm'.format(url=mysql_shell_pkg,ver=ver,osver=osver)
      project = (
        ver, osver, repo_url,
        '',
        '', 'mysqld', '/etc/my.cnf',
        '|'.join(["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]),
        '|'.join(dbg_pkg),
        'mysql-community-test-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        mysql_shell_pkg
      )

    if len(project) > 1:
      cur.execute(sql, project)
  conn.commit()
    
def save_percona_xtradb_cluster_versions_to_sqlite(osver):
  db_file = 'anydbver_version.db'
  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except Error as e:
    print(e)
    return
  cur = conn.cursor()
  vers = list(open(".version-info/percona-xtradb-cluster.{os}.txt".format(os=osver)))
  sql = """\
INSERT OR REPLACE INTO percona_xtradb_cluster_version(
  version, os, repo_url, repo_file, repo_enable_str,
  systemd_service, cnf_file, packages,
  debug_packages,
  tests_packages, garbd_packages
)
VALUES (?,?,?,?,?,?,?,?,?,?,?)
"""
  for line in vers:
    ver = line.rstrip()
    project = ()
    if ver.startswith('8.0') and osver.startswith('el'):
      pkgs = ['percona-xtradb-cluster-shared','percona-xtradb-cluster-client','percona-xtradb-cluster-server']
      if osver != 'el9':
        pkgs.insert(0,'percona-xtradb-cluster-shared-compat')
      pkgs = ["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]
      pkgs.insert(0,'openssl')
      project = (
        ver, osver,
        'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
        '/etc/yum.repos.d/percona-pxc-80-release.repo',
        'pxc-80', 'mysqld', '/etc/my.cnf',
        '|'.join(pkgs),
        'gdb|percona-xtradb-cluster-debuginfo-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'percona-xtradb-cluster-test-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'percona-xtradb-cluster-garbd-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver)
      )
    elif ver.startswith('5.7') and osver.startswith('el'):
      pkgs = ['Percona-XtraDB-Cluster-shared-compat-57','Percona-XtraDB-Cluster-shared-57','Percona-XtraDB-Cluster-client-57','Percona-XtraDB-Cluster-server-57']
      project = (
        ver, osver,
        'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
        '/etc/yum.repos.d/percona-original-release.repo',
        'pxc-57', 'mysqld', '/etc/percona-xtradb-cluster.conf.d/zz_mysqld.cnf',
        '|'.join(["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]),
        'gdb|Percona-XtraDB-Cluster-57-debuginfo-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-XtraDB-Cluster-test-57-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-XtraDB-Cluster-garbd-57-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver)
      )
    elif ver.startswith('5.6') and osver.startswith('el'):
      pkgs = ['Percona-XtraDB-Cluster-shared-56','Percona-XtraDB-Cluster-client-56','Percona-XtraDB-Cluster-server-56']
      pkgs = ["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]
      pkgs.insert(0,'which')

      project = (
        ver, osver,
        'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
        '/etc/yum.repos.d/percona-original-release.repo',
        'pxc-56', 'mysql', '/etc/my.cnf',
        '|'.join(pkgs),
        'gdb|Percona-XtraDB-Cluster-56-debuginfo-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-XtraDB-Cluster-test-56-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-XtraDB-Cluster-garbd-56-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver)
      )
    if len(project) > 1:
      cur.execute(sql, project)
  conn.commit()

def save_percona_server_versions_to_sqlite(osver):
  db_file = 'anydbver_version.db'
  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except Error as e:
    print(e)
    return
  cur = conn.cursor()
  vers = list(open(".version-info/percona-server.{os}.txt".format(os=osver)))
  sql = """\
INSERT OR REPLACE INTO percona_server_version(
  version, os, repo_url, repo_file, repo_enable_str,
  systemd_service, cnf_file, packages,
  debug_packages, rocksdb_packages,
  tests_packages, mysql_shell_packages
)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
"""
  for line in vers:
    ver = line.rstrip()
    project = ()
    if ver.startswith('8.0') and osver.startswith('el'):
      pkgs = ['percona-server-shared','percona-server-client','percona-server-server']
      if osver != 'el9':
        pkgs.insert(0,'percona-server-shared-compat')
      project = (
        ver, osver,
        'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
        '/etc/yum.repos.d/percona-ps-80-release.repo',
        'ps-80', 'mysqld', '/etc/my.cnf',
        '|'.join(["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]),
        'gdb|percona-server-debuginfo-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'percona-server-rocksdb-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'percona-server-test-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'percona-mysql-shell-{ver}-1.{osver}.x86_64'.format(ver=ver.split('-',1)[0],osver=osver)
      )
    elif ver.startswith('5.7') and osver.startswith('el'):
      pkgs = ['Percona-Server-shared-compat-57','Percona-Server-shared-57','Percona-Server-client-57','Percona-Server-server-57']
      project = (
        ver, osver,
        'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
        '/etc/yum.repos.d/percona-original-release.repo',
        'ps-57', 'mysqld', '/etc/percona-server.conf.d/mysqld.cnf',
        '|'.join(["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]),
        'gdb|Percona-Server-57-debuginfo-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-Server-rocksdb-57-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-Server-test-57-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        ''
      )
    elif ver.startswith('5.6') and osver.startswith('el'):
      pkgs = ['Percona-Server-shared-56','Percona-Server-client-56','Percona-Server-server-56']
      project = (
        ver, osver,
        'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
        '/etc/yum.repos.d/percona-original-release.repo',
        'ps-56', 'mysqld', '/etc/my.cnf',
        '|'.join(["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]),
        'gdb|Percona-Server-56-debuginfo-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-Server-rocksdb-56-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-Server-test-56-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        ''
      )
    elif ver.startswith('5.5') and osver.startswith('el'):
      pkgs = ['Percona-Server-shared-55','Percona-Server-client-55','Percona-Server-server-55']
      project = (
        ver, osver,
        'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
        '/etc/yum.repos.d/percona-original-release.repo',
        'ps-55', 'mysql', '/etc/my.cnf',
        '|'.join(["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]),
        'gdb|Percona-Server-55-debuginfo-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-Server-rocksdb-55-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-Server-test-55-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        ''
      )
    if len(project) > 1:
      cur.execute(sql, project)
  conn.commit()

def update_versions():
  versions = []
  if not os.path.exists(".version-info"):
    os.makedirs(".version-info")
  generate_versions_file("psmdb.el8.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/",
      "pattern": r'Percona-Server-MongoDB(?:-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-40/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-42/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-44/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-50/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm'}
    ])

  generate_versions_file("percona-server.el8.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/",
      "pattern": r'Percona-Server-server-\d\d-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/ps-80/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-server-server-(\d[^"]*)[.]el8.x86_64.rpm'}
    ])
  generate_versions_file("percona-server.el9.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/9/RPMS/x86_64/",
      "pattern": r'Percona-Server-server-\d\d-(\d[^"]*).el9.x86_64.rpm'},
      {"url": "https://repo.percona.com/ps-80/yum/release/9/RPMS/x86_64/",
      "pattern": r'percona-server-server-(\d[^"]*)[.]el9.x86_64.rpm'}
    ])

  generate_versions_file("percona-xtradb-cluster.el7.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/7/RPMS/x86_64/",
      "pattern": r'Percona-XtraDB-Cluster-server-\d\d-(\d[^"]*).el7.x86_64.rpm'},
      {"url": "https://repo.percona.com/pxc-80/yum/release/7/RPMS/x86_64/",
      "pattern": r'percona-xtradb-cluster-server-(\d[^"]*)[.]el7.x86_64.rpm'}
    ])

  generate_versions_file("percona-xtradb-cluster.el8.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/",
      "pattern": r'Percona-XtraDB-Cluster-server-\d\d-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/pxc-80/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-xtradb-cluster-server-(\d[^"]*)[.]el8.x86_64.rpm'}
    ])

  generate_versions_file("percona-xtradb-cluster.el9.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/9/RPMS/x86_64/",
      "pattern": r'Percona-XtraDB-Cluster-server-\d\d-(\d[^"]*).el9.x86_64.rpm'},
      {"url": "https://repo.percona.com/pxc-80/yum/release/9/RPMS/x86_64/",
      "pattern": r'percona-xtradb-cluster-server-(\d[^"]*)[.]el9.x86_64.rpm'}
    ])


  generate_versions_file("percona-orchestrator.el8.txt",
    [
      {"url": "https://repo.percona.com/pdps-8.0/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-orchestrator-(\d[^"]*).el8.x86_64.rpm'}
    ])
  generate_versions_file("percona-orchestrator.el9.txt",
    [
      {"url": "https://repo.percona.com/pdps-8.0/yum/release/9/RPMS/x86_64/",
      "pattern": r'percona-orchestrator-(\d[^"]*).el9.x86_64.rpm'}
    ])

  generate_versions_file("mysql.el7.txt",
    [
      {"url": "https://repo.mysql.com/yum/mysql-5.6-community/el/7/x86_64/",
      "pattern": r'mysql-community-server-(\d[^"]*).el7.x86_64.rpm'},
      {"url": "https://repo.mysql.com/yum/mysql-5.7-community/el/7/x86_64/",
      "pattern": r'mysql-community-server-(\d[^"]*).el7.x86_64.rpm'},
      {"url": "https://repo.mysql.com/yum/mysql-8.0-community/el/7/x86_64/",
      "pattern": r'mysql-community-server-(\d[^"]*).el7.x86_64.rpm'},
    ])

  generate_versions_file("mysql.el8.txt",
    [
      {"url": "https://repo.mysql.com/yum/mysql-8.0-community/el/8/x86_64/",
      "pattern": r'mysql-community-server-(\d[^"]*).el8.x86_64.rpm'},
    ])

  generate_versions_file("mysql.el9.txt",
    [
      {"url": "https://repo.mysql.com/yum/mysql-8.0-community/el/9/x86_64/",
      "pattern": r'mysql-community-server-(\d[^"]*).el9.x86_64.rpm'},
    ])



  for osver in ("el7","el8","el9"):
    save_percona_server_versions_to_sqlite(osver)
    save_percona_xtradb_cluster_versions_to_sqlite(osver)
    save_mysql_server_versions_to_sqlite(osver)


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
  osver = "el8"
  if args.os is not None:
    if args.os == "rocky8":
      osver = "el8"
    elif args.os == "rocky9":
      osver = "el9"
  for p in ('psmdb',):
    if args.percona_server_mongodb:
      vers = list(open(".version-info/psmdb.{os}.txt".format(os=osver)))
      version = vers[-1]
      for line in reversed(vers):
        ver = line.rstrip()
        if ver.startswith(args.percona_server_mongodb):
          version = ver
          break
      args.percona_server_mongodb = version.rstrip()
      #print('looking psmdb version {} in .version-info/psmdb.el8.txt, found: {}'.format(args.percona_server_mongodb, version))
  if args.percona_server == 'True':
    args.percona_server = '8.0'
  if args.percona_xtrabackup:
    vers = list(open(".version-info/xtrabackup.{os}.txt".format(os=osver)))
    version = vers[-1]
    for line in reversed(vers):
      ver = line.rstrip()
      if ver.startswith(args.percona_xtrabackup):
        version = ver
        break
    args.percona_xtrabackup = version.rstrip()
  if args.percona_xtradb_cluster == 'True':
    args.percona_xtradb_cluster = '8.0'
  if args.proxysql:
    vers = list(open(".version-info/proxysql.{os}.txt".format(os=osver)))
    version = vers[-1]
    for line in reversed(vers):
      ver = line.rstrip()
      if ver.startswith(args.proxysql):
        version = ver
        break
    args.proxysql = version.rstrip()
  if args.mysql_server == 'True':
    args.mysql_server = '8.0'
  if args.mysql_router:
    vers = list(open(".version-info/mysql.{os}.txt".format(os=osver)))
    version = vers[-1]
    for line in reversed(vers):
      ver = line.rstrip()
      if ver.startswith(args.mysql_router):
        version = ver
        break
    args.mysql_router = version.rstrip()
  if args.percona_proxysql:
    vers = list(open(".version-info/percona-proxysql.{os}.txt".format(os=osver)))
    version = vers[-1]
    for line in reversed(vers):
      ver = line.rstrip()
      if ver.startswith(args.percona_proxysql):
        version = ver
        break
    args.percona_proxysql = version.rstrip()
  if args.percona_orchestrator:
    vers = list(open(".version-info/percona-orchestrator.{os}.txt".format(os=osver)))
    version = vers[-1]
    for line in reversed(vers):
      ver = line.rstrip()
      if ver.startswith(args.percona_orchestrator):
        version = ver
        break
    args.percona_orchestrator = version.rstrip()


def parse_node(args):
  node = args.pop(0)

  for cmd_idx, cmd in enumerate(args):
    if ':' not in cmd:
      cmd = cmd + ":True"
    if not cmd.startswith("--"):
      cmd = re.sub(r'^', '--', cmd).replace(':','=', 1)
    args[cmd_idx] = cmd

  parser = argparse.ArgumentParser()
  parser.add_argument('--mysql-server', '--mysql', '--mysql-community-server', type=str, nargs='?')
  parser.add_argument('--mysql-router', type=str, nargs='?')
  parser.add_argument('--percona-server', '--ps', type=str, nargs='?')
  parser.add_argument('--percona-xtradb-cluster', '--pxc', type=str, nargs='?')
  parser.add_argument('--proxysql', type=str, nargs='?')
  parser.add_argument('--percona-proxysql', type=str, nargs='?')
  parser.add_argument('--haproxy', type=str, nargs='?')
  parser.add_argument('--haproxy-galera', type=str, nargs='?')
  parser.add_argument('--clustercheck', type=str, nargs='?')
  parser.add_argument('--galera-leader', '--galera-master', '--galera-join', type=str, nargs='?')
  parser.add_argument('--group-replication', '--innodb-cluster', type=str, nargs='?')
  parser.add_argument('--cluster-name', '--cluster', type=str, default='cluster1', nargs='?')
  parser.add_argument('--ldap', type=str, nargs='?')
  parser.add_argument('--percona-server-mongodb', '--psmdb', type=str, nargs='?')
  parser.add_argument('--ldap-master', type=str, nargs='?')
  parser.add_argument('--replica-set', type=str, nargs='?')
  parser.add_argument('--percona-postgresql', '--percona-postgres', '--ppg', type=str, nargs='?')
  parser.add_argument('--leader', '--master', '--primary', type=str, nargs='?')
  parser.add_argument('--percona-xtrabackup', type=str, nargs='?')
  parser.add_argument('--debug-packages', '--debug', type=str, nargs='?')
  parser.add_argument('--rocksdb', type=str, nargs='?')
  parser.add_argument('--s3sql', type=str, nargs='?')
  parser.add_argument('--percona-orchestrator', type=str, nargs='?')
  parser.add_argument('--percona-toolkit', type=str, nargs='?')
  parser.add_argument('--cert-manager', dest="cert_manager", type=str, nargs='?')
  parser.add_argument('--k8s-minio', dest="k8s_minio", type=str, nargs='?')
  parser.add_argument('--minio-certs', dest="minio_certs", type=str, nargs='?')
  parser.add_argument('--k3d', type=str, nargs='?')
  parser.add_argument('--helm', type=str, nargs='?')
  parser.add_argument('--os', type=str, default="")
  parser.add_argument('--k8s-pg', dest="k8s_pg", type=str, nargs='?')
  parser.add_argument('--k8s-ps', dest="k8s_ps", type=str, nargs='?')
  parser.add_argument('--k8s-mongo', dest="k8s_mongo", type=str, nargs='?')
  parser.add_argument('--k8s-pxc', dest="k8s_pxc", type=str, nargs='?')
  parser.add_argument('--pmm', dest="pmm", type=str, nargs='?')
  parser.add_argument('--db-version', dest="db_version", type=str, nargs='?')
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
  extra_vars = {'extra_db_user': 'dba', 'extra_db_password': 'secret', 'extra_start_db': '1'}
  env = {"DB_USER":"dba", "DB_PASS":"secret", "START":"1"}
  db_features = []
  print('Node: ', node, 'Actions: ',actions)
  if actions.ldap is not None :
    extra_vars["extra_ldap_server"] = "1"
    env["LDAP_SERVER"] = "1"
  if actions.ldap_master is not None:
    extra_vars["extra_ldap_server_ip"] = resolve_hostname(actions.ldap_master)
    env["LDAP_IP"] = extra_vars["extra_ldap_server_ip"]
  if actions.percona_server_mongodb is not None:
    extra_vars["extra_psmdb_version"] = actions.percona_server_mongodb
    extra_vars["extra_db_opts_file"] = "mongo/enable_wt.conf"
    env["PSMDB"] = actions.percona_server_mongodb
    env["DB_OPTS"] = "mongo/enable_wt.conf"
    if actions.replica_set is not None:
      extra_vars["extra_mongo_replicaset"] = actions.replica_set
      env["REPLICA_SET"] = actions.replica_set
  if actions.percona_server is not None:
    extra_vars["extra_percona_server_version"] = actions.percona_server
    extra_vars["extra_db_opts_file"] = "mysql/async-repl-gtid.cnf"
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["PS"] = actions.percona_server
    env["DB_OPTS"] = "mysql/async-repl-gtid.cnf"
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.mysql_server is not None:
    extra_vars["extra_mysql_version"] = actions.mysql_server
    extra_vars["extra_db_opts_file"] = "mysql/async-repl-gtid.cnf"
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["MYSQL"] = actions.mysql_server
    env["DB_OPTS"] = "mysql/async-repl-gtid.cnf"
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.mysql_router is not None:
    extra_vars["extra_mysql_router_version"] = actions.mysql_router
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["MYSQL_ROUTER"] = actions.mysql_router
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.percona_xtradb_cluster is not None:
    extra_vars["extra_percona_xtradb_cluster_version"] = actions.percona_xtradb_cluster
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

    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.cluster_name:
    extra_vars["extra_cluster_name"] = actions.cluster_name
    env["CLUSTER"] = actions.cluster_name
  if actions.galera_leader:
    extra_vars["extra_master_ip"] = resolve_hostname(actions.galera_leader)
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
    extra_vars["extra_percona_proxysql_version"] = actions.percona_proxysql
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["PERCONA_PROXYSQL"] = actions.percona_proxysql
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.haproxy_galera is not None: 
    extra_vars["extra_haproxy_galera"] = ','.join([resolve_hostname(node) for node in actions.haproxy_galera.split(',') ])
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
  if actions.percona_orchestrator is not None:
    extra_vars["extra_percona_orchestrator_version"] = actions.percona_orchestrator
    extra_vars["extra_db_user"] = "root"
    extra_vars["extra_db_password"] = "verysecretpassword1^"
    env["PERCONA_ORCHESTRATOR"] = actions.percona_orchestrator
    env["DB_USER"] = "root"
    env["DB_PASS"]= "verysecretpassword1^"
  if actions.leader is not None:
    extra_vars["extra_master_ip"] = resolve_hostname(actions.leader)
    env["DB_IP"] = extra_vars["extra_master_ip"]
  if len(db_features) > 0:
    extra_vars["extra_db_features"] = ",".join(db_features)
    env["DB_FEATURES"] = extra_vars["extra_db_features"]
  return env, extra_vars

def apply_node_command(node, env, cmd):
  run_fatal(cmd, "failed to deploy node {}".format(node), env=env)

def create_nodes(nodes_cnt, osver):
  create_nodes_cmd = "rm -f ssh_config ansible_hosts; ./docker_container.py --nodes={} --os={} --destroy --deploy".format(nodes_cnt, osver)
  logger.info(create_nodes_cmd)
  os.system(create_nodes_cmd)


def ssh_login(namespace, node):
  if node == "node0":
    node = "default"
  os.system("ssh -F {}ssh_config -o LogLevel=error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i secret/id_rsa -t root@{}".format(namespace, node))

def main():
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
      mysql_cli("", host)
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
  parser.add_argument('--os', dest="os", type=str, default="rocky8")

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
  nodes_os = args.os + ","
  for nodeline in nodelines:
    node_actions.append(parse_node(nodeline))
    node = node_actions[-1][0]
    node_names[ node ] = 1
    if (node_actions[-1][1]).os == "":
      (node_actions[-1][1]).os = args.os
    nodes_os = nodes_os + node + "=" + (node_actions[-1][1]).os + ","

  nodes_cnt = len(node_names)
  create_nodes(nodes_cnt, nodes_os)

  cmds = []

  ansible_hosts_run = open("ansible_hosts_run", "w")

  for n in node_actions:
    node = n[0]
    if node == "node0":
      node = "default"
    (env, extra_vars) = apply_node_actions(node, n[1])

    extrastr = ""
    for v in extra_vars:
      extrastr = extrastr + " " + v + "='" + extra_vars[v] + "'"

    python_path="/usr/bin/python3"

    if n[1].os in ("centos7", "el7"):
        python_path="/usr/bin/python"

    ansible_hosts_run.write(
    "{user}.{node} ansible_connection=ssh ansible_user=root ansible_ssh_private_key_file=secret/id_rsa ansible_host={ip} ansible_python_interpreter={python_path} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o GSSAPIDelegateCredentials=no -o GSSAPIKeyExchange=no -o GSSAPITrustDNS=no -o ProxyCommand=none' {extra_vars}\n".format(
        user=args.user,node=node, python_path=python_path,extra_vars=extrastr, ip=resolve_hostname(node))
    )
    print(extrastr)

  print(args)
  print(node_actions)

  ansible_hosts_run.close()
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
