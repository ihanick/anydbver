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
 
