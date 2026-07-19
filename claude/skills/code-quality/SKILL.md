---
name: Code Quality & Writing Standards
description: Use for all code writing, refactoring, and bug fixes — 10C discipline, no overengineering, minimal-diff fixes, completion checklist
globs: ["**/*.ts", "**/*.tsx", "**/*.js", "**/*.py", "**/*.go", "**/*.rs", "**/*.java", "**/*.cpp", "**/*.c", "**/*.h"]
---

# Code Quality & Writing Standards

This skill overrides default behavior. Every line of code MUST follow these principles.

## The 10C Standard for Writing Code

1. **Comprehensive** — cover all requirements, edge cases, error paths. Do not leave partial implementations or TODOs. Every function handles its full contract
2. **Coherent** — code flows logically. Related logic is grouped. Unrelated logic is separated. Reader can follow the narrative top-to-bottom without jumping
3. **Concrete** — no vague abstractions. Variable names describe what they hold. Function names describe what they do. Types describe what they represent. No `data`, `info`, `temp`, `result` as standalone names
4. **Concise** — minimum code for maximum correctness. No unnecessary variables, no redundant checks, no dead paths. If 3 lines do what 10 lines do with equal clarity, use 3
5. **Clear** — any competent developer can understand it in one read. Self-documenting through naming and structure. Comments only for non-obvious "why", never for "what"
6. **Complete** — no missing imports, no undefined references, no unhandled states. Code compiles and runs on first attempt. All types are explicit where inference is ambiguous
7. **Correct** — logic is right. Boundary conditions handled. Null/undefined/empty cases covered. Concurrent access considered. Security implications addressed
8. **Consistent** — follows project conventions. Same pattern for same problem everywhere. Naming, formatting, error handling uniform throughout
9. **Cost-effective** — efficient in time and resources. No overengineering. Don't build a framework when a function will do. Don't add abstraction layers "for the future." Don't create a microservice when a module suffices. Every line of code has a maintenance cost — earn it with a real requirement
10. **Calibrated** — solution complexity matches problem complexity. A simple CRUD endpoint does not need a strategy pattern, event bus, and three abstraction layers. A complex distributed transaction does need proper saga orchestration. Match the tool to the job, not the other way around

## Anti-Patterns (NEVER Do These)

- **Yapping**: verbose code with unnecessary intermediate variables, excessive comments explaining obvious logic, wrapper functions that add no value
- **Redundancy**: checking the same condition twice, re-validating data that's already validated upstream, duplicating logic that exists in a utility
- **Overlapping**: multiple functions/modules doing the same thing slightly differently. Consolidate or pick one
- **Looping**: circular dependencies, recursive patterns where iteration suffices, re-fetching data already in memory
- **Force-fixing**: using `any`/`as unknown as X` to silence type errors, adding `// @ts-ignore`, using `try-catch` to swallow errors, using `!important` in CSS, disabling linter rules inline. These mask bugs — find and fix the root cause
- **Shotgun debugging**: changing multiple things hoping one fixes the bug. Change ONE thing, verify, repeat
- **Cargo culting**: copying patterns without understanding why. Every pattern must earn its place
- **Overengineering**: building for imaginary future requirements. Creating abstractions for one use case. Adding config/options nobody asked for. Wrapping simple things in unnecessary layers. If you catch yourself saying "in case we need to..." — stop. YAGNI
- **Roundabout solutions**: taking an indirect path when a direct one exists. Going through 5 files and 3 abstractions to do what a single function call can do. If the path from input to output requires a map to follow, it's too complex
- **Complexity theater**: making simple things look sophisticated. Using design patterns where a plain function works. Creating a class hierarchy for one variant. Adding dependency injection when there's only one implementation. Complexity should be earned by a real requirement, never performed for appearance
- **Gold plating**: adding polish, features, or "improvements" beyond what was asked. The user asked for a login form, not a login form with biometric auth, remember-me, magic link, SSO, and CAPTCHA. Deliver what's needed, nothing more

## Bug Fixing & Problem Resolution — The Proper Way

