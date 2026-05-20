FROM rust:1.95-alpine3.23 AS builder

RUN for i in 1 2 3 4 5; do apk add --no-cache musl-dev pkgconfig openssl-dev openssl-libs-static curl-dev zlib-dev zlib-static cmake make g++ mold clang && break || sleep 5; done
ENV RUSTFLAGS="-C linker=clang -C link-arg=-fuse-ld=mold"

WORKDIR /app

COPY Cargo.toml Cargo.lock* ./
COPY src ./src

RUN cargo build --release

FROM alpine:3.23

RUN for i in 1 2 3 4 5; do apk add --no-cache ca-certificates libgcc && break || sleep 5; done && \
    addgroup -g 1000 -S app && adduser -u 1000 -S app -G app

WORKDIR /app

COPY --from=builder /app/target/release/validator .

USER 1000:1000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8082/health || exit 1

EXPOSE 8082

ENTRYPOINT ["./validator"]
