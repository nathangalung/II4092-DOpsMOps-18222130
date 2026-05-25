#!/usr/bin/env bash
# =============================================================================
# seed-gitea.sh — push the platform/ tree AND each use-case-*/ overlay to the
# in-cluster Gitea
# =============================================================================
# Closes the GitOps bootstrap loop:
#   1. install-gitea (atom-gitops-core) creates the gitea pod + the
#      gitea-bootstrap Job, which provisions org `platform` and an empty repo
#      `platform/platform` plus one repo per use-case overlay
#      (`platform/use-case-crypto`, ...). auto_init=true seeds each with a
#      README.md so downstream consumers always find a `main` ref.
#   2. ArgoCD has TWO source-of-truth surfaces:
#        - `platform/platform.git` — app-of-apps + per-component ApplicationSet
#        - `platform/<use-case>.git` — per-use-case AppProject +
#          ApplicationSet (lives in `use-case-*/argocd/`)
#      Both must contain the working tree by the time ArgoCD reconciles.
#   3. This script port-forwards Gitea once, then iterates over each source
#      directory (platform/ + use-case-*/) and force-pushes the working tree
#      to its corresponding gitea repo. Idempotent: re-running force-pushes
#      the latest tree on top, exactly what we want for an ops bootstrap.
#
# Why force-push: the bootstrap Job auto-creates each repo with a README.md
# initial commit that we don't share history with. A clean force-push is
# semantically correct — operator host is the source of truth at this stage,
# pre-CI/CD wiring.
#
# Why a temp dir: the ta workspace is intentionally NOT a git repo (per the
# project layout). Building the commit out-of-tree avoids polluting the
# operator's working directory with .git/ state.
#
# Wire-up: invoked by `make seed-gitea`, which `phase-full` chains after
# `atom-gitops-core` so ArgoCD has a populated repo by the time the
# self-managed root Application begins reconciling.
# =============================================================================
set -euo pipefail

NAMESPACE="${GITEA_NAMESPACE:-gitops}"
SERVICE="${GITEA_SERVICE:-gitea}"
LOCAL_PORT="${GITEA_LOCAL_PORT:-13000}"
ORG="${GITEA_ORG:-platform}"
ADMIN_SECRET="${GITEA_ADMIN_SECRET:-gitea-admin}"
BOOTSTRAP_JOB="${GITEA_BOOTSTRAP_JOB:-gitea-bootstrap}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM_DIR="${REPO_ROOT}/platform"

# Each entry: "<repo-name>:<src-dir-rel-to-repo-root>:<top-level-name>".
# - repo-name   → gitea repo to push to under org `platform`
# - src-dir     → absolute path inside the operator-host checkout
# - top-level   → directory name inside the commit (preserves
#                 `path: platform/components/<x>` semantics so ArgoCD
#                 source.path stays unchanged after refactor)
SEED_TARGETS=(
  "platform:${PLATFORM_DIR}:platform"
  "use-case-crypto:${REPO_ROOT}/use-case-crypto:use-case-crypto"
)

if [[ ! -d "${PLATFORM_DIR}" ]]; then
  echo "ERROR: ${PLATFORM_DIR} not found — must run from a checkout containing platform/" >&2
  exit 2
fi

if kubectl -n "${NAMESPACE}" get "job/${BOOTSTRAP_JOB}" >/dev/null 2>&1; then
  echo "==> seed-gitea: waiting for gitea-bootstrap Job to complete (timeout 900s)"
  # 900s, not 300s: cold-start chains image pull + gitea probes + DB init + bootstrap
  # script. Observed ~6m on a fresh cluster (#191 sandbox churn extends it further).
  kubectl -n "${NAMESPACE}" wait --for=condition=complete --timeout=900s "job/${BOOTSTRAP_JOB}"
else
  # Post-bootstrap re-runs (operator pushing an ongoing source change): the
  # bootstrap Job has been GC'd long ago. We still need to push, so verify
  # gitea itself is up and proceed.
  echo "==> seed-gitea: bootstrap Job absent (post-bootstrap rerun); checking gitea Service"
  kubectl -n "${NAMESPACE}" wait --for=condition=Available --timeout=120s "deployment/${SERVICE}" \
    || { echo "ERROR: gitea Deployment not Available in ${NAMESPACE}" >&2; exit 2; }
