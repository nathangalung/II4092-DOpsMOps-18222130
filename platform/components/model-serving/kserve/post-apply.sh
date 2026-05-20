#!/usr/bin/env bash
# =============================================================================
# kserve/post-apply.sh — heal predictor pods that missed storage-init injection
# =============================================================================
# Why this exists:
#   The kserve component is a single render that ships CRDs, controller-manager,
#   the `inferenceservice.kserve-webhook-server.pod-mutator` MutatingWebhook,
#   the kserve-webhook-server-service, AND the demo-health-check
#   InferenceService all in one `kubectl apply --server-side`. SSA creates
#   the InferenceService AT THE SAME TIME as the controller; the controller
#   then materialises a Deployment/ReplicaSet/Pod for the predictor BEFORE
#   the webhook Service has Endpoints.
#
#   The pod-mutator is configured `failurePolicy: Ignore` (correct: we don't
#   want webhook downtime to brick every model-serving pod). Combined with
#   the boot race, the very first predictor pod after a fresh `make nuke
#   && make phase-full` is created WITHOUT the storage-initializer init
#   container, because the API server failed-open on the unreachable
#   webhook. mlserver_mlflow then errors with `Invalid URI specified for
#   model platform-health-check (/mnt/models)` because /mnt/models is empty
#   — it's an emptyDir, never populated, since the init container that
#   would `aws s3 cp` from `s3://platform-models/sklearn/iris/` never
#   existed in the spec.
#
#   The Deployment never self-corrects: the same templated PodSpec is
#   re-rolled forever, each replica missing the init container, each
#   replica CrashLooping the same way.
#
# What this hook does:
#   1. Block until kserve-controller-manager Deployment is Available.
#   2. Block until kserve-webhook-server-service has Endpoints (TLS cert
#      rotation + leader election can take 60-90s on a fresh boot).
#   3. Walk every predictor pod across every namespace (`serving.kserve.io/
#      inferenceservice` label) and force-delete any whose Pod spec has no
#      `storage-initializer` init container. The owning ReplicaSet then
#      recreates the pod, this time hitting the live webhook and getting
#      the init container injected.
#
#   Idempotent: on a healthy cluster every predictor pod already has the
#   init container, so the loop walks the list and exits. Cost on a clean
#   cluster: ~5s for the rollout-status + endpoints checks.
# =============================================================================
set -euo pipefail

NS=model-serving

echo "    [post-apply] waiting kserve-controller-manager Available (timeout 900s)"
# 900s, not 300s: kserve-controller pod often hits a 5-7m sandbox-creation
# stall during phase-full reapply when containerd CRI is churning through
# concurrent Job/CronJob sandboxes (#191 mid-life recurrence). 300s expired
# right as the pod was about to come Ready.
kubectl -n "$NS" rollout status deploy/kserve-controller-manager --timeout=900s

echo "    [post-apply] waiting kserve-webhook-server-service Endpoints (timeout 360s)"
deadline=$(( $(date +%s) + 360 ))
while (( $(date +%s) < deadline )); do
  ep=$(kubectl -n "$NS" get endpoints kserve-webhook-server-service \
    -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
  if [[ -n "$ep" ]]; then
    echo "        endpoints ready: $ep"
    break
  fi
  sleep 5
done

echo "    [post-apply] healing predictor pods missing storage-initializer init"
kubectl get pods -A -l serving.kserve.io/inferenceservice -o json 2>/dev/null \
  | jq -r '.items[] | select(([.spec.initContainers[]?.name] | index("storage-initializer")) == null) | "\(.metadata.namespace) \(.metadata.name)"' \
  | while read -r pod_ns pod_name; do
      [[ -z "${pod_ns:-}" || -z "${pod_name:-}" ]] && continue
      echo "        delete $pod_ns/$pod_name (no storage-init → webhook race victim)"
      kubectl -n "$pod_ns" delete pod "$pod_name" --grace-period=0 --force >/dev/null 2>&1 || true
    done
