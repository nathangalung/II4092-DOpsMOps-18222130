# Live-demo and evaluation runner.
# Run from repo root:  make -C experiments <target>
# Or from here:        make <target>

SHELL := /bin/bash
# Resolve demo.sh and this folder.
HERE  := $(dir $(lastword $(MAKEFILE_LIST)))
DEMO  := bash $(HERE)demo.sh
# Domain values, one swap point.
CONFIG ?= $(HERE)config.crypto.env
export EXPERIMENTS_CONFIG := $(CONFIG)
# Bind address for UI port-forwards.
ADDR  ?= 127.0.0.1
export DEMO_ADDR := $(ADDR)
# Walk slice controls.
FROM ?=
TO   ?=
SHOW ?= 0
export FROM
export TO
export SHOW
# Folder for eval target.
SCN  ?=
# Drift injector knobs.
SIGMA ?= 2.0
DUR   ?= 600

.PHONY: help check verify walk \
        ingest process feast train serve drift govern \
        data predict lineage vector core \
        ui creds grafana datahub superset argocd minio mlflow \
        kafka-ui prometheus trino airflow qdrant \
        chaos chaos-clean load eval drift-inject provision eval-map

help: # list every target
	@echo "Connectivity, safe on this node"
	@echo "  verify        wiring status for every pipeline stage"
	@echo "  walk          verify each stage in order (FROM/TO slice, SHOW=1 adds evidence)"
	@echo ""
	@echo "Per stage, verify then read-only evidence"
	@echo "  ingest process feast train serve drift govern"
	@echo ""
	@echo "Read-only evidence shortcuts"
	@echo "  data     medallion rows and freshness"
	@echo "  predict  latest serving predictions"
	@echo "  drift    multi-scale drift scores (KF-07)"
	@echo "  lineage  DataHub lineage walk (KF-08, needs DATAHUB_TOKEN)"
	@echo "  vector   Qdrant vector-search latency (KF-04)"
	@echo "  core     data, predict, drift back to back"
	@echo ""
	@echo "UI access, one per terminal, Ctrl-C to stop"
	@echo "  creds    print all UI URLs and logins"
	@echo "  grafana datahub superset argocd minio mlflow"
	@echo "  kafka-ui prometheus trino airflow qdrant"
	@echo ""
	@echo "Evaluation"
	@echo "  chaos        apply Chaos Mesh experiments (KNF-03/04)"
	@echo "  chaos-clean  delete the Chaos Mesh experiments"
	@echo "  load         run every k6 script under load/ (KNF-01/02)"
	@echo "  drift-inject inject synthetic drift, KF-07 (SIGMA= DUR=)"
	@echo "  eval SCN=<f> run one folder, e.g. make eval SCN=parity"
	@echo "  eval-map     print which command proves which requirement"
	@echo ""
	@echo "Provisioning a slice on a resourced cluster"
	@echo "  provision    print the root make commands per pipeline slice"
	@echo ""
	@echo "Remote access from a laptop: see experiments/REMOTE_ACCESS.md"
	@echo "Full demo script: see experiments/RUNBOOK.md"

check: # stop when load is high
	@L=$$(cut -d' ' -f1 /proc/loadavg); echo "load1=$$L"; \
	awk -v l=$$L 'BEGIN{ exit (l+0 < 20) ? 0 : 1 }' \
	  || { echo "load too high, let the node settle first"; exit 1; }

verify: # wiring status for every stage
	@$(DEMO) verify all

walk: # verify stages, optional slice
	@$(DEMO) walk

ingest process feast train serve drift govern: # verify then show one stage
	@$(DEMO) $@

data predict lineage vector core: # read-only evidence shortcut
	@$(DEMO) $@

ui: creds # alias for creds

creds: # print UI urls and logins
	@$(DEMO) creds

grafana datahub superset argocd minio mlflow kafka-ui prometheus trino airflow qdrant: # forward one UI
	@$(DEMO) $@

