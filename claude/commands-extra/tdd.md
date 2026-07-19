Test-Driven Development workflow for $ARGUMENTS:

1. **Write failing tests first** — create test file(s) for the feature/function described
2. **Commit the tests** — `git add` and commit so they serve as an immutable contract
3. **Implement** — write the minimum code to make tests pass
4. **Refactor** — clean up while keeping tests green
5. **Verify** — run full test suite to ensure no regressions

Rules:
- Tests must fail before implementation (red-green-refactor)
- Each test should test ONE behavior
- Use descriptive test names that read like specifications
- Mock external dependencies, not internal modules
- Aim for edge cases: empty input, null, boundary values, error paths
