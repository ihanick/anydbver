import urllib.request
import urllib.error
import json
import re
import os
from pathlib import Path
import sqlite3

def strip_version(v):
  (v,p) = ''.join(c for c in v if c.isdigit() or c == '.' or c == '-').split('-')
  if p is None or p == '':
    p = "0"
  vernum = 0
  patchnum = 0
  for n in v.split('.'):
    if n == "":
      continue
    vernum = vernum * 1000 + int(n)

  for n in p.split('.'):
    if n == "":
      continue
    patchnum = patchnum * 1000 + int(n)

  return float(vernum)*10000 + float(patchnum)


def append_versions_from_url(vers, url, r):
  try:
    with urllib.request.urlopen(url) as response:
      m = re.findall(r, response.read().decode('utf-8'))
      for i in m:
        vers.append(i)
  except urllib.error.HTTPError as e:
    print(e, url, vers)
    return


def generate_versions_file(filename, src_info):
  versions = []
  for prg in src_info:
    append_versions_from_url(versions, prg["url"], prg["pattern"])
  # keep only unique versions
  versions = list(dict.fromkeys(versions))
  versions.sort(key=lambda x: strip_version(x))
  with open( str((Path(os.getcwd()) / ".version-info" / filename).resolve()), "w") as f:
    f.write("\n".join(versions) + "\n")

def save_postgresql_versions_to_sqlite(osver):
  osname = "el8"
  repo_url = "http://yum.postgresql.org/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm"

  if osver == "el7":
    repo_url = "http://yum.postgresql.org/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
    osname = 'rhel7'
  elif osver == "el8":
    repo_url = "http://yum.postgresql.org/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
    osname = 'rhel8'
  elif osver == 'el9':
    repo_url = "http://yum.postgresql.org/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
    osname = 'rhel9'

  db_file = 'anydbver_version.db'
  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()
  vers = list(open(".version-info/pg.{os}.txt".format(os=osver)))
  vers2 = {}
  ver2_file = ".version-info/pg2.{os}.txt".format(os=osver)
  if osver == "el8" and Path(ver2_file).is_file():
    vers2_list = list(open(ver2_file))
    for ver2 in vers2_list:
      (ver1, ver2) = ver2.split(' ')
      vers2[ver1] = ver2.rstrip()

  sql = """\
    INSERT OR REPLACE INTO postgresql_version(
      version,
      os,
      arch,
      repo_url,
      repo_file,
      repo_enable_str,
      systemd_service,
      packages,
      debug_packages
    )
    VALUES (?,?,?,?,?,?,?,?,?)
    """
  for line in vers:
    ver = line.rstrip()
    ver2 = ''
    maj_ver = ver.split('.',1)[0]
    if ver in vers2:
      ver2 = vers2[ver]
    project = ()
    if osver.startswith('el'):
      pkgs = ["postgresql{maj}-libs".format(maj=maj_ver),
      "postgresql{maj}".format(maj=maj_ver),
      "postgresql{maj}-server".format(maj=maj_ver),
      "postgresql{maj}-contrib".format(maj=maj_ver)]
      pkgs = ["{}-{}PGDG.{}.x86_64".format(pkg,ver,osname) for pkg in pkgs ]
      #if osver == "el8" and ver2 != '':
      #  pkgs.insert(1,"postgresql-common-{ver2}PGDG.{osver}.noarch".format(ver2=ver2, osver=osname))

      ver_no_dot = maj_ver
      if ver.startswith('11.5'):
        ver_no_dot = '11.5'


      project = (
        ver,
        osver,
        'x86_64',
        repo_url,
        '/etc/yum.repos.d/percona-ppg-{ver_no_dot}-release.repo'.format(ver_no_dot=ver_no_dot),
        'ppg-{ver_no_dot}'.format(ver_no_dot=ver_no_dot),
        'postgresql-{maj}'.format(maj=maj_ver),
        '|'.join(pkgs),
        'gdb|percona-postgresql{maj}-server-debuginfo-{ver}.{osver}.x86_64'.format(maj=maj_ver, ver=ver,osver=osver)
      )

    if len(project) > 1:
      cur.execute(sql, project)
  conn.commit()


