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
#     -f use-case-crypto/services/ingestion/websocket-collector/Dockerfile \
#     -t crypto-websocket-collector:latest \
#     .
# =============================================================================

FROM rust:1.95-alpine3.23 AS builder
RUN for i in 1 2 3 4 5; do apk add --no-cache musl-dev cmake make pkgconfig openssl-dev openssl-libs-static g++ mold clang curl-dev zlib-dev zlib-static && break || sleep 5; done
ENV RUSTFLAGS="-C linker=clang -C link-arg=-fuse-ld=mold"

WORKDIR /build

# Copy the platform library crate first (stable layer — only rebuilds when
# platform sources change).
COPY platform/services/ingestion/websocket-collector \
     platform/services/ingestion/websocket-collector

# Copy the crypto binary crate (this is the one under active development).
COPY use-case-crypto/services/ingestion/websocket-collector \
     use-case-crypto/services/ingestion/websocket-collector

WORKDIR /build/use-case-crypto/services/ingestion/websocket-collector
RUN cargo build --release --bin crypto-websocket-collector

FROM alpine:3.23
RUN for i in 1 2 3 4 5; do apk add --no-cache ca-certificates && break || sleep 5; done
COPY --from=builder \
     /build/use-case-crypto/services/ingestion/websocket-collector/target/release/crypto-websocket-collector \
     /usr/local/bin/
USER 1000
EXPOSE 8080
CMD ["crypto-websocket-collector"]
