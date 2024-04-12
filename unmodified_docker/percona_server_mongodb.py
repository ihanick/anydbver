from anydbver_run_tools import run_fatal, soft_params
from anydbver_common import logger, DEFAULT_PASSWORD, ANYDBVER_DIR

def deploy(node_args, node_name, net):
  params = soft_params(node_args)

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

