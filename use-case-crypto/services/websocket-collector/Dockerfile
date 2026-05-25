# =============================================================================
# use-case-crypto :: crypto-websocket-collector image
# =============================================================================
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
# =============================================================================

FROM rust:1.95-slim-trixie AS builder

RUN apt-get update && apt-get install -y \
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

# Copy the platform library crate first (stable layer — only rebuilds when
# platform sources change).
COPY platform/services/ingestion/websocket-collector \
     platform/services/ingestion/websocket-collector

# Copy the crypto binary crate (this is the one under active development).
COPY use-case-crypto/services/websocket-collector \
     use-case-crypto/services/websocket-collector

WORKDIR /build/use-case-crypto/services/websocket-collector
RUN cargo build --release --bin crypto-websocket-collector

FROM debian:trixie-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3t64 \
    libcurl4t64 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -u 1000 -m -s /usr/sbin/nologin app

COPY --from=builder \
     /build/use-case-crypto/services/websocket-collector/target/release/crypto-websocket-collector \
     /usr/local/bin/

USER 1000:1000
EXPOSE 8080
CMD ["crypto-websocket-collector"]
