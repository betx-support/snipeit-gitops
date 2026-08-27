#!/usr/bin/env bash
# §6.3 — Install Vault via its official Helm chart.
# Self-hosted, single-replica (no HA, no cloud KMS) — see §7.6 for the
# accepted tradeoffs and the HA revisit trigger.
#
# ui.enabled=true: the UI is off by default in this chart. Without it,
# vault/ingress.yaml would have a valid route to the Vault Service but
# nothing listening on it for a browser to actually render.
set -euo pipefail

helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vault hashicorp/vault -n vault --create-namespace \
  --set server.dataStorage.storageClass=local-path \
  --set server.dataStorage.size=10Gi \
  --set server.ha.enabled=false \
  --set ui.enabled=true
