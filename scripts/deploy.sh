#!/bin/bash

set -e

SCRIPT=$(readlink -f "$0")
SCRIPT_PATH=$(dirname "$SCRIPT")

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
    HOSTS_ENTRY="127.0.0.1 grafana.debian-k3s docker-registry.debian-k3s tempo.debian-k3s prometheus.debian-k3s linkerd-viz.debian-k3s graphite.debian-k3s pdf-generator.debian-k3s"
    if ! grep -qF "$HOSTS_ENTRY" /etc/hosts; then
        echo "$HOSTS_ENTRY" | sudo tee -a /etc/hosts
    fi
fi

# copy certs for cert-manager
mkdir -p ./deploy/kustomize/cert-manager/certs
cp ~/.lima/debian-k3s/copied-from-guest/server-ca.crt ./deploy/kustomize/cert-manager/certs/server-ca.crt
cp ~/.lima/debian-k3s/copied-from-guest/server-ca.key ./deploy/kustomize/cert-manager/certs/server-ca.key

$SCRIPT_PATH/rollout.sh
