# =============================================================================
# DataOps/MLOps Platform — Root Makefile
# =============================================================================
# Composable phase orchestration for platform deployment + use-case dispatch.
#
# Repository layout:
#   ./platform/         — Use-case-agnostic platform components (single-node k3s)
#   ./use-case-crypto/  — Crypto-specific microservices, DAGs, dbt models
#
# =============================================================================
# Bootstrap from fresh VPS (recommended order):
# =============================================================================
#   make install-k3s            # k3s + kubectl + helm + kustomize + yq + jq
#                               # (skips Docker; k3s ships own containerd)
#   make preflight              # verify all CLIs reachable + cluster context
#   make phase-base             # cert-mgr + istio + ESO/OpenBao + ArgoCD + storage
#   make phase-<X>              # add layers (observability/stream/feast/...)
#   make scale-up COMPONENT=<c> # scale workloads (manifests baseline replicas=0)
#
# Optional add-ons:
#   make install-docker-registry  # Docker + registry:5000 (for image builds)
#   make install-build-tools      # Go/Rust/Python/Bun/Java/Mill/xmake
#   make setup-toolchain          # everything in one shot
#
# Reset / reinstall:
#   make uninstall-k3s            # remove k3s only (binaries + data dirs)
#   make reinstall-k3s            # uninstall + fresh k3s install
#   make nuke-vps                 # FULL VPS reset (k3s + Docker + toolchains
#                                 # + caches gone; claude/project preserved)
#
# =============================================================================
# Phase composability — pick smallest phase that satisfies your goal.
#
# Layer-only phases (one concern per phase):
#   make phase-base                  Cert-manager + Istio + ESO + OpenBao + CNPG + MinIO + ArgoCD
#   make phase-observability         + LGTM stack (Prom/Grafana/Loki/Tempo/Alloy)
#   make phase-ingest-stream         + Kafka only (no proc, no Feast)
#   make phase-stream                Kafka + Flink (no Feast)
#   make phase-batch                 Spark + Airflow + dbt + Trino + Superset + GE (no Feast)
#   make phase-feast                 Redis + Feast standalone (BYO upstream)
#   make phase-mlflow                MySQL + MLflow standalone
#   make phase-kubeflow              MySQL + Kubeflow Pipelines/Trainer/Katib/Notebooks
#   make phase-serve                 Knative + KServe only (BYO model)
#
# Cross-layer phases (compose two stages):
#   make phase-stream-to-feast       Stream ingest → Flink → Feast
#   make phase-batch-to-feast        Batch ingest → Spark/Airflow/dbt/GE → Feast
#   make phase-feast-to-mlflow       Feast → MLflow only
#   make phase-feast-to-kubeflow     Feast → Kubeflow only
#   make phase-feast-to-training     Feast → MLflow + Kubeflow
#   make phase-feast-to-serving      Feast online store → KServe
#   make phase-mlflow-to-serving     MLflow → KServe (no Feast, no Kubeflow)
#   make phase-kubeflow-to-serving   Kubeflow → KServe (no Feast, no MLflow)
#   make phase-train-to-serving      MLflow + Kubeflow → KServe
#
# End-to-end phases (full pipeline):
#   make phase-stream-e2e            Stream → Feast → Train → Serve
#   make phase-batch-e2e             Batch → Feast → Train → Serve
#   make phase-governance            DataHub + OpenSearch + OpenLineage + ingestion
#   make phase-gitops                ArgoCD + Tekton + Gitea + Argo Rollouts
#   make phase-security              Chaos Mesh + Falco + Trivy + Velero + APISIX (opt-in)
#   make phase-auth                  RBAC + Dex/oauth2-proxy + SpiceDB authz (opt-in)
#   make phase-full                  Everything (incl. all add-ons + RBAC + auth + security extras)
#
# Full-stack combos (platform phase + use-case-crypto in one shot):
#   make full-stream                 phase-stream-e2e + crypto deploy (all sub-phases)
#   make full-batch                  phase-batch-e2e  + crypto deploy (all sub-phases)
#   make full-stream-with-data       phase-stream-e2e + crypto build + data sub-phase only
#   make full-batch-with-data        phase-batch-e2e  + crypto build + data sub-phase only
#   make full                        phase-full + crypto deploy (everything)
#
# Retry tuning (each apply-component.sh call retries on CRD-before-CR /
# slow-webhook / slow-controller boot. Defaults: 10 attempts × 10s = 100s window):
#   make phase-base APPLY_MAX_ATTEMPTS=20 APPLY_DELAY=15
#
# Per-component install (any of ~70 components):
#   make install-<component>         e.g. install-kafka, install-feast
#   make uninstall-<component>
#
# Per-namespace install (apply every component in a namespace):
#   make install-ns-<namespace>      e.g. install-ns-storage
#
# Operations:
#   make scale-zero-all              Scale all Deploys + STS to 0
#   make scale-up COMPONENT=feast REPLICAS=2
#   make scale-down COMPONENT=feast
#   make wipe-data                   Drop PVCs in storage namespaces
#   make nuke                        Delete all platform namespaces + CRDs
#   make status                      Pod state across all namespaces
#   make events                      Recent cluster events
#
# Use-case dispatch:
#   make usecase-crypto-up           Deploy use-case-crypto microservices
#   make usecase-crypto-down
#   make usecase-crypto-status
#
# Scalability primitives (HPA / VPA / KEDA):
#   make install-hpa COMPONENT=feast
#   make install-keda-scaledobject COMPONENT=flink
# =============================================================================

