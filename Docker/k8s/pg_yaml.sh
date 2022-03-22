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
kind: Service
metadata:
  name: $SERVER_NAME
spec:
  selector:
    name: $SERVER_NAME
  clusterIP: None
  ports:
  - name: pg
    port: 5432
    targetPort: 5432
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
kind: Pod
metadata:
  name: $SERVER_NAME
  labels:
    name: $SERVER_NAME
spec:
  containers:
  - name: pg
    env:
    - name: POSTGRES_PASSWORD
      value: secret
    image: $PG_IMG
    imagePullPolicy: IfNotPresent
    volumeMounts:
    - mountPath: /var/lib/postgresql/data
      name: datadir
    - mountPath: /docker-entrypoint-initdb.d
      name: initdir
  initContainers:
  - name: pagila-init
    image: curlimages/curl
    imagePullPolicy: IfNotPresent
    command:
      - sh
      - "-c"
      - |
        /bin/sh <<'EOF'
        [ -f /docker-entrypoint-initdb.d/pagila.sql ] || curl -sL https://github.com/devrimgunduz/pagila/raw/master/pagila-schema.sql https://github.com/devrimgunduz/pagila/raw/master/pagila-data.sql > /docker-entrypoint-initdb.d/pagila.sql
        cat > /docker-entrypoint-initdb.d/pg_hba.sh <<'EO_HBA'
        #!/bin/sh
        sed -i -e '\$ a host replication all all md5' /var/lib/postgresql/data/pg_hba.conf
        psql -U postgres -d postgres -c "ALTER SYSTEM SET wal_level = 'hot_standby';" -c "SELECT pg_reload_conf();"
        EO_HBA
        chmod +x /docker-entrypoint-initdb.d/pg_hba.sh
        EOF
    volumeMounts:
    - mountPath: /var/lib/postgresql/data
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

