Scaffold a new microservice named $ARGUMENTS in the monorepo.

Create the following structure:
```
apps/$ARGUMENTS/
  src/
    index.ts          # Hono app entry point with health/ready endpoints
    routes/           # Route handlers
    services/         # Business logic layer
    repositories/     # Data access layer
  Dockerfile          # Multi-stage build
  package.json        # Dependencies
  tsconfig.json       # TypeScript config extending root
  biome.json          # Extends root biome config
```

Include:
- Hono app with CORS, logging (hono-pino), error middleware
- Health check (GET /health) and readiness probe (GET /ready)
- Zod env validation at startup (packages/config pattern)
- Drizzle DB connection from packages/db
- NATS connection for event publishing/subscribing
- Correlation ID middleware (X-Request-ID)
- OpenAPI docs via @hono/zod-openapi + @scalar/hono-api-reference
- Docker multi-stage build (Bun)
- Add to docker-compose.yml and turbo.json
