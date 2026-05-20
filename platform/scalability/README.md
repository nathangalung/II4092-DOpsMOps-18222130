# Scalability Templates

K8s scalability primitives for the platform. Each component should pick the right tool for its scaling objective.

## Tool selection

| Workload pattern | Tool | Min | Why |
|---|---|---|---|
| Stateless web/API, CPU-bound | HPA | 1+ | Standard CPU/mem-based scaling |
| Stateless event-driven (Kafka, queue) | KEDA ScaledObject | 0 | Scale-to-zero on idle |
| Stateful DB | VPA (Off mode) | n/a | Advisory only — rightsize requests |
| Periodic batch | KEDA cron trigger | 0 | Run only during window |
| Multi-metric (CPU + custom) | HPA + Prometheus adapter | 1+ | Custom metrics via KEDA's metrics-api |
| Operators / control planes | Static replicas | 1-3 | Don't autoscale leader-elected pods |

## Templates

- `hpa-template.yaml` — HPA v2 with CPU + memory + tuned behavior windows
- `vpa-template.yaml` — VPA recommender + Auto/Initial/Off modes
- `keda-scaledobject-template.yaml` — Generic KEDA ScaledObject (any trigger)

## Apply via Makefile

```sh
make install-hpa COMPONENT=feast NS=model-lifecycle MIN=1 MAX=5 \
    CPU_TARGET=70 MEM_TARGET=80 KIND=Deployment

make install-vpa COMPONENT=mlflow NS=model-lifecycle KIND=Deployment \
    MODE=Off CPU_MIN=100m CPU_MAX=2 MEM_MIN=128Mi MEM_MAX=4Gi

make install-keda-scaledobject COMPONENT=consumer NS=data-processing \
    KIND=Deployment MIN=0 MAX=10 TRIGGER=kafka \
    TRIGGER_META='bootstrapServers: ... topic: ... lagThreshold: "100"'
```

## Per-component recommendations

| Component | NS | Tool | Notes |
|---|---|---|---|
| feast | model-lifecycle | HPA + VPA(Off) | Online serving = HPA, offline materialize = VPA recommendations |
| mlflow | model-lifecycle | HPA | CPU/mem only |
| kserve InferenceService | model-serving | KServe autoscaling | Built-in (Knative or KEDA) |
| flink | data-processing | KEDA Kafka lag | Scale workers on consumer lag |
| spark | data-processing | n/a | Spark dynamic allocation per job |
| airflow scheduler | data-processing | Static | Leader election; static 1-2 replicas |
| airflow worker | data-processing | KEDA Postgres queue | Scale by queued task count |
| kafka brokers | data-ingestion | n/a | Use KafkaNodePool replicas |
| datahub-gms | data-governance | HPA | Standard web app |
| trino coordinator | data-processing | Static | Coordinator is leader |
| trino worker | data-processing | HPA | CPU-bound |
| superset | data-processing | HPA | Stateless web app |
| prometheus | observability | VPA(Off) | Single instance, advisory rightsize |
| grafana | observability | HPA | Stateless web |
| loki write | observability | HPA | Ingester throughput |
| kafka-connect | data-ingestion | KEDA Kafka lag | Source/sink connector throughput |
