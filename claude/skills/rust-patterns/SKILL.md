---
name: Rust Patterns & Best Practices
description: Use when writing or reviewing Rust — ownership, error handling, async, crate selection, testing, build tooling
globs: ["**/*.rs", "**/Cargo.toml", "**/Cargo.lock", "**/.cargo/**"]
---

# Rust Patterns & Best Practices

## Performance Setup
- Linker: mold (3-10x faster than default ld)
- Compilation cache: sccache (cache across branches)
- Test runner: cargo-nextest (60% faster than cargo test)
- Security: cargo-audit + cargo-deny
- Linter: clippy with `-D warnings` (treat warnings as errors)

.cargo/config.toml:
```toml
[target.x86_64-unknown-linux-gnu]
linker = "clang"
rustflags = ["-C", "link-arg=-fuse-ld=mold"]

[build]
rustc-wrapper = "sccache"
```

## Ownership & Borrowing Principles

### The Three Rules
1. Each value has exactly one owner
2. When the owner goes out of scope, the value is dropped
3. You can have either ONE mutable reference OR any number of immutable references

### Practical Patterns
- **Clone only when necessary**: profile first, clone if ownership transfer is complex
- **Borrow by default**: `&T` for read, `&mut T` for write
- **Cow (Clone-on-Write)**: `Cow<str>` when you might need to own but usually borrow
- **Arc<Mutex<T>>** for shared mutable state across threads (avoid if possible)
- **Interior mutability**: `Cell<T>` (Copy types), `RefCell<T>` (runtime borrow checking)

## Error Handling

### Library vs Application
- **Libraries**: use `thiserror` — custom error types with `#[derive(Error)]`
- **Applications**: use `anyhow` — `Result<T, anyhow::Error>` with context
- **Never**: unwrap in library code, panic in library code, use `Box<dyn Error>` in public APIs

### Error Pattern
```rust
// Libraries
#[derive(Debug, thiserror::Error)]
pub enum ServiceError {
    #[error("not found: {0}")]
    NotFound(String),
    #[error("unauthorized")]
    Unauthorized,
    #[error(transparent)]
    Database(#[from] sqlx::Error),
}

// Applications
fn main() -> anyhow::Result<()> {
    do_thing().context("failed to do thing")?;
    Ok(())
}
```

## Async Patterns

### Tokio Best Practices
- Use `#[tokio::main]` for entry point
- `tokio::spawn` for concurrent tasks (returns JoinHandle)
- `tokio::select!` for racing futures
- `tokio::sync::mpsc` for channels, `tokio::sync::RwLock` for shared state
- Never block the async runtime (no `std::thread::sleep`, use `tokio::time::sleep`)

### Structured Concurrency
- Use `JoinSet` for managing groups of spawned tasks
- Cancel on drop: tasks cancelled when JoinSet is dropped
- Error propagation: collect errors from all tasks

## Type System Patterns

### Newtype Pattern
```rust
struct UserId(uuid::Uuid);
struct ProjectId(uuid::Uuid);
// Can't accidentally pass UserId where ProjectId expected
```

### Builder Pattern
For structs with many optional fields — use `bon` or `typed-builder` crate

### State Machine via Types
```rust
struct Draft;
struct Published;
struct Article<State> { /* fields */ _state: PhantomData<State> }
impl Article<Draft> { fn publish(self) -> Article<Published> { /* ... */ } }
// Can only call publish on Draft articles — compile-time guarantee
```

## Testing Patterns
- Unit tests: `#[cfg(test)] mod tests { use super::*; }`
- Integration tests: `tests/` directory (separate compilation)
- Property-based testing: `proptest` crate
- Snapshot testing: `insta` crate (review-based approval)
- Mocking: `mockall` crate for trait-based mocking
- Run with: `cargo nextest run` (faster), `cargo test -- --nocapture` (see output)

## Crate Selection Principles
- Check crates.io downloads + lib.rs ecosystem page
- Prefer crates with `#![forbid(unsafe_code)]` when security matters
- Check MSRV (Minimum Supported Rust Version) compatibility
- Prefer pure-Rust crates over C bindings (portability, safety)
- Essential ecosystem: serde, tokio, tracing, clap, axum, sqlx, reqwest
