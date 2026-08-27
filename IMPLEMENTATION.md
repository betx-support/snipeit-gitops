# Snipe-IT GitOps Stack — Implementation Guide

Execute in this order. Each step names the exact file(s) in `snipeit-gitops/`
it uses. Steps 1–3 are cluster-wide prerequisites this repo assumes exist but
never installs itself; steps 4 onward are specific to this stack.

**Assumption:** you already have a working Kubernetes cluster (`kubectl`
pointed at it, nodes `Ready`) with a CNI installed. If not, that's a separate
prerequisite this guide doesn't cover.

---

## 1. Storage — local-path-provisioner

Every PVC in this repo (MySQL, the app's own storage, Jenkins, Vault) uses
`storageClassName: local-path`. Nothing creates that StorageClass by itself.

```bash
bash infra/00-install-local-path-provisioner.sh
```

Verify:
```bash
kubectl get storageclass
# local-path should show (default)
```

## 2. Ingress controller — ingress-nginx

`values.yaml`'s `ingress.ingressClassName: nginx` needs this installed first.

```bash
bash infra/01-install-ingress-nginx.sh
```

This exposes it as **NodePort** (30080/30443) — there's no cloud load
balancer on-prem. Note those ports; you'll either point DNS/hosts entries at
`<node-ip>:30443`, or map your firewall's 443 → 30443.

Verify:
```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

## 3. Internal CA — cert-manager + a self-issued root

You don't have an internal CA yet, so this section builds one from scratch,
entirely inside the cluster, using cert-manager's standard "bootstrap your
own root" pattern. Nothing here is publicly trusted (it can't be — this CA
only exists for your internal `.internal.lan` hostnames), so step 3.5 covers
getting clients to actually trust it.

### 3.1 Install cert-manager

```bash
bash cert-manager/00-install-cert-manager.sh
kubectl wait --for=condition=Available --timeout=120s -n cert-manager deployment/cert-manager
kubectl wait --for=condition=Available --timeout=120s -n cert-manager deployment/cert-manager-webhook
```

### 3.2 Bootstrap a self-signed Issuer

This signs exactly one thing: the CA certificate itself, next step.

```bash
kubectl apply -f cert-manager/01-bootstrap-selfsigned-issuer.yaml
```

### 3.3 Mint the actual CA certificate

```bash
kubectl apply -f cert-manager/02-internal-ca-certificate.yaml
```

Verify it issued successfully (this can take a few seconds):
```bash
kubectl get certificate internal-ca -n cert-manager
# READY should become "True"
kubectl get secret internal-ca-key-pair -n cert-manager
# should exist, contains tls.crt, tls.key, ca.crt
```

### 3.4 Create the ClusterIssuer everything else in this repo references

This is the exact name `values.yaml`'s `ingress.clusterIssuer` and
`argocd/ingress.yaml`'s annotation already point at.

```bash
kubectl apply -f cert-manager/03-internal-ca-clusterissuer.yaml
```

Verify:
```bash
kubectl get clusterissuer internal-ca-issuer
# READY should be "True"
```

### 3.5 Extract the CA cert and trust it on your clients

```bash
bash cert-manager/04-extract-and-trust-ca.sh
```

This writes `internal-ca.crt` (the public cert only — never the private key,
which stays in the cluster) and prints OS-specific trust instructions
(Linux/`update-ca-certificates`, Windows cert store, macOS Keychain, and
Firefox separately, since Firefox ignores the OS trust store). **Do this on
every machine/browser that will hit `https://assets.internal.lan` or
`https://argocd.internal.lan`** — until then, expect a browser TLS warning;
that's expected for a self-signed internal CA, not a misconfiguration.

At this point, any `Ingress` in the cluster that adds the annotation
`cert-manager.io/cluster-issuer: internal-ca-issuer` will automatically get a
valid (internally-trusted) TLS certificate issued and auto-renewed by
cert-manager — no manual cert handling from here on.

---

## 4. Jenkins

```bash
bash jenkins/install.sh
```

Configure the dynamic agent pod template (`jenkins/agent-pod-template.yaml`)
under **Manage Jenkins → Clouds → Kubernetes → Pod Templates** (or re-run the
install with `--set-file` pointing at it — either works).

Under **Manage Jenkins → Credentials**, add:
- Git credentials (SSH key or token) scoped to this pipeline only
- A container registry credential, **only if** you're pushing a custom image
  (not needed if you're consuming the upstream `snipe/snipe-it` image as-is)

Jenkins deliberately gets **no cluster/kubeconfig credential** — it never
runs `kubectl` or `helm upgrade` against the cluster; that's ArgoCD's job
exclusively.

### 4.1 Expose Jenkins over the internal CA

```bash
kubectl apply -f jenkins/ingress.yaml
```

Add `jenkins.internal.lan` to your DNS/hosts, pointing at a node IP, port
30443 (from step 2). Get the initial admin password:
```bash
kubectl exec -n jenkins -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password
```

## 5. ArgoCD

```bash
bash argocd/install.sh
kubectl apply -f argocd/project.yaml
```

Don't apply `argocd/application.yaml` yet — that's the final step, once
Vault and the chart's remaining values are actually ready to serve traffic.

### 5.1 (Optional) Expose the ArgoCD UI over the internal CA

```bash
kubectl apply -f argocd/ingress.yaml
```

Add `argocd.internal.lan` to your DNS/hosts pointing at a node IP, port
30443 (from step 2). Log in with the initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

### 5.2 RBAC for who can operate the Application

Apply `argocd/rbac-policy.csv`'s contents into the `argocd-rbac-cm`
ConfigMap's `policy.csv` key (via `kubectl edit cm argocd-rbac-cm -n argocd`,
or your own GitOps process for ArgoCD's own config).

---

## 6. Vault

```bash
bash vault/01-install.sh
kubectl wait --for=condition=Ready --timeout=120s -n vault pod/vault-0 || true
# (it will report not-ready until unsealed in the next step — that's expected)
```

### 6.0 (Optional) Expose the Vault UI over the internal CA

```bash
kubectl apply -f vault/ingress.yaml
```

**Read `vault/ingress.yaml`'s comment block before applying this one** —
unlike Jenkins/ArgoCD/Snipe-IT, Vault holds actual plaintext secret material,
not just an app or a CI tool, so exposing its login UI on the network is a
deliberate tradeoff, not a default to accept without thinking about it. The
file ships permissive (any client on the network can reach the login page);
tighten with an IP allowlist annotation, or skip the file entirely and use
`kubectl port-forward -n vault svc/vault-ui 8200:8200` for admin access
instead, if that fits your environment better.

If applied, add `vault.internal.lan` to your DNS/hosts, port 30443.

### 6.1 Initialize and unseal

```bash
bash vault/02-init-unseal.sh
```

This prints the unseal commands using the 5 key shares just generated in
`vault-init-output.txt`. **Move that file to offline storage immediately** —
a physical safe or air-gapped secrets manager, never Git, never left on any
node's disk. Then run the 3 unseal commands it prints (any 3 of the 5
shares).

### 6.2 Enable the KV engine and write real secrets

Edit `vault/03-enable-kv-and-write-secrets.sh` first — replace every
`<generated>` placeholder with real values (e.g.
`openssl rand -base64 32` for `APP_KEY`/passwords), then run it:

```bash
bash vault/03-enable-kv-and-write-secrets.sh
```

### 6.3 Configure Kubernetes auth

```bash
bash vault/04-kubernetes-auth.sh
```

This creates the `snipeit-eso` Vault role/policy pairing — matched names,
per the fix already applied (see the repo README's note on the
policy/role-name mismatch this replaced).

### 6.4 Install External Secrets Operator

```bash
bash vault/05-install-external-secrets-operator.sh
```

### 6.5 Apply the Vault SecretStore

```bash
kubectl create namespace snipeit --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f argocd/vault-secretstore.yaml
```

(Creating the `snipeit` namespace here is a formality — `templates/namespace.yaml`
and ArgoCD's `CreateNamespace=true` will both also try to create it later;
harmless, since namespace creation is idempotent.)

At this point Vault holds the real secrets, and there's a `SecretStore`
ready to sync them into `Secret` objects the moment the chart's
`ExternalSecret` templates (already rendering, since `vault.enabled: true`
in `values.yaml`) are deployed by ArgoCD in the final step.

---

## 7. Fill in the last real gaps in the chart

Two things in the repo are still genuinely incomplete, on purpose (see the
repo README):

- **`charts/snipeit/values-production.yaml`** — currently mirrors the base
  `values.yaml`. Set real production values here: a pinned `image.tag`,
  actual resource limits, and confirm `ingress.host` matches the DNS name
  you'll actually use (default: `assets.internal.lan` — add it to your
  DNS/hosts pointing at a node IP, port 30443).
