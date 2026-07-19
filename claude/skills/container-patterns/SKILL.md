---
name: Container Patterns
description: Use when writing Dockerfiles, docker-compose files, Kubernetes manifests, or Helm charts — multi-stage builds, compose conventions, K8s deployment/service patterns, k3s specifics
globs: ["**/Dockerfile*", "**/docker-compose*.yml", "**/docker-compose*.yaml", "**/.dockerignore", "**/k8s/**", "**/kubernetes/**", "**/helm/**", "**/charts/**", "**/manifests/**"]
---

# Container Patterns

## Multi-Stage Builds
- Stage 1 (deps): install dependencies with lockfile
- Stage 2 (build): compile/bundle application
- Stage 3 (production): copy only built artifacts, use distroless/slim base
- Pin base image versions with SHA digests for reproducibility

## TypeScript/Bun Services
```dockerfile
FROM oven/bun:1 AS deps
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

FROM oven/bun:1 AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN bun run build

FROM oven/bun:1-slim AS production
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY --from=deps /app/node_modules ./node_modules
USER nonroot
CMD ["bun", "run", "dist/index.js"]
```

## Python Services
```dockerfile
FROM python:3.12-slim AS deps
RUN pip install uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

FROM python:3.12-slim AS production
COPY --from=deps /app/.venv ./.venv
COPY . .
USER nonroot
CMD [".venv/bin/python", "-m", "uvicorn", "main:app"]
```

## Compose Conventions
- Use profiles for optional services
- Named volumes for persistent data
- Health checks on all services
- Dependency ordering with depends_on + condition: service_healthy

## Kubernetes Deployment Conventions
- Always set resource requests AND limits
- Use rolling update strategy with maxSurge=1, maxUnavailable=0
- Include readiness and liveness probes on all containers
- Use configmaps for non-sensitive config, secrets for sensitive data
- Set pod disruption budgets for production workloads

## Kubernetes Service Patterns
- ClusterIP for internal services
- NodePort only for development
- Ingress with TLS termination for external access
- Use service mesh (Traefik) for mTLS between services

## Helm Charts
- Values files per environment: values-dev.yaml, values-staging.yaml, values-prod.yaml
- Use helpers/_helpers.tpl for common labels and selectors
- Pin image tags, never use :latest in production

## k3s Specifics
- Traefik is built-in as ingress controller
- Use local-path-provisioner for PVCs in single-node
- Use Longhorn for multi-node persistent storage
