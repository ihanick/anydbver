import datetime
import time

from anydbver_run_tools import run_fatal
from anydbver_common import logger, COMMAND_TIMEOUT

def wait_mysql_ready(name, sql_cmd,user,password, timeout=COMMAND_TIMEOUT):
  for _ in range(timeout // 2):
    s = datetime.datetime.now()
    if run_fatal(logger, ["docker", "exec", name, sql_cmd, "-u", user, "-p"+password, "--silent", "--connect-timeout=30", "--wait", "-e", "SELECT 1;"],
        "container {} ready wait problem".format(name),
        r"connect to local MySQL server through socket|Using a password on the command line interface can be insecure|connect to local server through socket|Access denied for user", False) == 0:
      return True
    if (datetime.datetime.now() - s).total_seconds() < 1.5:
      time.sleep(2)
  return False
