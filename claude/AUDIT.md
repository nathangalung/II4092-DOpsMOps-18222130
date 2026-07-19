# Claude Code Setup Audit — 2026-07-19

Full critique of the original setup (`~/.claude/` + plugins + MCP + external tools), with evidence. Verdicts here explain what landed in this folder and why. Sources: direct inspection of every file, official Claude Code docs, GitHub/PyPI metadata for external tools.

## Verdict summary

| Area | Before | After | Net |
|---|---|---|---|
| Plugins | 22 enabled | 11 | −11 (redundant/heavy) |
| Skills | 22 | 18 + 3 parked | 2 defects fixed, 2 merges, all descriptions rewritten |
| Commands | 5 global | 2 global + 3 parked | collisions/redundancy removed |
| MCP | 1 broken | 1 fixed | token-savior never worked |
| Settings | 1 contradiction, 2 undocumented keys, budget truncation | cleaned | model/[1m] conflict resolved |
| CLAUDE.md | 8 bytes (`@RTK.md` only) | + critical/audit stance | anti-sycophancy layer added |

---

## 1. Broken things found (objective defects)

1. **token-savior MCP never worked.** Configured command was the literal README placeholder `/path/to/venv/bin/token-savior`. Fix: the PyPI package is `token-savior-recall` (the binary name differs from the package name); portable config is `uvx token-savior-recall`. Applied in `install.sh`.
2. **security-principles OWASP bodies were scrambled.** Prevention bullets were shifted against the 2025 renumbering: crypto content sat under A02 Security Misconfiguration, injection content under A03 Supply Chain, insecure-design content under A04 Crypto, misconfiguration content under A05 Injection, and A06 was still titled "Vulnerable and Outdated Components" (2021 name; absorbed into A03 in 2025 — A06:2025 is Insecure Design). All reassigned; A07/A09 renamed to 2025 titles. Anyone following the old file got wrong-category guidance.
3. **devops-sre DORA tiers were non-discriminating.** Change Failure Rate listed High 16–30% AND Medium 16–30%, with 31–45% unassigned. Fixed to 31–45% for Medium.
4. **Skill listing truncation.** `skillListingBudgetFraction: 0.02` silently dropped the descriptions of 2 skills (typescript-strict, ui-ux-laws) — their files were byte-clean; the harness cuts least-used descriptions when over budget. Fixed by raising to 0.03 AND shrinking the skill/plugin count.
5. **caveman temp-file leak.** The plugin's atomic-write helper orphans `~/.claude/.caveman-active.<pid>.<ts>` files when a hook dies mid-write; nothing ever cleans them (confirmed by reading the plugin source — no reaper exists). 13 stale files removed on the old machine; expect slow re-accumulation until fixed upstream.
6. **`kubectl delete` and 83 other dangerous rules in the project allowlist.** 721 accumulated permission rules in `documents/ta/.claude/settings.local.json`, including `Bash(kubectl delete:*)`, `Bash(sudo …)`, `Bash(helm uninstall *)`. Session cruft from a homelab project — NOT ported. The portable settings.json ships a small read-only allowlist instead; let each machine accumulate its own or use `/fewer-permission-prompts`.

## 2. Settings critique

- **`model: "claude-fable-5[1m]"` contradicted `CLAUDE_CODE_DISABLE_1M_CONTEXT=1`.** The env var wins (deployment-level cap; the suffix is stripped in matching and Fable is natively 1M anyway, so `[1m]` granted nothing). Resolved: model is now plain `claude-fable-5`; the 200K cap stays as the deliberate cost choice. Delete the env var if you ever want the full window.
- **`CLAUDE_CODE_SUBAGENT_MODEL=opus`** forces every subagent (including Explore/workflow agents and agents with `model:` frontmatter) to Opus. Kept as a cost decision, documented in README. Note it makes `agents/opus-reviewer.md`'s pin redundant-but-harmless.
- **`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1`** is a no-op on Fable 5 / Sonnet 5 / Opus 4.7+ (always adaptive since v2.1.111). Kept — harmless, still meaningful if you drop to a 4.6 model.
- **`skipAutoPermissionPrompt`, `skipWorkflowUsageWarning`** are not in the published settings reference (likely newer than docs). Kept since the client accepts them; if a future version rejects unknown keys, these are the first to delete.
- **`defaultMode: "auto"` + `skipDangerousModePermissionPrompt: true`** — valid (docs: `auto` only takes effect in user-level settings), but this is a low-guardrail combination. Deliberate; flagged in README.
- **`settings.json.bak`** in `~/.claude/` was a stale pre-Fable copy (model: opus, subagents: sonnet, context-mode enabled). Not ported.

