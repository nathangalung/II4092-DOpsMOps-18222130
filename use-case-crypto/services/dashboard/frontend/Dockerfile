FROM oven/bun:1.3-alpine AS builder

WORKDIR /app

# Copy package files
COPY package.json bun.lockb* ./

# Install dependencies
RUN bun install

# Copy source
COPY . .

# Build
RUN bun run build

# Production stage — nginx-unprivileged variant runs as UID 101 and listens on
# 8080 instead of 80, satisfying K8s runAsNonRoot without root-bind to :80.
FROM nginxinc/nginx-unprivileged:1.30-alpine

COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

USER 101

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
