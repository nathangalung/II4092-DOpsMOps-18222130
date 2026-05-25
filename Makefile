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

# Docker build wrapper.
#   --network=host bypasses BuildKit's isolated network namespace so RUN steps
#   inherit the host's /etc/resolv.conf (campus + 1.1.1.1 + 8.8.8.8). Without
#   it, Docker 25+/BuildKit 0.13+ ignores daemon.json `dns:` for build
#   containers and any RUN that does outbound DNS (wget, curl, apk add, mill,
#   apt-get) fails with "bad address". Override on the CLI to disable:
#       make platform-build-services DOCKER_BUILD='docker build'
DOCKER_BUILD ?= docker build --network=host

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
  trainer:trainer \
  drift-detector:quality/drift \
  retraining:automation/retraining \
  materialization:automation/materialization \
  gateway:serving/gateway \
  feature-cache:serving/feature-cache \
  inference-engine:serving/inference-engine \
  scoring:serving/scoring \
  drift-reporter:drift-reporter

# Pass-through to scripts/render-scalability.sh, scripts/scale.sh, scripts/apply-component.sh
export KIND CPU_TARGET MEM_TARGET MODE CPU_MIN CPU_MAX MEM_MIN MEM_MAX MIN MAX TRIGGER TRIGGER_META NS NUKE_ALL FORCE
export MAX_ATTEMPTS=$(APPLY_MAX_ATTEMPTS)
export DELAY=$(APPLY_DELAY)

# =============================================================================
# USE-CASE-CRYPTO VARIABLES (sourced by usecase-crypto-* targets below)
# =============================================================================
# config/project.yaml is single source of truth for use-case naming. Secrets
# (API keys, passwords) live in use-case-crypto/.env (gitignored). `-include`
# resolves at parse time, so literal path is used here (not $(USECASE_DIR)).
-include use-case-crypto/.env
USE_CASE_NAME := $(or $(shell awk '/namespace:/{gsub(/"/,"",$$2); sub(/use-case-/,"",$$2); print $$2; exit}' $(USECASE_DIR)/config/project.yaml 2>/dev/null),crypto)
USE_CASE_PREFIX := $(USE_CASE_NAME)
NAMESPACE := use-case-$(USE_CASE_PREFIX)
ENV ?= local
# Generic service source code path (for building Docker images + running tests)
SERVICES_SRC ?= $(PLATFORM_DIR)/services
SVC_CONFIG := $(USECASE_DIR)/config/services.yaml
VERSION ?= latest
REGISTRY ?= $(PLATFORM_REGISTRY)
AIRFLOW_NS ?= data-processing
AIRFLOW_DEPLOY ?= deploy/airflow-scheduler

# Non-phase service lists (without USE_CASE_PREFIX — added in commands below)
TRAIN_CRONJOBS    := training-weekly retraining drift-check-daily drift-check-hourly drift-check-minute drift-check-weekly
SERVE_DEPLOYMENTS := gateway feature-cache inference-engine
APP_DEPLOYMENTS   := dashboard-backend dashboard-frontend ml-bridge
APP_CRONJOBS      := materialization

# Service enabled check — reads $(SVC_CONFIG).
# Usage: $(call svc_enabled,section,service_name) → "true" or "false".
svc_enabled = $(shell awk 'BEGIN{s=0;f=0} /^  $(1):/{s=1} s&&/^    $(2):/{f=1} f&&/enabled:/{print $$2;exit}' $(SVC_CONFIG) 2>/dev/null || echo "true")

# Recursive (lazy) — REQUIRED so $(call _push,name) expands $(1) at call site.
# Do NOT change to `:=` (immediate) — would lock $(1) to first call's value.
_push = docker tag $(1):$(VERSION) $(REGISTRY)/$(1):$(VERSION) && docker push $(REGISTRY)/$(1):$(VERSION)

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

atom-train-kubeflow: install-kubeflow-pipelines install-kubeflow-trainer install-kubeflow-notebooks install-kubeflow-katib ## Kubeflow training + AutoML (ml-pipeline + metadata-grpc HPAs folded into kubeflow-pipelines/hpa.yaml)

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
# the usecase-crypto-* targets below. If platform fails, use-case is skipped.
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
# usecase-crypto-build-* targets in this file). Idempotent: skips when image
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
			$(DOCKER_BUILD) -t $$tag $$ctx; \
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
# USE-CASE DISPATCH — crypto microservices, data init, build, deploy, ops
# =============================================================================
# Single source of truth: $(USECASE_DIR)/config/project.yaml drives USE_CASE_NAME.
# To create a new use case:
#   1. Copy use-case-crypto/ → use-case-<name>/
#   2. Edit USECASE_DIR := use-case-<name> at top of this Makefile
#   3. Edit config/project.yaml (namespace: use-case-<name>)
#   4. Run: make usecase-crypto-configure  (rename target after copy)
#
# Sub-phases match service flow (data → train → serve → app):
#   data   = ingestion + quality + processing → Feast feature store (~4GB)
#   train  = model training + drift detection (~2GB)
#   serve  = KServe inference services (~3GB)
#   app    = dashboard (frontend + backend) + automation (~2GB)
# =============================================================================
.PHONY: usecase-crypto-configure usecase-crypto-generate-kustomization usecase-crypto-compile-pipelines \
        usecase-crypto-seed-airflow-vars \
        usecase-crypto-setup usecase-crypto-setup-full \
        usecase-crypto-init-db usecase-crypto-init-clickhouse usecase-crypto-init-postgres \
        usecase-crypto-init-lakehouse usecase-crypto-init-redis usecase-crypto-init-kafka usecase-crypto-init-cdc \
        usecase-crypto-build-dbt usecase-crypto-dbt-run usecase-crypto-dbt-test \
        usecase-crypto-katib-run usecase-crypto-katib-status \
        usecase-crypto-feast-materialize usecase-crypto-train-now \
        usecase-crypto-check usecase-crypto-check-code usecase-crypto-format \
        usecase-crypto-lint usecase-crypto-lint-python usecase-crypto-lint-rust usecase-crypto-lint-go \
        usecase-crypto-lint-java usecase-crypto-lint-cpp usecase-crypto-lint-ts \
        usecase-crypto-test usecase-crypto-test-python usecase-crypto-test-rust usecase-crypto-test-go \
        usecase-crypto-test-java usecase-crypto-test-cpp usecase-crypto-test-ts \
        usecase-crypto-build usecase-crypto-build-ingestion usecase-crypto-build-quality \
        usecase-crypto-build-processing usecase-crypto-build-training usecase-crypto-build-serving \
        usecase-crypto-build-observability usecase-crypto-build-automation usecase-crypto-build-dashboard \
        usecase-crypto-build-data usecase-crypto-build-train usecase-crypto-build-serve usecase-crypto-build-app \
        usecase-crypto-lint-data usecase-crypto-lint-train usecase-crypto-lint-serve usecase-crypto-lint-app \
        usecase-crypto-test-data usecase-crypto-test-train usecase-crypto-test-serve usecase-crypto-test-app \
        usecase-crypto-data usecase-crypto-train usecase-crypto-serve usecase-crypto-app \
        usecase-crypto-up usecase-crypto-up-local usecase-crypto-up-cloud \
        usecase-crypto-deploy-data usecase-crypto-deploy-train usecase-crypto-deploy-serve usecase-crypto-deploy-app \
        usecase-crypto-down usecase-crypto-redeploy \
        usecase-crypto-stop-data usecase-crypto-stop-train usecase-crypto-stop-serve usecase-crypto-stop-app \
        usecase-crypto-resume-data usecase-crypto-resume-train usecase-crypto-resume-serve usecase-crypto-resume-app \
        usecase-crypto-status usecase-crypto-status-all usecase-crypto-logs usecase-crypto-logs-all \
        usecase-crypto-restart usecase-crypto-restart-one \
        usecase-crypto-clean usecase-crypto-clean-images usecase-crypto-clean-all usecase-crypto-images \
        usecase-crypto-shell-clickhouse usecase-crypto-shell-redis usecase-crypto-shell-kafka \
        usecase-crypto-port-forward-dashboard usecase-crypto-port-forward-gateway \
        usecase-crypto-check-cluster usecase-crypto-proto \
        usecase-crypto-sync-dags usecase-crypto-submit-pipeline

# -----------------------------------------------------------------------------
# TEMPLATE CONFIGURATION
# -----------------------------------------------------------------------------

usecase-crypto-generate-kustomization: ## Generate $(USECASE_DIR)/manifests/base/kustomization.yaml from services.yaml
	@echo "$(YELLOW)Generating $(USECASE_DIR)/manifests/base/kustomization.yaml from services config...$(NC)"
	@cd $(USECASE_DIR) && uv run scripts/generate_kustomization.py
	@echo "$(GREEN)Done. Verify with: kubectl kustomize $(USECASE_DIR)/manifests/overlays/$(ENV) --load-restrictor LoadRestrictionsNone | head$(NC)"

