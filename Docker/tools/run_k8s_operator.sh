#!/bin/bash
OP="$1"
VER="$2"
OP="${OP:-percona-postgresql-operator}"
URL="https://github.com/percona/${OP}.git"
VER="${VER:-1.1.0}"
NS="pgo"
BASEDIR="$(dirname "$0")"
DEST="${BASEDIR}/../data/k8s"

if [[ "$VER" == "latest" ]] ; then
  VER=main
elif [[ "$VER" != "main" ]] ; then
  VER="v$VER"
fi

if [[ "$OP" == "percona-postgresql-operator" ]] ; then
  NS="pgo"
elif [[ "$OP" == "percona-xtradb-cluster-operator" ]] ; then
  NS="pxc"
elif [[ "$OP" == "percona-server-mongodb-operator" ]] ; then
  NS="psmdb"
fi



fetch_files() {
  mkdir -p "$DEST"
  cd "$DEST"
  if [[ -d "$DEST/$OP" ]] ; then
    cd "$OP"
    git pull
    git checkout "$VER" 
  else
    git clone -b "$VER" "$URL"
  cd "$OP"
  fi
  until kubectl wait --for=condition=ready -n kube-system pod -l k8s-app=kube-dns &>/dev/null;do sleep 2;done
  kubectl create namespace "$NS"
}

run_percona_pg_operator() {
  kubectl apply -n "$NS" -f ./deploy/operator.yaml;
  until kubectl wait --for=condition=ready pod --namespace "$NS" -l name=postgres-operator &>/dev/null;do sleep 2;done
  sleep 30
  kubectl apply -n "$NS" -f ./deploy/cr.yaml;
  until kubectl wait --for=condition=ready --namespace "$NS" pod -l name=cluster1 &>/dev/null;do sleep 2;done

  info_percona_pg_operator
}

info_percona_pg_operator() {
  echo "kubectl -n "$NS" exec -it cluster1-dccb948b6-d7bkg -- env PSQL_HISTORY=/tmp/.psql_history psql -U postgres"
}

run_percona_pxc_operator() {
  kubectl apply -n "$NS" -f ./deploy/bundle.yaml;
  until
    kubectl -n "$NS" wait --for=condition=ready pod -l name="$OP" &>/dev/null ||
    kubectl -n "$NS" wait --for=condition=ready pod -l control-plane="$OP" &>/dev/null ||
    kubectl -n "$NS" wait --for=condition=ready pod -l app.kubernetes.io/name="$OP" &>/dev/null ;
  do sleep 2;done
  kubectl apply -n "$NS" -f ./deploy/cr.yaml;
  echo "Waiting for PXC node startup"
  until kubectl -n "$NS" wait --for=condition=ready pod -l app.kubernetes.io/instance=cluster1,app.kubernetes.io/component=pxc &>/dev/null;do sleep 2;done
  PASS=$(kubectl -n pxc get secrets my-cluster-secrets -o go-template="{{ .data.root | base64decode }}")
  info_percona_pxc_operator
}

info_percona_pxc_operator() {
  echo "kubectl -n "$NS" exec -it cluster1-pxc-0 -c pxc -- env LANG=C.utf8 MYSQL_HISTFILE=/tmp/.mysql_history mysql -uroot -p\"$PASS\""
}

run_percona_mongo_operator() {
  kubectl apply -n "$NS" -f ./deploy/bundle.yaml;
  until
    kubectl -n "$NS" wait --for=condition=ready pod -l name="$OP" &>/dev/null ||
    kubectl -n "$NS" wait --for=condition=ready pod -l control-plane="$OP" &>/dev/null ||
    kubectl -n "$NS" wait --for=condition=ready pod -l app.kubernetes.io/name="$OP" &>/dev/null ;
  do sleep 2;done
  kubectl apply -n "$NS" -f ./deploy/cr.yaml;
  echo "Waiting for MongoDB startup"
  until kubectl -n "$NS" wait --for=condition=ready pod -l app.kubernetes.io/instance=my-cluster-name,app.kubernetes.io/component=mongod &>/dev/null;do sleep 2;done
  info_percona_mongo_operator
}

info_percona_mongo_operator() {
  PASS=$(kubectl -n psmdb get secrets my-cluster-name-secrets -o go-template='{{ .data.MONGODB_CLUSTER_ADMIN_PASSWORD | base64decode }}')
  echo "kubectl -n "$NS" exec -it my-cluster-name-rs0-0 -- env LANG=C.utf8 HOME=/tmp mongo -u clusterAdmin --password=\"$PASS\" localhost/admin"
  PASS=$(kubectl -n psmdb get secrets my-cluster-name-secrets -o go-template='{{ .data.MONGODB_USER_ADMIN_PASSWORD | base64decode }}')
  echo "kubectl -n "$NS" exec -it my-cluster-name-rs0-0 -- env LANG=C.utf8 HOME=/tmp mongo -u userAdmin --password=\"$PASS\" localhost/admin"
}



main() {
  fetch_files
  if [[ "$OP" == "percona-postgresql-operator" ]] ; then
    run_percona_pg_operator
  elif [[ "$OP" == "percona-xtradb-cluster-operator" ]] ; then
    run_percona_pxc_operator
  elif [[ "$OP" == "percona-server-mongodb-operator" ]] ; then
    run_percona_mongo_operator
  fi
}


main
