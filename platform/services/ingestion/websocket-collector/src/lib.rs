//! Platform-generic WebSocket collector library.
//!
//! This crate is consumed by two binaries:
//!   - `websocket-collector` (this crate's own bin) — platform default, pairs
//!     `GenericCollector` with `DefaultTickerParser` and handles any public
//!     ticker feed.
//!   - Use-case overlays — depend on this crate as a library and plug in
//!     their own `MessageParser` implementations for source-specific
//!     payload schemas. Overlays live under their own repos
//!     (`use-case-<name>/services/ingestion/websocket-collector`); the
//!     platform crate stays neutral.
//!
//! ADR-013 — platform ships zero knowledge of any specific data source.
pub mod collectors;
pub mod config;
pub mod health;
pub mod producer;
