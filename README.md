# snipeit-gitops

Generated from `snipeit-cicd-jenkins-argocd-helm.md`. Every file here corresponds
to a specific section of that document — see the inline comments in each file
for the exact section reference.

**Start here: [`IMPLEMENTATION.md`](./IMPLEMENTATION.md)** — the full,
ordered, step-by-step guide from a bare cluster through a fully deployed,
CI/CD-managed Snipe-IT, including bootstrapping an internal CA from scratch
via `cert-manager/` (nothing else in this repo issues TLS certs without it)
and the `infra/` prerequisites (storage class, ingress controller) neither
source document covered.

## What's real vs. placeholder

- **Fully specified, ready to use as-is:** `charts/snipeit/Chart.yaml`, `values.yaml`,
  `templates/deployment.yaml`, `templates/_helpers.tpl`,
  `templates/external-secret.yaml`, `Jenkinsfile`, everything under `argocd/`,
  everything under `vault/`, everything under `jenkins/`.
- **Written to fill functional gaps, not given verbatim in either source
  document — review before treating as final:** `templates/mysql-statefulset.yaml`,
  `templates/mysql-services.yaml`, `templates/redis-deployment.yaml`,
  `templates/configmap.yaml`, `templates/storage-pvc.yaml`,
  `templates/namespace.yaml`, `templates/service.yaml`, `templates/ingress.yaml`,
  `templates/cronjobs.yaml`. These were derived from `values.yaml`'s existing
  `mysql.*`/`redis.*`/`storage.*`/`app.*`/`ingress.*` fields and from what
  `deployment.yaml` already expects (env var names, the hardcoded
  `snipeit-storage-pvc` claim name, port 80), so the stack is internally
  consistent end-to-end, but none of these were spelled out in either source
  document — no file in this chart is an empty stub anymore.
  `templates/rbac.yaml` creates the `snipeit-eso` ServiceAccount that
  `argocd/vault-secretstore.yaml` and `vault/04-kubernetes-auth.sh` reference
  by name — without it, ESO has no identity to authenticate to Vault with,
  and this was a genuine gap in the original generation.
- **Still a real TODO:** `values-production.yaml` — it renders and installs,
  but its values are copied straight from the base `values.yaml` rather than
  containing anything actually production-specific (tighter resource limits,
  a real production image tag pin, etc.). That decision belongs to whoever
  owns the companion design document, not something safe to invent here.
- **`jenkins/ingress.yaml` and `vault/ingress.yaml`** were added after the
  initial generation — the original scaffold only gave Snipe-IT and ArgoCD
  an actual `Ingress` object, despite the stated goal of all four services
  being reachable through ingress. Vault's install script (`vault/01-install.sh`)
  was also updated to set `ui.enabled=true`, since the chart ships that off
  by default and an Ingress with nothing listening behind it does nothing.
  Read the security-tradeoff comment at the top of `vault/ingress.yaml`
  before applying it — Vault is a materially different risk than the other
  three.
- **Worth a second look before relying on it:** `templates/namespace.yaml`
  creates the namespace so the chart installs standalone, but ArgoCD's
  `application.yaml` already does this via `CreateNamespace=true` — see the
  caution comment in that file about a known Helm/ArgoCD namespace-ownership
  interaction if you hit "already exists" errors under ArgoCD specifically.

## One bug fixed while generating this

§6.6 of the source document created a Vault policy named `snipeit-read` but
then referenced `policy=snipeit-eso` when defining the Kubernetes auth role —
a naming mismatch that would have granted the role zero actual permissions
(Vault roles/policies match by exact name). Both `vault/04-kubernetes-auth.sh`
here and the source markdown have been corrected to use `snipeit-eso`
consistently for both the policy and the role.

## Suggested install order

```
1. jenkins/install.sh
2. argocd/install.sh
3. kubectl apply -f argocd/project.yaml
4. vault/01-install.sh
5. vault/02-init-unseal.sh        # by hand — move vault-init-output.txt offline immediately
6. vault/03-enable-kv-and-write-secrets.sh   # fill in real secret values first
7. vault/04-kubernetes-auth.sh
8. vault/05-install-external-secrets-operator.sh
9. kubectl apply -f argocd/vault-secretstore.yaml
10. Fill in the placeholder templates (see above) + values-production.yaml
11. kubectl apply -f argocd/application.yaml
```

Steps 1–2 and 4–9 are one-time cluster bootstrap, done by a human — not part
of the Jenkins/ArgoCD pipeline itself. Once `application.yaml` is applied,
ArgoCD takes over: every subsequent change flows through Git → Jenkins
validation → merge → ArgoCD sync, per §8 (End-to-End Flow) of the source doc.
