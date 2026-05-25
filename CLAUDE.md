# Project policy — Claude / agent rules

## Git remotes — push policy

- **NEVER push to GitHub.** Any remote whose URL contains `github.com` is off-limits for `git push`, `gh pr create`, `gh push`, or any equivalent. Includes force-push, branch-push, tag-push, mirror-push.
- **Gitea (and any internal git host) is fine.** Pushes to remotes pointed at the in-cluster Gitea (e.g. `gitea.gitea.svc.cluster.local`, the configured Gitea ingress, or any `git.*` internal hostname) are allowed when the user asks for them. Argo CD pulls from Gitea, so refactor commits intended for cluster reconciliation belong there.
- Default is still "do not push anywhere unless explicitly asked". This rule only narrows where pushes may go when asked.
- When unsure which remote a push would hit, run `git remote -v` first and confirm the destination is **not** `github.com` before proceeding.
- The same restriction applies to PR / issue creation via `gh`: GitHub PRs/issues are off; Gitea / Tea CLI / API equivalents are fine.

## Docker builds — execution policy

- **NEVER run `docker build` in this Claude terminal.** Also do not run `docker push`, `docker buildx ...`, or any Makefile target that wraps them (e.g. `make *-build`, `make *-images`, `make *-push`). The user runs these manually in a separate terminal so build logs land in their session, not the assistant's.
- Editing `Dockerfile`s and Makefile build targets is allowed (durable source changes). Triggering the build is the user's step.
- If a change requires verification by rebuilding, write the change, tell the user the exact command to run, and wait.

## Related standing constraints (recap, do not relax)

- NEVER update git config.
- NEVER run destructive git commands (`push --force`, `reset --hard`, `branch -D`, `clean -f`) unless the user explicitly requests it.
- NEVER skip hooks (`--no-verify`, `--no-gpg-sign`) unless the user explicitly requests it.
- NEVER commit changes unless the user explicitly asks. Edits to source are durable in working tree — commit is a separate user-authorised step.
- UV mandate stays in force: no `pip`, `pip3`, `python`, or `python3` invocations; use `uv` / `uvx`.
- Single-node platform invariant: 1 replica idle per workload, HPA/VPA/KEDA may scale on real load.
- Platform stays domain-agnostic. Crypto-specific config lives only in `use-case-crypto/`.
- April 2026 max version cap on all base images, helm targetRevisions, language deps.