def save_percona_postgresql_versions_to_sqlite(osver):
  if osver == 'el9':
    return

  db_file = 'anydbver_version.db'
  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()
  vers = list(open(".version-info/ppg.{os}.txt".format(os=osver)))
  vers2 = {}
  vers2_file = ".version-info/ppg2.{os}.txt".format(os=osver)
  if osver == "el8" and Path(vers2_file).is_file():
    vers2_list = list(open(vers2_file))
    for ver2 in vers2_list:
      (ver1, ver2) = ver2.split(' ')
      vers2[ver1] = ver2.rstrip()

  sql = """\
    INSERT OR REPLACE INTO percona_postgresql_version(
      version,
      os,
      arch,
      repo_url,
      repo_file,
      repo_enable_str,
      systemd_service,
      packages,
      debug_packages
    )
    VALUES (?,?,?,?,?,?,?,?,?)
    """
  for line in vers:
    ver = line.rstrip()
    ver2 = ''
    maj_ver = ver.split('.',1)[0]
    if ver in vers2:
      ver2 = vers2[ver]
    project = ()
    if osver.startswith('el'):
      pkgs = ["percona-postgresql{maj}-libs".format(maj=maj_ver),
      "percona-postgresql{maj}".format(maj=maj_ver),
      "percona-postgresql{maj}-server".format(maj=maj_ver),
      "percona-postgresql{maj}-contrib".format(maj=maj_ver)]
      pkgs = ["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]
      #if osver == "el8":
      #  pkgs.insert(1,"percona-postgresql-common-{ver2}.{osver}.noarch".format(ver2=ver2, osver=osver))

      ver_no_dot = maj_ver
      if ver.startswith('11.5'):
        ver_no_dot = '11.5'

      project = (
        ver,
        osver,
        'x86_64',
        'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
        '/etc/yum.repos.d/percona-ppg-{ver_no_dot}-release.repo'.format(ver_no_dot=ver_no_dot),
        'ppg-{ver_no_dot}'.format(ver_no_dot=ver_no_dot),
        'postgresql-{maj}'.format(maj=maj_ver),
        '|'.join(pkgs),
        'gdb|percona-postgresql{maj}-server-debuginfo-{ver}.{osver}.x86_64'.format(maj=maj_ver, ver=ver,osver=osver)
      )

    if len(project) > 1:
      cur.execute(sql, project)
  conn.commit()

def create_percona_backup_mongodb_table():
  db_file = 'anydbver_version.db'

  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()

  sql = """
CREATE TABLE if not exists percona_backup_mongodb_version(
  version varchar(20),
  os varchar(20),
  arch varchar(20),
  packages varchar(1000),
  constraint pk PRIMARY KEY(version, os, arch)
);
"""

  cur.execute(sql, ())
  conn.commit()


def save_percona_backup_mongodb_versions_to_sqlite(osver):
  create_percona_backup_mongodb_table()

  arch = 'x86_64'

  db_file = 'anydbver_version.db'
  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()
  vers = list(open(".version-info/pbm.{os}.txt".format(os=osver)))
  sql = """\
    INSERT OR REPLACE INTO percona_backup_mongodb_version(
      version, os, arch, packages
    )
    VALUES (?,?,?,?)
    """
  for line in vers:
    ver = line.rstrip()
    project = ()
    if osver.startswith('el'):
      pbm_ver_short = re.sub(r'^([0-9]+\.[0-9]+\.[0-9]+)-.*$', r'\1', ver) 
      pbm_repo_url = 'https://www.percona.com/downloads/percona-backup-mongodb/percona-backup-mongodb-{pbm_version_short}'.format(pbm_version_short=pbm_ver_short)
      project = (
        ver, osver, arch,
        '{pbm_repo_url}/binary/redhat/{osver_num}/{arch}/percona-backup-mongodb-{pbm_version}.{dist}.{arch}.rpm'.format(
          pbm_repo_url=pbm_repo_url,
          pbm_version=ver,
          dist=osver,
          osver_num=osver.replace("el",""),
          arch=arch)
      )

    if len(project) > 1:
      cur.execute(sql, project)
  conn.commit()


    
def save_percona_server_mongodb_versions_to_sqlite(osver):

  db_file = 'anydbver_version.db'
  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()
  for arch in ('x86_64', 'aarch64'):
    vers_file = ".version-info/psmdb.{os}.{arch}.txt".format(os=osver, arch=arch) 
    if not os.path.exists(vers_file):
      continue
 
    vers = list(open(vers_file))
    sql = """\
      INSERT OR REPLACE INTO percona_server_mongodb_version(
        version, os, arch, repo_url, repo_file, repo_enable_str,
        systemd_service, conf_file, packages,
        debug_packages
      )
      VALUES (?,?,?,?,?,?,?,?,?,?)
      """
    for line in vers:
      ver = line.rstrip()
      project = ()
      if osver.startswith('el'):
        pkgs = ['percona-server-mongodb-tools','percona-server-mongodb-server', 'percona-server-mongodb-mongos', 'percona-server-mongodb']
        pkgs = ["{}-{}.{}.{}".format(pkg,ver,osver, arch) for pkg in pkgs ]
        if ver.startswith('6.0') or ver.startswith('7.0'):
          mongoshver = '1.6.1-1'
          if ver.startswith('6.0.2'):
            mongoshver = '1.6.0-1'
            pkgs.insert(1,'percona-mongodb-mongosh-{mongoshver}.{osver}.{arch}'.format(mongoshver=mongoshver,osver=osver, arch=arch))
          else:
            pkgs.insert(1,'percona-mongodb-mongosh')
        else:
          pkgs.insert(1,'percona-server-mongodb-shell-{ver}.{osver}.{arch}'.format(ver=ver,osver=osver, arch=arch))

        ver_no_dot = ''.join(ver.split('.',2)[0:2])
        project = (
          ver, osver, arch,
          'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
          '/etc/yum.repos.d/percona-psmdb-{ver_no_dot}-release.repo'.format(ver_no_dot=ver_no_dot),
          'psmdb-{ver_no_dot}'.format(ver_no_dot=ver_no_dot), 'mongod', '/etc/mongod.conf',
          '|'.join(pkgs),
          'gdb|percona-server-mongodb-debuginfo-{ver}.{osver}.{arch}'.format(ver=ver,osver=osver, arch=arch)
        )

      if len(project) > 1:
        cur.execute(sql, project)
    conn.commit()


def save_mysql_server_versions_to_sqlite(osver):
  repo_url = 'http://repo.mysql.com/mysql80-community-release-el8-4.noarch.rpm'
  db_file = 'anydbver_version.db'
  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()
  for arch in ("x86_64","aarch64"):
    vers_file = ".version-info/mysql.{os}.txt".format(os=osver)
    if arch == 'aarch64':
      vers_file = ".version-info/mysql.{os}.{arch}.txt".format(os=osver,arch=arch)
    if not os.path.exists(vers_file):
      continue
    vers = list(open(vers_file))
    sql = """\
      INSERT OR REPLACE INTO mysql_server_version(
        version, os, arch, repo_url, repo_file, repo_enable_str,
        systemd_service, cnf_file, packages,
        debug_packages,
        tests_packages, mysql_shell_packages, mysql_router_packages
      )
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
      """
    for line in vers:
      ver = line.rstrip()
      project = ()
      if osver.startswith('el'):
        pkgs = ["mysql-community-common", "mysql-community-libs", "mysql-community-client", "mysql-community-server"]
        dbg_pkg = ['gdb']
        if ver.startswith('8.0'):
          dbg_pkg.append('https://cdn.mysql.com//Downloads/MySQL-8.0/mysql-community-debuginfo-{ver}.{osver}.{arch}.rpm'.format(ver=ver,osver=osver,arch=arch))
        if ver.startswith('5.7'):
          dbg_pkg.append('https://cdn.mysql.com//Downloads/MySQL-5.7/mysql-community-debuginfo-{ver}.{osver}.{arch}.rpm'.format(ver=ver,osver=osver,arch=arch))
        if ver.startswith('5.6'):
          dbg_pkg.append('https://cdn.mysql.com//Downloads/MySQL-5.6/mysql-community-debuginfo-{ver}.{osver}.{arch}.rpm'.format(ver=ver,osver=osver,arch=arch))
        if osver == 'el7':
          repo_url = 'http://repo.mysql.com/mysql80-community-release-el7-7.noarch.rpm'
        elif osver == 'el8':
          repo_url = 'http://repo.mysql.com/mysql80-community-release-el8-4.noarch.rpm'
        elif osver == 'el9':
          repo_url = 'http://repo.mysql.com/mysql80-community-release-el9-1.noarch.rpm'

        mysql_shell_pkg = 'https://cdn.mysql.com/archives/mysql-shell/mysql-shell'
        if ver.startswith('8.0.33'):
          mysql_shell_pkg = 'http://cdn.mysql.com/Downloads/MySQL-Shell/mysql-shell'
        mysql_shell_pkg = '{url}-{ver}.{osver}.{arch}.rpm'.format(url=mysql_shell_pkg,ver=ver,osver=osver,arch=arch)
        project = (
          ver, osver, arch, repo_url,
          '',
          '', 'mysqld', '/etc/my.cnf',
          '|'.join(["{}-{}.{}.{}".format(pkg,ver,osver,arch) for pkg in pkgs ]),
          '|'.join(dbg_pkg),
          'mysql-community-test-{ver}.{osver}.{arch}'.format(ver=ver,osver=osver,arch=arch),
          mysql_shell_pkg,
          'mysql-router-community-{ver}.{osver}.{arch}'.format(ver=ver,osver=osver,arch=arch)
        )

      if len(project) > 1:
        cur.execute(sql, project)
  conn.commit()
    
def save_percona_xtradb_cluster_versions_to_sqlite(osver):
  db_file = 'anydbver_version.db'
  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()
  vers = list(open(".version-info/percona-xtradb-cluster.{os}.txt".format(os=osver)))
  sql = """\
    INSERT OR REPLACE INTO percona_xtradb_cluster_version(
      version, os, arch, repo_url, repo_file, repo_enable_str,
      systemd_service, cnf_file, packages,
      debug_packages,
      tests_packages, garbd_packages
    )
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
    """
  for line in vers:
    ver = line.rstrip()
    project = ()
    if ver.startswith('8.0') and osver.startswith('el'):
      pkgs = ['percona-xtradb-cluster-shared','percona-xtradb-cluster-client','percona-xtradb-cluster-server']
      if osver != 'el9':
        pkgs.insert(0,'percona-xtradb-cluster-shared-compat')
      pkgs = ["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]
      pkgs.insert(0,'openssl')
      project = (
        ver, osver, 'x86_64',
        'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
        '/etc/yum.repos.d/percona-pxc-80-release.repo',
        'pxc-80', 'mysqld', '/etc/my.cnf',
        '|'.join(pkgs),
        'gdb|percona-xtradb-cluster-debuginfo-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'percona-xtradb-cluster-test-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'percona-xtradb-cluster-garbd-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver)
      )
    elif ver.startswith('5.7') and osver.startswith('el'):
      pkgs = ['Percona-XtraDB-Cluster-shared-compat-57','Percona-XtraDB-Cluster-shared-57','Percona-XtraDB-Cluster-client-57','Percona-XtraDB-Cluster-server-57']
      project = (
        ver, osver, 'x86_64',
        'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
        '/etc/yum.repos.d/percona-original-release.repo',
        'pxc-57', 'mysqld', '/etc/percona-xtradb-cluster.conf.d/zz_mysqld.cnf',
        '|'.join(["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]),
        'gdb|Percona-XtraDB-Cluster-57-debuginfo-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-XtraDB-Cluster-test-57-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-XtraDB-Cluster-garbd-57-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver)
      )
    elif ver.startswith('5.6') and osver.startswith('el'):
      pkgs = ['Percona-XtraDB-Cluster-shared-56','Percona-XtraDB-Cluster-client-56','Percona-XtraDB-Cluster-server-56']
      pkgs = ["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]
      pkgs.insert(0,'which')

      project = (
        ver, osver, 'x86_64',
        'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
        '/etc/yum.repos.d/percona-original-release.repo',
        'pxc-56', 'mysql', '/etc/my.cnf',
        '|'.join(pkgs),
        'gdb|Percona-XtraDB-Cluster-56-debuginfo-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-XtraDB-Cluster-test-56-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
        'Percona-XtraDB-Cluster-garbd-56-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver)
      )
    if len(project) > 1:
      cur.execute(sql, project)
  conn.commit()

"""
CREATE TABLE mariadb_version(
  version varchar(20),
  os varchar(20),
  arch varchar(20),
  repo_url varchar(1000),
  repo_file varchar(1000),
  repo_enable_str varchar(20),
  systemd_service varchar(20),
  cnf_file varchar(100),
  packages varchar(1000),
  debug_packages varchar(1000),
  rocksdb_packages varchar(1000),
  tests_packages varchar(1000),
  mysql_shell_packages varchar(1000),
  constraint pk PRIMARY KEY(version, os, arch)
);
"""
def save_mariadb_versions_to_sqlite(osver):
  db_file = 'anydbver_version.db'
  vers_file = ".version-info/mariadb.{os}.txt".format(os=osver)
  if not os.path.exists(vers_file):
    return

  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()
  vers = list(open(vers_file))
  sql = """\
    INSERT OR REPLACE INTO mariadb_version(
      version, os, arch, repo_url, repo_file, repo_enable_str,
      systemd_service, cnf_file, packages,
      debug_packages, rocksdb_packages,
      tests_packages, mysql_shell_packages
    )
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
    """
  for line in vers:
    ver = line.rstrip()
    project = ()
    ver_short = '.'.join(ver.split('.')[0:2])
    if osver.startswith('el'):
      pkgs = ['MariaDB-common', 'MariaDB-shared', 'MariaDB-client', 'MariaDB-server']

      archive_url = 'https://mirror.mariadb.org/yum/{ver_short}/centos{elver}-amd64/rpms'.format(ver_short=ver_short, elver=osver.replace('el',''))
      pkg_suffix = "{osver}.x86_64.rpm".format(osver=osver)
      if osver.startswith('el7'):
        pkg_suffix = "{osver}.centos.x86_64.rpm".format(osver=osver)
      elif osver.startswith('el8'):
        archive_url = 'https://mirror.mariadb.org/yum/{ver_short}/rhel{elver}-amd64/rpms'.format(ver_short=ver_short, elver=osver.replace('el',''))

      #-10.5.18-1.el8.x86_64
      project = (
        ver, osver,'x86_64',
        '',
        '/etc/yum.repos.d/MariaDB.repo',
        '', 'mariadb', '/etc/my.cnf.d/zz_mysqld.cnf',
        '|'.join(["{url}/{pkg}-{ver}.{suf}".format(url=archive_url,pkg=pkg,ver=ver,suf=pkg_suffix) for pkg in pkgs ]),
        'gdb|{url}/MariaDB-server-debuginfo-{ver}.{suf}'.format(ver=ver,url=archive_url,suf=pkg_suffix),
        '{url}/MariaDB-rocksdb-engine-{ver}.{suf}'.format(url=archive_url,ver=ver,suf=pkg_suffix),
        '{url}/MariaDB-test-{ver}.{suf}'.format(url=archive_url,ver=ver,suf=pkg_suffix),
        ''
      )

    if len(project) > 1:
      cur.execute(sql, project)
  conn.commit()


  pass

def create_general_updater_table():
  db_file = 'anydbver_version.db'

  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()

  sql = """
CREATE TABLE if not exists general_version(
  version varchar(20),
  os varchar(20),
  arch varchar(20),
  program varchar(1000),
  constraint pk PRIMARY KEY(version, os, arch, program)
);
"""

  cur.execute(sql, ())
  conn.commit()

def save_general_version(ver, osver, arch, program):
  db_file = 'anydbver_version.db'

  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()

  sql = """
INSERT OR REPLACE INTO general_version(
  version,os,arch,program
)
VALUES (?,?,?,?)
"""
  cur.execute(sql, (ver,osver,arch,program))
  conn.commit()


def save_general_version_for_program(vers_file, osrver, arch, program):
  vers_file = str((Path(os.getcwd()) / ".version-info" / vers_file).resolve())
  if not os.path.exists(vers_file):
    return
  vers = list(open(vers_file))
  for line in vers:
    ver = line.rstrip()
    save_general_version(ver, osrver, arch, program)

def save_xtrabackup_versions_to_sqlite(osver):
  db_file = 'anydbver_version.db'
  vers_file = ".version-info/xtrabackup.{os}.txt".format(os=osver)
  if not os.path.exists(vers_file):
    return

  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()

  sql = """
CREATE TABLE if not exists percona_xtrabackup_version(
  version varchar(20),
  os varchar(20),
  arch varchar(20),
  repo_url varchar(1000),
  repo_file varchar(1000),
  repo_enable_str varchar(20),
  packages varchar(1000),
  debug_packages varchar(1000),
  tests_packages varchar(1000),
  constraint pk PRIMARY KEY(version, os, arch)
);
"""

  cur.execute(sql, ())

  vers = list(open(vers_file))
  sql = """\
    INSERT OR REPLACE INTO percona_xtrabackup_version(
      version, os, arch, repo_url, repo_file, repo_enable_str,
      packages, debug_packages, tests_packages
    )
    VALUES (?,?,?,?,?,?,?,?,?)
    """
  for line in vers:
    ver = line.rstrip()
    project = ()
    if osver.startswith('el'):
      versuf = '24'
      if ver.startswith('8.0'):
        versuf = '80'
      pkg_suffix = "{osver}.x86_64".format(osver=osver)
      pkgs = ['percona-xtrabackup-{versuf}-{ver}.{pkg_suffix}'.format(versuf=versuf, ver=ver, pkg_suffix=pkg_suffix)]

      project = (
        ver, osver,'x86_64',
        '', '', '',
        '|'.join(pkgs),
        '',
        ''
      )

    if len(project) > 1:
      cur.execute(sql, project)
  conn.commit()

def save_github_tags_to_sqlite(repo_name, tbl):
  db_file = 'anydbver_version.db'
  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()
  sql = "INSERT OR REPLACE INTO {tbl} (name,version) VALUES(?, ?)".format(tbl=tbl)
  url = "https://api.github.com/repos/{}/tags".format(repo_name)
  try:
    with urllib.request.urlopen(url) as response:
      r = json.loads(response.read().decode('utf-8'))
      for ver in r:
        if ver["name"].startswith("v"):
          ver["name"] = ver["name"][1:]
        cur.execute(sql, (repo_name, ver["name"]))
  except urllib.error.HTTPError as e:
    print(e, url, sql)
    return


  conn.commit()

def save_percona_server_versions_to_sqlite(osver):
  db_file = 'anydbver_version.db'
  conn = None
  try:
    conn = sqlite3.connect(db_file)
  except sqlite3.Error as e:
    print(e)
    return
  cur = conn.cursor()
  for arch in ("x86_64","aarch64"):
    vers_file = ".version-info/percona-server.{os}.txt".format(os=osver)
    if arch == 'aarch64':
      vers_file = ".version-info/percona-server.{os}.{arch}.txt".format(os=osver,arch=arch)

    if not Path(vers_file).is_file():
      continue

    vers = list(open(vers_file))
    sql = """\
      INSERT OR REPLACE INTO percona_server_version(
        version, os, arch, repo_url, repo_file, repo_enable_str,
        systemd_service, cnf_file, packages,
        debug_packages, rocksdb_packages,
        tests_packages, mysql_shell_packages, mysql_router_packages
      )
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      """
    for line in vers:
      ver = line.rstrip()
      project = ()
      if ver.startswith('8.0') and osver.startswith('el'):
        pkgs = ['percona-server-shared','percona-server-client','percona-server-server']
        if osver != 'el9' and arch == 'x86_64':
          pkgs.insert(0,'percona-server-shared-compat')
        project = (
          ver, osver,arch,
          'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
          '/etc/yum.repos.d/percona-ps-80-release.repo',
          'ps-80', 'mysqld', '/etc/my.cnf',
          '|'.join(["{}-{}.{}.{}".format(pkg,ver,osver,arch) for pkg in pkgs ]),
          'gdb|percona-server-debuginfo-{ver}.{osver}.{arch}'.format(ver=ver,osver=osver,arch=arch),
          'percona-server-rocksdb-{ver}.{osver}.{arch}'.format(ver=ver,osver=osver,arch=arch),
          'percona-server-test-{ver}.{osver}.{arch}'.format(ver=ver,osver=osver,arch=arch),
          'percona-mysql-shell-{ver}-1.{osver}.{arch}'.format(ver=ver.split('-',1)[0],osver=osver,arch=arch),
          'percona-mysql-router-{ver}.{osver}.{arch}'.format(ver=ver,osver=osver,arch=arch)
        )
      elif ver.startswith('5.7') and osver.startswith('el'):
        pkgs = ['Percona-Server-shared-compat-57','Percona-Server-shared-57','Percona-Server-client-57','Percona-Server-server-57']
        project = (
          ver, osver, arch,
          'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
          '/etc/yum.repos.d/percona-original-release.repo',
          'ps-57', 'mysqld', '/etc/percona-server.conf.d/mysqld.cnf',
          '|'.join(["{}-{}.{}.{}".format(pkg,ver,osver,arch) for pkg in pkgs ]),
          'gdb|Percona-Server-57-debuginfo-{ver}.{osver}.{arch}'.format(ver=ver,osver=osver,arch=arch),
          'Percona-Server-rocksdb-57-{ver}.{osver}.{arch}'.format(ver=ver,osver=osver,arch=arch),
          'Percona-Server-test-57-{ver}.{osver}.{arch}'.format(ver=ver,osver=osver,arch=arch),
          '',''
        )
      elif ver.startswith('5.6') and osver.startswith('el'):
        pkgs = ['Percona-Server-shared-56','Percona-Server-client-56','Percona-Server-server-56']
        project = (
          ver, osver, arch,
          'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
          '/etc/yum.repos.d/percona-original-release.repo',
          'ps-56', 'mysqld', '/etc/my.cnf',
          '|'.join(["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]),
          'gdb|Percona-Server-56-debuginfo-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
          'Percona-Server-rocksdb-56-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
          'Percona-Server-test-56-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
          '',''
        )
      elif ver.startswith('5.5') and osver.startswith('el'):
        pkgs = ['Percona-Server-shared-55','Percona-Server-client-55','Percona-Server-server-55']
        project = (
          ver, osver, arch,
          'http://repo.percona.com/yum/percona-release-latest.noarch.rpm',
          '/etc/yum.repos.d/percona-original-release.repo',
          'ps-55', 'mysql', '/etc/my.cnf',
          '|'.join(["{}-{}.{}.x86_64".format(pkg,ver,osver) for pkg in pkgs ]),
          'gdb|Percona-Server-55-debuginfo-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
          'Percona-Server-rocksdb-55-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
          'Percona-Server-test-55-{ver}.{osver}.x86_64'.format(ver=ver,osver=osver),
          '',''
        )
      if len(project) > 1:
        cur.execute(sql, project)
  conn.commit()

def update_versions():
  create_general_updater_table()
  if not os.path.exists(".version-info"):
    os.makedirs(".version-info")
  generate_versions_file("psmdb.el7.x86_64.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/7/RPMS/x86_64/",
      "pattern": r'Percona-Server-MongoDB(?:-\d\d)?-server-(\d[^"]*).el7.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-40/yum/release/7/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el7.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-42/yum/release/7/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el7.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-44/yum/release/7/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el7.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-50/yum/release/7/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el7.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-60/yum/release/7/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el7.x86_64.rpm'}
    ])

  generate_versions_file("psmdb.el8.x86_64.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/",
      "pattern": r'Percona-Server-MongoDB(?:-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-40/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-42/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-44/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-50/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-60/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-70/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el8.x86_64.rpm'}
    ])

  generate_versions_file("psmdb.el9.x86_64.txt",
    [
      {"url": "https://repo.percona.com/psmdb-60/yum/release/9/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el9.x86_64.rpm'},
      {"url": "https://repo.percona.com/psmdb-70/yum/release/9/RPMS/x86_64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el9.x86_64.rpm'}
     ])

  generate_versions_file("psmdb.el8.aarch64.txt",
    [
      {"url": "https://repo.percona.com/psmdb-60/yum/release/8/RPMS/aarch64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el8.aarch64.rpm'},
      {"url": "https://repo.percona.com/psmdb-70/yum/release/8/RPMS/aarch64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el8.aarch64.rpm'}
    ])

  generate_versions_file("psmdb.el9.aarch64.txt",
    [
      {"url": "https://repo.percona.com/psmdb-60/yum/release/9/RPMS/aarch64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el9.aarch64.rpm'},
      {"url": "https://repo.percona.com/psmdb-70/yum/release/9/RPMS/aarch64/",
      "pattern": r'percona-server-mongodb(?:-\d\d)?-server-(\d[^"]*).el9.aarch64.rpm'}
     ])

  generate_versions_file("mariadb.el8.txt",
    [
      {"url": "https://mirror.mariadb.org/yum/10.11/rhel8-amd64/rpms/",
      "pattern": r'MariaDB-server-(\d[^"]*).el8.x86_64.rpm'}
    ])



  generate_versions_file("percona-server.el7.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/7/RPMS/x86_64/",
      "pattern": r'Percona-Server-server-\d\d-(\d[^"]*).el7.x86_64.rpm'},
      {"url": "https://repo.percona.com/ps-80/yum/release/7/RPMS/x86_64/",
      "pattern": r'percona-server-server-(\d[^"]*)[.]el7.x86_64.rpm'}
    ])
  generate_versions_file("percona-server.el8.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/",
      "pattern": r'Percona-Server-server-\d\d-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/ps-80/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-server-server-(\d[^"]*)[.]el8.x86_64.rpm'}
    ])
  generate_versions_file("percona-server.el9.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/9/RPMS/x86_64/",
      "pattern": r'Percona-Server-server-\d\d-(\d[^"]*).el9.x86_64.rpm'},
      {"url": "https://repo.percona.com/ps-80/yum/release/9/RPMS/x86_64/",
      "pattern": r'percona-server-server-(\d[^"]*)[.]el9.x86_64.rpm'}
    ])
  generate_versions_file("percona-server.el8.aarch64.txt",
    [
      {"url": "https://repo.percona.com/ps-80/yum/release/8/RPMS/aarch64/",
      "pattern": r'percona-server-server-(\d[^"]*)[.]el8.aarch64.rpm'}
    ])
  generate_versions_file("percona-server.el9.aarch64.txt",
    [
      {"url": "https://repo.percona.com/ps-80/yum/release/9/RPMS/aarch64/",
      "pattern": r'percona-server-server-(\d[^"]*)[.]el9.aarch64.rpm'}
    ])


  generate_versions_file("percona-xtradb-cluster.el7.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/7/RPMS/x86_64/",
      "pattern": r'Percona-XtraDB-Cluster-server-\d\d-(\d[^"]*).el7.x86_64.rpm'},
      {"url": "https://repo.percona.com/pxc-80/yum/release/7/RPMS/x86_64/",
      "pattern": r'percona-xtradb-cluster-server-(\d[^"]*)[.]el7.x86_64.rpm'}
    ])

  generate_versions_file("percona-xtradb-cluster.el8.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/",
      "pattern": r'Percona-XtraDB-Cluster-server-\d\d-(\d[^"]*).el8.x86_64.rpm'},
      {"url": "https://repo.percona.com/pxc-80/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-xtradb-cluster-server-(\d[^"]*)[.]el8.x86_64.rpm'}
    ])

  generate_versions_file("percona-xtradb-cluster.el9.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/9/RPMS/x86_64/",
      "pattern": r'Percona-XtraDB-Cluster-server-\d\d-(\d[^"]*).el9.x86_64.rpm'},
      {"url": "https://repo.percona.com/pxc-80/yum/release/9/RPMS/x86_64/",
      "pattern": r'percona-xtradb-cluster-server-(\d[^"]*)[.]el9.x86_64.rpm'}
    ])

  generate_versions_file("pbm.el7.txt",
    [
      {"url": "https://repo.percona.com/pbm/yum/release/7/RPMS/x86_64/",
      "pattern": r'percona-backup-mongodb-(\d[^"]*).el7.x86_64.rpm'}
    ])
  generate_versions_file("pbm.el8.txt",
    [
      {"url": "https://repo.percona.com/pbm/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-backup-mongodb-(\d[^"]*).el8.x86_64.rpm'}
    ])
  generate_versions_file("pbm.el9.txt",
    [
      {"url": "https://repo.percona.com/pbm/yum/release/9/RPMS/x86_64/",
      "pattern": r'percona-backup-mongodb-(\d[^"]*).el9.x86_64.rpm'}
    ])

  generate_versions_file("percona-orchestrator.el8.txt",
    [
      {"url": "https://repo.percona.com/pdps-8.0/yum/release/8/RPMS/x86_64/",
      "pattern": r'percona-orchestrator-(\d[^"]*).el8.x86_64.rpm'}
    ])
  generate_versions_file("percona-orchestrator.el9.txt",
    [
      {"url": "https://repo.percona.com/pdps-8.0/yum/release/9/RPMS/x86_64/",
      "pattern": r'percona-orchestrator-(\d[^"]*).el9.x86_64.rpm'}
    ])

  save_general_version_for_program("percona-orchestrator.el8.txt", "el8", "x86_64", "percona-orchestrator")
  save_general_version_for_program("percona-orchestrator.el9.txt", "el9", "x86_64", "percona-orchestrator")

  generate_versions_file("pmm-client.el7.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/7/RPMS/x86_64/",
      "pattern": r'pmm\d*-client-(\d[^"]*).el7.x86_64.rpm'}
    ])
  generate_versions_file("pmm-client.el8.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/8/RPMS/x86_64/",
      "pattern": r'pmm\d*-client-(\d[^"]*).el8.x86_64.rpm'}
    ])
  generate_versions_file("pmm-client.el9.txt",
    [
      {"url": "https://repo.percona.com/percona/yum/release/9/RPMS/x86_64/",
      "pattern": r'pmm\d*-client-(\d[^"]*).el9.x86_64.rpm'}
    ])
  save_general_version_for_program("pmm-client.el7.txt", "el7", "x86_64", "pmm-client")
  save_general_version_for_program("pmm-client.el8.txt", "el8", "x86_64", "pmm-client")
  save_general_version_for_program("pmm-client.el9.txt", "el9", "x86_64", "pmm-client")

  generate_versions_file("mysql.el7.txt",
    [
      {"url": "https://repo.mysql.com/yum/mysql-5.6-community/el/7/x86_64/",
      "pattern": r'mysql-community-server-(\d[^"]*).el7.x86_64.rpm'},
      {"url": "https://repo.mysql.com/yum/mysql-5.7-community/el/7/x86_64/",
      "pattern": r'mysql-community-server-(\d[^"]*).el7.x86_64.rpm'},
      {"url": "https://repo.mysql.com/yum/mysql-8.0-community/el/7/x86_64/",
      "pattern": r'mysql-community-server-(\d[^"]*).el7.x86_64.rpm'},
    ])

  generate_versions_file("mysql.el8.txt",
    [
      {"url": "https://repo.mysql.com/yum/mysql-8.0-community/el/8/x86_64/",
      "pattern": r'mysql-community-server-(\d[^"]*).el8.x86_64.rpm'},
    ])

  generate_versions_file("mysql.el9.txt",
    [
      {"url": "https://repo.mysql.com/yum/mysql-8.0-community/el/9/x86_64/",
      "pattern": r'mysql-community-server-(\d[^"]*).el9.x86_64.rpm'},
    ])

  generate_versions_file("mysql.el8.aarch64.txt",
    [
      {"url": "https://repo.mysql.com/yum/mysql-8.0-community/el/8/aarch64/",
      "pattern": r'mysql-community-server-(\d[^"]*).el8.aarch64.rpm'},
    ])

  generate_versions_file("mysql.el9.aarch64.txt",
    [
      {"url": "https://repo.mysql.com/yum/mysql-8.0-community/el/9/aarch64/",
      "pattern": r'mysql-community-server-(\d[^"]*).el9.aarch64.rpm'},
    ])



  #percona-postgresql-common-230-1.el8.noarch
  generate_versions_file("ppg.el7.txt",
    [
      {"url": "http://repo.percona.com/ppg-11/yum/release/7/RPMS/x86_64",
      "pattern": r'percona-postgresql\d+-([0-9.-]+)\.el\d+.x86_64.rpm'},
       {"url": "http://repo.percona.com/ppg-12/yum/release/7/RPMS/x86_64",
      "pattern": r'percona-postgresql\d+-([0-9.-]+)\.el\d+.x86_64.rpm'},
       {"url": "http://repo.percona.com/ppg-13/yum/release/7/RPMS/x86_64",
      "pattern": r'percona-postgresql\d+-([0-9.-]+)\.el\d+.x86_64.rpm'},
       {"url": "http://repo.percona.com/ppg-14/yum/release/7/RPMS/x86_64",
      "pattern": r'percona-postgresql\d+-([0-9.-]+)\.el\d+.x86_64.rpm'},
       {"url": "http://repo.percona.com/ppg-15/yum/release/7/RPMS/x86_64",
      "pattern": r'percona-postgresql\d+-([0-9.-]+)\.el\d+.x86_64.rpm'},
       {"url": "http://repo.percona.com/ppg-16/yum/release/7/RPMS/x86_64",
      "pattern": r'percona-postgresql\d+-([0-9.-]+)\.el\d+.x86_64.rpm'},
     ])
  generate_versions_file("ppg.el8.txt",
    [
      {"url": "http://repo.percona.com/ppg-11/yum/release/8/RPMS/x86_64",
      "pattern": r'percona-postgresql\d+-([0-9.-]+)\.el\d+.x86_64.rpm'},
       {"url": "http://repo.percona.com/ppg-12/yum/release/8/RPMS/x86_64",
      "pattern": r'percona-postgresql\d+-([0-9.-]+)\.el\d+.x86_64.rpm'},
       {"url": "http://repo.percona.com/ppg-13/yum/release/8/RPMS/x86_64",
      "pattern": r'percona-postgresql\d+-([0-9.-]+)\.el\d+.x86_64.rpm'},
       {"url": "http://repo.percona.com/ppg-14/yum/release/8/RPMS/x86_64",
      "pattern": r'percona-postgresql\d+-([0-9.-]+)\.el\d+.x86_64.rpm'},
       {"url": "http://repo.percona.com/ppg-15/yum/release/8/RPMS/x86_64",
      "pattern": r'percona-postgresql\d+-([0-9.-]+)\.el\d+.x86_64.rpm'},
       {"url": "http://repo.percona.com/ppg-16/yum/release/8/RPMS/x86_64",
      "pattern": r'percona-postgresql\d+-([0-9.-]+)\.el\d+.x86_64.rpm'},
     ])

  generate_versions_file("pg.el7.txt",
    [
       {"url": "https://download.postgresql.org/pub/repos/yum/12/redhat/rhel-7-x86_64",
      "pattern": r'postgresql\d+-server-([0-9.-]+)PGDG\.rhel\d+.x86_64.rpm'},
       {"url": "https://download.postgresql.org/pub/repos/yum/13/redhat/rhel-7-x86_64",
      "pattern": r'postgresql\d+-server-([0-9.-]+)PGDG\.rhel\d+.x86_64.rpm'},
       {"url": "https://download.postgresql.org/pub/repos/yum/14/redhat/rhel-7-x86_64",
      "pattern": r'postgresql\d+-server-([0-9.-]+)PGDG\.rhel\d+.x86_64.rpm'},
       {"url": "https://download.postgresql.org/pub/repos/yum/15/redhat/rhel-7-x86_64",
      "pattern": r'postgresql\d+-server-([0-9.-]+)PGDG\.rhel\d+.x86_64.rpm'},
     ])
     
  generate_versions_file("pg.el8.txt",
    [
       {"url": "https://download.postgresql.org/pub/repos/yum/12/redhat/rhel-8-x86_64",
      "pattern": r'postgresql\d+-server-([0-9.-]+)PGDG\.rhel\d+.x86_64.rpm'},
       {"url": "https://download.postgresql.org/pub/repos/yum/13/redhat/rhel-8-x86_64",
      "pattern": r'postgresql\d+-server-([0-9.-]+)PGDG\.rhel\d+.x86_64.rpm'},
       {"url": "https://download.postgresql.org/pub/repos/yum/14/redhat/rhel-8-x86_64",
      "pattern": r'postgresql\d+-server-([0-9.-]+)PGDG\.rhel\d+.x86_64.rpm'},
       {"url": "https://download.postgresql.org/pub/repos/yum/15/redhat/rhel-8-x86_64",
      "pattern": r'postgresql\d+-server-([0-9.-]+)PGDG\.rhel\d+.x86_64.rpm'},
       {"url": "https://download.postgresql.org/pub/repos/yum/16/redhat/rhel-8-x86_64",
      "pattern": r'postgresql\d+-server-([0-9.-]+)PGDG\.rhel\d+.x86_64.rpm'},
     ])

  generate_versions_file("pg.el9.txt",
    [
       {"url": "https://download.postgresql.org/pub/repos/yum/15/redhat/rhel-9-x86_64",
      "pattern": r'postgresql\d+-server-([0-9.-]+)PGDG\.rhel\d+.x86_64.rpm'},
       {"url": "https://download.postgresql.org/pub/repos/yum/16/redhat/rhel-9-x86_64",
      "pattern": r'postgresql\d+-server-([0-9.-]+)PGDG\.rhel\d+.x86_64.rpm'},
     ])

  for osver in ("el7","el8","el9"):
    generate_versions_file("xtrabackup.{osver}.txt".format(osver=osver),
      [
        {"url": "https://repo.percona.com/percona/yum/release/{osver}/RPMS/x86_64/".format(osver=osver.replace("el","")),
         "pattern": r"percona-xtrabackup(?:-[0-9]+)-([0-9.-]*).{osver}.x86_64.rpm".format(osver=osver)}
      ])
 
  for op in ("percona/percona-xtradb-cluster-operator",
             "percona/percona-postgresql-operator",
             "percona/percona-server-mongodb-operator",
             "percona/percona-server-mysql-operator"):
    save_github_tags_to_sqlite(op, "k8s_operators_version")

  for osver in ("el7","el8","el9"):
    save_percona_server_versions_to_sqlite(osver)
    save_percona_xtradb_cluster_versions_to_sqlite(osver)
    save_mysql_server_versions_to_sqlite(osver)
    save_percona_server_mongodb_versions_to_sqlite(osver)
    save_percona_postgresql_versions_to_sqlite(osver)
    save_postgresql_versions_to_sqlite(osver)
    save_mariadb_versions_to_sqlite(osver)
    save_xtrabackup_versions_to_sqlite(osver)
    save_percona_backup_mongodb_versions_to_sqlite(osver)


