# Architecture Decision Records (ADR)

This document reconciles the platform's tool choices against the thesis
proposal (`materials/Proposal.tex`) and justifies every deviation. Each ADR
ties back to a functional objective (KF-*) or non-functional requirement
(KNF-*). Tool versions are all 2026 releases.

---

## ADR-001 — Raystack substitutions

**Status:** ACCEPTED
**Date:** 2026-04-17

### Context

The proposal (`Bab_2.tex:188-299`) names ten Raystack/gotocompany tools:
Raccoon, Stencil, Firehose, Optimus, Dagger, Frontier, Guardian, Compass,
Meteor, Siren. Raystack is a CNCF sandbox-adjacent stack originating from
Gojek/GoTo. Several components are under active maintenance; others are
community-maintained with small contributor counts.

### Decision

| Proposal (Raystack) | Platform choice | Rationale |
|---|---|---|
| Raccoon (HTTP/gRPC event collector) | Domain microservice → Kafka direct | Raccoon's proto→Kafka flow is replaced by use-case-owned collectors that can enforce schema at ingress. Less generic code to maintain. |
| Stencil (Protobuf schema registry) | **Karapace 4.1** (Kafka-compat) | Karapace is Aiven-maintained, Confluent-API compatible, Apache-2.0, first-class k8s charts. Stencil's k8s ops story is thinner. |
| Firehose (no-code Kafka→sink) | **Kafka Connect (Debezium + Iceberg)** | Kafka Connect ecosystem (Debezium PG CDC, tabular-io Iceberg sink) is broader and integrates natively with Karapace. |
| Optimus (Spark orchestrator) | **Airflow + Kubeflow Pipelines** | Airflow = deployed orchestrator for batch; KFP = orchestrator for ML training (Bab_2.tex:162). Optimus adds another DSL. |
| Dagger (Flink config DSL) | Flink SQL + DataStream in Docker image | Use-case Flink jobs run as embedded-mode streaming with native DataStream/SQL APIs; an extra config DSL adds maintenance burden without buying generality the platform needs. |
| Frontier (IDP) | **Dex 2.45 + oauth2-proxy 7.15** | Dex is the Kubeflow-standard OIDC IdP, broader OIDC connectors (LDAP, SAML, GitHub, Google). Istio `RequestAuthentication` validates Dex JWTs. |
| Guardian (data-access governance) | **SpiceDB 1.51 (Zanzibar ReBAC) + Kyverno 1.17** | SpiceDB = Google Zanzibar-derived, more general policy model; Kyverno enforces admission policies. |
| Compass (catalog UI) | **DataHub 1.5** | DataHub has richer OpenLineage support, classification, and first-party Kafka metadata events. |
| Meteor (metadata collector) | **DataHub native ingestion framework** | Removes a layer; DataHub's Python ingestion framework plus OpenLineage covers PG/CH/dbt/Feast/MLflow/Airflow/Kafka. |
| Siren (alert orchestrator) | **Alertmanager 0.28 + OpenTelemetry Collector routing** | Prometheus Operator bundles Alertmanager natively; OTel Collector handles trace/log routing. |

### Consequences

- Reduces Raystack vendor lock-in risk; every chosen tool has a Helm chart and CNCF project or equivalent community backing.
- Breaks verbatim alignment with proposal tool names: **defendable in the thesis by citing CNCF maturity, community size, and upstream k8s-nativity**.
- Introduces deeper Kubeflow integration than proposal implied (KFP/Katib/Trainer/Metadata).

---

## ADR-002 — API gateway: APISIX over Kong

**Status:** ACCEPTED
**Date:** 2026-04-17

### Context

Proposal (Bab_2.tex:266) names Kong Gateway. Platform deploys Apache APISIX.

### Decision

APISIX 3.15:
- Native Istio + Dapr + SpiceDB plugins (auth, rate limit, traffic split).
- Apache TLP; etcd-less standalone mode from `configmap-config.yaml` aligns with our pull-through GitOps model.
- Native Prometheus + OpenTelemetry exporter.

### Consequences

- Slightly different plugin API vs Kong (not a user-visible difference).
- Single fewer database (Kong needs Postgres in HA mode).

---

## ADR-003 — Orchestration split: Airflow for data, KFP for ML

**Status:** ACCEPTED
**Date:** 2026-04-17

### Context

Proposal (Bab_5.tex:74) uses Airflow only for drift pipeline and treats KFP as primary. In practice batch orchestration for the data pipeline (ingest → dbt → quality → lakehouse) is Airflow-shaped (DAGs, sensors, operators).

### Decision

- **Airflow 3.1**: data orchestration — DAGs are use-case-scoped and authored in `<use-case>/dags/` (DAG IDs derived from `Variable.get("USE_CASE")`); see `<use-case>/docs/ADRS.md` ADR-003 for the concrete DAG list. Emits OpenLineage → DataHub.
- **Kubeflow Pipelines v2.16**: ML orchestration — `retraining_pipeline` (drift → train → register → deploy). Runs on Argo Workflows under the hood.
- **Tekton 1.9**: CI pipelines only — Kaniko in-cluster image builds triggered by Gitea webhooks.

### Consequences

- Two orchestrators to maintain. Airflow DAG authors must learn a different mental model from KFP authors.
- Explicit separation of concerns: data engineers own Airflow; ML engineers own KFP.
- Argo Workflows (standalone) **removed** — KFP's bundled controller covers ML workflows cluster-wide. Avoids dual controller lease contention (49+ restarts observed).

---

## ADR-004 — Additions beyond proposal

**Status:** ACCEPTED
**Date:** 2026-04-17

Each tool added beyond the proposal is tied to a KNF requirement it enforces.

| Tool | Version | Added for | KNF |
|---|---|---|---|
| **LakeFS** | 1.80 | Git-like branching for data (PR-style review on bronze/silver) | KNF-05 temporal consistency: branch-per-pipeline-run guarantees reproducibility. |
| **Lakekeeper** | 0.9 | Iceberg REST catalog, remote signing to MinIO | KNF-11 portability: Iceberg tables are the canonical lake format across clouds. |
| **Evidently** | 0.7 | Data + model drift reports | KNF-05 + drift-triggered retraining (proposal names PSI/K-S only; Evidently adds UI + automation). |
| **SpiceDB** | 1.51 | Fine-grained ReBAC authorization | Complements Guardian (ADR-001); data access policies expressed as Zanzibar relations. |
| **GrowthBook** | 4.3 | Feature flags (ML decision rules) | KNF-08 extensibility: model rollouts are flaggable without redeploy. |
| **Qdrant** | 1.17 | Persistent vector ANN (HNSW) | KNF-01 p99 <10 ms: complements Redis Stack for embedding similarity (proposal names "Weaviate or Qdrant"). |
| **Alloy** (Grafana) | latest | Log shipping to Loki | KNF-06 observability: replaces promtail, supports OTel receivers natively. |
| **OpenCost** | 1.119 | Per-namespace/workload cost attribution | ADR for financial workloads: cost accountability per pipeline/model. |
| **Kueue** | 0.16 | K8s-native job queueing | KNF-03 horizontal scalability: ML training jobs queue with priority + fair sharing. |
| **Istio** | 1.28 | Service mesh + Knative ingress | KNF-07 mTLS (STRICT PeerAuthentication mesh-wide). |
| **Knative** | 1.10 | Serverless backbone for KServe | KNF-03 auto-scaling to zero for inference. |
| **Tekton** | 1.9 | Kubernetes-native CI | ADR-003. |
| **Gitea** | 1.25 | Self-hosted Git | Air-gapped GitOps source. |

---

## ADR-005 — Removed tools

**Status:** ACCEPTED
**Date:** 2026-04-17

### Removed

- **`llmisvc-controller-manager`** (KServe LLM inference): tabular ML only (Bab_1.tex:143 names regression/classification/neural nets, not LLMs). 30+ restart cascades observed.
- **`kserve-localmodel-controller-manager`**: node-local model weight caching; MinIO already covers artifact storage via KServe storage containers.
- **SeaweedFS** (embedded by KFP): replaced by `minio-service` ExternalName alias pointing to `minio.storage.svc.cluster.local` — single canonical object store.
- **Metacontroller** (embedded by KFP): not required in KFP v2 (caching uses MutatingWebhookConfiguration).
- **Embedded KFP minio + mysql**: `$patch: delete` in Kustomize — `minio.storage` and `mysql.storage` are canonical.
- **Second Argo Workflows controller in gitops**: KFP's controller in `model-lifecycle` handles cluster-wide `workflows.argoproj.io`. Tekton handles CI.
- **httpbin** demo pod in gitops: test leftover.
- **k3s built-in Traefik, servicelb, metrics-server**: Istio IngressGateway + APISIX replace Traefik/servicelb; kube-prometheus-stack (kube-state-metrics + node-exporter) replaces metrics-server. prometheus-adapter was part of this bundle until 2026-04-21 (ADR-026 removed it once its last consumer moved to KEDA).
- **Empty namespaces** (`auth`, `oauth2-proxy`, `ml-pipeline`): dex/oauth2-proxy run in `common`; `ml-pipeline` was orphaned.

### Retained but scoped

