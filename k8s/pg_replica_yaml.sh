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
  - name: pg-basebackup
    image: $PG_IMG
    imagePullPolicy: IfNotPresent
    command:
      - sh
      - "-c"
      - |
        /bin/sh <<'EOF'
        until PGPASSWORD=secret psql -h "$SRC" -U postgres -d postgres -c "SELECT 1;" > /dev/null 2>&1 ; do sleep 5 ; done
        PGPASSWORD=secret pg_basebackup -h "$SRC" -U postgres -D /var/lib/postgresql/data -Fp -Xs -P -R
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

