FROM rust:1.95-slim-trixie AS builder

WORKDIR /app

RUN for i in 1 2 3 4 5; do apt-get update && break || sleep 5; done && \
    apt-get install -y pkg-config libssl-dev protobuf-compiler mold clang && \
    rm -rf /var/lib/apt/lists/*

ENV RUSTFLAGS="-C linker=clang -C link-arg=-fuse-ld=mold"

COPY Cargo.toml Cargo.lock* ./
COPY src ./src

RUN cargo build --release

FROM debian:trixie-slim

RUN for i in 1 2 3 4 5; do apt-get update && break || sleep 5; done && \
    apt-get install -y ca-certificates libssl3 && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -u 1000 -m -s /usr/sbin/nologin app

COPY --from=builder /app/target/release/feature-cache /usr/local/bin/

USER 1000:1000

EXPOSE 8080 50053

CMD ["feature-cache"]
