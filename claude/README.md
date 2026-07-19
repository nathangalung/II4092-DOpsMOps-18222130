# Portable Claude Code Setup

Curated, audited copy of the global Claude Code configuration — ready to clone onto another device. Produced from a full audit of the original setup (see `AUDIT.md` for every finding and the reasoning behind each keep/drop).

## Install on a new machine

```bash
git clone <this-repo> claude && cd claude
./install.sh        # run OUTSIDE any active Claude Code session
claude              # then: /login, trust workspace
```

`install.sh` is idempotent: symlinks config into `~/.claude/` (backing up anything it replaces), installs RTK, registers marketplaces, installs the curated plugin set, and registers the token-savior MCP server. Auth (`/login`) is always per-machine.

## What's inside

| Path | What | Notes |
|---|---|---|
| `settings.json` | Global settings | Curated plugin list, RTK hook, caveman statusline, safe read-only permission allowlist |
| `CLAUDE.md` | Global memory | NEW: critical/audit-first stance — no reflexive agreement, verify before "done" |
| `RTK.md` | RTK reference | Imported by CLAUDE.md (`@RTK.md`) |
| `skills/` | 18 skills | 15 originals (descriptions rewritten to trigger-form, defects fixed), 2 merged, 1 new (`critical-audit`) |
| `skills-extra/` | 3 parked skills | Content the model already knows — install only if you miss them |
| `commands/` | 2 commands | `deploy-check`, `handoff` |
| `commands-extra/` | 3 parked commands | Redundant or project-specific — see below |
| `agents/` | `opus-reviewer` | Generalized (thesis-specific wording removed) |
| `statusline-caveman.sh` | Statusline wrapper | Survives plugin cache-hash changes |
| `install.sh` | Bootstrap | See above |
| `AUDIT.md` | Full critique | Every finding, verdict, and evidence from the audit |

## Plugin set (11, down from 22)

**Kept:** superpowers, context7, pr-review-toolkit, playwright, ralph-loop, 5 LSP stubs (ts/pyright/gopls/rust-analyzer/jdtls), caveman.

**Dropped (why, one line each):**
- `security-guidance` — heaviest always-on tax: injects every prompt + runs its own LLM security review at every turn-end; built-in `/security-review` covers on-demand use
- `serena` — builds itself from git at every session start; duplicates the LSP layer you already load
- `hookify` — 4 subprocesses per turn for zero configured rules on this machine
- `feature-dev` — competing feature pipeline that conflicts with superpowers workflows
- `code-review`, `code-simplifier` — subsumed by built-in `/code-review`, `/simplify`, and pr-review-toolkit
- `github` — native `gh` CLI already covers PRs/issues/API without a token-gated MCP
- `skill-creator` — superpowers:writing-skills overlaps
- `claude-code-setup` — one-time onboarding tool, redundant with built-in update-config
- `frontend-design` — your own frontend skills are richer
- `context-mode` (marketplace removed) — its PreToolUse Bash-rewrite hook mechanically collides with RTK's; also ELv2-licensed

## Parked items

- `skills-extra/software-engineering-laws`, `ui-ux-laws` — pure knowledge dumps of things the model already knows; SE-laws also had `globs: ["**"]` (fired on every file)
- `skills-extra/tailwind-ui` — fully duplicated by frontend-principles + typescript-strict
- `commands-extra/review-pr` — name-collided with pr-review-toolkit's `/review-pr`; built-in `/code-review` covers it
- `commands-extra/tdd` — superpowers:test-driven-development covers it
- `commands-extra/new-service` — Hono/NATS/Drizzle monorepo-specific; belongs in that project's `.claude/commands/`, not global

## Known caveats (deliberate choices — revisit if your usage changes)

- `CLAUDE_CODE_SUBAGENT_MODEL=opus` forces ALL subagents to Opus (overrides even agent frontmatter). Cost-control choice; unset to let subagents inherit the session model.
- `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` caps context at 200K (model set to `claude-fable-5`; the old `[1m]` suffix was a no-op contradiction and was removed).
- `defaultMode: "auto"` + `skipDangerousModePermissionPrompt` = low-friction, low-guardrail. Deliberate; flip to `"default"` on any machine where you want prompts.
- caveman plugin costs ~1–1.5k input tokens per turn to save output tokens — net-negative on already-terse sessions. `CAVEMAN_DEFAULT_MODE=off` disables cleanly.
- RTK on the old machine is 0.37.1; latest is 0.43+. `install.sh` installs current. Never `cargo install rtk` (wrong crate — name collision).
