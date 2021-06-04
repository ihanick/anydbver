# anydbver - Docker/Podman version

Andbver with LXD allows to start containers and install sofware similar to bare-metal production environment.
This branch is intended to use hub.docker.com images as possible without or with minimal modifications.

The replication/clusters setup is configured with sidecar/init containers.


```
RUN=1 GTID=0 MYSQL_IMG=percona/percona-server:latest bash -xe create_replication.sh
```

Destroy:
```
DESTROY=1 bash -xe create_replication.sh
```
