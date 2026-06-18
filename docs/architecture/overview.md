# Mela — Architecture Overview

> **Last Updated**: 2026-06-17 (v0.9.1) · **Maturity**: port complete (all 9 modules in Cyrius;
> end-to-end flow wired with both trust gates enforced; pre-1.0 hardening — see
> [`../development/state.md`](../development/state.md)).

Mela is the marketplace layer for AGNOS: discovery, distribution, and trust verification for
desktop apps *and* AI agents. This doc maps the modules and the data flow; the frozen public
surface is in [`../api/`](../api/), per-module status in
[`../development/state.md`](../development/state.md).

## Module map

| Module (Cyrius) | Owns | Status |
|--------|------|--------|
| `category` + `manifest` + `depgraph` | Core types — `MarketplaceManifest`, `MarketplaceCategory`, `PublisherInfo`; the `DependencyGraph` / `DepNode` resolver | ✅ ported |
| `local_registry` | The on-device registry — installed/cached artifacts, `index.json`, query | ✅ ported (fs-backed) |
| `remote_client` | Remote marketplace client — search / fetch / download / publish | ✅ ported (real HTTP+HTTPS+DNS via `sandhi`) |
| `trust` | Ed25519 publisher-signature verification; SHA-256 download integrity gating | ✅ ported (via `sigil`) |
| `transparency` | Append-only, hash-chained transparency log of published artifacts | ✅ ported |
| `ratings` | Ratings & reviews | ✅ ported |
| `sandbox_profiles` | Per-app capability/sandbox profiles, surfaced before install | ✅ ported |
| `flutter_packaging` / `flutter_agpkg` | Flutter app → `.agnos-agent` build + gzip/ustar archive | ✅ ported (via `sankoch`) |
| `pipeline` *(wiring)* | End-to-end publish→sign→log→verify→install, both trust gates enforced | ✅ ADR-0009 |

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
Both gates are **enforced end-to-end** at `pipeline_install` (ADR-0009): a tampered bundle,
digest mismatch, untrusted publisher, or wrong key each install nothing. The signature is
non-malleable (RFC 8032 §5.1.7, via `sigil`); see [`../development/threat-model.md`](../development/threat-model.md).

## Consumers

- **[`ark`](https://github.com/MacCracken/ark)** — pulls marketplace packages.
- **[`daimon`](https://github.com/MacCracken/daimon)** — agent discovery.

## Dependencies (Cyrius port)

- **[`sigil`](https://github.com/MacCracken/sigil)** — crypto boundary: Ed25519 + SHA-256 + hex
  (replaces `ed25519-dalek` + `sha2`).
- **[`agnostik`](https://github.com/MacCracken/agnostik)** — shared AGNOS types; supplies the
  `AgentManifest` the manifest flattens (replaces `agnos-common`).
- **[`sankoch`](https://github.com/MacCracken/sankoch)** — gzip/deflate/lz4 compression for the
  `.agnos-agent` packer (replaces `flate2`; tar is hand-rolled ustar, ADR-0008).
- stdlib `bayan` (JSON), `fs`, `hashmap`, etc. The Rust oracle's crates
  (`reqwest`/rustls, `tar`, `tokio`, `serde`, `uuid`, `chrono`, `tracing`) are replaced by the
  Cyrius stdlib + the deps above.
- **[`sandhi`](https://github.com/MacCracken/sandhi)** — the HTTP/HTTPS client (DNS resolver +
  TLS) backing `remote_client`'s transport (replaces `reqwest`/rustls).

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
