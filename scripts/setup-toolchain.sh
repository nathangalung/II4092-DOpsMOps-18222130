#!/bin/bash
# =============================================================================
# DataOps/MLOps Platform — Toolchain Setup
# =============================================================================
# Installs build tools + system deps to deploy the platform.
# Run once on a fresh VPS/VM.
#
# Supported: Ubuntu 24.04+ / Debian 13+
# Usage:     chmod +x scripts/setup-toolchain.sh && ./scripts/setup-toolchain.sh
#
# Languages: Go, Rust, Python, Java, TypeScript (Bun), C++ (xmake)
# Cluster:   k3s + kubectl + helm + kustomize + jq + yq
# Optional:  Docker (only for local image builds + registry:5000 cache)
#
# Env gates (skip stages):
#   SKIP_DOCKER=1        Skip Docker install (k3s containerd handles K8s)
#   SKIP_REGISTRY=1      Skip local registry:5000 (auto-on when SKIP_DOCKER=1)
#   SKIP_BUILD_TOOLS=1   Skip Go/Rust/Python/Bun/Java/Mill/xmake
#   SKIP_K3S=1           Skip k3s install (use existing cluster)
# =============================================================================

set -euo pipefail

# --- Env gates ---------------------------------------------------------------
SKIP_DOCKER="${SKIP_DOCKER:-0}"
SKIP_REGISTRY="${SKIP_REGISTRY:-0}"
SKIP_BUILD_TOOLS="${SKIP_BUILD_TOOLS:-0}"
SKIP_K3S="${SKIP_K3S:-0}"
# Auto-disable registry if no Docker
[[ "$SKIP_DOCKER" == "1" ]] && SKIP_REGISTRY=1

# --- Versions (pinned to stable releases) ------------------------------------
GO_VERSION="1.26.1"
RUST_VERSION="1.94.1"
PYTHON_VERSION="3.13"
UV_VERSION="0.11.3"
BUN_VERSION="1.3.11"
JAVA_VERSION="21"
MILL_VERSION="1.1.5"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- Helper: check if command exists at minimum version ----------------------
has() { command -v "$1" &>/dev/null; }

# =============================================================================
# 1. SYSTEM PACKAGES (apt)
# =============================================================================
install_system_packages() {
    info "Installing system packages..."
    sudo apt-get update -qq

    sudo apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        cmake \
        libssl-dev \
        libcurl4-openssl-dev \
        libsasl2-dev \
        protobuf-compiler \
        libprotobuf-dev \
        git \
        curl \
        wget \
        unzip \
        jq \
        ca-certificates \
        gnupg \
        lsb-release

    ok "System packages installed"
}

