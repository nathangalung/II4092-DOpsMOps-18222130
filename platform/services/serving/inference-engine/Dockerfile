# Multi-stage build using Xmake + Mold (faster than CMake + make)
FROM ubuntu:26.04 AS builder

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    libgrpc++-dev \
    libprotobuf-dev \
    pkg-config \
    protobuf-compiler \
    protobuf-compiler-grpc \
    wget \
    mold \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Xmake from source (avoids xmake.io DNS dependency)
RUN curl -fsSL https://github.com/xmake-io/xmake/releases/latest/download/xmake-master.tar.gz -o /tmp/xmake.tar.gz && \
    mkdir -p /tmp/xmake-build && tar xzf /tmp/xmake.tar.gz -C /tmp/xmake-build --strip-components=1 && \
    cd /tmp/xmake-build && ./configure --prefix=/usr/local && make -j$(nproc) && make install && \
    rm -rf /tmp/xmake.tar.gz /tmp/xmake-build

# Download ONNX Runtime
WORKDIR /onnxruntime
RUN wget -q https://github.com/microsoft/onnxruntime/releases/download/v1.24.1/onnxruntime-linux-x64-1.24.1.tgz \
    && tar -xzf onnxruntime-linux-x64-1.24.1.tgz \
    && mv onnxruntime-linux-x64-1.24.1 /opt/onnxruntime

# Build application
WORKDIR /app
COPY xmake.lua ./
COPY src ./src
COPY proto ./proto

ENV XMAKE_ROOT=y
RUN xmake f -m release -y && xmake build inference-engine

# Runtime image
FROM ubuntu:26.04

RUN apt-get update && apt-get install -y \
    libgrpc++1.51t64 \
    libprotobuf32t64 \
    && rm -rf /var/lib/apt/lists/* \
    && userdel -r ubuntu 2>/dev/null || true \
    && useradd -u 1000 -m -s /usr/sbin/nologin app

COPY --from=builder /opt/onnxruntime/lib/* /usr/local/lib/
COPY --from=builder /app/build/linux/x86_64/release/inference-engine /usr/local/bin/

RUN ldconfig

USER 1000:1000

EXPOSE 50052

CMD ["inference-engine"]
