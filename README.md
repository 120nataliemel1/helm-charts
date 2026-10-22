# helm-charts

Pinned, always-up-to-date wrapper charts that install our platform tools on any
EKS cluster. Each chart in `charts/` wraps one upstream chart as a dependency and
holds our shared defaults. Argo CD installs and keeps them in sync on every
cluster (see [Bootstrapping a new cluster](#bootstrapping-a-new-cluster)).

| Chart | Upstream | Version | Namespace | Sync wave |
|---|---|---|---|---|
| `charts/argocd` | `argo/argo-cd` | 10.10.5 (Argo CD v3.5.5) | `argocd` | -1 |
| `charts/kong` | `kong/ingress` | 0.24.0 | `kong` | 0 |
| `charts/cert-manager` | `jetstack/cert-manager` | v1.21.2 | `cert-manager` | 0 |
| `charts/rancher` | `rancher-stable/rancher` | 2.15.2 | `cattle-system` | 1 (needs Kong + cert-manager) |

## Layout

```
charts/<name>/
  Chart.yaml   # upstream chart pinned as a dependency
  Chart.lock   # resolved dependency versions (committed)
  values.yaml  # our overrides, nested under the dependency name
  templates/   # extra resources we add (rancher: its Kong Ingress)
bootstrap/     # app of apps: one Argo CD Application per chart
clusters/<cluster-name>/
  root-app.yaml  # the one manifest applied by hand
  <chart>.yaml   # optional per-cluster overrides for charts/<chart>
```

To add a tool: create `charts/<name>/` and add it under `apps:` in
`bootstrap/values.yaml`. Every cluster picks it up on the next sync.

Downloaded `charts/<name>/charts/*.tgz` are not committed. Argo CD and
`helm dependency build` fetch them from `Chart.lock`.

## Keeping charts updated

[Renovate](https://docs.renovatebot.com/modules/manager/helmv3/) (`renovate.json`)
watches every `Chart.yaml` and opens PRs when an upstream chart releases a new
version. It updates `Chart.yaml` and `Chart.lock`, and bumps the wrapper chart's
version. Minor and patch updates are grouped into one PR; major updates get
their own PR. Install the [Renovate GitHub App](https://github.com/apps/renovate)
on this repo to enable it.

The `lint` workflow runs `helm lint` and `helm template` on every PR, so a
broken upgrade is caught before it reaches `main`.

Before merging a Rancher upgrade, check its supported Kubernetes range
(`kubeVersion` in the upstream `Chart.yaml`, currently `< 1.37.0`).

## Bootstrapping a new cluster

With `kubectl` pointed at the new cluster:

```sh
# 1. Per-cluster folder (commit and push it)
cp -r clusters/example clusters/<cluster-name>
#    set `cluster: <cluster-name>` in clusters/<cluster-name>/root-app.yaml

# 2. Install Argo CD once by hand
helm dependency build charts/argocd
helm install argocd charts/argocd -n argocd --create-namespace --wait

# 3. Hand the cluster to Argo CD
kubectl apply -f clusters/<cluster-name>/root-app.yaml
```

If this repo is private, give Argo CD read access before step 3
([repository credentials](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/)).

### How it works

1. **Helm installs Argo CD.** Nothing can manage the cluster yet, so this one
   chart is installed by hand.
2. **`root-app.yaml` creates the `root` Application.** It points Argo CD at
   `bootstrap/` with `cluster: <cluster-name>`.
3. **`bootstrap/` creates one Application per chart** (`argocd`, `kong`,
   `cert-manager`, `rancher`). Each renders `charts/<name>` with
   `clusters/<cluster-name>/<name>.yaml` on top, if that file exists.
4. **Sync waves set the order.** `argocd` (wave -1) adopts the Helm install from
   step 1, so from now on Argo CD upgrades itself from Git. Kong and cert-manager
   (wave 0) must be Healthy before Rancher (wave 1) starts. `charts/argocd`
   adds the Application health check that makes this wait work.
5. **Git is the source of truth.** Every Application auto-syncs, prunes removed
   resources and reverts manual changes. A merged Renovate PR rolls out to every
   cluster that tracks `main`.

Open the Argo CD UI:

```sh
kubectl port-forward -n argocd svc/argocd-server 8080:443
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Log in at https://localhost:8080 as `admin`.

## Reaching Rancher

Rancher is exposed through a Kong Ingress (`charts/rancher/templates/ingress.yaml`).

**No hostname (default):** the Ingress matches any host, so Rancher is reachable at
`https://<kong-proxy-lb>/`. Kong serves its default self-signed certificate, so
the browser shows a warning. Get the address with:

```sh
kubectl get svc -n kong kong-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

**With a hostname:** create a CNAME to that address and set `rancher.hostname` in
the cluster's `rancher.yaml`. The Ingress then gets a host rule and a cert-manager
certificate: a self-signed CA by default (`ingress.tls.source: rancher`), or a
public one with `ingress.tls.source: letsEncrypt` and `letsEncrypt.email`.

The initial admin password is generated. Read it with:

```sh
kubectl get secret -n cattle-system bootstrap-secret \
  -o go-template='{{.data.bootstrapPassword|base64decode}}{{"\n"}}'
```
