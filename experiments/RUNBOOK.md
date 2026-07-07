# Live demo runbook

This is the script to run the platform during a defense or a walkthrough. It
drives the pipeline one stage at a time, checks that each stage is wired,
prints the evidence a stage produced, and opens the consoles. Everything here
is read-only against the running cluster. It never edits or redeploys the use
case, so it is safe to run live.

Two ideas keep this reproducible on any cluster. First, the runner reads all
domain values from one file, `experiments/config.crypto.env`, so a different
use case is a config swap, not a code change. Second, provisioning and running
the heavy pipeline stay in the root Makefile phases; this runner only exercises
and verifies whatever slice you provisioned. On this VPS the disk is the limit,
so the goal is to prove each stage is connected, not to keep every pod running
at once. On a cluster with room, the same commands drive the full pipeline.

Run the read-only steps over plain SSH. Run the UI steps with a tunnel, one per
terminal; see `REMOTE_ACCESS.md`.

## Before you start

Check the node is calm. The connectivity checks are cheap, but a busy disk
makes pods flap.

    make -C experiments check

Point at a different use case if needed. The crypto values are the default.

    export EXPERIMENTS_CONFIG=experiments/config.fraud.env   # optional

## Step 1, provision the slice you want

Provisioning lives in the root Makefile. Pick the smallest slice that shows
what you want. Run these from the repo root, on a cluster with resources.

    make -C experiments provision      # prints the list below

    make phase-ingest-stream           # ingestion only
    make phase-stream-to-feast         # up to the feature store
    make phase-train-to-serving        # training and serving
    make phase-stream-e2e              # the full stream pipeline
    make phase-full                    # everything

Then build and deploy the use case, and trigger a stage when you want it to
run:

    make usecase-crypto-build && make usecase-crypto-up
    make usecase-crypto-dbt-run            # run dbt, bronze to silver to gold
    make usecase-crypto-submit-pipeline    # register KFP retraining runs

Feast materialization runs as a step inside the Airflow data pipeline DAG
(crypto_hourly_features), so a data pipeline run refreshes the online store. The
production dbt path is the same DAG family (crypto_lakehouse); usecase-crypto-dbt-run
is a quick manual bypass. On this VPS, skip the heavy triggers and go straight to
verification below.

## Step 2, verify the wiring

One command reports every stage. Each line is one component and its state:
ready means it has a pod serving, wired means the service exists but no pod is
running yet, and missing means it is not there.

    make -C experiments verify

This is the connectivity map. A slice is proven connected when its stages read
ready or wired, even if nothing is actively running on this node.

## Step 3, walk the pipeline

Walk every stage in order, or a contiguous slice. Add SHOW=1 to print the
evidence after each check.

    make -C experiments walk
    make -C experiments walk FROM=ingest TO=feast
    make -C experiments walk FROM=train TO=serve SHOW=1

## Step 4, show the evidence per stage

Each stage target verifies the wiring, then prints what that stage produced.
Run the ones you want to demonstrate.

    make -C experiments ingest    # medallion landing and freshness
    make -C experiments process   # medallion rows plus batch stream parity, KF-11
    make -C experiments feast     # online store returns non-null features, KF-02
    make -C experiments train     # training input rows and last job
    make -C experiments serve     # latest predictions and direction
    make -C experiments drift     # multi-scale PSI and KS, KF-07
    make -C experiments govern    # DataHub lineage walk, KF-08

The DataHub walk needs a token. Get a bearer PAT from the DataHub UI under
Settings, Access Tokens, then export it before running govern or lineage:

    export DATAHUB_TOKEN=...

## Step 5, open the consoles

Print every URL and login, read live from cluster secrets:

    make -C experiments creds

Open one console with a tunnel from your laptop. The full list is in
`REMOTE_ACCESS.md`. Example for Grafana:

    ssh -L 3000:127.0.0.1:3000 USER@NODE 'cd ~/documents/ta && make -C experiments grafana'

## Step 6, run the evaluation scenarios

The functional and nonfunctional checks map to single commands. Print the map:

    make -C experiments eval-map

Load, drift, and resilience:

    make -C experiments load          # k6 latency and throughput, KNF-01/02
    make -C experiments drift-inject  # inject synthetic drift, KF-07
    make -C experiments chaos         # Chaos Mesh fault injection, KNF-03/04
    make -C experiments chaos-clean   # remove the experiments

drift-inject resolves the Kafka SCRAM credentials and cluster CA from cluster
secrets, then runs experiments/drift/inject_drift.py. It shifts the price
distribution on the validated topic so the drift detector fires and the
retrain workflow triggers. It needs the Kafka bootstrap reachable, so run it in
cluster or where the SASL_SSL:9093 endpoint resolves. Tune with SIGMA and DUR.

Run any scenario folder by name; it discovers the entry script:

    make -C experiments eval SCN=parity
    make -C experiments eval SCN=drift

## Notes

The runner never mutates the deployed use case. Triggering a real pipeline run
is a root Makefile step, kept separate on purpose so a demo cannot change the
system under test.

The stage checks read only MergeTree tables in ClickHouse. They never select a
Kafka-engine table, which would consume topic offsets and drop live records.

All endpoints, table names, and entity keys come from
`experiments/config.crypto.env`. Change the config, not the scripts, to point
at another use case.

Nothing here assumes a single node. The checks address workloads by label and
service, so they read the same on a multi-node cluster, where the platform
scales replicas out with HPA and KEDA under load. The one exception is
`make check`, whose load guard reads the local machine only; skip it when you
run from off the cluster.
