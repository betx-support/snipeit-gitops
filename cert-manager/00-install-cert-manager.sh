#!/usr/bin/env bash
# cert-manager is what actually watches Certificate/ClusterIssuer objects
# and issues/renews certs — nothing in this folder works without it.
set -euo pipefail

helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace \
  --set crds.enabled=true

echo "Wait for it to be ready before continuing:"
echo "  kubectl wait --for=condition=Available --timeout=120s -n cert-manager deployment/cert-manager"
echo "  kubectl wait --for=condition=Available --timeout=120s -n cert-manager deployment/cert-manager-webhook"
