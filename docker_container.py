#!/usr/bin/env python3
import logging
import os
import re
import sys
import argparse
import subprocess
from pathlib import Path
import platform
import time

COMMAND_TIMEOUT=600

FORMAT = '%(asctime)s %(levelname)s %(message)s'
logging.basicConfig(format=FORMAT)
logger = logging.getLogger('run k8s operator')
logger.setLevel(logging.INFO)

def create_ssh_keys():
  if (not Path("secret/.ssh/id_rsa").is_file()):
    run_fatal(["/bin/sh", "-c",
               "test -f secret/id_rsa || ssh-keygen -t rsa -f secret/id_rsa -P '' && chmod 0600 secret/id_rsa"],
              "Can't create a docker network", "can't create ssh keys")

def load_sett_file(provider, echo=True):
  if not Path(".anydbver").is_file():
    logger.info("Creating new settings file .anydbver with provider {}".format(provider))
    with open(".anydbver", "w") as file:
      file.write("PROVIDER={}".format(provider))

  sett = {}
  with open(".anydbver") as file:
   for l in file.readlines():
     (k,v) = l.split('=',1)
     sett[k] = v.strip()
  if echo:
    print("Loaded settings: ", sett)
  return sett

def run_fatal(args, err_msg, ignore_msg=None, print_cmd=True, env=None):
  if print_cmd:
    logger.info(subprocess.list2cmdline(args))
  process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, close_fds=True, env=env)
  ret_code = process.wait(timeout=COMMAND_TIMEOUT)
  output = process.communicate()[0].decode('utf-8')
  if ignore_msg and re.search(ignore_msg, output):
    return ret_code
  if ret_code:
    logger.error(output)
    raise Exception((err_msg+" '{}'").format(subprocess.list2cmdline(process.args)))
  return ret_code

def ssh_config_append_node(ns, node, ip, user):
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



def get_node_ip(provider, namespace, name):
  container_name = name
  if namespace != "":
    container_name = namespace + "-" + name

  if provider == "docker":
    return list(run_get_line(["docker", "inspect", "-f", "{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}", container_name], "Can't get node ip").splitlines())[0]
  elif provider == "lxd":
    container_name = container_name.replace(".","-")
    result = subprocess.run(['lxc', 'info', container_name], stdout=subprocess.PIPE)
    for l in result.stdout.decode('utf-8').splitlines():
      if "inet:" in l and "127.0.0.1" not in l:
        return l.split(':')[1].strip().split('/')[0]
    return ""
  else:
    return ""

def get_docker_os_image(os_name):
  if os_name is None:
    return ("rockylinux:8-sshd-systemd", "/usr/bin/python3")
  if os_name == "":
    return ("rockylinux:8-sshd-systemd", "/usr/bin/python3")
  if os_name in ("el9", "rocky9", "rockylinux9", "centos9"):
    return ("rockylinux:9-sshd-systemd", "/usr/bin/python3")
  if os_name in ("el7", "centos7"):
    return ("centos:7-sshd-systemd", "/usr/bin/python")
  if os_name in ("jammy", "20.04", "ubuntu-20.04", "ubuntu20.04"):
    return ("ubuntu:jammy-sshd-systemd", "/usr/bin/python3")
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

def start_container(args, name, priv):
  name_user = "{user}-{nodename}".format(user=args.user, nodename=name)
  ns_prefix = ""
  if args.namespace != "":
    ns_prefix = args.namespace + "-"
  container_name = "{ns_prefix}{user}-{nodename}".format(ns_prefix=ns_prefix, user=args.user, nodename=name)

  (docker_img, python_path) = get_docker_os_image(get_node_os(args.os, name))

  if args.provider=="docker":
    net = "{ns_prefix}{usr}-anydbver".format(ns_prefix=ns_prefix, usr=args.user)
    run_fatal(["docker", "network", "create", net], "Can't create a docker network", "already exists")
    ptfm = "linux/amd64"
    if platform.machine() == "aarch64":
      ptfm = "linux/arm64"
    run_fatal([
      "docker", "run",
      "--platform", ptfm, "--name", container_name,
      "-d", "--cgroupns=host", "--tmpfs", "/tmp", "--network", net,
      "--tmpfs", "/run", "--tmpfs", "/run/lock", "-v", "/sys/fs/cgroup:/sys/fs/cgroup",
      "--hostname", name, "{}-{}".format(docker_img, args.user)],
              "Can't start docker container")
  elif args.provider=="lxd":
    container_name = container_name.replace(".","-")
    lxd_launch_cmd = [ "lxc", "launch", "--profile", args.user, "{}-{}".format(docker_img.replace(":","/"),args.user), container_name ]
    if priv:
      lxd_launch_cmd.extend(['-c', 'security.nesting=true', '-c', 'security.privileged=true'])
    run_fatal(lxd_launch_cmd,
              "Can't start lxd container")
    os.system("until lxc exec {node} true ; do sleep 1;done; echo 'Connected to {node} via lxc'".format(node=container_name))
    create_ssh_keys()
    run_fatal(["lxc", "file", "push", "secret/id_rsa.pub", "{}/root/.ssh/authorized_keys".format(container_name)],
              "Can't allow ssh connections with keys")

  node_ip = ""
  while node_ip == "":
    node_ip = get_node_ip(args.provider, args.namespace, name_user)
    time.sleep(1)
  logger.info("Found node {} with ip {}".format(name_user, node_ip))
  ssh_config_append_node(args.namespace, name, node_ip, args.user)
  ansible_hosts_append_node(args.namespace, name, node_ip, args.user, python_path)
  os.system("until ssh -F {ns_prefix}ssh_config root@{node} true ; do sleep 1;done; echo 'Connected to {node} via ssh'".format(ns_prefix=ns_prefix, node=name))

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
  skip_nodes_list = args.skip_nodes.split(",")
  priv_nodes_list = args.priv_nodes.split(",")
  for name in get_all_nodes(args):
    if name not in skip_nodes_list:
      start_container(args, name, name in priv_nodes_list)

def destroy(args):
  for name in get_all_nodes(args):
    delete_container(args.namespace,name)


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--deploy', dest="deploy", action='store_true')
  parser.add_argument('--destroy', dest="destroy", action='store_true')
  parser.add_argument('--nodes', dest="nodes", type=int, default=1)
  parser.add_argument('--skip-nodes', dest="skip_nodes", type=str, default="")
  parser.add_argument('--priv-nodes', dest="priv_nodes", type=str, default="")
  parser.add_argument('--os', dest="os", type=str, default="rocky8")
  parser.add_argument('--namespace', dest="namespace", type=str, default="")
  parser.add_argument('--provider', dest="provider", type=str, default="docker")
  args = parser.parse_args()

  sett = load_sett_file(args.provider)

  if args.provider == "lxd" and "LXD_PROFILE" in sett:
    args.user = sett["LXD_PROFILE"]
  elif "USER" in os.environ:
    args.user = os.environ["USER"]
  else:
    args.user = os.getlogin()

  if args.destroy:
    destroy(args)
  if args.deploy:
    deploy(args)



if __name__ == '__main__':
  main()
