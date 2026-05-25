# IO Cascade — Architectural Decision Required

**Status:** BLOCKED on user decision. Fix attempt #6 same class — STOP per systematic-debugging Phase 4.5.

## Symptom

Recurring cluster-wide IO stall: PSI io.some avg10=85.89%, full avg10=72.77%, avg300=66.18% sustained. k3s "database is locked" on basic ops. Pod restart storms (all 4 sampled controllers terminated simultaneously at 2026-05-21T05:28:30Z). kubectl apply timeouts. ArgoCD repo-server gRPC hangs.

## Root Cause (this round)

**kine SQLite WAL grew to 9.0 GB.**

```
/var/lib/rancher/k3s/server/db/state.db-wal   9.0G   (normal <100MB)
/var/lib/rancher/k3s/server/db/state.db       332M
/var/lib/rancher/k3s/server/db/state.db-shm    18M
```

k3s journal shows Slow SQL INSERTs taking 22–32 seconds. fsync throughput on one ext4 spindle (sda) < write rate from ~30 controllers writing leases/status continuously → WAL grows unbounded → reads must walk 9 GB WAL → PSI saturates → controllers timeout → controllers restart → more writes → cascade.

Cascade trigger this round: self-inflicted argocd-application-controller restart 35 min prior to t=0.

## Fix Attempt History (Same Class)

| # | Task | Approach | Result |
|---|------|----------|--------|
| 1 | #160 | Resource limits on controllers | Cascade returned |
| 2 | #166 | Lease duration tuning | Cascade returned |
| 3 | #169 | Reduce sync frequency | Cascade returned |
| 4 | #209 | Throttle ArgoCD reconciliation | Cascade returned |
| 5 | #214 | ClickHouse IO isolation | Cascade returned |
| 6 | #307 | (this round, abandoned) | STOP per skill |

Pattern: tactical fixes only delay. Underlying disk bandwidth × write rate ratio unchanged. No tactical fix will hold.

## Architectural Options

| Option | Action | Mandate Impact | Recovery | Risk |
|--------|--------|---------------|----------|------|
| **A. Embedded etcd** | `k3s server --cluster-init` (drop kine, embedded etcd backend) | Preserves single-node + 1-replica mandate | `make phase-full` rerun | Medium — requires k3s reconfiguration; etcd memory overhead ~200Mi |
| **B. Scale-0 idle operators** | Scale truly-idle operators to 0; KEDA wakes on event | **Bends** "1 replica idle" mandate (some workloads = 0 idle) | Patch deployments | Low — but conflicts with stated invariant |
| **C. Scope cut** | Drop optional operators (chaos-mesh, snapshot-controller, spark-operator-prod, others) | Preserves invariant on remaining workloads | Remove from AppSet, kustomize | Medium — removes MLOps L2 features |
| **D. Faster kine storage** | Move `/var/lib/rancher/k3s/server/db` to NVMe or tmpfs | Preserves all mandates | Stop k3s, rsync db, symlink, start k3s | Hardware change — NVMe needed; tmpfs loses on reboot |

## Recommendation

**Option A** — k3s embedded etcd via `--cluster-init`.

Reasoning:
- Preserves "single-node, 1 replica idle, HPA/KEDA scale on load" mandate verbatim
- Etcd handles ~30 controller write rate with margin (well-tested at scale)
- No hardware change required
- Cleanest structural fix; eliminates SQLite as the bottleneck root cause permanently
- Standard production K8s pattern (embedded etcd is the k3s HA default)

Trade-off: ~200Mi etcd memory overhead, one-time `make phase-full` rerun for full reconciliation.

## Acute Relief (regardless of chosen path)

`sudo systemctl restart k3s` forces SQLite WAL checkpoint → drops 9 GB → ~0 immediately. Buys 1–7 days before WAL grows again. **User-level action only** (sudo).

## What Triggered the Pause

`superpowers:systematic-debugging` skill Phase 4.5:

> **If 3+ Fixes Failed: Question Architecture**
> Pattern indicating architectural problem: Each fix reveals new shared state/coupling/problem in different place. Fixes require "massive refactoring" to implement. Each fix creates new symptoms elsewhere.
> **STOP and question fundamentals.** Discuss with your human partner before attempting more fixes.

This is fix attempt #6. Pattern confirmed. Decision required.

## Decision Owner

User. Bends mandates → user must approve. Requires sudo → user must execute.

---

*Generated 2026-05-21. References task #307, #317. See `superpowers:systematic-debugging`.*
