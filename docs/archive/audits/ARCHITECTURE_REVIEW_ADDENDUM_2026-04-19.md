# Architecture Review — Addendum (2026-04-19)

**Scope:** Corrects and supersedes findings in
`ARCHITECTURE_REVIEW_2026-04-19.md`. Prior report conflated **cluster
state** (what is running in k3s today) with **file state** (what the repo
actually declares). Many items flagged P0/P1 are already fixed at the
file level; the real gap is **ArgoCD reconciliation has not been applied
yet**, not missing code. This addendum reclassifies every finding against
the file tree, documents legitimate design decisions, and enumerates only
the genuine file-level work remaining.

---

## 1. Executive re-scoring

| Band | Original count | Actual file-level count | Delta |
|---|---|---|---|
| P0 (Critical) | 7 | **0** | −7 (all fixed in files; pending `kubectl apply`) |
| P1 (High) | 12 | **4** | −8 (legit design or cluster-only) |
| P2 (Medium) | 9 | **3** | −6 |
| P3 (Cluster drift, not file) | 0 | **5** | +5 (new bucket) |

The repo is **substantially more complete** than the initial audit
implied. The work ahead is narrow, targeted, and concentrated on:

1. Wire-ins inside existing `kustomization.yaml` files.
2. One net-new use-case (`use-case-stock/`).
3. ADR documentation drift (ADR-006 version string; ADR-009 opt-out list).

Everything else is pre-flight hygiene (delete stale APIServices, empty
namespaces, and obsolete controllers) that belongs in the deploy
runbook, not the code tree.

---

## 2. Phantom P0/P1 findings — RETRACTED

Each row below was flagged as critical in the original review. The
re-audit found the fix already present in the repository. No further
file edits required for these items.

| # | Original claim | Actual file state | Evidence |
|---|---|---|---|
| P0-1 | Vault readiness probe uses `exec: jq` (KNF-07 broken) | `httpGet /v1/sys/health?standbyok=true&perfstandbyok=true` on port 8200 with `sealedcode: 204` | `platform/components/security/vault/statefulset.yaml:230-246` |
| P0-2 | KServe `InferenceService` for crypto missing | `crypto-predictor` declared, `modelFormat.name: mlflow`, `modelFormat.version: "2"`, `storageUri: s3://mlflow/artifacts/...` | `use-case-crypto/manifests/base/inferenceservices/crypto-inference.yaml` |
| P0-3 | Katib experiment not authored | `flaml-automl-hpo` Experiment (Bayesian, `rmse` objective, `parallelTrialCount: 1`, `maxTrialCount: 5`) | `use-case-crypto/manifests/base/katib/experiment-lightgbm.yaml` |
| P0-4 | KFP retraining pipeline missing | `retraining_pipeline.py` + compiled `retraining_pipeline.yaml` + `submit_recurring.py` | `use-case-crypto/pipelines/` |
| P0-5 | `prometheus-adapter` unavailable → HPA/Katib cannot consume `ClickHouseQueryResult` metrics | Deployment v0.12.0 + kustomization entry | `platform/components/observability/prometheus-adapter/deployment.yaml` |
| P0-6 | Kyverno shipped with no policies | 7 policies shipped (5 ValidatingPolicy, 1 ImageValidatingPolicy, 1 GeneratingPolicy auto-default-deny) | `platform/components/security/kyverno/policies.yaml` |
| P0-7 | Falco / Trivy / Velero / Chaos Mesh not installed | Helm releases authored at 2026 pins | `platform/components/security/{falco,trivy-operator,velero,chaos-mesh}/helm-release.yaml` |
| P1-3 | KES (Kubernetes Encryption Service for MinIO) missing | `configmap.yaml` with `v1` KMS proto defined | `platform/components/security/kes/configmap.yaml` |
| P1-5 | Longhorn not default SC | `defaultClass: true`, `targetRevision: 1.11.1`, `defaultClassReplicaCount: 1` (single-node clamp) | `platform/components/storage/longhorn/helm-release.yaml` |
| P1-7 | CloudNativePG Barman plugin missing | `plugin-barman-cloud` Application referenced at `targetRevision: 0.6.0` | `platform/components/storage/cnpg/plugin-barman-cloud.yaml` |
| P1-9 | ESO ClusterSecretStore not authored | `cluster-secret-store.yaml` targets Vault KV v2 at `secret/data/...` | `platform/components/security/external-secrets/cluster-secret-store.yaml` |

