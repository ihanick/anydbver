import os
import sys
import re
import subprocess


COMMAND_TIMEOUT=600

def run_fatal(logger, args, err_msg, ignore_msg=None, print_cmd=True, env={}):
  env_vars = env.copy()
  if print_cmd:
    envstr = ""
    for v in env_vars:
      envstr = envstr + " " + v + "=" + env_vars[v]
    logger.info(envstr + " " + subprocess.list2cmdline(args))
  env_vars.update(os.environ.copy())
  proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, close_fds=True, env=env_vars)
  if proc is None or proc.stdout is None:
    return
  output = ''
  while proc.poll() is None:
    text = proc.stdout.readline().decode('utf-8')
    output = output + text
    #log.write(text)
    if print_cmd:
      sys.stdout.write(text)
  ret_code = proc.wait(timeout=COMMAND_TIMEOUT)
  if ignore_msg and re.search(ignore_msg, output):
    return ret_code
  if ret_code:
    logger.error(output)
    raise Exception((err_msg+" '{}'").format(subprocess.list2cmdline(args)))
  return ret_code

def run_get_line(logger, args,err_msg, ignore_msg=None, print_cmd=True):
  if print_cmd:
    logger.info(subprocess.list2cmdline(args))
  proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, close_fds=True)
  ret_code = proc.wait(timeout=COMMAND_TIMEOUT)
  output = proc.communicate()[0].decode('utf-8')
  if ignore_msg and re.search(ignore_msg, output):
    return output
  if ret_code:
    logger.error(output)
    raise Exception((err_msg+" '{}'").format(subprocess.list2cmdline(args)))
  return output
 

def soft_params(opt):
  params = {}
  if (',' not in opt) and '=' not in opt:
    params["version"] = opt
    return params
  if (',' not in opt):
    opt = "True," + opt
  (program_version, program_params) = opt.split(",",1)
  if '=' not in program_version:
    params["version"] = program_version
  else:
    params["version"] = "True"
    program_params = opt
  for param in program_params.split(","):
    if '=' in param:
      (k,v) = param.split("=",1)
      k.replace('_','-')
      if k == "ns":
        k = "namespace"
      if k == "s3sql":
        k = "sql"
      if k == "s3sql":
        k = "sql"
      params[k] = v
    else:
      params[param] = True

  return params

