# Online feature-serving check — SK-F-02 (KF-02; runtime evidence for #492)

`online-serving-check.py` asserts that the Feast **online** store actually serves
non-null features — the value assertion the latency benchmark
(`experiments/load/feast-online-latency.js`) deliberately omits (it only checks
HTTP 200, which a 200-with-all-nulls would pass). It POSTs one request per entity
to the feature server's `/get-online-features` REST endpoint — the same contract
the k6 script and the platform `ml-bridge` reader use — and fails if any entity
comes back empty (a batch→materialize→online-read gap, i.e. #491 not effective).

Self-contained via PEP 723 inline metadata (`httpx`) — run with `uv run`, no venv:

```bash
set -a; . experiments/config.crypto.env; set +a
kubectl -n model-lifecycle port-forward svc/feast 6566:6566 &     # reach the in-cluster server
FEAST_URL=http://localhost:6566 uv run experiments/feast/online-serving-check.py
```

| Env var | Purpose | Default |
|---------|---------|---------|
| `FEAST_URL` | feature-server base URL (`host:6566`) | `http://feast.model-lifecycle.svc:6566` |
| `FEATURE_SERVICE` | Feast feature service to request | `crypto_inference_features` |
| `ENTITY_KEY` | entity join key | `symbol` |
| `SYMBOLS` | entity instances to sample (comma-sep) | `BTC-USD,ETH-USD,SOL-USD` |

Exit `0` = every entity served ≥1 non-null feature (the evidence KF-02 / #492
needs — the user running this against the live cluster is what closes #492); `1` =
a materialization gap (some entity empty); `2` = server error / unrecognised shape.
The offline-landed counterpart is `experiments/etl/data-landed-check.sh`.

## Value parity — the full SK-F-02 acceptance

The thesis SK-F-02 acceptance (`uji_penerimaan.tex`) is stronger than non-null:
*online (Valkey) and offline (ClickHouse) values must be **consistent** for the
same entity and reference time*. That value-equality leg uses the Feast **SDK**
(the thesis-named tooling) rather than this REST check, because Feast itself maps
feature refs to the offline columns — no hand-mapping of gold-mart columns. Run it
against the use-case feature repo (the same `get_online_features` call shape the
platform `ml-bridge` reader uses), comparing against `get_historical_features`.

The Feast repo is NOT a checked-in directory — it lives as the ConfigMap
`crypto-feast-feature-repo` (source: `use-case-crypto/manifests/base/configmaps/feast.yaml`)
and is only rendered onto disk inside the materialize / ml-bridge pods. Materialize
it locally from that ConfigMap, then point the SDK at it (port-forward the online
Valkey + offline ClickHouse stores its `feature_store.yaml` references first):

```bash
mkdir -p /tmp/feast-repo
# definitions.py is a plain ConfigMap key. The repo config is stored as
# `feature_store.yaml.tmpl` with ${CLICKHOUSE_USER}/${CLICKHOUSE_PASSWORD}
# placeholders (the pod renders it at init via envsubst from pipeline-secrets),
# so fetch it and envsubst it into a real feature_store.yaml:
kubectl -n use-case-crypto get configmap crypto-feast-feature-repo \
  -o 'jsonpath={.data.definitions\.py}' > /tmp/feast-repo/definitions.py
export CLICKHOUSE_USER CLICKHOUSE_PASSWORD   # from `kubectl -n use-case-crypto get secret pipeline-secrets -o jsonpath=...`
kubectl -n use-case-crypto get configmap crypto-feast-feature-repo \
  -o 'jsonpath={.data.feature_store\.yaml\.tmpl}' | envsubst > /tmp/feast-repo/feature_store.yaml
FEAST_REPO_PATH=/tmp/feast-repo \
uv run --with feast - <<'PY'
import os, pandas as pd
from datetime import datetime, timezone
from feast import FeatureStore
store = FeatureStore(repo_path=os.environ["FEAST_REPO_PATH"])
fs, ent = os.getenv("FEATURE_SERVICE","crypto_inference_features"), os.getenv("ENTITY_KEY","symbol")
sym = os.getenv("SYMBOLS","BTC-USD").split(",")[0]
online = store.get_online_features(features=store.get_feature_service(fs),
                                   entity_rows=[{ent: sym}]).to_dict()
edf = pd.DataFrame({ent:[sym], "event_timestamp":[datetime.now(timezone.utc)]})
offline = store.get_historical_features(entity_df=edf,
                                        features=store.get_feature_service(fs)).to_df()
print("online :", {k:v[0] for k,v in online.items() if k!=ent})
print("offline:", offline.drop(columns=[ent,"event_timestamp"]).iloc[0].to_dict())
PY
```

The two rows should match (within float tolerance) per `EVENT_TIME_COLUMN`. This is
the leg `evaluasi_target.tex` marks "Menunggu pengukuran beban" — kept as a manual
SDK procedure (not a committed script) because it needs the feature repo + registry
that only the in-cluster reader carries.
