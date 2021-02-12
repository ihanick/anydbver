# Advanced usage: caching

* Install nginx
* change nginx.conf
```
http {
# ....
    proxy_cache_path /mnt/data/nginx-cache levels=1:2 keys_zone=my_cache:10m max_size=10g inactive=10080m use_temp_path=off;

    server {
        listen       80;
        server_name  repo.percona.com.local;
        root         /usr/share/nginx/html;


        location / {
            proxy_cache my_cache;
            proxy_pass http://repo.percona.com;
        }

        error_page 404 /404.html;
            location = /40x.html {
        }

        error_page 500 502 503 504 /50x.html;
            location = /50x.html {
        }
    }

    server {
        listen       80;
        server_name  downloads.mariadb.com.local;
        root         /usr/share/nginx/html;


        location / {
            proxy_cache my_cache;
            proxy_pass https://downloads.mariadb.com;
            proxy_set_header Host downloads.mariadb.com;
            proxy_ssl_server_name on;
        }
    }
```
* Put the record in /etc/hosts on LXD server
```
ip_of_nginx_server repo.percona.com.local
ip_of_nginx_server downloads.mariadb.com.local

```
* Export bash variable `export LOCAL_REPO_CACHE=1`, add to .bashrc if needed

## LXD cache for base OS image
* Export variable
```
export ANYDBVER_CACHE_OS_IMG=1
```
* During first deployment the image is cached as ${USER}-$OS-empty
* During next deployments for the same OS the cache image speedup startup

## Cache for existing package installations
* Create a cache from image with "install" keyword
```
./anydbver deploy install ps:8.0.22 cache:ps-8.0.22
```
* Use same syntax for deployment
```
./anydbver deploy \
          install ps:8.0.22 cache:ps-8.0.22 \
  node1   install ps:8.0.22 cache:ps-8.0.22 \
  node2   install ps:8.0.22 cache:ps-8.0.22 \
  default ps:8.0.22 \
  node1 ps:8.0.22 master:default \
  node2 ps:8.0.22 master:default
```

```
./anydbver deploy install k3s cache:k8s
./anydbver deploy \
        install k3s cache:k8s \
  node1 install k3s cache:k8s \
  node2 install k3s cache:k8s \
  node3 install k3s cache:k8s \
  default k3s \
  node1 k3s-master:default \
  node2 k3s-master:default \
  node3 k3s-master:default \
  default k8s-pmm k8s-pxc
```

```
./anydbver deploy install pg:13 patroni cache:pg13-patroni
./anydbver deploy \
          install pg:13 patroni cache:pg13-patroni \
  node1   install pg:13 patroni cache:pg13-patroni \
  node2   install pg:13 patroni cache:pg13-patroni \
  default pg:13 patroni \
  node1   pg:13 master:default patroni etcd-ip:default \
  node2   pg:13 master:default patroni etcd-ip:default
```

* Currently mysql/percona-server/MariaDB/Postgres/Patroni/PMM/Samba/k3s support install keyword
