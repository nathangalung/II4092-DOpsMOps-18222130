#!/usr/bin/env bash
# =============================================================================
# scale-zero-all.sh — scale every Deployment + StatefulSet in platform
# namespaces to 0 (frees CPU/mem; keeps CRDs, Services, PVCs).
# =============================================================================
# Operators (cnpg-operator, kyverno admission, istiod, etc.) are NOT scaled —
# they manage cluster invariants. To scale operators too, use NUKE_ALL=1.
#
# Excluded: kube-system (built-in local-path-provisioner lives here), cnpg-system,
# kyverno (policy admission), istio-system (mesh), keda, external-secrets,
# cert-manager.
# =============================================================================
set -euo pipefail

NUKE_ALL="${NUKE_ALL:-0}"

# Always-running namespaces (cluster infra)
declare -a EXCLUDE=(
  kube-system
  kube-public
  kube-node-lease
  default
)

# Operator namespaces — kept up unless NUKE_ALL=1
if [[ "$NUKE_ALL" == "0" ]]; then
  EXCLUDE+=(
    cnpg-system
    kyverno
    istio-system
    keda
    external-secrets
    cert-manager
    argo-rollouts
    spark-operator
    flink-operator
    chaos-mesh
    falco
    trivy-system
    velero
    clickhouse-system
    cnpg-system
  )
fi

excl_grep="$(printf '%s|' "${EXCLUDE[@]}")"
excl_grep="${excl_grep%|}"

echo "==> Scaling Deployments to 0 (excluding: $excl_grep)"
kubectl get deploy -A --no-headers 2>/dev/null \
  | awk -v ex="$excl_grep" '$1 !~ "^("ex")$" {print $1, $2}' \
  | while read -r ns name; do
      [[ -z "$ns" || -z "$name" ]] && continue
      echo "    scale deploy/$name -n $ns → 0"
      kubectl scale deploy "$name" -n "$ns" --replicas=0 >/dev/null 2>&1 || true
    done

echo ""
echo "==> Scaling StatefulSets to 0 (excluding: $excl_grep)"
kubectl get sts -A --no-headers 2>/dev/null \
  | awk -v ex="$excl_grep" '$1 !~ "^("ex")$" {print $1, $2}' \
  | while read -r ns name; do
      [[ -z "$ns" || -z "$name" ]] && continue
      echo "    scale sts/$name -n $ns → 0"
      kubectl scale sts "$name" -n "$ns" --replicas=0 >/dev/null 2>&1 || true
    done

echo ""
echo "==> Done. Verify with: kubectl get pods -A"
