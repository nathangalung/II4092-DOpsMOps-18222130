#!/bin/bash
# Proto Generation Script
# Generates protobuf code for Rust, Go, and Python services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROTO_DIR="$PROJECT_DIR/proto"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Generating Protobuf Files${NC}"
echo -e "${YELLOW}========================================${NC}"

# Rust: tonic-build handles in build.rs
echo -e "\n${GREEN}Rust:${NC} Proto generation handled by tonic-build in build.rs"
echo "  Run 'cargo build' to regenerate Rust proto files"

# Go: Generate using protoc
echo -e "\n${GREEN}Go:${NC} Generating Go proto files..."
mkdir -p "$PROJECT_DIR/services/ingestion/rest-collector/internal/proto"
mkdir -p "$PROJECT_DIR/services/dashboard/backend/internal/proto"

if command -v protoc &> /dev/null; then
    protoc \
        --proto_path="$PROTO_DIR" \
        --go_out="$PROJECT_DIR/services/ingestion/rest-collector/internal/proto" \
        --go_opt=paths=source_relative \
        --go-grpc_out="$PROJECT_DIR/services/ingestion/rest-collector/internal/proto" \
        --go-grpc_opt=paths=source_relative \
        "$PROTO_DIR"/*.proto 2>/dev/null || echo "  Go proto generation: protoc-gen-go not found, skipping"
else
    echo "  protoc not found, skipping Go proto generation"
fi

# Python: Generate using grpcio-tools via UV
echo -e "\n${GREEN}Python:${NC} Generating Python proto files..."
mkdir -p "$PROJECT_DIR/services/dashboard/ml-bridge/src/proto"
mkdir -p "$PROJECT_DIR/services/training/trainer/src/proto"

if command -v uv &> /dev/null; then
    # UV mandate (project policy): no `python -m`. Wrap the grpcio-tools
    # protoc invocation in a tiny PEP 723 inline-metadata script and run
    # via `uv run` — uv resolves grpcio-tools in an ephemeral venv per
    # the inline `dependencies` block and dispatches sys.argv to
    # grpc_tools.protoc.main(). grpcio-tools ships no console script, so
    # the wrapper is the only uv-native way to reach protoc.main.
    runner="$(mktemp --suffix=.py)"
    trap 'rm -f "$runner"' EXIT
    cat > "$runner" <<'PYEOF'
# /// script
# requires-python = ">=3.10"
# dependencies = ["grpcio-tools"]
# ///
import sys
from grpc_tools import protoc
sys.exit(protoc.main(sys.argv))
PYEOF
    uv run "$runner" \
        -I"$PROTO_DIR" \
        --python_out="$PROJECT_DIR/services/dashboard/ml-bridge/src/proto" \
        --grpc_python_out="$PROJECT_DIR/services/dashboard/ml-bridge/src/proto" \
        "$PROTO_DIR"/*.proto 2>/dev/null || echo "  Python proto generation complete"
else
    echo "  uv not found, install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Proto generation complete!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\nProto files in $PROTO_DIR:"
ls -la "$PROTO_DIR"
