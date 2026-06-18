# Mela

> **मेला** (Hindi: *fair / marketplace / gathering*) — the app & agent marketplace for AGNOS.

**Mela** is AGNOS's marketplace layer: discovery, distribution, and **trust verification**
for desktop applications *and* AI agents. The design goal — every artifact it serves is
Ed25519-signed, SHA-256-integrity-checked, and recorded in an append-only transparency log:
a package manager's convenience with a supply-chain auditor's guarantees.

- **Type**: binary + library — **Rust → Cyrius port** (Rust oracle at `rust-old/`;
  Cyrius port under `src/`)
- **License**: GPL-3.0-only
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Status**: pre-1.0 (**v0.9.x**) — see [`docs/development/state.md`](docs/development/state.md)

> **Port complete; hardening for 1.0.** All 9 Rust modules are ported to Cyrius (the 6208-line
> Rust implementation stays frozen at [`rust-old/`](rust-old/) as the **parity oracle**, retired
> after v1.0). The end-to-end publish→verify→install flow is wired with **both trust gates
> enforced**, a pre-release [security audit](docs/audit/) + [threat model](docs/development/threat-model.md)
> are in place, and the public API is frozen ([`docs/api/`](docs/api/)). The trust properties below
> are **shipped and tested** (457+ parity tests), not aspirations.
> [`docs/development/state.md`](docs/development/state.md) tracks live status.

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
| `lib.rs` → `category` + `manifest` + `depgraph` | `MarketplaceCategory`, `MarketplaceManifest`, `PublisherInfo`, the `DependencyGraph` resolver | ✅ `src/{category,manifest,depgraph}.cyr` |
| `trust` | Ed25519 signature verification, publisher trust, SHA-256 integrity gating | ✅ `src/trust.cyr` (sigil; RFC 8032 KAT) |
| `transparency` | Append-only, hash-chained transparency log of published artifacts | ✅ `src/transparency.cyr` |
| `local_registry` | On-device registry — installed/cached artifacts, local index, query | ✅ `src/local_registry.cyr` (fs-backed) |
| `remote_client` | Remote marketplace client — search / fetch / download / publish (transport seam) | ✅ `src/remote_client.cyr` |
| `sandbox_profiles` | Per-app capability/sandbox profiles surfaced before install | ✅ `src/sandbox_profiles.cyr` |
| `ratings` | Ratings & reviews | ✅ `src/ratings.cyr` |
| `flutter_packaging` / `flutter_agpkg` | Flutter app → `.agnos-agent` build + gzip/ustar archive | ✅ `src/flutter_{packaging,agpkg}.cyr` (sankoch) |
| *(wiring)* `pipeline` | End-to-end publish→sign→log→verify→install, both gates enforced | ✅ `src/pipeline.cyr` |

All 9 Rust modules ported; **457+ parity tests** green, every external-data parser fuzzed. See
[`docs/api/`](docs/api/) for the frozen public surface and
[`docs/benchmarks-rust-v-cyrius.md`](docs/benchmarks-rust-v-cyrius.md) for hot-path numbers.

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
cyrius run benches/hotpaths.cyr          # hot-path benchmarks (ns/op)
```

The Rust oracle at [`rust-old/`](rust-old/) is the frozen parity reference. It is **not built
here** — it depends on `agnos-common` (a sibling crate not vendored in this repo); the Cyrius
tests assert behavior against it by hand, module by module.

A guided walkthrough lives in [`docs/guides/getting-started.md`](docs/guides/getting-started.md).

## Documentation

- [`docs/api/`](docs/api/) — **frozen public API reference** (what consumers build against)
- [`CHANGELOG.md`](CHANGELOG.md) — what changed, per version
- [`docs/architecture/overview.md`](docs/architecture/overview.md) — module map, data flow, trust model
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — completed / backlog / future / v1.0 criteria
- [`docs/development/state.md`](docs/development/state.md) — live status snapshot
- [`docs/development/threat-model.md`](docs/development/threat-model.md) + [`docs/audit/`](docs/audit/) — trust boundaries, controls, audit findings
- [`docs/benchmarks-rust-v-cyrius.md`](docs/benchmarks-rust-v-cyrius.md) — hot-path benchmarks
- [`docs/adr/`](docs/adr/) — architectural decision records
- [`SECURITY.md`](SECURITY.md) — vulnerability reporting

## License

GPL-3.0-only. Part of the [AGNOS](https://github.com/MacCracken/agnosticos) ecosystem.
