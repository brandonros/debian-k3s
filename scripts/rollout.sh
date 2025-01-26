#!/bin/bash

set -e

# workaround traefik needing v1.1.1 gateway-api and linkerd needing v0.8.1 gateway-api crds
if ! kubectl get crd gatewayclasses.gateway.networking.k8s.io -o json | jq -e '.status.storedVersions | contains(["v1beta1"])' >/dev/null
then
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v0.8.1/experimental-install.yaml
    kubectl wait --for condition=established --timeout=60s crd/httproutes.gateway.networking.k8s.io
    kubectl wait --for condition=available --timeout=60s deployment/gateway-api-admission-server -n gateway-system
    kubectl wait --for=condition=ready pod -l name=gateway-api-admission-server -n gateway-system --timeout=120s

    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.1/experimental-install.yaml
    kubectl wait --for condition=established --timeout=60s crd/backendlbpolicies.gateway.networking.k8s.io
fi

## metrics-server
echo "deploying metrics-server"
kustomize build ./deploy/kustomize/metrics-server | envsubst | kubectl apply -f -
# TODO: wait for metrics-server to be ready

## cert-manager
echo "deploying cert-manager"
kustomize build ./deploy/kustomize/cert-manager | envsubst | kubectl apply -f -
echo "Waiting for cert-manager deployments to be created..."
kubectl wait --for=create deployment/cert-manager -n cert-manager --timeout=120s
kubectl wait --for=create deployment/cert-manager-webhook -n cert-manager --timeout=120s
kubectl wait --for=create deployment/cert-manager-cainjector -n cert-manager --timeout=120s
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
echo "Waiting for cert-manager CA secret to be created..."
kubectl wait --for=create secret/debian-k3s-tls -n cert-manager --timeout=60s

## cert-manager-ca
echo "deploying cert-manager-ca"
kustomize build ./deploy/kustomize/cert-manager-ca | envsubst | kubectl apply -f -
echo "Waiting for ClusterIssuer to be ready..."
kubectl wait --for=condition=ready clusterissuer/debian-k3s-ca-issuer --timeout=60s

## trust-manager
echo "deploying trust-manager"
kustomize build ./deploy/kustomize/trust-manager | envsubst | kubectl apply -f -
echo "Waiting for trust-manager deployments to be created..."
kubectl wait --for=create deployment/trust-manager -n trust-manager --timeout=120s
echo "Waiting for trust-manager deployments to be available..."
kubectl wait --for=condition=available deployment/trust-manager -n trust-manager --timeout=120s
echo "Waiting for trust-manager webhook to be ready..."
kubectl wait --for=condition=ready pod -l app=trust-manager -n trust-manager --timeout=120s
echo "Waiting for trust-manager CRDs to be established..."
kubectl wait --for=condition=established --timeout=120s crd/bundles.trust.cert-manager.io
 
## traefik
echo "deploying traefik"
kustomize build ./deploy/kustomize/traefik | envsubst | kubectl apply -f -
echo "Waiting for traefik deployments to be created..."
kubectl wait --for=create deployment/traefik -n traefik --timeout=120s
echo "Waiting for traefik to be ready..."
kubectl wait --for=condition=available deployment/traefik -n traefik --timeout=120s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n traefik --timeout=120s
echo "Waiting for traefik CA secret to be created..."
kubectl wait --for=create secret/debian-k3s-gateway-tls -n traefik --timeout=60s

## linkerd
echo "deploying linkerd"
kustomize build ./deploy/kustomize/linkerd | envsubst | kubectl apply -f -
# TODO: wait for linkerd to be ready

## monitoring
echo "deploying monitoring"
kustomize build ./deploy/kustomize/monitoring | envsubst | kubectl apply -f -
# TODO: wait for monitoring to be ready

## pdf-generator
echo "deploying pdf-generator"
kustomize build ./deploy/kustomize/pdf-generator | envsubst | kubectl apply -f -
kubectl rollout status deployment pdf-generator -n pdf-generator --watch

## linkerd-control-plane
echo "deploying linkerd-control-plane"
kustomize build ./deploy/kustomize/linkerd-control-plane | envsubst | kubectl apply -f -
# TODO: wait for linkerd-control-plane to be ready

## traefik-routes
echo "deploying traefik-routes"
kustomize build ./deploy/kustomize/traefik-routes | envsubst | kubectl apply -f -
# TODO: wait for traefik-routes to be ready