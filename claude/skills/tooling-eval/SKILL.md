---
name: Tooling Evaluation & Performance
description: Use when choosing, adding, or replacing dev tools, libraries, or dependencies, or setting up lint/build/test toolchains — selection criteria, best-in-class per-language picks, benchmark discipline
globs: ["**/package.json", "**/pyproject.toml", "**/requirements*.txt", "**/go.mod", "**/Cargo.toml", "**/build.gradle*", "**/pom.xml", "**/CMakeLists.txt", "**/Makefile"]
---

# Tooling Evaluation & Performance

Numbers below are order-of-magnitude guides from published benchmarks. Before citing a specific figure or version in user-facing output, verify against current benchmarks/docs (Context7 or the project's own benchmark page) — these age fast.

## Selection Criteria (All Must Pass)

### 1. Activity & Maintenance (CRITICAL)
- Last commit < 3 months (6 months max for stable/mature)
- Issues triaged, PRs reviewed, at least 2 active maintainers
- Release cadence: at least quarterly
- Red flags: "looking for maintainers", no releases in 12+ months, mass issue closure

### 2. Stability & Maturity
- Semantic versioning (v1.0+ for production)
- Breaking changes documented with migration guides
- Prefer: company-backed or foundation-backed (Apache, CNCF, Linux Foundation)

### 3. Performance
- Benchmarked against alternatives (own AND independent benchmarks)
- Systems language (Rust, Go, C) for tooling = strong perf signal

### 4. Ecosystem Fit
- Works with existing stack without heavy adaptation
- Good TypeScript types (JS ecosystem), plugin system, CI/CD compatible

### 5. License
MIT, Apache 2.0, BSD, ISC preferred. Avoid SSPL, BSL; flag AGPL for anything you might offer as a service.

## When to Replace / When Not
- Replace when: tool deprecated, unpatched CVEs, alternative is 3x+ faster AND equally stable
- Do NOT replace when: only marginally better, migration > 1 sprint, new tool < v1.0

## Best-in-Class Per Language

### JavaScript / TypeScript
| Task | Use | Not | Why |
|---|---|---|---|
| Runtime | Bun | Node.js | Much faster cold start, install, CPU-bound work. Caveat: real apps with DB+logic converge — the gap is in tooling, not steady-state HTTP |
| Bundler | Vite (Rolldown) | Webpack | Order-of-magnitude faster cold build and hot rebuild |
| Linter+Formatter | Biome | ESLint+Prettier | ~50x on large repos, single tool |
| Lint-only | oxlint | ESLint | Fastest lint pass; no formatter |
| Tests | Vitest | Jest | Native ESM+TS, Vite HMR |
| HTTP framework | Hono | Express | Multiples faster, less memory, runs on Bun/Workers/Node |
| ORM | Drizzle | Prisma | Thin SQL-first core, tiny bundle, avoids N+1 in complex queries |
| Git hooks | Lefthook | Husky | Go binary, no node_modules dependency, parallel |
| Static sites | Astro | Next.js (for static) | Zero JS by default, islands hydration |

### Python
| Task | Use | Not | Why |
|---|---|---|---|
| Packages | uv | pip / poetry | 10-100x installs, lockfile, replaces pyenv+pip-tools |
| Lint+Format | ruff | flake8/pylint/black | 100x+ class speedup, single tool |
| Types | pyright | mypy | Faster, stricter, better IDE integration |
| JSON | orjson / msgspec | json stdlib | Multiples faster both directions |

### Go
| Task | Use | Why |
|---|---|---|
| Linter | golangci-lint | 100+ linters parallel with caching |
| Security | govulncheck | Official, call-graph analysis not just dep matching |
| Build flags | -trimpath -ldflags="-s -w" | Substantially smaller binary |
| Test flags | -race -count=1 -shuffle=on | Catches data races + order-dependent tests |
| HTTP router | net/http (1.22+) | Stdlib has path params; drop gorilla/mux |

### Rust
| Task | Use | Why |
|---|---|---|
| Linker | mold | Multiples faster than lld/gold on big links |
| Compile cache | sccache | Caches across branches and CI |
| Tests | cargo-nextest | Parallel per-test, flaky retry |
| Security | cargo-audit + cargo-deny | CVE + license scanning in CI |

```toml
# .cargo/config.toml
[target.x86_64-unknown-linux-gnu]
linker = "clang"
rustflags = ["-C", "link-arg=-fuse-ld=mold"]
[build]
rustc-wrapper = "sccache"
```

### C / C++
| Task | Use | Why |
|---|---|---|
| Build | CMake + Ninja | Parallel incremental builds |
| Compile cache | ccache / sccache | Skips compilation on hit |
| Linker | mold / lld | Far faster than GNU ld |
| Sanitizers | ASan+UBSan | ~2x slowdown vs valgrind's 10-50x; catches more classes |
| Static analysis | clang-tidy | 300+ checks, auto-fix |

### Java
| Task | Use | Why |
|---|---|---|
| JDK | Current LTS (21+) + ZGC | Sub-ms GC pauses |
| Build | Gradle (cache on) | Incremental + parallel + cached |
| Native image | GraalVM | ms-startup, fraction of memory |
| Concurrency | Virtual threads (Loom) | Millions of threads, no pool tuning |

## Go-Based Infra Worth Defaulting To
Traefik (gateway/ingress), k3s (lightweight K8s), NATS (messaging), Temporal (workflows), Lefthook (git hooks).

## Observability & Infra Picks
OpenObserve or Grafana stack (dashboards/logs/traces), Uptime Kuma (status), Langfuse (LLM observability), Infisical (secrets), Coolify (self-hosted PaaS). Check licenses (several are AGPL).

## Modern CLI Replacements (Rust-based)
ripgrep→grep, fd→find, bat→cat, eza→ls, delta→diff, zoxide→cd, hyperfine→time, tokei→cloc, starship (prompt), atuin (history). Install via system package manager or `cargo binstall`.

## Universal Performance Rules
1. **Profile before optimizing** — perf, pprof, Chrome DevTools, py-spy
2. **Algorithm first** — O(n²)→O(n log n) beats any tool change
3. **Measure on production-like data** — micro-benchmarks lie
4. **Cache at the right layer** — CPU L1 > L2 > L3 > RAM > SSD > network
5. **Parallelize independent work** — but measure Amdahl's Law limit first

## Always Check Current Docs
Before implementing with any library, fetch up-to-date docs (Context7 MCP). Prevents deprecated APIs and stale patterns.
