---
name: critical-audit
description: Use when reviewing code, architecture, a plan, or a claim before approval, merge, or deploy — and whenever the user asks "is this good / correct / ready / ok?". Runs an adversarial three-lens audit (saboteur, maintainer, security) that must surface concrete findings instead of rubber-stamping.
---

# Critical Audit

Adversarial review. The goal is to find what is wrong, not to confirm what is right. A review that finds nothing must justify itself harder than one that finds problems.

## Rules

1. **No rubber-stamping.** Each lens below must either produce at least one concrete finding or explicitly state what was checked and why it survived. "Looks good" without listed checks is an invalid result.
2. **Findings need evidence.** Every finding cites the file:line, the input that triggers it, or the doc/benchmark that contradicts it. No vibes-based objections either — a finding you cannot ground gets dropped, not softened into a hedge.
3. **Severity honestly.** critical (breaks/leaks/loses data) > warning (works but fragile or misleading) > nit (style). Do not inflate nits to look thorough; do not deflate criticals to be polite.
4. **Verify before reporting.** If a finding can be checked cheaply (run the test, trigger the path, read the callee), check it. Report CONFIRMED vs SUSPECTED explicitly.

## The three lenses

Run all three. For large diffs, spawn one subagent per lens in parallel.

### 1. Saboteur — "how does this fail in production?"
- Race conditions, partial failure, retries, idempotency
- Boundary inputs: empty, null, huge, negative, unicode, concurrent
- Resource leaks: connections, file handles, unbounded growth
- What happens when the dependency (DB, API, queue) is down or slow?

### 2. Maintainer — "what will the next person curse?"
- Misleading names, comments that lie, dead code left behind
- Hidden coupling; change here silently breaks there
- Missing or wrong tests (tests that assert nothing, mock the thing under test)
- Convention drift from the rest of the codebase

### 3. Security auditor — "what would an attacker do?"
- Injection (SQL/command/path), unsafe deserialization
- AuthN/AuthZ gaps: missing checks, IDOR, trust of client input
- Secrets in code/logs/errors; over-broad permissions
- Supply chain: new dependencies — pinned? maintained? necessary?

## Output format

```
VERDICT: approve | approve-with-fixes | reject
CRITICAL: <file:line — finding — evidence> (or "none — checked: <list>")
WARNING:  <...>
NIT:      <...>
```

Verdict must follow from findings: any unresolved critical → reject. Do not let a friendly verdict contradict your own findings list.
