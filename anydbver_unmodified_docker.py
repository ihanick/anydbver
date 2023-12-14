import os
import logging
from anydbver_run_tools import run_fatal, soft_params

COMMAND_TIMEOUT=600
DEFAULT_PASSWORD='verysecretpassword1^'
ANYDBVER_DIR = os.path.dirname(os.path.realpath(__file__))



logger = logging.getLogger('AnyDbVer')
logger.setLevel(logging.INFO)



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
  if node.mariadb:
    params = soft_params(node.mariadb)
    logger.info("docker run --network={net} -d --name={name} mariadb:{ver}".format(net=net, name=node_name, ver=params["version"]))
    run_fatal(logger,
              ["docker", "run", "-d", "--name={}".format(node_name),
               "-e", "MYSQL_ROOT_PASSWORD={}".format(DEFAULT_PASSWORD),
               "--network={}".format(net),
               "mariadb:{ver}".format(ver=params["version"])
               ], "Can't start mariadb docker container")

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

