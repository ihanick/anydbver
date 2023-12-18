import datetime
import time
import os
import logging
from anydbver_run_tools import run_fatal, soft_params

COMMAND_TIMEOUT=600
DEFAULT_PASSWORD='verysecretpassword1^'
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
               "-e", "MYSQL_ROOT_PASSWORD={}".format(DEFAULT_PASSWORD),
               "-v", "{}:/vagrant".format(ANYDBVER_DIR),
               "--network={}".format(net),
               "mysql/mysql-server:{ver}".format(ver=params["version"])
               ]
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
  if node.percona_server:
    params = soft_params(node.percona_server)
    logger.info("docker run --network={net} -d --name={name} percona/percona-server:{ver}".format(net=net, name=node_name, ver=params["version"]))
    run_fatal(logger,
              ["docker", "run", "-d", "--name={}".format(node_name),
               "-e", "MYSQL_ROOT_PASSWORD={}".format(DEFAULT_PASSWORD),
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
    run_fatal(logger,
              ["docker", "run", "-d", "--name={}".format(node_name),
               "-e", "POSTGRES_PASSWORD={}".format(DEFAULT_PASSWORD),
               "--network={}".format(net),
               "postgres:{ver}".format(ver=params["version"])
               ], "Can't start postgres docker container")
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

