# Changelog

All notable changes to Mela are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Performance claims must
include benchmark numbers; breaking changes get a **Breaking** section with a migration note.

## [Unreleased]

## [0.9.3] — Namespaced public API (co-bundle-safe with nous)

### Breaking

- **Public symbols that collided with consumer co-dependencies are now
  `mela_`-prefixed.** When ark co-bundles mela with **nous** and **sigil** in one
  Cyrius binary, 15 of mela's public function names clashed — most damagingly
  `registry_new` (mela's raw struct vs nous's `Result`), which under
  last-definition-wins silently rebound *nous's* resolver to mela's
  implementation. Renamed across `src/` + tests:
  - vs nous: `registry_new`→`mela_registry_new`, `registry_search`→`mela_registry_search`,
    `manifest_new`→`mela_manifest_new`, `manifest_to_json`→`mela_manifest_to_json`,
    `update_to_json`→`mela_update_to_json`
  - vs sigil: `keyring_new`→`mela_keyring_new`, plus `keyring_add_key`,
    `keyring_get_all_versions`, `keyring_is_empty`, `keyring_len`, `kv_key_id`,
    `kv_valid_from`, `kv_valid_until`, `kv_public_key_hex`, `kv_is_valid_at`.

  Migration: consumers call the `mela_`-prefixed names. mela ∩
  {nous, sigil, agnostik, sankoch} public-symbol collisions are now **zero**, so
  ark can consume `dist/mela.cyr` alongside nous without last-def-wins hazards.
  472-test suite green; `dist/mela.cyr` regenerated.

## [0.9.2] — Consumable library + the deferred work, actually done

Closes the gaps that were standing between 0.9.1 and a real v1.0: mela now ships
as a **library ark can consume**, and the two pieces previously stubbed/deferred
— on-disk extraction and network transport — are **implemented and proven**, not
ADR-deferred. **472/472 parity tests** green (was 463; the live HTTP/HTTPS fetch is a bash demo,
not in `cyrius test`).

### Added
- **Library packaging (ADR-0010)** — `[lib]` section + `cyrius distlib` →
  **`dist/mela.cyr`**, the single-file bundle downstream consumers pull via
  `[deps.mela] modules = ["dist/mela.cyr"]`. mela was binary-only (no `[lib]`,
  no bundle), so ark could not depend on it. Proven: a program including *only*
  `dist/mela.cyr` runs `cat_parse`, `manifest_validate`, and the full
  `pipeline_install` (both trust gates) successfully.
- **Real on-disk tarball extraction (ADR-0005 resolved)** — `agpkg_extract_to_dir`
  unpacks a gzipped-ustar bundle to disk (gunzip + per-entry zip-slip guard +
  parent-dir creation + write); `pipeline_install` now **extracts onto the
  install dir** after the gates pass. Tested on disk (`extraction` group: files
  written, content re-parses, a `../escaped.so` entry is *not* written).
- **Real HTTP + HTTPS transport (ADR-0006 resolved)** — `_rc_http_get` rides
  **`sandhi`**'s full HTTP client: URL parse → **DNS resolution** → **TLS** (for
  `https://`) → HTTP/1.1-or-H2 → response framing, over real sockets.
  `rc_search` / `rc_fetch_manifest` run the live online flow (build URL → fetch →
  parse → cache). **Proven live both ways**: HTTP from `python3 -m http.server`
  returned the served manifest, and **`https://example.com/` returned the real
  page** — i.e. sandhi resolved the name, completed the TLS handshake, and
  fetched over HTTPS. No IPv4-only / no-HTTPS caveats: sandhi handles all of it.

### Dependencies
- Added **`sandhi`** (`dist/sandhi.cyr`, tag 1.6.7) — the HTTP/HTTPS client
  (DNS + TLS), replacing Rust `reqwest`; plus its stdlib transitive set (`net`,
  `async`, `atomic`, `mmap`, `dynlib`, `fdlopen`, `regression`, `http`, `tls`,
  `ws`).

## [0.9.1] — API freeze + documentation cleanup

Freezes the public surface and reconciles the docs with the shipped port.
Docs-only — no code change; **463/463 parity tests** unchanged.

### Added
- **`docs/api/`** — the **frozen public API reference**: the v1.0-bound surface downstream
  consumers (ark) build against, with conventions (`Str`, `0` = error/absent, `i64` epochs,
  JSON wire = ADR-0001, `_`-prefixed = internal) and per-module stable function listings.
  Signature/semantic changes to a listed function now require an ADR.
- **`docs/examples/publish-and-install.md`** — worked end-to-end example (package → sign → log →
  verify → install) with the rejection table.

### Changed
- **README** — status `v0.1.0`/"early scaffolding" → `v0.9.x`/"port complete; hardening for 1.0";
  module table all ✅; trust properties marked shipped+tested; added links to `docs/api/`, the
  audit, threat model, and benchmarks; quick-start notes `rust-old` isn't built locally.
