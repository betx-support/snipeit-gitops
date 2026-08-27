#!/usr/bin/env bash
# §6.7 — Install External Secrets Operator. After this, apply
# argocd/vault-secretstore.yaml (either directly with kubectl, or let
# ArgoCD manage it alongside project.yaml/application.yaml), and set
# vault.enabled: true in values.yaml / values-production.yaml so the
# chart's templates/external-secret.yaml renders.
set -euo pipefail

helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
