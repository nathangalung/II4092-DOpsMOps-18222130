#!/usr/bin/env bash
# =============================================================================
# apply-component.sh — install or uninstall a single platform component
# =============================================================================
# Usage:
#   apply-component.sh <apply|delete> <component-name>
#
# Renders platform/components/<NS>/<name> with `kustomize build --enable-helm`
# (so kustomization.yaml may pull upstream charts via `helmCharts:`) and
# applies the result with `kubectl apply --server-side --force-conflicts`.
# Server-side apply is mandatory because several CRD bundles ship by upstream
# charts (Kyverno, ESO, cert-manager) exceed the 256KB annotation limit
# imposed by client-side apply.
#
# A component may also ship `pre-apply.sh` for cases that kustomize+helm
# cannot express cleanly (e.g. patching a distro-bundled Deployment that was
# disabled at install time, like k3s metrics-server).
# =============================================================================
set -euo pipefail

ACTION="${1:-}"
NAME="${2:-}"

if [[ -z "$ACTION" || -z "$NAME" ]]; then
  echo "Usage: $0 <apply|delete> <component-name>" >&2
  exit 1
fi

if [[ "$ACTION" != "apply" && "$ACTION" != "delete" ]]; then
  echo "ACTION must be 'apply' or 'delete' (got: $ACTION)" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPONENTS="$ROOT/platform/components"
# Repo-local cache. Env-agnostic across users/hosts (no /tmp collisions, no
# /tmp-cleaner wipe mid-retry). .cache/ is gitignored at repo root.
CACHE_DIR="$ROOT/.cache"
export REPO_ROOT="$ROOT"
export CACHE_DIR

declare -a NAMESPACES=(
  common security storage data-ingestion data-processing
  data-governance model-lifecycle model-serving observability gitops
)

COMPONENT_PATH=""
for ns in "${NAMESPACES[@]}"; do
  if [[ -d "$COMPONENTS/$ns/$NAME" ]]; then
    COMPONENT_PATH="$COMPONENTS/$ns/$NAME"
    NS="$ns"
    break
  fi
done

if [[ -z "$COMPONENT_PATH" ]]; then
  echo "ERROR: Component '$NAME' not found under any namespace dir." >&2
  echo "Tried: ${NAMESPACES[*]}" >&2
  exit 1
fi

echo "==> $ACTION $NS/$NAME"

# Render once. `kustomize build --enable-helm` inflates `helmCharts:` entries
# so chart-backed components (ESO, Kyverno) work without a per-component
# pre-apply.sh. File path is stable (under repo .cache/) so subsequent
# retries reuse the render and we don't pollute /tmp across users/hosts.
RENDER_DIR="$CACHE_DIR/renders"
mkdir -p "$RENDER_DIR"
RENDER="$RENDER_DIR/component-${NS}-${NAME}-rendered.yaml"
RENDER_RAW="$RENDER_DIR/component-${NS}-${NAME}-rendered.raw.yaml"
if [[ -f "$COMPONENT_PATH/kustomization.yaml" ]]; then
  echo "    rendering: kustomize build --enable-helm $COMPONENT_PATH"
  kustomize build --enable-helm "$COMPONENT_PATH" > "$RENDER_RAW"
else
  # Plain directory of yaml manifests
  : > "$RENDER_RAW"
  find "$COMPONENT_PATH" -maxdepth 1 -name '*.yaml' -print0 \
    | xargs -0 -I{} sh -c 'cat "{}"; echo "---"' >> "$RENDER_RAW"
fi

