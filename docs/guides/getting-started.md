# Getting Started

> **Last Updated**: 2026-06-17 · Mela is **early scaffolding** — this covers building and
> working in the repo, not operating a live marketplace (which isn't wired yet; see
> [`../development/state.md`](../development/state.md)).

## Prerequisites

- Rust toolchain (edition 2024, **MSRV 1.89** — see `rust-toolchain.toml`).
- The sibling `agnosticos` checkout (mela depends on `agnos-common` via a path dep:
  `../agnosticos/userland/agnos-common`).

## Build & test

```sh
cargo build --all-features
cargo test --all-features      # includes serde-roundtrip tests on public types
```

## Cleanliness gate

The work-loop bar (every cycle must pass — see [`CLAUDE.md`](../../CLAUDE.md)):

```sh
cargo fmt --check
cargo clippy --all-features --all-targets -- -D warnings
cargo audit
cargo deny check
RUSTDOCFLAGS="-D warnings" cargo doc --all-features --no-deps
```

## Where to look

| You want to… | Start at |
|--------------|----------|
| Understand the system | [`../architecture/overview.md`](../architecture/overview.md) |
| See what's real vs scaffolded | [`../development/state.md`](../development/state.md) |
| Know what's next | [`../development/roadmap.md`](../development/roadmap.md) |
| Read marketplace core types | `src/lib.rs` |
| See the trust gates | `src/trust.rs`, `src/transparency.rs` |

## Conventions (from CLAUDE.md)

- Every public type is serde `Serialize` + `Deserialize`, with a roundtrip test.
- Public enums are `#[non_exhaustive]`; pure functions are `#[must_use]`.
- **Zero `unwrap`/`panic` in library code.**
- TLS is **rustls only** — never introduce OpenSSL.
- Never accept unsigned artifacts; never skip SHA-256 integrity.
