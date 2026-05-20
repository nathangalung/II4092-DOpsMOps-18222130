# Dashboard backend Dockerfile.
FROM golang:1.26-alpine3.23 AS builder

WORKDIR /app

# Install dependencies
RUN for i in 1 2 3 4 5; do apk add --no-cache git && break || sleep 5; done

# Copy go mod files
COPY go.mod go.sum* ./
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-w -s" -o /dashboard-backend ./cmd/main.go

# Final stage
FROM alpine:3.23

# Retry apk to handle intermittent DNS failures
RUN for i in 1 2 3 4 5; do apk --no-cache add ca-certificates tzdata && break || sleep 5; done && \
    addgroup -g 65532 -S nonroot && adduser -u 65532 -S nonroot -G nonroot

WORKDIR /app

COPY --from=builder --chown=65532:65532 /dashboard-backend .

USER 65532:65532

EXPOSE 8080

ENTRYPOINT ["./dashboard-backend"]
