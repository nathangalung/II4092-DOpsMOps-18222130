#!/usr/bin/env bash
# =============================================================================
# cnpg/pre-apply.sh — install CNPG + barman-cloud plugin CRDs via SSA before
# the main kustomize render lands.
# =============================================================================
# Why this exists:
#   CNPG ships two CRDs whose JSON-schema bodies exceed the
#   `kubectl.kubernetes.io/last-applied-configuration` 262144-byte annotation
#   limit:
#     clusters.postgresql.cnpg.io  — 452 KB schema
#     poolers.postgresql.cnpg.io   — 649 KB schema
#
#   apply-component.sh already uses `kubectl apply --server-side
#   --force-conflicts` (SSA writes managedFields, not the legacy annotation)
#   so the local make path is fine.
#
#   Argo CD 3.3.6, however, falls back to CSA (`kubectl replace --force`) when
#   `syncStrategy.apply.force: true` is set on a sync operation — which our
#   AppSet template enables for self-healing. CSA writes the legacy
#   last-applied-configuration annotation, blows past 262144 bytes, the apply
#   errors with "metadata.annotations: Too long: must have at most 262144
#   bytes", and Argo then **prunes** the CRD it failed to update. Downstream
#   carnage: every CNPG `Cluster` and `Pooler` CR disappears (e.g. postgresql
#   in storage ns); `postgresql-app` Secret never re-emits; every consumer
#   that mounts it (DataHub, MLflow, Lakekeeper, etc.) stalls.
#
# Fix:
#   1. Disable chart's `crds.create` so neither the local render nor Argo's
#      render contains the CRDs in the apply-target set (no SSA-vs-CSA path
#      divergence possible).
#   2. This hook reads the chart's `templates/crds/crds.yaml` files directly,
#      strips the `{{- if .Values.crds.create }}` / `{{- end }}` wrapper
#      lines (the only Go-template tokens in those files), and applies the
#      result with `kubectl apply --server-side --force-conflicts`. Pure SSA,
#      no annotation, no size cap.
#
#   The CRDs are now "platform-managed by apply-component.sh", not Argo. On
#   `make phase-base` they install via this hook before the CNPG operator
#   Deployment lands; on `make nuke` they tear down via the kustomize-managed
#   sync (Argo no longer claims them, but they get GC'd by the operator's
#   `helm.sh/resource-policy: keep` only if the chart explicitly says so —
#   field-verified the CRDs have that annotation, so they survive helm
#   uninstall, which matches the behaviour we want for stateful Cluster CRs).
#
# Idempotent: SSA does an upsert, so subsequent runs are no-op when CRDs are
# already current.
# =============================================================================
set -euo pipefail

CHART_ROOT="$(cd "$(dirname "$0")/charts" && pwd)"
CNPG_CRDS="$CHART_ROOT/cloudnative-pg-0.28.0/cloudnative-pg/templates/crds/crds.yaml"
BARMAN_CRDS="$CHART_ROOT/plugin-barman-cloud-0.6.0/plugin-barman-cloud/templates/crds/crds.yaml"

for f in "$CNPG_CRDS" "$BARMAN_CRDS"; do
  if [[ ! -f "$f" ]]; then
    echo "    [pre-apply] FATAL: CRD source missing: $f" >&2
    exit 1
  fi
done

TMP="$(mktemp -t cnpg-crds.XXXXXX.yaml)"
trap 'rm -f "$TMP"' EXIT

# Strip the single-line helm gate (`{{- if .Values.crds.create }}` at the top
# and `{{- end }}` at the bottom) from both chart files and concat into one
# render. sed '/^{{/d' is sufficient — there are no other Go-template tokens
# anywhere in either file (field-verified).
{
  sed '/^{{/d' "$CNPG_CRDS"
  echo "---"
  sed '/^{{/d' "$BARMAN_CRDS"
} > "$TMP"

echo "    [pre-apply] installing CNPG + barman-cloud CRDs via SSA ($(wc -c < "$TMP") bytes)"
kubectl apply --server-side --force-conflicts -f "$TMP" >/dev/null

# Block until at least the two large CRDs are Established. The CNPG operator
# Deployment that the main apply lands needs them ready; without this wait,
# the operator container can race the CRD watch and crash-loop until the
# kube-apiserver's CRD discovery refresh ticks (often 60-120s).
for crd in clusters.postgresql.cnpg.io poolers.postgresql.cnpg.io \
           backups.postgresql.cnpg.io scheduledbackups.postgresql.cnpg.io; do
  if ! kubectl wait --for=condition=Established "crd/$crd" --timeout=120s >/dev/null 2>&1; then
    echo "    [pre-apply] WARNING: $crd not Established within 120s — continuing" >&2
  fi
done

echo "    [pre-apply] CRDs installed + Established"