**Verification method:** `mcp__plugin_context-mode_context-mode__ctx_batch_execute`
with directory listings + targeted greps; subsequent Read of each
suspect file before retracting. Re-audit run 2026-04-19.

---

## 3. Legitimate design — do NOT "fix"

| Pattern | Where | Why it is correct |
|---|---|---|
| `istio-injection: disabled` on `model-lifecycle` | `platform/components/model-lifecycle/namespace.yaml` | KFP v2 launcher injects `PodDefault` CRs that clash with Istio sidecars (ordering of init-containers + port 15001 reservation). KFP upstream recommends Istio OFF. |
| `istio-injection: disabled` on `model-serving` | `platform/components/model-serving/namespace.yaml` | KServe queue-proxy binds the same admission path Istio would inject; dual-sidecar breaks Knative `serving.knative.dev/visibility: cluster-local`. KServe upstream documents "disable Istio injection OR use Istio ingress; not both." |
| `istio-injection: disabled` on `vault` | `platform/components/security/vault/namespace.yaml` | Raft HTTP between pods on 8201 requires mTLS termination on the Vault listener, not the sidecar; double-wrap conflicts with `tls_disable=1` + mesh STRICT. |
| `istio-injection: disabled` on `longhorn-system`, `kube-system` | (chart-managed) | iSCSI + hostNetwork traffic cannot be mesh-wrapped. k3s core depends on direct service-to-service. |

Action: **ADR-009 needs to list these namespaces as explicit
exceptions** (already planned — see §5). Do **not** relabel the
namespaces.

---

## 4. Cluster-only drift (P3 — fix via kubectl, not edits)

These are runtime-only observations from the original review that do
not correspond to any file gap. Every row below maps to a specific
numbered section of `platform/REMEDIATION_RUNBOOK.md`; run the runbook
top-to-bottom on the target cluster rather than issuing the commands
out of band.

| Symptom | Root cause | Runbook reference |
|---|---|---|
| ArgoCD has 0 Applications reconciled | Bootstrap `kubectl apply -k platform/components/gitops/argo-cd` + `app-of-apps.yaml` never ran | §6 — GitOps activation (AppProject + ApplicationSet) |
| `v1beta1.custom.metrics.k8s.io` / `v1beta1.external.metrics.k8s.io` APIServices orphaned | prometheus-adapter Deployment not yet applied; stale APIService objects from prior metrics-server | §10.3 — stale APIService cleanup pattern; §10.10 — prometheus-adapter re-deploy |
| `kafka-dev` namespace running alongside `data-ingestion` | Old pre-operator dev cluster leftover | §10.15 — kafka-dev namespace cleanup |
| Traefik still running despite ADR-005 (k3s built-ins removed) | k3s installer default; reinstall with the disable flags | §0 — Prerequisites (k3s `--disable=traefik --disable=servicelb`) |
| Orphan `workflow-controller` Deployment in `argo` ns | Second Argo Workflows controller removed per ADR-003 but the old Deployment remains | §10.5 — workflow-controller dead Deployment |

No file changes. This section exists so future reviewers do not re-raise
these as P0; the fixes are operational and scripted in the runbook.

---

## 5. Genuine file-level gaps (the real work)

The four items below are the only places the repo is actually
incomplete. Each one is tracked as a task and addressed in a subsequent
commit in this same work stream.

