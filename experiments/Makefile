# Live-demo runner for evaluation scenarios.
# Run from repo root: make -C experiments <target>
# Or from here:       make <target>

SHELL := /bin/bash
# Resolve demo.sh next to this Makefile.
DEMO  := bash $(dir $(lastword $(MAKEFILE_LIST)))demo.sh

.PHONY: help check data drift predict lineage vector core

help: # list demo targets
	@echo "evaluation demo targets"
	@echo "  check     guard cluster load below 20"
	@echo "  data      KF-03/05 medallion row counts"
	@echo "  drift     KF-07 PSI and KS"
	@echo "  predict   serving buy hold sell"
	@echo "  lineage   KF-08 DataHub lineage UI"
	@echo "  vector    KF-04 Qdrant search latency"
	@echo "  core      run data drift lineage"

check: # stop if load high
	@L=$$(cut -d' ' -f1 /proc/loadavg); echo "load1=$$L"; \
	awk -v l=$$L 'BEGIN{ exit (l+0 < 20) ? 0 : 1 }' \
	  || { echo "load too high, recover the cluster first"; exit 1; }

data drift predict lineage vector: # run one scenario
	@$(DEMO) $@

core: data drift lineage # three safe demos
