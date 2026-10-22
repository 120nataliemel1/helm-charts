#!/usr/bin/env bash
# Bootstrap a cluster with every platform tool. Run with kubectl pointed at it:
#
#   ./bootstrap.sh <cluster-name>
#
# 1. Installs Argo CD with Helm (charts/argocd).
# 2. Creates the `root` Application, which points Argo CD at bootstrap/ with
#    `cluster: <cluster-name>`. Argo CD then installs the rest and keeps it in
#    sync with Git, taking over its own install as well.
#
# clusters/<cluster-name>/ is optional: without it the cluster gets the defaults.
# Safe to re-run.
set -euo pipefail

CLUSTER="${1:?usage: $0 <cluster-name>}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_URL="${REPO_URL:-https://github.com/120nataliemel1/helm-charts.git}"
REVISION="${REVISION:-main}"

echo "Bootstrapping cluster '$CLUSTER' on context $(kubectl config current-context)"
if [[ ! -d "$ROOT/clusters/$CLUSTER" ]]; then
  echo "No clusters/$CLUSTER/ folder: using chart defaults."
fi

echo "==> Installing Argo CD"
args=()
if [[ -f "$ROOT/clusters/$CLUSTER/argocd.yaml" ]]; then
  args+=(-f "$ROOT/clusters/$CLUSTER/argocd.yaml")
fi
helm dependency build "$ROOT/charts/argocd" >/dev/null
helm upgrade --install argocd "$ROOT/charts/argocd" \
  --namespace argocd --create-namespace \
  --wait --timeout 10m \
  ${args[@]+"${args[@]}"}
kubectl wait --for condition=established --timeout 60s crd/applications.argoproj.io

echo "==> Creating root Application"
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $REPO_URL
    targetRevision: $REVISION
    path: bootstrap
    helm:
      valuesObject:
        cluster: $CLUSTER
        repoURL: $REPO_URL
        targetRevision: $REVISION
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

echo
echo "Done. Argo CD is now installing Kong, cert-manager and Rancher. Watch with:"
echo "  kubectl get applications -n argocd -w"
echo "Argo CD UI: kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "  admin password: kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