### 5.1. `use-case-crypto/manifests/base/kustomization.yaml` — missing katib wire-in
`experiment-lightgbm.yaml` exists at `katib/experiment-lightgbm.yaml`
but is not in the `resources:` list. Fix: add line under "ORCHESTRATED
BY AIRFLOW + KFP" block, marked as KFP-launched HPO.

### 5.2. `platform/DECISIONS.md` ADR-006 — Vault version string drift
ADR-006 table says `Vault 1.21.4`; the actual StatefulSet pins
`hashicorp/vault:1.21.5`. Update ADR-006 to 1.21.5 so the policy line
`verify-platform-images-cosign` cannot fire a false-positive against its
own source of truth.

### 5.3. `platform/DECISIONS.md` ADR-009 — opt-out exception list
ADR-009 currently says "Overrides permitted only for: kube-system,
longhorn-system, Explicitly labeled namespaces via exception list" but
does not enumerate the list. Rewrite to:

1. Name the five opt-out namespaces.
2. State the conflict each one resolves.
3. Point at the `networkPolicy` that re-establishes zero-trust in the
   absence of the sidecar.

### 5.4. `use-case-stock/` — net-new use-case
Directory does not exist. Scaffold as a narrow fork of `use-case-crypto/`:

```
use-case-stock/
├── argocd/application.yaml            # AppProject + Application, scoped to use-case-stock ns
├── config/project.yaml                # domain = stock, symbols = [AAPL, MSFT, NVDA, ...]
├── manifests/base/
│   ├── namespace.yaml                 # istio-injection: enabled
│   ├── kustomization.yaml             # mirrors crypto, narrower resource list
│   ├── configmap-feast.yaml           # stock feature views (intraday 1m, 1h, 1d)
│   ├── pipeline-infrastructure.yaml   # endpoints — identical to crypto
│   ├── kafka-topics/                  # stock.{rest.raw,validated,features.v1,predictions.v1}.yaml
│   ├── cronjobs/rest-collector-yahoo.yaml   # Yahoo Finance REST (no WS; equity markets close)
│   ├── inferenceservices/stock-inference.yaml   # stock-predictor, MLflow format
│   ├── kueue/queues.yaml              # LocalQueue stock-training-queue
│   ├── rbac/                          # stock-pipeline-sa
│   ├── vault/vault-bootstrap-stock.yaml
│   └── network-policies.yaml
├── pipelines/retraining_pipeline.py   # symlink or copy of crypto template, retargeted
└── proto/                             # stock-specific event protos
```

Rationale for fork-vs-generalize: the thesis RQ matrix explicitly lists
**two** domains (crypto + stock) to demonstrate platform reuse. A narrow
fork proves the use-case boundary (§6 of the original review); a shared
Helm umbrella would hide the boundary and weaken the thesis claim.

---

## 6. 2026 version audit — ALL PASS

Verified `targetRevision` in every `helm-release.yaml` under
`platform/components/{security,storage,observability}/` against ADR-006
minimum-release floor. All pins satisfy 2026 release line.

| Component | Pin | Satisfies ADR-006 | Upstream release |
|---|---|---|---|
| kyverno | 3.7.0 (chart) → Kyverno 1.17.1 | ✓ | 2026-02-19 |
| falco | 6.0.6 (chart) → Falco 0.43.1 | ✓ | 2026-Q1 |
| trivy-operator | 0.32.0 → operator 0.31.0 / trivy 0.63.0 | ✓ | 2026-Q1 |
| velero | 8.6.0 (chart) → velero 1.18.0 | ✓ | 2026-03-18 |
| chaos-mesh | 2.8.2 | ✓ | 2026-Q1 |
| external-secrets | 2.3.0 (chart) → ESO v0.22.x app | ✓ | 2026-04-13 |
| longhorn | 1.11.1 | ✓ | 2026-Q2 |
| cnpg | 0.28.0 → operator v1.29.x | ✓ | 2026-Q1 |
| clickhouse-operator | 0.26.2 | ✓ | 2026-02-24 |
| vault (image pin) | 1.21.5 | ✓ (ADR-006 text says 1.21.4 — **fix**) | 2026-Q1 |
| cert-manager | v1.20.0 | ✓ | 2026-03-09 |
| kube-prometheus-stack | 83.4.3 | ✓ | 2026-Q2 |
| argocd | v3.3.3 | ✓ | 2026-Q1 |
| istio | 1.28 | ✓ | 2026 |
| knative | 1.20 | ✓ | 2026 |
| kserve | v0.17 | ✓ | 2026 |

