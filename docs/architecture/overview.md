# Mela — Architecture Overview

> **Last Updated**: 2026-06-17 · **Maturity**: early scaffolding (module surfaces in place;
> end-to-end flows not yet wired — see [`../development/state.md`](../development/state.md)).

Mela is the marketplace layer for AGNOS: discovery, distribution, and trust verification for
desktop apps *and* AI agents. This doc maps the modules and the intended data flow. It
describes the **target architecture**; per-module implementation status lives in
[`../development/state.md`](../development/state.md).

## Module map

| Module | Owns | Status |
|--------|------|--------|
| `lib.rs` | Marketplace core types — `MarketplaceManifest`, `MarketplaceCategory`, `PublisherInfo`; the `DependencyGraph` / `DepNode` resolver | scaffolded |
| `local_registry` | The on-device registry — installed/cached artifacts, local index, query | scaffolded |
| `remote_client` | Remote marketplace HTTP client (reqwest, **rustls-only**) — search / fetch / download / publish | scaffolded |
| `trust` | Ed25519 publisher-signature verification; SHA-256 download integrity gating | scaffolded |
| `transparency` | Append-only, verifiable transparency log of published artifacts | scaffolded |
| `ratings` | Ratings & reviews | scaffolded |
| `sandbox_profiles` | Per-app capability/sandbox profiles, surfaced before install | scaffolded |
| `flutter_packaging` / `flutter_agpkg` | Flutter app → `.agpkg` (AGNOS package) build pipeline + archive format | scaffolded |

## Intended data flow

```
publish:   app/agent ──▶ flutter_packaging ──▶ .agpkg ──▶ trust (sign, Ed25519)
                                                    │
                                                    ▼
                                          transparency (append log entry)
                                                    │
                                                    ▼
                                          remote_client.publish ──▶ marketplace

install:   remote_client (search/fetch) ──▶ trust (verify sig + SHA-256)
                                                    │
                          sandbox_profiles (surface capabilities) ◀─┤
                                                    │
                                                    ▼
                                          local_registry (record install)
```

The two trust gates are the load-bearing invariants: **nothing is installed without a valid
Ed25519 signature and a matching SHA-256 digest** (`trust`), and **every publication is
recorded in the append-only `transparency` log** so the record can't be silently rewritten.
These are design targets at the scaffolding stage, not yet enforced end-to-end.

## Consumers

- **[`ark`](https://github.com/MacCracken/ark)** — pulls marketplace packages.
- **[`daimon`](https://github.com/MacCracken/daimon)** — agent discovery.

## Dependencies

- **[`sigil`](https://github.com/MacCracken/sigil)** — the trust/crypto boundary (signatures,
  key handling).
- **`agnos-common`** — shared AGNOS types (path dep).
- Rust crates: `ed25519-dalek`, `reqwest`(rustls), `sha2`, `tar`, `flate2`, `tokio`,
  `serde`, `uuid`, `chrono`, `tracing`.

## Planned boundaries

Two AGNOS crates are part of mela's *intended* design but **do not exist yet** — they are not
scaffolded, and mela has no code that touches them today:

| Planned dep | Provides | mela uses it for |
|-------------|----------|------------------|
| `mudra` | Token/value primitives — asset identity, ownership, type | making a paid app/agent an ownable asset |
| `vinimaya` | Transaction layer — atomic transfers, escrow, settlement | purchasing / value transfer for paid distribution |

**Paid distribution is future work.** When it is built, mela will integrate `mudra` +
`vinimaya` behind a thin internal boundary and run against **interim stubs** until those repos
are scaffolded — so the marketplace's free-distribution path never blocks on the value cluster.
No stub module is committed yet (there's no consumer to justify one at the scaffolding stage);
the boundary is introduced when the paid surface is.

## Architecture notes

Non-obvious invariants and constraints land in [`./`](.) as numbered notes
(`NNN-kebab-case.md`) as they're discovered — see [`README.md`](README.md).
