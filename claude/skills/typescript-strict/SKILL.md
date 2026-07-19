---
name: TypeScript Strict Patterns
description: Use when writing or reviewing TypeScript — strict tsconfig, Bun, Biome, Zod, Hono, Drizzle conventions
globs: ["**/*.ts", "**/*.tsx", "**/tsconfig*.json", "**/biome.json"]
---

# TypeScript Strict Patterns

## Performance Setup
- Runtime: Bun (NOT Node.js — 3x faster startup, native TypeScript)
- Package manager: Bun (NOT npm/yarn/pnpm — 10-25x faster install)
- Bundler: Vite 8 with Rolldown (Rust-based, 10-30x faster than Webpack)
- Linter+Formatter: Biome (NOT ESLint+Prettier — 10-100x faster, Rust-based)
- Test runner: Vitest (NOT Jest — 2-5x faster, native ESM+TypeScript)
- Git hooks: Lefthook (Go binary, NOT Husky — no node_modules dependency)

## Type System
- `strict: true` always (tsconfig.json) — non-negotiable
- Prefer `type` over `interface` (unless declaration merging needed)
- NEVER use `any` — use `unknown` + type guards for unknown types
- Zod schemas as single source of truth, derive types: `type User = z.infer<typeof userSchema>`
- Discriminated unions for state: `type State = { type: "loading" } | { type: "error"; message: string } | { type: "success"; data: T }`
- `as const` objects + type helper instead of enums:
```typescript
const STATUS = { DRAFT: "draft", ACTIVE: "active" } as const;
type Status = (typeof STATUS)[keyof typeof STATUS]; // "draft" | "active"
```
- `readonly` arrays and objects by default
- No type assertions (`as`) unless provably safe — prefer type guards
- Named exports only (no default exports)
- Barrel exports (index.ts) per feature module

## Hono Backend (Clean Architecture)
```
Route Handler → Service → Repository
```
- Route handler: parse input (Zod via @hono/zod-validator), call service, return response
- Service: business logic, no HTTP knowledge, no direct DB access
- Repository: Drizzle queries, database-specific logic
- Error handling: centralized middleware, not per-handler try-catch
- Response format: `{ success: boolean, data?: T, error?: { code: string, message: string } }`
- OpenAPI: @hono/zod-openapi + @scalar/hono-api-reference (auto-generated from Zod)
- Type-safe client: hono/client (zero codegen — import route types directly)

## Drizzle ORM
- UUID v7 primary key: `import { uuidv7 } from "uuidv7"` (NOT crypto.randomUUID — v4 is random, bad for B-tree index locality)
- All timestamps: `timestamptz` stored in UTC, convert in frontend
- Schema split: one file per domain (auth.schema.ts, projects.schema.ts)
- Atomic operations: `db.transaction()` for multi-table writes
- Migrations: `drizzle-kit generate` → `drizzle-kit migrate` (never manual ALTER)
- Query builder for complex queries, `.query` API for simple relations

## React
- Functional components only — no class components
- Custom hooks for reusable logic (prefix `use`)
- **State management hierarchy**:
  - Component state: `useState` (local)
  - Server state: TanStack Query v5 (cached, deduplicated, background refetch)
  - Client state: Zustand v5 (sidebar, theme, modals) — use `useShallow` for array/object selectors
  - URL state: TanStack Router search params (shareable)
  - Form state: React Hook Form v7 + Zod resolver
- Data fetching: ALWAYS TanStack Query, NEVER fetch in useEffect
- All text: `useTranslation()` from react-i18next — zero hardcoded strings
- Code splitting: automatic via TanStack Router file-based routes
- Loading: skeleton loaders (NOT spinners on blank pages)
- Errors: error boundary per section (NOT whole page crash)
- Optimistic updates for frequent actions (like, apply, toggle)
- Memoization (`useMemo`/`useCallback`): ONLY when profiled as needed

## Biome Config
```json
{
  "$schema": "https://biomejs.dev/schemas/2.0/schema.json",
  "linter": { "enabled": true },
  "formatter": { "enabled": true, "indentStyle": "space", "indentWidth": 2 }
}
```
- `biome check --write` replaces both eslint --fix and prettier --write
- `biome check --write --staged` for git hooks (via Lefthook)
