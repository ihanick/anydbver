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
    image: $MYSQL_IMG
    imagePullPolicy: IfNotPresent
    command:
      - sh
      - "-c"
      - |
        /bin/bash <<'EOF'
        cat > /docker-entrypoint-initdb.d/root.sql <<CREATE_ROOT_EOF
        CREATE USER root@'%' IDENTIFIED BY '\$MYSQL_ROOT_PASSWORD';
        GRANT ALL PRIVILEGES ON *.* TO root@'%' WITH GRANT OPTION;
        ALTER USER root@localhost IDENTIFIED BY '\$MYSQL_ROOT_PASSWORD';
        INSTALL PLUGIN clone SONAME 'mysql_clone.so';
        SET GLOBAL clone_valid_donor_list = '$SRC_NAME:3306';
        CLONE INSTANCE FROM 'root'@'$SRC_NAME':3306 IDENTIFIED BY '\$MYSQL_ROOT_PASSWORD';
        CREATE_ROOT_EOF

        cat > /docker-entrypoint-initdb.d/slave.sql <<SLAVE_EOF
        CHANGE MASTER TO MASTER_USER='root',MASTER_PASSWORD='\$MYSQL_ROOT_PASSWORD', MASTER_HOST='$SRC_NAME', MASTER_AUTO_POSITION=1;
        SHUTDOWN;
        SLAVE_EOF

        mysqld -u mysql --initialize-insecure
        echo "Empty database is created"
        until mysql -u root -p"\$MYSQL_ROOT_PASSWORD" -h $SRC_NAME --silent --connect-timeout=30 --wait -e "SELECT 1;" > /dev/null 2>&1 ; do sleep 5 ; done
        echo "Master Started"
        mysqld -u mysql --init-file=/docker-entrypoint-initdb.d/root.sql
        echo "Setup slave"
        mysqld -u mysql --init-file=/docker-entrypoint-initdb.d/slave.sql --server-id=$SERVER_ID --log-bin=mysqld-bin --report_host=$SERVER_NAME --log-slave-updates --enforce_gtid_consistency=ON --gtid_mode=ON
        echo "MySQL initialized"
        rm /docker-entrypoint-initdb.d/root.sql /docker-entrypoint-initdb.d/slave.sql
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