usecase-crypto-compile-pipelines: ## Recompile KFP pipeline YAMLs (bakes USE_CASE-derived defaults)
	@echo "$(YELLOW)Compiling KFP pipelines (USE_CASE=$(USE_CASE_NAME))...$(NC)"
	@cd $(USECASE_DIR)/pipelines && USE_CASE=$(USE_CASE_NAME) USE_CASE_REGISTRY=$(REGISTRY) USE_CASE_IMAGE_TAG=$(VERSION) USE_CASE_IMAGE_PREFIX=$(USE_CASE_NAME) uv run --with 'kfp[kubernetes]==2.16.0' retraining_pipeline.py
	@echo "$(GREEN)Done. $(USECASE_DIR)/pipelines/retraining_pipeline.yaml regenerated.$(NC)"

usecase-configure: ## Propagate USE_CASE_NAME (from config/project.yaml) to ALL use-case files. Domain-agnostic.
	@$(USECASE_DIR)/scripts/configure-use-case.sh

usecase-crypto-configure: usecase-configure ## Alias of usecase-configure (back-compat)

# -----------------------------------------------------------------------------
# COMPLETE SETUP
# -----------------------------------------------------------------------------

usecase-crypto-setup: ## Complete setup: test + build + init-db + deploy
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)  COMPLETE SETUP - $(NAMESPACE)$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@$(MAKE) usecase-crypto-test
	@$(MAKE) usecase-crypto-build
	@$(MAKE) usecase-crypto-init-db
	@$(MAKE) usecase-crypto-up
	@echo ""
	@echo "$(GREEN)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)  SETUP COMPLETE!$(NC)"
	@echo "$(GREEN)═══════════════════════════════════════════════════════════════$(NC)"

usecase-crypto-setup-full: ## Full setup with all checks: format + lint + test + build + init-db + deploy
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)  FULL SETUP (with code quality) - $(NAMESPACE)$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@$(MAKE) usecase-crypto-check
	@$(MAKE) usecase-crypto-build
	@$(MAKE) usecase-crypto-init-db
	@$(MAKE) usecase-crypto-up
	@echo ""
	@echo "$(GREEN)  FULL SETUP COMPLETE!$(NC)"

# -----------------------------------------------------------------------------
# PHASED SETUP (deploy incrementally by memory footprint)
# -----------------------------------------------------------------------------

usecase-crypto-data: ## Data sub-phase: lint + test + build + deploy + init DB + dbt
	@echo "$(BLUE)  DATA: Ingestion + Quality + Processing + Medallion$(NC)"
	@$(MAKE) usecase-crypto-lint-data
	@$(MAKE) usecase-crypto-test-data
	@$(MAKE) usecase-crypto-build-data
	@$(MAKE) usecase-crypto-init-db
	@$(MAKE) usecase-crypto-deploy-data
	@$(MAKE) usecase-crypto-dbt-run
	@echo "$(GREEN)Data complete. Run 'make usecase-crypto-status' to verify.$(NC)"

usecase-crypto-train: ## Train sub-phase: lint + test + build + deploy + KFP pipeline
	@echo "$(BLUE)  TRAIN: Training + Drift Detection + Kubeflow Pipeline$(NC)"
	@$(MAKE) usecase-crypto-lint-train
	@$(MAKE) usecase-crypto-test-train
	@$(MAKE) usecase-crypto-build-train
	@$(MAKE) usecase-crypto-deploy-train
	@$(MAKE) usecase-crypto-submit-pipeline
	@echo "$(GREEN)Train complete.$(NC)"

usecase-crypto-serve: ## Serve sub-phase: lint + test + build + deploy (KServe)
	@echo "$(BLUE)  SERVE: Serving (KServe + Gateway)$(NC)"
	@$(MAKE) usecase-crypto-lint-serve
	@$(MAKE) usecase-crypto-test-serve
	@$(MAKE) usecase-crypto-build-serve
	@$(MAKE) usecase-crypto-deploy-serve
	@echo "$(GREEN)Serve complete.$(NC)"

usecase-crypto-app: ## App sub-phase: lint + test + build + deploy dashboard + automation
	@echo "$(BLUE)  APP: Dashboard + Automation$(NC)"
	@$(MAKE) usecase-crypto-lint-app
	@$(MAKE) usecase-crypto-test-app
	@$(MAKE) usecase-crypto-build-app
	@$(MAKE) usecase-crypto-deploy-app
	@echo "$(GREEN)App complete.$(NC)"

# Phase-specific build aggregators
usecase-crypto-build-data: ## Build Data images: Ingestion + Quality + Processing
	@$(MAKE) usecase-crypto-build-ingestion
	@$(MAKE) usecase-crypto-build-quality
	@$(MAKE) usecase-crypto-build-processing
	@echo "$(GREEN)Data images built.$(NC)"

usecase-crypto-build-train: ## Build Train images: Training + Drift
	@$(MAKE) usecase-crypto-build-training
	@echo "$(GREEN)Train images built.$(NC)"

usecase-crypto-build-serve: ## Build Serve images: Serving
	@$(MAKE) usecase-crypto-build-serving
	@echo "$(GREEN)Serve images built.$(NC)"

usecase-crypto-build-app: ## Build App images: Dashboard + Automation
	@$(MAKE) usecase-crypto-build-dashboard
	@$(MAKE) usecase-crypto-build-automation
	@echo "$(GREEN)App images built.$(NC)"

# Phase-specific lint targets
usecase-crypto-lint-data: ## Lint Data services
	@echo "$(YELLOW)Linting Data services...$(NC)"
	@cd $(SERVICES_SRC)/ingestion/rest-collector && (golangci-lint run ./... 2>/dev/null || go vet ./...)
	@cd $(SERVICES_SRC)/ingestion/websocket-collector && cargo clippy -- -D warnings
	@cd $(SERVICES_SRC)/quality/validator && cargo clippy -- -D warnings
	@uv run --with ruff ruff check $(SERVICES_SRC)/quality/analyzer/
	@uv run --with ruff ruff check $(SERVICES_SRC)/quality/drift/
	@uv run --with ruff ruff check $(SERVICES_SRC)/processing/batch/
	@uv run --with ruff ruff check $(SERVICES_SRC)/processing/vector/
	@cd $(SERVICES_SRC)/processing/stream/feature-engine && cargo clippy -- -D warnings
	@cd $(SERVICES_SRC)/processing/stream/flink-job && mill flink.compile
	@cd $(USECASE_DIR)/services/websocket-collector && cargo clippy -- -D warnings
	@cd $(USECASE_DIR)/services/processing/stream-processor && mill flink.compile
	@echo "$(GREEN)Data lint passed.$(NC)"

usecase-crypto-lint-train: ## Lint Train services
	@uv run --with ruff ruff check $(SERVICES_SRC)/trainer/
	@echo "$(GREEN)Train lint passed.$(NC)"

usecase-crypto-lint-serve: ## Lint Serve services
	@cd $(SERVICES_SRC)/serving/gateway && cargo clippy -- -D warnings
	@cd $(SERVICES_SRC)/serving/feature-cache && cargo clippy -- -D warnings
	@(which xmake > /dev/null 2>&1 && pkg-config --exists grpc++ protobuf 2>/dev/null && test -d /opt/onnxruntime) && \
		(cd $(SERVICES_SRC)/serving/inference-engine && mkdir -p build/generated && xmake f --tests=y -y && xmake build test_inference) || \
		echo "$(YELLOW)  SKIP: C++ deps not fully installed$(NC)"
	@echo "$(GREEN)Serve lint passed.$(NC)"

usecase-crypto-lint-app: ## Lint App services
	@cd $(SERVICES_SRC)/dashboard/backend && (golangci-lint run ./... 2>/dev/null || go vet ./...)
	@uv run --with ruff ruff check $(SERVICES_SRC)/dashboard/ml-bridge/
	@cd $(SERVICES_SRC)/dashboard/frontend && bun run lint
	@uv run --with ruff ruff check $(SERVICES_SRC)/automation/materialization/
	@uv run --with ruff ruff check $(SERVICES_SRC)/automation/retraining/
	@echo "$(GREEN)App lint passed.$(NC)"

# Phase-specific test targets
usecase-crypto-test-data: ## Test Data services
	@cd $(SERVICES_SRC)/ingestion/rest-collector && go test ./...
	@cd $(SERVICES_SRC)/ingestion/websocket-collector && cargo nextest run 2>/dev/null || cargo test
	@cd $(SERVICES_SRC)/quality/validator && cargo nextest run 2>/dev/null || cargo test
	@cd $(SERVICES_SRC)/quality/analyzer && uv run pytest tests/ -v
	@cd $(SERVICES_SRC)/quality/drift && uv run pytest tests/ -v
	@cd $(SERVICES_SRC)/processing/stream/feature-engine && cargo nextest run 2>/dev/null || cargo test
	@cd $(SERVICES_SRC)/processing/stream/flink-job && mill flink.test
	@cd $(SERVICES_SRC)/processing/batch && uv run pytest tests/ -v
	@cd $(SERVICES_SRC)/processing/vector && uv run pytest tests/ -v
	@cd $(USECASE_DIR)/services/websocket-collector && cargo nextest run 2>/dev/null || cargo test
	@cd $(USECASE_DIR)/services/processing/stream-processor && mill flink.test
	@echo "$(GREEN)Data tests passed.$(NC)"