- **`docs/architecture/overview.md`** — maturity, per-module status (all ported), gate
  enforcement, and the dependency list updated to the Cyrius deps (sigil / agnostik / sankoch).
- **`docs/guides/getting-started.md`** — layout (the real `src/` module chain), the end-to-end
  flow, and an "Extending mela" workflow that points at the frozen API + ADR discipline.
- **CLAUDE.md** — filled the project `Goal` (mela = the marketplace trust boundary).

## [0.9.0] — Security audit + hardening

A pre-release security audit of the supply-chain trust boundary, informed by
current 0-day / CVE classes, with concrete hardening. **463/463 parity tests**
green (was 457).

### Added
- **`docs/audit/2026-06-17-audit.md`** — findings table mapping current CVE/0-day
  classes (tar zip-slip CVE-2025-45582 / tar-fs CVE-2024-12905 / mholt zip-slip,
  gzip-bomb CVE-2026-49853, Ed25519 §5.1.7 malleability, signature-stripping,
  typosquatting, dependency confusion) onto mela's surface, with the control and
  residual risk for each, plus sources.
- **`docs/development/threat-model.md`** — assets, trust boundaries (B1 publisher
  → artifact, B2 untrusted network, B3 on-disk), attacker model, and the control
  holding each boundary, with the in-code enforcement points.

### Security / Hardened
- **Tar entry-safety guard** (`_tar_entry_safe` in `flutter_agpkg.cyr`) — the
  hand-rolled ustar reader now rejects **symlink/hardlink/non-regular** entries
  and **absolute or `..`-traversal** names. `agpkg_inspect` skips them;
  `agpkg_read_entry` refuses them. Defends the zip-slip / symlink-escape class
  (CVE-2025-45582, tar-fs CVE-2024-12905). New `hardening` test group.
- **Confirmed controls** (documented, already enforced): bounded decompression
  (fixed 8 MiB inflate buffer, fails closed → gzip-bomb safe); Ed25519
  non-malleability via `sigil` RFC 8032 §5.1.7 + a 64-byte signature gate; both
  install trust gates (signature + digest); manifest-name validation before the
  install path; key-validity windows; append-only transparency log; all
  external-data parsers fuzzed.

### Notes
- No new dependency. The deferred on-disk extractor (ADR-0005) and live transport
  (ADR-0006) carry explicit follow-up items in the audit/threat-model.

## [0.8.1] — Release run: end-to-end wiring + benchmarks

The full marketplace flow, wired across all ported modules with **both trust
gates enforced**. **457/457 parity tests** green (was 444).

### Added
- **`src/pipeline.cyr`** — end-to-end flow: `pipeline_package` (manifest+sandbox
  → gzipped-ustar bundle), `pipeline_publish` (Ed25519 sign + transparency-log
  append), `pipeline_extract_manifest`/`_sandbox`, and `pipeline_install` which
  enforces **gate 1** (signature over the bundle, keyed by publisher key_id) and
  **gate 2** (SHA-256 content digest) before recording into the local registry.
- **End-to-end test** (`pipeline` group) — happy path installs and is logged;
  a tampered bundle, a digest mismatch, an untrusted publisher, and a wrong
  keyring key are each rejected with nothing installed.
- **`agpkg_read_entry`** — pull a named entry's bytes back out of a bundle;
  closes the deferred `local_registry` tarball extraction (ADR-0005).
- **Benchmarks** — [`benches/hotpaths.cyr`](benches/hotpaths.cyr) +
  [`docs/benchmarks-rust-v-cyrius.md`](docs/benchmarks-rust-v-cyrius.md): ns/op
  for registry lookup, manifest validate, SHA-256, gzip+ustar inspect, and
  Ed25519 verify. (`cyrius bench` SIGILLs with the crypto/compression deps
  linked at this pin; a `cyrius run` timing loop is used instead. The
  Rust-vs-Cyrius comparison is deferred — `rust-old` can't be built without
  `agnos-common`.)
- **ADR**: [0009](docs/adr/0009-end-to-end-pipeline-and-gate-enforcement.md) —
  the pipeline wiring and gate enforcement (transport stays a local seam,
  ADR-0006).

### Notes
- All 9 modules remain ported; this release ties them together. `rust-old/` is
  retained (retired after v1.0, once coverage ≥ the Rust suite).

## [0.8.0] — Packaging (`flutter_packaging.rs`, `flutter_agpkg.rs`)

Build and read the `.agnos-agent` package format — the **final port milestone**:
all 9 Rust modules are now in Cyrius. **444/444 parity tests** green (was 355).

### Added
- **`src/flutter_packaging.cyr`** (pure) — `WaylandRequirement` / `DisplayBackend`
  (+Display), `FlutterAppManifest` / `FlutterPackageLayout` / `FlutterLaunchConfig`,
  `validate_flutter_manifest`, `determine_backend`, `build_launch_config`,
  `build_env_vars`, `layout_for_app`.
