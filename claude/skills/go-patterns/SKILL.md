---
name: Go Patterns & Best Practices
description: Use when writing or reviewing Go — project layout, error handling, concurrency, tooling, testing idioms
globs: ["**/*.go", "**/go.mod", "**/go.sum"]
---

# Go Patterns & Best Practices

## Performance Setup
- Linter: `golangci-lint run` (aggregates 100+ linters, parallel execution)
- Security: `govulncheck ./...` (official Go team vulnerability scanner)
- Build: `go build -trimpath -ldflags="-s -w"` (30-50% smaller binaries)
- Testing: `go test -race -count=1 -shuffle=on ./...` (catch races, flaky tests)
- Profiling: `go tool pprof` (CPU, memory, goroutine profiling — zero overhead when off)
- Mocking: mockery v3 (auto-generates mocks from interfaces)

## Go Proverbs (Rob Pike)

1. "Don't communicate by sharing memory, share memory by communicating." → channels
2. "Concurrency is not parallelism." → goroutines coordinate, they don't necessarily run simultaneously
3. "Channels orchestrate; mutexes serialize." → prefer channels for coordination
4. "The bigger the interface, the weaker the abstraction." → small interfaces (io.Reader, io.Writer)
5. "Make the zero value useful." → empty struct should be valid and ready to use
6. "interface{} says nothing." → use generics (Go 1.18+) or specific interfaces
7. "A little copying is better than a little dependency." → don't import a package for one function
8. "Clear is better than clever." → readability over brevity
9. "Errors are values." → handle them, wrap them with context, don't panic
10. "Don't just check errors, handle them gracefully." → add context: `fmt.Errorf("loading config: %w", err)`

## Project Layout
```
cmd/             # Entry points (cmd/server/main.go, cmd/worker/main.go)
internal/        # Private application code (not importable by other modules)
  handler/       # HTTP handlers (parse request, call service, return response)
  service/       # Business logic (no HTTP knowledge, no DB knowledge)
  repository/    # Data access (SQL queries, external API calls)
  model/         # Domain types and value objects
  middleware/    # HTTP middleware (auth, logging, rate limiting)
pkg/             # Public library code (importable by others)
migrations/      # Database migrations
```

## Error Handling
```go
// Always wrap errors with context
if err != nil {
    return fmt.Errorf("fetching user %s: %w", userID, err)
}

// Sentinel errors for expected conditions
var ErrNotFound = errors.New("not found")
var ErrConflict = errors.New("conflict")

// Check with errors.Is (not ==)
if errors.Is(err, ErrNotFound) { return http.StatusNotFound }

// Custom error types with errors.As
var validErr *ValidationError
if errors.As(err, &validErr) { return validErr.Fields }
```

## Concurrency Patterns
- `errgroup.Group`: parallel tasks with first-error cancellation
- `sync.WaitGroup`: wait for all goroutines (no error propagation)
- `context.Context`: propagate cancellation and deadlines through call chain
- `sync.Once`: thread-safe one-time initialization
- `sync.Map`: concurrent map (only when contention is high, otherwise mutex+map)

## Testing Patterns
```go
func TestCalculatePrice(t *testing.T) {
    tests := []struct {
        name     string
        input    int
        expected int
        wantErr  bool
    }{
        {"zero", 0, 0, false},
        {"positive", 100, 125, false},
        {"negative", -1, 0, true},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()
            got, err := CalculatePrice(tt.input)
            if tt.wantErr { require.Error(t, err); return }
            require.NoError(t, err)
            assert.Equal(t, tt.expected, got)
        })
    }
}
```

## HTTP Handler Pattern (stdlib, Go 1.22+)
```go
mux := http.NewServeMux()
mux.HandleFunc("GET /api/users/{id}", getUser)   // path params built-in
mux.HandleFunc("POST /api/users", createUser)
```
- stdlib `net/http` now has path parameters (Go 1.22+) — chi/gorilla often unnecessary
- For complex routing/middleware: chi is lightweight and stdlib-compatible

## Generics Best Practices (Go 1.18+)
- Use generics for utility functions: `Map[T, U]`, `Filter[T]`, `Contains[T comparable]`
- Don't over-generify: if only used with one type, use that type
- Constraint interfaces: `comparable`, `~int | ~float64`, custom constraints
