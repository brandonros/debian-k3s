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
    HOSTS_ENTRY="127.0.0.1 chess-engine-api.debian-k3s grafana.debian-k3s docker-registry.debian-k3s tempo.debian-k3s prometheus.debian-k3s linkerd-viz.debian-k3s backstage.debian-k3s"
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

# deploy
export HOST_PATH="/mnt/chess_engine_api"
export NGROK_API_KEY=${NGROK_API_KEY}
export NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN}
export NGROK_HOST=${NGROK_HOST}
kustomize build ./deploy/kustomize | envsubst | kubectl apply -f -

# patch coredns for external cluster pulling from docker-registry in the cluster
echo "reconfiguring coredns"
kubectl wait --for=condition=available --timeout=300s deployment/traefik -n traefik
export TRAEFIK_IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.spec.clusterIP}')
envsubst < deploy/kustomize/coredns/config.yaml | kubectl apply -f -

# check if we need to build the application
if ! curl -s https://docker-registry.debian-k3s/v2/_catalog | jq -e '.repositories | contains(["chess-engine-api"])' >/dev/null; then
    echo "chess-engine-api image not found, building application"

    # create build job
    export TIMESTAMP=$(date +%s)
    export JOB_NAME="kaniko-build-${TIMESTAMP}"
    export IMAGE_DESTINATION="docker-registry.docker-registry.svc.cluster.local:5000/chess-engine-api:latest"
    export PVC_NAME="cicd-pvc"
    export DOCKERFILE="Dockerfile"
    export PVC_MOUNT_PATH="/workspace"
    envsubst < ./deploy/kustomize/cicd/build-job.yaml | kubectl apply -f -

    # wait for job to complete
    echo "waiting for kaniko build job to complete"
    kubectl wait --for=condition=complete --timeout=300s job/${JOB_NAME} -n cicd
fi