- **`src/flutter_agpkg.cyr`** — `PackFlutterConfig`, build-dir validation
  (`FlutterBuildDir::validate` over `fs`), `generate_manifest` /
  `generate_sandbox_profile`, and the packer: **`pack_flutter_app`** writes a
  gzipped-ustar `.agnos-agent`; **`agpkg_inspect`** reads it back.
- **Archive support** — gzip via the new **`sankoch`** dep; a hand-rolled POSIX
  **ustar** tar writer/reader (sankoch is compression-only). The in-Cyrius
  build→inspect round-trip is parity-tested.
- **Cross-validation** — verified interoperable with the system `tar`/`gzip`
  both directions (GNU `tar` reads/extracts a Cyrius-built archive; Cyrius
  `agpkg_inspect` reads a `tar czf`-built archive). The independent oracle for
  "format identical, not self-consistent" (`rust-old` can't be built locally).
- **Fuzz** (`tests/mela.fcyr`) extended: the packaging config / sandbox importers
  and the gzip+ustar inspector survive arbitrary bytes.
- **ADR**: [0008](docs/adr/0008-packaging-gzip-ustar-and-cross-validation.md) —
  gzip+ustar approach and system-tar cross-validation.

### Dependencies
- **`sankoch`** (`dist/sankoch.cyr`, tag 2.4.3) — gzip/deflate/lz4 compression
  (replaces Rust `flate2`). Its stdlib deps were already present.

## [0.7.0] — Sandbox profiles + ratings (`sandbox_profiles.rs`, `ratings.rs`)

Capability disclosure before install, and a ratings/reviews system. Ports two
modules. **355/355 parity tests** green (was 240). No new dependency.

### Added
- **`src/sandbox_profiles.cyr`** — `SandboxPreset` (+ Display), `LandlockRule` /
  `NetworkRule` / `PredefinedProfile`, the Photis Nadi & Aequi profiles, the
  generic `build_profile_for_preset` (photo-editor / productivity / browser /
  game / cli-tool / gpu-compute / custom), and `validate_profile`. JSON
  serde-roundtrip (preset as PascalCase variant name).
- **`src/ratings.cyr`** — `Rating` / `RatingStats` / `RatingFilter` and a
  deduplicating `RatingStore` (one rating per agent per package, latest wins):
  `add_rating` (validation), `get_ratings` (filter + newest-first sort),
  `get_stats` (average / distribution / latest), `top_rated` (average desc,
  total tiebreak), counts. `average_score` is a real `f64`; the store persists
  integer scores and recomputes stats on read.
- **Ratings persistence** — `save` / `load` JSON over stdlib `fs` (missing file →
  empty store, corrupt → error); `Rating` / `RatingStats` / store (de)serialization.
- **Fuzz** (`tests/mela.fcyr`) extended: the sandbox-profile and ratings-store
  importers survive arbitrary bytes.
- **ADR**: [0007](docs/adr/0007-ratings-f64-and-sandbox-rule-types.md) — f64
  averages via Cyrius float builtins, i64 epoch timestamps, and
  `LandlockRule`/`NetworkRule` defined in `sandbox_profiles` until `flutter_agpkg`.

## [0.6.0] — Remote client (`remote_client.rs`)

Talk to a marketplace registry: search / fetch-manifest / download / publish
(+ check-updates). Ports the request/response/cache/offline logic of
`remote_client.rs`; the live HTTP/TLS transport is a seam wired at v0.9.0
(ADR-0006). **240/240 parity tests** green (was 184).

### Added
- **`src/remote_client.cyr`** — `url_encode` (percent-encoding),
  `sanitize_filename`, `validate_path_segment` (rejects traversal / NUL); URL
  builders for all five endpoints; `RegistryClient` (base-url trailing-slash
  trim, cache dir, offline flag).
- **Response types** `SearchResults` / `SearchResult` / `PublishResponse` /
  `UpdateAvailable` with JSON encode + decode — round-trip and **canned
  mock-endpoint** parse tested (response-parse parity).
- **Offline-mode guards** — search/fetch fall back to the cache, download/publish
  are blocked, check_updates returns empty.
- **On-disk response cache** — `cache_search` / `cached_search`,
  `cache_manifest` / `cached_manifest` over stdlib `fs` (`create_dir_all`-style
  `_rc_mkdir_p`), round-tripped on disk.
- **Fuzz** (`tests/mela.fcyr`) extended: the search-results / publish-response /
  update response parsers survive arbitrary bytes.
- **ADR**: [0006](docs/adr/0006-remote-client-transport-seam.md) — the live
  `sandhi`/`tls` HTTP transport (`_rc_http_get`) is a deferred seam; the Rust
  test suite is itself socket-free, so v0.6.0 ports the full testable surface
  and defers transport to the v0.9.0 end-to-end wiring.

### Notes
- No new dependency: caching uses already-vendored stdlib `fs`; the JSON codec
  reuses `bayan`. `sandhi` / `tls` are added when the transport seam is wired
  (v0.9.0).

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