KUBECTL ?= kubectl
HELM ?= helm
COMPONENT ?=
REPLICAS ?= 1

# Retry tuning for apply-component.sh — handles CRD-before-CR + slow webhook boot.
# Override per-call:  make phase-base APPLY_MAX_ATTEMPTS=20 APPLY_DELAY=15
APPLY_MAX_ATTEMPTS ?= 10
APPLY_DELAY ?= 10

PLATFORM_DIR := platform
USECASE_DIR := use-case-crypto
SCRIPTS := scripts
COMPONENTS := $(PLATFORM_DIR)/components
SCALABILITY := $(PLATFORM_DIR)/scalability

# Generic (domain-agnostic) container images built from platform/services/.
# Format: <image-name>:<service-subdir-under-platform/services>
# Each Dockerfile is self-contained — build context = service directory.
# Build via `make platform-build-services`; consumed by use-case retag step.
PLATFORM_REGISTRY ?= localhost:5000
PLATFORM_IMAGE_TAG ?= latest
PLATFORM_SERVICES := \
  rest-collector:ingestion/rest-collector \
  validator:quality/validator \
  analyzer:quality/analyzer \
  feature-engine:processing/stream/feature-engine \
  flink-job:processing/stream/flink-job \
  vector-processing:processing/vector \
  trainer:training/trainer \
  drift-detector:training/drift \
  retraining:automation/retraining \
  materialization:automation/materialization \
  gateway:serving/gateway \
  feature-cache:serving/feature-cache \
  inference-engine:serving/inference-engine \
  scoring:serving/scoring \
  evidently-reporter:observability/evidently-reporter

# Pass-through to scripts/render-scalability.sh, scripts/scale.sh, scripts/apply-component.sh
export KIND CPU_TARGET MEM_TARGET MODE CPU_MIN CPU_MAX MEM_MIN MEM_MAX MIN MAX TRIGGER TRIGGER_META NS NUKE_ALL FORCE
export MAX_ATTEMPTS=$(APPLY_MAX_ATTEMPTS)
export DELAY=$(APPLY_DELAY)