usecase-crypto-test-train: ## Test Train services
	@cd $(SERVICES_SRC)/trainer && uv run pytest tests/ -v
	@echo "$(GREEN)Train tests passed.$(NC)"

usecase-crypto-test-serve: ## Test Serve services
	@cd $(SERVICES_SRC)/serving/gateway && cargo nextest run 2>/dev/null || cargo test
	@cd $(SERVICES_SRC)/serving/feature-cache && cargo nextest run 2>/dev/null || cargo test
	@(which xmake > /dev/null 2>&1 && pkg-config --exists grpc++ protobuf 2>/dev/null && test -d /opt/onnxruntime) && \
		(cd $(SERVICES_SRC)/serving/inference-engine && mkdir -p build/generated && xmake f --tests=y && xmake run test_inference) || \
		echo "$(YELLOW)  SKIP: C++ deps not fully installed$(NC)"
	@echo "$(GREEN)Serve tests passed.$(NC)"

usecase-crypto-test-app: ## Test App services
	@cd $(SERVICES_SRC)/dashboard/backend && go test ./...
	@cd $(SERVICES_SRC)/dashboard/ml-bridge && uv run pytest tests/ -v
	@cd $(SERVICES_SRC)/dashboard/frontend && bun install --frozen-lockfile 2>/dev/null || bun install && bun run --bun vitest --run
	@cd $(SERVICES_SRC)/automation/materialization && uv run pytest tests/ -v
	@cd $(SERVICES_SRC)/automation/retraining && uv run pytest tests/ -v
	@echo "$(GREEN)App tests passed.$(NC)"

# -----------------------------------------------------------------------------
# CODE QUALITY
# -----------------------------------------------------------------------------

usecase-crypto-check: usecase-crypto-check-code ## Run all code quality checks (format + lint + test)
	@echo "$(GREEN)All code quality checks passed.$(NC)"

usecase-crypto-check-code: ## Format, lint, and test all use-case code
	@$(MAKE) usecase-crypto-format
	@$(MAKE) usecase-crypto-lint
	@$(MAKE) usecase-crypto-test

# -----------------------------------------------------------------------------
# DATABASE INITIALIZATION
# -----------------------------------------------------------------------------

usecase-crypto-init-db: usecase-crypto-init-clickhouse usecase-crypto-init-postgres usecase-crypto-init-lakehouse usecase-crypto-init-redis usecase-crypto-init-kafka ## Init all databases + lakehouse
	@echo "$(GREEN)All databases initialized.$(NC)"

usecase-crypto-init-lakehouse: ## Init Lakehouse (MinIO buckets + Polaris catalog)
	@echo "$(YELLOW)Initializing Lakehouse (MinIO + Polaris + LakeFS)...$(NC)"
	@bash $(SERVICES_SRC)/base/database/init_lakehouse.sh
	@echo "$(GREEN)Lakehouse init complete.$(NC)"

