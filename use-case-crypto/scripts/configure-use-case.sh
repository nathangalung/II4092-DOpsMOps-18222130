#!/usr/bin/env bash
# =============================================================================
# use-case template configure — single source-of-truth propagation
# =============================================================================
# Reads the desired use-case prefix from `config/project.yaml` (the field
# `project.namespace`, which has the canonical form `use-case-<NAME>`), detects
# the current prefix from `manifests/overlays/local/kustomization.yaml`
# (`namePrefix: <NAME>-`), and propagates NEW everywhere via sed + file rename.
#
# Effect: edit one line in config/project.yaml, run `make usecase-configure`,
# the whole use-case directory rebrands consistently. The directory itself is
# treated as a template that can be cloned and re-pointed at any domain.
#
# Idempotent: re-running with no config change is a no-op.
#
# Scope of rewrite (content):
#   manifests/, argocd/, cross-namespace/  (k8s YAML)
#   config/                                (project + service config)
#   dags/, pipelines/                      (Airflow / KFP Python)
#   dbt/                                   (dbt models, project, profiles)
#   database/                              (SQL schemas, ClickHouse init)
#   services/                              (Rust/Go/Python/TS app code, narrow)
#   scripts/, docs/                        (shell scripts, markdown)
#
# Scope of rename (filenames):
#   Any path component containing the OLD prefix is renamed to NEW.
#
# Out of scope (intentional, not rewritten):
#   - Vendor names: `cryptopanic`, `coinbase`, `coingecko` (third-party domains)
#   - Java package `com.usecase.crypto.functions.*` (renaming a Java package
#     requires moving .java files and updating imports; do that in a follow-up
#     refactor scoped to services/processing/flink-job/src/).
#   - `.git/` (history is never rewritten)
#
# Usage:
#   cd use-case-crypto
#   $EDITOR config/project.yaml   # change namespace: use-case-<new>
#   make -C ../ usecase-configure
# =============================================================================

set -euo pipefail

# Resolve to the use-case directory regardless of where the script is invoked.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USECASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$USECASE_DIR"

# ---------------------------------------------------------------------------
# Detect NEW from config/project.yaml — the canonical source of truth
# ---------------------------------------------------------------------------
# `project.namespace` always has form `use-case-<NAME>` (enforced by readme +
# CLAUDE.md domain-isolation rule); strip the prefix to derive the bare name.
CONFIG="$USECASE_DIR/config/project.yaml"
if [[ ! -f "$CONFIG" ]]; then
    printf "${RED}ERROR: %s not found${NC}\n" "$CONFIG" >&2
    exit 1
fi

NEW="$(awk '/^[[:space:]]*namespace:/ {
    gsub(/"/, "", $2); sub(/use-case-/, "", $2); print $2; exit
}' "$CONFIG")"

if [[ -z "${NEW:-}" ]]; then
    printf "${RED}ERROR: could not parse project.namespace from %s${NC}\n" "$CONFIG" >&2
    printf "  Expected line: 'namespace: \"use-case-<name>\"' under project:\n" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Detect OLD from manifests/overlays/local/kustomization.yaml — the place
# previous configure runs imprint the prefix
# ---------------------------------------------------------------------------
OVERLAY="$USECASE_DIR/manifests/overlays/local/kustomization.yaml"
if [[ ! -f "$OVERLAY" ]]; then
    printf "${RED}ERROR: %s not found${NC}\n" "$OVERLAY" >&2
    exit 1
fi
OLD="$(awk '/^namePrefix:/ { gsub(/[ "-]/, "", $2); print $2; exit }' "$OVERLAY")"

if [[ -z "${OLD:-}" ]]; then
    printf "${RED}ERROR: could not parse namePrefix from %s${NC}\n" "$OVERLAY" >&2
    exit 1
fi

if [[ "$OLD" == "$NEW" ]]; then
    printf "${GREEN}Already configured: namePrefix='%s-' matches config/project.yaml${NC}\n" "$NEW"
    exit 0
fi

printf "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
printf "${BLUE}  Reconfiguring use case: ${YELLOW}%s${BLUE} → ${GREEN}%s${NC}\n" "$OLD" "$NEW"
printf "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

