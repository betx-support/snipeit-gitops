#!/usr/bin/env bash
# §4.1 — Install Jenkins via its own Helm chart. Runs in its own namespace,
# ClusterIP only (exposed later via a second Ingress, see §4.1's design note).
set -euo pipefail

helm repo add jenkins https://charts.jenkins.io
helm repo update
helm install jenkins jenkins/jenkins -n jenkins --create-namespace \
  --set controller.serviceType=ClusterIP \
  --set persistence.storageClass=local-path \
  --set persistence.size=10Gi
