# debian-k3s

K3s + Kustomize + Helm on top of Debian

## Technologies used

- Lima (Apple Virtualization framework, Debian GNU/Linux virtual machine)
- k3s (Kubernetes cluster, workload orchestration)
- Traefik (ingress, SSL, load balancing, routing)
- Linkerd (service mesh, observability)
- cert-manager + trust-manager (automated certificate management)
- Helm (deployment package manager / YAML templating engine)
- Graphite (metrics)
- Chromium (headless browser)

## Technologies to add

- nats - messaging queue
- kafka - event streaming
- unleash - feature flags
- minio - object storage

## How to use

```shell
# install dependencies
brew install kubectl lima helm kustomize

# configure kubectl
export KUBECONFIG="/Users/brandon/.lima/debian-k3s/copied-from-guest/kubeconfig.yaml"

# create VM + deploy infrastructure + build container
./scripts/deploy.sh

# cleanup
./scripts/cleanup.sh
```