# ---------------------------------------------------------------------------
# Vendor names to preserve — substrings that contain OLD but are not the
# use-case identity (e.g. third-party APIs that happen to embed "crypto").
# These get masked before rewrite and unmasked after.
# ---------------------------------------------------------------------------
declare -a VENDOR_KEEP=(
    "cryptopanic"   # third-party news/sentiment API
    "Cryptopanic"
    "CRYPTOPANIC"
)

# Single sentinel character chosen because it never legitimately appears in
# any code/YAML/config/markdown across the repo (verified via `grep -rl $'\x01'`).
SENTINEL=$'\x01'

# ---------------------------------------------------------------------------
# Files to rewrite — explicit extension allowlist keeps `find` deterministic
# and avoids touching binaries.
# ---------------------------------------------------------------------------
mapfile -d '' FILES < <(
    find . \
        -path ./.git -prune -o \
        -path ./.venv -prune -o \
        -path ./node_modules -prune -o \
        -path "*/target" -prune -o \
        -path "*/out" -prune -o \
        -path "*/__pycache__" -prune -o \
        -type f \( \
              -name "*.yaml" -o -name "*.yml" \
            -o -name "*.py"  -o -name "*.sh" \
            -o -name "*.rs"  -o -name "*.go" -o -name "*.ts" -o -name "*.tsx" \
            -o -name "*.sql" -o -name "*.md" -o -name "*.toml" \
            -o -name "*.json" -o -name "*.j2" -o -name "*.proto" \
            -o -name "*.txt" -o -name "*.env*" -o -name ".env*" \
            -o -name "Dockerfile*" -o -name "Makefile*" \
            -o -name "build.mill" \
        \) -print0
)

# ---------------------------------------------------------------------------
# Helper: rewrite a single file (mask vendor names → swap OLD→NEW → unmask).
# Uses GNU sed in-place; on macOS `gsed` if available.
# ---------------------------------------------------------------------------
if sed --version >/dev/null 2>&1; then
    SED_INPLACE=(sed -i)
else
    SED_INPLACE=(sed -i '')
fi

rewrite_file() {
    local f="$1"
    # 1. Mask vendor names (preserve them across the rewrite).
    for v in "${VENDOR_KEEP[@]}"; do
        "${SED_INPLACE[@]}" "s|${v}|${SENTINEL}${v}${SENTINEL}|g" "$f"
    done
    # 2. Swap OLD → NEW with GNU-sed word boundaries.
    #
    #    `\<X\>` matches X as a whole word — i.e., where both sides are at the
    #    boundary of a word char run ([A-Za-z0-9_]). That catches `crypto-foo`,
    #    `use-case-crypto`, `"crypto"`, `crypto.x`, ` crypto;`, etc. without
    #    touching `cryptopanic` or `cryptography` (no boundary inside a word).
    #
    #    `_` counts as a word char, so for snake_case we need explicit handling:
    #      crypto_x         — leading token of an identifier
    #      x_crypto         — trailing token
    #      x_crypto_y       — middle token
    #    These three patterns plus `\<X\>` cover identifier rewrites cleanly.
    "${SED_INPLACE[@]}" \
        -e "s|\\<${OLD}\\>|${NEW}|g"             `# whole word; covers prefix/suffix/dotted/quoted/colon-bounded` \
        -e "s|\\<${OLD}_|${NEW}_|g"              `# snake_case leading token: crypto_pipeline` \
        -e "s|_${OLD}\\>|_${NEW}|g"              `# snake_case trailing token: use_case_crypto` \
        -e "s|_${OLD}_|_${NEW}_|g"               `# snake_case middle token: my_crypto_lib`    \
        "$f"
    # 3. Unmask vendor names.
    for v in "${VENDOR_KEEP[@]}"; do
        "${SED_INPLACE[@]}" "s|${SENTINEL}${v}${SENTINEL}|${v}|g" "$f"
    done
}

# ---------------------------------------------------------------------------
# Content rewrite pass
# ---------------------------------------------------------------------------
printf "${YELLOW}Rewriting content in %d files...${NC}\n" "${#FILES[@]}"
for f in "${FILES[@]}"; do
    rewrite_file "$f"
