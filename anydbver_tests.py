import sqlite3
from anydbver_run_tools import run_fatal
def exec_shell_from_sqlite(logger, sql, params, err_msg):
  db_file = 'anydbver_version.db'
  try:
    conn = sqlite3.connect(db_file)
    conn.row_factory = sqlite3.Row
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()
  cur.execute(sql, params)
  rows = cur.fetchall()
  for row in rows:
    logger.info(row["cmd"])
    run_fatal(logger, ["/bin/sh", "-c", row["cmd"] ], err_msg)

def get_test_ids(logger, name):
  sql = "SELECT test_id FROM tests WHERE test_name = ?"
  params = (name,)
  if name == "all":
    sql = "SELECT test_id FROM tests"
    params = ()
  db_file = 'anydbver_version.db'
  res = []
  try:
    conn = sqlite3.connect(db_file)
    conn.row_factory = sqlite3.Row
  except sqlite3.Error as e:
    logger.error(e)
    return []
  cur = conn.cursor()
  cur.execute(sql, params)
  rows = cur.fetchall()
  for row in rows:
    res.append(row["test_id"])
  return res


def test(logger, name):
  logger.info("Testing {}".format(name))
  for t_id in get_test_ids(logger, name):
    exec_shell_from_sqlite(logger, "SELECT cmd FROM tests WHERE test_id = ?", (t_id,), "Can't prepare a test {}".format(name))
    exec_shell_from_sqlite(logger, "SELECT cmd FROM test_cases WHERE test_id = ?", (t_id,), "Can't run a test {}".format(name))


