#!/usr/bin/env -S uv run --no-project --quiet python
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Set replicas=0 / replicaCount=0 baseline in all platform/components YAML.

Replaces top-level `replicas: <N>` and `replicaCount: <N>` with `: 0`.
Preserves minReplicas/maxReplicas (HPA bounds) and .tmpl placeholders.

Usage:
    uv run python scripts/set-replicas-zero.py            # default platform/components
    uv run python scripts/set-replicas-zero.py <dir>      # custom target
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_TARGET = REPO_ROOT / "platform" / "components"

PATTERN = re.compile(
    r"^(?P<i>[ \t]*)(?P<k>replicas|replicaCount):[ \t]+(?P<v>\d+)(?P<rest>[ \t]*(#.*)?)$"
)
SKIP_EXT = {".tmpl", ".j2", ".png", ".jpg", ".gz", ".tgz"}
SKIP_DIRS = {".git", "__pycache__", "node_modules", ".venv"}


def main(argv: list[str]) -> int:
    target = Path(argv[1]) if len(argv) > 1 else DEFAULT_TARGET
    if not target.is_dir():
        print(f"ERROR: not a directory: {target}", file=sys.stderr)
        return 2

    print(f"==> Setting replicas=0 baseline in: {target}")
    changed = 0
    for root, dirs, files in os.walk(target):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if any(f.endswith(ext) for ext in SKIP_EXT):
                continue
            if not (f.endswith(".yaml") or f.endswith(".yml")):
                continue
            path = Path(root) / f
            lines = path.read_text().splitlines(keepends=True)
            new: list[str] = []
            file_changed = False
            for line in lines:
                m = PATTERN.match(line.rstrip("\n"))
                if m and m.group("v") != "0":
                    new.append(
                        f"{m.group('i')}{m.group('k')}: 0{m.group('rest')}\n"
                    )
                    file_changed = True
                else:
                    new.append(line)
            if file_changed:
                path.write_text("".join(new))
                changed += 1
                print(f"  patched: {path.relative_to(target)}")
    print(f"==> {changed} files patched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
