# Chaos — fault injection (KNF-04 resilience, KNF-03 autoscale)

Chaos Mesh manifests that inject faults into the deployed use-case and platform,
then let the operator and the autoscaler prove recovery and scaling. Every CR
lives in the `platform-test` namespace; the operator discovers experiments
cluster-wide and acts on the pods named by each `selector`, so the real target
namespace (`use-case-crypto`, `model-lifecycle`, `data-ingestion`) is set in the
selector, not the CR namespace. The use-case-targeted manifests carry `${...}`
placeholders rendered from the config with `envsubst`.

| File | Kind(s) | Validates | Targets |
|------|---------|-----------|---------|
| `pod-chaos.yaml` | PodChaos ×4 | KNF-04 (SK-N-04) | kafka broker, KServe predictor, feature-cache, CNPG primary pod-kill recovery |
| `network-chaos.yaml` | NetworkChaos ×4 | KNF-04 (SK-N-04) | Feast delay, gateway egress loss, ml-bridge→MLflow latency, kafka broker loss |
| `stress-chaos.yaml` | StressChaos ×1 | KNF-03 (SK-N-03) | gateway CPU stress → KEDA cpu trigger scale-out |
| `game-day.yaml` | Workflow ×2 | KNF-04 (SK-N-04) | use-case drill: gateway→cache→mlflow; substrate drill: cnpg→kafka |

The use-case-targeted CRs carry `${...}` placeholders; the platform-substrate
CRs (kafka broker, CNPG primary) use literal selectors — domain-stable infra,
no `envsubst` vars.

## Run

Load the config first; `envsubst` renders the domain selectors:

```sh
set -a; . "${EXPERIMENTS_CONFIG:-experiments/config.crypto.env}"; set +a
kubectl apply -f experiments/namespace.yaml                       # platform-test ns

# KNF-04 — single faults (pick a file), watch recovery:
envsubst < experiments/chaos/pod-chaos.yaml     | kubectl apply -f -
envsubst < experiments/chaos/network-chaos.yaml | kubectl apply -f -

# KNF-04 — full game-day drill (the three use-case faults in series):
envsubst < experiments/chaos/game-day.yaml      | kubectl apply -f -

# KNF-03 — drive the gateway KEDA cpu trigger from inside the pod:
envsubst < experiments/chaos/stress-chaos.yaml  | kubectl apply -f -
```

Swap `apply` for `delete` to end each experiment when the window closes.

## What to measure

* **KNF-04 (SK-N-04)** — recovery objective `RTO < 5 min`, data loss `RPO < 1 min`.
  Watch pod restart + endpoint readiness (`kubectl get pods,endpoints -A -w`) and
  the availability / SLO-burn panels before and after the fault window; serving
  must resume without manual action.
* **KNF-03 (SK-N-03)** — `kubectl get hpa,scaledobject,pods -w`: the gateway scales
  out past its KEDA cpu threshold during the stressor, then returns to the
  1-replica idle baseline after `duration` (single-node mandate). The k6 path
  `experiments/load/hpa-keda-rampup.js` drives the same scaler with external load.

## Notes

* **One-shot, not scheduled.** Experiments run manually on demand against a live
  cluster; nothing here is reconciled by Argo CD or part of `make phase-full`.
* **Target via selector.** mlflow latency selects `model-lifecycle`
  `app.kubernetes.io/name: mlflow` and hits only ml-bridge traffic; the kafka kill
  selects `data-ingestion`. Retargeting an app is a config change
  (`GATEWAY_APP` / `FEATURE_CACHE_APP` / `ML_BRIDGE_APP`), never a manifest edit.
* **Workflow legs omit `duration`.** Inside `game-day.yaml` each leg is bounded by
  its parent `deadline` (`vworkflow.kb.io` rejects `duration` in a Workflow template).
