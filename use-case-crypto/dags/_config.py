"""Domain-knob layer — single source of truth for all crypto Airflow DAGs.

Every USE_CASE-derived name (namespace, image prefix, ConfigMap, Secret,
ENV_FROM_SOURCES) and the shared k8s_pod factory live here.

Clone workflow: copy a new use-case directory, set ``USE_CASE=<name>`` in
Airflow Variables (or change the ``default_var`` below), and all DAGs that
import from this module stay body-identical — no per-file edits required.

Setup (Airflow Variables):
    airflow variables set USE_CASE                    crypto
    airflow variables set USE_CASE_NAMESPACE          use-case-crypto
    airflow variables set USE_CASE_REGISTRY           localhost:5000
    airflow variables set USE_CASE_IMAGE_TAG          v1.0.0
    # optional overrides (defaults derive from USE_CASE):
    airflow variables set USE_CASE_PIPELINE_CONFIGMAP crypto-pipeline-config
    airflow variables set USE_CASE_PIPELINE_SECRET    pipeline-secrets
    airflow variables set USE_CASE_IMAGE_PREFIX       crypto

Naming asymmetry (deliberate, see use-case-crypto name-reference.yaml):
  - ConfigMap is produced by kustomize configMapGenerator, so ``namePrefix:
    crypto-`` rewrites it → ``crypto-pipeline-config`` (prefixed).
  - Secret is an ExternalSecret ``spec.target.name`` — a field value opaque to
    kustomize namePrefix — so the rendered Secret keeps its literal,
    unprefixed name ``pipeline-secrets``. All 37 in-cluster refs use it.
"""

from __future__ import annotations

from airflow.models import Variable
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator
from kubernetes.client import models as k8s

# ─────────────────────────────────────────────────────────────
# Configuration — read from Airflow Variables (declarative, not hardcoded).
#
# Single knob `USE_CASE` derives every domain-coupled name (namespace,
# image prefix, ConfigMap, Secret). Cloning this file to a new use-case
# means: rename the file + dag_id strings and set `USE_CASE=<name>` in
# Airflow Variables — the rest of the body stays identical.
# ─────────────────────────────────────────────────────────────
USE_CASE = Variable.get("USE_CASE", default_var="crypto")
NAMESPACE = Variable.get(
    "USE_CASE_NAMESPACE", default_var=f"use-case-{USE_CASE}"
)
REGISTRY = Variable.get("USE_CASE_REGISTRY", default_var="localhost:5000")
IMAGE_TAG = Variable.get("USE_CASE_IMAGE_TAG", default_var="latest")
IMAGE_PREFIX = Variable.get("USE_CASE_IMAGE_PREFIX", default_var=USE_CASE)
PIPELINE_CONFIGMAP = Variable.get(
    "USE_CASE_PIPELINE_CONFIGMAP", default_var=f"{USE_CASE}-pipeline-config"
)
PIPELINE_SECRET = Variable.get(
    # Unprefixed by design — the Secret is rendered from an ExternalSecret
    # `target.name` (opaque to kustomize namePrefix), unlike the ConfigMap.
    # Fix #489: was incorrectly `f"{USE_CASE}-pipeline-secrets"` (prefixed)
    # which caused all KPO child-pods to fail with MountSecretError because
    # the rendered Secret in the namespace is the literal `pipeline-secrets`.
    "USE_CASE_PIPELINE_SECRET", default_var="pipeline-secrets"
)
FEAST_REPO_CONFIGMAP = Variable.get(
    # Feast feature-repo ConfigMap (feature_store.yaml.tmpl + definitions.py),
    # mounted read-only into the `feast_materialize` task so the materialization
    # image renders feature_store.yaml at pod start. It is a PLAIN ConfigMap
    # resource (not a configMapGenerator), so kustomize `namePrefix: crypto-`
    # rewrites it to `crypto-feast-feature-repo` with NO hash suffix — this
    # static default matches the rendered name. Derives from USE_CASE, so a
    # cloned use-case needs no edit here.
    "USE_CASE_FEAST_REPO_CONFIGMAP", default_var=f"{USE_CASE}-feast-feature-repo"
)

ENV_FROM_SOURCES = [
    k8s.V1EnvFromSource(
        config_map_ref=k8s.V1ConfigMapEnvSource(name=PIPELINE_CONFIGMAP),
    ),
    k8s.V1EnvFromSource(
        secret_ref=k8s.V1SecretEnvSource(name=PIPELINE_SECRET),
    ),
]


def _image(name: str) -> str:
    """Build full image reference from service name."""
    return f"{REGISTRY}/{IMAGE_PREFIX}-{name}:{IMAGE_TAG}"


def k8s_pod(
    task_id: str,
    image: str,
    cmds: list[str],
    args: list[str] | None = None,
    cpu_req: str = "100m",
    mem_req: str = "256Mi",
    cpu_lim: str = "500m",
    mem_lim: str = "1Gi",
    **kwargs,
) -> KubernetesPodOperator:
    """Factory for KubernetesPodOperator with standard config."""
    return KubernetesPodOperator(
        task_id=task_id,
        name=f"airflow-{task_id}",
        namespace=NAMESPACE,
        image=image,
        cmds=cmds,
        arguments=args or [],
        env_from=ENV_FROM_SOURCES,
        # `Always` (not IfNotPresent) against the in-cluster registry
        # (localhost:5000). With `:latest` + IfNotPresent, k8s pins whatever
        # digest the node cached at first pull FOREVER — a rebuilt+pushed image is
        # never re-pulled, so every KPO child (batch_features, drift_check,
        # scoring, sentiment, feast_materialize, dbt_run) silently runs stale
        # code. That masked the missing `clickhouse_password` field in
        # config.py → ClickHouse Code 194 auth failures on batch-features. The
        # registry is in-cluster, so re-pulling each run is cheap and
        # air-gap-safe (mirrors #301/#459/#291).
        image_pull_policy="Always",
        # Keep FAILED task pods for post-mortem (`kubectl logs`/`describe`);
        # delete only successful ones to stay tidy on the single node. Mirrors
        # the platform Airflow KubernetesExecutor policy
        # (AIRFLOW__KUBERNETES_EXECUTOR__DELETE_WORKER_PODS_ON_FAILURE=False):
        # a child pod that errors must be inspectable, or the failure is opaque.
        on_finish_action="delete_succeeded_pod",
        get_logs=True,
        # 600s (not 300s): on the single IO-constrained node, a cold
        # `Always`-pull of a freshly-rebuilt child image (256MB, all-new
        # layers) measured 4m33s — past a 300s startup deadline — so KPO
        # marked the task up_for_retry even though the pod itself ran to
        # exit 0. Steady-state Always-pulls only re-verify cached layers
        # (seconds), so the wider deadline only adds headroom for the
        # post-rebuild cold pull; a healthy pod still starts fast. Mirrors
        # the disk-distress timeout bumps (#203 kserve rollout 300→900s,
        # #285 upgrade-job 1800→3600s).
        startup_timeout_seconds=600,
        container_resources=k8s.V1ResourceRequirements(
            requests={"cpu": cpu_req, "memory": mem_req},
            limits={"cpu": cpu_lim, "memory": mem_lim},
        ),
        **kwargs,
    )
