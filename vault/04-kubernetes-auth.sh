#!/usr/bin/env bash
# §6.6 — Enable the Kubernetes auth method, define a policy scoped to
# exactly the two paths ESO needs, and bind it to the snipeit-eso
# ServiceAccount in the snipeit namespace only.
set -euo pipefail

kubectl exec -n vault vault-0 -- vault auth enable kubernetes

kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"

kubectl exec -i -n vault vault-0 -- vault policy write snipeit-eso - <<'EOF'
path "snipeit/data/mysql" { capabilities = ["read"] }
path "snipeit/data/app"   { capabilities = ["read"] }
EOF

kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/snipeit-eso \
  bound_service_account_names=snipeit-eso \
  bound_service_account_namespaces=snipeit \
  policy=snipeit-eso \
  ttl=1h