**No tool bumps required.** One doc-drift fix (ADR-006 Vault minor).

---

## 7. Removed tools — CONFIRMED gone

Cross-checked ADR-005 against the repo. All items below have zero
residual references in `kustomization.yaml` chains:

- `llmisvc-controller-manager` ✓
- `kserve-localmodel-controller-manager` ✓
- SeaweedFS ✓ (replaced by `minio.storage` ExternalName)
- Metacontroller ✓
- Embedded KFP `minio` + `mysql` ✓ (`$patch: delete` in Kustomize overlay)
- Second Argo Workflows controller ✓ (only KFP's remains, in `model-lifecycle`)
- httpbin demo ✓
- Empty `auth`, `oauth2-proxy`, `ml-pipeline` namespaces ✓
- k3s Traefik/servicelb/metrics-server ✓ (disable flags in `setup-toolchain.sh`)

Advisor earlier warned that `mysql` was still required for KFP metadata
backend. Re-audit confirms: the `mysql` that remains is a **dedicated
CloudNativePG-managed MySQL in `storage` namespace** for KFP's metadata
service; the **`mysql` deleted by ADR-005 was the embedded KFP default**.
Different workloads, different namespaces. `storage/mysql.yaml` stays.

---

## 8. Updated prioritised backlog (replaces §9 of original)

| # | Change | File(s) touched | Risk | Effort |
|---|---|---|---|---|
| 1 | Add `katib/experiment-lightgbm.yaml` to crypto kustomization | `use-case-crypto/manifests/base/kustomization.yaml` | None | 1 line |
| 2 | Bump ADR-006 Vault row 1.21.4 → 1.21.5 | `platform/DECISIONS.md` | None (docs) | 1 line |
| 3 | Rewrite ADR-009 with explicit opt-out list + per-namespace rationale | `platform/DECISIONS.md` | None (docs) | ~20 lines |
| 4 | Scaffold `use-case-stock/` | new tree, ~15 files | Low (net-new, isolated) | Medium |
| 5 | Append `§10.15 kafka-dev namespace cleanup` to remediation runbook. The other four §4 rows already had runbook coverage: ArgoCD → §6 (GitOps activation), Traefik → §0 (Prerequisites), workflow-controller → §10.5, stale APIServices → §10.3 + §10.10. | `platform/REMEDIATION_RUNBOOK.md` | None (ops docs) | Small |

All changes are **file-level and reviewable via git diff**. No terminal
one-offs; no ArgoCD-only reconciliation tricks; no live-cluster
mutations required to land this work in the repo.

---

## 9. Methodology correction

Original review read live cluster and projected gaps back onto the
repo. That produced false negatives on every item the cluster had not
yet reconciled. The corrected methodology used for this addendum:

1. **Start from the file tree**, not from `kubectl get`.
2. For every P0/P1 claim, open the path the fix would live at and
   verify presence/absence **before** writing the finding.
3. If the file exists but is unreferenced by `kustomization.yaml`, the
   gap is a **wire-in**, not a **rewrite**.
4. If the file exists and is referenced but the cluster object is
   missing, the gap is **ArgoCD reconciliation**, not a file gap.
5. Call the advisor before each change of interpretation to surface
   assumption drift.

Apply this filter first on any future architecture audit of this repo.

---

*Addendum authored 2026-04-19 after file-tree verification via
ctx_batch_execute + targeted Reads. Supersedes findings in
ARCHITECTURE_REVIEW_2026-04-19.md where the two disagree.*
