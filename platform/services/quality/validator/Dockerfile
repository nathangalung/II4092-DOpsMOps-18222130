FROM rust:1.95-slim-trixie AS builder

WORKDIR /app

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

COPY Cargo.toml Cargo.lock* ./
COPY src ./src

RUN cargo build --release

FROM debian:trixie-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3t64 \
    libcurl4t64 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -u 1000 -m -s /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder /app/target/release/validator .

USER 1000:1000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8082/health || exit 1

EXPOSE 8082

ENTRYPOINT ["./validator"]