chaos: # apply resilience experiments
	@command -v envsubst >/dev/null 2>&1 || { echo "envsubst not installed"; exit 1; }
	@kubectl apply -f $(HERE)namespace.yaml
	@set -a; . $(CONFIG); set +a; \
	for f in $(HERE)chaos/*.yaml; do [ -e "$$f" ] || continue; echo "apply $$f"; envsubst < "$$f" | kubectl apply -f -; done

chaos-clean: # delete resilience experiments
	@command -v envsubst >/dev/null 2>&1 || { echo "envsubst not installed"; exit 1; }
	@set -a; . $(CONFIG); set +a; \
	for f in $(HERE)chaos/*.yaml; do [ -e "$$f" ] || continue; envsubst < "$$f" | kubectl delete --ignore-not-found -f -; done
	@kubectl delete -f $(HERE)namespace.yaml --ignore-not-found

load: # run k6 scripts under load/
	@command -v k6 >/dev/null 2>&1 || { echo "k6 not installed, skipping"; exit 1; }
	@set -a; . $(CONFIG); set +a; \
	for f in $(HERE)load/*.js; do [ -e "$$f" ] || continue; echo "k6 run $$f"; k6 run "$$f" || true; done

drift-inject: # inject synthetic drift (KF-07)
	@$(DEMO) drift-inject --sigma $(SIGMA) --duration $(DUR)

eval: # run one evaluation folder
	@d=$(HERE)$(SCN); \
	if [ -z "$(SCN)" ]; then echo "set SCN=<folder>, e.g. make eval SCN=parity"; exit 2; fi; \
	if [ ! -d "$$d" ]; then echo "no folder $$d"; exit 2; fi; \
	set -a; . $(CONFIG); set +a; \
	if [ -f "$$d/run.sh" ]; then bash "$$d/run.sh"; \
	elif [ -f "$$d/Makefile" ]; then $(MAKE) -C "$$d"; \
	elif ls "$$d"/*.sh >/dev/null 2>&1; then for s in "$$d"/*.sh; do echo "bash $$s"; bash "$$s"; done; \
	elif ls "$$d"/*.yaml >/dev/null 2>&1; then kubectl apply -f "$$d/"; \
	else echo "no run.sh, Makefile, shell, or yaml entry in $$d"; fi

eval-map: # requirement to command map
	@echo "Functional (KF)"
	@echo "  KF-02 feast online serving   make feast   (or feast/online-serving-check.py)"
	@echo "  KF-04 vector search latency  make vector"
	@echo "  KF-07 drift and retrain      make drift; inject via make drift-inject"
	@echo "  KF-08 DataHub lineage        make lineage (needs DATAHUB_TOKEN)"
	@echo "  KF-11 batch stream parity    make process (parity/parity-check.sh)"
	@echo "Nonfunctional (KNF)"
	@echo "  KNF-01 online latency        make load    (load/feast-online-latency.js)"
	@echo "  KNF-02 throughput and lag    make load    (load/feast-throughput.js)"
	@echo "  KNF-03 autoscale rampup      make load    (load/hpa-keda-rampup.js)"
	@echo "  KNF-04 resilience game day   make chaos"

provision: # root make commands per slice
	@echo "Provision a slice on a resourced cluster, run from repo root"
	@echo "  ingestion only        make phase-ingest-stream"
	@echo "  stream to feast        make phase-stream-to-feast"
	@echo "  batch to feast         make phase-batch-to-feast"
	@echo "  feast to training      make phase-feast-to-training"
	@echo "  train and serve        make phase-train-to-serving"
	@echo "  full stream pipeline   make phase-stream-e2e"
	@echo "  everything             make phase-full"
	@echo ""
	@echo "Deploy the use case, then run a stage"
	@echo "  build and deploy       make usecase-crypto-build && make usecase-crypto-up"
	@echo "  deploy data subphase   make usecase-crypto-data"
	@echo "  deploy train subphase  make usecase-crypto-train"
	@echo "  deploy serve subphase  make usecase-crypto-serve"
	@echo "  run dbt transforms     make usecase-crypto-dbt-run"
	@echo "  feast materialize      airflow dags trigger crypto_hourly_features"
	@echo "  submit KFP training    make usecase-crypto-submit-pipeline"
