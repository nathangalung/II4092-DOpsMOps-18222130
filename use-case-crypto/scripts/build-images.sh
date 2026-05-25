#!/bin/bash
# =============================================================================
# Build Docker images for use-case-crypto services
# =============================================================================
# Usage:
#   ./scripts/build-images.sh           - Build all services
#   ./scripts/build-images.sh ingestion - Build only ingestion services
#
# Environment Variables:
#   SERVICES_SRC - Path to generic service source code (default: services-src)
#   VERSION      - Image tag (default: latest)
#   REGISTRY     - Docker registry (default: empty for local)
#   NO_CACHE     - Set to "true" to disable Docker cache
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVICES_SRC_DIR="${SERVICES_SRC:-$PROJECT_DIR/services-src}"
USECASE_SERVICES_DIR="$PROJECT_DIR/services"

# Configuration
VERSION="${VERSION:-latest}"
REGISTRY="${REGISTRY:-}"
NO_CACHE="${NO_CACHE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Build flags
BUILD_FLAGS=""
if [ "$NO_CACHE" = "true" ]; then
    BUILD_FLAGS="--no-cache"
fi

# =============================================================================
# SERVICE DEFINITIONS - All 17 services
# =============================================================================
# Format: "name:context_path:dockerfile_relative_path"

declare -A SERVICE_GROUPS

# Ingestion services (2)
SERVICE_GROUPS["ingestion"]="
rest-collector:ingestion/rest-collector:Dockerfile
websocket-collector:ingestion/websocket-collector:Dockerfile
"

# Quality services (2)
SERVICE_GROUPS["quality"]="
validator:quality/validator:Dockerfile
analyzer:quality/analyzer:Dockerfile
"

# Processing services (4)
SERVICE_GROUPS["processing"]="
batch-processing:processing/batch:Dockerfile
feature-engine:processing/stream/feature-engine:Dockerfile
stream-processor:processing/stream-processor:Dockerfile
vector-processing:processing/vector:Dockerfile
"

# Training services (2)
SERVICE_GROUPS["training"]="
trainer:trainer:Dockerfile
drift-detector:quality/drift:Dockerfile
"

# Serving services (3)
SERVICE_GROUPS["serving"]="
gateway:serving/gateway:Dockerfile
feature-cache:serving/feature-cache:Dockerfile
inference-engine:serving/inference-engine:Dockerfile
"

# Automation services (1)
SERVICE_GROUPS["automation"]="
materialization:automation/materialization:Dockerfile
"

# Dashboard services (3)
SERVICE_GROUPS["dashboard"]="
dashboard-backend:dashboard/backend:Dockerfile
ml-bridge:dashboard/ml-bridge:Dockerfile
dashboard-frontend:dashboard/frontend:Dockerfile
"

# All services combined
ALL_SERVICES=""
for group in "${!SERVICE_GROUPS[@]}"; do
    ALL_SERVICES+="${SERVICE_GROUPS[$group]}"
done

# =============================================================================
# FUNCTIONS
# =============================================================================

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

