# mela — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**0.1.0** — ported from Rust (2026-06-17) via `cyrius port`. 6208 lines of Rust preserved at `rust-old/` for parity reference.

## Toolchain

- **Cyrius pin**: `6.2.19` (in `cyrius.cyml [package].cyrius`)

## Source

- Rust reference: 6208 lines at `rust-old/` (frozen, do not edit).
- Cyrius port: **1 of 9 modules ported** — `src/category.cyr` (`MarketplaceCategory`: `cat_name`
  / `cat_parse`, parity with the Rust `Display`/`FromStr`). `src/main.cyr` wires it + smokes a
  parse→display round-trip. Remaining: the rest of `lib.rs` (manifest/publisher/dep-graph),
  `local_registry`, `remote_client`, `trust`, `transparency`, `ratings`, `sandbox_profiles`,
  `flutter_packaging`/`flutter_agpkg`.

## Tests

**19/19** parity tests green (`tests/mela.tcyr` — the `category` group, asserting `cat_name` /
`cat_parse` against the Rust `Display`/`FromStr` behavior). `cyrius test` is the gate; each
ported module adds its parity group.

## Dependencies

Direct (declared in `cyrius.cyml`):

- stdlib — string, fmt, alloc, vec, str, syscalls, io, args, assert

## Consumers

_None yet._

## Next

See [`roadmap.md`](roadmap.md). The first milestone is typically Rust→Cyrius surface parity for the 6208-line subset.