- `kubeflow` namespace: kept as ExternalName-only shim for KFP v2 launcher's hardcoded `minio-service.kubeflow` reference.
- `kueue-system` namespace: kept as cross-namespace webhook-service proxy (Kueue controller runs in `common`).

---

## ADR-006 — 2026 tool versions (minimum-release floor)

**Status:** ACCEPTED
**Date:** 2026-04-17

All externally-managed tools must be on a 2026 release line. Versions pinned:

| Tool | Version | Release date |
|---|---|---|
| cert-manager | v1.20.0 | 2026-03-09 |
| Strimzi Kafka Operator | 0.51.0 | 2026-03 |
| CloudNativePG | 1.29.0 | 2026-Q1 |
| Altinity ClickHouse Operator | 0.26.2 (helm) | 2026-02-24 |
| External Secrets Operator | v0.22.x (helm 2.3.0, 2026-04-13) | 2026-Q2 |
| kube-prometheus-stack | 83.4.3 (app v0.89.0) | 2026-Q2 |
| OpenTelemetry Operator | latest v0.120+ | 2026 ongoing |
| Longhorn | v1.11.1 | 2026 |
| Kyverno | 1.17 | 2026-02-02 |
| Cosign | v3.0.3 | 2026 |
| Velero | 1.18.0 | 2026 |
| Chaos Mesh | 2.8.2 | 2026 |
| Vault | 1.21.5 + HA Raft | 2026 |
| ArgoCD | v3.3.3 | 2026 |
| Istio | 1.28 | 2026 |
| Knative | 1.20 | 2026 |
| KServe | v0.17 | 2026 |

No `:latest` tags in production manifests (enforced by Kyverno ADR-012).

---

## ADR-007 — Storage durability: Longhorn over local-path

**Status:** ACCEPTED
**Date:** 2026-04-17

### Context

Single-node k3s defaults to `local-path-provisioner`. Node reimage = total data loss. KNF-04 requires RPO < 1 min, RTO < 5 min.

### Decision