- **Push this repo to your actual Git server**, and update the placeholder
  URL (`https://your-git-server/snipeit-gitops.git`) in both
  `argocd/project.yaml` (`spec.sourceRepos`) and `argocd/application.yaml`
  (`spec.source.repoURL`) to the real one.

### 7.1 Configure the Jenkins webhook

Point your Git server's push-event webhook at Jenkins'
`/github-webhook/` (or equivalent) endpoint, per §4.5 of the CI/CD guide —
avoids polling lag entirely.

---

## 8. Deploy

```bash
kubectl apply -f argocd/application.yaml
```

From here, ArgoCD takes over: it renders the chart, diffs against the
cluster, and applies (with `prune: true` and `selfHeal: true` already set).
Watch it:

```bash
kubectl get application snipeit -n argocd -w
```

---

## 9. Verify end-to-end

```bash
kubectl get pods -n snipeit
```

You should see: the `snipeit` Deployment's Pod (after its `migrate`
initContainer completes), `mysql-0` (StatefulSet), a `redis` Pod, and the
`ExternalSecret`-populated `mysql-app-secret` / `snipeit-app-secret` objects
already present.

```bash
kubectl get externalsecret -n snipeit
# both should show SecretSynced = True
kubectl get certificate -n snipeit
# snipeit-tls should show READY = True (issued by internal-ca-issuer)
```

