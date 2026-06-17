# Mela — Roadmap

> **Last Updated**: 2026-06-17 · Live status: [`state.md`](state.md) · Per-version history:
> [`../../CHANGELOG.md`](../../CHANGELOG.md)

Versioned milestones from the current scaffolding toward a 1.0 marketplace. Honest about
where the work actually is: mela is **early scaffolding** — module surfaces exist, end-to-end
flows do not yet.

## Completed

- **0.1.0 — scaffolding.** Module surfaces + core types laid out: marketplace core (`lib.rs`),
  `local_registry`, `remote_client` (rustls), `trust`, `transparency`, `ratings`,
  `sandbox_profiles`, `flutter_packaging`/`flutter_agpkg`. First-party documentation set.

## In Progress / Backlog

- **Wire the trust gates end-to-end** — install path actually rejects unsigned/​tamper artifacts
  (`trust`: Ed25519 + SHA-256), publish path actually appends to the `transparency` log.
- **Local registry round-trip** — install → record → query → remove, persisted on disk.
- **Remote client flows** — search / fetch / download / publish against a real (or mock)
  marketplace endpoint, with serde-roundtrip + integration tests.
- **Sandbox profiles surfaced before install** — capabilities shown to the user pre-install.
- **Backfill ADR-015** (referenced by `lib.rs` but missing from `docs/adr/`) and the other
  decisions the scaffold already encodes (rustls-only, Ed25519-mandatory, `.agpkg` format).
- **CI + cleanliness gate green** — `cargo fmt`/`clippy -D warnings`/`audit`/`deny`, benchmarks.

## Future

- **Paid distribution** — integrate the value/transaction cluster behind a thin boundary:
  `mudra` (asset identity / ownership) + `vinimaya` (atomic transfers / escrow / settlement).
  **Both are not yet scaffolded**; this milestone runs against interim stubs until those repos
  exist, and the free-distribution path must never block on them.
- **Cyrius port** — mela is Rust today; port status is *Pending* (see
  [`shared-crates.md`](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md)).
  Follows the standard Rust→Cyrius port pattern (preserve `rust-old/`, port module-by-module,
  benchmark against the Rust predecessor).
- **Pre-release security audit** — `docs/audit/YYYY-MM-DD-audit.md` + a `threat-model.md`
  (mela is a supply-chain trust boundary; the audit bar is high).

## v1.0 Criteria

- Trust gates enforced end-to-end (no install without valid signature + digest; every publish
  logged to transparency).
- Local registry + remote client flows complete, tested, and benchmarked.
- Sandbox-profile disclosure on every install.
- Public API stabilized (`#[non_exhaustive]` enums, serde roundtrip on all types, zero
  panic/unwrap in library code) and documented in `docs/api/`.
- A passing pre-release security audit.
- Decision on whether the 1.0 surface ships as Rust or the Cyrius port.