fi

echo "==> seed-gitea: reading admin creds from secret/${ADMIN_SECRET}"
ADMIN_USER=$(kubectl -n "${NAMESPACE}" get secret "${ADMIN_SECRET}" -o jsonpath='{.data.username}' | base64 -d)
ADMIN_PASS=$(kubectl -n "${NAMESPACE}" get secret "${ADMIN_SECRET}" -o jsonpath='{.data.password}' | base64 -d)
if [[ -z "${ADMIN_USER}" || -z "${ADMIN_PASS}" ]]; then
  echo "ERROR: empty admin creds in secret ${NAMESPACE}/${ADMIN_SECRET}" >&2
  exit 2
fi

# Pick first free TCP port in [LOCAL_PORT, LOCAL_PORT+999]. A prior run that
# was SIGKILL'd or aborted before its `trap cleanup EXIT` could fire leaves an
# orphan `kubectl port-forward` holding ${LOCAL_PORT}. Auto-skipping to the
# next free port is safer than killing whatever owns it (could be an unrelated
# process — a developer's local dev server, another concurrent seed-gitea run,
# etc.). 1000-port window is far larger than any realistic collision count.
echo "==> seed-gitea: locating free local TCP port (base ${LOCAL_PORT})"
found_port=""
for candidate in $(seq "${LOCAL_PORT}" "$((LOCAL_PORT + 999))"); do
  if ! ss -tlnH "sport = :${candidate}" 2>/dev/null | grep -q LISTEN; then
    found_port="${candidate}"
    break
  fi
done
if [[ -z "${found_port}" ]]; then
  echo "ERROR: no free TCP port in ${LOCAL_PORT}..$((LOCAL_PORT + 999))" >&2
  exit 2
fi
if [[ "${found_port}" != "${LOCAL_PORT}" ]]; then
  echo "    base port ${LOCAL_PORT} busy; using ${found_port}"
fi
LOCAL_PORT="${found_port}"

