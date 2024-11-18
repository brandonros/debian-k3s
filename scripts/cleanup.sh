#!/bin/bash

set -e

# stop and delete VM
limactl stop debian-k3s || true
limactl delete debian-k3s || true

# delete k3s-server-ca certificates
CERTS=$(security find-certificate -a -c "k3s-server-ca" | grep "alis" | cut -d'"' -f4)
if [ -z "$CERTS" ]; then
    echo "No k3s-server-ca certificates found"
    exit 0
fi
for cert in $CERTS; do
    echo "Found certificate: $cert"
    echo "Deleting..."
     if sudo security delete-certificate -c "$cert"; then
        echo "Successfully deleted $cert"
    else
        echo "Failed to delete $cert"
    fi
done

# remove entries from /etc/hosts
HOSTS_ENTRY="127.0.0.1 chess-engine-api.debian-k3s grafana.debian-k3s docker-registry.debian-k3s tempo.debian-k3s prometheus.debian-k3s linkerd-viz.debian-k3s backstage.debian-k3s"
if grep -qF "$HOSTS_ENTRY" /etc/hosts; then
    sudo sed -i '' "/$HOSTS_ENTRY/d" /etc/hosts
    echo "Removed hosts entries"
fi
