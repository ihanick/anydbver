from anydbver_run_tools import run_fatal, soft_params
from anydbver_common import DEFAULT_PASSWORD, logger

def deploy(node_args, node_name, net):
  params = soft_params(node_args)
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

