#!/usr/bin/env bash
# §5.1 — Install ArgoCD via Helm. TLS terminates once, at ingress-nginx
# (§5.1 design note) — hence server.insecure=true for ArgoCD's own
# internal server component.
set -euo pipefail

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd -n argocd --create-namespace \
  --set server.service.type=ClusterIP \
  --set configs.params."server\.insecure"=true
