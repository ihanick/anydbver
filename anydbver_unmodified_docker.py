from anydbver_common import logger
from unmodified_docker import pmm as docker_pmm
from unmodified_docker import mysql_server as docker_mysql_server
from unmodified_docker import pxc as docker_pxc
from unmodified_docker import percona_server_mysql as docker_percona_server_mysql
from unmodified_docker import mariadb as docker_mariadb
from unmodified_docker import postgresql as docker_postgresql
from unmodified_docker import percona_postgresql as docker_percona_postgresql
from unmodified_docker import alertmanager as docker_alertmanager
from unmodified_docker import percona_server_mongodb as docker_percona_server_mongodb
from unmodified_docker import samba as docker_samba
from unmodified_docker import minio as docker_minio

def setup_unmodified_docker_images(usr, ns, node_name, node):
  ns_prefix = ns
  if ns_prefix != "":
    ns_prefix = ns_prefix + "-"
  logger.info("Setting up node {} with unmodified docker image".format(node_name))

  if node.mysql_server:
    docker_mysql_server.setup(node.mysql_server, usr, ns_prefix, node_name)
  if node.samba:
    docker_samba.setup(node_name)

def deploy_unmodified_docker_images(usr, ns, node_name, node):
  ns_prefix = ns
  if ns_prefix != "":
    ns_prefix = ns_prefix + "-"
  net = "{}{}-anydbver".format(ns_prefix, usr)
  logger.info("Deploying node with unmodified docker image")
  if node.pmm:
    docker_pmm.deploy(node.pmm, node_name, net)
  if node.mysql_server:
    docker_mysql_server.deploy(node.mysql_server, node_name, usr, net, ns_prefix)
  if node.percona_xtradb_cluster:
    docker_pxc.deploy(node.percona_xtradb_cluster, node_name, net)
  if node.percona_server:
    docker_percona_server_mysql.deploy(node.percona_server, node_name, net)
  if node.mariadb:
    docker_mariadb.deploy(node.mariadb, node_name, net)
  if node.postgresql:
    docker_postgresql.deploy(node.postgresql, node_name, usr, net, ns_prefix)
  if node.percona_postgresql:
    docker_percona_postgresql.deploy(node.percona_postgresql, node_name, usr, net, ns_prefix)
  if node.alertmanager:
    docker_alertmanager.deploy(node.alertmanager, node_name, net)
  if node.minio:
    docker_minio.deploy(node.minio, node_name, net)
  if node.percona_server_mongodb:
    docker_percona_server_mongodb.deploy(node.percona_server_mongodb, node_name, net)
  if node.samba:
    docker_samba.deploy(node.samba, node_name, net)

