cat <<EOYAML | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: datadir-$SERVER_NAME
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 6G
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: initdir-$SERVER_NAME
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 6G
---
apiVersion: v1
kind: Service
metadata:
  name: $SERVER_NAME
spec:
  selector:
    name: $SERVER_NAME
  clusterIP: None
  ports:
  - name: mysql
    port: 3306
    targetPort: 3306
---
apiVersion: v1
kind: Pod
metadata:
  name: $SERVER_NAME
  labels:
    name: $SERVER_NAME
spec:
  containers:
  - name: mysql
    env:
    - name: MYSQL_ROOT_PASSWORD
      value: secret
    - name: MYSQL_ROOT_HOST
      value: "%"
    image: $MYSQL_IMG
    imagePullPolicy: IfNotPresent
    args:
      - --server-id=$SERVER_ID
      - --log-bin=mysqld-bin
      - --report_host=$SERVER_NAME
      - --log-slave-updates
      - --enforce_gtid_consistency=ON
      - --gtid_mode=ON
    volumeMounts:
    - mountPath: /var/lib/mysql
      name: datadir
    - mountPath: /docker-entrypoint-initdb.d
      name: initdir
  initContainers:
  - name: worlddb
    env:
    - name: MYSQL_ROOT_PASSWORD
      value: secret
    image: curlimages/curl
    imagePullPolicy: IfNotPresent
    command:
      - sh
      - "-c"
      - |
        /bin/sh <<'EOF'
        cat > /docker-entrypoint-initdb.d/root.sql <<CREATE_ROOT_EOF
        INSTALL PLUGIN clone SONAME 'mysql_clone.so';
        CREATE_ROOT_EOF
        [ -f /docker-entrypoint-initdb.d/world.sql ] || curl -sL https://downloads.mysql.com/docs/world-db.tar.gz |tar -C /docker-entrypoint-initdb.d/ --strip-components 1 -xz
        EOF
    volumeMounts:
    - mountPath: /var/lib/mysql
      name: datadir
    - mountPath: /docker-entrypoint-initdb.d
      name: initdir

  restartPolicy: Always
  volumes:
  - name: datadir
    persistentVolumeClaim:
      claimName: datadir-$SERVER_NAME
  - name: initdir
    persistentVolumeClaim:
      claimName: initdir-$SERVER_NAME
EOYAML

