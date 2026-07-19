Review the current PR or branch changes with focus on:

## Security
- Check for hardcoded secrets, SQL injection, XSS, CSRF vulnerabilities
- Validate input sanitization and auth checks

## Tests
- Are there tests for new functionality?
- Do existing tests still pass?
- Edge cases covered?

## Conventions
- Code follows project CLAUDE.md conventions
- TypeScript strict mode, no `any`
- Proper error handling (no swallowed errors)
- i18n for all user-facing strings

## Architecture
- Clean separation of concerns (route -> service -> repository)
- No business logic in route handlers
- Proper use of transactions for atomic operations

Review the diff with: `git diff main...HEAD`
Provide actionable feedback organized by severity: critical, warning, suggestion.
Focus on $ARGUMENTS if specified, otherwise review everything.
