#!/usr/bin/env bash
# =============================================================================
# nuke.sh — DESTRUCTIVE: tear down the whole platform.
# =============================================================================
# Order:
#   1. Scale every workload to 0 (graceful shutdown, NUKE_ALL=1)
#   2. Strip operator-managed CR finalizers (CHI/Kafka/CNPG/ESO/…)
#   3. Delete platform namespaces
#   4. Wait for namespace termination
#   5. Strip stuck PVC/PV finalizers
#   6. Delete platform CRDs + force-finalize stragglers
#   7. Sweep legacy Longhorn artifacts if any survived from pre-ADR-031 cluster
#      (no-op on fresh clusters; safe for forward compatibility)
#   8. Drop orphan webhooks + APIServices
#   9. Flush containerd CRI sandbox/container bookkeeping
#  10. Reclaim leaked host-local CNI IPAM leases
#
# Storage: k3s built-in `local-path` provisioner (ADR-031). PVCs land as
# hostPath bind-mounts under /var/lib/rancher/k3s/storage/. PV reclaimPolicy
# Delete on the SC drops the dir on PVC delete — no extra cleanup needed.
#
# Excluded by default: kube-system, kube-public, kube-node-lease, default.
#
# Usage:
#   nuke.sh                         # confirm prompt
#   FORCE=1 nuke.sh                 # skip confirmation
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Platform namespaces. PVCs release via local-path-provisioner (ADR-031);
# hostPath dirs under /var/lib/rancher/k3s/storage/ are deleted by k3s on
# PVC delete (reclaimPolicy=Delete on local-path SC). No CSI driver namespace
# to keep alive — single pass tear-down.
#
# platform-registry — in-cluster Docker registry (data-ingestion atom installs
# install-registry into its own namespace before kafka-connect's Connect Build
# pushes Debezium+Iceberg images there). Without this entry in nuke, the
# namespace lingers Terminating across runs (deletionTimestamp from prior
# manual delete or a failed Application sync, finalizers waiting on a CRD
# that's already gone) and phase-full's `kubectl create ns platform-registry`
# fails with "namespace is being terminated". Field-observed 2026-05-12.
declare -a PLATFORM_NS=(
  common security storage data-ingestion data-processing data-governance
  model-lifecycle model-serving observability gitops kubeflow
  cnpg-system clickhouse-system cert-manager kyverno keda kueue-system
  knative-serving istio-system external-secrets falco trivy-system
  argo-rollouts spark-operator flink-operator chaos-mesh velero
  tekton-pipelines tekton-pipelines-resolvers
  platform-registry
)

if [[ "${FORCE:-0}" != "1" ]]; then
  echo "WARNING: this will DELETE every namespace below + all platform CRDs."
  printf '  platform ns: '; printf '%s ' "${PLATFORM_NS[@]}"; echo
  read -r -p "Type 'NUKE' to continue: " confirm
  [[ "$confirm" == "NUKE" ]] || { echo "Aborted."; exit 1; }
fi

echo ""
echo "==> Step 1: scale-zero-all (graceful)"
NUKE_ALL=1 bash "$ROOT/scripts/scale-zero-all.sh" || true

