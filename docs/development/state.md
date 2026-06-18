# mela — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**0.2.0** — Core manifest model (2026-06-17). `lib.rs` fully ported. 6208 lines of Rust
preserved at `rust-old/` for parity reference.

## Toolchain

- **Cyrius pin**: `6.2.19` (in `cyrius.cyml [package].cyrius`). Installed `cycc` is `6.2.21` —
  pin-drift warning is expected and benign; `cyrius lib sync` keeps `lib/` vendored to the pin.

## Source

- Rust reference: 6208 lines at `rust-old/` (frozen, do not edit).
- Cyrius port: **`lib.rs` complete (1 of 9 modules)** —
  - `src/category.cyr` — `MarketplaceCategory` (`cat_name` / `cat_parse`, Rust `Display`/`FromStr`).
  - `src/manifest.cyr` — `PublisherInfo`, `MarketplaceManifest` (`validate` / `qualified_name`),
    `is_valid_semver`, and the JSON codec (`*_to_json` / `*_from_json`, wire format = ADR-0001).
  - `src/depgraph.cyr` — `DepNode`, `DependencyGraph` (`add` / `len` / `is_empty` /
    `check_missing` / `detect_cycle` / Kahn `resolve`).
  - `src/main.cyr` wires all three.
- Remaining (8): `local_registry`, `remote_client`, `trust`, `transparency`, `ratings`,
  `sandbox_profiles`, `flutter_packaging`/`flutter_agpkg`. Next milestone: **v0.3.0 trust**.

## Tests

**76/76** parity tests green (`tests/mela.tcyr` — groups `category`, `semver`, `publisher`,
`manifest`, `depgraph-base`, `depgraph-resolve`, `json`). Malformed-manifest fuzz harness at
`tests/mela.fcyr` (parsers survive arbitrary bytes). `cyrius test` is the gate; each ported
module adds its parity group.

## Dependencies

Direct (declared in `cyrius.cyml`):

- stdlib — string, fmt, alloc, vec, str, syscalls, io, args, assert, hashmap, tagged, result,
  fnptr, trait, bayan (JSON codec), chrono
- **agnostik** (`dist/agnostik.cyr`, tag 1.3.1) — the shared-types crate; supplies the
  `AgentManifest` that `MarketplaceManifest` flattens.

## Consumers

_None yet._

## Next

See [`roadmap.md`](roadmap.md). Next milestone: **v0.3.0 — Trust gate** (`trust.rs`, dep gate
`sigil`): Ed25519 publisher-signature verification + SHA-256 download-integrity gating.
