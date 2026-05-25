#!/usr/bin/env -S uv run python
"""Generate manifests/base/kustomization.yaml based on enabled services.

Reads config/services.yaml and generates the kustomization.yaml
with only enabled services referenced. Preserves use-case-specific resources
(namespace, configmaps, secrets, patches) and only toggles service refs.

Usage:
    uv run python scripts/generate_kustomization.py
    uv run python scripts/generate_kustomization.py --dry-run
"""

import argparse
import sys
from pathlib import Path

# Service name → kustomize resource paths mapping (local paths)
SERVICE_RESOURCES = {
    # Ingestion
    ("ingestion", "rest_collector"): [
        "deployments/rest-collector.yaml",
    ],
    ("ingestion", "websocket_collector"): [
        "deployments/websocket-collector.yaml",
    ],
    ("ingestion", "backfill"): [
        "cronjobs/backfill.yaml",
    ],
    ("ingestion", "supplementary"): [
        "cronjobs/supplementary.yaml",
    ],
    # Quality
    ("quality", "validator"): [
        "deployments/validator.yaml",
    ],
    ("quality", "analyzer"): [
        "deployments/analyzer.yaml",
    ],
    # Processing
    ("processing", "feature_engine"): [
        "deployments/feature-engine.yaml",
    ],
    ("processing", "stream_processor"): [
        "flink/flinkdeployment.yaml",
    ],
    ("processing", "batch"): [
        "deployments/batch-processing.yaml",
        "cronjobs/batch-features.yaml",
    ],
    ("processing", "vector"): [
        "deployments/vector-processing.yaml",
        "cronjobs/vector-embedding.yaml",
    ],
    ("processing", "firehose_sink"): [
        "deployments/firehose-sink.yaml",
    ],
    # Training
    ("training", "trainer"): [
        "cronjobs/training.yaml",
    ],
    ("training", "drift"): [
        "cronjobs/drift-multi-scale.yaml",
    ],
    # Automation
    ("automation", "materialization"): [
        "cronjobs/materialization.yaml",
    ],
    # Serving
    ("serving", "gateway"): [
        "deployments/gateway.yaml",
    ],
    ("serving", "feature_cache"): [
        "deployments/feature-cache.yaml",
    ],
    ("serving", "inference_engine"): [
        "deployments/inference-engine.yaml",
    ],
    # Dashboard
    ("dashboard", "backend"): [
        "deployments/dashboard-backend.yaml",
    ],
    ("dashboard", "frontend"): [
        "deployments/dashboard-frontend.yaml",
    ],
    ("dashboard", "ml_bridge"): [
        "deployments/ml-bridge.yaml",
    ],
}


def parse_services_yaml(path: Path) -> dict:
    """Simple YAML parser for services.yaml (no pyyaml dependency)."""
    services = {}
    current_section = None
    current_service = None

    for line in path.read_text().splitlines():
        stripped = line.rstrip()
        if not stripped or stripped.startswith("#"):
            continue

        # Top-level section (2-space indent)
        if (
            stripped.startswith("  ")
            and not stripped.startswith("    ")
            and ":" in stripped
        ):
            key = stripped.strip().rstrip(":").strip()
            if key and not key.startswith("#"):
                current_section = key
                current_service = None
                continue

        # Service name (4-space indent)
        if (
            stripped.startswith("    ")
            and not stripped.startswith("      ")
            and ":" in stripped
        ):
            key = stripped.strip().rstrip(":").strip()
            if key and not key.startswith("#"):
                current_service = key
                continue

        # Enabled flag (6-space indent)
        if (
            stripped.startswith("      ")
            and "enabled:" in stripped
            and current_section
            and current_service
        ):
            val = stripped.split("enabled:")[-1].strip()
            enabled = val.lower() == "true"
            services[(current_section, current_service)] = enabled

    return services