1. **Reproduce first** — confirm the bug exists and write a failing test
2. **Understand root cause** — trace the execution path. Use debugger, logs, or tests. Understand WHY it breaks, not just WHERE
3. **Fix at the correct layer** — if the bug is in data validation, fix validation. Don't add a defensive check three layers up. Fix where the invariant should be enforced
4. **Minimal change** — change only what's necessary. Don't refactor surrounding code in a bug fix PR
5. **Verify the fix** — failing test now passes. No regressions. Edge cases covered
6. **Never use workarounds as permanent fixes** — if a library has a bug, file an issue and document the workaround as temporary with a link. If an API returns bad data, fix the API contract, don't silently coerce

## Structural Principles

### Single Level of Abstraction (SLA)
Every function should operate at ONE level of abstraction. Don't mix HTTP parsing with business logic with database queries in one function.

### Early Return / Guard Clause
Check preconditions at the top, return/throw early. Keep the happy path unindented.

### Command-Query Separation (CQS)
Functions either DO something (command, returns void) or ANSWER something (query, returns value). Mixing both creates hidden side effects.

### Fail Fast
Validate inputs at system boundaries immediately. Don't pass invalid data deeper into the system hoping something will catch it.

### Principle of Least Surprise
Code should do exactly what its name suggests, nothing more, nothing less. If `getUser()` also logs analytics, rename it or split it.

### Immutability by Default
Prefer `const`, `readonly`, frozen objects. Mutate only when performance demands it and you can prove it's safe.

## Effectiveness & Efficiency — No Overengineering

### The Right Amount of Code
- **Effective**: solves the actual problem the user has, not a generalized version of it
- **Efficient**: uses minimal resources (time, memory, CPU, developer hours) for the job
- **Direct**: shortest path from problem to solution. No detours through unnecessary abstractions

### Complexity Budget (Spend Wisely)
Every project has a finite complexity budget. Each abstraction, indirection, or pattern costs from that budget. Ask before adding:
1. **Does a real requirement demand this?** (not "might need later")
2. **Is there a simpler way that works?** (3 similar lines > premature abstraction)
3. **Does this help the CURRENT use case?** (not a hypothetical future one)
4. **Can I remove this and nothing breaks?** (if yes, remove it)

### Scale of Solution Must Match Scale of Problem
| Problem | Right Solution | Overengineered Solution |
|---|---|---|
| Format a date | One utility function | A DateFormatter class with strategies |
| Fetch user by ID | Direct DB query | Repository + Unit of Work + CQRS |
| Toggle dark mode | CSS class + localStorage | State machine + event bus + context |
| Validate an email | Zod schema / regex | Custom validation framework |
| Share 3 constants | Export from a file | Shared package with versioning |

### Three Strikes Rule (Rule of Three)
- **1st time**: just write the code inline
- **2nd time**: note the duplication but keep it
- **3rd time**: NOW extract an abstraction — you have 3 real use cases to design against

Abstracting on the first occurrence creates the WRONG abstraction because you don't yet know how it varies.

### YAGNI Enforcement
Before adding anything, prove it's needed NOW:
- No "just in case" error handlers for impossible states
- No feature flags for features that don't exist yet
- No generic `<T>` when only one type is ever used
- No plugin system when there's only one plugin
- No event bus when there are only two subscribers
- No microservice when a function call works

## Code Review Checklist (Self-Review Before Committing)

- [ ] Does every function have a clear single responsibility?
- [ ] Are all error paths handled (not just the happy path)?
- [ ] Is there any duplicated logic that should be extracted?
- [ ] Would a new team member understand this without explanation?
- [ ] Are there any security implications (injection, XSS, auth bypass)?
- [ ] Does this handle concurrent access correctly?
- [ ] Are all magic numbers/strings extracted to named constants?
- [ ] Is the public API minimal? (Don't export what doesn't need to be exported)
- [ ] Is this the simplest solution that fully solves the problem?
- [ ] Is there any code here that serves a hypothetical future rather than a current need?
- [ ] Could I explain why every abstraction exists in one sentence tied to a real requirement?
- [ ] If I deleted any layer/class/pattern, would a real feature break? (if no → delete it)
