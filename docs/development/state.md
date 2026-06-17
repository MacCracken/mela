# Mela — Current State

> **Last refresh**: 2026-06-17 | **Refresh cadence**: every release / on meaningful state change.
> CLAUDE.md is durable preferences/process; this file is volatile live state.

## Version

| Field | Value | Source |
|-------|-------|--------|
| **Version** | **0.1.0** | [`VERSION`](../../VERSION) / `Cargo.toml` |
| **Language** | Rust (edition 2024, MSRV 1.89) | `Cargo.toml` |
| **Port status** | **Pending** (Cyrius port not started) | shared-crates.md |
| **Maturity** | **early scaffolding** | — |

## What's real today

Module **surfaces** are scaffolded — types, structure, and the trust/transparency/sandbox
boundaries are laid out. The **end-to-end marketplace is not yet wired**; the trust properties
described in the README are design targets, not enforced flows.

| Module | Surface present | End-to-end wired |
|--------|:---:|:---:|
| `lib.rs` (core types + resolver) | ✅ | — |
| `local_registry` | ✅ | ⏳ |
| `remote_client` | ✅ | ⏳ |
| `trust` (Ed25519 + SHA-256) | ✅ | ⏳ |
| `transparency` | ✅ | ⏳ |
| `ratings` | ✅ | ⏳ |
| `sandbox_profiles` | ✅ | ⏳ |
| `flutter_packaging` / `flutter_agpkg` | ✅ | ⏳ |

## Not yet present

- **Paid distribution** — needs `mudra` (asset identity/ownership) + `vinimaya`
  (transactions/escrow/settlement). **Neither repo is scaffolded;** mela has no code touching
  that surface. Future work, against interim stubs until they land.
- **ADR-015** — referenced by `lib.rs` ("the marketplace architecture defined in ADR-015") but
  the `docs/adr/` record doesn't exist yet — to backfill.
- **CI / benchmark history** — `scripts/bench-history.sh` referenced by CLAUDE.md; not yet
  established.

## Notes

- CLAUDE.md points at `docs/development/applications/first-party-standards.md`; the live
  standards are at agnosticos
  [`docs/development/first-party/`](https://github.com/MacCracken/agnosticos/tree/main/docs/development/first-party)
  — the CLAUDE.md reference is stale and should be corrected when CLAUDE.md is next touched.