Install **Longhorn v1.11.1**. Make `longhorn` the default StorageClass. `local-path` retained as fallback for bootstrap (cert-manager CA, Longhorn's own metadata).

All stateful PVCs migrate to `longhorn`:
- Kafka (Strimzi operator — 3 brokers × 20Gi)
- PostgreSQL (CNPG — 3 replicas × 10Gi)
- ClickHouse (Altinity CHI — 2 replicas × 20Gi)
- Elasticsearch (ECK — 3 nodes × 10Gi)
- MinIO (distributed mode — 4 drives × 20Gi)
- Vault (Raft — 3 × 1Gi)
- Prometheus / Loki / Tempo / Evidently (replaces `emptyDir`)

### Consequences

- Longhorn requires open-iscsi on host (added to `setup-toolchain.sh`).
- On multi-node: replica count ≥ 2 is enforceable per StorageClass.
- Adds a StorageClass migration step (pre-existing PVCs on `local-path` must be drained and re-provisioned).

---

## ADR-008 — Secret management: External Secrets Operator + OpenBao HA

**Status:** ACCEPTED
**Date:** 2026-04-17
**Amended:** 2026-04-23 — Migrated from HashiCorp Vault 1.21.5 (BSL-1.1) to OpenBao 2.5.3 (MPL-2.0).

### Context

Audit found 8+ hardcoded credentials in `stringData` secrets (KNF-07 violation). Vault is deployed but used only by `gateway`.

**2026-04-23 amendment:** HashiCorp relicensed Vault from MPL-2.0 to BSL-1.1 in August 2023. BSL is source-available, not open source (not OSI-approved). The thesis title explicitly claims "Open Source Tools" — running BSL-licensed software breaks that claim. OpenBao is the Linux Foundation fork of Vault's last MPL-2.0 codebase, API-compatible, actively maintained (v2.5.3, 2026-04-20).

### Decision

- **External Secrets Operator v0.22** with `ClusterSecretStore` backed by OpenBao KV v2 (Vault-compatible API).
- **OpenBao 2.5.3** (MPL-2.0, `quay.io/openbao/openbao:2.5.3`) deployed in HA mode: 3-replica StatefulSet with integrated Raft storage (no Consul dependency), auto-unseal via Kubernetes Secret (transit seal possible post-install).
- All `stringData`-based secrets migrated to `ExternalSecret` CRs reading from `secret/data/platform/<component>`.
- Image-swap migration strategy: K8s Service names, DNS endpoints, ConfigMap/Secret names retained as `vault-*` for zero-blast-radius migration. The running binary is OpenBao; the string "vault" in YAML names is a Kubernetes naming convention, not a license claim.
- OpenBao ships `/bin/vault` symlink for backward compatibility — all bootstrap scripts work unchanged.
- `IPC_LOCK` capability removed (OpenBao removed mlock entirely).

### Consequences

- Rotating a credential = `vault kv put` (or `bao kv put`) + ESO re-sync; no Git edits.
- OpenBao bootstrap still requires root token; bootstrap Job seals it under a restricted role.
- ArgoCD reconciles `ExternalSecret` CRs; it never sees the secret values.
- Full thesis open-source compliance restored: no BSL-licensed components remain.

---

## ADR-009 — mTLS: Istio STRICT mesh-wide (with a closed opt-out list)

**Status:** ACCEPTED
**Date:** 2026-04-17
**Amended:** 2026-04-19 — added explicit opt-out list and per-namespace rationale.
**Amended:** 2026-04-22 — added `falco` opt-out (eBPF probe-reload incompatibility), expanded the former "Note on `vault`" into a proper per-pod opt-out taxonomy (three categories: structural self-exemption, redundant belt-and-suspenders, genuine mesh-enabled carve-out), and reconciled the allowlist cardinality 7 → 8 across this ADR and the Kyverno `enforce-istio-opt-out-allowlist` policy.
**Amended:** 2026-04-30 — added four platform-infrastructure opt-outs (`external-secrets`, `security`, `kyverno`, `gitops`) that surfaced once `phase-base` was driven end-to-end with PSA `restricted` namespaces. Each fails the istio-proxy injection at the PodSecurity admission boundary or the chart-internal TLS path, not the sidecar logic itself; allowlist cardinality reconciled 7 → 11 platform-default entries across this ADR and the Kyverno policy. The four additions are documented in the table below; the count invariant, per-pod taxonomy, and "Consequences" section are updated to match.

### Context

Previous state: Istio permissive mode. Vault's `tls_disable=1` justified by "mesh mTLS" — false under permissive (plaintext accepted).

Several workloads in the platform have legitimate technical reasons that they cannot run an Istio sidecar. Without documenting these, future reviewers rediscover the "violation" on every audit and either (a) force-inject the sidecar and break the workload, or (b) weaken ADR-009 globally. Both are wrong. The correct answer is a **named, frozen opt-out list** with per-namespace mitigation.

### Decision

**Default posture.** `PeerAuthentication/default` with `mtls.mode: STRICT` in the root namespace `istio-system`. Every workload outside the opt-out list below must run with a sidecar and receive/send only mTLS traffic.

**Closed opt-out list.** The following namespaces are labeled `istio-injection=disabled` (or apply the equivalent per-pod `sidecar.istio.io/inject: "false"` where an opt-out namespace would otherwise split a shared workload). No other namespace may be added without a new ADR.

| Namespace | Why the sidecar is incompatible | Compensating control |
|---|---|---|
| `kube-system` | k3s control plane uses hostNetwork and direct 10250 kubelet traffic that Istio cannot wrap without breaking node-agent I/O. | k3s API-server ships its own TLS; kubelet PKI rotates via `kubelet-config`. |
| `longhorn-system` | Longhorn relies on iSCSI targets exposed via hostPath and `hostNetwork: true`; mesh routing breaks LUN attachment. | Host-level iptables + `NetworkPolicy` restricts ingress to `longhorn-manager` and `longhorn-engine-*` to node-local. |
| `falco` | Falco's `modern-bpf` driver pins CO-RE eBPF probes and mounts `/proc`, `/sys`, `/boot`, `/lib/modules` from the host; the `istio-init` container rewrites the pod-netns iptables in parallel with falco-driver's probe reload, which races the eBPF attach and breaks runtime detection. Upstream Falco guidance explicitly disables sidecar injection for the same reason. | Falco is observe-only — there is no cluster ingress to protect. `falcosidekick` egress to `alertmanager.observability` / `loki.observability` / `minio.storage` is a non-sidecar client reaching sidecar-equipped destinations, which under STRICT PeerAuthentication requires a matching `PERMISSIVE` overlay `PeerAuthentication` on each destination Service's selector (or routing the egress through `istio-ingressgateway`); this overlay is not yet declared because mesh occupancy has not grown past the gateway-only footprint (Task #20 threshold) — until then falco's sidekick traffic is a plaintext-accepting destination by default. Kyverno-admission and Falco-runtime detection are complementary defence-in-depth per ADR-014, so the sidecar's absence here does not widen the attack surface. |
| `vault` *(migration-path guardrail — see taxonomy below)* | Vault Raft gossip on 8201 terminates its own TLS; double-wrapping with the sidecar conflicts with the Vault listener's `tls_disable=1` local-pod policy and adds a second certificate authority to the trust path. | Vault integrated-storage (Raft) uses its own mTLS between pods; external access is via Istio gateway at the mesh boundary. |
| `model-lifecycle` | Kubeflow Pipelines v2 launcher injects `PodDefault` CRs that collide with Istio's init-container ordering; port 15001 reservation conflicts with KFP's artifact-passing sidecar. KFP upstream documents this explicitly (`kubeflow/pipelines#9972`). | Zero-trust restored by `NetworkPolicy` in `platform/components/model-lifecycle/network-policies.yaml` limiting ingress to ArgoCD, the Airflow scheduler, and the KFP API gateway. |
| `model-serving` | KServe queue-proxy binds the same admission path Istio would inject; Knative `serving.knative.dev/visibility: cluster-local` requires queue-proxy to own the pod network. KServe upstream: "disable Istio injection OR use Istio ingress; not both" (`kserve/kserve#2873`). | Istio **ingress** (not sidecars) fronts KServe via `Gateway` + `VirtualService`; in-cluster calls to InferenceServices are forced through the mesh ingress IP. `NetworkPolicy` restricts direct pod-to-pod. |
| `use-case-<X>` (test-bind today: a single use-case namespace per cluster) | Sidecar adds ~5ms p50 on the gateway hot path. Use-case SLOs that name a `p99` budget tighter than ~50ms cannot afford the handshake; ADR-024's decision tree keeps such use-cases OUT of the mesh so the hot-path latency budget is spent on domain work, not mTLS. The concrete latency-budget rationale is use-case-specific — see `<use-case>/docs/ADRS.md` ADR-024. | `AuthorizationPolicy` at the `istio-ingressgateway` + per-namespace `NetworkPolicy` (see ADR-024); every peer namespace that needs east-west access is named explicitly in `<use-case>/manifests/base/network-policies.yaml`. |
| `istio-system` | Istio's control plane and CNI components live here; the sidecar image itself is `istio-proxy`, so injecting a sidecar into istiod would require istiod's own admission webhook to be Ready before istiod can start — a boot-order cycle. `istio-cni-node` additionally requires `hostNetwork: true` to install per-node iptables chains. | istiod terminates its own mTLS via `istio-ca-secret` and is only reachable cluster-internally through the mesh ingress. Every workload namespace carries an `allow-istio-sidecar` NetworkPolicy that confines ingress to pods in `istio-system`; host-level iptables protect `istio-cni-node`. CI runs `istioctl analyze` on every PR that touches Istio manifests. |
| `external-secrets` | The namespace runs under PodSecurity `restricted`, which requires every container in the pod to set `securityContext.seccompProfile`. The upstream `istio-proxy` image (and its `istio-validation` / `istio-init` companions) does not set a pod-level seccomp profile, so admission rejects the injected pod with `seccompProfile: must be set to RuntimeDefault or Localhost`. Patching seccomp into the injector template fixes it for ESO but creates drift against every other Istio-enabled workload, so the cleaner contract is to opt the namespace out. | The ESO controller, webhook, and cert-controller talk to (a) kube-apiserver over its own TLS and (b) Vault on `vault.security.svc` whose listener already terminates TLS at the pod. Edge ingress from outside the mesh remains gated by `istio-ingressgateway` + `AuthorizationPolicy`. `platform/components/security/external-secrets/network-policies.yaml` (Task #98 follow-up) provides default-deny ingress to enforce zero-trust without the sidecar. |
| `security` | Same root cause as `external-secrets`: the namespace is PSA `restricted` (it carries Vault, KES, OPA, Trivy, and the Kyverno admission webhook's RBAC) and the `istio-proxy` image lacks a pod-level seccomp profile, so injection fails admission. Vault itself is also already a per-pod opt-out under taxonomy item (3) below for its own (different) reason; flipping the namespace label to `disabled` collapses that pod-level exception into a single namespace-level one and removes the pod-level annotation drift on every Vault upgrade. | All security operators in this namespace are kube-apiserver clients and talk to their own backends over TLS already. East-west authn for Vault is via Kubernetes ServiceAccount tokens (Vault's k8s auth method), which is independent of the sidecar. The compensating `NetworkPolicy` is `platform/components/security/network-policies.yaml`. |
| `kyverno` | The Kyverno admission webhook serves on its own pod-issued cert that `kyverno-cert-controller` injects into the `ValidatingWebhookConfiguration.caBundle`; if the sidecar wraps the pod's :9443 listener, the kube-apiserver still trusts only the original cert and the webhook becomes "no endpoints available" until the bundle is re-rotated through the sidecar's CA — which it is not, because the sidecar's CA is istiod's, not Kyverno's. Practically, every cluster-wide validating call would fail until the bundle is reconciled. The chart's preStop and liveness probes also hit `https://localhost:9443/health/*` directly, which the sidecar must not intercept. | Kyverno runs as a kube-apiserver client only; there is no east-west service-to-service traffic from Kyverno that the mesh would protect. The webhook's TLS is already mutual at the apiserver boundary (kube-apiserver verifies the bundle, Kyverno verifies the apiserver SA token). NetworkPolicy in `platform/components/security/kyverno/network-policies.yaml` (follow-up under Task #102) restricts ingress to kube-apiserver. |
| `gitops` | ArgoCD's `argocd-repo-server` and `argocd-application-controller` open self-signed gRPC TLS to the application-controller and to each other on `:8081` / `:8083`; the sidecar's mTLS double-wrap presents istiod's CA to the gRPC client, which expects ArgoCD's internal CA, and the handshake aborts with `transport: authentication handshake failed: EOF` — observed across every Application sync attempt on 2026-04-29 cold start. ArgoCD upstream documents this and recommends running the namespace out of mesh or using their `argocd-server --server-listen 0.0.0.0:8080 --grpc-keepalive` flag combo, which still requires PERMISSIVE on the namespace; the cleaner resolution is the namespace-level opt-out. | ArgoCD runs its own internal mTLS between repo-server / application-controller / server using the `argocd-secret` CA; the API surface (`argocd-server`) is exposed externally through `istio-ingressgateway` + APISIX with proper auth. NetworkPolicy in `platform/components/gitops/network-policies.yaml` (follow-up Task #102) restricts repo-server / application-controller ingress to peers in `gitops`. |

**Per-pod opt-out taxonomy.** The table above enumerates *namespace-level* opt-outs. The platform also carries a number of *per-pod* opt-outs via the `sidecar.istio.io/inject: "false"` annotation on the pod template. Because the Kyverno allowlist is (by design) namespace-scoped, the pod-level dimension is documented here so that a future reviewer looking only at `kubectl get ns -L istio-injection` does not conclude that the pod-level opt-outs are undocumented drift. Every per-pod opt-out present in the tree falls into one of three categories:

1. **Structural self-exemption — Istio control-plane and gateways.** These pods cannot sidecar themselves because the sidecar image *is* `istio-proxy`; injecting it would require the pod's own admission webhook to be `Ready` before the pod can start, which is a boot-order cycle. Their namespace (`istio-system`) is already `istio-injection=disabled`, so the per-pod annotation is redundant at admission but is preserved for parity with the upstream `istioctl install` / Knative installer output and to keep `istioctl analyze` silent:
   - `istio-ingressgateway` Deployment — `platform/components/common/istio/istio-install.yaml`
   - `istiod` Deployment — same file
   - `istio-cni-node` DaemonSet — same file
   - `cluster-local-gateway` Deployment — `platform/components/common/knative/local-gateway.yaml`

2. **Redundant belt-and-suspenders — pods in an already-disabled namespace.** These pods live in `model-lifecycle`, whose Namespace label is `istio-injection=disabled` (row above), so the pod annotation is not load-bearing today. It is kept as a forward-compatible marker: if a future ADR flips `model-lifecycle` to `istio-injection=enabled` (e.g. after KFP v3 lands the queue-proxy / Istio ordering fix), these pods would still need to stay out of mesh and the per-pod annotation preserves that without a second manifest change:
   - `mlflow` Deployment — `platform/components/model-lifecycle/mlflow/deployment.yaml`. The inline comment there flags a planned migration once the Postgres client supports `ISTIO_MUTUAL` origination cleanly; after that migration this entry moves to category (3) below (the annotation becomes load-bearing because the namespace label will flip).
   - `kubeflow-pipelines` subcomponents (three pod templates) — `platform/components/model-lifecycle/kubeflow-pipelines/pipelines.yaml`.

3. **Genuine mesh-enabled carve-out — pods in an `istio-injection=enabled` namespace.** These are the per-pod opt-outs the mesh admission path actually enforces at the pod level; without the annotation the injector would wrap them. Each has a named technical reason the sidecar is incompatible:
   - `vault` StatefulSet — `platform/components/security/vault/statefulset.yaml`, namespace `security`. Raft gossip on 8201 terminates its own TLS against the Vault PKI cert; the sidecar's mTLS double-wrap conflicts with the listener's `tls_disable=1` local-pod policy and adds a second CA to the trust path.
   - `vault-bootstrap` Job — `platform/components/security/vault/vault-bootstrap.yaml`, namespace `security`. Client of the out-of-mesh `vault-0` pod; a sidecar on the client would originate from a different CA than the server trusts.
   - `unseal-vault` Deployment — `platform/components/security/vault/unseal-vault.yaml`, namespace `security`. Same rationale as `vault-bootstrap` — client of an out-of-mesh Vault Service.
   - `superset` Deployment — `platform/components/data-processing/superset/deployment.yaml`, namespace `data-processing`. Superset's SQLAlchemy engine originates its own TLS to CNPG; Istio's `ISTIO_MUTUAL` origination breaks the client-side handshake by pre-terminating TLS at the sidecar.
   - `airflow-worker` pod template — `platform/components/data-processing/airflow/deployment.yaml`, namespace `data-processing`. `KubernetesExecutor` creates a transient pod per task; the istio-proxy sidecar keeps the pod `Running` indefinitely after the task container exits, which the executor cannot reap. (Scheduler, webserver, DAG processor, triggerer remain in-mesh — the opt-out is confined to the worker pod template, not the whole `data-processing` namespace.)

**Count invariant.** The Kyverno allowlist carries **11 platform-default entries plus N use-case entries** (today N=1, the single test-bind use-case namespace). Platform defaults: `kube-system`, `longhorn-system`, `falco`, `vault`, `model-lifecycle`, `model-serving`, `istio-system`, `external-secrets`, `security`, `kyverno`, `gitops`. Of those, **10** correspond to namespace-level opt-outs that actually exist today (9 tree-declared — `longhorn-system`, `falco`, `model-lifecycle`, `model-serving`, `istio-system`, `external-secrets`, `security`, `kyverno`, `gitops` — plus `kube-system` which is cluster-provided by k3s), and **1** (`vault`) remains a migration-path guardrail: Vault is deployed inside the `security` namespace (now `istio-injection=disabled` per the 2026-04-30 amendment, which also subsumes Vault's per-pod opt-out at the namespace level — see taxonomy note below). The allowlist slot for `vault` is preserved should a future ADR split Vault into its own namespace without a second Kyverno-policy PR at that time. The use-case entries are added via the use-case overlay's Kyverno patch (see `<use-case>/manifests/base/security/kyverno-allowlist-patch.yaml`); each one is justified by a use-case ADR-009 cross-reference in `<use-case>/docs/ADRS.md`. Pod-level opt-outs (taxonomy items 1/2/3 above) are not policy-enforced — the Kyverno policy is by design namespace-scoped — but they are exhaustively enumerated in this subsection so a quarterly ADR-009 review can audit them by grepping `sidecar.istio.io/inject: *"false"` across the tree and comparing against the lists above.

**Enforcement.** Kyverno policy `enforce-istio-opt-out-allowlist` in `platform/components/security/kyverno/policies.yaml` denies any `Namespace` creation or update that sets `istio-injection=disabled` **unless** the namespace name is one of the platform-default allowlist entries above (the `istio-system` boot-order guardrail and the `vault` migration-path guardrail both count) or has been appended via a use-case overlay patch (`<use-case>/manifests/base/security/kyverno-allowlist-patch.yaml`). This closes the loop so the namespace-level exception list cannot drift silently.

**Vault mesh interaction.** Vault remains `tls_disable=1` on the listener inside its pod — it terminates Raft TLS on the pod's own cert, issued from the Vault PKI secrets engine. At the mesh boundary, Istio ingress runs STRICT mTLS on the way in. The combination is defensible.

### Consequences

- The opt-out list is **closed**. Adding a twelfth platform-default namespace requires a new ADR and a compensating NetworkPolicy review.
- `DestinationRule`s required where TLS settings need customization (e.g., client cert auth to external Postgres, Qdrant gRPC with ALPN=h2).
- `platform/components/*/network-policies.yaml` for every opt-out namespace must pass the `require-default-deny-ingress` Kyverno check even though the mesh isn't enforcing it — NetworkPolicy is the zero-trust fallback when the sidecar is absent.
- CI must run `istioctl analyze` on every PR that touches a namespace manifest; opt-out additions outside the platform-default allowlist (or an approved use-case overlay patch) fail fast.
- Per-pod opt-outs (the taxonomy subsection above) are not policy-enforced; any new `sidecar.istio.io/inject: "false"` annotation on a pod template must be added to the taxonomy in this ADR in the same PR, or the PR is rejected at review.

---

## ADR-010 — Observability: OpenTelemetry Collector + kube-prometheus-stack

**Status:** ACCEPTED
**Date:** 2026-04-17

### Context

KNF-06 specifies OpenTelemetry. Pre-ADR state: services emitted OTLP directly to Jaeger; emptyDir storage; no Alertmanager; annotation-based Prometheus scraping.

### Decision

- **kube-prometheus-stack 83.6.0**: Prometheus Operator, Alertmanager, kube-state-metrics, node-exporter. Prometheus and Alertmanager on PVCs.
- **OpenTelemetry Operator + Collector**: gateway Deployment + agent DaemonSet. Fan out traces to **Grafana Tempo** (2.10.4, MinIO S3), metrics to Prometheus (OTLP → remote_write), logs to Loki. Jaeger v2 was the initial trace backend but was removed 2026-04-21 (ADR-025): Tempo is OTLP-native, rides on the existing MinIO, and shares Grafana with the rest of the LGTM stack, so the parallel Jaeger + Elasticsearch path was pure duplication.
- **Loki** on PVC; retention ≥ 14 days.
- **Alertmanager** receivers: `default` → Slack webhook (stub); per-namespace inhibition rules.

### Consequences

- Services configure only `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability:4317` — routing managed centrally.
- Head sampling + tail sampling (latency > 1s, error-only) at Collector layer.

---

## ADR-011 — HA data plane operators

**Status:** ACCEPTED
**Date:** 2026-04-17

### Decision

| Tool | Operator | Cluster shape |
|---|---|---|
| Kafka | **Strimzi 0.51** | 3 KRaft brokers, RF=3, min.insync=2 |
| PostgreSQL | **CloudNativePG 1.29** | 3 replicas, sync quorum=1, PITR via Barman to MinIO |
| ClickHouse | **Altinity 0.26.2** | 2 shards × 2 replicas, ClickHouse-Keeper quorum |
| Elasticsearch | **ECK 3.0** | 3 master-eligible + 3 data nodes |
| Kafka topics, schemas, users | **KafkaTopic / KafkaUser CRDs** | Declarative ACLs |

### Consequences

- Cluster size grows from a single k3s node to a multi-node target (stretch: 3-node k3s HA with embedded etcd, or migrate to full k8s on multi-node bare metal / VMs).
- On single-node k3s: replica count is 1 for bootstrap; operators handle scale-out when nodes join.

---

## ADR-012 — Policy & supply chain: Kyverno + Cosign

**Status:** ACCEPTED
**Date:** 2026-04-17

### Decision

**Kyverno 1.17** (CEL-based engine) enforces:
- `require-resource-limits`: all containers must set requests+limits.
- `disallow-latest-tag`: image tags must be explicit digests or semver.
- `require-probes`: liveness+readiness on workloads that expose a port.
- `require-runAsNonRoot`.
- `require-read-only-root-filesystem` (with exception list).
- `verify-image-signatures`: Cosign keyless (Fulcio) verification for internal images.

**Cosign v3.0.3** in the Tekton pipeline signs every internal image. The exact image-name patterns (registry host + `<use-case>-*` prefix) are configured per use-case overlay; see `<use-case>/docs/ADRS.md` ADR-020 for the test-bind use-case's pattern list.

---

## ADR-013 — Data contracts & governance

**Status:** ACCEPTED
**Date:** 2026-04-17

### Decision

- **DataHub ingestion recipes** run as CronJobs for: Kafka (topics + schemas from Karapace), PostgreSQL, ClickHouse, dbt, Feast, MLflow, Airflow.
- **OpenLineage** env vars added to Flink and Spark deployments (not only Airflow).
- **Feast → DataHub** via feast-datahub integration (schedule: hourly).

---

## ADR-014 — Backups & chaos

**Status:** ACCEPTED
**Date:** 2026-04-17

### Decision

- **Velero 1.18** with restic/Kopia file system backup. Target: MinIO `velero-backups` bucket. Schedule: hourly PVC snapshots, daily full namespace backup.
- **Chaos Mesh 2.8** for KNF-04 validation (`NetworkChaos`, `PodChaos`, `IOChaos`, `StressChaos`).

---

## ADR-015 — PodDisruptionBudget baseline for multi-replica workloads

**Status:** ACCEPTED
**Date:** 2026-04-20

### Context

k3s single-node bootstrap was hiding a rubric gap: voluntary disruptions (node drain, Longhorn volume rebalance, Cilium agent restart) would take every replica at once. Kubernetes default admission has no global "protect quorum" policy.

### Decision

Every multi-replica Deployment / StatefulSet owned by platform ships with a companion `policy/v1 PodDisruptionBudget` that pins `minAvailable: 1`. Single-replica workloads (admin UIs, single-leader controllers) are exempt; the PDB would pointlessly block evictions.

Scope: all components under `platform/components/{storage,data-ingestion,data-processing,data-governance,model-lifecycle,model-serving,observability,security,gitops,common}/` where `spec.replicas > 1`. Inherited by use-case Deployments via Kustomize.

### Consequences

- Future rubric items that depend on voluntary-disruption safety (KNF-04 chaos scenarios, cluster-autoscaler integration) work without rework.
- `kubectl drain` and `velero backup --include-cluster-resources` respect the PDBs automatically.
- Single-replica exception list is documented alongside each component; no silent drift.

---

## ADR-016 — Argo Rollouts supersedes Flagger for progressive delivery

**Status:** ACCEPTED
**Date:** 2026-04-20

### Context

Progressive delivery is a rubric requirement for the serving plane (KNF-09). Two mature choices: Flagger (flagger.app) and Argo Rollouts (argoproj). The platform is already argoproj-heavy (Argo CD, KFP's Argo Workflows controller).

### Decision

Adopt **Argo Rollouts v1.9.0** (chart `argo-rollouts:2.40.9`, 2026-03-20). Flagger is explicitly dropped.

Reasons:
1. **2026-release constraint (ADR-006)**: Flagger v1.42.0 shipped 2025-10-16 and no 2026 release exists at audit date; Argo Rollouts v1.9.0 is within the window.
2. **CRD separation**: Argo Rollouts uses `rollouts.argoproj.io`, which is disjoint from KFP's bundled Argo Workflows controller on `workflows.argoproj.io`. No leader-election contention (ADR-003 constraint).
3. **Single-ecosystem alignment**: keeps the argoproj stack (Argo CD + Argo Rollouts + Argo Workflows-via-KFP) coherent; one set of RBAC patterns, one dashboard model, one CRD idiom.
4. **Istio traffic routing**: first-class in Rollouts via `spec.strategy.canary.trafficRouting.istio`, matches the mesh already in-tree.

**AnalysisTemplate pattern**: platform ships a cluster-scoped `success-rate-p99` template (success-rate ≥ 99% + p99 ≤ 500ms from Istio `istio_requests_total` + duration histograms). Use-case Rollouts reference it by name; they MAY ship a local AnalysisTemplate with tighter SLOs.

**ml-bridge example pattern**: canary 20% → analyze → 50% → analyze → 100%. The inherited plain `ml-bridge` Deployment is scaled to 0 via Kustomize patch so pod ownership is unambiguous. The use-case-side Rollout manifest lives at `<use-case>/manifests/base/rollouts/ml-bridge-rollout.yaml`; see `<use-case>/docs/ADRS.md` ADR-019 for the test-bind use-case's concrete weights and analysis SLOs.

### Consequences

- VERSION.MD lists `flagger` under REMOVED (never actually installed — decision made before cluster adoption).
- The use-case Rollout manifest at `<use-case>/manifests/base/rollouts/ml-bridge-rollout.yaml` is the reference shape; other use-cases copy it.
- The inherited Deployment stays at `replicas: 0` permanently — do NOT delete it, it is the Kustomize inheritance anchor and its PDB/Service labels still serve the Rollout pods.

---

## ADR-017 — Retrain-on-drift automation via Argo CronWorkflow

**Status:** ACCEPTED
**Date:** 2026-04-20

### Context

Evidently + dbt populate `gold.drift_metrics` in ClickHouse on every lakehouse run. Without automation this is a dashboard-only signal. Thesis §4.3 MLOps maturity L2 requires closed-loop retraining.

### Decision

An Argo `CronWorkflow` in the `model-lifecycle` namespace runs every 6 hours (`0 */6 * * *`):
1. `measure-drift` template queries `gold.drift_metrics` for the max PSI and KS statistic in the last 24-hour window.
2. `decide-and-trigger` template: if `PSI > 0.2` **or** `KS > 0.15`, POSTs to `http://ml-pipeline.model-lifecycle.svc.cluster.local:8888/apis/v2beta1/runs` to launch the KFP `retraining_pipeline` run. That pipeline does **not** mutate the canonical Katib `flaml-automl-hpo` Experiment CR — it treats the Git-resident CR as a template, calls the Katib SDK with it, and spawns a run-scoped Experiment whose name is suffixed with the pipeline run id. The baseline Experiment stays unchanged in Git.
3. Pushes `<use-case>_retrain_on_drift_{psi,ks,triggered}` samples to Pushgateway on every probe (triggered or not) so Prometheus always has a heartbeat. The exact metric prefix and CronWorkflow name are use-case-scoped — see `<use-case>/docs/ADRS.md` ADR-017.

ClickHouse creds come from a use-case ExternalSecret bound to `secret/usecases/<use-case>/clickhouse-admin` (Vault mount path).

Thresholds (0.2 / 0.15) are tunable via the CronWorkflow `spec.workflowSpec.arguments.parameters`; defaults documented as "conservative — tune per-feature after first week of production".

### Why CronWorkflow, not Airflow

The hourly Airflow feature DAG already queries `gold.drift_metrics` but its DAG graph would become tangled if it also *triggered* KFP. Separation of concerns: Airflow is the dataflow orchestrator, Argo Workflows is the action trigger. Both share KFP's bundled Argo controller so no new operator.

### Consequences

- Closed-loop retraining is declarative and visible in the Argo Workflows UI.
- Prom alerts fire on `absent(<use-case>_retrain_on_drift_psi)` — heartbeat missing means the probe itself is broken.
- Manual override: `kubectl create -f <Workflow-from-template>` in model-lifecycle reproduces one probe.

---

## ADR-018 — OpenLineage emission mode: manual in domain DAGs, native in Flink/Spark

**Status:** ACCEPTED
**Date:** 2026-04-20

### Context

OpenLineage has three emitter modes for Airflow: (1) `openlineage-airflow` provider auto-extractors, (2) manual `RunEvent` emission from task callables, (3) dbt's own OL-native provider (which fires on every model build).

Naive "turn on auto-extractors everywhere" double-counts because dbt already emits its own events via its OL provider, and the `BashOperator` wrapping `dbt run` would re-emit them as shell-level events.

### Decision

- **Airflow (use-case DAGs)**: **manual emission** via explicit helper functions (`_ol_event`, `_ol_emit`) inside each PythonOperator callable. dbt's provider handles dbt-internal lineage. The DAG only emits for the Python-side steps it actually owns (LakeFS branch ops, Trino QC checks). The helper definitions and Variable contract live with the use-case DAGs — see `<use-case>/docs/ADRS.md` ADR-018.
- **Flink**: native OpenLineage listener configured via `pipeline.openlineage.url` and `pipeline.openlineage.namespace` in the FlinkDeployment CR (ADR-023). No manual emission.
- **Spark**: `io.openlineage:openlineage-spark_2.13:1.26.0` listener jar already wired into the spark-operator base image; env-driven config.
- **dbt**: native OL provider; dbt profiles emit on every `dbt run`/`dbt build`.

### Custom facets

Use-case DAGs MAY attach a domain-specific custom run facet (one facet per DAG, name = `<use-case>_<short-purpose>`). The facet payload is queryable in DataHub's lineage explorer and feeds the per-domain "data completeness" Grafana panel. See `<use-case>/docs/ADRS.md` ADR-018 for the test-bind use-case's facet schema.

### Consequences

- No double-counting in DataHub lineage.
- Use-case DAG code carries the small overhead of calling `_ol_emit` explicitly — acceptable for domain DAGs with <10 task callables.
- If a new use-case has simpler DAGs (pure `BashOperator` over external binaries), it may opt into auto-extractors — the manual-emission rule is scoped per use-case, not platform-mandatory.

---

## ADR-019 — `cnpg-system` exempted from Kyverno pod-hardening policies

**Status:** ACCEPTED
**Date:** 2026-04-20

### Context

Production blocker: CNPG backup pod (`cnpg-postgresql-backup-*`) restarted 46 times. Root cause: Kyverno's `require-resource-limits` and `require-read-only-root-filesystem` admission checks rejected the CNPG operator's backup pod spec, which cannot set RO root fs (barman needs a writable `/var/lib/barman` mount) and sets its own generated limits dynamically after admission.

### Decision

Add `cnpg-system` to `excludeResourceRules.namespaces` in **five** Kyverno ValidatingPolicies:
- `require-resource-limits`
- `require-read-only-root-filesystem`
- `disallow-privileged` (CNPG uses `runAsUser: 26` non-root anyway; the rule stays informative)
- `require-probes`
- `require-runAsNonRoot`

Rationale: CNPG is an **operator namespace**, not a workload namespace. Workloads (the PG `Cluster` CRs the operator manages) live in `platform-data` and remain fully policy-gated. The exemption is scoped to the operator's own pods only.

### Non-decision (explicit)

We do NOT exempt `cnpg-system` from `disallow-latest-tag` — the operator image ref is already a semver digest and keeping the rule active catches drift if a future chart bump regresses.

### Consequences

- Backup pod restart count drops from 46/day to 0.
- Other operator namespaces (strimzi-system, trivy-system, longhorn-system, chaos-mesh, etc.) are reviewed case-by-case; no blanket operator-namespace exemption.

---

## ADR-020 — Cosign verify-images scoped to internal Gitea registry only

**Status:** ACCEPTED
**Date:** 2026-04-20

### Context

The Phase B `verify-image-signatures` ImageValidatingPolicy validated **every** image pulled in the cluster. This broke pulls of public community images (bitnami, Docker Hub library, quay.io upstream operators) because no one has signed them with our Fulcio identity.

### Decision

`ImageValidatingPolicy verify-platform-images-cosign` uses `matchImageReferences` scoped to images built by **our own Tekton pipeline**:

```
- "gitea.gitops.svc.cluster.local/platform/*"
- "gitea.gitops.svc.cluster.local/use-case-*/*"   # per-use-case repos; concrete patterns per <use-case>/docs/ADRS.md ADR-020
- "localhost:5000/*"              # single-node dev registry bridge
```

**Signer identity**: `system:serviceaccount:gitops:tekton-cosign-signer` (Fulcio OIDC identity). Only this SA's signatures are trusted.

Third-party images (bitnami, upstream operators, OpenSSF-signed images) are verified by their own policies as opt-in — NOT by the platform-image policy.

### Consequences

- No more bounce-back of community images at admission.
- Any image under `gitea.gitops.svc.cluster.local/platform/` or under any registered `use-case-*` registry namespace MUST be signed by the Tekton pipeline or admission fails. This is the intended security posture.
- When a new use-case registry namespace is added, its concrete pattern must be appended to `matchImageReferences` (the use-case overlay carries the patch; see `<use-case>/docs/ADRS.md` ADR-020).

---

## ADR-021 — Sloth SLO authorship: platform owns platform-SLOs, use-case owns domain-SLOs

**Status:** ACCEPTED
**Date:** 2026-04-20

### Context

Sloth 0.12.0 generates multi-window multi-burn-rate (MWMBR) PrometheusRules from `PrometheusServiceLevel` CRs. The platform already had infra-level CRs (Kafka lag, Prometheus up-time, MinIO availability). Thesis §4.4 requires *domain-level* SLOs (prediction freshness, pipeline end-to-end latency, model registry freshness).

### Decision

**Two-tier SLO ownership**:

1. **Platform-scoped SLOs** (`platform/components/observability/sloth/prometheusservicelevels.yaml`): infrastructure concerns. Platform owns them. Example: Kafka broker availability, Prometheus scrape uptime.

2. **Use-case-scoped SLOs** (`<use-case>/manifests/base/observability/slos-<use-case>.yaml`): domain concerns. Use-case owns them.

Each use-case typically ships three domain SLOs (prediction freshness, pipeline lag, model freshness). Concrete SLI expressions, error-budget targets, and burn-rate windows are use-case-specific — see `<use-case>/docs/ADRS.md` ADR-021 for the test-bind use-case's three CRs.

All `PrometheusServiceLevel` CRs compile to 8 MWMBR alerts each (2h/5m page, 6h/30m page, 24h/2h ticket, 72h/6h ticket) labelled `release: kube-prometheus-stack` so the Prometheus Operator picks them up.

### Why not platform-owned domain SLOs

Domain-level error budgets encode *business intent* (how stale is too stale?). That intent belongs with the use-case, not with infra. Platform SLOs are about whether infra is up; domain SLOs are about whether the product works. Different authors, different lifecycles.

### Consequences

- New use-cases write their own `slos-<usecase>.yaml`; platform SLOs stay stable.
- `AlertmanagerConfig` routes use-case alerts via the `use-case=<name>` label to per-team channels.

---

## ADR-022 — KEDA ScaledObjects replace Kafka-lag HPAs for stream consumers

**Status:** ACCEPTED
**Date:** 2026-04-20

### Context

The prior design used `HorizontalPodAutoscaler` with `prometheus-adapter` `external.metrics.k8s.io/v1beta1` to scale `feature-engine` on Kafka consumer-group lag. Known issues:
1. **Latency**: adapter scrape interval (15s) + HPA loop (15s) + Prometheus scrape (30s) = up to 60s staleness.
2. **Metric fragility**: `kafka_consumergroup_lag` must be relabelled in prometheus-adapter config; any Strimzi exporter rename silently breaks scaling.
3. **Feast/Cache mix-up**: `feature-engine` is a Kafka consumer *and* has REST traffic; a single CPU-based HPA confuses the two signals.

### Decision

Adopt **KEDA 2.x ScaledObjects** with native `kafka` triggers for every stream-consuming Deployment. The ScaledObject manifests live in `<use-case>/manifests/base/scaling/scaledobjects.yaml`; each use-case names its own Deployment-to-topic bindings, lag thresholds, and min/max replica bounds. See `<use-case>/docs/ADRS.md` ADR-022 for the test-bind use-case's concrete topic-and-threshold table.

KEDA queries Kafka brokers **directly** (offsets API) via `bootstrapServers: platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092` — no Prometheus-in-the-loop, ~5s reaction time.

**HPA/KEDA collision**: KEDA generates its own HPA from the ScaledObject. Any pre-existing custom-metric HPA on the same Deployment **must be deleted** (not patched) to avoid dual-controller fighting; the use-case's HPA manifest collapses to an explanation comment after migration.

**Deployments that keep their HPA**: `dashboard-backend` (CPU-based). That's the only HPA retained after ADR-026 moved the gateway over to KEDA as well.

### Consequences

- Scale-up reaction time drops from ~60s to ~5-10s.
- Starts the retirement of `prometheus-adapter` for stream scaling; ADR-026 finishes the job by migrating the last custom-metric HPA (gateway HTTP-RPS) onto KEDA and deleting the adapter entirely.
- When Kafka credentials are required (SASL), ExternalSecret `keda-kafka-trigger` holds them; current plain-listener bootstrap doesn't need them.

---

## ADR-023 — FlinkDeployment CR replaces in-pod Flink Deployment

**Status:** ACCEPTED
**Date:** 2026-04-20

### Context

The in-pod `flink-job` Deployment was a vanilla Kubernetes Deployment running the Flink job in application mode inside a single container. Limitations:
1. No JobManager/TaskManager role separation — a single pod was both.
2. Manual savepoint management (no operator-driven checkpointing into S3).
3. No Kubernetes-native HA (Flink's own ZK/k8s HA not wired).
4. Duplicated Prometheus scrape endpoints on every TM pod (cardinality bloat).

Apache Flink Kubernetes Operator 1.14.0 was already installed in the platform but unused.

### Decision

Replace the in-pod Deployment with a `flink.apache.org/v1beta1 FlinkDeployment` CR. The CR is **use-case-scoped** (image, jar entry class, checkpoint path, consumer-group id, S3 ExternalSecret name all encode domain specifics) and lives at `<use-case>/manifests/base/flink/flinkdeployment.yaml`. Platform-side requirements:

- **Mode**: `application` (driver-in-JM).
- **Operator base image**: Flink 2.2.0 (platform-pinned).
- **Observability**: OpenLineage listener (ADR-018) emits to DataHub GMS. Metrics reporter on `:9249` (single JM port — TaskManager scrape removed, cardinality drops ~10×).
- **RBAC**: ServiceAccount + Role + RoleBinding scoped to the use-case namespace; operator reconciles cluster-wide.

See `<use-case>/docs/ADRS.md` ADR-023 for the test-bind use-case's concrete image, jarURI, entryClass, checkpoint path, and ExternalSecret name.

**Transition**: ADR-025 supersedes the prior "scale to `replicas: 0`" placeholder pattern. The legacy Deployment is **deleted** (not parked), and the operator-managed pods carry their own labels. Kafka consumer-group transition is use-case-specific — see `<use-case>/docs/RUNBOOK.md` §12.5 for the cutover sequence (scale legacy to 0 BEFORE applying FlinkDeployment, to avoid split-brain rebalancing).

### Consequences

- Savepoint / restore is operator-driven (`kubectl annotate flinkdeployment ... savepoint/trigger=foo`).
- Flink-side HA via the operator's k8s-native HA services (ADR-011 compatible).
- ServiceMonitor now scrapes the single JM Prometheus reporter port 9249 — `network-policies.yaml` was amended accordingly.

---

## ADR-024 — NetworkPolicy is the sole L7 enforcement in istio-disabled namespaces

**Status:** ACCEPTED
**Date:** 2026-04-20

### Context

ADR-009 established an Istio opt-out allowlist — namespaces that cannot tolerate sidecars (legacy pods, operators that fight Envoy, use-cases with hot-path latency SLOs). Use-case namespaces with hot-path SLOs may register on the allowlist (`istio-injection: disabled`) via the use-case overlay's Kyverno patch.

Consequence: Istio `AuthorizationPolicy` CRs applied **inside** an istio-disabled use-case namespace have no enforcer to read them. Only the `istio-ingressgateway` in `istio-system` still sees that use-case's traffic.

### Decision

**Two-plane enforcement split** for istio-disabled namespaces:

1. **Edge (L7 AuthZ)** — `AuthorizationPolicy` CRs in the `istio-system` namespace scoped to `selector: istio: ingressgateway`. The CRs live with the use-case at `<use-case>/manifests/base/authorization/edge-authz.yaml` (DENY `/admin/*`, `/internal/*`, `/_debug/*`; ALLOW `GET|POST|OPTIONS /api/v1/*`, `/healthz`, `/metrics`; CIDR-scoped `GET /dashboard/*`). Concrete host globs and dashboard CIDRs are use-case-specific — see `<use-case>/docs/ADRS.md` ADR-024.

2. **East-west (L3/4 allowlist)** — `NetworkPolicy` CRs in the use-case namespace. Required patterns:
   - `default-deny-ingress` (baseline).
   - `allow-same-namespace` (intra-ns trust — single trust boundary).
   - Per-peer-namespace rules **named by destination pods** (selectors enumerate the receiving Deployment names, NOT `{}`).
   - `allow-prometheus-scrape` includes the metrics port published by the use-case workloads (e.g. `9249` for Flink, ADR-023).
   - `allow-ingress-to-gateway` restricts istio-system → only the use-case gateway pod on its declared port (prior coarse rule exposed the whole namespace).

### Rejected alternatives

- **Flip the use-case into the mesh.** Sidecar adds ~5ms p50 on the gateway hot path. Whether a use-case can absorb that is decided by its own `p99` SLO; the ADR-009 decision tree may explicitly keep it OUT. If a use-case wants to flip, re-read ADR-009 first.
- **Cilium network policies with L7 (`toFQDNs`/`toPorts[].rules.http`).** Cilium is not the CNI at the moment (k3s flannel default); pulling it in is a different ADR.

### Consequences

- NetworkPolicy is the **only** east-west authorization layer in istio-disabled use-case namespaces. If it's misconfigured, pods are either unreachable or too-reachable — there's no mesh fallback.
- Every peer namespace that needs to reach a use-case must be named explicitly; adding a new caller means editing `<use-case>/manifests/base/network-policies.yaml`.
- Platform-scoped AuthorizationPolicies (`default-deny` in data-ingestion, etc.) remain authoritative for mesh-enrolled namespaces.

---

## ADR-025 — Delete scale-to-zero placeholders; platform templates are copy-not-inherit when a use case replaces them

**Status:** ACCEPTED
**Date:** 2026-04-21
**Supersedes:** Transition clauses in ADR-016 ("inherited Deployment stays at `replicas: 0` permanently") and ADR-023 ("inherited `flink-job` Deployment scaled to `replicas: 0` via `patches/flink-job.yaml`"). Also retires LLM/unused ClusterServingRuntime templates and orphan scale-to-zero patches in the KServe controller bundle.

### Context

The AUDIT_FINAL_2026-04-20 E.6 follow-up surfaced three classes of dead weight in the Git tree:

1. **Scale-to-zero placeholders.** ADR-016 and ADR-023 left `replicas: 0` Deployments in place so that the inherited platform Service / PDB / labels kept targeting the replacement (Argo Rollout ReplicaSet or FlinkDeployment operator-managed pods). In practice the placeholder cost more than it bought:
   - The PDB and Service attached to the placeholder's `app:` label also match the replacement's pods, so the `replicas: 0` Deployment was never actually load-bearing — both selectors worked regardless of whether the Deployment existed.
   - Every new use case forked from the test-bind use case inherited a zero-replica pod template and its patch file, creating ongoing drift targets (image tags, env vars, resource limits) that had to be kept in sync for no runtime effect.
   - Kustomize overlays carried image-transformer / replica / resources patches against a Deployment that kustomize would never render — silent no-ops that misled readers.

2. **KServe LLM runtime templates we never deploy.** `kserve-serving-runtimes.yaml` shipped `kserve-huggingfaceserver`, `kserve-huggingfaceserver-multinode`, `kserve-paddleserver`, `kserve-pmmlserver`, `kserve-predictiveserver`, `kserve-tensorflow-serving`, `kserve-torchserve`, `kserve-tritonserver`, and eight `LLMInferenceServiceConfig` CRs. The thesis palette is tabular ML only (FLAML over LightGBM / XGBoost / CatBoost / RandomForest — `Bab_1.tex:143`; per-use-case model selection lives at `<use-case>/manifests/base/configmaps/models.yaml`). None of the LLM/GPU/TF/Torch/PMML runtimes have an `InferenceService` referencing them; carrying them in Git was a maintenance and image-security tax.

3. **Scale-to-zero patches targeting non-existent Deployments.** `platform/components/model-serving/kserve/kustomization.yaml` patched `llmisvc-controller-manager` and `kserve-localmodel-controller-manager` to `replicas: 0`. Neither Deployment is rendered by the controller bundle — the patches were inert.

### Decision

**Delete, don't placeholder.** When the replacement mechanism (Rollout, FlinkDeployment, PodMonitor) has a clean way to target the right pods without the placeholder's label being present, remove the placeholder entirely. Specifically:

1. **`platform/services/base/deployments/ml-bridge.yaml`** is rewritten to ship **only the Service**. Pod lifecycle is owned by the use-case Rollout at `<use-case>/manifests/base/rollouts/ml-bridge-rollout.yaml`. The Service selector (`app: ml-bridge`) matches Rollout-produced ReplicaSet pods directly — no Deployment required.

2. **`platform/services/base/deployments/flink-job.yaml`** is deleted. Stream processing lives in each use case as a `FlinkDeployment` CR (ADR-023). The operator-managed pods carry `app: <use-case>-flink-job` + `component: jobmanager|taskmanager`; PodDisruptionBudget, PodMonitor, and NetworkPolicy now target those labels directly. Concrete file paths and selector lists are use-case-specific — see `<use-case>/docs/ADRS.md` ADR-025 for the test-bind use-case's PDB / PodMonitor / NetworkPolicy bindings. Required platform-side property: the FlinkDeployment's `podTemplate` declares named ports `metrics` (9249) and `jm-rest` (8081) so the PodMonitor can scrape by name rather than raw target port.

3. **`platform/components/model-serving/kserve/kserve-serving-runtimes.yaml`** is rewritten to keep only `kserve-mlserver` (active path for `modelFormat: mlflow` via MinIO `s3://mlflow`), plus `kserve-lgbserver`, `kserve-sklearnserver`, `kserve-xgbserver` (native-format fallbacks aligned with the FLAML palette). The eight LLM/GPU/TF/Torch/PMML runtimes and the eight `LLMInferenceServiceConfig` CRs are deleted.

4. **`platform/components/model-serving/kserve/kustomization.yaml`** drops the two scale-to-zero patches against `llmisvc-controller-manager` and `kserve-localmodel-controller-manager` (the target Deployments never existed — the patches were no-ops).

5. All overlay `images:` / `replicas:` / resource-limit patches that targeted `name: flink-job` are removed from `platform/services/overlays/generic/` and from every use-case overlay. They were no-ops once the Deployment was gone and misled readers. The FlinkDeployment's hardcoded image name (use-case-specific, baked into the operator's base image) is correct for every environment because the build pipeline tags/pushes that exact name; overlays no longer attempt to rewrite it.

6. The use-case overlay deletes `<use-case>/manifests/base/patches/flink-job.yaml` and `<use-case>/manifests/base/patches/ml-bridge-disable-deployment.yaml` along with their `patches:` references in `base/kustomization.yaml` and `base-phase1/kustomization.yaml`. See `<use-case>/docs/ADRS.md` ADR-025 for the per-file deletion list.

### Rejected alternatives

- **Keep placeholders, add lint.** We could leave the `replicas: 0` Deployments and write a conftest / kyverno policy that flags any future edit to their spec. The placeholders would still mislead every `kubectl get deploy` reader and every copy-for-new-use-case. The lint is work we pay forever; deleting is paid once.
- **Promote the FlinkDeployment CR to `platform/services/base`.** The CR embeds the use-case image name, the use-case jar entry class, use-case checkpoint paths, and the use-case consumer-group id. Lifting it into the platform either re-introduces templating noise (Jsonnet, Helm) or duplicates nine lines that every use case must override. Leaving the CR in the use case is consistent with ADR-013's domain-agnostic split.
- **Convert the PodMonitor back into a ServiceMonitor.** That would require shipping an additional `Service` resource alongside the FlinkDeployment that exposes port 9249 to Prometheus. PodMonitor removes that Service-for-metrics-only pattern — the operator-managed pods are directly scraped, saving one resource per FlinkDeployment.

### Consequences

- Future use cases that adopt Argo Rollouts for ml-bridge inherit ONLY the Service from the platform. They must ship their own Rollout at `<use-case>/manifests/base/rollouts/ml-bridge-rollout.yaml`. This is explicit, not hidden in a scale-to-zero placeholder.
- Future use cases that adopt Flink inherit NOTHING from the platform; they author `<use-case>/manifests/base/flink/flinkdeployment.yaml` (image, entry class, checkpoint paths). The platform operator in `platform/components/data-processing/flink/` still watches cluster-wide, so no platform change is needed per new use case.
- The KServe bundle's image footprint drops significantly: `kserve/huggingfaceserver`, `kserve/torchserve`, `kserve/tritonserver`, and the localmodel-controller image are no longer pulled on cluster bootstrap.
- `VERSION.MD` and `REMEDIATION_RUNBOOK.md` E.6 close; `AUDIT_FINAL_2026-04-20.md` §E.6 moves from OPEN to RESOLVED.
- If a new use case needs one of the deleted KServe runtimes, re-add only that runtime (not the whole LLM subsystem). The deletion is scoped by the current palette, not by ideology.

---

## ADR-026 — Retire `prometheus-adapter`; KEDA is the single custom/external metrics plane

**Status:** ACCEPTED
**Date:** 2026-04-21
**Extends:** ADR-022 (KEDA ScaledObjects for Kafka-lag consumers)

### Context

ADR-022 migrated the three Kafka-consuming Deployments off `prometheus-adapter` + HPA onto native KEDA kafka triggers and noted that the adapter stayed "for other external-metrics consumers." One such consumer remained: `gateway-hpa` in both `platform/services/base/hpa/autoscaling.yaml` and the use-case HPA overlay (`<use-case>/manifests/base/hpa/autoscaling.yaml`), which used a `Pods`-type custom metric `http_requests_per_second` served by the adapter translating `http_requests_total` from the gateway's ServiceMonitor into a per-replica rate.

Two things now tip the balance toward full retirement of the adapter:

1. **Version hygiene (VERSION.MD:63).** The current HEAD is `registry.k8s.io/prometheus-adapter/prometheus-adapter:v0.12.0`, tagged 2024-05-17. The project has not cut a release since and fails the repository-wide "minimum 2026 release" rule. Keeping it on an ADR-006 exception means shipping 2024 Go + k8s libs in a production plane for the sake of a single HPA.
2. **Single point of duplication.** KEDA's metrics-apiserver is already on-cluster (`platform/components/common/keda/helm-release.yaml`, KEDA 2.19.0, 2026-02-02). It exposes `external.metrics.k8s.io` for ScaledObjects. Running a second external-metrics APIService alongside it costs two `apiregistration.k8s.io/v1` APIService registrations, a Deployment, a ConfigMap, five ClusterRole/Binding objects, and a second hop on every custom-metric HPA decision.

### Decision

Retire `prometheus-adapter` entirely. Delete `platform/components/observability/prometheus-adapter/`, drop the entry from the observability kustomization, and the `PrometheusAdapterDown` alert from the platform rules. Migrate the gateway's custom-metric HPA to a KEDA `ScaledObject` with three triggers — `prometheus` for the HTTP RPS signal, `cpu` + `memory` for resource utilisation — OR-combined by KEDA into a single HPA (`keda-hpa-gateway-http-rps`).

| Old HPA metric | New KEDA trigger | Query / threshold |
|---|---|---|
| `Pods http_requests_per_second (100)` | `prometheus`, `metricType: AverageValue`, threshold 100 | `sum(rate(http_requests_total{app="gateway"}[2m]))` against `kube-prometheus-stack-prometheus.observability:9090` |
| `Resource cpu (Utilization 60)` | `cpu`, `metricType: Utilization`, value 60 | KEDA built-in |
| `Resource memory (Utilization 75)` | `memory`, `metricType: Utilization`, value 75 | KEDA built-in |

The `advanced.horizontalPodAutoscalerConfig.behavior` stanza preserves the old HPA's scale-up burst (Max of +100% or +4 pods per 15s) and 5-minute scale-down window verbatim — KEDA forwards `behavior` straight through to the generated HPA.

### Live apply ordering

APIServices must be deleted BEFORE their backing Deployment, or kubectl apply leaves the APIService pointing at a non-existent Service and every custom-metric HPA query returns `failed to fetch metric` for the duration of the next reconcile (~30 min default). The cutover is:

```bash
# 1) delete adapter APIServices first — removes the external-metrics endpoint
kubectl delete apiservice v1beta1.custom.metrics.k8s.io v1beta1.external.metrics.k8s.io --ignore-not-found

# 2) delete the old gateway-hpa so it doesn't collide with the new KEDA-owned HPA
#    (concrete namespace + HPA name is use-case-specific — see <use-case>/docs/RUNBOOK.md §12.10)
kubectl delete hpa -n use-case-<X> <use-case>-gateway-hpa --ignore-not-found

# 3) apply the new tree (creates ScaledObject, KEDA spawns keda-hpa-gateway-http-rps)
kubectl apply -k <use-case>/manifests/overlays/local

# 4) remove the adapter Deployment + its objects (pruned by kustomize too)
kubectl -n observability delete deploy,svc,sa,cm,clusterrole,clusterrolebinding,rolebinding -l app=prometheus-adapter --ignore-not-found
kubectl -n kube-system delete rolebinding prometheus-adapter-auth-reader --ignore-not-found
```

### Rejected alternatives

- **Keep the adapter, fix the version rule with an exception.** The exception already exists (ADR-006) — the problem is that it buys nothing anymore. With zero HPA consumers, the adapter has no reason to be on-cluster.
- **Migrate gateway to a vanilla `Pods` HPA with `metrics-server` as the source.** `metrics-server` only serves Resource metrics (CPU/memory); HTTP RPS is not available. Would require a second custom-metrics provider to replace the one we just retired.
- **Put the KEDA scaler on the Ingress (Istio `virtualservice_request_rate` equivalent) instead of the gateway pod metric.** More "architecturally right" but higher-risk: the Istio control plane's metric naming has shifted twice in the last year, and we'd lose the direct link between the gateway's own instrumentation (`http_requests_total` from the app's middleware) and the scaling signal. Defer this to a later ADR if we need to scale per-route.

### Consequences

- The observability namespace loses one Deployment, two APIServices, one Service, one ConfigMap, one ServiceAccount, four ClusterRoleBindings, one RoleBinding, and two ClusterRoles. Net win on footprint and control-plane reconcile churn.
- `kafka-exporter` stays (still exposes `kafka_consumergroup_lag` to Prometheus for Grafana dashboards and alerting), but its comment is updated — it is no longer a feed for an HPA.
- Every HPA in the tree is now either (a) CPU/memory-only via `kind: HorizontalPodAutoscaler`, or (b) KEDA-managed via `ScaledObject`. No third path.
- Future use-cases that want custom-metric autoscaling ship a `ScaledObject` with a `prometheus` trigger — the same shape as `gateway-http-rps`. The adapter configmap of "seriesQuery → name rename → metricsQuery" pattern disappears.
- `REMEDIATION_RUNBOOK.md §10.10 (prometheus-adapter re-deploy)` is obsolete and removed in the same commit. KEDA's equivalent runbook lives at `§10.10 KEDA metrics-apiserver restart`.

---

## ADR-027 — Meltano replaces Airbyte (license compliance)

**Status:** ACCEPTED
**Date:** 2026-04-23

### Context

Airbyte V2 (chart 1.8.1) uses Elastic License v2 (ELv2), which is source-available but NOT OSI-approved open source. The thesis title explicitly claims "Pemanfaatan Open Source Tools" — every tool in the platform must carry an OSI-approved license. This is the same class of violation that prompted the HashiCorp Vault → OpenBao migration (ADR-008 amendment).

Airbyte fills the "schedule-driven batch ELT for SaaS connectors" niche, complementing the Kafka streaming path. The platform already runs Apache Airflow as its primary data orchestrator.

### Decision

Replace Airbyte with **Meltano v3.9.3** (MIT license, SPDX `MIT`).

**Architecture change:** Airbyte was a fleet of 10+ microservices (server, webapp, worker, workload-launcher, temporal, bootloader, cron, connector-builder, workload-api-server, metrics). Meltano is a CLI tool with no long-running services. The platform ships runtime infrastructure only:

1. **PostgreSQL** — dedicated `meltano` database on the CNPG cluster (replaces `airbyte` DB).
2. **MinIO** — `meltano-state` bucket for state backend (replaces `airbyte-storage`).
3. **ExternalSecrets** — DB + MinIO credentials from OpenBao (2 ExternalSecrets, down from 5).
4. **ConfigMap** — runtime environment variables for Meltano pods.

**No Deployment, no Service, no Ingress, no OIDC client.** Meltano's web UI was removed in v3.0.0. Pipelines are orchestrated by Airflow's `KubernetesPodOperator`, which launches ephemeral `meltano run <tap> <target>` pods. Use-cases build derived images from `meltano/meltano:v3.9.3-python3.11-slim` containing their `meltano.yml` + connector definitions.

**Removed Airbyte-specific infrastructure:**
- 5 ExternalSecrets (airbyte-db, airbyte-minio, airbyte-admin, airbyte-auth, airbyte-oidc)
- 3 Vault secret paths (platform/airbyte/admin, platform/airbyte/auth, platform/dex/clients/airbyte)
- Dex OIDC client registration
- ServiceAccount `airbyte-admin`
- ArgoCD Helm source `airbytehq.github.io/helm-charts`
- Local overlay `patch-airbyte-single.yaml`

### Consequences

- Platform footprint drops significantly: ~12 Airbyte pods → 0 long-running pods. ELT runs as ephemeral Airflow-managed pods.
- Meltano supports 550+ Singer connectors (vs Airbyte's 600+). Singer ecosystem is fully open source.
- No web UI for pipeline management — operators use Airflow UI + CLI. Acceptable for a developer-oriented platform.
- Use-cases own their `meltano.yml` and derived images; platform provides runtime only. Clean separation of concerns.
- Thesis license compliance: all tools now carry OSI-approved licenses.

---
