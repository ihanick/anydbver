#!/usr/bin/env python3
import logging
import os
import re
import sys
import argparse
import itertools
import subprocess
from pathlib import Path
import platform

COMMAND_TIMEOUT=600

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

def ansible_hosts_append_node(ns, node, ip, user, python_path):
  ns = ""
  ssh_options = ""
  if ns != "":
    ns = ns + "-"
  if sys.platform == "linux" or sys.platform == "linux2":
    ssh_options = "-o GSSAPIAuthentication=no -o GSSAPIDelegateCredentials=no -o GSSAPIKeyExchange=no -o GSSAPITrustDNS=no"
  ansible_host = """\
      {node} ansible_connection=ssh ansible_user=root ansible_ssh_private_key_file=secret/id_rsa ansible_host={ip} ansible_python_interpreter={python_path} ansible_ssh_common_args='-o StrictHostKeyChecking=no {ssh_options} -o ProxyCommand=none'
""".format(node="{}.{}".format(user,node), ip=ip,ssh_options=ssh_options, python_path=python_path)
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

def get_docker_os_image(os_name):
  if os_name is None:
    return ("rockylinux:8-sshd-systemd", "/usr/bin/python3")
  if os_name == "":
    return ("rockylinux:8-sshd-systemd", "/usr/bin/python3")
  if os_name in ("el9", "rocky9", "rockylinux9", "centos9"):
    return ("rockylinux:9-sshd-systemd", "/usr/bin/python3")
  if os_name in ("el7", "centos7"):
    return ("centos:7-sshd-systemd", "/usr/bin/python")
  return ("rockylinux:8-sshd-systemd", "/usr/bin/python3")

def get_node_os(os_str, name):
  if name == "default":
    name = "node0"
  # os_str="rocky8,node0=rocky8,node1=rocky9"
  os_search = re.search(',{node_name}=(.*?)(?:,|$)'.format(node_name=name), os_str)

  logger.info("Trying to find os: {} for {}".format(os_str, name))
  if os_search:
    logger.info("Found OS for {name}: {os}".format(name=name, os=os_search.group(1)))
    return os_search.group(1)
  return ""

def start_container(args, name):
  container_name = "{user}-{nodename}".format(user=args.user, nodename=name)
  name_user = container_name
  if args.namespace != "":
    container_name = args.namespace + "-" + name

  (docker_img, python_path) = get_docker_os_image(get_node_os(args.os, name))

  net = "{}{}-anydbver".format(args.namespace, args.user)
  run_fatal(["docker", "network", "create", net], "Can't create a docker network", "already exists")
  ptfm = "linux/amd64"
  if platform.machine() == "aarch64":
    ptfm = "linux/arm64"
  run_fatal([
    "docker", "run",
    "--platform", ptfm, "--name", container_name,
    "-d", "--cgroupns=host", "--tmpfs", "/tmp", "--network", net,
    "--tmpfs", "/run", "-v", "/sys/fs/cgroup:/sys/fs/cgroup",
    "--hostname", name, docker_img],
            "Can't start docker container")
  node_ip = get_node_ip(args.namespace, name_user)
  ssh_config_append_node(args.namespace, name, node_ip, args.user)
  ansible_hosts_append_node(args.namespace, name, node_ip, args.user, python_path)
  os.system("until ssh -F ssh_config root@{node} true ; do sleep 1;done".format(node=name))

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
  parser.add_argument('--os', dest="os", type=str, default="rocky8")
  parser.add_argument('--namespace', dest="namespace", type=str, default="")
  args = parser.parse_args()

  if "USER" in os.environ:
    args.user = os.environ["USER"]
  else:
    args.user = os.getlogin()

  if args.destroy:
    destroy(args)
  if args.deploy:
    deploy(args)



if __name__ == '__main__':
  main()