# -----------------------------------------------------------------------------
# Step 1.5: pre-nuke CR finalizer scrub.
#
# Operator-managed CRs (CHI/CHK, Kafka*, CNPG Cluster/Backup, KEDA ScaledObject,
# kserve InferenceService, ESO ExternalSecret/PushSecret, cert-manager
# Certificate/Order/Challenge, ArgoCD Application) carry finalizers like
# `finalizer.clickhousekeeperinstallation.altinity.com` that ONLY their owning
# operator can clear. Step 1 (scale-zero-all) intentionally takes those
# operators down; Step 2 then deletes the platform namespaces with
# --wait=false. Result: the CRs sit with deletionTimestamp + uncleared
# finalizer forever, blocking ns termination AND — worst case — surviving
# CRD deletion long enough that `phase-full` resurrects them when the CRD
# is re-applied. The resurrected CR re-enters the operator's deleteCR path
# with deletionTimestamp still set, which is exactly the nil-deref panic
# we hit in clickhouse-operator 0.26.x's deleteCHK
# (`GetRootServiceTemplates` on a CR with no `.spec.templates.serviceTemplates`).
#
# Strip finalizers BEFORE ns/CRD delete so K8s GC can drop the CR cleanly.
# Per-kind list rather than walking every CRD: keeps the scrub bounded and
# avoids stripping finalizers we shouldn't (e.g. cert-manager.io leaf-CA
# finalizers that DO want operator-managed clearing in a non-nuke flow).
# -----------------------------------------------------------------------------
echo ""
echo "==> Step 1.5: pre-nuke CR finalizer scrub (stateful operator CRs)"
declare -a STUCK_KINDS=(
  chi.clickhouse.altinity.com
  chk.clickhouse-keeper.altinity.com
  kafka.kafka.strimzi.io
  kafkatopic.kafka.strimzi.io
  kafkauser.kafka.strimzi.io
  kafkaconnect.kafka.strimzi.io
  kafkaconnector.kafka.strimzi.io
  kafkamirrormaker2.kafka.strimzi.io
  kafkabridge.kafka.strimzi.io
  cluster.postgresql.cnpg.io
  backup.postgresql.cnpg.io
  scheduledbackup.postgresql.cnpg.io
  pooler.postgresql.cnpg.io
  inferenceservice.serving.kserve.io
  trainedmodel.serving.kserve.io
  servingruntime.serving.kserve.io
  application.argoproj.io
  applicationset.argoproj.io
  appproject.argoproj.io
  scaledobject.keda.sh
  scaledjob.keda.sh
  triggerauthentication.keda.sh
  externalsecret.external-secrets.io
  pushsecret.external-secrets.io
  clustersecretstore.external-secrets.io
  certificate.cert-manager.io
  certificaterequest.cert-manager.io
  challenge.acme.cert-manager.io
  order.acme.cert-manager.io
  cleanuppolicy.kyverno.io
  clusterpolicy.kyverno.io
  policy.kyverno.io
  sparkapplication.sparkoperator.k8s.io
  scheduledsparkapplication.sparkoperator.k8s.io
  flinkdeployment.flink.apache.org
  flinksessionjob.flink.apache.org
  rollout.argoproj.io
  experiment.argoproj.io
  analysisrun.argoproj.io
  analysistemplate.argoproj.io
  workflow.argoproj.io
  pipelinerun.tekton.dev
  taskrun.tekton.dev
)
for kind in "${STUCK_KINDS[@]}"; do
  # Walk every namespace, strip finalizers on every CR of this kind.
  # `kubectl get <unknown-kind> -A` returns empty when the CRD is absent,
  # so jq emits nothing and the inner loop is a natural no-op — no need
  # for an upfront `kubectl get crd "$kind"` check (which would require
  # the full plural-CRD-object-name `kafkas.kafka.strimzi.io` etc., not
  # the short forms `kafka`/`chi`/`chk`/`cluster` that `kubectl get` is
  # happy to resolve via the discovery cache).
  # --type=merge replaces .metadata.finalizers wholesale; safe even if list
  # is already empty.
  #
  # Wrap the whole sub-pipeline in `|| true` so transient apiserver hiccups
  # (kubectl get non-zero under IO pressure / retry storm) don't make the
  # outer `set -e` bail mid-scrub. Pipefail+set-e otherwise propagates a
  # single failed `kubectl get` to script exit, leaving Steps 2-11 unrun.
  {
    kubectl get "$kind" -A -o json 2>/dev/null \
      | jq -r '.items[]? | "\(.metadata.namespace // "_cluster") \(.metadata.name)"' \
      | while read -r cr_ns cr_name; do
          [[ -z "${cr_name:-}" ]] && continue
          if [[ "$cr_ns" == "_cluster" ]]; then
            kubectl patch "$kind" "$cr_name" \
              --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
          else
            kubectl -n "$cr_ns" patch "$kind" "$cr_name" \
              --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
          fi
          echo "    stripped finalizer: $kind/$cr_name (ns=$cr_ns)"
        done
  } || true
done

echo ""
echo "==> Step 2: delete platform namespaces"
for ns in "${PLATFORM_NS[@]}"; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then
    echo "    delete ns/$ns"
    kubectl delete ns "$ns" --ignore-not-found --wait=false --timeout=10s || true
  fi
done

