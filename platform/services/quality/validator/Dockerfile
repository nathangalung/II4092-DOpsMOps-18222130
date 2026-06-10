FROM rust:1.95-slim-trixie AS builder

WORKDIR /app

RUN for i in 1 2 3 4 5; do apt-get update && break || sleep 5; done && \
    apt-get install -y pkg-config libssl-dev libcurl4-openssl-dev zlib1g-dev cmake build-essential mold clang && \
    rm -rf /var/lib/apt/lists/*

ENV RUSTFLAGS="-C linker=clang -C link-arg=-fuse-ld=mold"

COPY Cargo.toml Cargo.lock* ./
COPY src ./src

# Cargo caches (BuildKit): a shared registry cache dedupes crate downloads across
# every Rust service; a per-service target cache keeps incremental compile
# artifacts across rebuilds even when `COPY src` busts the layer (the prior
# layout recompiled every crate from scratch on any source edit). A cache mount
# is NOT persisted into the image layer, so the release binary is copied to
# /artifacts (an ordinary dir) inside the SAME RUN for the runtime stage to COPY
# out — removing that cp breaks the cross-stage copy.
RUN --mount=type=cache,id=cargo-registry,target=/usr/local/cargo/registry \
    --mount=type=cache,id=cargo-target-validator,target=/app/target \
    cargo build --release && \
    mkdir -p /artifacts && cp /app/target/release/validator /artifacts/

FROM debian:trixie-slim

RUN for i in 1 2 3 4 5; do apt-get update && break || sleep 5; done && \
    apt-get install -y ca-certificates libssl3t64 libcurl4t64 && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -u 1000 -m -s /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder /artifacts/validator .

USER 1000:1000

EXPOSE 8082

ENTRYPOINT ["./validator"]
