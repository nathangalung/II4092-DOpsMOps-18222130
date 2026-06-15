#!/usr/bin/env bash
# =============================================================================
# scale-up-platform.sh — restore every Deployment + StatefulSet + KafkaNodePool
# in platform namespaces back to replicas=1 (single-node mandate).
# =============================================================================
# Inverse of scale-zero-all.sh. Single-node convention: every workload runs
# replicas=1 idle; HPAs scale above this on load. This script restores baseline
# after a scale-zero, without waiting for ArgoCD selfHeal.
#
# Excludes the same operator+infra namespaces as scale-zero-all.sh so we don't
# touch resources that are intentionally 0 (e.g. controller deployments paused
# during upgrade).
#
# Also handles Strimzi KafkaNodePool (controls broker STS via operator) since
# scaling the broker STS directly is reverted by Strimzi's operator within
# seconds — the nodepool CR is the source of truth.
# =============================================================================
set -euo pipefail

REPLICAS="${REPLICAS:-1}"

declare -a EXCLUDE=(
  kube-system
  kube-public
  kube-node-lease
  default
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
)

excl_grep="$(printf '%s|' "${EXCLUDE[@]}")"
excl_grep="${excl_grep%|}"

echo "==> Scaling Deployments to $REPLICAS (excluding: $excl_grep)"
kubectl get deploy -A --no-headers 2>/dev/null \
  | awk -v ex="$excl_grep" '$1 !~ "^("ex")$" {print $1, $2}' \
  | while read -r ns name; do
      [[ -z "$ns" || -z "$name" ]] && continue
      echo "    scale deploy/$name -n $ns → $REPLICAS"
      kubectl scale deploy "$name" -n "$ns" --replicas="$REPLICAS" >/dev/null 2>&1 || true
    done

echo ""
echo "==> Scaling StatefulSets to $REPLICAS (excluding: $excl_grep)"
kubectl get sts -A --no-headers 2>/dev/null \
  | awk -v ex="$excl_grep" '$1 !~ "^("ex")$" {print $1, $2}' \
  | while read -r ns name; do
      [[ -z "$ns" || -z "$name" ]] && continue
      echo "    scale sts/$name -n $ns → $REPLICAS"
      kubectl scale sts "$name" -n "$ns" --replicas="$REPLICAS" >/dev/null 2>&1 || true
    done

# Strimzi KafkaNodePool — the operator owns the broker STS replicas, so scaling
# the STS is fought by the operator. Patch the CR instead.
if kubectl api-resources --api-group=kafka.strimzi.io 2>/dev/null | grep -q kafkanodepools; then
  echo ""
  echo "==> Scaling KafkaNodePool CRs to $REPLICAS"
  kubectl get kafkanodepool -A --no-headers -o custom-columns=NS:.metadata.namespace,N:.metadata.name 2>/dev/null \
    | while read -r ns name; do
        [[ -z "$ns" || -z "$name" ]] && continue
        echo "    patch kafkanodepool/$name -n $ns → replicas=$REPLICAS"
        kubectl patch kafkanodepool "$name" -n "$ns" --type=merge -p "{\"spec\":{\"replicas\":$REPLICAS}}" >/dev/null 2>&1 || true
      done
fi

echo ""
echo "==> Done. Verify with: kubectl get pods -A | grep -vE '(Running|Completed)'"