echo ""
echo "==> Step 3: delete platform CRDs (best-effort)"
declare -a CRD_GROUPS=(
  argoproj.io
  cert-manager.io acme.cert-manager.io
  cnpg.io postgresql.cnpg.io
  kafka.strimzi.io
  clickhouse.altinity.com clickhouse-keeper.altinity.com
  external-secrets.io generators.external-secrets.io
  flink.apache.org sparkoperator.k8s.io
  serving.knative.dev networking.internal.knative.dev autoscaling.internal.knative.dev caching.internal.knative.dev messaging.knative.dev
  serving.kserve.io inference.kserve.io
  monitoring.coreos.com
  grafana.integreatly.org
  keda.sh eventing.keda.sh
  kueue.x-k8s.io
  istio.io networking.istio.io security.istio.io install.istio.io extensions.istio.io telemetry.istio.io
  kyverno.io policies.kyverno.io reports.kyverno.io
  trivy-operator.aquasec.com
  velero.io
  policy.kruise.io apps.kruise.io
  tekton.dev triggers.tekton.dev resolution.tekton.dev
  chaos-mesh.org
  apisix.apache.org
  events.bitnami.com
  falco.org
  vault.banzaicloud.com
  pkg.crossplane.io
  capabilities.spicedb.dev
  helm.toolkit.fluxcd.io source.toolkit.fluxcd.io kustomize.toolkit.fluxcd.io notification.toolkit.fluxcd.io
  rollouts.argoproj.io
  snapshot.storage.k8s.io
  jobset.x-k8s.io trainer.kubeflow.org
)

# Wrap each group's pipeline in `{ ... } || true` so pipefail-propagated
# kubectl/awk/SIGPIPE failures never bail the whole nuke (Step 3 is best-effort
# — a missing CRD or transient API blip must not abort cleanup that still has
# Steps 4-12 to run).
for g in "${CRD_GROUPS[@]}"; do
  {
    kubectl get crd 2>/dev/null \
      | awk -v g="$g" '$1 ~ "\\."g"$" {print $1}' \
      | while read -r crd; do
          [[ -z "$crd" ]] && continue
          echo "    delete crd/$crd"
          kubectl delete crd "$crd" --ignore-not-found --wait=false --timeout=10s 2>/dev/null || true
        done
  } || true
done

echo ""
echo "==> Step 4: wait for platform namespace termination (max 5 min)"
deadline=$(( $(date +%s) + 300 ))
while [[ $(date +%s) -lt $deadline ]]; do
  remaining=0
  for ns in "${PLATFORM_NS[@]}"; do
    kubectl get ns "$ns" >/dev/null 2>&1 && remaining=$((remaining+1))
  done
  [[ $remaining -eq 0 ]] && break
  echo "    $remaining platform namespaces still terminating..."
  sleep 10
done

# Strip finalizers from stuck PVCs/PVs (CSI may have already detached but
# finalizer not cleared). Best-effort.
echo ""
echo "==> Step 5: strip finalizers on any stuck PVC/PV/namespace"
for ns in "${PLATFORM_NS[@]}"; do
  kubectl get ns "$ns" >/dev/null 2>&1 || continue
  for pvc in $(kubectl -n "$ns" get pvc -o name 2>/dev/null); do
    echo "    strip finalizer $pvc -n $ns"
    kubectl -n "$ns" patch "$pvc" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
  done
  echo "    strip finalizer ns/$ns"
  kubectl get ns "$ns" -o json 2>/dev/null \
    | jq '.spec.finalizers=[]' \
    | kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f - >/dev/null 2>&1 || true