def generate_kustomization(services: dict, dry_run: bool = False) -> str:
    """Generate kustomization.yaml content."""
    enabled_resources = []
    disabled_resources = []

    for (section, svc_name), resource_paths in SERVICE_RESOURCES.items():
        enabled = services.get((section, svc_name), True)
        for rpath in resource_paths:
            if enabled:
                enabled_resources.append((section, rpath))
            else:
                disabled_resources.append((section, rpath))

    # Group by section
    sections = {}
    for section, path in enabled_resources:
        sections.setdefault(section, []).append(path)

    disabled_sections = {}
    for section, path in disabled_resources:
        disabled_sections.setdefault(section, []).append(path)

    # Section display names
    section_names = {
        "ingestion": "Ingestion",
        "quality": "Quality",
        "processing": "Processing",
        "training": "Training",
        "automation": "Automation",
        "serving": "Serving",
        "dashboard": "Dashboard",
    }

    section_order = [
        "ingestion",
        "quality",
        "processing",
        "training",
        "serving",
        "automation",
        "dashboard",
    ]

    lines = []
    lines.append(
        "# ============================================================================="
    )
    lines.append("# USE-CASE — Kustomize Base (AUTO-GENERATED)")
    lines.append(
        "# ============================================================================="
    )
    lines.append("# Generated by: uv run python scripts/generate_kustomization.py")
    lines.append("# Based on: config/services.yaml enabled flags")
    lines.append("#")
    lines.append("# To regenerate: make generate-kustomization")
    lines.append(
        "# ============================================================================="
    )
    lines.append("")
    lines.append("apiVersion: kustomize.config.k8s.io/v1beta1")
    lines.append("kind: Kustomization")
    lines.append("")
    lines.append("resources:")
    lines.append(
        "  # ==========================================================================="
    )
    lines.append("  # INFRASTRUCTURE + DOMAIN RESOURCES")
    lines.append(
        "  # ==========================================================================="
    )
    lines.append("  - pipeline-infrastructure.yaml")
    lines.append("  - namespace.yaml")
    lines.append("  - configmaps/feast.yaml")
    lines.append("  - external-secrets.yaml  # ADR-008: ExternalSecret CRs (was legacy secrets.yaml)")
    lines.append("  - schema-registration.yaml")
    lines.append("")
    lines.append(
        "  # ==========================================================================="
    )
    lines.append("  # SERVICE TEMPLATES")
    lines.append(
        "  # ==========================================================================="
    )

    for section in section_order:
        lines.append("")
        lines.append(f"  # --- {section_names.get(section, section)} ---")
        for path in sections.get(section, []):
            lines.append(f"  - {path}")
        for path in disabled_sections.get(section, []):
            lines.append(f"  # - {path}  # DISABLED in services.yaml")

    lines.append("")
    lines.append("  # --- RBAC ---")
    lines.append("  - rbac/roles.yaml")
    lines.append("  - rbac/bindings.yaml")
    lines.append("")
    lines.append("  # --- Autoscaling ---")
    lines.append("  # - hpa/autoscaling.yaml")

    lines.append("")
    lines.append(
        "# ============================================================================="
    )
    lines.append("# DOMAIN CONFIG PATCHES")
    lines.append(
        "# ============================================================================="
    )
    lines.append("patches:")
    lines.append("  - path: configmaps/identity.yaml")
    lines.append("  - path: configmaps/topics.yaml")
    lines.append("  - path: configmaps/sources.yaml")
    lines.append("  - path: configmaps/features.yaml")
    lines.append("  - path: configmaps/models.yaml")
    lines.append("  - path: configmaps/quality.yaml")
    lines.append("")
    lines.append("  # --- Service patches ---")
    lines.append("  - path: patches/rest-collector.yaml")
    lines.append("  - path: patches/feature-engine.yaml")
    lines.append("  - path: patches/supplementary-source.yaml")
    lines.append("  - path: patches/supplementary-data.yaml")
    lines.append("  - path: patches/backfill.yaml")
    lines.append("")
    lines.append(
        "# ============================================================================="
    )
    lines.append("# COMMON LABELS")
    lines.append(
        "# ============================================================================="
    )
    lines.append("labels:")
    lines.append("  - pairs:")
    lines.append("      app.kubernetes.io/component: ml-pipeline")
    lines.append("      app.kubernetes.io/part-of: mlops-platform")
    lines.append("      app.kubernetes.io/managed-by: kustomize")
    lines.append("    includeSelectors: true")
    lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Generate kustomization.yaml from services config"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Print output without writing"
    )
    args = parser.parse_args()

    script_dir = Path(__file__).parent
    project_dir = script_dir.parent
    svc_config = project_dir / "config" / "services.yaml"
    output_file = project_dir / "manifests" / "base" / "kustomization.yaml"

    if not svc_config.exists():
        print(f"Error: {svc_config} not found", file=sys.stderr)
        sys.exit(1)

    services = parse_services_yaml(svc_config)
    content = generate_kustomization(services, dry_run=args.dry_run)

    if args.dry_run:
        print(content)
        enabled = sum(1 for v in services.values() if v)
        disabled = sum(1 for v in services.values() if not v)
        print(f"\n# Services: {enabled} enabled, {disabled} disabled", file=sys.stderr)
    else:
        output_file.write_text(content)
        enabled = sum(1 for v in services.values() if v)
        disabled = sum(1 for v in services.values() if not v)
        print(
            f"Generated {output_file} ({enabled} enabled, {disabled} disabled services)"
        )


if __name__ == "__main__":
    main()
