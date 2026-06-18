# Changelog

All notable changes to Mela are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Performance claims must
include benchmark numbers; breaking changes get a **Breaking** section with a migration note.

## [Unreleased]

## [0.2.0] — Core manifest model (rest of `lib.rs`)

The data model every other module consumes. Ports the remainder of
`rust-old/src/lib.rs` to Cyrius with function-level parity, wires the `agnostik`
shared-types crate, and pins the manifest wire format. **76/76 parity tests**
green (was 19).

### Added
- **`src/manifest.cyr` — the manifest model.** `PublisherInfo`, `MarketplaceManifest`
  (`validate()` with the full oracle rule set + `qualified_name()`), and the
  `is_valid_semver` helper. The agent body is agnostik's `AgentManifest`; the
  validatable `version` is a mela-owned `Str` descriptor (ADR-0002).
- **`src/depgraph.cyr` — dependency resolution.** `DepNode` and `DependencyGraph`
  (`add` / `len` / `is_empty` / `check_missing`, DFS `detect_cycle`, and a Kahn
  topological `resolve` with deterministic sorted seeds; cycle ⇒ error).
- **Hand-written JSON codec** for `MarketplaceManifest` and `PublisherInfo`
  (`*_to_json` / `*_from_json`) over the stdlib `bayan` value tree. Round-trip
  parity-tested against the Rust serde-JSON tests.
- **Malformed-manifest fuzz harness** (`tests/mela.fcyr`) — arbitrary bytes
  through `manifest_from_json` / `publisher_from_json` never fault.
- **ADRs**: [0001](docs/adr/0001-manifest-wire-format-json.md) (JSON wire format;
  category serializes as the PascalCase serde variant name, not the `Display`
  form) and [0002](docs/adr/0002-agent-version-as-str-descriptor.md) (version as
  a `Str` descriptor).

### Dependencies
- **`agnostik`** (`dist/agnostik.cyr`, tag 1.3.1) wired as the `AgentManifest`
  source. Added the stdlib modules it needs — `hashmap`, `tagged`, `result`,
  `fnptr`, `trait`, `bayan`, `chrono`.

## [0.1.0] — Rust → Cyrius port scaffold

### Changed
- **Began the Rust → Cyrius port.** `cyrius port` scaffolded the Cyrius project: the 6208-line
  Rust implementation is preserved at `rust-old/` as the parity oracle; `cyrius.cyml` (pin
  **6.2.19**), `src/main.cyr`, the CI workflows, and `tests/mela.{tcyr,bcyr,fcyr}` are in place.
  The build tooling is now Cyrius (`cyrius build`/`test`), not cargo.

### Added
- **First ported module — `src/category.cyr` (`MarketplaceCategory`).** Ports the discovery
  category enum from `rust-old/src/lib.rs`: id↔name (`cat_name`, the Rust `Display`) and a
  case-insensitive `cat_parse` (the Rust `FromStr`, including the `dev-tool` / `desktopapp`
  aliases). **19/19 parity tests** green (`tests/mela.tcyr`).
- First-party documentation set: `README.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  `SECURITY.md`, `CHANGELOG.md`, and the `docs/` tree (the `cyrius port` scaffold's port-aware
  templates, enriched) — to the
  [First-Party Documentation Standard](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-documentation.md).

## [0.1.0-rust] — Initial Rust crate (parity oracle)

Initial **scaffolding** — module surfaces, core types, and the trust / transparency / sandbox
boundaries for the AGNOS app & agent marketplace. Early pre-alpha; the end-to-end marketplace
is **not yet wired** (see [`docs/development/state.md`](docs/development/state.md)).

### Added
- **Marketplace core** (`lib.rs`) — core types `MarketplaceManifest`, `MarketplaceCategory`,
  `PublisherInfo`, and the `DependencyGraph` / `DepNode` resolver (the marketplace architecture
  per ADR-015 — to be backfilled into `docs/adr/`).
- **Module scaffolds** — `local_registry` (on-device registry surface), `remote_client`
  (remote marketplace HTTP client, **rustls-only** TLS), `trust` (Ed25519 + SHA-256
  verification surface), `transparency` (append-only log), `ratings`, `sandbox_profiles`
  (per-app capability profiles), `flutter_packaging` / `flutter_agpkg` (Flutter → `.agpkg`).

### Notes
- Rust (edition 2024, MSRV 1.89). The Cyrius port is a roadmap milestone (port status:
  *Pending*), tracked in [`docs/development/roadmap.md`](docs/development/roadmap.md).
- The value/transaction cluster (`mudra`, `vinimaya`) is **not yet scaffolded** — paid
  distribution is future work and will run against interim stubs until those repos exist.
- All public types are serde `Serialize` + `Deserialize`; public enums are `#[non_exhaustive]`.