## 3. Plugin audit (22 → 11)

Per-turn/session cost ranking of the old set: (1) security-guidance — UserPromptSubmit injection on every prompt + its own out-of-band LLM security review on every turn-end + a 180s SDK install check at SessionStart; (2) caveman — ruleset every session + reminder every turn; (3) serena — uvx git-build at every session start plus a large tool schema; (4) hookify — four python subprocesses per turn (PreToolUse before every tool call) with zero configured rules on this machine; (5) each MCP plugin (context7/github/playwright) — one subprocess + schema per session.

Dropped, with the deciding fact:
- **security-guidance** — always-on tax; built-in `/security-review` covers on-demand use.
- **serena** — heaviest cold start; semantic navigation duplicates the LSP plugins + native LSP tool.
- **hookify** — pure overhead until you write rules; if you ever need it, reinstall then.
- **feature-dev** — its explore→architect→review pipeline competes with superpowers' brainstorm→plan→execute; running both means contradictory process prescriptions.
- **code-review (plugin)** — name-shadows the built-in `/code-review`; pr-review-toolkit is the strictly richer reviewer.
- **code-simplifier** — subsumed twice (built-in `/simplify`, and pr-review-toolkit bundles its own).
- **github** — remote MCP requiring `GITHUB_PERSONAL_ACCESS_TOKEN`; `gh` CLI already does PRs/issues/API here.
- **skill-creator** — superpowers:writing-skills covers it.
- **claude-code-setup** — one-shot onboarding recommender; built-in update-config skill covers ongoing needs.
- **frontend-design** — one generic skill vs your three richer frontend skills.
- **clangd-lsp** — you had already disabled it locally; not re-enabled.
- **context-mode marketplace** — removed from `extraKnownMarketplaces`: its PreToolUse Bash-rewrite hook is the one mechanism-level collision with RTK (double-rewrite hazard — the likely reason it was already disabled), and it's ELv2 (only non-OSS tool in the set).

Kept, with the deciding fact:
- **superpowers** (6.1.1 — note: `installed_plugins.json` still lists a stale 5.1.0 entry; the loaded copy is 6.1.1) — the workflow backbone; also what makes feature-dev/skill-creator droppable.
- **context7** — the only MCP with unique value (version-current library docs).
- **pr-review-toolkit** — best reviewer of the set (6 specialized agents); kept INSTEAD of code-review + code-simplifier. Its `/review-pr` no longer collides now that the personal `review-pr` command is parked.
- **playwright** — browser/E2E; pins to `@playwright/mcp@latest` (uncontrolled drift — pin a version if reproducibility starts to matter).
- **ralph-loop** — Stop hook exits immediately unless its config file exists; near-zero cost, unique completion-promise looping (built-in `/loop` is interval-based).
- **5 LSP stubs** — declarative extension→server bindings; zero cost until a matching file opens. Server binaries must be installed separately (install.sh prints the commands).
- **caveman** — kept because you actively use it, with eyes open: it spends ~1–1.5k input tokens/turn to compress output, so it's net-negative on terse sessions; statusline now wired via `statusline-caveman.sh` (silences its per-session nag); temp-file leak documented above.

## 4. Skills audit (22 → 18 + 3 parked)

Systemic issue fixed everywhere: **20/22 descriptions were topic lists, not triggers.** Anthropic guidance wants descriptions that say WHEN to invoke. All kept skills now start with "Use when …".

Fixed defects: OWASP scramble (§1.2), DORA tiers (§1.3). Removed client leakage: BYTZ Platform / Midtrans / Xendit hard-coded in diagramming, ml-ai-principles, security-principles — a client's domain baked into supposedly reusable skills (now genericized).

Merges:
- **container-patterns** = docker-patterns + k8s-patterns. k8s-patterns was 30 lines and its `**/*.yaml` glob fired on every YAML file in any project. Merged globs are directory-scoped.
- **tooling-eval** = performance-tooling + open-source-eval. They duplicated each other's Rust-CLI tables and every language skill's tool rows. The merge keeps open-source-eval's timeless selection criteria, strips pinned versions (Bun 1.3, Biome 2.3, oxlint 1.39, mold 2.30…) and GitHub star counts (stale within months), keeps order-of-magnitude ratios, and adds an explicit "verify numbers before citing" rule. Rationale: a stale benchmark asserted confidently is worse than no number.