Visit `https://assets.internal.lan` (via your NodePort/DNS mapping from step
2) from a machine that's trusted the CA per step 3.5 — it should load with a
valid, non-warning TLS certificate. Same check applies to the other three
services now exposed the same way: `https://argocd.internal.lan`,
`https://jenkins.internal.lan`, and (if you applied it) `https://vault.internal.lan`
— all four should show a valid cert issued by `internal-ca-issuer` once the
CA is trusted client-side.

---

## 10. What each piece does when you change something later

- **Change app code / bump the image tag** → PR against `values-production.yaml`
  → Jenkins validates → merge → ArgoCD syncs. No manual `kubectl` ever.
- **Rotate a secret** → `vault kv put snipeit/app APP_KEY=<new>` directly
  against Vault → ESO picks it up within `refreshInterval` (1h), or force it:
  ```bash
  kubectl annotate externalsecret snipeit-app-secret -n snipeit force-sync=$(date +%s) --overwrite
  ```
  No Git commit, no Jenkins, no ArgoCD sync involved — by design (§8 of the
  CI/CD guide).
- **Rotate the internal CA itself** — a 10-year duration was chosen
  deliberately so this should be rare; when it happens, every client that
  trusted the old `internal-ca.crt` needs the new one re-trusted (step 3.5
  again), which is the real cost of running your own CA versus a publicly
  trusted one.

---

## Troubleshooting quick reference

| Symptom | Check |
|---|---|
| Browser shows "certificate not trusted" on `assets.internal.lan` | Did you complete step 3.5 on *that specific* client/browser? Each one needs the CA trusted individually. |
| `kubectl get certificate -n snipeit` never reaches `READY: True` | `kubectl describe certificate snipeit-tls -n snipeit` → almost always `internal-ca-issuer` isn't `READY` yet (step 3.4) or cert-manager's webhook isn't up (step 3.1) |
| `ExternalSecret` never syncs | Is Vault sealed? `kubectl exec -n vault vault-0 -- vault status` — if `Sealed: true`, run the 3 unseal commands again (Vault reseals on every restart, no auto-unseal in this design) |
| PVC stuck `Pending` | `kubectl get storageclass` — confirm `local-path` exists and is default (step 1) |
| Ingress 404s / connection refused | Confirm you're hitting the NodePort (30443) or have it mapped to 443, and that DNS/hosts actually resolves the hostname to a node IP |
| `kubeadm`/cluster-level issues | Out of scope for this guide — see the separate Kubernetes Installation Guide |

For everything Jenkins/ArgoCD/Vault-specific beyond this, see the
Troubleshooting Additions table (§9) in `snipeit-cicd-jenkins-argocd-helm.md`.
