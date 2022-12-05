#!/usr/bin/env python3
import logging
import os
import re
import sys
import argparse
import itertools
import subprocess
from pathlib import Path

COMMAND_TIMEOUT=600

USER="ihanick"

FORMAT = '%(asctime)s %(levelname)s %(message)s'
logging.basicConfig(format=FORMAT)
logger = logging.getLogger('run k8s operator')
logger.setLevel(logging.INFO)

def run_fatal(args, err_msg, ignore_msg=None, print_cmd=True, env=None):
  if print_cmd:
    logger.info(subprocess.list2cmdline(args))
  process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, close_fds=True, env=env)
  ret_code = process.wait(timeout=COMMAND_TIMEOUT)
  output = process.communicate()[0].decode('utf-8')
  if ignore_msg and re.search(ignore_msg, output):
    return ret_code
  if ret_code:
    logger.error(output)
    raise Exception((err_msg+" '{}'").format(subprocess.list2cmdline(process.args)))
  return ret_code

def ssh_config_append_node(ns, node, ip, user):
  ns = ""
  if ns != "":
    ns = ns + "-"
  ssh_node = """
Host {node} {fullnode}
   User root
   HostName {ip}
   StrictHostKeyChecking no
   UserKnownHostsFile /dev/null
   ProxyCommand none
   IdentityFile secret/id_rsa
""".format(node=node,ip=ip, fullnode="{}.{}".format(user, node))
  with open("{}ssh_config".format(ns), "a") as ssh_config:
    ssh_config.write(ssh_node)

def ansible_hosts_append_node(ns, node, ip, user):
  ns = ""
  if ns != "":
    ns = ns + "-"
  ansible_host = """\
      {node} ansible_connection=ssh ansible_user=root ansible_ssh_private_key_file=secret/id_rsa ansible_host={ip} ansible_python_interpreter=/usr/bin/python3 ansible_ssh_common_args='-o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o GSSAPIDelegateCredentials=no -o GSSAPIKeyExchange=no -o GSSAPITrustDNS=no -o ProxyCommand=none'
""".format(node="{}.{}".format(user,node), ip=ip)
  with open("{}ansible_hosts".format(ns), "a") as ansible_hosts:
    ansible_hosts.write(ansible_host)

def run_get_line(args,err_msg, ignore_msg=None, print_cmd=True, env=None):
  if print_cmd:
    logger.info(subprocess.list2cmdline(args))
  process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, close_fds=True, env=env)
  ret_code = process.wait(timeout=COMMAND_TIMEOUT)
  output = process.communicate()[0].decode('utf-8')
  if ignore_msg and re.search(ignore_msg, output):
    return output
  if ret_code:
    logger.error(output)
    raise Exception((err_msg+" '{}'").format(subprocess.list2cmdline(process.args)))
  return output



def get_node_ip(namespace, name):
  container_name = name
  if namespace != "":
    container_name = namespace + "-" + name

  return list(run_get_line(["docker", "inspect", "-f", "{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}", container_name], "Can't get node ip").splitlines())[0]

def start_container(args, name):
  container_name = name
  if args.namespace != "":
    container_name = args.namespace + "-" + name

  net = "{}{}-anydbver".format(args.namespace, args.user)
  run_fatal(["docker", "network", "create", net], "Can't create a docker network", "already exists")
  run_fatal(["docker", "run", "--name", container_name,
             "-d", "--cgroupns=host", "--tmpfs", "/tmp", "--network", net,
             "--tmpfs", "/run", "-v", "/sys/fs/cgroup:/sys/fs/cgroup", "rockylinux:8-sshd-systemd"],
            "Can't start docker container")
  ssh_config_append_node(args.namespace, name, get_node_ip(args.namespace, name), args.user)
  ansible_hosts_append_node(args.namespace, name, get_node_ip(args.namespace, name), args.user)

def delete_container(namespace, name):
  container_name = name
  if namespace != "":
    container_name = namespace + "-" + name
  run_fatal(["docker", "rm", "-f", container_name],
            "Can't delete docker container")


def get_all_nodes(args):
  nodes = ["default"]
  for name in range(1, args.nodes):
    nodes.append("node"+str(name))
  return nodes

def deploy(args):
  for name in get_all_nodes(args):
    start_container(args, name)

def destroy(args):
  for name in get_all_nodes(args):
    delete_container(args.namespace,name)


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--deploy', dest="deploy", action='store_true')
  parser.add_argument('--destroy', dest="destroy", action='store_true')
  parser.add_argument('--nodes', dest="nodes", type=int, default=1)
  parser.add_argument('--namespace', dest="namespace", type=str, default="")
  args = parser.parse_args()

  args.user = os.getlogin()
  args.os = "rocky8"

  if args.destroy:
    destroy(args)
  if args.deploy:
    deploy(args)



if __name__ == '__main__':
  main()