echo "==> seed-gitea: starting port-forward svc/${SERVICE} ${LOCAL_PORT}->3000"
kubectl -n "${NAMESPACE}" port-forward "svc/${SERVICE}" "${LOCAL_PORT}:3000" >/tmp/seed-gitea-pf.log 2>&1 &
PF_PID=$!
cleanup() {
  if kill -0 "${PF_PID}" 2>/dev/null; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "==> seed-gitea: waiting for port-forward + gitea API readiness"
for i in $(seq 1 30); do
  if curl -fsS --max-time 2 "http://localhost:${LOCAL_PORT}/api/v1/version" >/dev/null 2>&1; then
    echo "    gitea API up after ${i}s"
    break
  fi
  if (( i == 30 )); then
    echo "ERROR: gitea API never came up at localhost:${LOCAL_PORT}" >&2
    cat /tmp/seed-gitea-pf.log >&2 || true
    exit 2
  fi
  sleep 1
done

WORKDIR_ROOT=$(mktemp -d -t seed-gitea-XXXXXX)
trap "cleanup; rm -rf '${WORKDIR_ROOT}'" EXIT INT TERM

for target in "${SEED_TARGETS[@]}"; do
  IFS=":" read -r repo_name src_dir top_level <<<"${target}"

  if [[ ! -d "${src_dir}" ]]; then
    echo "==> seed-gitea: skipping ${repo_name} — source ${src_dir} not present"
    continue
  fi

  # ADR-013: platform's gitea-bootstrap creates only `platform/platform`.
  # Per-use-case repos are provisioned here (operator-host scope is allowed
  # to enumerate use-cases). Idempotent: 201 on create, 409 on already-exists.
  echo "==> seed-gitea: ensuring repo ${ORG}/${repo_name}"
  uc_code=$(curl -sS -o /tmp/seed-gitea-uc.json -w '%{http_code}' \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -H 'Content-Type: application/json' \
    -X POST "http://localhost:${LOCAL_PORT}/api/v1/orgs/${ORG}/repos" \
    -d "{\"name\":\"${repo_name}\",\"auto_init\":true,\"default_branch\":\"main\",\"private\":false,\"description\":\"Synced by ArgoCD (managed by seed-gitea.sh).\"}" || echo 000)
  case "${uc_code}" in
    201) echo "    repo ${ORG}/${repo_name} created (HTTP 201)" ;;
    409|422) echo "    repo ${ORG}/${repo_name} already exists (HTTP ${uc_code})" ;;
    *)
      echo "ERROR: repo create for ${ORG}/${repo_name} returned ${uc_code}" >&2
      cat /tmp/seed-gitea-uc.json >&2 || true
      exit 2
      ;;
  esac

  workdir="${WORKDIR_ROOT}/${repo_name}"
  mkdir -p "${workdir}"

  # rsync (not cp -a) so we can prune build artifacts. platform/services and
  # use-case-*/services each hold multi-GB of .venv / __pycache__ /
  # Rust target/ / node_modules from local app builds — they're not read by
  # ArgoCD (which only targets manifest dirs under platform/components/<x>
  # or use-case-*/manifests/) and copying them stalls under disk pressure
  # (cp -a goes D-state on saturated I/O).
  echo "==> seed-gitea: staging ${top_level}/ tree in ${workdir} (rsync --exclude build artifacts)"
  rsync -a \
    --exclude='.git' \
    --exclude='.venv' \
    --exclude='__pycache__' \
    --exclude='target' \
    --exclude='node_modules' \
    --exclude='.uv-cache' \
    --exclude='.pytest_cache' \
    --exclude='.mypy_cache' \
    --exclude='*.pyc' \
    "${src_dir}/" "${workdir}/${top_level}/"

  # Use-case repos inherit Deployments / RBAC / ConfigMap templates from
  # `platform/services/base/` via `../../../platform/services/base/...`
  # relative paths in `use-case-*/manifests/base/kustomization.yaml`.
  # When the use-case repo is checked out standalone by ArgoCD (which
  # owns a separate clone per `source.repoURL`), those paths point above
  # the repo root and kustomize errors with `evalsymlink failure: no such
  # file or directory: platform/`. Mirroring just the `platform/services/
  # base/` subtree alongside `${top_level}/` resolves the paths
  # deterministically without bloating the use-case repo with the full
  # platform tree (~1.2k files vs ~30). This is purely a derived
  # artefact of the seed step — the operator-host working tree never
  # carries a `platform/` sibling inside `use-case-*/`.
  if [[ "${repo_name}" == use-case-* ]]; then
    inherited_src="${PLATFORM_DIR}/services/base"
    if [[ -d "${inherited_src}" ]]; then
      echo "==> seed-gitea: mirroring platform/services/base/ into ${repo_name} repo (cross-tree base for kustomize ../../..)"
      # rsync (<3.2.3) won't create missing dst parents. --mkpath exists on
      # newer rsync but distros lag; pre-create the parent explicitly so the
      # script works on stock Debian/Ubuntu/RHEL operator hosts.
      mkdir -p "${workdir}/platform/services"
      rsync -a \
        --exclude='.git' \
        --exclude='.venv' \
        --exclude='__pycache__' \
        --exclude='target' \
        --exclude='node_modules' \
        --exclude='.uv-cache' \
        --exclude='.pytest_cache' \
        --exclude='.mypy_cache' \
        --exclude='*.pyc' \
        "${inherited_src}/" "${workdir}/platform/services/base/"
    fi
  fi

  (
    cd "${workdir}"
    git init -q -b main
    git -c user.email="admin@platform.local" -c user.name="platform-admin" add .
    git -c user.email="admin@platform.local" -c user.name="platform-admin" commit -q -m "${repo_name}: seed working tree"

    REMOTE="http://${ADMIN_USER}:${ADMIN_PASS}@localhost:${LOCAL_PORT}/${ORG}/${repo_name}.git"
    echo "==> seed-gitea: force-pushing main to ${ORG}/${repo_name}"
    git push -qf "${REMOTE}" main:main
    echo "==> seed-gitea: ${repo_name} done ($(find . -type f -not -path './.git/*' | wc -l) files pushed)"
  )
done

echo "==> seed-gitea: all targets pushed"
