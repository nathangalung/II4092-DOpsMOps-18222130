# Remote UI access for the live demo

The platform runs on the VPS. Your browser runs on your laptop. A UI
port-forward binds to the VPS localhost, so you cannot reach it from the laptop
directly. Each UI needs one SSH tunnel from the laptop.

Run every command in this file on your laptop, not on the VPS. Each one opens a
tunnel and starts the port-forward on the VPS in a single step. Keep the
terminal open while you use the UI, and press Ctrl-C to stop it. Use one
terminal per UI.

VPS target used below: client_26_1@167.205.88.202. Replace it if it changes.

## How the one-liner works

The command has two parts. The `-L LOCAL:127.0.0.1:LOCAL` part forwards a port
from your laptop to the VPS localhost. The quoted part runs the matching make
target on the VPS, which port-forwards that UI to the VPS localhost on the same
port. The make target resolves the real Kubernetes Service port for you, so you
never guess it.

## First get the logins

Run this once on the VPS (values print in your VPS terminal):

    make -C experiments creds

## One command per UI, run on the laptop

Grafana, dashboards and metrics, open http://localhost:3000
    ssh -L 3000:127.0.0.1:3000 client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments grafana'

DataHub, catalog and lineage, open http://localhost:9002
    ssh -L 9002:127.0.0.1:9002 client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments datahub'

Superset, business dashboards, open http://localhost:8088
    ssh -L 8088:127.0.0.1:8088 client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments superset'

Argo CD, GitOps delivery, open http://localhost:8081
    ssh -L 8081:127.0.0.1:8081 client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments argocd'

MinIO console, object storage, open http://localhost:9001
    ssh -L 9001:127.0.0.1:9001 client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments minio'

MLflow, experiments and model registry, open http://localhost:5000
    ssh -L 5000:127.0.0.1:5000 client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments mlflow'

Kafka UI, topics and consumer lag, open http://localhost:8080
    ssh -L 8080:127.0.0.1:8080 client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments kafka-ui'

Prometheus, raw metrics and targets, open http://localhost:9090
    ssh -L 9090:127.0.0.1:9090 client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments prometheus'

Trino, federated SQL, open http://localhost:8082
    ssh -L 8082:127.0.0.1:8082 client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments trino'

Airflow, workflow orchestration, open http://localhost:8085
    ssh -L 8085:127.0.0.1:8085 client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments airflow'

Qdrant, vector store dashboard, open http://localhost:6333/dashboard
    ssh -L 6333:127.0.0.1:6333 client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments qdrant'

## The data scenarios need no browser

These print results straight to the terminal. Run them over plain SSH:

    ssh client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments core'
    ssh client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments data'
    ssh client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments drift'
    ssh client_26_1@167.205.88.202 'cd ~/documents/ta && make -C experiments predict'

## Direct kubectl form, without the make target

If you prefer the explicit form, the four UIs whose Service port equals the
local port work exactly like your DataHub example:

    ssh -L 9002:127.0.0.1:9002 client_26_1@167.205.88.202 'kubectl port-forward -n data-governance svc/datahub-frontend 9002:9002'
    ssh -L 9090:127.0.0.1:9090 client_26_1@167.205.88.202 'kubectl port-forward -n observability svc/kube-prometheus-stack-prometheus 9090:9090'
    ssh -L 6333:127.0.0.1:6333 client_26_1@167.205.88.202 'kubectl port-forward -n storage svc/qdrant 6333:6333'

Grafana is the one exception, its Service port is 80 not 3000, so the explicit
form maps local 3000 to Service 80:

    ssh -L 3000:127.0.0.1:3000 client_26_1@167.205.88.202 'kubectl port-forward -n observability svc/grafana 3000:80'

For the other UIs the Service port is not the same as the local port, so prefer
the make target form above, which reads the real port for you.

## If a port is already busy on the VPS

A leftover port-forward from a killed session can hold a port. Clear it on the
VPS, then rerun:

    ssh client_26_1@167.205.88.202 'pkill -f "port-forward"'

## Alternative, expose on the VPS public IP

If you cannot use tunnels, bind the forward to all interfaces and open the VPS
IP directly. Only do this on a trusted network, it exposes the UI publicly.

    make -C experiments grafana ADDR=0.0.0.0
    then open http://167.205.88.202:3000
