# anydbver - Docker/Podman version

Andbver with LXD allows to start containers and install sofware similar to bare-metal production environment.
This branch is intended to use hub.docker.com images as possible without or with minimal modifications.

The replication/clusters setup is configured with sidecar/init containers.

## MySQL and Percona Server
* Use clone and GTID

```
./anydbver deploy ps gtid world node1 ps gtid master:node0
```

* Use clone and binary log file+position

```
./anydbver deploy ps world node1 ps master:node0
```

* Use GTID and offline filesystem copy (works with 5.6, 5.7, 8.0)

```
./anydbver deploy ps:5.6 gtid world node1 ps:5.6 snapshot gtid master:node0
```

* Arguments
```
./anydbver deploy \
  node0 mysql gtid args:--innodb-log-file-size=512M \
  node1 gtid mysql args:'--innodb-log-file-size=1G --innodb-flush-log-at-trx-commit=0'
```

Use `mysql` instead of `ps` for mysql/mysql-server image.

## Postgresql

* Pagila sample database and physical replication secondary created by offline filesystem copy
```
./anydbver deploy node0 pg pagila node1 pg snapshot master:node0
```

* Pagila sample database and physical replication secondary created by `pg_basebackup`
```
./anydbver deploy node0 pg pagila node1 pg master:node0
`
Destroy:
```
./anydbver destroy
```