usecase-crypto-init-clickhouse: ## Init ClickHouse tables
	@echo "$(YELLOW)Initializing ClickHouse...$(NC)"
	@CH_POD=$$(kubectl -n storage get pods -l clickhouse.altinity.com/chi=platform -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$CH_POD" ]; then echo "$(RED)ClickHouse CHI pod not found$(NC)"; exit 1; fi; \
	kubectl -n storage wait --for=condition=ready pod/$$CH_POD --timeout=60s || \
		(echo "$(RED)ClickHouse pod not ready$(NC)" && exit 1); \
	CH_PASS=$$(kubectl -n storage get secret clickhouse-admin -o jsonpath='{.data.CLICKHOUSE_PASSWORD}' | base64 -d); \
	kubectl exec -i -n storage $$CH_POD -c clickhouse -- clickhouse-client --user default --password "$$CH_PASS" --multiquery < $(USECASE_DIR)/database/init_clickhouse.sql; \
	kubectl exec -n storage $$CH_POD -c clickhouse -- clickhouse-client --user default --password "$$CH_PASS" --query "SHOW DATABASES" 2>/dev/null || true; \
	kubectl exec -n storage $$CH_POD -c clickhouse -- clickhouse-client --user default --password "$$CH_PASS" --query "SHOW TABLES FROM bronze" 2>/dev/null || true
	@echo "$(GREEN)ClickHouse init complete.$(NC)"

usecase-crypto-init-postgres: ## Init PostgreSQL OLTP tables (pipeline schema)
	@echo "$(YELLOW)Initializing PostgreSQL...$(NC)"
	@PG_POD=$$(kubectl get pods -n storage -l cnpg.io/cluster=postgresql,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) && \
		kubectl wait --for=condition=ready pod/$$PG_POD -n storage --timeout=60s || \
		(echo "$(RED)PostgreSQL pod not ready$(NC)" && exit 1)
	@PG_POD=$$(kubectl get pods -n storage -l cnpg.io/cluster=postgresql,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}') && \
		kubectl exec -n storage $$PG_POD -- psql -U postgres -c "CREATE DATABASE pipeline" 2>/dev/null || true
	@PG_POD=$$(kubectl get pods -n storage -l cnpg.io/cluster=postgresql,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}') && \
		kubectl exec -i -n storage $$PG_POD -- psql -U postgres -d pipeline < $(SERVICES_SRC)/base/database/init_postgres.sql
	@PG_POD=$$(kubectl get pods -n storage -l cnpg.io/cluster=postgresql,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}') && \
		kubectl exec -i -n storage $$PG_POD -- psql -U postgres -d pipeline < $(USECASE_DIR)/database/init_postgres.sql
	@PG_POD=$$(kubectl get pods -n storage -l cnpg.io/cluster=postgresql,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}') && \
		kubectl exec -n storage $$PG_POD -- psql -U postgres -d pipeline -c "\dt pipeline.*"
	@echo "$(GREEN)PostgreSQL init complete.$(NC)"

usecase-crypto-init-cdc: ## Register Debezium CDC connector (PostgreSQL → Kafka)
	@echo "$(YELLOW)Registering Debezium CDC connector...$(NC)"
	@kubectl delete job $(USE_CASE_PREFIX)-debezium-registration -n $(NAMESPACE) 2>/dev/null || true
	@kubectl apply -k $(USECASE_DIR)/manifests/overlays/$(ENV)-data --load-restrictor LoadRestrictionsNone 2>/dev/null || \
		kubectl apply -k $(USECASE_DIR)/manifests/overlays/$(ENV) --load-restrictor LoadRestrictionsNone 2>/dev/null
	@kubectl wait --for=condition=complete job/$(USE_CASE_PREFIX)-debezium-registration -n $(NAMESPACE) --timeout=120s 2>/dev/null || \
		echo "$(YELLOW)Job may already be complete or still running$(NC)"
	@echo "$(GREEN)CDC connector registered.$(NC)"

# PSA `restricted` + Kyverno `require-resource-limits` enforced on
# use-case-crypto, so a bare `kubectl run` is rejected. We materialise a
# Pod manifest via heredoc that satisfies both: securityContext (non-root,
# no priv-esc, drop ALL, seccomp RuntimeDefault) + explicit cpu/mem
# requests+limits. CLICKHOUSE creds come from the `pipeline-secrets`
# Secret mirrored into the use-case ns by ESO (ADR-035) — the dbt
# profile (profiles.yml) reads them via env_var('CLICKHOUSE_USER'),
# env_var('CLICKHOUSE_PASSWORD'). Image ENTRYPOINT/CMD already runs
# `dbt run --profiles-dir /dbt --project-dir /dbt`; we override `args:`
# for the `test` variant.
usecase-crypto-dbt-run: ## Run dbt transformations (bronze → silver → gold)
	@echo "$(YELLOW)Running dbt transformations...$(NC)"
	@kubectl delete pod dbt-manual-run -n $(NAMESPACE) 2>/dev/null || true
	@printf '%s\n' \
		'apiVersion: v1' \
		'kind: Pod' \
		'metadata:' \
		'  name: dbt-manual-run' \
		'  namespace: $(NAMESPACE)' \
		'spec:' \
		'  restartPolicy: Never' \
		'  securityContext:' \
		'    runAsNonRoot: true' \
		'    runAsUser: 1000' \
		'    runAsGroup: 1000' \
		'    fsGroup: 1000' \
		'    seccompProfile: { type: RuntimeDefault }' \
		'  volumes:' \
		'  - name: dbt-profile' \
		'    configMap: { name: dbt-profile }' \
		'  containers:' \
		'  - name: dbt' \
		'    image: localhost:5000/$(USE_CASE_PREFIX)-dbt-project:$(VERSION)' \
		'    imagePullPolicy: IfNotPresent' \
		'    args: ["run", "--profiles-dir", "/tmp/dbt-profiles", "--project-dir", "/dbt"]' \
		'    volumeMounts:' \
		'    - { name: dbt-profile, mountPath: /tmp/dbt-profiles }' \
		'    env:' \
		'    - { name: CLICKHOUSE_HOST,  value: clickhouse-platform.storage.svc.cluster.local }' \
		'    - { name: CLICKHOUSE_PORT,  value: "8123" }' \
		'    - { name: CLICKHOUSE_USER,     valueFrom: { secretKeyRef: { name: pipeline-secrets, key: CLICKHOUSE_USER } } }' \
		'    - { name: CLICKHOUSE_PASSWORD, valueFrom: { secretKeyRef: { name: pipeline-secrets, key: CLICKHOUSE_PASSWORD } } }' \
		'    resources:' \
		'      requests: { cpu: 200m, memory: 512Mi }' \
		'      limits:   { cpu: "1",  memory: 2Gi   }' \
		'    securityContext:' \
		'      allowPrivilegeEscalation: false' \
		'      readOnlyRootFilesystem: false' \
		'      capabilities: { drop: [ALL] }' \
		| kubectl apply -f -
	@kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/dbt-manual-run -n $(NAMESPACE) --timeout=600s || \
		(echo "$(RED)dbt-manual-run did not Succeed — tail logs:$(NC)"; kubectl logs -n $(NAMESPACE) dbt-manual-run --tail=80; exit 1)
	@kubectl logs -n $(NAMESPACE) dbt-manual-run --tail=20
	@kubectl delete pod dbt-manual-run -n $(NAMESPACE) 2>/dev/null || true
	@echo "$(GREEN)dbt transformations complete.$(NC)"

usecase-crypto-dbt-test: ## Run dbt data quality tests
	@echo "$(YELLOW)Running dbt tests (data quality gates)...$(NC)"
	@kubectl delete pod dbt-test-run -n $(NAMESPACE) 2>/dev/null || true
	@printf '%s\n' \
		'apiVersion: v1' \
		'kind: Pod' \
		'metadata:' \
		'  name: dbt-test-run' \
		'  namespace: $(NAMESPACE)' \
		'spec:' \
		'  restartPolicy: Never' \
		'  securityContext:' \
		'    runAsNonRoot: true' \
		'    runAsUser: 1000' \
		'    runAsGroup: 1000' \
		'    fsGroup: 1000' \
		'    seccompProfile: { type: RuntimeDefault }' \
		'  volumes:' \
		'  - name: dbt-profile' \
		'    configMap: { name: dbt-profile }' \
		'  containers:' \
		'  - name: dbt' \
		'    image: localhost:5000/$(USE_CASE_PREFIX)-dbt-project:$(VERSION)' \
		'    imagePullPolicy: IfNotPresent' \
		'    args: ["test", "--profiles-dir", "/tmp/dbt-profiles", "--project-dir", "/dbt"]' \
		'    volumeMounts:' \
		'    - { name: dbt-profile, mountPath: /tmp/dbt-profiles }' \
		'    env:' \
		'    - { name: CLICKHOUSE_HOST,  value: clickhouse-platform.storage.svc.cluster.local }' \
		'    - { name: CLICKHOUSE_PORT,  value: "8123" }' \
		'    - { name: CLICKHOUSE_USER,     valueFrom: { secretKeyRef: { name: pipeline-secrets, key: CLICKHOUSE_USER } } }' \
		'    - { name: CLICKHOUSE_PASSWORD, valueFrom: { secretKeyRef: { name: pipeline-secrets, key: CLICKHOUSE_PASSWORD } } }' \
		'    resources:' \
		'      requests: { cpu: 100m, memory: 256Mi }' \
		'      limits:   { cpu: 500m, memory: 1Gi   }' \
		'    securityContext:' \
		'      allowPrivilegeEscalation: false' \
		'      readOnlyRootFilesystem: false' \
		'      capabilities: { drop: [ALL] }' \
		| kubectl apply -f -
	@kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/dbt-test-run -n $(NAMESPACE) --timeout=300s || \
		(echo "$(RED)dbt-test-run did not Succeed — tail logs:$(NC)"; kubectl logs -n $(NAMESPACE) dbt-test-run --tail=80; exit 1)
	@kubectl logs -n $(NAMESPACE) dbt-test-run --tail=20
	@kubectl delete pod dbt-test-run -n $(NAMESPACE) 2>/dev/null || true
	@echo "$(GREEN)dbt tests passed.$(NC)"

# -----------------------------------------------------------------------------
# ML LIFECYCLE
# -----------------------------------------------------------------------------

usecase-crypto-train-now: ## Trigger training job immediately (all symbols)
	@kubectl delete job $(USE_CASE_PREFIX)-train-manual -n $(NAMESPACE) 2>/dev/null || true
	@kubectl create job $(USE_CASE_PREFIX)-train-manual --from=cronjob/$(USE_CASE_PREFIX)-training-weekly -n $(NAMESPACE)
	@echo "$(GREEN)Training job created. Monitor: kubectl logs -n $(NAMESPACE) job/$(USE_CASE_PREFIX)-train-manual -c trainer -f$(NC)"

usecase-crypto-feast-materialize: ## Run Feast materialization (ClickHouse → Redis)
	@kubectl delete job $(USE_CASE_PREFIX)-feast-manual -n $(NAMESPACE) 2>/dev/null || true
	@kubectl create job $(USE_CASE_PREFIX)-feast-manual --from=cronjob/$(USE_CASE_PREFIX)-materialization -n $(NAMESPACE)
	@echo "$(GREEN)Materialization job created.$(NC)"

usecase-crypto-katib-run: ## Launch Katib HPO experiment (LightGBM hyperparameter search)
	@kubectl delete experiment $(USE_CASE_PREFIX)-lightgbm-hpo -n $(NAMESPACE) 2>/dev/null || true
	@kubectl apply -f $(USECASE_DIR)/manifests/base/katib/experiment-lightgbm.yaml -n $(NAMESPACE)
	@echo "$(GREEN)Katib experiment created. Monitor: make usecase-crypto-katib-status$(NC)"

usecase-crypto-katib-status: ## Check Katib experiment status
	@kubectl get experiments -n $(NAMESPACE) 2>/dev/null || echo "No experiments found"
	@kubectl get trials -n $(NAMESPACE) 2>/dev/null || echo "No trials found"

usecase-crypto-init-redis: ## Init Redis (feature cache for online serving)
	@echo "$(YELLOW)Initializing Redis...$(NC)"
	@REDIS_POD=$$(kubectl get pods -n storage -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) && \
		kubectl wait --for=condition=ready pod/$$REDIS_POD -n storage --timeout=60s || \
		(echo "$(RED)Redis pod not ready$(NC)" && exit 1)
	@REDIS_POD=$$(kubectl get pods -n storage -l app=redis -o jsonpath='{.items[0].metadata.name}') && \
		kubectl exec -n storage $$REDIS_POD -- redis-cli PING && \
		kubectl exec -n storage $$REDIS_POD -- redis-cli CONFIG SET maxmemory-policy allkeys-lru || true
	@REDIS_POD=$$(kubectl get pods -n storage -l app=redis -o jsonpath='{.items[0].metadata.name}') && \
		kubectl exec -n storage $$REDIS_POD -- redis-cli FT.CREATE feature_idx ON HASH PREFIX 1 "feast:" SCHEMA \
			symbol TAG \
			timestamp NUMERIC 2>/dev/null || \
		echo "$(YELLOW)Index exists or Redis Search not available (OK for basic caching)$(NC)"
	@echo "$(GREEN)Redis init complete.$(NC)"

usecase-crypto-init-kafka: ## Create Kafka topics
	@echo "$(YELLOW)Initializing Kafka topics...$(NC)"
	@kubectl wait --for=condition=ready pod/kafka-0 -n data-ingestion --timeout=60s || \
		(echo "$(RED)Kafka pod not ready$(NC)" && exit 1)
	@kubectl exec -n data-ingestion kafka-0 -- /opt/kafka/bin/kafka-topics.sh --create --if-not-exists --topic $(USE_CASE_PREFIX)-raw --partitions 3 --replication-factor 1 --bootstrap-server localhost:9092 2>/dev/null || true
	@kubectl exec -n data-ingestion kafka-0 -- /opt/kafka/bin/kafka-topics.sh --create --if-not-exists --topic $(USE_CASE_PREFIX)-validated --partitions 3 --replication-factor 1 --bootstrap-server localhost:9092 2>/dev/null || true
	@kubectl exec -n data-ingestion kafka-0 -- /opt/kafka/bin/kafka-topics.sh --create --if-not-exists --topic $(USE_CASE_PREFIX)-features --partitions 3 --replication-factor 1 --bootstrap-server localhost:9092 2>/dev/null || true
	@kubectl exec -n data-ingestion kafka-0 -- /opt/kafka/bin/kafka-topics.sh --create --if-not-exists --topic $(USE_CASE_PREFIX)-predictions --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092 2>/dev/null || true
	@kubectl exec -n data-ingestion kafka-0 -- /opt/kafka/bin/kafka-topics.sh --create --if-not-exists --topic $(USE_CASE_PREFIX)-sentiment --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092 2>/dev/null || true
	@kubectl exec -n data-ingestion kafka-0 -- /opt/kafka/bin/kafka-topics.sh --create --if-not-exists --topic drift-events --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092 2>/dev/null || true
	@kubectl exec -n data-ingestion kafka-0 -- /opt/kafka/bin/kafka-topics.sh --create --if-not-exists --topic $(USE_CASE_PREFIX)-trades --partitions 3 --replication-factor 1 --bootstrap-server localhost:9092 2>/dev/null || true
	@kubectl exec -n data-ingestion kafka-0 -- /opt/kafka/bin/kafka-topics.sh --create --if-not-exists --topic $(USE_CASE_PREFIX)-orderbook --partitions 3 --replication-factor 1 --bootstrap-server localhost:9092 2>/dev/null || true
	@kubectl exec -n data-ingestion kafka-0 -- /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092 2>/dev/null | grep -E "($(USE_CASE_PREFIX)|drift)" || true
	@echo "$(GREEN)Kafka topics init complete.$(NC)"

# -----------------------------------------------------------------------------
# DOCKER IMAGE BUILD — retag generic + rebuild overlays
# -----------------------------------------------------------------------------
# REQUIRES: Generic images first via `make platform-build-services`.
# Services WITHOUT overlay code → retag generic image (fast, no rebuild).
# Services WITH overlay code → rebuild with domain code (TMPDIR / overlay Dockerfile).
# -----------------------------------------------------------------------------

usecase-crypto-build: platform-build-services ## Build generic + retag/rebuild + push crypto images
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)  Building Use-Case Images (retag generic + rebuild overlays)$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@if ! docker image inspect rest-collector:$(VERSION) >/dev/null 2>&1; then \
		echo "$(RED)ERROR: Generic images not found. Run: make platform-build-services$(NC)"; \
		exit 1; \
	fi
	@$(MAKE) usecase-crypto-build-ingestion
	@$(MAKE) usecase-crypto-build-quality
	@$(MAKE) usecase-crypto-build-processing
	@$(MAKE) usecase-crypto-build-training
	@$(MAKE) usecase-crypto-build-serving
	@$(MAKE) usecase-crypto-build-observability
	@$(MAKE) usecase-crypto-build-automation
	@$(MAKE) usecase-crypto-build-dashboard
	@echo ""
	@echo "$(GREEN)All images ready.$(NC)"
	@docker images | grep "$(USE_CASE_PREFIX)-" | head -20

