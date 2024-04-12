from anydbver_run_tools import run_fatal, soft_params
from anydbver_common import ANYDBVER_DIR, logger

def deploy(node_args, node_name, net):
  params = soft_params(node_args)

  minio_port =  ""
  if "port" in params and params["port"] != "":
    minio_port = params["port"] + ":"

  minio_admin_port =  ""
  if "admin-port" in params and params["admin-port"] != "":
    minio_admin_port = params["admin-port"] + ":"

  docker_run_cmd = [
              "docker", "run", "-d", "--name={}".format(node_name),
              "-p", "{}9000".format(minio_port),
              "-p", "{}9090".format(minio_admin_port),
              "--network={}".format(net),
              "-v", "{}/data/minio-bkp-config.env:/etc/config.env".format(ANYDBVER_DIR),
              "-v", "{}/data:/mnt/data".format(ANYDBVER_DIR),
              "-e", "MINIO_CONFIG_ENV_FILE=/etc/config.env",
              "minio/minio:{}".format(params["version"]), "server", "--console-address", ":9090", "--certs-dir", "/mnt/data/certs"
              ]

  run_fatal(logger, docker_run_cmd, "Can't start minio S3 server")
