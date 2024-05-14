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
  sentinel_conf = ""

  master_hostname = node_name

  if "master" in params:
    if params["master"] == "node0":
      params["master"] = "default"

    master_nodename = "{}{}-{}".format(ns_prefix,usr,params["master"])
    master_hostname = master_nodename.replace(".", "-")


    repl_conf = """\
replicaof {master_ip} 6379  
""".format(master_ip=master_hostname, passwd=DEFAULT_PASSWORD)


  if "sentinel" in params:
    sentinel_conf="""\
cat > /data/sentinel.conf <<EOF
bind 0.0.0.0
port 26379
sentinel resolve-hostnames yes
sentinel monitor mymaster {master_name} 6379 2
sentinel auth-pass mymaster {passwd}
sentinel auth-user mymaster default
sentinel down-after-milliseconds mymaster 10000
EOF
valkey-sentinel /data/sentinel.conf &
""".format(master_name=master_hostname, passwd=DEFAULT_PASSWORD)

  docker_run_cmd.extend([
    "/bin/sh",
    "-c",
    """\
cat > /data/valkey.conf <<EOF
requirepass {passwd}
masterauth {passwd}
{repl_conf}
EOF
{sentinel_conf}
exec valkey-server /data/valkey.conf
""".format(passwd=DEFAULT_PASSWORD, repl_conf=repl_conf, sentinel_conf=sentinel_conf),
    ])

  run_fatal(logger, docker_run_cmd, "Can't start ValKey")