# Strip Helm lifecycle hooks. `kustomize build --enable-helm` calls
# `helm template` which by default INCLUDES hook resources (helm.sh/hook
# annotation) — pre-delete, post-upgrade, test, etc. Applying these as plain
# k8s resources via `kubectl apply` runs them imperatively, which is
# catastrophic: e.g. Kyverno's pre-delete `scale-to-zero` Job scales the
# admission-controller Deployment to 0 on first install, and
# `rm-validatingwhconfig` deletes the policy admission webhook config. We
# only want the steady-state resources from each chart.
if grep -q 'helm.sh/hook' "$RENDER_RAW" 2>/dev/null; then
  hook_count=$(yq eval-all 'select(.metadata.annotations."helm.sh/hook" != null)' "$RENDER_RAW" 2>/dev/null | grep -c '^kind:' || true)
  echo "    stripping $hook_count helm hook resource(s) from render"
  yq eval-all 'select(.metadata.annotations."helm.sh/hook" == null)' "$RENDER_RAW" > "$RENDER"
else
  cp "$RENDER_RAW" "$RENDER"
fi

# Pre-apply hook runs BEFORE the main apply. Used by components that cannot be
# expressed as pure kustomize+helm (e.g. metrics-server, which is disabled at
# k3s install time and needs a fresh upstream install + arg injection).
if [[ "$ACTION" == "apply" && -x "$COMPONENT_PATH/pre-apply.sh" ]]; then
  echo "    pre-apply hook detected"
  if ! bash "$COMPONENT_PATH/pre-apply.sh"; then
    echo "    pre-apply FAILED (last error above)" >&2
    exit 2
  fi
fi

# Empty render → component is fully owned by pre-apply.sh (e.g. metrics-server).
if ! grep -qvE '^---$|^[[:space:]]*$' "$RENDER" 2>/dev/null; then
  echo "    render empty — pre-apply hook owns this component, skipping main $ACTION"
  exit 0
fi

if [[ "$ACTION" == "delete" ]]; then
  kubectl delete -f "$RENDER" --ignore-not-found || true
  exit 0
fi

# Strategy-migration guard for Deployments switching to type=Recreate.
#
# Default kubectl/helm-templated Deployments ship with strategy.type=RollingUpdate
# AND populate strategy.rollingUpdate.{maxSurge,maxUnavailable}. When the
# manifest later flips type to Recreate via SSA, kube-apiserver validates the
# MERGED object (our type=Recreate + the prior manager's still-owned
# rollingUpdate sub-fields) and rejects with:
#   The Deployment "<name>" is invalid: spec.strategy.rollingUpdate: Forbidden:
#   may not be specified when strategy `type` is 'Recreate'
# This is a one-shot migration symptom on RE-APPLY (post-nuke installs are
# clean since the deploy doesn't pre-exist). To make in-place re-apply
# converge identically to nuke+reapply, pre-patch any live Deployment whose
# rendered manifest asks for type=Recreate to drop stale rollingUpdate.
# JSON-patch `replace` on /spec/strategy is one atomic op that takes
# ownership of both keys, so subsequent SSA sees a clean field tree.
# Field-validated 2026-05-03 against pushgateway.
if [[ "$ACTION" == "apply" ]] && grep -q 'type: Recreate' "$RENDER" 2>/dev/null; then
  RECREATE_DEPLOYS=$(yq eval-all 'select(.kind == "Deployment" and .spec.strategy.type == "Recreate") | .metadata.namespace + "/" + .metadata.name' "$RENDER" 2>/dev/null || true)
  if [[ -n "$RECREATE_DEPLOYS" ]]; then
    while IFS=/ read -r dep_ns dep_name; do
      [[ -z "${dep_ns:-}" || -z "${dep_name:-}" ]] && continue
      kubectl get deploy "$dep_name" -n "$dep_ns" >/dev/null 2>&1 || continue
      live_ru=$(kubectl get deploy "$dep_name" -n "$dep_ns" -o jsonpath='{.spec.strategy.rollingUpdate}' 2>/dev/null || true)
      if [[ -n "$live_ru" ]]; then
        echo "    strategy-migration: clearing stale rollingUpdate on $dep_ns/$dep_name (Recreate target)"
        kubectl patch deploy "$dep_name" -n "$dep_ns" --type=json \
          -p '[{"op":"replace","path":"/spec/strategy","value":{"type":"Recreate"}}]' >/dev/null 2>&1 || true
      fi
    done <<< "$RECREATE_DEPLOYS"
  fi
