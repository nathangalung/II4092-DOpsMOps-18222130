# Load scenarios — k6 client-side latency & throughput (KNF-01/02/03, KF-04)

Client-side performance probes run with [k6](https://k6.io). Each reads its inputs
from `config.crypto.env` as `__ENV.*`, so load the config first:

```bash
set -a; . "${EXPERIMENTS_CONFIG:-experiments/config.crypto.env}"; set +a
```

These measure **latency/throughput only** — value correctness is asserted by the
sibling checks (`feast/online-serving-check.py` for non-null online features,
`parity/parity-check.sh` for batch↔stream parity). A k6 `200` with all-null values
would pass here, which is why the value legs live elsewhere.

| Script | Criterion | Measures | k6 thresholds |
|--------|-----------|----------|---------------|
| `feast-online-latency.js` | KNF-01 / SK-N-01 | Feast online-serving latency (Valkey path) at `QPS` (def 5000) constant arrival for `DURATION` (def 15m) | `p50<5`, `p95<8`, `p99<10` ms; `http_req_failed<0.001` |
| `feast-throughput.js` | KNF-02 / SK-N-02 | Feast online-serving throughput, ramping 5k→12k arrival | `http_reqs rate>10000`; `http_req_failed<0.001` |
| `hpa-keda-rampup.js` | KNF-03 / SK-N-03 | KServe v2 predict (`PREDICT_URL`) under a 100→1000 ramp, to drive HPA/KEDA scale-out | `http_req_failed<0.01` (watch `kubectl get hpa,scaledobject,pods -w` alongside) |
| `vector-search-latency.js` | KF-04 / SK-F-04, KNF-01 | Qdrant vector-search latency on `COLLECTION` (def `crypto_sentiment`) at `RPS` (def 100) for `DURATION` (def 5m) | `p50<5`, `p95<8`, `p99<10` ms; `http_req_failed<0.001` |

Run one with, e.g.:

```bash
k6 run experiments/load/feast-online-latency.js
```

## Measurement targets — the metric-precision gradient

The same criterion carries up to three different numeric targets across the
documents; do not conflate them (thesis Bab 6 §6.2 and the requirement tables):

1. **Formal requirement (thesis `kebutuhan_nonfungsional.tex`)** — loose:
   *"latensi p99 sub-detik"* (< 1000 ms) on feature serving and vector search.
2. **Design-chapter target (thesis Bab 4)** — tighter point targets: **< 10 ms**
   p99 for the Valkey online store; **< 20 ms** p99 for Qdrant top-10 search on
   collections up to ten million vectors.
3. **Harness operational thresholds (the table above)** — the strictest, and the
   harness's own working SLOs, NOT thesis quotes. They refine layer 2: the Feast
   `p99<10` matches the Bab-4 Valkey target exactly; the vector `p99<10` is
   intentionally stricter than the Bab-4 `<20` ms vector ceiling (a vector p99
   between 10–20 ms therefore fails this script yet still meets the thesis design
   target — relax `vector-search-latency.js`'s `p99` to `20` if you want the
   script's pass bar to equal the thesis ceiling rather than exceed it).

All three layers agree the formal pass bar (layer 1) is **sub-second**, which every
steady-state sample comfortably meets.

## Caveats (thesis status: KF-04, KNF-01/02/03 are *Terinstrumentasi*)

- **KF-04 recall is NOT measured here.** `vector-search-latency.js` issues a
  **random** query vector and asserts latency only. Top-10 recall (> 0.95 against
  offline ground truth) requires a *populated* collection and is deferred — the
  thesis records KF-04 as *Terinstrumentasi* with "recall belum diuji karena
  koleksi kosong". The collection is `crypto_sentiment`, written by the
  `vector-embedding` CronJob (now wired via `VECTOR_COLLECTION`); recall can be
  measured once embeddings land. NOTE: the BERT/Qdrant embedding path is currently
  a standalone capability — `ml-bridge` inference does not consume Qdrant — so the
  vectors are not on the live serving path.
- **p99 teardown artifact.** Under `constant-arrival-rate`, the ramp-down inflates
  the p99 tail: the thesis observed a one-off **p99 = 157 ms** and explicitly
  dismissed it as a load-teardown artifact, not steady-state (Bab 6 §6.2 item 4;
  steady p50/p95 were 4.25 / 5.02 ms). Read p50/p95 as the steady-state signal, or
  exclude the teardown window, before judging a p99 against the targets above.
- **Single-node scope (thesis B-2/B-5).** Throughput (KNF-02) and near-linear
  horizontal scaling (KNF-03) targets are evaluated on one k3s node, so they
  exercise multi-replica autoscaling on a single node — full multi-node peak
  characterization is out of the thesis evaluation scope (Bab 7 future work).