done

# ---------------------------------------------------------------------------
# Filename rename pass — process deepest paths first so parent renames don't
# invalidate child paths mid-loop.
# ---------------------------------------------------------------------------
printf "${YELLOW}Renaming files containing '%s' in the basename...${NC}\n" "$OLD"
renamed=0
# Sort by depth descending — `awk '{print gsub(/\//,"&")"\t"$0}'` counts slashes.
while IFS= read -r -d '' path; do
    dir="$(dirname "$path")"
    base="$(basename "$path")"
    # Only rewrite OLD as a whole token in the basename (avoid touching
    # filenames where OLD is embedded inside a vendor word, e.g. "cryptopanic").
    new_base="$base"
    # Mask vendor words in the basename to protect them.
    for v in "${VENDOR_KEEP[@]}"; do
        new_base="${new_base//${v}/${SENTINEL}${v}${SENTINEL}}"
    done
    new_base="${new_base//${OLD}/${NEW}}"
    for v in "${VENDOR_KEEP[@]}"; do
        new_base="${new_base//${SENTINEL}${v}${SENTINEL}/${v}}"
    done
    if [[ "$new_base" != "$base" ]]; then
        mv -- "$path" "$dir/$new_base"
        printf "  ${GREEN}mv${NC} %s → %s\n" "$path" "$dir/$new_base"
        renamed=$((renamed + 1))
    fi
done < <(
    find . \
        -path ./.git -prune -o \
        -path ./.venv -prune -o \
        -path "*/target" -prune -o \
        -path "*/out" -prune -o \
        -type f -print0 \
    | awk -v RS='\0' -v ORS='\0' '{print gsub(/\//, "&")"\t"$0}' \
    | sort -z -nr \
    | cut -z -f2-
)

# ---------------------------------------------------------------------------
# Validation — surface anything still referencing OLD (excluding vendor words,
# git internals, and the script itself which documents OLD names in comments).
# ---------------------------------------------------------------------------
printf "\n${BLUE}Validating...${NC}\n"
SCRIPT_REL="${BASH_SOURCE[0]#"$USECASE_DIR/"}"
remaining_raw="$(grep -rln \
    --exclude-dir=.git \
    --exclude-dir=.venv \
    --exclude-dir=target \
    --exclude-dir=out \
    --exclude-dir=__pycache__ \
    -- "$OLD" . 2>/dev/null || true)"

# Filter out the configure script itself (carries OLD as documentation) and
# whitelisted vendor-name occurrences.
remaining=""
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" == *"$SCRIPT_REL"* ]] && continue
    # Drop the file from the remaining list if its only OLD occurrences are
    # inside a vendor word (e.g. cryptopanic).
    other="$(grep -nE "(^|[^a-zA-Z])${OLD}([^a-zA-Z]|$)" "$line" 2>/dev/null \
        | grep -viE "$(IFS='|'; echo "${VENDOR_KEEP[*]}")" || true)"
    [[ -n "$other" ]] && remaining+="$line"$'\n'
done <<< "$remaining_raw"

if [[ -n "$remaining" ]]; then
    printf "${YELLOW}WARNING: residual '%s' references remain in:${NC}\n" "$OLD"
    printf '%s' "$remaining" | sed 's|^|  |'
    printf "${YELLOW}Inspect manually — these are intentionally domain-specific (Java${NC}\n"
    printf "${YELLOW}package names, vendor APIs, archived data tables) or genuine misses.${NC}\n"
else
    printf "${GREEN}No residual '%s' references found.${NC}\n" "$OLD"
fi

printf "\n${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"
printf "${GREEN}  Reconfigured: '%s' → '%s' (%d files, %d renames)${NC}\n" "$OLD" "$NEW" "${#FILES[@]}" "$renamed"
printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"
printf "Next steps:\n"
printf "  1. ${BLUE}git diff${NC}                                    # review changes\n"
printf "  2. ${BLUE}kubectl kustomize manifests/overlays/local${NC}   # verify renders\n"
printf "  3. ${BLUE}make usecase-build && make usecase-up${NC}        # deploy\n"