Parked (skills-extra/):
- **software-engineering-laws** — 40+ named laws the model already knows cold; near-zero procedural value; `globs: ["**"]` made it a candidate on every file; its content is duplicated across code-quality/backend/security/ui-ux.
- **ui-ux-laws** — same category ("30 laws from lawsofux.com" — the site has ~21, so even the count claim is off); a11y content triple-duplicated.
- **tailwind-ui** — 33 lines fully contained in frontend-principles + typescript-strict.

Known remaining debt (deliberately NOT done — needs your judgment, not a bulk rewrite):
- **backend-principles, data-engineering-principles, devops-sre-principles, frontend-principles, ml-ai-principles** are still knowledge-dump-heavy with cross-duplication (12-Factor in two skills, DDIA pillars verbatim in two, Nygard patterns in two, data-quality dimensions verbatim in two, Tailwind-v4 setup in two, state-management table in two). Recommended follow-up: pick one home per concept and cut the copies (~30–40% size reduction across the five).
- **Version-pinned claims remain in the language skills** (Java "21.0.5-graal", Go 1.22 references, Vite 8/Rolldown, uuidv7, GPT-4o refs in ml-ai). These age; the tooling-eval discipline note ("verify before citing") is the mitigation until each gets a pass.
- **diagramming globs include `**/*.md`** — broad, but arguably right since diagrams live in markdown. Left as-is.

## 5. Commands audit (5 → 2 + 3 parked)

- **deploy-check** — kept. Generic enough ("or equivalent").
- **handoff** — kept. Still useful alongside built-in compaction (explicit, git-committable session state).
- **review-pr** — parked. Collided with pr-review-toolkit's `/review-pr` (one shadows the other) and built-in `/code-review`; three overlapping reviewers is two too many.
- **tdd** — parked. superpowers:test-driven-development is the richer version of the same workflow.
- **new-service** — parked. Hono/NATS/Drizzle/turbo monorepo scaffold is project-specific; a global command that assumes one stack is a foot-gun in other repos. Move into that monorepo's `.claude/commands/`.

## 6. External tools

- **RTK** — empirically the highest-value piece of the whole setup: 64.7M tokens saved (73.2%) across 42,263 commands on the old machine. Old machine runs 0.37.1; latest stable 0.43.x. Install ONLY via brew / official curl script / `cargo install --git` — plain `cargo install rtk` fetches an unrelated crate ("Rust Type Kit", the exact collision RTK.md warns about). Known limitation: only the Bash tool is compressed; native Read/Grep/Glob bypass it.
- **token-savior** — legit and maintained (Mibayy/token-savior; PyPI `token-savior-recall`, needs Python 3.11+). Was dead config until now; fixed via uvx in install.sh.
- **superpowers** — in the official marketplace; loaded version is current (6.1.1) despite the stale registry entry.
- **caveman** — v1.9.x, active, MIT. Honest upstream caveats: saves output tokens only (~65% avg), adds input tokens per turn.

## 7. Anti-sycophancy layer (new — this was the explicit requirement)

Prior art reviewed: the strongest existing pattern is a three-layer design (persistent CLAUDE.md rules + on-demand adversarial skill + optional prompt-rewriting hook), plus multi-persona adversarial reviewers where each persona MUST surface at least one issue. What shipped here:

1. **CLAUDE.md "Critical Stance" section** — always loaded: evaluate before implementing, no praise-openers, evidence-grounded disagreement AND agreement, "is this good?" = audit request not reassurance request, verify before claiming done, report failures verbatim.
2. **skills/critical-audit** — on-demand three-lens adversarial review (saboteur / maintainer / security auditor) with a no-rubber-stamp rule: every lens either produces a grounded finding or lists exactly what it checked; verdict must follow from the findings.
3. **Deliberately NO per-prompt hook.** A UserPromptSubmit hook that rewrites/append-nags every prompt would cost tokens every turn (the exact pathology this audit dinged security-guidance and caveman for). CLAUDE.md is already always-loaded; that's the cheap persistent layer.

## 8. What was NOT ported, on purpose

- 721-rule project permission allowlist (see §1.6)
- `~/.claude.json` (OAuth/session/per-project trust — per-machine by design; MCP servers recreated via CLI instead)
- `~/.claude/plugins/` cache (reconstructable; ~11 plugins had duplicate stale version dirs anyway)
- `.credentials.json`, `projects/`, `history.jsonl`, session state
- `settings.json.bak`, the dead `context-mode` marketplace entry, and the `~/.claude/context-mode/` leftover directory
