# Multi-stage build for Go REST collector
FROM golang:1.26-alpine3.23 AS builder

WORKDIR /app

# Install dependencies
RUN for i in 1 2 3 4 5; do apk add --no-cache git && break || sleep 5; done

# Copy go mod files
COPY go.mod go.sum* ./
RUN go mod download

# Build arg to bust Docker cache when source changes.
# Pass --build-arg BUILD_HASH=$(git rev-parse --short HEAD) from Makefile.
ARG BUILD_HASH=dev

# Copy source (cache invalidated when BUILD_HASH changes)
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-w -s -X main.buildHash=${BUILD_HASH}" -o rest-collector ./cmd/main.go

# Runtime image
FROM alpine:3.23

RUN for i in 1 2 3 4 5; do apk add --no-cache ca-certificates tzdata && break || sleep 5; done && \
    addgroup -g 1000 -S app && adduser -u 1000 -S app -G app

WORKDIR /app

COPY --from=builder /app/rest-collector .

USER 1000:1000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

EXPOSE 8080

ENTRYPOINT ["./rest-collector"]
