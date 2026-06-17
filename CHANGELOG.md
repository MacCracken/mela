# Changelog

All notable changes to Mela are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Performance claims must
include benchmark numbers; breaking changes get a **Breaking** section with a migration note.

## [Unreleased]

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

## [0.1.0]

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
