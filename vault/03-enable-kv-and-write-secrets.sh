#!/usr/bin/env bash
# §6.5 — Enable the KV v2 engine at path "snipeit" and write the actual
# secret values. Replace every <generated> placeholder before running.
# Run once, by hand, using the root token from vault-init-output.txt.
set -euo pipefail

ROOT_TOKEN="<root-token>"   # from vault-init-output.txt — never hard-code for real use

kubectl exec -n vault vault-0 -- vault login "$ROOT_TOKEN"

kubectl exec -n vault vault-0 -- vault secrets enable -path=snipeit kv-v2

kubectl exec -n vault vault-0 -- vault kv put snipeit/mysql \
  MYSQL_ROOT_PASSWORD="<generated>" \
  MYSQL_PASSWORD="<generated>"

kubectl exec -n vault vault-0 -- vault kv put snipeit/app \
  APP_KEY="<generated, base64:...>" \
  DB_PASSWORD="<same value as MYSQL_PASSWORD above>"
