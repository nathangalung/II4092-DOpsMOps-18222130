Pre-deployment validation checklist:

1. **Build**: Run `bun run build` or equivalent — must pass with zero errors
2. **Type Check**: Run `bun run typecheck` — no TypeScript errors
3. **Lint**: Run `bun run check` — Biome passes clean
4. **Tests**: Run `bun run test` — all tests pass
5. **Docker**: Validate Dockerfiles build successfully
6. **Migrations**: Check for pending database migrations
7. **Env Vars**: Verify .env.example has all required variables documented
8. **Security**: Run `trivy` or `grype` scan if available

Report results as a checklist with pass/fail per item.
Focus on $ARGUMENTS service if specified, otherwise check all.
