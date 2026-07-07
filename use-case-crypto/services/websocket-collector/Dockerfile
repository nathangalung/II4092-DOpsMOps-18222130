# use-case-crypto :: crypto-websocket-collector image
# Builds the Coinbase-specific binary that path-depends on the platform's
# `websocket-collector` library crate. The platform crate lives at a sibling
# path, so the build context MUST be the repository root (not this directory)
# so Cargo can resolve the relative `path = "..."` dependency.
#
# Build command (from repo root):
#   docker build \
#     -f use-case-crypto/services/websocket-collector/Dockerfile \
#     -t crypto-websocket-collector:latest \
#     .

FROM rust:1.95-slim-trixie AS builder

RUN for i in 1 2 3 4 5; do apt-get update && break || sleep 5; done && \
    apt-get install -y \
    pkg-config \
    libssl-dev \
    libcurl4-openssl-dev \
    zlib1g-dev \
    cmake \
    build-essential \
    mold \
    clang \
    && rm -rf /var/lib/apt/lists/*

ENV RUSTFLAGS="-C linker=clang -C link-arg=-fuse-ld=mold"

WORKDIR /build

# Copy the platform library crate first (stable layer - only rebuilds when
# platform sources change).
COPY platform/services/ingestion/websocket-collector \
     platform/services/ingestion/websocket-collector

# Copy the crypto binary crate (this is the one under active development).
COPY use-case-crypto/services/websocket-collector \
     use-case-crypto/services/websocket-collector

WORKDIR /build/use-case-crypto/services/websocket-collector

# Cargo caches (BuildKit): shared registry (dedupes crate downloads across all
# Rust services) + a target cache so incremental compile artifacts survive
# rebuilds even when the source COPY busts the layer. The target dir is a cache
# mount - NOT persisted into the image layer - so the binary is copied to
# /artifacts inside the SAME RUN for the runtime stage to COPY out; removing that
# cp breaks the cross-stage copy.
RUN --mount=type=cache,id=cargo-registry,target=/usr/local/cargo/registry \
    --mount=type=cache,id=cargo-target-crypto-wsc,target=/build/use-case-crypto/services/websocket-collector/target \
    cargo build --release --bin crypto-websocket-collector && \
    mkdir -p /artifacts && cp target/release/crypto-websocket-collector /artifacts/

FROM debian:trixie-slim

RUN for i in 1 2 3 4 5; do apt-get update && break || sleep 5; done && \
    apt-get install -y \
    ca-certificates \
    libssl3t64 \
    libcurl4t64 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -u 1000 -m -s /usr/sbin/nologin app

COPY --from=builder /artifacts/crypto-websocket-collector /usr/local/bin/

USER 1000:1000
EXPOSE 8080
CMD ["crypto-websocket-collector"]