# =============================================================================
# 2. DOCKER
# =============================================================================
install_docker() {
    if has docker; then
        ok "Docker already installed: $(docker --version)"
    else
        info "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker "$USER"
        ok "Docker installed"
    fi

    # Configure Docker daemon with reliable DNS and log rotation
    if [ ! -f /etc/docker/daemon.json ] || ! grep -q "dns" /etc/docker/daemon.json 2>/dev/null; then
        info "Configuring Docker daemon (DNS + log rotation)..."
        # Detect the host's upstream DNS server (institutional/ISP) for Docker containers
        local HOST_DNS
        HOST_DNS=$(resolvectl status 2>/dev/null | grep -oP 'DNS Servers:\s*\K[\d.]+' | head -1 || \
                   grep -m1 'nameserver' /run/systemd/resolve/resolv.conf 2>/dev/null | awk '{print $2}' || \
                   echo "1.1.1.1")
        sudo tee /etc/docker/daemon.json > /dev/null <<DOCKER_EOF
{
  "dns": ["${HOST_DNS}", "1.1.1.1", "8.8.8.8"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DOCKER_EOF
        sudo systemctl restart docker
        ok "Docker daemon configured (primary DNS: ${HOST_DNS})"
    fi

    # In-cluster Distribution v3 registry (platform/components/common/registry)
    # listens on hostPort 5000 of the node — no host-side `registry:2` daemon
    # is needed any more.  Stale containers from previous bootstraps are
    # removed so they don't fight for :5000.
    if docker ps -a --format '{{.Names}}' | grep -q "^registry$"; then
        info "Removing legacy host docker registry (replaced by in-cluster Distribution)..."
        docker rm -f registry >/dev/null 2>&1 || true
        ok "Legacy host registry removed"
    fi
}

# =============================================================================
# 3. k3s
# =============================================================================
install_k3s() {
    # k3s install flags:
    #   --disable=traefik:             platform uses Istio IngressGateway + APISIX for L7
    #                                  (dual-controller traffic routing is ambiguous).
    #   --disable=servicelb:           we use Istio IngressGateway's LoadBalancer directly;
    #                                  klipper-lb adds an extra hop.
    #   --disable=metrics-server:      replaced by kube-prometheus-stack's kube-state-metrics
    #                                  + node-exporter + Prometheus Adapter for HPA.
    #   --write-kubeconfig-mode 644:   readable by user without sudo.
    local K3S_INSTALL_FLAGS="--write-kubeconfig-mode 644 --disable=traefik --disable=servicelb --disable=metrics-server"

    if has k3s; then
        ok "k3s already installed: $(k3s --version | head -1)"
    else
        info "Installing k3s (traefik/servicelb/metrics-server disabled — platform provides replacements)..."
        curl -sfL https://get.k3s.io | sh -s - ${K3S_INSTALL_FLAGS}
        mkdir -p ~/.kube
        cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
        chmod 600 ~/.kube/config
        ok "k3s installed"
    fi

    # Always (re)write the config so source edits (e.g. #214 tolerance args)
    # propagate without manual /etc cleanup.  Heredocs below are the source of
    # truth for /etc/rancher/k3s/*.yaml; previous if-guard caused stale configs
    # to persist across nuke + phase-full and silently shadow source fixes.
    # Track content changes via SHA so we restart k3s exactly once at the end
    # of this function if (and only if) any /etc/rancher/k3s/*.yaml changed.
    local k3s_needs_restart=0
    local sha_before sha_after
    sha_before=$(sudo sha256sum \
        /etc/rancher/k3s/config.yaml \
        /etc/rancher/k3s/pss-config.yaml \
        /etc/rancher/k3s/audit-policy.yaml 2>/dev/null | awk '{print $1}' | sort | sha256sum)
    {
        info "Configuring k3s config (max-pods=250, IO-cascade tolerance #214, local-path default storage class — ADR-031)..."
        sudo mkdir -p /etc/rancher/k3s
        sudo tee /etc/rancher/k3s/config.yaml > /dev/null <<'K3S_CFG_EOF'
# k3s server configuration.  Built-in controllers that the platform replaces
# with best-of-breed upstream equivalents are disabled here so that they stay
# disabled across restarts (the CLI --disable only applies at install time).
disable:
  - traefik        # replaced by Istio IngressGateway + APISIX
  - servicelb      # replaced by Istio IngressGateway LoadBalancer
  - metrics-server # replaced by kube-state-metrics (HPA custom metrics served by KEDA since ADR-026; prometheus-adapter retired 2026-04-21)

# local-path-provisioner is the ONLY storage class on this single-node
# platform (ADR-031). PVCs land as hostPath bind-mounts under
# /var/lib/rancher/k3s/storage/ — no CSI driver, no engine pod, no replica
# pod overhead.
kubelet-arg:
  - max-pods=250
  # IO-cascade tolerance (#214 — original Longhorn-era cause now mitigated by
  # ADR-031, but kine + containerd still share /dev/sda1). Under sustained
  # PSI IO full>50% the kubelet PATCH /status
  # latency exceeds the default 40s grace period and the node flips NotReady,
  # which triggers TaintManagerEviction + pod recreation storm + more IO load
  # (self-perpetuating cascade observed 14× in 20h).  Lower PATCH cadence to
  # reduce kine write pressure originating from the kubelet itself.
  - node-status-update-frequency=20s
  # Match runtime-request-timeout to containerd pull/start latencies observed
  # during recovery storms (helper-pod-create 120s+).  Default 2m is too tight.
  - runtime-request-timeout=10m
  # NOTE: shutdown-grace-period* removed in k3s 1.35+ — kubelet only accepts
  # these via KubeletConfiguration file now, not flags. Defaults still apply.

# Admission: enforce PodSecurityStandards on all namespaces by default.
# default-{not-ready,unreachable}-toleration-seconds are kube-apiserver flags
# (DefaultTolerationSeconds admission plugin) — NOT controller-manager flags;
# placing them on controller-manager-arg crashes the embedded CM at startup
# ("unknown flag") which cascades to the whole k3s server exiting (field-
# observed 2026-05-14 in #214 first deploy attempt).
kube-apiserver-arg:
  - admission-control-config-file=/etc/rancher/k3s/pss-config.yaml
  - audit-policy-file=/etc/rancher/k3s/audit-policy.yaml
  - audit-log-path=/var/log/kubernetes/audit/audit.log
  - audit-log-maxage=30
  - audit-log-maxbackup=10
  - audit-log-maxsize=100
  # IO-cascade tolerance (#214): pods stay 10min after their node flips
  # NotReady/Unreachable before TaintManagerEviction starts terminating
  # them.  Defaults are 300s; under kine WAL saturation a node may flap
  # NotReady transiently and we don't want a 5-minute blip to trigger
  # wholesale pod recreation storm (the very thing that perpetuates the
  # cascade — see #160/#166/#169/#209).
  - default-not-ready-toleration-seconds=600
  - default-unreachable-toleration-seconds=600

# IO-cascade tolerance (#214): node-monitor checks every 5s and trips NotReady
# at 40s by default.  Under kine WAL saturation the kubelet PATCH /status round-
# trip exceeds that even when the node is functionally healthy.  Stretch the
# grace window so transient kine txn timeouts don't cascade to pod evictions.
kube-controller-manager-arg:
  - node-monitor-period=10s
  - node-monitor-grace-period=180s
K3S_CFG_EOF

        # PodSecurity admission: baseline enforcement by default, restricted audit.
        # Namespaces that run privileged pods (cert-manager webhooks, istio-cni)
        # override with pod-security.kubernetes.io/enforce=privileged label.
        sudo tee /etc/rancher/k3s/pss-config.yaml > /dev/null <<'PSS_EOF'
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: PodSecurity
    configuration:
      apiVersion: pod-security.admission.config.k8s.io/v1
      kind: PodSecurityConfiguration
      defaults:
        enforce: baseline
        enforce-version: latest
        audit: restricted
        audit-version: latest
        warn: restricted
        warn-version: latest
      exemptions:
        usernames: []
        runtimeClasses: []
        namespaces:
          - kube-system
          - cert-manager
          - istio-system
          - kyverno
PSS_EOF

        # Audit policy: log all authorization decisions on security-relevant resources.
        sudo tee /etc/rancher/k3s/audit-policy.yaml > /dev/null <<'AUDIT_EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
  - RequestReceived
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps", "serviceaccounts"]
      - group: "rbac.authorization.k8s.io"
      - group: "authentication.k8s.io"
      - group: "authorization.k8s.io"
  - level: RequestResponse
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: "apps"
        resources: ["deployments", "statefulsets", "daemonsets"]
      - group: "batch"
        resources: ["jobs", "cronjobs"]
  - level: None
AUDIT_EOF
        sudo mkdir -p /var/log/kubernetes/audit
        ok "k3s config (PSS + audit + disable list + #214 tolerance) written"
    }
    sha_after=$(sudo sha256sum \
        /etc/rancher/k3s/config.yaml \
        /etc/rancher/k3s/pss-config.yaml \
        /etc/rancher/k3s/audit-policy.yaml 2>/dev/null | awk '{print $1}' | sort | sha256sum)
    if [[ "$sha_before" != "$sha_after" ]]; then
        k3s_needs_restart=1
        info "k3s config content changed — restart queued for end of install_k3s"
    fi

    # Configure k3s containerd to trust the in-cluster Distribution registry.
    # The registry Pod (platform/components/common/registry) exposes hostPort
    # 5000, so requests for `registry.platform-registry.svc.cluster.local:5000`
    # are rewritten to plain HTTP `http://localhost:5000` and never have to
    # resolve cluster DNS from the host.  `localhost:5000` is kept for
    # convenience (manual `docker push localhost:5000/...`).
    if ! diff -q /etc/rancher/k3s/registries.yaml - <<'K3S_REG_EOF' >/dev/null 2>&1
mirrors:
  "registry.platform-registry.svc.cluster.local:5000":
    endpoint:
      - "http://localhost:5000"
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"
configs:
  "registry.platform-registry.svc.cluster.local:5000":
    tls:
      insecure_skip_verify: true
  "localhost:5000":
    tls:
      insecure_skip_verify: true
K3S_REG_EOF
    then
        info "Updating k3s registries.yaml (in-cluster Distribution mirror)..."
        sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<'K3S_REG_EOF'
mirrors:
  "registry.platform-registry.svc.cluster.local:5000":
    endpoint:
      - "http://localhost:5000"
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"
configs:
  "registry.platform-registry.svc.cluster.local:5000":
    tls:
      insecure_skip_verify: true
  "localhost:5000":
    tls:
      insecure_skip_verify: true
K3S_REG_EOF
        k3s_needs_restart=1
        ok "k3s registries.yaml updated — restart queued"
    else
        ok "k3s registries.yaml already up to date"
    fi

    # Apply queued restart exactly once if any /etc/rancher/k3s/*.yaml changed.
    if [[ "${k3s_needs_restart:-0}" -eq 1 ]]; then
        info "Restarting k3s to pick up config changes..."
        sudo systemctl restart k3s
        ok "k3s restarted"
    fi
}

# =============================================================================
# 4. SYSCTL TUNING
# =============================================================================
configure_sysctl() {
    info "Configuring kernel parameters..."
    local SYSCTL_FILE="/etc/sysctl.d/99-k3s-platform.conf"

    sudo tee "$SYSCTL_FILE" > /dev/null <<'SYSCTL_EOF'
# k3s / platform tuning
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = 524288
fs.file-max = 2097152
SYSCTL_EOF

    sudo sysctl --system > /dev/null 2>&1
    ok "Kernel parameters configured"
}

# =============================================================================
# 4b. DNS RELIABILITY
# =============================================================================
configure_dns() {
    info "Configuring DNS with fallback resolvers..."
    local HOST_DNS
    HOST_DNS=$(grep -m1 'nameserver' /run/systemd/resolve/resolv.conf 2>/dev/null | awk '{print $2}' || echo "1.1.1.1")

    sudo mkdir -p /etc/systemd/resolved.conf.d
    sudo tee /etc/systemd/resolved.conf.d/dns.conf > /dev/null <<DNS_EOF
[Resolve]
DNS=${HOST_DNS} 1.1.1.1 8.8.8.8
FallbackDNS=1.0.0.1 8.8.4.4
DNSOverTLS=no
DNS_EOF

    sudo systemctl restart systemd-resolved 2>/dev/null || true
    ok "DNS configured (primary: ${HOST_DNS}, fallback: 1.1.1.1, 8.8.8.8)"
}

# =============================================================================
# 5. GO
# =============================================================================
install_go() {
    if has go && go version 2>&1 | grep -q "go${GO_VERSION}"; then
        ok "Go already installed: $(go version)"
        return
    fi

    info "Installing Go ${GO_VERSION}..."
    # Use mktemp -d so concurrent installs / locked-down /tmp policies don't
    # collide; trap-cleanup guarantees no leak on early exit.
    local GO_TMP
    GO_TMP=$(mktemp -d)
    trap 'rm -rf "$GO_TMP"' RETURN
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o "$GO_TMP/go.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "$GO_TMP/go.tar.gz"

    # Ensure PATH
    grep -q '/usr/local/go/bin' ~/.profile 2>/dev/null || \
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.profile
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin

    ok "Go installed: $(go version)"
}

# =============================================================================
# 6. RUST + cargo-nextest
# =============================================================================
install_rust() {
    if has rustc && rustc --version 2>&1 | grep -q "${RUST_VERSION}"; then
        ok "Rust already installed: $(rustc --version)"
    else
        info "Installing Rust ${RUST_VERSION}..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
            sh -s -- -y --default-toolchain "${RUST_VERSION}" --profile minimal
        source "$HOME/.cargo/env"
        ok "Rust installed: $(rustc --version)"
    fi

    # cargo-nextest
    if has cargo-nextest; then
        ok "cargo-nextest already installed: $(cargo nextest --version 2>&1 | head -1)"
    else
        info "Installing cargo-nextest..."
        cargo install cargo-nextest --locked
        ok "cargo-nextest installed"
    fi
}

# =============================================================================
# 7. PYTHON (via uv)
# =============================================================================
install_python() {
    if has uv; then
        ok "uv already installed: $(uv --version)"
    else
        info "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
        ok "uv installed: $(uv --version)"
    fi

    # Install Python via uv (managed, doesn't touch system Python)
    if uv python find "${PYTHON_VERSION}" &>/dev/null; then
        ok "Python ${PYTHON_VERSION} already available via uv"
    else
        info "Installing Python ${PYTHON_VERSION} via uv..."
        uv python install "${PYTHON_VERSION}"
        ok "Python ${PYTHON_VERSION} installed"
    fi
}

# =============================================================================
# 8. BUN (TypeScript runtime)
# =============================================================================
install_bun() {
    if has bun && bun --version 2>&1 | grep -q "${BUN_VERSION}"; then
        ok "Bun already installed: $(bun --version)"
        return
    fi

    info "Installing Bun ${BUN_VERSION}..."
    curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"
    export PATH="$HOME/.bun/bin:$PATH"
    ok "Bun installed: $(bun --version)"
}

# =============================================================================
# 9. JAVA (OpenJDK)
# =============================================================================
install_java() {
    if has java && java --version 2>&1 | grep -q "openjdk ${JAVA_VERSION}"; then
        ok "Java already installed: $(java --version 2>&1 | head -1)"
        return
    fi

    info "Installing OpenJDK ${JAVA_VERSION}..."
    sudo apt-get install -y --no-install-recommends "openjdk-${JAVA_VERSION}-jdk-headless"
    ok "Java installed: $(java --version 2>&1 | head -1)"
}

# =============================================================================
# 10. MILL (Scala/Java build tool)
# =============================================================================
install_mill() {
    if has mill; then
        ok "Mill already installed: $(mill version 2>&1 | tail -1)"
        return
    fi

    info "Installing Mill ${MILL_VERSION}..."
    mkdir -p "$HOME/.local/bin"
    curl -fsSL "https://repo1.maven.org/maven2/com/lihaoyi/mill-dist/${MILL_VERSION}/mill-dist-${MILL_VERSION}.jar" -o "$HOME/.local/bin/mill"
    chmod +x "$HOME/.local/bin/mill"
    export PATH="$HOME/.local/bin:$PATH"
    ok "Mill installed: $(mill version 2>&1 | tail -1)"
}

# =============================================================================
# 11. XMAKE (C++ build system)
# =============================================================================
install_xmake() {
    if has xmake; then
        ok "xmake already installed: $(xmake --version 2>&1 | head -1 | sed 's/\x1b\[[0-9;]*m//g')"
        return
    fi

    info "Installing xmake from source..."
    local TMPDIR
    TMPDIR=$(mktemp -d)
    curl -fsSL "https://github.com/xmake-io/xmake/releases/latest/download/xmake-master.tar.gz" -o "${TMPDIR}/xmake.tar.gz"
    tar xzf "${TMPDIR}/xmake.tar.gz" -C "${TMPDIR}" --strip-components=1
    cd "${TMPDIR}"
    ./configure --prefix="$HOME/.local" > /dev/null 2>&1
    make -j"$(nproc)" > /dev/null 2>&1
    make install > /dev/null 2>&1
    cd - > /dev/null
    rm -rf "${TMPDIR}"
    export PATH="$HOME/.local/bin:$PATH"
    ok "xmake installed: $(xmake --version 2>&1 | head -1 | sed 's/\x1b\[[0-9;]*m//g')"
}

# =============================================================================
# 12. HELM
# =============================================================================
install_helm() {
    if has helm; then
        ok "helm already installed: $(helm version --short 2>/dev/null)"
        return
    fi
    info "Installing helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    ok "helm installed: $(helm version --short)"
}

# =============================================================================
# 13. KUSTOMIZE (standalone — kubectl has built-in but some workflows want CLI)
# =============================================================================
install_kustomize() {
    if has kustomize; then
        ok "kustomize already installed: $(kustomize version 2>/dev/null | head -1)"
        return
    fi
    info "Installing kustomize..."
    curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
    ok "kustomize installed: $(kustomize version | head -1)"
}

# =============================================================================
# 14. YQ
# =============================================================================
install_yq() {
    if has yq; then
        ok "yq already installed: $(yq --version 2>/dev/null)"
        return
    fi
    info "Installing yq..."
    sudo curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" \
        -o /usr/local/bin/yq
    sudo chmod +x /usr/local/bin/yq
    ok "yq installed: $(yq --version)"
}

# =============================================================================
# 15. VERIFY
# =============================================================================
verify_all() {
    echo ""
    echo "=============================================="
    echo "  Toolchain Verification"
    echo "=============================================="

    local ALL_OK=true

    check_tool() {
        local name="$1" cmd="$2"
        local version
        version=$(eval "$cmd" 2>&1 | head -1) || true
        if [ -n "$version" ]; then
            printf "  %-20s %s\n" "$name" "$version"
        else
            printf "  %-20s %s\n" "$name" "NOT FOUND"
            ALL_OK=false
        fi
    }

    check_tool "Go"             "go version"
    check_tool "Rust"           "rustc --version"
    check_tool "cargo-nextest"  "cargo nextest --version"
    check_tool "Python (uv)"    "uv python find ${PYTHON_VERSION}"
    check_tool "uv"             "uv --version"
    check_tool "Bun"            "bun --version"
    check_tool "Java"           "java --version"
    check_tool "Mill"           "mill version"
    check_tool "xmake"          "xmake --version | head -1 | sed 's/\x1b\[[0-9;]*m//g'"
    check_tool "Docker"         "docker --version"
    check_tool "kubectl"        "kubectl version --client --short 2>/dev/null || kubectl version --client"
    check_tool "helm"           "helm version --short"
    check_tool "kustomize"      "kustomize version | head -1"
    check_tool "yq"             "yq --version"
    check_tool "jq"             "jq --version"
    check_tool "cmake"          "cmake --version | head -1"
    check_tool "pkg-config"     "pkg-config --version"

    echo ""
    echo "  System libraries:"
    printf "  %-20s %s\n" "OpenSSL" "$(pkg-config --modversion openssl 2>/dev/null || echo 'NOT FOUND')"
    printf "  %-20s %s\n" "libcurl" "$(pkg-config --modversion libcurl 2>/dev/null || echo 'NOT FOUND')"
    printf "  %-20s %s\n" "libsasl2" "$(pkg-config --modversion libsasl2 2>/dev/null || echo 'NOT FOUND')"

    echo ""
    if $ALL_OK; then
        echo "  All tools verified!"
    else
        echo "  WARNING: Some tools are missing. Check output above."
    fi
    echo "=============================================="
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    echo "=============================================="
    echo "  DataOps/MLOps Platform — Toolchain Setup"
    echo "=============================================="
    echo ""

    install_system_packages
    configure_dns

    if [[ "$SKIP_DOCKER" != "1" ]]; then
        install_docker
    else
        info "Skipping Docker (SKIP_DOCKER=1)"
    fi

    if [[ "$SKIP_K3S" != "1" ]]; then
        install_k3s
        configure_sysctl
    else
        info "Skipping k3s (SKIP_K3S=1)"
    fi

    # Cluster CLIs (always installed — needed by Makefile/preflight)
    install_helm
    install_kustomize
    install_yq

    if [[ "$SKIP_BUILD_TOOLS" != "1" ]]; then
        install_go
        install_rust
        install_python
        install_bun
        install_java
        install_mill
        install_xmake
    else
        info "Skipping build tools (SKIP_BUILD_TOOLS=1)"
    fi

    verify_all

    echo ""
    echo "Setup complete. If this is a new shell, run:"
    echo "  source ~/.profile && source ~/.cargo/env 2>/dev/null"
    echo ""
    echo "Next steps:"
    echo "  cd ~/documents/ta && make preflight && make phase-base"
}

main "$@"
