from anydbver_run_tools import run_fatal, soft_params
from anydbver_common import DEFAULT_PASSWORD, ANYDBVER_DIR, logger

def deploy(node_args, node_name, usr, net, ns_prefix):
  params = soft_params(node_args)

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

  docker_run_cmd.append("percona/percona-distribution-postgresql:{ver}".format(ver=params["version"]))
  if "entrypoint" in params:
    docker_run_cmd.append("-c")
    with open(params["entrypoint"],'r') as f:
      docker_run_cmd.append(f.read())

  run_fatal(logger, docker_run_cmd, "Can't start percona postgres docker container")
