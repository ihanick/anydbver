from anydbver_run_tools import run_fatal, soft_params
from anydbver_common import ANYDBVER_DIR, DEFAULT_PASSWORD, logger

def deploy(node_args, node_name, net):
  params = soft_params(node_args)
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

def setup(node_name):
  run_fatal(logger, [
            "docker", "exec", node_name,
            "sh", "/vagrant/tools/add_samba_users_and_groups.sh" ],
            "Can't add samba users and groups")

