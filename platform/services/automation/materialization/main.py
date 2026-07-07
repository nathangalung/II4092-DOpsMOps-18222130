"""
Feast feature materialization job.

Renders the feature repo from a template (when FEAST_TEMPLATE_DIR is set),
applies feature definitions, then materializes from the offline store
(ClickHouse) to the online store (Valkey - Redis-RESP-compatible).

Domain-agnostic: the optional render step lets any use-case ship its feature
repo as a ConfigMap of `feature_store.yaml.tmpl` + `definitions.py` carrying
`${VAR}` placeholders (creds delivered via envFrom). When FEAST_TEMPLATE_DIR
is unset - e.g. the platform stub cronjob that mounts a ready-rendered
`feature_store.yaml` - the render is a no-op and behaviour is unchanged.
"""

from __future__ import annotations

import logging
import os
import re
import shutil
import subprocess
from datetime import UTC, datetime, timedelta
from pathlib import Path

from feast import FeatureStore

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _render_repo(repo_path: str) -> None:
    """Render `feature_store.yaml` from a `${VAR}` template, when configured.

    Reads ``$FEAST_TEMPLATE_DIR/feature_store.yaml.tmpl``, substitutes every
    ``${VAR}`` from the pod environment, copies ``definitions.py`` alongside it,
    and writes both into ``repo_path`` (a writable emptyDir).  A referenced var
    that is missing raises immediately - better to fail loud than ship a
    half-rendered store that silently points Feast at the wrong backend.

    No-op when FEAST_TEMPLATE_DIR is unset.
    """
    template_dir = os.getenv("FEAST_TEMPLATE_DIR")
    if not template_dir:
        return

    def _sub(match: re.Match[str]) -> str:
        key = match.group(1)
        try:
            return os.environ[key]
        except KeyError as exc:
            raise KeyError(
                f"feature_store.yaml.tmpl references ${{{key}}} but it is unset in "
                "the pod environment (check pipeline-config / pipeline-secrets envFrom)"
            ) from exc

    tmpl = Path(template_dir, "feature_store.yaml.tmpl").read_text()
    # Substitute per line, skipping full-line `#` comments. A template note like
    # `# creds arrive as ${VAR}` documents the mechanism and must NOT be treated
    # as a real placeholder (it would trip the missing-var guard below). Real
    # `${VAR}` placeholders live on config lines and still fail loud when unset.
    rendered = "".join(
        line if line.lstrip().startswith("#") else re.sub(r"\$\{(\w+)\}", _sub, line)
        for line in tmpl.splitlines(keepends=True)
    )

    repo = Path(repo_path)
    repo.mkdir(parents=True, exist_ok=True)
    (repo / "feature_store.yaml").write_text(rendered)
    shutil.copy(Path(template_dir, "definitions.py"), repo / "definitions.py")
    logger.info("Rendered feature repo into %s from %s", repo_path, template_dir)


def main() -> None:
    """Render (optional), apply feature definitions, and run materialization."""
    repo_path = os.getenv("FEAST_REPO_PATH", "/app/feature_repo")

    # Step 0: Render the feature repo from its template (no-op without a template)
    _render_repo(repo_path)

    # Step 1: Apply feature definitions to registry
    logger.info(f"Applying feature definitions from {repo_path}")
    result = subprocess.run(
        ["feast", "apply"],
        cwd=repo_path,
        capture_output=True,
        text=True,
    )
    # Fail loud: a swallowed `feast apply` error means a stale/empty registry,
    # which then aborts `materialize` with an opaque error (or silently
    # materializes nothing). Surface the real cause to the orchestrator.
    if result.returncode != 0:
        raise RuntimeError(
            f"feast apply failed (exit {result.returncode}): {result.stderr}"
        )
    logger.info(f"feast apply: {result.stdout.strip()}")

    # Step 2: Materialize features (offline to online)
    store = FeatureStore(repo_path=repo_path)

    end_date = datetime.now(tz=UTC)
    hours = int(os.getenv("MATERIALIZE_HOURS", "24"))
    start_date = end_date - timedelta(hours=hours)

    logger.info(f"Materializing features from {start_date} to {end_date}")
    store.materialize(start_date=start_date, end_date=end_date)
    logger.info("Materialization complete")


if __name__ == "__main__":
    main()
