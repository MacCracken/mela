# Changelog

All notable changes to Mela are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Performance claims must
include benchmark numbers; breaking changes get a **Breaking** section with a migration note.

## [Unreleased]

## [0.5.0] — Local registry (`local_registry.rs`)

The on-device store: install / record / query / search / remove, persisted to
`index.json` and reloaded on open. Ports the index + lifecycle half of the
largest Rust module (970 lines) over stdlib `fs` + the v0.2.0 manifest model.
**184/184 parity tests** green (was 147), including real on-disk round-trips.

### Added
- **`src/local_registry.cyr` — `InstalledMarketplacePackage` + `LocalRegistry`.**
  `registry_install` (quota check, manifest validate, upgrade detection, index
  insert + persist), `registry_uninstall`, `get_package`, `list_installed`
  (sorted), `search` (case-insensitive over name / description / tags),
  `total_installed_size`, `len`, `is_empty`, `set_storage_quota`, `in_memory`.
- **On-disk index** — `save_index` / `load_index` via stdlib `fs`
  (`file_write_all` / `file_read_all` / `sys_mkdir`); `index.json` is a
  name→record JSON object with the manifest nested via the ADR-0001 codec.
  Install → reopen → query → uninstall → reopen round-trips on disk, parity-tested.
- **Signature-verify gate** — `registry_verify_package` (current-key lookup →
  decode key → `trust_verify`): valid signature accepted, tampered content /
  wrong key / unknown key_id rejected.
- **`manifest_to_jv` / `manifest_from_jv`** — value-tree entry points so the
  manifest codec composes inside the index record without re-serializing.
- **Fuzz** (`tests/mela.fcyr`) extended: the registry index importer survives
  arbitrary bytes.
- **ADR**: [0005](docs/adr/0005-registry-index-format-and-tarball-deferral.md) —
  the `index.json` on-disk format, and deferral of gzip/tar tarball extraction
  (`extract_*_tarball`, `.sig` sidecar, `count_files`) to v0.8.0 (`sankoch`).

### Notes
- No new dependency: persistence uses already-vendored stdlib `fs` / `io` /
  `syscalls`; hashing + verification reuse `sigil` (v0.3.0).

## [0.4.0] — Transparency log (`transparency.rs`)

Every publication recorded in an append-only, hash-chained log: each entry is
SHA-256 chained to the previous one, so a silent edit anywhere breaks the chain.
Ports `rust-old/src/transparency.rs`. **147/147 parity tests** green (was 114).
No new dependency — hashing reuses the v0.3.0 `sigil` integration.

### Added
- **`src/transparency.cyr` — `LogEntry` + `TransparencyLog`.** `compute_hash`
  (SHA-256 over sequence‖timestamp‖package‖version‖key_id‖content_hash‖
  signature_hash‖previous_hash) and `verify_self`; `tlog_append` (chains
  `previous_hash`, stamps `sequence`, computes `entry_hash`), `tlog_verify_chain`
  (self-hash + link + sequence checks), `find`, `entries_for_package`, `latest`,
  `len`, `is_empty`.
- **JSON codec** — `tlog_to_json` / `tlog_from_json` (array of entry objects);
  `from_json` re-verifies the chain, so a tampered import is rejected. Parity
  with the Rust serde round-trip + tamper/invalid tests.
- **Fuzz** (`tests/mela.fcyr`) extended: `tlog_from_json` survives arbitrary
  bytes (garbage → 0).
- **ADR**: [0004](docs/adr/0004-transparency-timestamp-epoch.md) — `timestamp`
  is an explicit `i64` epoch (not chrono), hashed as its decimal form and
  serialized as a JSON int; the chain stays self-consistent and tamper-evident.

## [0.3.0] — Trust gate (`trust.rs`)

The load-bearing invariant: nothing is trusted without a valid signature, and
download integrity is gated on a digest. Ports `rust-old/src/trust.rs` over the
`sigil` crypto crate. **114/114 parity tests** green (was 76), including
known-answer crypto vectors.

### Added
- **`src/trust.cyr` — Ed25519 + SHA-256 trust core.** `trust_hash_data`
  (SHA-256 hex), `trust_sign` / `trust_verify` (Ed25519; a non-64-byte signature
  is rejected), `trust_keypair_from_seed` / `trust_generate_keypair`,
  `trust_key_id_from_pk`, and hex encode/decode.
- **`KeyVersion` + in-memory `PublisherKeyring`** — `kv_is_valid_at`,
  `kv_verifying_key` (hex→32-byte key, rejects bad hex / wrong length), and
  `keyring_new` / `add_key` / `get_current_key` / `get_all_versions` / `len` /
  `is_empty`. The disk `load()` is deferred to the fs-persistence milestone.
- **Known-answer tests**: SHA-256 (`hello world`, empty) and the RFC 8032
  Ed25519 Test 1 vector (seed → public key → signature). Plus sign/verify
  round-trip and the tampered-data / wrong-key / bad-signature-length rejects.
- **Fuzz** (`tests/mela.fcyr`) extended: the trust hex decoder, key-from-hex
  decoder, and signature verifier survive arbitrary bytes (garbage → 0).
- **ADR**: [0003](docs/adr/0003-trust-time-and-deferred-keyring-load.md) —
  validity windows use `i64` epoch time (not chrono); `get_current_key` takes an
  explicit `now` for deterministic trust decisions; the disk loader defers.

### Dependencies
- **`sigil`** (`dist/sigil.cyr`, tag 3.8.0) wired as the crypto provider —
  Ed25519 + SHA-256 + hex. Added the stdlib modules its dist needs (`fs`,
  `freelist`, `slice`, `process`, `sakshi`, `ct`, `keccak`, `thread`,
  `thread_local`, `random`, `bench`). `trust.cyr` explicitly
  `include`s `lib/thread_local.cyr` — sigil's constant-time crypto bank calls
  `thread_local_*`, which the stdlib auto-resolver does not pull through a dist
  bundle (would link undefined and SIGILL on first verify).

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