usecase-crypto-build-ingestion: ## Retag ingestion + build websocket-collector overlay
	@echo "$(YELLOW)── Ingestion ──$(NC)"
	@if [ "$(call svc_enabled,ingestion,rest_collector)" = "true" ]; then \
		docker tag rest-collector:$(VERSION) $(USE_CASE_PREFIX)-rest-collector:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-rest-collector) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-rest-collector (retagged)$(NC)"; \
	else echo "$(YELLOW)  - rest-collector SKIPPED$(NC)"; fi
	@if [ "$(call svc_enabled,ingestion,websocket_collector)" = "true" ]; then \
		$(DOCKER_BUILD) -f $(USECASE_DIR)/services/websocket-collector/Dockerfile \
			-t $(USE_CASE_PREFIX)-websocket-collector:$(VERSION) \
			. && \
		$(call _push,$(USE_CASE_PREFIX)-websocket-collector) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-websocket-collector (overlay binary with Coinbase parser)$(NC)"; \
	else echo "$(YELLOW)  - websocket-collector SKIPPED$(NC)"; fi

usecase-crypto-build-quality: ## Retag quality images from generic
	@echo "$(YELLOW)── Quality ──$(NC)"
	@if [ "$(call svc_enabled,quality,validator)" = "true" ]; then \
		docker tag validator:$(VERSION) $(USE_CASE_PREFIX)-validator:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-validator) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-validator (retagged)$(NC)"; \
	else echo "$(YELLOW)  - validator SKIPPED$(NC)"; fi
	@if [ "$(call svc_enabled,quality,analyzer)" = "true" ]; then \
		docker tag analyzer:$(VERSION) $(USE_CASE_PREFIX)-analyzer:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-analyzer) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-analyzer (retagged)$(NC)"; \
	else echo "$(YELLOW)  - analyzer SKIPPED$(NC)"; fi