done
for pv in $(kubectl get pv -o name 2>/dev/null); do
  status=$(kubectl get "$pv" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [[ "$status" == "Released" || "$status" == "Failed" ]]; then
    echo "    strip finalizer $pv (status=$status)"
    kubectl patch "$pv" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    kubectl delete "$pv" --ignore-not-found --wait=false 2>/dev/null || true
  fi
done

# -----------------------------------------------------------------------------
# Step 6: sweep LEGACY Longhorn + snapshot-controller artifacts.
#
# Pre-ADR-031 clusters carried longhorn-system (CSI driver, manager, engine,
# replica) + snapshot-controller (kube-system, external-snapshotter v8.x).
# Both removed from the platform manifest tree, but a forward-compatible nuke
# must still erase any residue from a cluster bootstrapped before the
# migration — otherwise leftover CRs/CRDs trap PVC release and orphan
# webhooks reject new apply.
#
# Idempotent: every loop is a natural no-op on a fresh / already-migrated
# cluster (kubectl get on absent CRD returns empty, ns/cluster-role delete
# with --ignore-not-found is silent).
# -----------------------------------------------------------------------------
echo ""
echo "==> Step 6: sweep legacy Longhorn + snapshot-controller artifacts"
# Longhorn CRs (clear finalizers, then delete)
for kind in volumes engines replicas backingimages backingimagedatasources \
            backingimagemanagers backuptargets backupvolumes backups \
            recurringjobs sharemanagers nodes engineimages instancemanagers \
            orphans settings supportbundles systembackups systemrestores \
            volumeattachments; do
  {
    kubectl -n longhorn-system get "${kind}.longhorn.io" -o name 2>/dev/null \
      | while read -r r; do
          kubectl -n longhorn-system patch "$r" --type=json \
            -p='[{"op":"replace","path":"/metadata/finalizers","value":[]}]' 2>/dev/null || true
          kubectl -n longhorn-system delete "$r" --ignore-not-found --wait=false 2>/dev/null || true
        done
  } || true
done
kubectl delete ns longhorn-system --ignore-not-found --wait=false --timeout=30s 2>/dev/null || true
{
  kubectl get crd 2>/dev/null | awk '/\.longhorn\.io$/ {print $1}' \
    | while read -r crd; do
        kubectl delete crd "$crd" --ignore-not-found --wait=false --timeout=10s 2>/dev/null || true
      done
} || true
# Wait + force-finalize longhorn-system if stuck
deadline=$(( $(date +%s) + 60 ))
while kubectl get ns longhorn-system >/dev/null 2>&1 && [[ $(date +%s) -lt $deadline ]]; do
  sleep 5
done
if kubectl get ns longhorn-system >/dev/null 2>&1; then
  kubectl get ns longhorn-system -o json 2>/dev/null \
    | jq '.spec.finalizers=[]' \
    | kubectl replace --raw "/api/v1/namespaces/longhorn-system/finalize" -f - >/dev/null 2>&1 || true
fi
# snapshot-controller in kube-system (kube-system not in PLATFORM_NS sweep)
{
  kubectl -n kube-system delete deployment snapshot-controller --ignore-not-found --wait=false 2>/dev/null || true
  kubectl -n kube-system delete serviceaccount snapshot-controller --ignore-not-found --wait=false 2>/dev/null || true
  kubectl delete clusterrole snapshot-controller-runner --ignore-not-found --wait=false 2>/dev/null || true
  kubectl delete clusterrolebinding snapshot-controller-role --ignore-not-found --wait=false 2>/dev/null || true
  kubectl -n kube-system delete role snapshot-controller-leaderelection --ignore-not-found --wait=false 2>/dev/null || true
  kubectl -n kube-system delete rolebinding snapshot-controller-leaderelection --ignore-not-found --wait=false 2>/dev/null || true
} || true

echo ""
echo "==> Step 7: strip stuck CRDs (force-finalize)"
{
  kubectl get crd 2>/dev/null | awk 'NR>1 && $1 !~ /\.cattle\.io$/ {print $1}' \
    | while read -r c; do
        kubectl patch crd "$c" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
        kubectl delete crd "$c" --ignore-not-found --wait=false 2>/dev/null || true
      done
} || true

# -----------------------------------------------------------------------------
# Step 7.5: wait until no platform CRD has a deletionTimestamp.
#
# `kubectl delete crd ... --wait=false` (Step 3 + 6 + 7 above) returns the
# moment the apiserver records the deletion intent — but GC may take 10-60s
# to drop the CRD object once finalizers clear. If the next phase-full apply
# fires while a CRD still has deletionTimestamp set, SSA accepts the new
# spec WITH a warning ("Detected changes to resource X which is currently
# being deleted"), then GC finalises the deletion, removing the CRD AND
# every CR + every controller informer subscribed to it. Same race holds
# for any operator CRD; wait for the sweep to converge before phase-full.
#
# Fix: poll the platform CRD list and exit only once all are GONE (not just
# `deletionTimestamp` set — fully gone). 180s deadline covers slow
# finalizer chains (operator missing, finalizer-clearing already null'd in
# Step 7 above so this should converge in well under 30s in practice).
# -----------------------------------------------------------------------------
echo ""
echo "==> Step 7.5: wait for platform CRD termination (deadline 180s)"
# Apiserver returns 503 ServiceUnavailable mid-nuke under kine WAL pressure
# (bulk CRD delete generates ~250 writes/s).  Two-stage capture: first fetch
# the raw CRD list into a var so kubectl failure is detected directly; on
# failure log + sleep + continue (do NOT capture pipe output, that produced
# stacked "0\n999" tokens that broke `[[ -eq 0 ]]` on 2026-05-14).  Only when
# the kubectl call succeeds do we run the awk|wc filter.
deadline=$(( $(date +%s) + 180 ))
while (( $(date +%s) < deadline )); do
  if ! crd_list=$(kubectl get crd 2>/dev/null); then
    echo "    apiserver unavailable (503), waiting..."
    sleep 5
    continue
  fi
  remaining=$(printf '%s\n' "$crd_list" \
    | awk 'NR>1 && $1 !~ /\.cattle\.io$/ && $1 !~ /^addons\.k3s\.cattle\.io$/' \
    | wc -l)
  if [[ "$remaining" -eq 0 ]]; then
    echo "    all platform CRDs fully terminated"
    break
  fi
  echo "    $remaining CRD(s) still terminating..."
  sleep 5
done
# If anything still lingers, force-strip finalizers one more time so
# downstream apply doesn't hit the resurrection race.  Same two-stage
# capture: skip the force-strip pass entirely if apiserver still 503s.
if crd_list=$(kubectl get crd 2>/dev/null); then
  remaining=$(printf '%s\n' "$crd_list" | awk 'NR>1 && $1 !~ /\.cattle\.io$/ {print $1}')
else
  remaining=""
fi
if [[ -n "$remaining" ]]; then
  echo "    forcibly clearing finalizers on stragglers:"
  for c in $remaining; do
    echo "      $c"
    kubectl patch crd "$c" --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
    kubectl delete crd "$c" --ignore-not-found --wait=true --timeout=30s 2>/dev/null || true
  done
fi

echo ""
echo "==> Step 8: drop orphan webhook configurations"
kubectl get validatingwebhookconfigurations -o name 2>/dev/null \
  | grep -vE 'k3s|cattle' | xargs -r kubectl delete --ignore-not-found 2>/dev/null || true
kubectl get mutatingwebhookconfigurations -o name 2>/dev/null \
  | grep -vE 'k3s|cattle' | xargs -r kubectl delete --ignore-not-found 2>/dev/null || true

echo ""
echo "==> Step 9: drop orphan APIServices (extension APIs)"
kubectl get apiservice -o name 2>/dev/null \
  | grep -vE 'v1\.apps|v1\.authentication|v1\.authorization|v1\.autoscaling|v1\.batch|v1\.certificates|v1\.coordination|v1\.discovery|v1\.events|v1\.networking|v1\.node|v1\.policy|v1\.rbac|v1\.scheduling|v1\.storage|v1\.flowcontrol|v1\.admissionregistration|v1\.apiextensions|v1\.apiregistration|v1\.k3s\.cattle|cattle\.io' \
  | xargs -r kubectl delete --ignore-not-found 2>/dev/null || true

echo ""
echo "==> Step 10: drop legacy non-built-in StorageClasses"
# k3s built-in `local-path` SC is owned by k3s and must NOT be deleted (it's
# auto-recreated on next k3s start anyway, but the gap breaks any concurrent
# PVC bind). Drop only the pre-ADR-031 longhorn-* classes; harmless no-op
# on fresh clusters.
kubectl delete sc longhorn longhorn-backup longhorn-fast longhorn-replicated longhorn-static --ignore-not-found 2>/dev/null || true

# -----------------------------------------------------------------------------
# Step 11: flush containerd CRI bookkeeping (sandbox + container reservations).
#
# Why this exists:
#   k3s embeds containerd. Containerd's CRI shim keeps in-memory state for
#   every container/sandbox it has ever created on the host: the name, its
#   container-ID, and the lifecycle state (CREATED, RUNNING, EXITED, REMOVING).
#   `--wait=false` deletes from Steps 2/3/6/7 above tell the apiserver "drop
#   the K8s objects" — but kubelet's CRI calls to actually stop+remove the
#   underlying containers race with the apiserver work, and on a cluster
#   under IO pressure (PSI io >70% during nuke is common with Longhorn
#   detach) some of those CRI removes get stuck in a "removing state" that
#   never converges. The exited container record AND its reserved name stay
#   alive in containerd's bookkeeping forever (until containerd restart).
#
#   Field-observed 2026-05-09: after `make nuke && make phase-full`, 30+
#   pods stuck ContainerCreating/CreateContainerError across knative-serving,
#   model-lifecycle, data-processing, data-ingestion. k3s journal shows:
#     "failed to reserve sandbox name '<pod-A>_<ns>_<podUID>_0':
#      name '<pod-A>_<ns>_<podUID>_0' is reserved for '<old-container-ID>'"
#     "failed to set removing state for container '<id>':
#      container is already in removing state"
#   The reservation belonged to a dead container from the prior nuke cycle
#   that crictl rm -f cannot dislodge (already-removing). Phase-full's
#   knative pre-apply waited 25 min for `webhook` rollout, exited 2.
#
# What this hook does:
#   1. `crictl rm` every container in EXITED state. Frees the
#      "container_<name>_<podUID>_<attempt>" reservation. The "already in
#      removing state" subset is silently ignored — they require containerd
#      restart, which we escalate to in the next bullet.
#   2. `crictl rmp` every sandbox in NOTREADY state. Frees the
#      "<pod>_<ns>_<podUID>_0" sandbox-name reservation. Job pods that
#      completed (CronJob runs, *-bootstrap Jobs) are the typical residents.
#   3. If after the prune the EXITED count is non-zero AND we see at least
#      one "removing state" sticky entry, do a `systemctl restart k3s`. This
#      is the only cure for a stuck-in-removing container record. It's
#      disruptive (~30s downtime for kube-apiserver/kubelet) but on a
#      single-node nuked cluster there is nothing actually serving traffic
#      to disrupt — every workload is already gone.
#
#   Idempotent: on a clean nuke (no stragglers) every loop is a no-op and
#   the entire step finishes in <2s. ~30s when the prune actually fires.
# -----------------------------------------------------------------------------
echo ""
echo "==> Step 11: flush containerd CRI bookkeeping (stale sandbox/container reservations)"
if command -v crictl >/dev/null 2>&1; then
  exited_before=$(sudo crictl ps -a --state exited -q 2>/dev/null | wc -l || echo 0)
  notready_before=$(sudo crictl pods --state notready -q 2>/dev/null | wc -l || echo 0)
  echo "    before: $exited_before exited container(s), $notready_before notready sandbox(es)"

  # Remove exited containers; collect "already in removing state" stickies.
  # awk over grep -c: grep -c on no-match returns exit 1 + prints "0", and the
  # `|| echo 0` recovery layer then concatenates a second "0", producing the
  # multi-line value "0\n0" that `[[ -gt 0 ]]` blows up on. awk emits exactly
  # one integer regardless of input.
  rm_log=$(mktemp)
  sudo crictl ps -a --state exited -q 2>/dev/null \
    | xargs -r -n1 sudo crictl rm -f 2>"$rm_log" >/dev/null || true
  stuck_removing=$(awk '/already in removing state/ {c++} END {print c+0}' "$rm_log" 2>/dev/null || echo 0)
  rm -f "$rm_log"

  # Remove notready sandboxes (Job pods done, etc.).
  sudo crictl pods --state notready -q 2>/dev/null \
    | xargs -r -n1 sudo crictl rmp -f 2>/dev/null >/dev/null || true

  exited_after=$(sudo crictl ps -a --state exited -q 2>/dev/null | wc -l || echo 0)
  notready_after=$(sudo crictl pods --state notready -q 2>/dev/null | wc -l || echo 0)
  echo "    after:  $exited_after exited container(s), $notready_after notready sandbox(es)"

  # Escalate to k3s restart only if we hit the unfixable-by-crictl path.
  # `stuck_removing>0 && exited_after>0` means containerd's in-memory state
  # is wedged; the ONLY recovery is to bounce the daemon. Skip when
  # `KEEP_K3S=1` is set (debugging from inside the cluster, etc.).
  if [[ "$stuck_removing" -gt 0 && "$exited_after" -gt 0 && "${KEEP_K3S:-0}" != "1" ]]; then
    echo "    detected $stuck_removing container(s) wedged in 'removing state' — restarting k3s to flush"
    if sudo systemctl restart k3s 2>&1; then
      echo "    waiting up to 90s for kube-apiserver to come back"
      deadline=$(( $(date +%s) + 90 ))
      while (( $(date +%s) < deadline )); do
        if kubectl get --raw /readyz >/dev/null 2>&1; then
          echo "    apiserver Ready"
          break
        fi
        sleep 3
      done
    else
      echo "    WARN: systemctl restart k3s failed; continuing without flush" >&2
    fi
  fi
else
  echo "    crictl not on PATH — skip (k3s embeds it; check /var/lib/rancher/k3s/data/current/bin/)"
fi

# -----------------------------------------------------------------------------
# Step 12: reclaim host-local CNI IPAM lease files (flannel /var/lib/cni)
# -----------------------------------------------------------------------------
# Why this exists:
#   k3s' default CNI is flannel + host-local IPAM. host-local writes one file
#   per allocated pod IP under /var/lib/cni/networks/cbr0/<10.42.x.y>. The
#   file contains the container ID and pod metadata. Release is triggered by
#   the CNI DEL plugin call kubelet issues when a sandbox is torn down.
#
#   On nuke-scale churn (Step 2/3/6/7 batch delete; Step 11 crictl rmp), some
#   DEL calls race with sandbox removal and silently no-op. Each leak burns
#   one IP from the /24 range. After 1–2 nuke cycles, the lease file count
#   can exceed live pod IPs by 50–100. Eventually the range is exhausted
#   and all NEW pod sandboxes fail with:
#       failed to allocate for range 0: no IP addresses available in
#       range set: 10.42.0.1-10.42.0.254
#   Field-observed 2026-05-15: post-nuke phase-full had 127 stale leases
#   out of 254 slots; new use-case-crypto pods could not get IPs.
#
# What this hook does:
#   1. Enumerate live pod IPs from the apiserver (.status.podIP).
#   2. Enumerate lease files matching ^10\.42\..*\.\.*$ in the IPAM dir.
#   3. Delete every lease whose IP is NOT in the live-pod set.
#
#   Skipped silently if /var/lib/cni/networks/cbr0/ doesn't exist (different
#   CNI installed, or a clean host pre-bootstrap). Idempotent — re-runs on
#   a clean state do nothing.
# -----------------------------------------------------------------------------
echo ""
echo "==> Step 12: reclaim leaked host-local CNI IPAM leases"
CNI_DIR=/var/lib/cni/networks/cbr0
if sudo test -d "$CNI_DIR"; then
  live_tmp=$(mktemp)
  lease_tmp=$(mktemp)
  kubectl get pod -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null \
    | awk '/^10\.42\./' | sort -u > "$live_tmp"
  sudo ls "$CNI_DIR" 2>/dev/null | awk '/^10\.42\./' | sort -u > "$lease_tmp"
  total_leases=$(wc -l < "$lease_tmp")
  total_live=$(wc -l < "$live_tmp")
  stale_count=0
  while IFS= read -r ip; do
    if [[ -n "$ip" ]]; then
      sudo rm -f "$CNI_DIR/$ip" 2>/dev/null && stale_count=$((stale_count + 1)) || true
    fi
  done < <(comm -23 "$lease_tmp" "$live_tmp")
  rm -f "$live_tmp" "$lease_tmp"
  echo "    leases=$total_leases live_pod_ips=$total_live reclaimed=$stale_count"
else
  echo "    $CNI_DIR not present — skip (non-flannel CNI?)"
fi

echo ""
echo "==> Done. Final state:"
echo "Namespaces:"; kubectl get ns 2>/dev/null | awk 'NR>1 {print "  ", $1, $2}'
echo "Pods (kube-system only):"; kubectl -n kube-system get pods --no-headers 2>/dev/null | awk '{print "  ", $1, $3}'
echo "PVs:"; kubectl get pv --no-headers 2>/dev/null | wc -l | awk '{print "  ", $1, "pv(s)"}'
echo "CRDs (non-k3s):"; kubectl get crd 2>/dev/null | awk 'NR>1 && $1 !~ /\.cattle\.io$/' | wc -l | awk '{print "  ", $1, "crd(s)"}'
echo "Webhooks:"; kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations --no-headers 2>/dev/null | wc -l | awk '{print "  ", $1, "webhook(s)"}'
echo "StorageClasses:"; kubectl get sc 2>/dev/null | awk 'NR>1 {print "  ", $1}'
