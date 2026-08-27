#!/usr/bin/env bash
# §6.4 — Initialize and unseal Vault. Run once, interactively, by hand —
# this is deliberately NOT something CI/CD (Jenkins or ArgoCD) ever runs.
#
# vault-init-output.txt contains 5 unseal key shares + the initial root
# token. MOVE THIS FILE TO OFFLINE STORAGE IMMEDIATELY (a physical safe,
# an air-gapped secrets manager) — never commit it, never leave it on any
# node's disk. Split the 5 key shares across different holders if more
# than one person should be able to reconstitute quorum.
set -euo pipefail

kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 -key-threshold=3 > vault-init-output.txt

echo "Now unseal with any 3 of the 5 keys printed above, e.g.:"
echo "  kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-1>"
echo "  kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-2>"
echo "  kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-3>"
