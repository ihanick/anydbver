from anydbver_run_tools import run_fatal, soft_params
from anydbver_common import ANYDBVER_DIR, logger

def deploy(node_args, node_name, net):
  params = soft_params(node_args)

  run_fatal(logger,
            [
              "docker", "run", "-d", "--name={}".format(node_name),
              "-p", "0.0.0.0:{}:9093".format(params["port"]),
              "--network={}".format(net),
              "-v", "{}/data/alertmanager/config:/etc/alertmanager".format(ANYDBVER_DIR),
              "-v", "{}/data/alertmanager/data:/alertmanager/data".format(ANYDBVER_DIR),
              "prom/alertmanager:{}".format(params["version"]), "--config.file=/etc/alertmanager/alertmanager.yaml"
              ], "Can't start alertmanager docker container")
