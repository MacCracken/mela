# Mela

> **मेला** (Hindi: *fair / marketplace / gathering*) — the app & agent marketplace for AGNOS.

**Mela** is AGNOS's marketplace layer: discovery, distribution, and **trust verification**
for desktop applications *and* AI agents. The design goal — every artifact it serves is
Ed25519-signed, SHA-256-integrity-checked, and recorded in an append-only transparency log:
a package manager's convenience with a supply-chain auditor's guarantees.

- **Type**: binary + library — **mid-port from Rust to Cyrius** (Rust oracle at `rust-old/`;
  Cyrius port under `src/`)
- **License**: GPL-3.0-only
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Status**: pre-1.0 (**v0.1.0**) — see [`docs/development/state.md`](docs/development/state.md)

> ⚠️ **Port in progress — early scaffolding.** mela is mid-port from Rust to Cyrius. The
> 6208-line Rust implementation is frozen at [`rust-old/`](rust-old/) as the **parity oracle**;
> the Cyrius port grows under `src/`, one module at a time (first landed:
> `MarketplaceCategory`). The trust properties below are the **design targets** the port carries
> forward, not yet shipped guarantees. [`docs/development/state.md`](docs/development/state.md)
> tracks what's ported today.

## Why Mela

A sovereign OS still needs a front door for software. Mela is that front door, built so the
*trust* properties are structural rather than bolted on:

- **Nothing unsigned ships.** Every package and every agent carries an Ed25519 publisher
  signature; unsigned artifacts are rejected, not warned about.
- **Integrity is verified on every download** (SHA-256), not assumed.
- **Publication is transparent.** An append-only, verifiable transparency log (CT-style)
  records what was published, by whom, and when — so a malicious or compromised publisher
  can't quietly backdate or disappear an artifact.
- **Capability is explicit.** Each app ships a sandbox profile declaring exactly what it may
  touch; the marketplace surfaces those capabilities before install, not after.
- **Agents are first-class.** Mela distributes AI agents alongside apps — the same trust,
  discovery, and sandboxing surface serves both.

## What's inside

The marketplace surface — Rust source preserved at `rust-old/src/`, ported module-by-module to
Cyrius under `src/`:

| Module / type | Role | Cyrius port |
|---------------|------|-------------|
| `MarketplaceCategory` (from `lib.rs`) | Discovery category enum (Display + FromStr) | ✅ `src/category.cyr` — 19 parity tests |
| `lib.rs` (rest) | `MarketplaceManifest`, `PublisherInfo`, the `DependencyGraph` resolver | ⏳ |
| `local_registry` | On-device registry — installed/cached artifacts, local index, query | ⏳ |
| `remote_client` | Remote marketplace HTTP client (TLS via the stdlib `tls` surface) — search / fetch / download | ⏳ |
| `trust` | Ed25519 signature verification, publisher trust, SHA-256 integrity gating | ⏳ |
| `transparency` | Append-only, verifiable transparency log of published artifacts | ⏳ |
| `ratings` | Ratings & reviews | ⏳ |
| `sandbox_profiles` | Per-app capability/sandbox profiles surfaced before install | ⏳ |
| `flutter_packaging` / `flutter_agpkg` | Flutter app → `.agpkg` (AGNOS package) build + archive format | ⏳ |

## Where it sits

- **Consumers**: [`ark`](https://github.com/MacCracken/ark) (pulls marketplace packages),
  [`daimon`](https://github.com/MacCracken/daimon) (agent discovery).
- **Depends on**: [`sigil`](https://github.com/MacCracken/sigil) (trust/crypto boundary).
- **Planned — not yet scaffolded**: `mudra` (asset identity / ownership primitives) +
  `vinimaya` (atomic transfers / escrow / settlement), the value/transaction cluster for
  **paid distribution**. Neither repo exists yet; the paid-distribution surface is future work
  and will run against **interim stubs** until they land. See
  [`docs/architecture/overview.md`](docs/architecture/overview.md) § *Planned boundaries*.
- **Recipes**: [`zugot`](https://github.com/MacCracken/zugot) (takumi build recipes).

See [`docs/architecture/overview.md`](docs/architecture/overview.md) for the module map and data flow.

## Quick start

```sh
# Build + test the Cyrius port
cyrius deps                              # resolve [deps.*] into lib/
cyrius build src/main.cyr build/mela     # build
cyrius test                              # parity tests (tests/mela.tcyr)

# The Rust oracle (reference only — frozen at rust-old/)
( cd rust-old && cargo test )            # the behavior the port targets
```

A guided walkthrough lives in [`docs/guides/getting-started.md`](docs/guides/getting-started.md).

## Documentation

- [`CHANGELOG.md`](CHANGELOG.md) — what changed, per version
- [`docs/architecture/overview.md`](docs/architecture/overview.md) — module map, data flow, trust model
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — completed / backlog / future / v1.0 criteria
- [`docs/development/state.md`](docs/development/state.md) — live status snapshot
- [`docs/adr/`](docs/adr/) — architectural decision records
- [`SECURITY.md`](SECURITY.md) — vulnerability reporting

## License

GPL-3.0-only. Part of the [AGNOS](https://github.com/MacCracken/agnosticos) ecosystem.