usecase-crypto-build-processing: ## Rebuild batch (overlay) + retag others + build stream-processor
	@echo "$(YELLOW)── Processing ──$(NC)"
	@if [ "$(call svc_enabled,processing,batch)" = "true" ]; then \
		TMPDIR=$$(mktemp -d) && \
		cp -r $(SERVICES_SRC)/processing/batch/* $$TMPDIR/ && \
		if [ -d $(USECASE_DIR)/services/processing/batch ]; then cp -r $(USECASE_DIR)/services/processing/batch/* $$TMPDIR/; fi && \
		$(DOCKER_BUILD) -t $(USE_CASE_PREFIX)-batch-processing:$(VERSION) $$TMPDIR && \
		rm -rf $$TMPDIR && \
		$(call _push,$(USE_CASE_PREFIX)-batch-processing) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-batch-processing (overlay rebuild)$(NC)"; \
	else echo "$(YELLOW)  - batch-processing SKIPPED$(NC)"; fi
	@if [ "$(call svc_enabled,processing,feature_engine)" = "true" ]; then \
		docker tag feature-engine:$(VERSION) $(USE_CASE_PREFIX)-feature-engine:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-feature-engine) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-feature-engine (retagged)$(NC)"; \
	else echo "$(YELLOW)  - feature-engine SKIPPED$(NC)"; fi
	@if [ "$(call svc_enabled,processing,stream_processor)" = "true" ]; then \
		if ! docker image inspect flink-job:$(VERSION) >/dev/null 2>&1; then \
			echo "$(RED)ERROR: Platform base image flink-job:$(VERSION) not found. Run: make platform-build-services$(NC)"; \
			exit 1; \
		fi; \
		$(DOCKER_BUILD) -t $(USE_CASE_PREFIX)-stream-processor:$(VERSION) $(USECASE_DIR)/services/processing/stream-processor && \
		$(call _push,$(USE_CASE_PREFIX)-stream-processor) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-stream-processor (overlay with Trade/Orderbook functions)$(NC)"; \
	else echo "$(YELLOW)  - stream-processor SKIPPED$(NC)"; fi
	@if [ "$(call svc_enabled,processing,vector)" = "true" ]; then \
		docker tag vector-processing:$(VERSION) $(USE_CASE_PREFIX)-vector-processing:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-vector-processing) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-vector-processing (retagged)$(NC)"; \
	else echo "$(YELLOW)  - vector-processing SKIPPED$(NC)"; fi
	@$(MAKE) usecase-crypto-build-dbt

usecase-crypto-build-dbt: ## Build dbt image with use-case models baked in
	@echo "$(YELLOW)── dbt (use-case models) ──$(NC)"
	@$(DOCKER_BUILD) -f $(USECASE_DIR)/Dockerfile.dbt -t dbt-project:$(VERSION) $(USECASE_DIR) && \
		docker tag dbt-project:$(VERSION) $(USE_CASE_PREFIX)-dbt-project:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-dbt-project) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-dbt-project$(NC)"

usecase-crypto-build-training: ## Retag training + build feast materialization image
	@echo "$(YELLOW)── Training ──$(NC)"
	@if [ "$(call svc_enabled,training,trainer)" = "true" ]; then \
		docker tag trainer:$(VERSION) $(USE_CASE_PREFIX)-trainer:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-trainer) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-trainer (retagged)$(NC)"; \
	else echo "$(YELLOW)  - trainer SKIPPED$(NC)"; fi
	@if [ "$(call svc_enabled,training,drift)" = "true" ]; then \
		docker tag drift-detector:$(VERSION) $(USE_CASE_PREFIX)-drift-detector:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-drift-detector) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-drift-detector (retagged)$(NC)"; \
	else echo "$(YELLOW)  - drift-detector SKIPPED$(NC)"; fi
	@$(DOCKER_BUILD) -f $(USECASE_DIR)/Dockerfile.feast -t $(USE_CASE_PREFIX)-materialization:$(VERSION) $(USECASE_DIR) && \
		$(call _push,$(USE_CASE_PREFIX)-materialization) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-materialization (feast overlay build)$(NC)"

usecase-crypto-build-serving: ## Retag serving images from generic
	@echo "$(YELLOW)── Serving ──$(NC)"
	@if [ "$(call svc_enabled,serving,gateway)" = "true" ]; then \
		docker tag gateway:$(VERSION) $(USE_CASE_PREFIX)-gateway:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-gateway) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-gateway (retagged)$(NC)"; \
	else echo "$(YELLOW)  - gateway SKIPPED$(NC)"; fi
	@if [ "$(call svc_enabled,serving,feature_cache)" = "true" ]; then \
		docker tag feature-cache:$(VERSION) $(USE_CASE_PREFIX)-feature-cache:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-feature-cache) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-feature-cache (retagged)$(NC)"; \
	else echo "$(YELLOW)  - feature-cache SKIPPED$(NC)"; fi
	@if [ "$(call svc_enabled,serving,inference_engine)" = "true" ]; then \
		docker tag inference-engine:$(VERSION) $(USE_CASE_PREFIX)-inference-engine:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-inference-engine) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-inference-engine (retagged)$(NC)"; \
	else echo "$(YELLOW)  - inference-engine SKIPPED$(NC)"; fi
	@if docker image inspect scoring:$(VERSION) >/dev/null 2>&1; then \
		docker tag scoring:$(VERSION) $(USE_CASE_PREFIX)-scoring:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-scoring) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-scoring (retagged)$(NC)"; \
	else echo "$(YELLOW)  - scoring SKIPPED (image not built)$(NC)"; fi

usecase-crypto-build-observability: ## Retag observability images from generic
	@echo "$(YELLOW)── Observability ──$(NC)"
	@if docker image inspect drift-reporter:$(VERSION) >/dev/null 2>&1; then \
		docker tag drift-reporter:$(VERSION) $(USE_CASE_PREFIX)-drift-reporter:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-drift-reporter) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-drift-reporter (retagged)$(NC)"; \
	else echo "$(YELLOW)  - drift-reporter SKIPPED (image not built)$(NC)"; fi

usecase-crypto-build-automation: ## Retag automation images from generic
	@echo "$(YELLOW)── Automation ──$(NC)"
	@if [ "$(call svc_enabled,automation,materialization)" = "true" ]; then \
		docker tag materialization:$(VERSION) $(USE_CASE_PREFIX)-materialization:$(VERSION) && \
		$(call _push,$(USE_CASE_PREFIX)-materialization) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-materialization (retagged)$(NC)"; \
	else echo "$(YELLOW)  - materialization SKIPPED$(NC)"; fi

usecase-crypto-build-dashboard: ## Build dashboard images (UI is inherently use-case-specific)
	@echo "$(YELLOW)── Dashboard ──$(NC)"
	@if [ "$(call svc_enabled,dashboard,backend)" = "true" ]; then \
		$(DOCKER_BUILD) -t $(USE_CASE_PREFIX)-dashboard-backend:$(VERSION) $(USECASE_DIR)/services/dashboard/backend && \
		$(call _push,$(USE_CASE_PREFIX)-dashboard-backend) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-dashboard-backend (use-case build)$(NC)"; \
	else echo "$(YELLOW)  - dashboard-backend SKIPPED$(NC)"; fi
	@if [ "$(call svc_enabled,dashboard,ml_bridge)" = "true" ]; then \
		$(DOCKER_BUILD) -t $(USE_CASE_PREFIX)-ml-bridge:$(VERSION) $(USECASE_DIR)/services/dashboard/ml-bridge && \
		$(call _push,$(USE_CASE_PREFIX)-ml-bridge) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-ml-bridge (use-case build)$(NC)"; \
	else echo "$(YELLOW)  - ml-bridge SKIPPED$(NC)"; fi
	@if [ "$(call svc_enabled,dashboard,frontend)" = "true" ]; then \
		$(DOCKER_BUILD) -t $(USE_CASE_PREFIX)-dashboard-frontend:$(VERSION) $(USECASE_DIR)/services/dashboard/frontend && \
		$(call _push,$(USE_CASE_PREFIX)-dashboard-frontend) && \
		echo "$(GREEN)  + $(USE_CASE_PREFIX)-dashboard-frontend (use-case build)$(NC)"; \
	else echo "$(YELLOW)  - dashboard-frontend SKIPPED$(NC)"; fi

usecase-crypto-images: ## List use-case-prefixed tags present in registry
	@curl -fsS http://$(REGISTRY)/v2/_catalog 2>/dev/null | \
		jq -r --arg p "$(USE_CASE_PREFIX)-" '.repositories[] | select(startswith($$p)) | "  " + .' || \
		echo "$(RED)Registry unreachable: $(REGISTRY)$(NC)"

# -----------------------------------------------------------------------------
# AIRFLOW VARIABLES SEED
# -----------------------------------------------------------------------------

usecase-crypto-seed-airflow-vars: ## Seed USE_CASE Airflow Variables from config (run after deploy)
	@echo "$(BLUE)Seeding Airflow Variables for USE_CASE=$(USE_CASE_NAME)...$(NC)"
	@kubectl exec -n $(AIRFLOW_NS) $(AIRFLOW_DEPLOY) -- bash -c '\
		airflow variables set USE_CASE $(USE_CASE_NAME) && \
		airflow variables set USE_CASE_NAMESPACE $(NAMESPACE) && \
		airflow variables set USE_CASE_REGISTRY $(REGISTRY) && \
		airflow variables set USE_CASE_IMAGE_TAG $(VERSION) && \
		airflow variables set USE_CASE_IMAGE_PREFIX $(USE_CASE_NAME) && \
		airflow variables set USE_CASE_PIPELINE_CONFIGMAP $(USE_CASE_NAME)-pipeline-config && \
		airflow variables set USE_CASE_PIPELINE_SECRET $(USE_CASE_NAME)-pipeline-secrets && \
		airflow variables set OPENLINEAGE_NAMESPACE $(USE_CASE_NAME)-pipeline && \
		airflow variables set OPENLINEAGE_PRODUCER_QUALITY_GATE airflow-$(USE_CASE_NAME)-quality-gate && \
		airflow variables set OPENLINEAGE_PRODUCER_LAKEHOUSE airflow-$(USE_CASE_NAME)-lakehouse'
	@echo "$(GREEN)Airflow Variables seeded.$(NC)"

# -----------------------------------------------------------------------------
# KUBERNETES DEPLOYMENT
# -----------------------------------------------------------------------------

usecase-crypto-up: ## Deploy all use-case-crypto microservices (data + train + serve + app)
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)  Deploying $(NAMESPACE) to Kubernetes ($(ENV))$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@kubectl create namespace $(NAMESPACE) 2>/dev/null || echo "$(YELLOW)Namespace already exists$(NC)"
	@kubectl kustomize $(USECASE_DIR)/manifests/overlays/$(ENV) --load-restrictor LoadRestrictionsNone | kubectl apply -f -
	@echo "$(GREEN)Deployment initiated.$(NC)"
	@sleep 5
	@$(MAKE) usecase-crypto-status

usecase-crypto-up-local: ## Deploy to local cluster (ENV=local)
	@ENV=local $(MAKE) usecase-crypto-up

usecase-crypto-up-cloud: ## Deploy to cloud cluster (ENV=cloud)
	@ENV=cloud $(MAKE) usecase-crypto-up

usecase-crypto-deploy-data: ## Deploy Data sub-phase only
	@echo "$(BLUE)  Deploying Data only ($(ENV))$(NC)"
	@kubectl create namespace $(NAMESPACE) 2>/dev/null || echo "$(YELLOW)Namespace already exists$(NC)"
	@kubectl kustomize $(USECASE_DIR)/manifests/overlays/$(ENV)-data --load-restrictor LoadRestrictionsNone | kubectl apply -f -
	@sleep 5
	@$(MAKE) usecase-crypto-status

usecase-crypto-deploy-train: ## Deploy Train sub-phase only
	@echo "$(BLUE)  Deploying Train only ($(ENV))$(NC)"
	@kubectl create namespace $(NAMESPACE) 2>/dev/null || echo "$(YELLOW)Namespace already exists$(NC)"
	@kubectl kustomize $(USECASE_DIR)/manifests/overlays/$(ENV)-train --load-restrictor LoadRestrictionsNone | kubectl apply -f -
	@kubectl get cronjobs -n $(NAMESPACE) | grep -E "training|drift|retraining"

usecase-crypto-deploy-serve: ## Deploy Data+Train+Serve (removes App workloads)
	@$(MAKE) usecase-crypto-up
	@echo "$(YELLOW)Removing App workloads...$(NC)"
	@for d in $(APP_DEPLOYMENTS); do \
		kubectl delete deployment $(USE_CASE_PREFIX)-$$d -n $(NAMESPACE) --ignore-not-found=true 2>/dev/null || true; \
		kubectl delete service $(USE_CASE_PREFIX)-$$d -n $(NAMESPACE) --ignore-not-found=true 2>/dev/null || true; \
	done
	@for cj in $(APP_CRONJOBS); do \
		kubectl delete cronjob $(USE_CASE_PREFIX)-$$cj -n $(NAMESPACE) --ignore-not-found=true 2>/dev/null || true; \
	done
	@echo "$(GREEN)Data+Train+Serve deployed (App removed).$(NC)"

usecase-crypto-deploy-app: ## Deploy all phases (same as usecase-crypto-up)
	@$(MAKE) usecase-crypto-up

usecase-crypto-down: ## Undeploy use-case-crypto
	@echo "$(YELLOW)Removing all use-case deployments from $(NAMESPACE)...$(NC)"
	@kubectl kustomize $(USECASE_DIR)/manifests/overlays/$(ENV) --load-restrictor LoadRestrictionsNone | kubectl delete -f - --ignore-not-found=true
	@echo "$(GREEN)All deployments removed.$(NC)"

usecase-crypto-redeploy: ## Redeploy (down + up)
	@$(MAKE) usecase-crypto-down
	@sleep 3
	@$(MAKE) usecase-crypto-up

# -----------------------------------------------------------------------------
# STOP / RESUME (scale to 0 / back to 1, data preserved)
# -----------------------------------------------------------------------------

usecase-crypto-stop-data: ## Stop services (scale to 0 + suspend CronJobs, data preserved)
	@echo "$(YELLOW)Stopping services...$(NC)"
	@kubectl scale deploy -n $(NAMESPACE) --all --replicas=0 2>/dev/null || true
	@kubectl get cronjobs -n $(NAMESPACE) -o name 2>/dev/null | xargs -I{} kubectl patch {} -n $(NAMESPACE) -p '{"spec":{"suspend":true}}' 2>/dev/null || true
	@kubectl delete pods -n $(NAMESPACE) --field-selector=status.phase=Succeeded --force --grace-period=0 2>/dev/null || true
	@kubectl delete pods -n $(NAMESPACE) -l job-name --force --grace-period=0 2>/dev/null || true
	@echo "$(GREEN)Stopped. Data preserved. Resume: make usecase-crypto-resume-data$(NC)"

usecase-crypto-resume-data: ## Resume services (scale back to 1 + unsuspend CronJobs)
	@echo "$(YELLOW)Resuming services...$(NC)"
	@kubectl scale deploy -n $(NAMESPACE) --all --replicas=1 2>/dev/null || true
	@kubectl get cronjobs -n $(NAMESPACE) -o name 2>/dev/null | xargs -I{} kubectl patch {} -n $(NAMESPACE) -p '{"spec":{"suspend":false}}' 2>/dev/null || true
	@echo "$(GREEN)Resumed. Run 'make usecase-crypto-status' to verify.$(NC)"

usecase-crypto-stop-train: usecase-crypto-stop-data ## Stop Train (same as stop-data — single namespace)
usecase-crypto-resume-train: usecase-crypto-resume-data ## Resume Train
usecase-crypto-stop-serve: usecase-crypto-stop-data ## Stop Serve
usecase-crypto-resume-serve: usecase-crypto-resume-data ## Resume Serve
usecase-crypto-stop-app: usecase-crypto-stop-data ## Stop App
usecase-crypto-resume-app: usecase-crypto-resume-data ## Resume App

# -----------------------------------------------------------------------------
# STATUS / MONITORING
# -----------------------------------------------------------------------------

usecase-crypto-status: ## Check deployment status
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)  Deployment Status - $(NAMESPACE)$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@kubectl get pods -n $(NAMESPACE) 2>/dev/null || echo "$(YELLOW)Namespace $(NAMESPACE) not found$(NC)"
	@echo "$(YELLOW)CronJobs:$(NC)"
	@kubectl get cronjobs -n $(NAMESPACE) 2>/dev/null || true
	@echo "$(YELLOW)Services:$(NC)"
	@kubectl get svc -n $(NAMESPACE) 2>/dev/null || true

usecase-crypto-status-all: ## Check all relevant namespaces
	@kubectl get pods -A | grep -E "($(NAMESPACE)|storage|data-ingestion|model-lifecycle)" | head -30

usecase-crypto-logs: ## View logs (usage: make usecase-crypto-logs DEPLOY=rest-collector)
	@if [ -z "$(DEPLOY)" ]; then \
		echo "$(YELLOW)Usage: make usecase-crypto-logs DEPLOY=<deployment-name>$(NC)"; \
		echo ""; \
		echo "Available deployments:"; \
		kubectl get deployments -n $(NAMESPACE) -o name 2>/dev/null | sed 's/deployment.apps\///'; \
	else \
		kubectl logs -f deployment/$(DEPLOY) -n $(NAMESPACE) --all-containers=true; \
	fi

usecase-crypto-logs-all: ## View all logs
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=$(USE_CASE_PREFIX)-pipeline --all-containers=true -f --max-log-requests=20

usecase-crypto-restart: ## Restart all deployments
	@kubectl rollout restart deployment -n $(NAMESPACE)
	@echo "$(GREEN)Restart initiated.$(NC)"

usecase-crypto-restart-one: ## Restart specific deployment (DEPLOY=rest-collector)
	@if [ -z "$(DEPLOY)" ]; then \
		echo "$(YELLOW)Usage: make usecase-crypto-restart-one DEPLOY=<deployment-name>$(NC)"; \
	else \
		kubectl rollout restart deployment/$(DEPLOY) -n $(NAMESPACE); \
	fi

# -----------------------------------------------------------------------------
# TESTING
# -----------------------------------------------------------------------------

usecase-crypto-test: ## Run all use-case tests (6 languages) — fails on first error
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)  Running All Tests (18 services, 6 languages)$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@FAIL=0; \
	echo "$(YELLOW)── [1/6] Python ──$(NC)"; \
	$(MAKE) usecase-crypto-test-python || FAIL=1; \
	echo "$(YELLOW)── [2/6] Rust ──$(NC)"; \
	$(MAKE) usecase-crypto-test-rust || FAIL=1; \
	echo "$(YELLOW)── [3/6] Go ──$(NC)"; \
	$(MAKE) usecase-crypto-test-go || FAIL=1; \
	echo "$(YELLOW)── [4/6] Java ──$(NC)"; \
	$(MAKE) usecase-crypto-test-java || FAIL=1; \
	echo "$(YELLOW)── [5/6] C++ ──$(NC)"; \
	$(MAKE) usecase-crypto-test-cpp || FAIL=1; \
	echo "$(YELLOW)── [6/6] TypeScript ──$(NC)"; \
	$(MAKE) usecase-crypto-test-ts || FAIL=1; \
	if [ $$FAIL -eq 1 ]; then \
		echo "$(RED)  TESTS FAILED$(NC)"; exit 1; \
	fi; \
	echo "$(GREEN)  ALL TESTS PASSED$(NC)"

usecase-crypto-test-python: ## Run Python tests (uv + pytest)
	@cd $(SERVICES_SRC)/trainer && uv run pytest tests/ -v
	@cd $(SERVICES_SRC)/quality/drift && uv run pytest tests/ -v
	@cd $(SERVICES_SRC)/quality/analyzer && uv run pytest tests/ -v
	@cd $(SERVICES_SRC)/processing/batch && uv run pytest tests/ -v
	@cd $(SERVICES_SRC)/processing/vector && uv run pytest tests/ -v
	@cd $(SERVICES_SRC)/dashboard/ml-bridge && uv run pytest tests/ -v
	@cd $(SERVICES_SRC)/automation/materialization && uv run pytest tests/ -v
	@cd $(SERVICES_SRC)/automation/retraining && uv run pytest tests/ -v

usecase-crypto-test-rust: ## Run Rust tests (cargo-nextest)
	@cd $(SERVICES_SRC)/ingestion/websocket-collector && cargo nextest run 2>/dev/null || cargo test
	@cd $(SERVICES_SRC)/quality/validator && cargo nextest run 2>/dev/null || cargo test
	@cd $(SERVICES_SRC)/processing/stream/feature-engine && cargo nextest run 2>/dev/null || cargo test
	@cd $(SERVICES_SRC)/serving/gateway && cargo nextest run 2>/dev/null || cargo test
	@cd $(SERVICES_SRC)/serving/feature-cache && cargo nextest run 2>/dev/null || cargo test
	@cd $(USECASE_DIR)/services/websocket-collector && cargo nextest run 2>/dev/null || cargo test

usecase-crypto-test-go: ## Run Go tests
	@cd $(SERVICES_SRC)/ingestion/rest-collector && go test ./...
	@cd $(SERVICES_SRC)/dashboard/backend && go test ./...

usecase-crypto-test-java: ## Run Java tests (Mill)
	@cd $(SERVICES_SRC)/processing/stream/flink-job && mill flink.test
	@cd $(USECASE_DIR)/services/processing/stream-processor && mill flink.test

usecase-crypto-test-cpp: ## Run C++ tests (xmake — requires protoc, grpc, onnxruntime)
	@(pkg-config --exists grpc++ protobuf 2>/dev/null && test -d /opt/onnxruntime) || { echo "$(YELLOW)  SKIP: C++ system deps not installed$(NC)"; exit 0; }
	@cd $(SERVICES_SRC)/serving/inference-engine && mkdir -p build/generated && xmake f --tests=y && xmake run test_inference

usecase-crypto-test-ts: ## Run TypeScript tests (bun + vitest)
	@cd $(SERVICES_SRC)/dashboard/frontend && bun install --frozen-lockfile 2>/dev/null || bun install && bun run --bun vitest --run

# -----------------------------------------------------------------------------
# LINTING / FORMATTING
# -----------------------------------------------------------------------------

usecase-crypto-lint: ## Run all use-case linters (6 languages)
	@$(MAKE) usecase-crypto-lint-python
	@$(MAKE) usecase-crypto-lint-rust
	@$(MAKE) usecase-crypto-lint-go
	@$(MAKE) usecase-crypto-lint-java
	@$(MAKE) usecase-crypto-lint-cpp
	@$(MAKE) usecase-crypto-lint-ts

usecase-crypto-lint-python: ## Lint Python (ruff via uv)
	@uv run --with ruff ruff check $(SERVICES_SRC)/

usecase-crypto-lint-rust: ## Lint Rust (clippy)
	@cd $(SERVICES_SRC)/ingestion/websocket-collector && cargo clippy -- -D warnings
	@cd $(SERVICES_SRC)/quality/validator && cargo clippy -- -D warnings
	@cd $(SERVICES_SRC)/processing/stream/feature-engine && cargo clippy -- -D warnings
	@cd $(SERVICES_SRC)/serving/gateway && cargo clippy -- -D warnings
	@cd $(SERVICES_SRC)/serving/feature-cache && cargo clippy -- -D warnings
	@cd $(USECASE_DIR)/services/websocket-collector && cargo clippy -- -D warnings

usecase-crypto-lint-go: ## Lint Go (golangci-lint)
	@cd $(SERVICES_SRC)/ingestion/rest-collector && golangci-lint run ./... 2>/dev/null || go vet ./...
	@cd $(SERVICES_SRC)/dashboard/backend && golangci-lint run ./... 2>/dev/null || go vet ./...

usecase-crypto-lint-java: ## Lint Java (Mill compile check)
	@cd $(SERVICES_SRC)/processing/stream/flink-job && mill flink.compile
	@cd $(USECASE_DIR)/services/processing/stream-processor && mill flink.compile

usecase-crypto-lint-cpp: ## Lint C++ (xmake compile check)
	@which xmake > /dev/null 2>&1 || { echo "$(YELLOW)  SKIP: xmake not installed$(NC)"; exit 0; }
	@cd $(SERVICES_SRC)/serving/inference-engine && mkdir -p build/generated && xmake f --tests=y -y && xmake build test_inference

usecase-crypto-lint-ts: ## Lint TypeScript (eslint via bun)
	@cd $(SERVICES_SRC)/dashboard/frontend && bun run lint

usecase-crypto-format: ## Format all use-case code
	@echo "$(YELLOW)Formatting code...$(NC)"
	@cd $(SERVICES_SRC)/ingestion/websocket-collector && cargo fmt 2>/dev/null || true
	@cd $(SERVICES_SRC)/quality/validator && cargo fmt 2>/dev/null || true
	@cd $(SERVICES_SRC)/processing/stream/feature-engine && cargo fmt 2>/dev/null || true
	@cd $(SERVICES_SRC)/serving/gateway && cargo fmt 2>/dev/null || true
	@cd $(SERVICES_SRC)/serving/feature-cache && cargo fmt 2>/dev/null || true
	@uv run --with ruff ruff format $(SERVICES_SRC)/ 2>/dev/null || true
	@cd $(SERVICES_SRC)/ingestion/rest-collector && go fmt ./... 2>/dev/null || true
	@cd $(SERVICES_SRC)/dashboard/backend && go fmt ./... 2>/dev/null || true
	@cd $(SERVICES_SRC)/dashboard/frontend && bun x prettier --write src/ 2>/dev/null || true
	@cd $(USECASE_DIR)/services/websocket-collector && cargo fmt 2>/dev/null || true

# -----------------------------------------------------------------------------
# CLEANUP
# -----------------------------------------------------------------------------

usecase-crypto-clean: ## Clean use-case build artifacts
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@cd $(SERVICES_SRC)/ingestion/websocket-collector && cargo clean 2>/dev/null || true
	@cd $(SERVICES_SRC)/quality/validator && cargo clean 2>/dev/null || true
	@cd $(SERVICES_SRC)/processing/stream/feature-engine && cargo clean 2>/dev/null || true
	@cd $(SERVICES_SRC)/serving/gateway && cargo clean 2>/dev/null || true
	@cd $(SERVICES_SRC)/serving/feature-cache && cargo clean 2>/dev/null || true
	@cd $(SERVICES_SRC)/serving/inference-engine && xmake clean 2>/dev/null || rm -rf build 2>/dev/null || true
	@cd $(SERVICES_SRC)/processing/stream/flink-job && rm -rf out/ .mill-jvm-opts 2>/dev/null || true
	@rm -rf $(SERVICES_SRC)/dashboard/frontend/dist 2>/dev/null || true
	@rm -rf $(SERVICES_SRC)/dashboard/frontend/node_modules 2>/dev/null || true
	@find $(SERVICES_SRC) -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find $(SERVICES_SRC) -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	@find $(SERVICES_SRC) -type d -name "target" -exec rm -rf {} + 2>/dev/null || true
	@find $(SERVICES_SRC) -type d -name ".xmake" -exec rm -rf {} + 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete.$(NC)"

usecase-crypto-clean-images: ## Remove all crypto Docker images
	@docker images | grep "$(USE_CASE_PREFIX)-" | awk '{print $$3}' | xargs -r docker rmi -f 2>/dev/null || true
	@docker images | grep "$(REGISTRY)/$(USE_CASE_PREFIX)-" | awk '{print $$3}' | xargs -r docker rmi -f 2>/dev/null || true
	@echo "$(GREEN)Images removed.$(NC)"

usecase-crypto-clean-all: usecase-crypto-clean usecase-crypto-clean-images usecase-crypto-down ## Clean everything

# -----------------------------------------------------------------------------
# UTILITIES
# -----------------------------------------------------------------------------

usecase-crypto-shell-clickhouse: ## Open ClickHouse shell
	@kubectl exec -it -n storage clickhouse-0 -- clickhouse-client

usecase-crypto-shell-redis: ## Open Redis shell
	@REDIS_POD=$$(kubectl get pods -n storage -l app=redis -o jsonpath='{.items[0].metadata.name}') && \
		kubectl exec -it -n storage $$REDIS_POD -- redis-cli

usecase-crypto-shell-kafka: ## Open Kafka shell
	@kubectl exec -it -n data-ingestion kafka-0 -- bash

usecase-crypto-port-forward-dashboard: ## Port forward dashboard (localhost:3000)
	@echo "$(YELLOW)Dashboard at http://localhost:3000$(NC)"
	@kubectl port-forward -n $(NAMESPACE) svc/$(USE_CASE_PREFIX)-dashboard-frontend 3000:80

usecase-crypto-port-forward-gateway: ## Port forward gateway API (localhost:8080)
	@echo "$(YELLOW)Gateway API at http://localhost:8080$(NC)"
	@kubectl port-forward -n $(NAMESPACE) svc/$(USE_CASE_PREFIX)-gateway 8080:8080

usecase-crypto-check-cluster: ## Check if K8s cluster is running + dependencies
	@kubectl cluster-info || (echo "$(RED)Cluster not running.$(NC)" && exit 1)
	@kubectl get pods -n storage | grep -E "(clickhouse|redis|minio)" || true
	@kubectl get pods -n data-ingestion | grep kafka || true
	@kubectl get pods -n model-lifecycle | grep mlflow || true
	@echo "$(GREEN)Cluster ready.$(NC)"

usecase-crypto-proto: ## Generate all proto files
	@$(USECASE_DIR)/scripts/proto-gen.sh 2>/dev/null || \
		(echo "$(YELLOW)Running inline proto generation...$(NC)" && \
		protoc --go_out=. --go-grpc_out=. $(USECASE_DIR)/proto/*.proto 2>/dev/null || true)

# -----------------------------------------------------------------------------
# WORKFLOW COMMANDS (Airflow / Kubeflow)
# -----------------------------------------------------------------------------

usecase-crypto-sync-dags: ## Sync Airflow DAGs into the Airflow pod
	@echo "$(BLUE)Syncing Airflow DAGs...$(NC)"
	@AIRFLOW_POD=$$($(KUBECTL) get pods -n data-processing -l app=airflow -o name | head -1) && \
		if [ -n "$$AIRFLOW_POD" ]; then \
			$(KUBECTL) cp $(USECASE_DIR)/dags/ data-processing/$${AIRFLOW_POD#pod/}:/opt/airflow/dags/ && \
			echo "$(GREEN)DAGs synced.$(NC)"; \
		else \
			echo "$(YELLOW)Airflow pod not found$(NC)"; \
		fi

usecase-crypto-submit-pipeline: ## Compile + submit KFP retraining pipeline
	@echo "$(BLUE)Submitting Kubeflow Pipeline...$(NC)"
	@$(KUBECTL) port-forward svc/ml-pipeline -n model-lifecycle 8888:8888 > /dev/null 2>&1 & \
		PF_PID=$$! && sleep 5 && \
		cd $(USECASE_DIR)/pipelines && \
		KFP_HOST=http://localhost:8888 uv run --with 'kfp[kubernetes]==2.16.0' submit_recurring.py && \
		kill $$PF_PID 2>/dev/null && \
		echo "$(GREEN)Pipeline submitted.$(NC)" || \
		{ kill $$PF_PID 2>/dev/null; echo "$(YELLOW)KFP not available — pipeline submission deferred$(NC)"; }
