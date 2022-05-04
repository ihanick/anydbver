#!/bin/bash
PORT="${1:-443}"
SERVICE="$2"
DOMAIN="$3"
if ! kubectl get namespaces -o go-template='{{ .metadata.name }}' ingress-nginx ; then
  export HELM_CACHE_HOME="$PWD/data/helm/cache" HELM_CONFIG_HOME="$PWD/data/helm/config" HELM_DATA_HOME="$PWD/data/helm/data"
  helm repo add nginx-stable https://helm.nginx.com/stable
  helm repo update
  helm install nginx-ingress --namespace ingress-nginx --create-namespace --set controller.service.httpPort.port=80 --set controller.service.httpsPort.enable=true nginx-stable/nginx-ingress
fi

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-$SERVICE
  annotations:
    nginx.org/ssl-services: "$SERVICE"
spec:
  tls:
  - hosts:
    - $SERVICE.$DOMAIN
    secretName: tls-minio
  rules:
  - host: $SERVICE.$DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $SERVICE
            port:
              number: 443
  ingressClassName: nginx
EOF
