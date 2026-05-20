FROM rust:1.95-alpine3.23 AS builder
RUN for i in 1 2 3 4 5; do apk add --no-cache musl-dev cmake make pkgconfig openssl-dev openssl-libs-static g++ mold clang curl-dev zlib-dev zlib-static && break || sleep 5; done
ENV RUSTFLAGS="-C linker=clang -C link-arg=-fuse-ld=mold"
WORKDIR /app
COPY Cargo.toml Cargo.lock* ./
COPY src ./src
RUN cargo build --release

FROM alpine:3.23
RUN for i in 1 2 3 4 5; do apk add --no-cache ca-certificates && break || sleep 5; done
COPY --from=builder /app/target/release/websocket-collector /usr/local/bin/
USER 1000
EXPOSE 8080
CMD ["websocket-collector"]