fi

# StatefulSet immutable-field migration guard.
#
# StatefulSet spec rejects updates to immutable fields with the api-server
# error:
#   The StatefulSet "<name>" is invalid: spec: Forbidden: updates to
#   statefulset spec for fields other than 'replicas', 'ordinals', 'template',
#   'updateStrategy', 'revisionHistoryLimit', 'persistentVolumeClaimRetentionPolicy'
#   and 'minReadySeconds' are forbidden
# Immutable fields are: selector, serviceName, podManagementPolicy,
# volumeClaimTemplates (entire list including storageClassName / size /
# accessModes per template).
#
# This is a one-shot migration symptom on RE-APPLY (post-nuke installs are
# clean since the sts doesn't pre-exist).  To make in-place re-apply
# converge identically to nuke+reapply, detect drift on any immutable field
# vs the rendered manifest and `kubectl delete --cascade=orphan` the live
# sts first.  Orphan-delete preserves pods AND PVCs; the upcoming apply
# creates a fresh sts which re-adopts pods by selector and re-uses PVCs by
# name (`<vct.name>-<sts.name>-<ordinal>`).
#
# Storage-class migration caveat: PVCs themselves have an immutable
# `spec.storageClassName`.  If volumeClaimTemplates.storageClassName
# changed, this guard orphan-deletes the sts but the existing PVCs stay on
# the old class.  When no PVCs exist for the sts (e.g. fresh deploy or
# pre-cleaned), the new sts provisions PVCs with the new class — fully
# clean migration.  When PVCs do exist on the old class, this guard
# additionally deletes them ONLY IF the sts has zero pods running (i.e.
# `replicas: 0` or all pods already terminated), so data loss is bounded
# to use-cases that already opted into a clean rebuild.  For non-zero
# replicas with storage-class drift the guard fails loud with an
# actionable message rather than silently leaving the cluster on the old
# storage class.
#
# Field-validated 2026-05-19 against
# data-governance/opensearch (longhorn-replicated → local-path migration,
# replicas=0, no PVCs — clean orphan-delete + reapply).
if [[ "$ACTION" == "apply" ]] && grep -q '^kind: StatefulSet$' "$RENDER" 2>/dev/null; then
  STSS=$(yq eval-all 'select(.kind == "StatefulSet") | .metadata.namespace + "/" + .metadata.name' "$RENDER" 2>/dev/null || true)
  while IFS=/ read -r sts_ns sts_name; do
    [[ -z "${sts_ns:-}" || -z "${sts_name:-}" ]] && continue
    kubectl get sts "$sts_name" -n "$sts_ns" >/dev/null 2>&1 || continue

    # Live + rendered fingerprint over the four immutable fields. Both
    # paths normalise through jq -S so key-order differences don't trip the
    # equality check.
    live_fp=$(kubectl get sts "$sts_name" -n "$sts_ns" -o json 2>/dev/null | jq -S '{
      selector: .spec.selector,
      serviceName: .spec.serviceName,
      podManagementPolicy: (.spec.podManagementPolicy // "OrderedReady"),
      vct: [(.spec.volumeClaimTemplates // [])[] | {
        name: .metadata.name,
        storageClassName: (.spec.storageClassName // ""),
        accessModes: (.spec.accessModes // []),
        storage: (.spec.resources.requests.storage // "")
      }]
    }' 2>/dev/null || echo "null")
    render_fp=$(yq eval-all "select(.kind == \"StatefulSet\" and .metadata.namespace == \"$sts_ns\" and .metadata.name == \"$sts_name\") | {
      \"selector\": .spec.selector,
      \"serviceName\": .spec.serviceName,
      \"podManagementPolicy\": (.spec.podManagementPolicy // \"OrderedReady\"),
      \"vct\": [(.spec.volumeClaimTemplates // [])[] | {
        \"name\": .metadata.name,
        \"storageClassName\": (.spec.storageClassName // \"\"),
        \"accessModes\": (.spec.accessModes // []),
        \"storage\": (.spec.resources.requests.storage // \"\")
      }]
    }" "$RENDER" -o json 2>/dev/null | jq -S . 2>/dev/null || echo "null")

    if [[ "$live_fp" == "null" || "$render_fp" == "null" || "$live_fp" == "$render_fp" ]]; then
      continue
    fi

    echo "    sts-migration: immutable-field drift on $sts_ns/$sts_name"
    # storageClassName-specific path needs PVC cleanup too. Detect via the
    # vct[].storageClassName slice of the fingerprint.
    live_scs=$(echo "$live_fp" | jq -r '[.vct[]?.storageClassName] | join(",")')
    render_scs=$(echo "$render_fp" | jq -r '[.vct[]?.storageClassName] | join(",")')
    pvc_drift=0
    if [[ "$live_scs" != "$render_scs" ]]; then
      pvc_drift=1
      echo "      storageClassName drift: live=[$live_scs] render=[$render_scs]"
    fi

    # Refuse to delete PVCs of a running sts. User must scale-zero first.
    live_replicas=$(kubectl get sts "$sts_name" -n "$sts_ns" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
    if (( pvc_drift )) && [[ "${live_replicas:-0}" != "0" ]]; then
      echo "      REFUSING to migrate storageClass on a running sts ($live_replicas replicas)." >&2
      echo "      Scale to zero first:  kubectl scale sts $sts_name -n $sts_ns --replicas=0" >&2
      echo "      Then delete the stale PVCs:  kubectl delete pvc -n $sts_ns -l <sts label>" >&2
      echo "      Then re-run this apply." >&2
      exit 3
    fi

    # Orphan-delete the sts.  Keeps pods (if any) + PVCs.  Fail loud if
    # the delete itself errors — falling through to the apply would re-hit
    # the same `spec: Forbidden` immutable-field rejection and the retry
    # loop would simply mask it as a flaky apply.
    echo "      orphan-deleting sts $sts_ns/$sts_name (keeps pods + PVCs)"
    if ! kubectl delete sts "$sts_name" -n "$sts_ns" --cascade=orphan --wait=true; then
      echo "      ERROR: orphan-delete failed; refusing to retry SSA against drifted immutable spec" >&2
      exit 4
    fi

    # Storage-class migration: delete stale PVCs so the new sts provisions
    # fresh ones on the new class.  Selector matches the vct-derived name
    # pattern `<vct.name>-<sts.name>-<ordinal>` — list and delete by prefix
    # rather than by label (vct PVCs don't always inherit sts labels).
    # Failures here are fatal too — leaving a stale-class PVC bound would
    # silently keep new pods on the old storage class.
    if (( pvc_drift )); then
      vct_names=$(echo "$render_fp" | jq -r '.vct[]?.name')
      while IFS= read -r vct; do
        [[ -z "$vct" ]] && continue
        # Match `<vct>-<sts>-<N>` exactly so we don't catch other PVCs.
        stale_pvcs=$(kubectl get pvc -n "$sts_ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -E "^${vct}-${sts_name}-[0-9]+$" || true)
        for pvc in $stale_pvcs; do
          echo "      deleting stale PVC $sts_ns/$pvc (storageClass drift)"
          if ! kubectl delete pvc "$pvc" -n "$sts_ns" --wait=false; then
            echo "      ERROR: failed to delete stale PVC $sts_ns/$pvc" >&2
            exit 5
          fi
        done
      done <<< "$vct_names"
    fi
  done <<< "$STSS"
fi

# Job immutable-field migration guard.
#
# Job spec.template (and selector / completionMode / completions /
# podFailurePolicy) is immutable after creation.  When a rendered Job's image
# / args / env / resources differ from the live Job (typical post-version-bump
# install-* re-apply case), kube-apiserver rejects the SSA with:
#   The Job "<name>" is invalid: spec.template: Invalid value: ... : field is immutable
#
# Strategy: per Job in render, compare an image+args+env-name+restartPolicy
# fingerprint of live vs rendered template (skipping apiserver-defaulted
# bits like terminationMessagePath / dnsPolicy that would create false-
# positive drift).
#   - No drift: leave alone (SSA is noop / mutable-field-only update).
#   - Drift + live Job in terminal state (status.active==0, Complete or
#     Failed): foreground-delete the Job (cascades to its pods) and let SSA
#     re-create from the render.
#   - Drift + live Job still active (status.active>0): fail loud rather
#     than silently interrupt an in-progress run.
#
# Field-validated 2026-05-19 against data-governance/datahub-upgrade-job
# (image acryldata/datahub-upgrade v1.5.0.1 → v1.5.0.3, status=Failed/
# DeadlineExceeded — clean foreground-delete + reapply).
if [[ "$ACTION" == "apply" ]] && grep -q '^kind: Job$' "$RENDER" 2>/dev/null; then
  JOBS=$(yq eval-all 'select(.kind == "Job") | .metadata.namespace + "/" + .metadata.name' "$RENDER" 2>/dev/null || true)
  fp_filter='{
    containers: [(.spec.template.spec.containers // [])[] | {
      name: .name,
      image: .image,
      args: (.args // []),
      command: (.command // []),
      env_names: ([(.env // [])[] | .name] | sort)
    }],
    initContainers: [(.spec.template.spec.initContainers // [])[] | {
      name: .name,
      image: .image,
      args: (.args // []),
      command: (.command // [])
    }],
    restartPolicy: (.spec.template.spec.restartPolicy // ""),
    backoffLimit: (.spec.backoffLimit // 6),
    completions: (.spec.completions // 1),
    parallelism: (.spec.parallelism // 1),
    completionMode: (.spec.completionMode // "NonIndexed"),
    # Pod-template annotations are part of spec.template and therefore
    # immutable on Job updates.  An annotation-only diff (e.g. adding
    # sidecar.istio.io/inject: "false" to escape an istio-proxy hang) would
    # otherwise slip past the container/env fingerprint and the apply would
    # fail loudly with `spec.template: ... field is immutable`.  Labels are
    # excluded because the Job controller auto-injects batch.kubernetes.io/
    # controller-uid + job-name, which the render does not declare → always
    # false-positive drift.  Field-validated 2026-05-20.
    templateAnnotations: (.spec.template.metadata.annotations // {})
  }'
  while IFS=/ read -r j_ns j_name; do
    [[ -z "${j_ns:-}" || -z "${j_name:-}" ]] && continue
    kubectl get job "$j_name" -n "$j_ns" >/dev/null 2>&1 || continue

    live_fp=$(kubectl get job "$j_name" -n "$j_ns" -o json 2>/dev/null | jq -S "$fp_filter" 2>/dev/null || echo "null")
    render_fp=$(yq eval-all "select(.kind == \"Job\" and .metadata.namespace == \"$j_ns\" and .metadata.name == \"$j_name\")" "$RENDER" -o json 2>/dev/null | jq -S "$fp_filter" 2>/dev/null || echo "null")

    if [[ "$live_fp" == "null" || "$render_fp" == "null" || "$live_fp" == "$render_fp" ]]; then
      continue
    fi

    echo "    job-migration: immutable-field drift on $j_ns/$j_name"
    live_active=$(kubectl get job "$j_name" -n "$j_ns" -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
    live_active="${live_active:-0}"
    if (( live_active > 0 )); then
      echo "      REFUSING to delete an active Job ($live_active pod(s) running)." >&2
      echo "      Investigate manually:  kubectl get job $j_name -n $j_ns" >&2
      echo "      Wait for the run to finish or  kubectl delete job $j_name -n $j_ns  if you accept the interrupt." >&2
      exit 6
    fi

    last_cond=$(kubectl get job "$j_name" -n "$j_ns" -o jsonpath='{.status.conditions[-1].type}' 2>/dev/null || echo "unknown")
    echo "      foreground-deleting Job $j_ns/$j_name (last-condition: $last_cond)"

    # Gated strip of ArgoCD hook finalizer.  Jobs rendered with
    # `argocd.argoproj.io/hook: Sync` (e.g. datahub-upgrade-job) gain an
    # `argocd.argoproj.io/hook-finalizer` from argocd-application-controller
    # when its AppProject reconciler sees the resource.  In kubectl-direct
    # phase-full mode the controller never clears it, so a subsequent
    # `kubectl delete` hangs in Terminating forever.  Only strip when the
    # finalizers list actually contains an argocd.argoproj.io entry so we
    # don't accidentally null another controller's finalizer (e.g. velero).
    # Field-validated 2026-05-19: data-governance/datahub-upgrade-job stuck
    # with `finalizers: [argocd.argoproj.io/hook-finalizer]` until cleared.
    fins=$(kubectl get job "$j_name" -n "$j_ns" -o jsonpath='{.metadata.finalizers}' 2>/dev/null || true)
    if [[ "$fins" == *"argocd.argoproj.io"* ]]; then
      echo "      stripping argocd hook-finalizer on Job $j_ns/$j_name"
      kubectl patch job "$j_name" -n "$j_ns" --type=merge \
        -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
    fi

    if ! kubectl delete job "$j_name" -n "$j_ns" --cascade=foreground --wait=true --timeout=120s; then
      echo "      ERROR: foreground-delete failed; refusing to retry SSA against drifted immutable spec" >&2
      exit 7
    fi
  done <<< "$JOBS"
fi

# Server-side apply with retries:
#   - CRD-before-CR race (chart ships CRDs in same render as CRs)
#   - Webhook-not-ready (cert-manager / kyverno / ESO admission webhooks)
#   - Slow operator boot (controller starts after first apply)
MAX_ATTEMPTS="${MAX_ATTEMPTS:-10}"
DELAY="${DELAY:-10}"

CMD=(kubectl apply --server-side --force-conflicts -f "$RENDER")
echo "    cmd: ${CMD[*]}"
APPLY_OUT="$RENDER_DIR/component-${NS}-${NAME}-apply.out"
# `set -e` is on; tee through process substitution so an apply failure aborts
# the script, but we still capture stdout+stderr for the mid-deletion check.
bash "$ROOT/scripts/retry.sh" "$MAX_ATTEMPTS" "$DELAY" -- "${CMD[@]}" 2>&1 \
  | tee "$APPLY_OUT"

# Partial-nuke defense. SSA exits 0 when a target resource still has a
# `metadata.deletionTimestamp` from a prior tear-down: the new spec is
# accepted, but the finalizer chain completes shortly after and the resource
# vanishes from the cluster. Symptom: kubectl prints
#   "Warning: Detected changes to resource X which is currently being deleted."
# AND `serverside-applied`, then later the resource is gone. Field-observed
# against `cnpg-system/barman-cloud` Service after `make nuke && make
# phase-full` — Service was mid-deletion, SSA accepted the new spec, GC
# finalised the deletion, cnpg-operator booted with no Service → barman
# plugin registration failed → openbao-0 timed out at the StatefulSet
# rollout wait, phase-full halted at install-openbao. Same race shape held
# historically for any operator CRD (pre-ADR-031 longhorn was the canonical
# repro path; the defense is operator-agnostic).
#
# A blind `sleep 30` is fragile: finalizer chains can take >30s when the
# CR-clearing operator was itself just torn down. Better path:
#   1. Parse names of "currently being deleted" resources from APPLY_OUT.
#   2. Poll until each one actually disappears (or 180s deadline). The
#      resources we hit this on are cluster-scoped CRDs, so plain
#      `kubectl get crd <name>` works without -n.
#   3. If anything still lingers, force-strip finalizers (last resort —
#      never block phase-full forever on a wedged finalizer).
#   4. Re-apply. SSA on a clean cluster is idempotent + fast.
if grep -q "currently being deleted" "$APPLY_OUT" 2>/dev/null; then
  echo "    [partial-nuke defense] resources were mid-deletion during apply — waiting for finalize"
  # Pair each "currently being deleted" warning with the IMMEDIATELY FOLLOWING
  # `<kind>[.group]/<name> serverside-applied` line that kubectl prints. SSA
  # always emits these adjacent per-resource (warning, then applied-line for
  # the same resource). awk tracks state across the pair so multiple back-to-
  # back warnings stay correctly bound to their own applied-lines. Result:
  # `<kind>/<name>` tuples that kubectl accepts directly without disambiguation
  # (e.g. `service/barman-cloud`,
  # `flinkdeployment.flink.apache.org/session-cluster`). The prior regex
  # extracted only `<name>` from the warning, which made `kubectl get $name`
  # fall through to a NotFound for namespaced or non-default-kind resources,
  # so the defense exited the wait loop instantly and re-applied while the
  # finalizer was still chained — defeating its own purpose.
  mid_del=$(awk '
    /currently being deleted/ { expect=1; next }
    expect==1 && / serverside-applied$/ { print $1; expect=0; next }
    expect==1 { expect=0 }
  ' "$APPLY_OUT" | sort -u)
  if [[ -n "$mid_del" ]]; then
    # Resolve namespace per tuple from the rendered manifest (kubectl's warning
    # doesn't print the namespace). Match by lowercased kind + name; yq's
    # downcase normalises the YAML `kind` (e.g. "Service", "BackupTarget") to
    # match the shortform kubectl prints before any `.group` suffix.
    declare -A NS_OF
    while IFS= read -r tuple; do
      [[ -z "$tuple" ]] && continue
      kind_full="${tuple%%/*}"
      kind_short="${kind_full%%.*}"
      name="${tuple##*/}"
      ns=$(yq eval-all "
        select((.kind | downcase) == \"$kind_short\" and .metadata.name == \"$name\")
        | (.metadata.namespace // \"\")
      " "$RENDER" 2>/dev/null | head -1)
      [[ "$ns" == "null" ]] && ns=""
      NS_OF[$tuple]="$ns"
    done <<< "$mid_del"

    deadline=$(( $(date +%s) + 180 ))
    still_pending=""
    while (( $(date +%s) < deadline )); do
      still_pending=""
      while IFS= read -r tuple; do
        [[ -z "$tuple" ]] && continue
        ns="${NS_OF[$tuple]:-}"
        if [[ -n "$ns" ]]; then
          kubectl -n "$ns" get "$tuple" >/dev/null 2>&1 && still_pending+=" $tuple"
        else
          kubectl get "$tuple" >/dev/null 2>&1 && still_pending+=" $tuple"
        fi
      done <<< "$mid_del"
      if [[ -z "$still_pending" ]]; then
        echo "        all mid-delete resources finalized"
        break
      fi
      echo "        still terminating:$still_pending"
      sleep 5
    done
    if [[ -n "$still_pending" ]]; then
      echo "        force-stripping finalizers on stragglers:$still_pending"
      for tuple in $still_pending; do
        ns="${NS_OF[$tuple]:-}"
        if [[ -n "$ns" ]]; then
          kubectl -n "$ns" patch "$tuple" --type=merge \
            -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
        else
          kubectl patch "$tuple" --type=merge \
            -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
        fi
      done
      sleep 5
    fi
  fi
  echo "    [partial-nuke defense] re-applying"
  bash "$ROOT/scripts/retry.sh" "$MAX_ATTEMPTS" "$DELAY" -- "${CMD[@]}"
fi

# Post-apply hook runs AFTER the main apply succeeds. Used by components whose
# steady-state requires waiting on a Job/StatefulSet/etc. that is created by
# the apply itself (e.g. openbao-bootstrap Job that seeds OpenBao KV — the
# downstream phase-full steps depend on those secrets existing). Hooks run
# only on `apply`, not `delete`, and only after a successful apply.
if [[ -x "$COMPONENT_PATH/post-apply.sh" ]]; then
  echo "    post-apply hook detected"
  if ! bash "$COMPONENT_PATH/post-apply.sh"; then
    echo "    post-apply FAILED (last error above)" >&2
    exit 2
  fi
fi
