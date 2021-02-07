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
* Export bash variable `LOCAL_REPO_CACHE=1`, add to .bashrc if needed

## LXD cache for base OS image
* Export variable
```
export ANYDBVER_CACHE_OS_IMG=1
```
* During first deployment the image is cached as ${USER}-$OS-empty
* During next deployments for the same OS the cache image speedup startup
