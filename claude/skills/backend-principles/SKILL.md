---
name: Backend Development Principles
description: Use when designing APIs, services, or database schemas, or reasoning about distributed systems — CAP/PACELC, ACID/BASE, resilience patterns, API/DB design
globs: ["**/*.ts", "**/*.go", "**/*.py", "**/*.rs", "**/*.java", "**/routes/**", "**/services/**", "**/repositories/**", "**/api/**", "**/controllers/**", "**/handlers/**"]
---

# Backend Development Principles & Laws

Sources: "Designing Data-Intensive Applications" (Kleppmann), "Release It!" (Nygard), "Clean Architecture" (Martin), "Domain-Driven Design" (Evans)

## DDIA Core Principles (Kleppmann)

### Three Pillars of Data Systems
1. **Reliability**: system works correctly even when faults occur (hardware, software, human error)
2. **Scalability**: system handles growth in data/traffic/complexity gracefully
3. **Maintainability**: system is easy for engineers to work on over time

### Maintainability Breakdown
- **Operability**: easy for ops to keep running (health dashboards, graceful degradation, predictable behavior)
- **Simplicity**: easy for new engineers to understand (remove accidental complexity, good abstractions)
- **Evolvability**: easy to change for new requirements (loosely coupled, well-defined interfaces)

## Distributed Systems Laws

### CAP Theorem (Brewer)
"Pick 2 of 3: Consistency, Availability, Partition Tolerance."
- Network partitions WILL happen — you must handle them
- CP: sacrifice availability for consistency (banks, ledgers, escrow)
- AP: sacrifice consistency for availability (feeds, caches, notifications)

### PACELC (Extension of CAP)
"If Partition → A or C. Else → Latency or Consistency."
- Even without partitions, latency-consistency tradeoff exists
- Read replicas: fast but possibly stale (AP + EL)
- Primary reads: consistent but slower (CP + EC)

### ACID (Transactions)
- **Atomicity**: all or nothing → `db.transaction()`
- **Consistency**: valid state before and after → constraints + checks
- **Isolation**: concurrent transactions don't interfere
- **Durability**: committed data survives crashes
- When to use: payments, state machine transitions, multi-table writes

### BASE (Eventually Consistent)
- **Basically Available** + **Soft State** + **Eventually Consistent**
- When to use: read-heavy analytics, activity feeds, search indexes

### Two Generals / Byzantine Generals
- You can never be 100% sure both sides acknowledged a message
- Implication: idempotency is MANDATORY in distributed systems

## API Design Principles

### API Versioning: URL-based `/api/v1/resource` (simple, cacheable)
### Pagination: cursor-based for real-time, offset for stable. Default 20, max 100. NEVER return all
### Rate Limiting: token bucket for APIs, sliding window for abuse prevention. 429 + Retry-After header
### Response Envelope: `{ success, data, error: { code, message } }`
### Robustness: accept flexible input, return strict output

## Database Principles

### Normalization (Codd): 1NF → 2NF → 3NF → BCNF. Denormalize ONLY after profiling proves bottleneck
### N+1 is #1 killer: always eager-load or batch. EXPLAIN before optimizing
### Connection pool: `pool_size = (core_count * 2) + effective_spindle_count`
### Constraints at DB level: CHECK, UNIQUE, FK, NOT NULL — not just app logic
### Migrations: additive only in production (add columns, never rename/drop in same deploy)
### Double-entry for money: every movement = debit + credit summing to zero

## Messaging & Event Patterns

### Events are facts (past tense, immutable), Commands are requests (imperative, may fail), Queries are questions (no side effects)
### Exactly-once delivery is impossible. At-least-once + idempotent consumer = exactly-once processing
### Outbox Pattern: write event to outbox table in SAME transaction as business data. Background worker publishes to NATS
### Saga (Temporal orchestration for complex flows, NATS choreography for simple fan-out)

## DDD Principles (Eric Evans)

### Strategic Patterns
- **Bounded Context**: each microservice owns a clear domain boundary
- **Ubiquitous Language**: same terminology in code, database, conversations, docs
- **Context Mapping**: define relationships between bounded contexts (upstream/downstream, conformist, anti-corruption layer)

### Tactical Patterns
- **Aggregate Root**: cluster of domain objects treated as single unit for data changes
- **Value Object**: immutable, equality by value (e.g., Money, Address, EmailAddress)
- **Domain Event**: significant occurrence in the domain ("OrderPlaced", "MilestoneApproved")
- **Repository**: abstraction for data access, hides persistence details from domain

## Clean Architecture Layers (Robert C. Martin)
```
Route Handler (HTTP) → Service (Business Logic) → Repository (Data Access)
```
- Dependencies point inward: outer layers depend on inner, never reverse
- Business logic has ZERO knowledge of HTTP, database, or frameworks
- Domain entities are plain objects with no framework decorators

## Resilience Patterns (Nygard)

### Circuit Breaker: Closed → Open (fail fast) → Half-Open (test recovery)
Config: threshold 5 failures → open, 30s reset → half-open, 3 successes → closed

### Retry: `delay = min(base * 2^attempt + random_jitter, max_delay)`
Base 1s, factor 2x, max 30s, jitter ±500ms. Idempotent operations ONLY

### Bulkhead: separate pools per downstream service. Payment down ≠ project service blocked

### Timeout: NEVER wait forever. Set explicit timeouts on every external call

### Graceful Degradation: AI down → cached results + "estimates may be outdated" banner

### Shed Load: when overloaded, reject new requests (429) rather than slow all requests

## Security Principles
- Defense in Depth: 7 layers (network → auth → authz → validation → logic → data → output)
- Least Privilege: minimum access required, revoke when done
- Zero Trust: authenticate every call, even internal service-to-service
- Fail Secure: auth failure → deny access (never fail open)
