#!/usr/bin/env bash
# Every PVC in this repo (MySQL's StatefulSet, the app's storage PVC,
# Jenkins' persistence, Vault's dataStorage) uses storageClassName:
# local-path. Nothing creates that StorageClass by itself — Rancher's
# local-path-provisioner does, and needs to be installed once per cluster
# before anything else in this repo can actually bind a volume.
set -euo pipefail

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# Make it the default StorageClass so PVCs that omit storageClassName still bind.
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "Verify:"
echo "  kubectl get storageclass"
echo "  kubectl get pods -n local-path-storage"
