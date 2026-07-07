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

# Install Xmake from source, pinned to v2.9.9 - the last 2.9.x release (satisfies
# set_xmakever("2.9.0") in xmake.lua), tagged 2025-04 so within the April-2026
# cap, and before the 3.0 major bump that could shift codegen. The prior
# /releases/latest/ URL was unpinned: non-reproducible and liable to pull a
# post-cap build. (Source tarball, not xmake.io - avoids that host's DNS.)
RUN curl -fsSL https://github.com/xmake-io/xmake/releases/download/v2.9.9/xmake-master.tar.gz -o /tmp/xmake.tar.gz && \
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

# Runtime libs match builder ABI
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgrpc++-dev \
    libprotobuf-dev \
    && rm -rf /var/lib/apt/lists/* \
    && userdel -r ubuntu 2>/dev/null || true \
    && useradd -u 1000 -m -s /usr/sbin/nologin app

COPY --from=builder /opt/onnxruntime/lib/* /usr/local/lib/
COPY --from=builder /app/build/linux/x86_64/release/inference-engine /usr/local/bin/

RUN ldconfig

USER 1000:1000

EXPOSE 50052

CMD ["inference-engine"]
