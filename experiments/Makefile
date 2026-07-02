# Live-demo and evaluation runner.
# Run from repo root:  make -C experiments <target>
# Or from here:        make <target>

SHELL := /bin/bash
# Resolve demo.sh and this folder.
HERE  := $(dir $(lastword $(MAKEFILE_LIST)))
DEMO  := bash $(HERE)demo.sh
# Bind address for UI port-forwards, override with ADDR=0.0.0.0.
ADDR  ?= 127.0.0.1
export DEMO_ADDR := $(ADDR)

.PHONY: help check core data drift predict lineage vector \
        ui creds grafana datahub superset argocd minio mlflow \
        kafka-ui prometheus trino airflow qdrant \
        chaos chaos-clean load eval

help: # list every target
	@echo "Demo data scenarios (read-only, safe on stage)"
	@echo "  data         KF-03/05 medallion row counts and coverage"
	@echo "  drift        KF-07 multi-scale PSI and KS, retrain trigger"
	@echo "  predict      serving output, buy hold sell direction"
	@echo "  lineage      KF-08 DataHub lineage graph UI"
	@echo "  vector       KF-04 Qdrant vector-search latency"
	@echo "  core         run data, drift, predict back to back"
	@echo ""
	@echo "UI access (one per terminal, Ctrl-C to stop the forward)"
	@echo "  ui           print all UI URLs and logins"
	@echo "  creds        same as ui, reads logins from live secrets"
	@echo "  grafana datahub superset argocd minio mlflow"
	@echo "  kafka-ui prometheus trino airflow qdrant"
	@echo ""
	@echo "Evaluation"
	@echo "  chaos        apply Chaos Mesh resilience experiments"
	@echo "  chaos-clean  delete the Chaos Mesh experiments"
	@echo "  load         run every k6 script under load/"
	@echo "  eval SCN=<f> run one folder, e.g. make eval SCN=parity"
	@echo ""
	@echo "Access from a laptop, per UI port:"
	@echo "  ssh -L PORT:127.0.0.1:PORT USER@NODE   then open http://localhost:PORT"
	@echo "Or expose on the node itself:"
	@echo "  make <ui> ADDR=0.0.0.0                 then open http://NODE_IP:PORT"

check: # stop when node load is high
	@L=$$(cut -d' ' -f1 /proc/loadavg); echo "load1=$$L"; \
	awk -v l=$$L 'BEGIN{ exit (l+0 < 20) ? 0 : 1 }' \
	  || { echo "load too high, let the node settle first"; exit 1; }

data drift predict lineage vector: # run one demo scenario
	@$(DEMO) $@

core: data drift predict # three bulletproof demos

ui: creds # alias for creds

creds: # print UI urls and logins
	@$(DEMO) creds

grafana datahub superset argocd minio mlflow kafka-ui prometheus trino airflow qdrant: # forward one UI
	@$(DEMO) $@

chaos: # apply resilience experiments
	@echo "applying Chaos Mesh experiments from $(HERE)chaos/"
	@kubectl apply -f $(HERE)chaos/

chaos-clean: # delete resilience experiments
	@kubectl delete -f $(HERE)chaos/ --ignore-not-found

load: # run k6 scripts under load/
	@command -v k6 >/dev/null 2>&1 || { echo "k6 not installed, skipping"; exit 1; }
	@for f in $(HERE)load/*.js; do [ -e "$$f" ] || continue; echo "k6 run $$f"; k6 run "$$f" || true; done

eval: # run one evaluation folder by discovered entry
	@d=$(HERE)$(SCN); \
	if [ -z "$(SCN)" ]; then echo "set SCN=<folder>, e.g. make eval SCN=parity"; exit 2; fi; \
	if [ ! -d "$$d" ]; then echo "no folder $$d"; exit 2; fi; \
	if [ -f "$$d/run.sh" ]; then bash "$$d/run.sh"; \
	elif [ -f "$$d/Makefile" ]; then $(MAKE) -C "$$d"; \
	elif ls "$$d"/*.sh >/dev/null 2>&1; then for s in "$$d"/*.sh; do echo "bash $$s"; bash "$$s"; done; \
	elif ls "$$d"/*.yaml >/dev/null 2>&1; then kubectl apply -f "$$d/"; \
	else echo "no run.sh, Makefile, shell, or yaml entry in $$d"; fi