build_service() {
    local name=$1
    local context=$2
    local dockerfile=$3

    local base_context="$SERVICES_SRC_DIR/$context"
    local usecase_context="$USECASE_SERVICES_DIR/$context"

    # Determine image name
    local image_name="crypto-${name}:${VERSION}"
    if [ -n "$REGISTRY" ]; then
        image_name="${REGISTRY}/crypto-${name}:${VERSION}"
    fi

    if [ ! -d "$base_context" ]; then
        echo -e "${YELLOW}⚠ Skipping ${name}: directory not found ($base_context)${NC}"
        return 1
    fi

    if [ ! -f "$base_context/$dockerfile" ]; then
        echo -e "${YELLOW}⚠ Skipping ${name}: Dockerfile not found ($base_context/$dockerfile)${NC}"
        return 1
    fi

    # If use-case has overlay files, merge into temp dir before building
    local build_context="$base_context"
    local tmp_dir=""
    if [ -d "$usecase_context" ]; then
        tmp_dir=$(mktemp -d)
        cp -r "$base_context"/* "$tmp_dir"/
        cp -r "$usecase_context"/* "$tmp_dir"/
        build_context="$tmp_dir"
        echo -e "${YELLOW}Building ${name} (with use-case overlay)...${NC}"
    else
        echo -e "${YELLOW}Building ${name}...${NC}"
    fi

    echo "  Context:    $build_context"
    echo "  Image:      $image_name"

    local result=0
    if docker build $BUILD_FLAGS -t "$image_name" -f "$build_context/$dockerfile" "$build_context"; then
        echo -e "${GREEN}✓ Successfully built $image_name${NC}\n"
    else
        echo -e "${RED}✗ Failed to build $image_name${NC}\n"
        result=1
    fi

    # Clean up temp dir
    [ -n "$tmp_dir" ] && rm -rf "$tmp_dir"
    return $result
}

build_group() {
    local group=$1
    local services="${SERVICE_GROUPS[$group]}"

    if [ -z "$services" ]; then
        echo -e "${RED}Unknown service group: $group${NC}"
        echo "Available groups: ${!SERVICE_GROUPS[*]}"
        exit 1
    fi

    print_header "Building $group services"

    local built=0
    local failed=0
    local skipped=0

    while IFS= read -r line; do
        [ -z "$line" ] && continue

        IFS=':' read -r name context dockerfile <<< "$line"

        if build_service "$name" "$context" "$dockerfile"; then
            ((built++))
        else
            if [ -d "$SERVICES_SRC_DIR/$context" ]; then
                ((failed++))
            else
                ((skipped++))
            fi
        fi
    done <<< "$services"

    echo -e "${GREEN}Group $group: $built built, $skipped skipped, $failed failed${NC}"
}

build_all() {
    print_header "Building ALL use-case-crypto Docker images"

    local total_built=0
    local total_failed=0
    local total_skipped=0

    for group in ingestion quality processing training serving automation dashboard; do
        echo -e "\n${BLUE}── $group ──${NC}"
        local services="${SERVICE_GROUPS[$group]}"

        while IFS= read -r line; do
            [ -z "$line" ] && continue

            IFS=':' read -r name context dockerfile <<< "$line"

            if build_service "$name" "$context" "$dockerfile"; then
                ((total_built++))
            else
                if [ -d "$SERVICES_SRC_DIR/$context" ]; then
                    ((total_failed++))
                else
                    ((total_skipped++))
                fi
            fi
        done <<< "$services"
    done

    print_header "Build Summary"
    echo -e "${GREEN}✓ Built:   $total_built${NC}"
    echo -e "${YELLOW}⚠ Skipped: $total_skipped${NC}"
    echo -e "${RED}✗ Failed:  $total_failed${NC}"
}

show_help() {
    echo "Usage: $0 [group|service]"
    echo ""
    echo "Groups:"
    echo "  ingestion   - REST collector, WebSocket collector"
    echo "  quality     - Validator, Analyzer"
    echo "  processing  - Batch, Feature engine, Flink, Vector"
    echo "  training    - Trainer, Drift detector"
    echo "  serving     - Gateway, Feature cache, Inference engine"
    echo "  automation  - Materialization (retrain-on-drift = Argo CronWorkflow, not an image)"
    echo "  dashboard   - Backend, ML bridge, Frontend"
    echo ""
    echo "Examples:"
    echo "  $0                    # Build all services"
    echo "  $0 ingestion          # Build ingestion services only"
    echo "  $0 serving            # Build serving services only"
    echo ""
    echo "Environment:"
    echo "  VERSION=v1.0.0 $0     # Tag images with v1.0.0"
    echo "  NO_CACHE=true $0      # Build without cache"
    echo "  SERVICES_SRC=/path $0 # Override generic service source path"
}

# =============================================================================
# MAIN
# =============================================================================

echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  use-case-crypto Docker Image Builder${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Version: $VERSION"
echo "Registry: ${REGISTRY:-local}"
echo "Cache: $([ "$NO_CACHE" = "true" ] && echo "disabled" || echo "enabled")"
echo "Services source: $SERVICES_SRC_DIR"

# Connect to Minikube's Docker daemon
CLUSTER="${CLUSTER:-platform}"
echo -e "\n${YELLOW}Connecting to Minikube Docker daemon...${NC}"
if eval $(minikube -p "$CLUSTER" docker-env 2>/dev/null); then
    echo -e "${GREEN}✓ Connected to Minikube Docker${NC}"
else
    echo -e "${YELLOW}⚠ Could not connect to Minikube, using local Docker${NC}"
fi

# Parse arguments
case "${1:-all}" in
    -h|--help|help)
        show_help
        exit 0
        ;;
    all|"")
        build_all
        ;;
    ingestion|quality|processing|training|serving|automation|dashboard)
        build_group "$1"
        ;;
    *)
        echo -e "${RED}Unknown argument: $1${NC}"
        show_help
        exit 1
        ;;
esac

# Show built images
echo -e "\n${YELLOW}Built images:${NC}"
docker images | grep "crypto-" | head -20

echo -e "\n${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Build complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo "  1. Create namespace:  kubectl create namespace use-case-crypto"
echo "  2. Deploy services:   kubectl kustomize manifests/overlays/local --load-restrictor LoadRestrictionsNone | kubectl apply -f -"
echo "  3. Check status:      kubectl get pods -n use-case-crypto"
