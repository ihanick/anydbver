from anydbver_run_tools import run_fatal, soft_params
from .mysql_common import wait_mysql_ready
from anydbver_common import logger, DEFAULT_PASSWORD, DEFAULT_SERVER_ID, ANYDBVER_DIR

import urllib.parse

def deploy(node_args, node_name, usr, net, ns_prefix):
  params = soft_params(node_args)
  logger.info("docker run --network={net} -d --name={name} mysql/mysql-server:{ver}".format(net=net, name=node_name, ver=params["version"]))
  docker_run_cmd = ["docker", "run", "-d", "--name={}".format(node_name),
             "--hostname={}".format(node_name.replace(".", "-")),
             "-e", "MYSQL_ROOT_PASSWORD={}".format(DEFAULT_PASSWORD),
             "-e", "MYSQL_ROOT_HOST=%",
             "-v", "{}:/vagrant".format(ANYDBVER_DIR),
             "--network={}".format(net),
             "--restart=always",
             "mysql/mysql-server:{ver}".format(ver=params["version"])
             ]

  if "group-replication" in params:
    if "server_id" not in params:
      if node_name == "{}{}-default".format(ns_prefix, usr):
        params["server_id"] = DEFAULT_SERVER_ID
      else:
        params["server_id"] = DEFAULT_SERVER_ID + int(node_name.replace("{}{}-node".format(ns_prefix, usr),""))
    if "args" not in params:
      params["args"] = ""
    params["args"] = params["args"] + " --innodb-buffer-pool-size=512M --server-id={server_id} --report-host={report_host} --log-bin=mysqld-bin --binlog-checksum=NONE --gtid_mode=ON --enforce-gtid-consistency=ON --log-slave-updates --transaction_write_set_extraction=XXHASH64 --master_info_repository=TABLE --relay_log_info_repository=TABLE --binlog_transaction_dependency_tracking=WRITESET --slave_parallel_type=LOGICAL_CLOCK --slave_preserve_commit_order=ON".format(server_id=params["server_id"], report_host=node_name.replace(".", "-"))
  if "args" in params:
      docker_run_cmd.extend(params["args"].split())
  run_fatal(logger, docker_run_cmd , "Can't start mysql server docker container")
  if not wait_mysql_ready(node_name, "mysql", "root", DEFAULT_PASSWORD):
    logger.fatal("Can't start mysql server in docker container " + node_name)
  if "sql" in params:
      url = "/".join(params["sql"].split("/",3)[:3])
      file = params["sql"].split("/",3)[3]
      run_fatal(logger,
                ["/bin/sh","-c","MC_HOST_minio={url} tools/mc cat minio/{file} | docker exec -i {node_name} mysql -uroot -p'{password}'".format(
                    url=url, file=file, node_name=node_name, password=DEFAULT_PASSWORD)],"Can't load sql file from S3")


def setup(node_args, usr, ns_prefix, node_name):
  params = soft_params(node_args)
  pass_encoded = urllib.parse.quote_plus(DEFAULT_PASSWORD)
  if "cluster-name" not in params:
    params["cluster-name"] = "cluster1"
  if "group-replication" in params and "master" not in params:
    run_fatal(logger, [
                "docker", "exec", node_name,
                "bash", "-c",
                """until mysqlsh --password=$MYSQL_ROOT_PASSWORD -e "dba.createCluster('{}', {{}})" ; do sleep 1; done""".format(params["cluster-name"]) ],
              "Can't set up first Group replication node")
  if "group-replication" in params and "master" in params:
    if params["master"] == "node0":
      params["master"] = "default"

    master_nodename = "{}{}-{}".format(ns_prefix,usr,params["master"])
    master_hostname = master_nodename.replace(".", "-")
    node_hostname = node_name.replace(".", "-")

    run_fatal(logger, [
                "docker", "exec", node_name,
                "bash", "-c",
                """mysqlsh --host={master_host} --password=$MYSQL_ROOT_PASSWORD -e "var c=dba.getCluster();c.addInstance('root:{password}@{node}:3306', {{recoveryMethod: 'clone', label: '{node}'}})" """.format(master_host=master_hostname, password=pass_encoded, node=node_hostname) ],
              "Can't set up secondary Group replication node {node}".format(node=node_name),
              r"is shutting down")
    run_fatal(logger, [
                "docker", "exec", master_nodename,
                "bash", "-c",
                """until mysql -N -uroot -p"$MYSQL_ROOT_PASSWORD" -e "select MEMBER_STATE from performance_schema.replication_group_members where member_host='{node}'"|grep -q ONLINE ; do sleep 1 ; done""".format(node=node_hostname) ], "Group replication node {node} is not ONLINE".format(node=node_name))

