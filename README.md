# helm-charts

Pinned, always-up-to-date wrapper charts that install our platform tools on any
EKS cluster. Each chart in `charts/` wraps one upstream chart as a dependency and
holds our shared defaults. Install them all on a new cluster with
`scripts/install.sh`.

| Chart | Upstream | Version | Namespace | Install order |
|---|---|---|---|---|
| `charts/kong` | `kong/ingress` | 0.24.0 | `kong` | 1 |
| `charts/cert-manager` | `jetstack/cert-manager` | v1.21.2 | `cert-manager` | 1 |
| `charts/rancher` | `rancher-stable/rancher` | 2.15.2 | `cattle-system` | 2 (needs Kong + cert-manager) |

## Layout

```
charts/<name>/
  Chart.yaml   # upstream chart pinned as a dependency
  Chart.lock   # resolved dependency versions (committed)
  values.yaml  # our overrides, nested under the dependency name
  templates/   # extra resources we add (rancher: its Kong Ingress)
clusters/<cluster-name>/<chart>.yaml  # optional per-cluster overrides
scripts/install.sh                    # installs all charts in order
```

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

## Provisioning a new cluster

Point `kubectl` at the new cluster, then run:

```sh
scripts/install.sh                        # defaults
scripts/install.sh clusters/<cluster-name> # with per-cluster overrides
```

It installs Kong, cert-manager and Rancher in order (`helm upgrade --install --wait`,
safe to re-run) and prints the Kong load balancer address and Rancher's bootstrap
password.

Per-cluster settings go in `clusters/<cluster-name>/<chart>.yaml` (copy
`clusters/example/`). Each file is optional and is passed with `-f` to that chart.
The charts themselves contain no cluster-specific values.

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
