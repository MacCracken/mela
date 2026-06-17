# Mela

> **मेला** (Hindi: *fair / marketplace / gathering*) — the app & agent marketplace for AGNOS.

**Mela** is AGNOS's marketplace layer: discovery, distribution, and **trust verification**
for desktop applications *and* AI agents. The design goal — every artifact it serves is
Ed25519-signed, SHA-256-integrity-checked, and recorded in an append-only transparency log:
a package manager's convenience with a supply-chain auditor's guarantees.

- **Type**: binary + library (Rust today; Cyrius port planned — see [roadmap](docs/development/roadmap.md))
- **License**: GPL-3.0-only
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Status**: pre-1.0 (**v0.1.0**) — see [`docs/development/state.md`](docs/development/state.md)

> ⚠️ **Early scaffolding.** The module surfaces below are scaffolded — types, structure, and
> the trust / transparency / sandbox boundaries are laid out, but the end-to-end marketplace
> is not yet wired and the trust properties are *design targets*, not shipped guarantees.
> [`docs/development/state.md`](docs/development/state.md) tracks what's real today.

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

| Module | Role |
|--------|------|
| `lib.rs` | Marketplace core — `MarketplaceManifest`, `MarketplaceCategory`, `PublisherInfo`, the `DependencyGraph` resolver |
| `local_registry` | The on-device registry — installed/cached artifacts, local index, query |
| `remote_client` | Remote marketplace HTTP client (reqwest + **rustls only**, no OpenSSL) — search / fetch / download |
| `trust` | Ed25519 signature verification, publisher trust, SHA-256 integrity gating |
| `transparency` | Append-only, verifiable transparency log of published artifacts |
| `ratings` | Ratings & reviews |
| `sandbox_profiles` | Per-app capability/sandbox profiles surfaced before install |
| `flutter_packaging` / `flutter_agpkg` | Flutter app → `.agpkg` (AGNOS package) build + archive format |

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
# Build + test (Rust)
cargo build --all-features
cargo test --all-features

# Cleanliness gate (the work-loop bar — see CLAUDE.md)
cargo fmt --check
cargo clippy --all-features --all-targets -- -D warnings
cargo audit && cargo deny check
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
