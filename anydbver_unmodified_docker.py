import datetime
import time
import os
import logging
import urllib.parse
from anydbver_run_tools import run_fatal, soft_params

COMMAND_TIMEOUT=600
DEFAULT_PASSWORD='verysecretpassword1^'
DEFAULT_SERVER_ID=50
ANYDBVER_DIR = os.path.dirname(os.path.realpath(__file__))



logger = logging.getLogger('AnyDbVer')
logger.setLevel(logging.INFO)


def wait_mysql_ready(name, sql_cmd,user,password, timeout=COMMAND_TIMEOUT):
  for _ in range(timeout // 2):
    s = datetime.datetime.now()
    if run_fatal(logger, ["docker", "exec", name, sql_cmd, "-u", user, "-p"+password, "--silent", "--connect-timeout=30", "--wait", "-e", "SELECT 1;"],
        "container {} ready wait problem".format(name),
        r"connect to local MySQL server through socket|Using a password on the command line interface can be insecure|connect to local server through socket|Access denied for user", False) == 0:
      return True
    if (datetime.datetime.now() - s).total_seconds() < 1.5:
      time.sleep(2)
  return False

def setup_unmodified_docker_images(usr, ns, node_name, node):
  ns_prefix = ns
  if ns_prefix != "":
    ns_prefix = ns_prefix + "-"
  net = "{}{}-anydbver".format(ns_prefix, usr)
  logger.info("Setting up node {} with unmodified docker image".format(node_name))

  if node.mysql_server:
    params = soft_params(node.mysql_server)
    pass_encoded = urllib.parse.quote_plus(DEFAULT_PASSWORD)
    if "cluster-name" not in params:
      params["cluster-name"] = "cluster1"
    if "group-replication" in params and "master" not in params:
      run_fatal(logger, [
                  "docker", "exec", node_name,
                  "bash", "-c",
                  """until mysqlsh --password=$MYSQL_ROOT_PASSWORD -e "dba.createCluster('{}', {{}})" ; do sleep 1; done""".format(params["cluster-name"]) ],
                "Can't set up first Group replication node")
    if "group-replication" in params and "master" in params:
      if params["master"] == "node0":
        params["master"] = "default"

      master_nodename = "{}{}-{}".format(ns_prefix,usr,params["master"])
      master_hostname = master_nodename.replace(".", "-")
      node_hostname = node_name.replace(".", "-")

      run_fatal(logger, [
                  "docker", "exec", node_name,
                  "bash", "-c",
                  """mysqlsh --host={master_host} --password=$MYSQL_ROOT_PASSWORD -e "var c=dba.getCluster();c.addInstance('root:{password}@{node}:3306', {{recoveryMethod: 'clone', label: '{node}'}})" """.format(master_host=master_hostname, password=pass_encoded, node=node_hostname) ],
                "Can't set up secondary Group replication node {node}".format(node=node_name),
                r"is shutting down")
      run_fatal(logger, [
                  "docker", "exec", master_nodename,
                  "bash", "-c",
                  """until mysql -N -uroot -p"$MYSQL_ROOT_PASSWORD" -e "select MEMBER_STATE from performance_schema.replication_group_members where member_host='{node}'"|grep -q ONLINE ; do sleep 1 ; done""".format(node=node_hostname) ], "Group replication node {node} is not ONLINE".format(node=node_name))

  if node.percona_server_mongodb:
    'rs.initiate( { _id : "rs0", members: [ { _id: 0, host: "ihanick-default:27017" }, { _id: 1, host: "ihanick-node1:27017" },{ _id: 2, host: "ihanick-node2:27017" }, ] })'
    pass
  if node.samba:
      run_fatal(logger, [
                "docker", "exec", node_name,
                "sh", "/vagrant/tools/add_samba_users_and_groups.sh" ],
                "Can't add samba users and groups")

def deploy_unmodified_docker_images(usr, ns, node_name, node):
  ns_prefix = ns
  if ns_prefix != "":
    ns_prefix = ns_prefix + "-"
  net = "{}{}-anydbver".format(ns_prefix, usr)
  logger.info("Deploying node with unmodified docker image")
  if node.pmm:
    params = soft_params(node.pmm)
    pmm_port = ""
    if "port" in params and params["port"] != "":
      pmm_port = params["port"] + ":"

    docker_run_cmd =["docker", "run", "-d", "--name={}".format(node_name),
               "-p", "{port}443".format(port=pmm_port),
               "--network={}".format(net) ]

    if "memory" in params:
      docker_run_cmd.append("--memory={}".format(params["memory"]))

    if type(params["docker-image"]) == type(True):
      docker_run_cmd.append("percona/pmm-server:{ver}".format(ver=params["version"]))
    else:
      docker_run_cmd.append(params["docker-image"])

    run_fatal(logger, docker_run_cmd, "Can't start PMM")

    run_fatal(logger,
              [
    "docker", "exec", node_name, "bash", "-c", 'sleep 30;grafana-cli --config /etc/grafana/grafana.ini --homepath /usr/share/grafana --configOverrides cfg:default.paths.data=/srv/grafana admin reset-admin-password {}'.format(DEFAULT_PASSWORD)
    ], "Can't change PMM password")
  if node.mysql_server:
    params = soft_params(node.mysql_server)
    logger.info("docker run --network={net} -d --name={name} mysql/mysql-server:{ver}".format(net=net, name=node_name, ver=params["version"]))
    docker_run_cmd = ["docker", "run", "-d", "--name={}".format(node_name),
               "--hostname={}".format(node_name.replace(".", "-")),
               "-e", "MYSQL_ROOT_PASSWORD={}".format(DEFAULT_PASSWORD),
               "-e", "MYSQL_ROOT_HOST=%",
               "-v", "{}:/vagrant".format(ANYDBVER_DIR),
               "--network={}".format(net),
               "--restart=always",
               "mysql/mysql-server:{ver}".format(ver=params["version"])
               ]

    if "group-replication" in params:
      if "server_id" not in params:
        if node_name == "{}{}-default".format(ns_prefix, usr):
          params["server_id"] = DEFAULT_SERVER_ID
        else:
          params["server_id"] = DEFAULT_SERVER_ID + int(node_name.replace("{}{}-node".format(ns_prefix, usr),""))
      if "args" not in params:
        params["args"] = ""
      params["args"] = params["args"] + " --innodb-buffer-pool-size=512M --server-id={server_id} --report-host={report_host} --log-bin=mysqld-bin --binlog-checksum=NONE --gtid_mode=ON --enforce-gtid-consistency=ON --log-slave-updates --transaction_write_set_extraction=XXHASH64 --master_info_repository=TABLE --relay_log_info_repository=TABLE --binlog_transaction_dependency_tracking=WRITESET --slave_parallel_type=LOGICAL_CLOCK --slave_preserve_commit_order=ON".format(server_id=params["server_id"], report_host=node_name.replace(".", "-"))
    if "args" in params:
        docker_run_cmd.extend(params["args"].split())
    run_fatal(logger, docker_run_cmd , "Can't start mysql server docker container")
    if not wait_mysql_ready(node_name, "mysql", "root", DEFAULT_PASSWORD):
      logger.fatal("Can't start mysql server in docker container " + node_name)
    if "sql" in params:
        url = "/".join(params["sql"].split("/",3)[:3])
        file = params["sql"].split("/",3)[3]
        run_fatal(logger,
                  ["/bin/sh","-c","MC_HOST_minio={url} tools/mc cat minio/{file} | docker exec -i {node_name} mysql -uroot -p'{password}'".format(
                      url=url, file=file, node_name=node_name, password=DEFAULT_PASSWORD)],"Can't load sql file from S3")
  if node.percona_xtradb_cluster:
    params = soft_params(node.percona_xtradb_cluster)
    logger.info("docker run --network={net} -d --name={name} percona/percona-xtradb-cluster:{ver}".format(net=net, name=node_name, ver=params["version"]))
    run_fatal(logger,
              ["docker", "run", "-d", "--name={}".format(node_name),
               "-e", "MYSQL_ROOT_PASSWORD={}".format(DEFAULT_PASSWORD),
               "-e", "MYSQL_ROOT_HOST=%",
               "-v", "{}:/vagrant".format(ANYDBVER_DIR),
               "--network={}".format(net),
               "percona/percona-xtradb-cluster:{ver}".format(ver=params["version"])
               ], "Can't start percona server docker container")
    if not wait_mysql_ready(node_name, "mysql", "root", DEFAULT_PASSWORD):
      logger.fatal("Can't start percona server in docker container " + node_name)
    if "sql" in params:
        url = "/".join(params["sql"].split("/",3)[:3])
        file = params["sql"].split("/",3)[3]
        run_fatal(logger,
                  ["/bin/sh","-c","MC_HOST_minio={url} tools/mc cat minio/{file} | docker exec -i {node_name} mysql -uroot -p'{password}'".format(
                      url=url, file=file, node_name=node_name, password=DEFAULT_PASSWORD)],"Can't load sql file from S3")
  if node.percona_server:
    params = soft_params(node.percona_server)
    logger.info("docker run --network={net} -d --name={name} percona/percona-server:{ver}".format(net=net, name=node_name, ver=params["version"]))
    run_fatal(logger,
              ["docker", "run", "-d", "--name={}".format(node_name),
               "-e", "MYSQL_ROOT_PASSWORD={}".format(DEFAULT_PASSWORD),
               "-e", "MYSQL_ROOT_HOST=%",
               "-v", "{}:/vagrant".format(ANYDBVER_DIR),
               "--network={}".format(net),
               "percona/percona-server:{ver}".format(ver=params["version"])
               ], "Can't start percona server docker container")
    if not wait_mysql_ready(node_name, "mysql", "root", DEFAULT_PASSWORD):
      logger.fatal("Can't start percona server in docker container " + node_name)
    if "sql" in params:
        url = "/".join(params["sql"].split("/",3)[:3])
        file = params["sql"].split("/",3)[3]
        run_fatal(logger,
                  ["/bin/sh","-c","MC_HOST_minio={url} tools/mc cat minio/{file} | docker exec -i {node_name} mysql -uroot -p'{password}'".format(
                      url=url, file=file, node_name=node_name, password=DEFAULT_PASSWORD)],"Can't load sql file from S3")
  if node.mariadb:
    params = soft_params(node.mariadb)
    logger.info("docker run --network={net} -d --name={name} mariadb:{ver}".format(net=net, name=node_name, ver=params["version"]))
    run_fatal(logger,
              ["docker", "run", "-d", "--name={}".format(node_name),
               "--hostname={}".format(node_name.replace(".", "-")),
               "-e", "MYSQL_ROOT_PASSWORD={}".format(DEFAULT_PASSWORD),
               "--network={}".format(net),
               "mariadb:{ver}".format(ver=params["version"])
               ], "Can't start mariadb docker container")
    if not wait_mysql_ready(node_name, "mariadb", "root", DEFAULT_PASSWORD):
      logger.fatal("Can't start mariadb in docker container " + node_name)
    if "sql" in params:
        url = "/".join(params["sql"].split("/",3)[:3])
        file = params["sql"].split("/",3)[3]
        run_fatal(logger,
                  ["/bin/sh","-c","MC_HOST_minio={url} tools/mc cat minio/{file} | docker exec -i {node_name} mariadb -uroot -p'{password}'".format(
                      url=url, file=file, node_name=node_name, password=DEFAULT_PASSWORD)],"Can't load sql file from S3")
  if node.postgresql:
    params = soft_params(node.postgresql)

    docker_run_cmd = ["docker", "run", "-d", "--name={}".format(node_name),
               "-e", "POSTGRES_PASSWORD={}".format(DEFAULT_PASSWORD),
               "--network={}".format(net),
               
               ]
    if "master" in params:
      if params["master"] == "node0":
        params["master"] = "default"
      primary_host = "{}{}-{}".format(ns_prefix, usr, params["master"])
      params["entrypoint"] = ANYDBVER_DIR + "/tools/setup_postgresql_replication_docker.sh"
      docker_run_cmd.append("-e")
      docker_run_cmd.append("POSTGRES_PRIMARY_HOST={}".format(primary_host))
    else:
      params["entrypoint"] = ANYDBVER_DIR + "/tools/setup_pg_hba.sh"
    
    if "entrypoint" in params:
      docker_run_cmd.append("--entrypoint=/bin/sh")

    docker_run_cmd.append("postgres:{ver}".format(ver=params["version"]))
    if "entrypoint" in params:
      docker_run_cmd.append("-c")
      with open(params["entrypoint"],'r') as f:
        docker_run_cmd.append(f.read())

    run_fatal(logger, docker_run_cmd, "Can't start postgres docker container")

  if node.alertmanager:
    params = soft_params(node.alertmanager)
    run_fatal(logger,
              [
                "docker", "run", "-d", "--name={}".format(node_name),
                "-p", "0.0.0.0:{}:9093".format(params["port"]),
                "--network={}".format(net),
                "-v", "{}/data/alertmanager/config:/etc/alertmanager".format(ANYDBVER_DIR),
                "-v", "{}/data/alertmanager/data:/alertmanager/data".format(ANYDBVER_DIR),
                "prom/alertmanager:{}".format(params["version"]), "--config.file=/etc/alertmanager/alertmanager.yaml"
                ], "Can't start alertmanager docker container")

  if node.percona_server_mongodb:
    params = soft_params(node.percona_server_mongodb)
    hostname = node_name.replace(".", "-")
    if "args" not in params:
      params["args"] = []
    params["args"].append("--bind_ip")
    params["args"].append("localhost,{hostname}".format(hostname=hostname))
    if "rs" in params:
      params["replica-set"] = params["rs"]

    if "replica-set" in params:
      params["args"].append("--replSet")
      params["args"].append(params["replica-set"])
      params["args"].append("--keyFile")
      params["args"].append("/vagrant/secret/{}-keyfile-docker".format(params["replica-set"]))

      run_fatal(logger, ["docker", "run", "-i", "--rm",
               "-v", "{}:/vagrant".format(ANYDBVER_DIR),
               "busybox", "sh", "-c",
               "mkdir -p /vagrant/data/secret;cp /vagrant/secret/{rs}-keyfile /vagrant/data/secret/{rs}-keyfile-docker;chown 1001 /vagrant/data/secret/{rs}-keyfile-docker;chmod 0600 /vagrant/data/secret/{rs}-keyfile-docker".format(rs=params["replica-set"])], "Can't copy keyfile for docker")


    docker_run_cmd = ["docker", "run", "-d", "--name={}".format(node_name),
               "--hostname={}".format(hostname),
               "-v", "{}:/vagrant".format(ANYDBVER_DIR),
               "--network={}".format(net),
               "-e", "MONGO_INITDB_ROOT_USERNAME=admin",
               "-e", "MONGO_INITDB_ROOT_PASSWORD={password}".format(password=DEFAULT_PASSWORD),
               "--restart=always",
               "percona/percona-server-mongodb:{ver}".format(ver=params["version"]),
               ]
    docker_run_cmd.append("mongod")
    docker_run_cmd.extend(params["args"])
    run_fatal(logger, docker_run_cmd, "Can't start percona server for mongodb docker container")
  if node.samba:
    params = soft_params(node.samba)
    hostname = node_name.replace(".", "-")
    if "realm" not in params:
      params["realm"] = "PERCONA.LOCAL"

    with open(ANYDBVER_DIR + '/secret/id_rsa.pub','r') as f:
      ssh_pub_key = f.read()

    
    docker_run_cmd = ["docker", "run", "-d", "--name={}".format(node_name),
               "--hostname={}".format(hostname),
               "-v", "{}:/vagrant".format(ANYDBVER_DIR),
               "--network={}".format(net),
               "-e", "REALM={realm}".format(realm=params["realm"]),
               "-e", "ADMINPASS={password}".format(password=DEFAULT_PASSWORD),
               "-e", "SSH_AUTHORIZED_KEYS={}".format(ssh_pub_key),
               "--restart=always",
               "smblds/smblds:latest",
               ]
    run_fatal(logger, docker_run_cmd, "Can't start Samba (Active Directory) Lightweight Directory Services docker container")

