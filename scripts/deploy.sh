#!/bin/bash

set -e

# check if VM is already running
if ! limactl list | grep -q "debian-k3s.*Running"
then
    # provision VM
    echo "provisioning VM"
    limactl start --tty=false --name debian-k3s ./deploy/vm/debian-k3s.yaml

    # trust k3s-generated CA
    echo "trusting k3s-generated CA"
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /Users/brandon/.lima/debian-k3s/copied-from-guest/server-ca.crt

    # append exposed external services from ingress to /etc/hosts if not already present
    echo "adding to /etc/hosts"
    HOSTS_ENTRY="127.0.0.1 grafana.debian-k3s docker-registry.debian-k3s tempo.debian-k3s prometheus.debian-k3s linkerd-viz.debian-k3s graphite.debian-k3s chromium.debian-k3s pdf-generator.debian-k3s"
    if ! grep -qF "$HOSTS_ENTRY" /etc/hosts; then
        echo "$HOSTS_ENTRY" | sudo tee -a /etc/hosts
    fi
fi

# copy certs for cert-manager
mkdir -p ./deploy/kustomize/cert-manager/certs
cp ~/.lima/debian-k3s/copied-from-guest/server-ca.crt ./deploy/kustomize/cert-manager/certs/server-ca.crt
cp ~/.lima/debian-k3s/copied-from-guest/server-ca.key ./deploy/kustomize/cert-manager/certs/server-ca.key

# workaround traefik needing v1.1.1 gateway-api and linkerd needing v0.8.1 gateway-api crds
if ! kubectl get crd gatewayclasses.gateway.networking.k8s.io -o json | jq -e '.status.storedVersions | contains(["v1beta1"])' >/dev/null
then
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v0.8.1/experimental-install.yaml
    kubectl wait --for condition=established --timeout=60s crd/httproutes.gateway.networking.k8s.io
    kubectl wait --for condition=available --timeout=60s deployment/gateway-api-admission-server -n gateway-system

    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.1/experimental-install.yaml
    kubectl wait --for condition=established --timeout=60s crd/backendlbpolicies.gateway.networking.k8s.io
fi

## metrics-server
echo "deploying metrics-server"
kustomize build ./deploy/kustomize/metrics-server | envsubst | kubectl apply -f -

## cert-manager
echo "deploying cert-manager"
kustomize build ./deploy/kustomize/cert-manager | envsubst | kubectl apply -f -
echo "Waiting for cert-manager deployments to be available..."
kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=120s
kubectl wait --for=condition=available deployment/cert-manager-webhook -n cert-manager --timeout=120s
kubectl wait --for=condition=available deployment/cert-manager-cainjector -n cert-manager --timeout=120s
echo "Waiting for cert-manager webhook to be ready..."
kubectl wait --for=condition=ready pod -l app=webhook -n cert-manager --timeout=120s
echo "Waiting for cert-manager CRDs to be established..."
kubectl wait --for=condition=established --timeout=120s crd/clusterissuers.cert-manager.io
kubectl wait --for=condition=established --timeout=120s crd/certificates.cert-manager.io
kubectl wait --for=condition=established --timeout=120s crd/certificaterequests.cert-manager.io

## cert-manager-ca
echo "deploying cert-manager-ca"
kustomize build ./deploy/kustomize/cert-manager-ca | envsubst | kubectl apply -f -
echo "Waiting for ClusterIssuer to be ready..."
kubectl wait --for=condition=ready clusterissuer/debian-k3s-ca-issuer --timeout=60s

## trust-manager
echo "deploying trust-manager"
kustomize build ./deploy/kustomize/trust-manager | envsubst | kubectl apply -f -
echo "Waiting for trust-manager deployments to be available..."
kubectl wait --for=condition=available deployment/trust-manager -n trust-manager --timeout=120s
echo "Waiting for trust-manager webhook to be ready..."
kubectl wait --for=condition=ready pod -l app=trust-manager -n trust-manager --timeout=120s
echo "Waiting for trust-manager CRDs to be established..."
kubectl wait --for=condition=established --timeout=120s crd/bundles.trust.cert-manager.io

## linkerd
echo "deploying linkerd"
kustomize build ./deploy/kustomize/linkerd | envsubst | kubectl apply -f -
# TODO: wait for linkerd to be ready

## traefik
echo "deploying traefik"
kustomize build ./deploy/kustomize/traefik | envsubst | kubectl apply -f -
echo "Waiting for traefik to be ready..."
kubectl wait --for=condition=available deployment/traefik -n traefik --timeout=120s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n traefik --timeout=120s

## coredns
echo "deploying coredns"
kustomize build ./deploy/kustomize/coredns | envsubst | kubectl apply -f -

## monitoring
echo "deploying monitoring"
kustomize build ./deploy/kustomize/monitoring | envsubst | kubectl apply -f -

## chromium
echo "deploying chromium"
kustomize build ./deploy/kustomize/chromium | envsubst | kubectl apply -f -

## pdf-generator
echo "deploying pdf-generator"
kustomize build ./deploy/kustomize/pdf-generator | envsubst | kubectl apply -f -

## traefik-routes
echo "deploying traefik-routes"
kustomize build ./deploy/kustomize/traefik-routes | envsubst | kubectl apply -f -

# patch coredns for external cluster pulling from docker-registry in the cluster
echo "reconfiguring coredns"
kubectl wait --for=condition=available --timeout=300s deployment/traefik -n traefik
export TRAEFIK_IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.spec.clusterIP}')
envsubst < deploy/kustomize/coredns/config.yaml | kubectl apply -f -
