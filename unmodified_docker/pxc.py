from anydbver_run_tools import run_fatal, soft_params
from .mysql_common import wait_mysql_ready
from anydbver_common import logger, DEFAULT_PASSWORD, ANYDBVER_DIR

def deploy(node_args, node_name, net):
  params = soft_params(node_args)

  logger.info("docker run --network={net} -d --name={name} percona/percona-xtradb-cluster:{ver}".format(net=net, name=node_name, ver=params["version"]))
  run_fatal(logger,
            ["docker", "run", "-d", "--name={}".format(node_name),
             "-e", "MYSQL_ROOT_PASSWORD={}".format(DEFAULT_PASSWORD),
             "-e", "MYSQL_ROOT_HOST=%",
             "-v", "{}:/vagrant".format(ANYDBVER_DIR),
             "--network={}".format(net),
             "percona/percona-xtradb-cluster:{ver}".format(ver=params["version"])
             ], "Can't start percona server docker container")
  if not wait_mysql_ready(node_name, "mysql", "root", DEFAULT_PASSWORD):
    logger.fatal("Can't start percona server in docker container " + node_name)
  if "sql" in params:
      url = "/".join(params["sql"].split("/",3)[:3])
      file = params["sql"].split("/",3)[3]
      run_fatal(logger,
                ["/bin/sh","-c","MC_HOST_minio={url} tools/mc cat minio/{file} | docker exec -i {node_name} mysql -uroot -p'{password}'".format(
                    url=url, file=file, node_name=node_name, password=DEFAULT_PASSWORD)],"Can't load sql file from S3")

