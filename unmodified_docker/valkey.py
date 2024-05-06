from anydbver_run_tools import run_fatal, soft_params
from anydbver_common import DEFAULT_PASSWORD, logger

def deploy(node_args, node_name, usr, net, ns_prefix):
  params = soft_params(node_args)
  docker_run_cmd =["docker", "run", "-d", "--name={}".format(node_name),
             "--network={}".format(net) ]

  if "memory" in params:
    docker_run_cmd.append("--memory={}".format(params["memory"]))

  if type(params["docker-image"]) == type(True):
    docker_run_cmd.append("valkey/valkey:{ver}".format(ver=params["version"]))
  else:
    docker_run_cmd.append(params["docker-image"])

  repl_conf = ""
  if "master" in params:
    if params["master"] == "node0":
      params["master"] = "default"

    master_nodename = "{}{}-{}".format(ns_prefix,usr,params["master"])
    master_hostname = master_nodename.replace(".", "-")

    repl_conf = """\
replicaof {master_ip} 6379  
masterauth {passwd}
""".format(master_ip=master_hostname, passwd=DEFAULT_PASSWORD)

  docker_run_cmd.extend([
    "/bin/sh",
    "-c",
    """\
cat > /data/valkey.conf <<EOF
requirepass {passwd}
{repl_conf}
EOF
exec valkey-server /data/valkey.conf
""".format(passwd=DEFAULT_PASSWORD, repl_conf=repl_conf),
    ])

  run_fatal(logger, docker_run_cmd, "Can't start ValKey")
