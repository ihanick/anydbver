from anydbver_run_tools import run_fatal, soft_params
from anydbver_common import ANYDBVER_DIR, logger

MINIO_USER="UIdgE4sXPBTcBB4eEawU"
MINIO_PASS="7UdlDzBF769dbIOMVILV"
MINIO_BUCKET="bucket1"

def deploy(node_args, node_name, net):
  params = soft_params(node_args)

  minio_port =  ""
  if "port" in params and params["port"] != "":
    minio_port = params["port"] + ":"

  minio_admin_port =  ""
  if "admin-port" in params and params["admin-port"] != "":
    minio_admin_port = params["admin-port"] + ":"

  minio_user =  MINIO_USER
  if "access-key" in params and params["access-key"] != "":
    minio_user = params["access-key"]

  minio_password = MINIO_PASS
  if "secret-key" in params and params["secret-key"] != "":
    minio_password = params["secret-key"]


  minio_config_path = "{}/data/minio-bkp-config.env".format(ANYDBVER_DIR)
  minio_config =  """\
MINIO_ROOT_USER={minio_user}
MINIO_ROOT_PASSWORD={minio_password}
MINIO_VOLUMES="/mnt/data"
""".format(minio_user=minio_user, minio_password=minio_password)

  with open(minio_config_path,"w+") as f:
            f.writelines(minio_config)


  minio_password = MINIO_PASS
  if "secret-key" in params and params["secret-key"] != "":
    minio_password = params["secret-key"] + ":"

  docker_run_cmd = [
              "docker", "run", "-d", "--name={}".format(node_name),
              "-p", "{}9000".format(minio_port),
              "-p", "{}9090".format(minio_admin_port),
              "--network={}".format(net),
              "-v", "{}:/etc/config.env".format(minio_config_path),
              "-v", "{}/data/minio:/mnt/data".format(ANYDBVER_DIR),
              "-e", "MINIO_CONFIG_ENV_FILE=/etc/config.env",
              "minio/minio:{}".format(params["version"]), "server", "--console-address", ":9090",
              ]

  url_schema="http"
  if "certs" not in params or params["certs"] not in ("none", "false", "False",):
    docker_run_cmd.extend([ "--certs-dir", "/mnt/data/certs",])
    url_schema="https"


  run_fatal(logger, docker_run_cmd, "Can't start minio S3 server")

  bucket = MINIO_BUCKET
  if "bucket" in params and params["bucket"] != "":
    bucket = params["bucket"]

  create_bucket_sh = """\
zcat /opt/bin/mc.gz > /mnt/data/mc
chmod +x /mnt/data/mc
until /mnt/data/mc --insecure alias set bkp {url_schema}://127.0.0.1:9000 "{minio_user}" "{minio_password}" ; do sleep 1; done
/mnt/data/mc --insecure rb --force bkp/{bucket}
/mnt/data/mc --insecure mb bkp/{bucket}
""".format(url_schema=url_schema, minio_user=minio_user, minio_password=minio_password, bucket=bucket)

  run_fatal(logger,
            [
  "docker", "exec", node_name, "sh", "-c", create_bucket_sh,
  ], "Can't create a bucket")

