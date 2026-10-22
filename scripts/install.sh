#!/usr/bin/env bash
# Install every platform chart on the current kubectl context, in dependency order.
#
#   scripts/install.sh                 # defaults only
#   scripts/install.sh clusters/prod   # plus per-cluster overrides: clusters/prod/<chart>.yaml
#
# Safe to re-run: each step is `helm upgrade --install`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERRIDES="${1:-}"

# release  namespace
RELEASES=(
  "kong         kong"
  "cert-manager cert-manager"
  "rancher      cattle-system"
)

echo "Installing into context: $(kubectl config current-context)"

for entry in "${RELEASES[@]}"; do
  read -r name ns <<<"$entry"
  chart="$ROOT/charts/$name"
  args=()
  if [[ -n "$OVERRIDES" && -f "$OVERRIDES/$name.yaml" ]]; then
    args+=(-f "$OVERRIDES/$name.yaml")
  fi

  echo "==> $name ($ns)"
  helm dependency build "$chart" >/dev/null
  helm upgrade --install "$name" "$chart" \
    --namespace "$ns" --create-namespace \
    --wait --timeout 10m \
    ${args[@]+"${args[@]}"}
done

lb=$(kubectl get svc -n kong kong-gateway-proxy \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
pw=$(kubectl get secret -n cattle-system bootstrap-secret \
  -o go-template='{{.data.bootstrapPassword|base64decode}}' 2>/dev/null || true)

echo
echo "Kong proxy LB : ${lb:-<pending, check: kubectl get svc -n kong kong-gateway-proxy>}"
echo "Rancher URL   : https://${lb:-<kong-proxy-lb>}/ (or your rancher.hostname)"
echo "Bootstrap pw  : ${pw:-<not found yet>}"
