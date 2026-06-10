FROM rust:1.95-slim-trixie AS builder

WORKDIR /app

RUN for i in 1 2 3 4 5; do apt-get update && break || sleep 5; done && \
    apt-get install -y pkg-config libssl-dev protobuf-compiler mold clang && \
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
    --mount=type=cache,id=cargo-target-gateway,target=/app/target \
    cargo build --release && \
    mkdir -p /artifacts && cp /app/target/release/serving-gateway /artifacts/

FROM debian:trixie-slim

# libssl3t64 (NOT libssl3): Debian trixie completed the 64-bit time_t transition,
# so the OpenSSL 3 runtime package is libssl3t64. `libssl3` has no installation
# candidate in trixie and would fail the build.
RUN for i in 1 2 3 4 5; do apt-get update && break || sleep 5; done && \
    apt-get install -y ca-certificates libssl3t64 && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -u 1000 -m -s /usr/sbin/nologin app

COPY --from=builder /artifacts/serving-gateway /usr/local/bin/

USER 1000:1000

EXPOSE 8080 8081 8082

CMD ["serving-gateway"]
