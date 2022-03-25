#!/bin/bash
OP=percona-postgresql-operator
URL="https://github.com/percona/${OP}.git"
VER="1.1.0"
NS="pgo"
BASEDIR="$(dirname "$0")"
DEST="${BASEDIR}/../data/k8s"

if [[ "$VER" != "latest" || "$VER" != "main" ]] ; then
  VER="v$VER"
fi

if [[ "$OP" == "percona-postgresql-operator" ]] ; then
  NS="pgo"
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
  echo "kubectl -n $PGO exec -it cluster1-dccb948b6-d7bkg -- env PSQL_HISTORY=/tmp/.psql_history psql -U postgres"
}



main() {
  fetch_files
  if [[ "$OP" == "percona-postgresql-operator" ]] ; then
    run_percona_pg_operator
  fi
}


main