# Color helpers
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
BLUE := \033[0;34m
NC := \033[0m

.DEFAULT_GOAL := help

# =============================================================================
# HELP
# =============================================================================
.PHONY: help
help: ## Show grouped help
	@printf "\n$(BLUE)═══ DataOps/MLOps Platform ═══$(NC)\n\n"
	@printf "$(YELLOW)Composable Phases:$(NC)\n"
	@awk 'BEGIN{FS=":.*##"} /^phase-[a-z0-9-]+:.*##/ {printf "  $(GREEN)%-28s$(NC) %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@printf "\n$(YELLOW)Full-Stack Combos (platform + use-case-crypto):$(NC)\n"
	@awk 'BEGIN{FS=":.*##"} /^full(-[a-z0-9-]+)?:.*##/ {printf "  $(GREEN)%-28s$(NC) %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@printf "\n$(YELLOW)Atom Targets:$(NC)\n"
	@awk 'BEGIN{FS=":.*##"} /^atom-[a-z0-9-]+:.*##/ {printf "  $(GREEN)%-28s$(NC) %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@printf "\n$(YELLOW)Per-Namespace Install:$(NC)\n"
	@awk 'BEGIN{FS=":.*##"} /^install-ns-[a-z0-9-]+:.*##/ {printf "  $(GREEN)%-28s$(NC) %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@printf "\n$(YELLOW)Toolchain Setup:$(NC)\n"
	@awk 'BEGIN{FS=":.*##"} /^(setup-toolchain|install-k3s|install-deploy-tools|install-build-tools|install-docker-registry|uninstall-k3s|reinstall-k3s|nuke-vps|preflight):.*##/ {printf "  $(GREEN)%-28s$(NC) %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@printf "\n$(YELLOW)Operations:$(NC)\n"
	@awk 'BEGIN{FS=":.*##"} /^(scale-|wipe-|nuke|status|events|wait-|set-replicas)[a-z0-9-]*:.*##/ {printf "  $(GREEN)%-28s$(NC) %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@printf "\n$(YELLOW)Image Build (generic + use-case):$(NC)\n"
	@awk 'BEGIN{FS=":.*##"} /^(platform-(registry-up|(registry|build|push|clean)-services)|usecase-crypto-(build|images)):.*##/ {printf "  $(GREEN)%-28s$(NC) %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@printf "\n$(YELLOW)Use-Case Dispatch:$(NC)\n"
	@awk 'BEGIN{FS=":.*##"} /^usecase-[a-z0-9-]+:.*##/ {printf "  $(GREEN)%-28s$(NC) %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@printf "\n$(YELLOW)Per-component install:$(NC)  make install-<component>\n"
	@printf "$(YELLOW)Per-component uninstall:$(NC) make uninstall-<component>\n"
	@printf "$(YELLOW)List all components:$(NC)    make list-components\n\n"
	@printf "$(YELLOW)Retry knobs:$(NC) APPLY_MAX_ATTEMPTS=$(APPLY_MAX_ATTEMPTS) APPLY_DELAY=$(APPLY_DELAY)s\n"
	@printf "  $(BLUE)e.g. slow VPS:$(NC) make phase-base APPLY_MAX_ATTEMPTS=20 APPLY_DELAY=15\n\n"

.PHONY: list-components
list-components: ## Print every available component name
	@bash $(SCRIPTS)/list-components.sh

# =============================================================================
# PREFLIGHT — verify required tooling on this host
# =============================================================================
.PHONY: preflight
preflight: ## Verify kubectl, helm, kustomize, kubectl context
	@bash $(SCRIPTS)/preflight.sh

.PHONY: setup-toolchain install-k3s install-deploy-tools install-build-tools install-docker-registry uninstall-k3s reinstall-k3s nuke-vps

setup-toolchain: ## Install everything (k3s + cluster CLIs + Docker + build tools) — full one-shot
	@bash $(SCRIPTS)/setup-toolchain.sh

install-k3s: ## Install k3s + cluster CLIs only (no Docker, no build tools) — minimal deploy
	@SKIP_DOCKER=1 SKIP_REGISTRY=1 SKIP_BUILD_TOOLS=1 bash $(SCRIPTS)/setup-toolchain.sh

install-deploy-tools: ## Install helm + kustomize + yq + jq only (no k3s, no Docker)
	@SKIP_DOCKER=1 SKIP_REGISTRY=1 SKIP_BUILD_TOOLS=1 SKIP_K3S=1 bash $(SCRIPTS)/setup-toolchain.sh

install-build-tools: ## Install Go + Rust + Python + Bun + Java + Mill + xmake only (no cluster)
	@SKIP_DOCKER=1 SKIP_REGISTRY=1 SKIP_K3S=1 bash $(SCRIPTS)/setup-toolchain.sh

install-docker-registry: ## Install Docker + local registry:5000 (opt-in for use-case-crypto image builds)
	@SKIP_K3S=1 SKIP_BUILD_TOOLS=1 bash $(SCRIPTS)/setup-toolchain.sh

uninstall-k3s: ## Uninstall k3s completely + all residual state (true fresh VPS parity) — DESTRUCTIVE
	@if [ -x /usr/local/bin/k3s-killall.sh ]; then \
		echo "==> Step 1: k3s-killall.sh (stop pods + flush iptables + tear down CNI)"; \
		sudo /usr/local/bin/k3s-killall.sh 2>/dev/null || true; \
	fi
	@if [ -x /usr/local/bin/k3s-uninstall.sh ]; then \
		echo "==> Step 2: k3s-uninstall.sh (remove binaries + /var/lib/rancher + systemd unit)"; \
		sudo /usr/local/bin/k3s-uninstall.sh; \
	else \
		echo "==> k3s already uninstalled"; \
	fi
	@echo "==> Step 3: purge residual k3s/CNI/audit/sysctl state"
	@sudo rm -rf \
		/etc/rancher /var/lib/rancher /var/lib/kubelet \
		/run/k3s /run/flannel \
		/etc/cni /opt/cni /var/lib/cni \
		/var/log/kubernetes /var/log/pods /var/log/containers \
		/etc/sysctl.d/99-k3s-platform.conf \
		/etc/systemd/resolved.conf.d/dns.conf \
		2>/dev/null || true
	@rm -rf $$HOME/.kube 2>/dev/null || true
	@echo "==> Step 4: reload sysctl + systemd-resolved"
	@sudo sysctl --system >/dev/null 2>&1 || true
	@sudo systemctl restart systemd-resolved 2>/dev/null || true
	@echo "==> k3s fully purged. VPS k3s state: fresh."

reinstall-k3s: uninstall-k3s install-k3s ## Uninstall k3s then fresh install (clean re-deploy)
	@echo "==> k3s reinstalled. Configure kubeconfig:"
	@echo "    sudo install -m 600 -o $$USER /etc/rancher/k3s/k3s.yaml ~/.kube/config"

nuke-vps: ## Reset VPS to fresh state (k3s + Docker + toolchains + caches gone, claude preserved) — DESTRUCTIVE
	@bash $(SCRIPTS)/nuke-vps.sh

# =============================================================================
# GENERIC PER-COMPONENT INSTALL / UNINSTALL
# =============================================================================
# Pattern target: dispatches to apply-component.sh which finds the component
# under platform/components/<NS>/<name> and runs `kubectl apply -k`.
# For helm-release.yaml ArgoCD Applications, ArgoCD must be running first
# (install-argo-cd as part of phase-base).

.PHONY: install-% uninstall-% wait-% prune-stuck-sandboxes

install-%: ## Install single component by name
	@bash $(SCRIPTS)/apply-component.sh apply $*
	@bash $(SCRIPTS)/prune-stuck-sandboxes.sh --all 120 || true

uninstall-%: ## Uninstall single component by name
	@bash $(SCRIPTS)/apply-component.sh delete $*

wait-%: ## Wait for a component pods Ready
	@bash $(SCRIPTS)/wait-component.sh $* 300

prune-stuck-sandboxes: ## Reactively clear containerd CRI sandbox-name reservation cascades (cluster-wide)
	@bash $(SCRIPTS)/prune-stuck-sandboxes.sh --all 60

# =============================================================================
# PER-NAMESPACE INSTALL (every component under a namespace dir)
# =============================================================================
# All paths route through scripts/retry.sh — uniform CRD-before-CR resilience.
.PHONY: install-ns-common install-ns-security install-ns-storage install-ns-data-ingestion install-ns-data-processing install-ns-data-governance install-ns-model-lifecycle install-ns-model-serving install-ns-observability install-ns-gitops

install-ns-common: ## Apply all common components (cert-manager, istio, knative, keda, kueue...)
	@bash $(SCRIPTS)/retry.sh $(APPLY_MAX_ATTEMPTS) $(APPLY_DELAY) -- $(KUBECTL) apply -k $(COMPONENTS)/common

install-ns-security: ## Apply all security components (openbao, ESO, kyverno, falco, trivy...)
	@bash $(SCRIPTS)/retry.sh $(APPLY_MAX_ATTEMPTS) $(APPLY_DELAY) -- $(KUBECTL) apply -k $(COMPONENTS)/security

install-ns-storage: ## Apply all storage components (postgres, minio, valkey, mysql, qdrant, clickhouse...)
	@bash $(SCRIPTS)/retry.sh $(APPLY_MAX_ATTEMPTS) $(APPLY_DELAY) -- $(KUBECTL) apply -k $(COMPONENTS)/storage

install-ns-data-ingestion: ## Apply all ingestion components (kafka stack)
	@bash $(SCRIPTS)/retry.sh $(APPLY_MAX_ATTEMPTS) $(APPLY_DELAY) -- $(KUBECTL) apply -k $(COMPONENTS)/data-ingestion

install-ns-data-processing: ## Apply all processing components (flink, spark, airflow, dbt, trino, superset, GE)
	@bash $(SCRIPTS)/retry.sh $(APPLY_MAX_ATTEMPTS) $(APPLY_DELAY) -- $(KUBECTL) apply -k $(COMPONENTS)/data-processing

install-ns-data-governance: ## Apply all governance components (datahub, opensearch, openlineage)
	@bash $(SCRIPTS)/retry.sh $(APPLY_MAX_ATTEMPTS) $(APPLY_DELAY) -- $(KUBECTL) apply -k $(COMPONENTS)/data-governance

install-ns-model-lifecycle: ## Apply all model-lifecycle (mlflow, feast, kubeflow*, katib)
	@bash $(SCRIPTS)/retry.sh $(APPLY_MAX_ATTEMPTS) $(APPLY_DELAY) -- $(KUBECTL) apply -k $(COMPONENTS)/model-lifecycle

install-ns-model-serving: ## Apply all model-serving (kserve)
	@bash $(SCRIPTS)/retry.sh $(APPLY_MAX_ATTEMPTS) $(APPLY_DELAY) -- $(KUBECTL) apply -k $(COMPONENTS)/model-serving

install-ns-observability: ## Apply all observability (prom, grafana, loki, tempo, alloy, opencost...)
	@bash $(SCRIPTS)/retry.sh $(APPLY_MAX_ATTEMPTS) $(APPLY_DELAY) -- $(KUBECTL) apply -k $(COMPONENTS)/observability

install-ns-gitops: ## Apply all gitops (argocd, gitea, tekton, argo-rollouts)
	@bash $(SCRIPTS)/retry.sh $(APPLY_MAX_ATTEMPTS) $(APPLY_DELAY) -- $(KUBECTL) apply -k $(COMPONENTS)/gitops

# =============================================================================
# ATOMS — minimal grouped units used to compose phases
# =============================================================================
.PHONY: atom-namespaces atom-cert-istio atom-keda-kueue atom-eso atom-openbao atom-kyverno atom-argocd atom-storage-core atom-storage-kv atom-storage-vector atom-storage-mysql atom-storage-olap atom-storage-lake atom-obs-stack atom-obs-extra atom-ingest-stream atom-proc-stream atom-proc-batch atom-proc-quality atom-features atom-train-mlflow atom-train-kubeflow atom-kubeflow-base atom-serving-core atom-governance-core atom-governance-extra atom-gitops-core atom-rbac atom-auth atom-security-extra

atom-namespaces: ## Create all platform namespaces only
	@bash $(SCRIPTS)/apply-namespaces.sh

atom-cert-istio: install-cert-manager install-istio ## Cert-manager + Istio mesh

atom-keda-kueue: install-keda install-kueue install-metrics-server ## KEDA + Kueue + metrics-server

atom-eso: install-external-secrets ## External-secrets operator + CRDs (must precede atom-openbao + atom-storage-core: their ExternalSecret CRs need ESO CRDs)

# Storage: rely on k3s built-in `local-path` StorageClass (rancher.io/local-path).
# Single-node + replica max 1 mandate makes Longhorn pure overhead; see ADR-031.
# Backups: velero Kopia file-system mode (no CSI snapshotter needed).

atom-openbao: install-openbao ## OpenBao server StatefulSet — depends on atom-eso (ExternalSecret CRDs already there for downstream consumers). openbao-0 PVC binds to k3s built-in `local-path`.

atom-kyverno: install-kyverno ## Kyverno policy admission controller

atom-argocd: install-argo-cd ## ArgoCD core (gitops backbone for HelmRelease apps)

atom-storage-core: install-cnpg install-postgresql install-kes install-minio ## Postgres + KES + MinIO — depend on atom-eso + atom-openbao (ExternalSecrets pull creds from openbao KV). PVCs bind to k3s built-in `local-path`.

atom-storage-kv: install-valkey ## Online feature cache + KV

atom-storage-vector: install-qdrant ## Vector DB

atom-storage-mysql: install-mysql ## MySQL for Kubeflow

atom-storage-olap: install-clickhouse-operator install-clickhouse ## ClickHouse columnar OLAP

atom-storage-lake: install-lakefs install-lakekeeper ## LakeFS + Iceberg REST catalog

atom-obs-stack: install-kube-prometheus-stack install-grafana install-loki install-tempo install-opentelemetry install-pushgateway ## Core LGTM observability

atom-obs-extra: install-pyroscope install-opencost install-evidently install-sloth ## Pyroscope + OpenCost + Evidently + SLO

atom-ingest-stream: install-registry install-kafka-operator install-kafka install-karapace install-kafka-ui install-kafka-connect ## Kafka streaming stack (Strimzi). install-registry must precede install-kafka-connect: KafkaConnect Build (kaniko) pushes the Debezium+Iceberg image to registry.platform-registry.svc.cluster.local:5000 — without the registry the connect-build pod fails DNS lookup and the KafkaConnect cluster never reaches Ready.

atom-proc-stream: install-flink ## Flink streaming

atom-proc-batch: install-spark install-airflow install-dbt install-trino install-superset ## Spark + Airflow + dbt + Trino + Superset

atom-proc-quality: install-great-expectations ## Great Expectations data validation

atom-features: install-feast ## Feast feature store (online + offline)

atom-train-mlflow: install-mlflow ## MLflow tracking + registry

atom-train-kubeflow: install-kubeflow-pipelines install-kubeflow-pipeline-api install-kubeflow-metadata install-kubeflow-trainer install-kubeflow-notebooks install-kubeflow-katib ## Kubeflow training + AutoML

atom-serving-core: install-knative install-kserve ## Knative + KServe

atom-governance-core: install-opensearch install-datahub install-openlineage ## DataHub + OpenSearch + OpenLineage

atom-gitops-core: install-argo-cd install-argo-rollouts install-gitea install-tekton seed-gitea ## Argo + Tekton + Gitea (+ seed working tree into gitea so ArgoCD app-of-apps can reconcile)

atom-rbac: install-rbac ## Cluster-wide RBAC bindings (data-engineer/scientist/admin roles)

atom-auth: install-auth install-spicedb ## Dex OIDC + oauth2-proxy + SpiceDB authz (depends on phase-base for ESO+CNPG)

atom-kubeflow-base: install-kubeflow-core ## Kubeflow gateway + network-policies + roles (depends on atom-cert-istio)

atom-governance-extra: install-datahub-ingestion ## DataHub source recipes + ingestion CronJobs (depends on atom-governance-core)

atom-security-extra: install-chaos-mesh install-falco install-trivy-operator install-velero install-apisix ## Chaos engineering (KNF-04/11) + Falco runtime + Trivy vuln + Velero backup + APISIX gateway

# =============================================================================
# COMPOSABLE PHASES — user-facing entry points
# =============================================================================
.PHONY: phase-base phase-observability \
        phase-ingest-stream \
        phase-stream phase-batch \
        phase-feast phase-mlflow phase-kubeflow phase-serve \
        phase-stream-to-feast phase-batch-to-feast \
        phase-feast-to-mlflow phase-feast-to-kubeflow phase-feast-to-training phase-feast-to-serving \
        phase-mlflow-to-serving phase-kubeflow-to-serving phase-train-to-serving \
        phase-stream-e2e phase-batch-e2e \
        phase-governance phase-gitops phase-security phase-auth phase-full

# --- Layer-only phases (single concern) ----------------------------------------
phase-base: atom-namespaces atom-argocd atom-cert-istio atom-keda-kueue atom-kyverno atom-eso atom-openbao atom-storage-core ## Minimal infra: ArgoCD + mesh + ESO + OpenBao + Postgres + MinIO. PVCs bind to k3s built-in `local-path` (no separate CSI driver needed).

phase-observability: phase-base atom-obs-stack ## Base + LGTM stack

phase-ingest-stream: phase-base atom-ingest-stream ## Base + Kafka (ingest only, no proc)

phase-stream: phase-base atom-ingest-stream atom-proc-stream ## Kafka + Flink (no Feast)

phase-batch: phase-base atom-storage-olap atom-proc-batch atom-proc-quality ## Spark + Airflow + dbt + Trino + Superset + GE (no Feast)

phase-feast: phase-base atom-storage-kv atom-features ## Feast standalone (Redis + Feast)

phase-mlflow: phase-base atom-storage-mysql atom-train-mlflow ## MLflow standalone (MySQL + MLflow)

phase-kubeflow: phase-base atom-storage-mysql atom-train-kubeflow ## Kubeflow Pipelines + Trainer + Katib + Notebooks standalone

phase-serve: phase-base atom-serving-core ## Knative + KServe only (BYO model)

# --- Cross-layer phases (compose two stages) -----------------------------------
phase-stream-to-feast: phase-base atom-storage-kv atom-ingest-stream atom-proc-stream atom-features ## Stream → Flink → Feast

phase-batch-to-feast: phase-base atom-storage-kv atom-storage-olap atom-proc-batch atom-proc-quality atom-features ## Batch → Spark/Airflow/dbt/GE → Feast

phase-feast-to-mlflow: phase-base atom-storage-kv atom-storage-mysql atom-features atom-train-mlflow ## Feast → MLflow only

phase-feast-to-kubeflow: phase-base atom-storage-kv atom-storage-mysql atom-features atom-train-kubeflow ## Feast → Kubeflow only

phase-feast-to-training: phase-base atom-storage-kv atom-storage-mysql atom-features atom-train-mlflow atom-train-kubeflow ## Feast → MLflow + Kubeflow

phase-feast-to-serving: phase-base atom-storage-kv atom-features atom-serving-core ## Feast online store → KServe

phase-mlflow-to-serving: phase-base atom-storage-mysql atom-train-mlflow atom-serving-core ## MLflow → KServe (no Feast, no Kubeflow)

phase-kubeflow-to-serving: phase-base atom-storage-mysql atom-train-kubeflow atom-serving-core ## Kubeflow → KServe (no Feast, no MLflow)

phase-train-to-serving: phase-base atom-storage-mysql atom-train-mlflow atom-train-kubeflow atom-serving-core ## MLflow + Kubeflow → KServe

# --- End-to-end phases (full pipeline) -----------------------------------------
phase-stream-e2e: phase-stream-to-feast atom-storage-mysql atom-train-mlflow atom-train-kubeflow atom-serving-core ## Stream → Feast → Train → Serve

phase-batch-e2e: phase-batch-to-feast atom-storage-mysql atom-train-mlflow atom-train-kubeflow atom-serving-core ## Batch → Feast → Train → Serve

phase-governance: phase-base atom-governance-core atom-governance-extra ## DataHub stack + ingestion CronJobs

phase-gitops: atom-namespaces atom-cert-istio atom-gitops-core ## ArgoCD + Tekton + Gitea + Argo Rollouts

phase-security: phase-base atom-security-extra ## Base + Chaos Mesh + Falco + Trivy + Velero + APISIX (opt-in security stack)

phase-auth: phase-base atom-rbac atom-auth ## Base + RBAC + Dex/oauth2-proxy + SpiceDB authz

phase-full: phase-base atom-rbac phase-observability atom-storage-kv atom-storage-vector atom-storage-mysql atom-storage-olap atom-storage-lake atom-auth atom-ingest-stream atom-proc-stream atom-proc-batch atom-proc-quality atom-features atom-train-mlflow atom-train-kubeflow atom-kubeflow-base atom-serving-core atom-governance-core atom-governance-extra atom-gitops-core atom-obs-extra atom-security-extra ## Everything (incl. RBAC, auth, kubeflow gateway, datahub ingestion, security extras)

# =============================================================================
# FULL-STACK (platform phase + use-case-crypto deploy in one shot)
# =============================================================================
# Platform retries each component up to APPLY_MAX_ATTEMPTS times. Use-case
# deploy runs after platform finishes; it has its own retry/wait logic in
# use-case-crypto/Makefile. If platform fails, use-case is skipped.
.PHONY: full-stream full-batch full-stream-with-data full-batch-with-data full

full-stream: phase-stream-e2e usecase-crypto-up ## Platform stream-e2e + use-case-crypto deploy (all)

full-batch: phase-batch-e2e usecase-crypto-up ## Platform batch-e2e + use-case-crypto deploy (all)

full-stream-with-data: phase-stream-e2e usecase-crypto-build usecase-crypto-data ## Platform stream-e2e + crypto build + data sub-phase only

full-batch-with-data: phase-batch-e2e usecase-crypto-build usecase-crypto-data ## Platform batch-e2e + crypto build + data sub-phase only

full: phase-full usecase-crypto-up ## Everything platform + use-case-crypto deploy

# =============================================================================
# OPERATIONS
# =============================================================================
.PHONY: scale-zero-all scale-up scale-down status events wipe-data nuke set-replicas-zero

scale-zero-all: ## Scale every running Deployment + StatefulSet to 0 (live cluster)
	@bash $(SCRIPTS)/scale-zero-all.sh

set-replicas-zero: ## Patch all platform/components/ YAMLs: replicas → 0 (manifest baseline)
	@uv run --no-project --quiet $(SCRIPTS)/set-replicas-zero.py

scale-up: ## Scale a Deployment/STS — make scale-up COMPONENT=feast REPLICAS=2 [NS=model-lifecycle]
	@bash $(SCRIPTS)/scale.sh up "$(COMPONENT)" "$(REPLICAS)" "$(NS)"

scale-down: ## Scale a Deployment/STS to 0 — make scale-down COMPONENT=feast [NS=model-lifecycle]
	@bash $(SCRIPTS)/scale.sh down "$(COMPONENT)" 0 "$(NS)"

status: ## Pod state per namespace, summarised
	@$(KUBECTL) get pods -A --no-headers 2>/dev/null | awk '{print $$1, $$4}' | sort | uniq -c | sort -rn

events: ## Last 50 events across cluster (most recent first)
	@$(KUBECTL) get events -A --sort-by=.lastTimestamp --no-headers 2>/dev/null | tail -50

wipe-data: ## Delete all PVCs in storage + data namespaces (DESTRUCTIVE)
	@bash $(SCRIPTS)/wipe-data.sh

nuke: ## Delete all platform namespaces + CRDs (DESTRUCTIVE — full reset)
	@bash $(SCRIPTS)/nuke.sh

# =============================================================================
# GITOPS BOOTSTRAP — seed gitea with the platform/ working tree
# =============================================================================
# install-gitea provisions the empty `platform/platform` repo via the
# gitea-bootstrap Job. ArgoCD app-of-apps + ApplicationSet point at that
# repo, paths `platform/components/<x>`. Until the working tree is pushed,
# every Application reports `app path does not exist`. Wired into
# atom-gitops-core so phase-full leaves ArgoCD in a reconciling state.
.PHONY: seed-gitea
seed-gitea: ## Push platform/ tree into the in-cluster gitea (force-push, idempotent)
	@bash $(SCRIPTS)/seed-gitea.sh

# =============================================================================
# SCALABILITY PRIMITIVES — HPA / VPA / KEDA
# =============================================================================
.PHONY: install-hpa install-vpa install-keda-scaledobject

install-hpa: ## Install HPA from template — make install-hpa COMPONENT=feast NS=model-lifecycle MIN=1 MAX=5
	@bash $(SCRIPTS)/render-scalability.sh hpa "$(COMPONENT)" "$(NS)" "$(MIN)" "$(MAX)"

install-vpa: ## Install VPA recommender — make install-vpa COMPONENT=feast NS=model-lifecycle
	@bash $(SCRIPTS)/render-scalability.sh vpa "$(COMPONENT)" "$(NS)"

install-keda-scaledobject: ## Install KEDA ScaledObject — make install-keda-scaledobject COMPONENT=consumer NS=data-processing TRIGGER=kafka
	@bash $(SCRIPTS)/render-scalability.sh keda "$(COMPONENT)" "$(NS)" "$(TRIGGER)"

# =============================================================================
# PLATFORM IMAGE BUILD — generic (domain-agnostic) Docker images
# =============================================================================
# Builds the 14 platform/services/ Dockerfiles into local Docker, then pushes
# each tag to $(PLATFORM_REGISTRY). Use-case overlays retag these (see
# use-case-crypto/Makefile build-* targets). Idempotent: skips when image
# already present (`docker image inspect`). Bypass cache with FORCE_REBUILD=1.
#
# Registry runs in-cluster (platform/components/common/registry → ns
# platform-registry, hostPort 5000). The platform-registry-up target only
# verifies reachability; it does not spawn a docker registry container.
.PHONY: platform-registry-up platform-build-services platform-push-services \
        platform-clean-services

platform-registry-up: ## Verify in-cluster registry reachable on :5000 (platform/components/common/registry)
	@if curl -fsS http://$(PLATFORM_REGISTRY)/v2/ >/dev/null 2>&1; then \
		echo "$(GREEN)Registry reachable: $(PLATFORM_REGISTRY)$(NC)"; \
	else \
		echo "$(RED)Registry not reachable on $(PLATFORM_REGISTRY)$(NC)"; \
		echo "$(YELLOW)Apply platform-registry component:$(NC)"; \
		echo "    make -C platform install COMPONENT=common/registry"; \
		echo "$(YELLOW)Or check pod state:$(NC)"; \
		echo "    kubectl -n platform-registry get pods,svc"; \
		exit 1; \
	fi

platform-build-services: platform-registry-up ## Build + push 15 generic images to $(PLATFORM_REGISTRY)
	@echo "$(BLUE)══════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)  Building generic platform images → $(PLATFORM_REGISTRY)$(NC)"
	@echo "$(BLUE)══════════════════════════════════════════════════════════$(NC)"
	@set -e; for entry in $(PLATFORM_SERVICES); do \
		img=$${entry%%:*}; \
		path=$${entry#*:}; \
		ctx=$(PLATFORM_DIR)/services/$$path; \
		tag=$$img:$(PLATFORM_IMAGE_TAG); \
		remote=$(PLATFORM_REGISTRY)/$$tag; \
		if [ ! -f $$ctx/Dockerfile ]; then \
			echo "$(RED)  ! $$tag — Dockerfile missing at $$ctx/Dockerfile, skip$(NC)"; \
			continue; \
		fi; \
		if [ -z "$$FORCE_REBUILD" ] && docker image inspect $$tag >/dev/null 2>&1; then \
			echo "$(YELLOW)  · $$tag (cached, FORCE_REBUILD=1 to rebuild)$(NC)"; \
		else \
			echo "$(GREEN)  + building $$tag from $$ctx$(NC)"; \
			docker build -t $$tag $$ctx; \
		fi; \
		docker tag $$tag $$remote; \
		docker push $$remote >/dev/null; \
		echo "$(GREEN)    pushed → $$remote$(NC)"; \
	done
	@echo ""
	@echo "$(GREEN)All generic images built + pushed$(NC)"
	@docker images --format '{{.Repository}}:{{.Tag}}' | \
		awk -F: 'BEGIN{n=split("$(PLATFORM_SERVICES)",a," ")} \
		         {for(i=1;i<=n;i++){split(a[i],p,":");if($$1==p[1])print "  "$$0}}' | sort -u

platform-push-services: platform-registry-up ## Re-push already-built generic images (no rebuild)
	@set -e; for entry in $(PLATFORM_SERVICES); do \
		img=$${entry%%:*}; \
		tag=$$img:$(PLATFORM_IMAGE_TAG); \
		if docker image inspect $$tag >/dev/null 2>&1; then \
			docker tag $$tag $(PLATFORM_REGISTRY)/$$tag; \
			docker push $(PLATFORM_REGISTRY)/$$tag >/dev/null && \
				echo "$(GREEN)  · pushed $(PLATFORM_REGISTRY)/$$tag$(NC)"; \
		else \
			echo "$(RED)  ! $$tag not built — run make platform-build-services$(NC)"; \
		fi; \
	done

platform-clean-services: ## Remove local generic images (registry data preserved)
	@for entry in $(PLATFORM_SERVICES); do \
		img=$${entry%%:*}; \
		docker rmi -f $$img:$(PLATFORM_IMAGE_TAG) $(PLATFORM_REGISTRY)/$$img:$(PLATFORM_IMAGE_TAG) 2>/dev/null || true; \
	done
	@echo "$(GREEN)Local generic images removed$(NC)"

# =============================================================================
# USE-CASE DISPATCH
# =============================================================================
# Use-case sub-phases match service flow (data → train → serve → app):
#   data   = ingestion + quality + processing → Feast feature store
#   train  = model training + drift detection
#   serve  = KServe inference services
#   app    = dashboard (frontend + backend) + automation (retraining)
.PHONY: usecase-crypto-up usecase-crypto-down usecase-crypto-status usecase-crypto-build usecase-crypto-test \
        usecase-crypto-data usecase-crypto-train usecase-crypto-serve usecase-crypto-app \
        usecase-crypto-images

usecase-crypto-up: ## Deploy all use-case-crypto microservices (data + train + serve + app)
	@$(MAKE) -C $(USECASE_DIR) deploy

usecase-crypto-down: ## Undeploy use-case-crypto
	@$(MAKE) -C $(USECASE_DIR) undeploy

usecase-crypto-status: ## Use-case-crypto pod state
	@$(MAKE) -C $(USECASE_DIR) status

usecase-crypto-build: platform-build-services ## Build generic + retag/rebuild + push crypto images
	@$(MAKE) -C $(USECASE_DIR) build-images REGISTRY=$(PLATFORM_REGISTRY) VERSION=$(PLATFORM_IMAGE_TAG)

usecase-crypto-images: ## List crypto-* tags present in registry
	@curl -fsS http://$(PLATFORM_REGISTRY)/v2/_catalog 2>/dev/null | \
		jq -r '.repositories[] | select(startswith("crypto-")) | "  " + .'  || \
		echo "$(RED)Registry unreachable: $(PLATFORM_REGISTRY)$(NC)"

usecase-crypto-test: ## Run all use-case-crypto tests
	@$(MAKE) -C $(USECASE_DIR) test

usecase-crypto-data: ## Setup data sub-phase: ingestion + quality + processing → Feast
	@$(MAKE) -C $(USECASE_DIR) setup-data

usecase-crypto-train: ## Setup train sub-phase: training + drift detection
	@$(MAKE) -C $(USECASE_DIR) setup-train

usecase-crypto-serve: ## Setup serve sub-phase: KServe inference services
	@$(MAKE) -C $(USECASE_DIR) setup-serve

usecase-crypto-app: ## Setup app sub-phase: dashboard + automation
	@$(MAKE) -C $(USECASE_DIR) setup-app
