---
name: DevOps & SRE Principles
description: Use when setting up CI/CD, deployments, monitoring, or incident response — DORA metrics, SRE error budgets, IaC, observability, deployment strategies
globs: ["**/Dockerfile*", "**/docker-compose*", "**/*.yaml", "**/*.yml", "**/k8s/**", "**/terraform/**", "**/.github/**", "**/Makefile", "**/scripts/**", "**/infra/**", "**/deploy/**"]
---

# DevOps & SRE Principles & Laws

Sources: "The Phoenix Project" (Kim), "The DevOps Handbook" (Kim/Humble/Debois), "Accelerate" (Forsgren/Humble/Kim), "Site Reliability Engineering" (Google), "Release It!" (Nygard)

## The Three Ways (DevOps Handbook)

### First Way: Flow (Systems Thinking)
"Optimize the entire value stream, not individual steps."
- Reduce batch sizes (small PRs, frequent deploys)
- Limit work in progress (WIP limits)
- Eliminate bottlenecks (automate manual gates)
- Make work visible (kanban boards, deployment dashboards)

### Second Way: Feedback
"Create fast, constant feedback loops at every stage."
- Fail fast: CI catches errors in minutes, not days
- Shift left: test/security scan early
- Telemetry everywhere: know before users report
- Blameless post-mortems: learn from failure, don't punish

### Third Way: Continuous Learning
"Create a culture of experimentation and learning."
- Chaos engineering: inject failures to learn
- Game days: practice incident response
- 20% time for tooling improvements

## DORA Metrics (Accelerate Book — Forsgren, Humble, Kim)

The four key metrics that predict software delivery and organizational performance, validated by 7+ years of research across 36,000+ professionals:

### Throughput Metrics
1. **Deployment Frequency**: how often you deploy to production
   - Elite: on-demand (multiple times/day)
   - High: weekly to monthly
   - Medium: monthly to every 6 months
   - Low: every 6+ months

2. **Lead Time for Changes**: time from commit to production
   - Elite: < 1 hour
   - High: 1 day to 1 week
   - Medium: 1 week to 1 month
   - Low: 1 to 6 months

### Stability Metrics
3. **Change Failure Rate**: % of deployments causing incidents
   - Elite: 0-15%
   - High: 16-30%
   - Medium: 31-45%
   - Low: 46-60%

4. **Mean Time to Restore (MTTR)**: time to recover from incidents
   - Elite: < 1 hour
   - High: < 1 day
   - Medium: 1 day to 1 week
   - Low: 1 week to 1 month

### 5th Metric: Reliability (added 2021)
- Does the service meet its SLOs?
- Operational performance targets met?

**Key insight from Accelerate**: high performers are NOT trading speed for stability — they achieve BOTH. There is no speed-vs-quality tradeoff at the organizational level.

### Capabilities That Drive DORA Metrics
- Trunk-based development (short-lived branches)
- Continuous integration & delivery
- Automated testing (unit + integration + e2e)
- Loosely coupled architecture (microservices)
- Monitoring & observability
- Blameless post-mortems
- Work-in-progress limits

## CALMS Framework
- **Culture**: shared responsibility, no "throw over the wall"
- **Automation**: everything automatable should be automated
- **Lean**: eliminate waste, small batches, continuous flow
- **Measurement**: measure everything, decide with data (DORA metrics)
- **Sharing**: break silos, shared tools, shared on-call

## SRE Principles (Google)

### Service Level Hierarchy
- **SLI** (Indicator): what you measure (latency P95, error rate)
- **SLO** (Objective): target value (P95 latency < 500ms)
- **SLA** (Agreement): contract with consequences (99.9% uptime)
- **Error Budget**: 100% - SLO = allowed unreliability (99.9% = 43.2 min/month downtime)

### Error Budget Policy
- Budget > 50%: ship features freely
- Budget 20-50%: risk assessment required
- Budget exhausted: only reliability work until replenished

### Toil Elimination
"Toil = manual, repetitive, automatable, tactical, no enduring value."
- If you do it more than twice, automate it
- SREs spend <50% time on toil (target: 0%)

## Observability (Three Pillars + RED + USE + Golden Signals)

### Three Pillars
1. **Logs**: structured JSON, correlation IDs (Pino → OpenObserve)
2. **Metrics**: counters, gauges, histograms (OpenTelemetry → OpenObserve)
3. **Traces**: distributed request flow (OpenTelemetry → OpenObserve)

### RED Method (request-driven services)
- **R**ate: requests/second
- **E**rror: failed requests/second
- **D**uration: latency distribution (P50, P95, P99)

### USE Method (infrastructure resources)
- **U**tilization: % resource in use
- **S**aturation: queue length / work pending
- **E**rrors: error count from resource

### Golden Signals (Google SRE)
1. Latency (success vs error), 2. Traffic (req/s), 3. Errors (5xx rate), 4. Saturation (CPU/mem/queue)

## Infrastructure as Code

### Immutable Infrastructure
"Don't modify running infra — replace it." No SSH fixes, update code and redeploy.

### Cattle Not Pets
"Servers are numbered (cattle), not named (pets)." Any instance is replaceable in minutes.

### GitOps: infra in Git → PR review → automated reconciliation → drift detection

## Deployment Patterns
- **Blue-Green**: two envs, instant switch, instant rollback (2x cost)
- **Canary**: 5-10% traffic → monitor → gradually increase
- **Feature Flags** (Flagsmith): decouple deploy from release, kill switch
- **Rolling Updates**: replace instances one at a time, zero-downtime

## Chaos Engineering (Netflix)
1. Define steady state → 2. Hypothesize → 3. Inject real-world failure → 4. Disprove → 5. Minimize blast radius

## 12-Factor App (Heroku)
1. Codebase (one repo), 2. Dependencies (explicit), 3. Config (env vars), 4. Backing services (attached), 5. Build/release/run (separated), 6. Processes (stateless), 7. Port binding, 8. Concurrency (horizontal), 9. Disposability (fast start, graceful stop), 10. Dev/prod parity, 11. Logs (stdout), 12. Admin processes (one-off)

## Release It! Patterns (Michael Nygard)
- **Circuit Breaker**: closed → open → half-open (prevent cascading failure)
- **Bulkhead**: isolate failure domains (separate pools per service)
- **Timeout**: never wait forever for a response
- **Retry + Backoff**: exponential with jitter, idempotent only
- **Shed Load**: reject requests when overloaded (429) rather than slow everyone
- **Handshaking**: health checks before routing traffic to new instances
