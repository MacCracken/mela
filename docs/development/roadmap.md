# mela — Roadmap

> **Last Updated**: 2026-06-17 (v0.9.1) · Live status: [`state.md`](state.md) · Per-version history:
> [`../../CHANGELOG.md`](../../CHANGELOG.md)
>
> The path from the **v0.1.0 port scaffold** to a **v1.0 release**. mela is mid-port from Rust
> to Cyrius; this roadmap sequences that port module-by-module, foundation-up, then wires the
> marketplace end-to-end and hardens it. **Each milestone is self-contained** — an agent can
> pick up any one cold from this file.

## How to work a milestone (the port discipline)

`rust-old/src/` is the **frozen parity oracle** — the reference for *what the code does*. Never
edit it. For each milestone:

1. **Read** the named `rust-old/src/*.rs` module(s) to understand the surface and behavior.
2. **Port** it to `src/<module>.cyr` in Cyrius — redesign to Cyrius conventions (no serde:
   hand-write ser/de; structs are `load64`/`store64` at 8-byte offsets; enums are `i64`
   constants + functions; `streq` for cstring compare; see [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md)
   § Cyrius conventions). `include` it from `src/main.cyr`.
3. **Add the dep** to `cyrius.cyml` `[deps.*]` if the milestone names one; `cyrius deps`.
4. **Assert parity** — add a `test_<module>()` group to `tests/mela.tcyr` that checks the
   Cyrius behavior matches the Rust oracle (same inputs → same outputs). Fuzz any parser path
   in `tests/mela.fcyr`.
5. **Green gate** — `cyrius build src/main.cyr build/mela` + `cyrius test` clean; bump the
   `VERSION`, write the CHANGELOG entry, refresh [`state.md`](state.md).

Order is **foundation-up**: pure types → crypto gate → log → store → network → policy → packaging
→ wire → harden. Don't skip ahead; later modules consume earlier ones.

---

## Completed

### v0.9.1 — API freeze + documentation cleanup ✅ (2026-06-17)
- **`docs/api/`** — the frozen, v1.0-bound public surface (conventions + per-module stable
  functions); changes to a listed function now require an ADR. `docs/examples/` end-to-end example.
- **Docs reconciled** to the shipped port: README (status / module table / shipped trust
  properties / api+audit+benchmarks links), `architecture/overview.md` (statuses + Cyrius deps),
  `getting-started.md` (module chain + workflow), CLAUDE.md `Goal` filled. Docs-only; 463/463 tests.

### v0.9.0 — Security audit + hardening ✅ (2026-06-17)
- **Audit** (`docs/audit/2026-06-17-audit.md`) + **threat model**
  (`docs/development/threat-model.md`): current CVE/0-day classes mapped to mela's surface with
  controls + residual risk; informed by web research (tar zip-slip, gzip bombs, Ed25519
  malleability, supply-chain).
- **Hardening**: `_tar_entry_safe` — the ustar reader rejects symlink/hardlink/non-regular entries
  and `..`/absolute names (zip-slip class, CVE-2025-45582 / tar-fs CVE-2024-12905). `hardening`
  test group. Bounded decompression, signature/digest gates, name validation, key windows, and
  fuzzed parsers confirmed. **463/463 tests**.

### v0.8.1 — End-to-end wiring + benchmarks ✅ (2026-06-17)
- **`src/pipeline.cyr`** wires the full flow: `pipeline_package` → `pipeline_publish` (Ed25519
  sign + transparency-log append) → `pipeline_install` enforcing **both trust gates** (signature
  over the bundle keyed by publisher key_id; SHA-256 content digest) before recording.
- E2E test: happy path installs + is logged; tampered / digest-mismatch / untrusted / wrong-key
  all rejected. `agpkg_read_entry` closed the ADR-0005 tarball-extraction gap.
- **Benchmarks** captured (`benches/hotpaths.cyr` + `docs/benchmarks-rust-v-cyrius.md`); ADR-0009.
  **457/457 tests**. (Rust-vs-Cyrius comparison deferred — `rust-old` unbuildable without agnos-common.)

### v0.8.0 — Packaging ✅ (2026-06-17) — **module port complete (9/9)**
- **`flutter_packaging.rs` ported** → `src/flutter_packaging.cyr` (pure): manifest/layout/launch/
  env types, `validate_flutter_manifest`, `determine_backend`, `build_env_vars`.
- **`flutter_agpkg.rs` ported** → `src/flutter_agpkg.cyr`: build-dir validation, manifest/sandbox
  generation, and the `.agnos-agent` packer/inspector — **`sankoch` gzip + hand-rolled ustar tar**.
- build→inspect round-trips in Cyrius; **cross-validated against the system `tar` both directions**
  (the independent oracle, since `rust-old` can't be built); inspector fuzzed. ADR-0008. **444/444 tests**.

### v0.7.0 — Sandbox profiles + ratings ✅ (2026-06-17)
- **`sandbox_profiles.rs` ported** → `src/sandbox_profiles.cyr`: `SandboxPreset`,
  `PredefinedProfile`, Photis Nadi / Aequi / per-preset builders, `validate_profile`, JSON codec.
- **`ratings.rs` ported** → `src/ratings.cyr`: deduplicating `RatingStore`, `add_rating` /
  `get_ratings` / `get_stats` (real f64 averages) / `top_rated`, filters, save/load JSON.
- Profiles surface declared capabilities pre-install; ratings round-trip on disk; both
  parity-tested; importers fuzzed. f64 + i64-time + rule-type decisions in ADR-0007. **355/355 tests**.

### v0.6.0 — Remote client ✅ (2026-06-17)
- **`remote_client.rs` logic ported** → `src/remote_client.cyr`: url_encode / sanitize /
  validate_path_segment, URL builders, response types + JSON codec, `RegistryClient` (base-url
  trim + offline), offline guards, fs response cache.
- The four flows demonstrated against **canned mock responses** (response-parse parity); response
  parsers fuzzed; offline + cache round-trips tested on disk. **240/240 tests**.
- Live HTTP/TLS transport (`sandhi`/`tls`) is a seam deferred to **v0.9.0** end-to-end (ADR-0006) —
  the Rust test suite is itself socket-free, so no live path is exercised yet.

### v0.5.0 — Local registry ✅ (2026-06-17)
- **`local_registry.rs` index/lifecycle ported** → `src/local_registry.cyr`:
  `InstalledMarketplacePackage` + `LocalRegistry` (install/uninstall/get/list/search/quota/
  total-size), `index.json` persisted via stdlib `fs` (ADR-0005), signature-verify gate.
- install→query→remove round-trips **on disk**; the index survives a reopen (parity-tested);
  signature valid/wrong-key/unknown-key paths covered; index importer fuzzed. **184/184 tests**.
- Deferred to v0.8.0 (`sankoch`): gzip/tar tarball extraction + `.sig` sidecar + `count_files`.

### v0.4.0 — Transparency log ✅ (2026-06-17)
- **`transparency.rs` ported** → `src/transparency.cyr`: `LogEntry` (`compute_hash` /
  `verify_self`) + `TransparencyLog` (`append` / `verify_chain` / `find` /
  `entries_for_package` / `latest` / `len` / `is_empty`), SHA-256 hash-chained.
- JSON codec re-verifies the chain on import (tampered entry rejected, invalid JSON rejected);
  append + full-log verify pass; a mutated entry is detected. Import parser fuzzed.
- No new dep (hashing reuses `sigil`); timestamp as `i64` epoch (ADR-0004). **147/147 tests** green.

### v0.3.0 — Trust gate ✅ (2026-06-17)
- **`trust.rs` ported** → `src/trust.cyr` over **sigil** (`dist/sigil.cyr`): Ed25519
  sign/verify + SHA-256 hashing, hex codec, `KeyVersion` (`is_valid_at` / `verifying_key`),
  in-memory `PublisherKeyring`. Disk `load()` deferred to the fs milestone.
- Sign→verify round-trips; tampered + wrong-key + bad-length signatures all rejected;
  SHA-256 + RFC 8032 Ed25519 known-answer vectors match. Trust parsers fuzzed.
- Time as `i64` epoch, explicit `now`, deferred loader (ADR-0003). **114/114 tests** green.

### v0.2.0 — Core manifest model ✅ (2026-06-17)
- **`lib.rs` fully ported.** `src/manifest.cyr` (`PublisherInfo`, `MarketplaceManifest` +
  `validate`/`qualified_name`, `is_valid_semver`, JSON codec) and `src/depgraph.cyr` (`DepNode`,
  `DependencyGraph`: `add`/`len`/`is_empty`/`check_missing`/`detect_cycle`/Kahn `resolve`).
- **`agnostik` dep wired** (`dist/agnostik.cyr`) as the `AgentManifest` source.
- Manifest wire format pinned (ADR-0001 JSON) + version-as-`Str` divergence (ADR-0002).
- **76/76 parity tests** green; malformed-manifest fuzz harness.

### v0.1.0 — Port scaffold ✅ (2026-06-17)
- `cyrius port` scaffold: 6208 lines of Rust → `rust-old/` (oracle); `cyrius.cyml` (pin
  6.2.19), `src/main.cyr`, CI workflows, `tests/mela.{tcyr,bcyr,fcyr}`.
- First module ported: **`MarketplaceCategory`** → `src/category.cyr` (`cat_name` / `cat_parse`,
  19 parity tests).
- First-party doc set (README, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, CHANGELOG, `docs/`).

---

## Port milestones (v0.2.0 → v0.8.0)

### v0.2.0 — Core manifest model (rest of `lib.rs`)
- **Goal**: the data model every other module consumes.
- **Port**: `rust-old/src/lib.rs` (remaining ~470 lines) — `PublisherInfo`, `MarketplaceManifest`
  + its `validate()`, `DepNode` / `DependencyGraph` resolver.
- **Dep gate**: **`agnostik`** (the Cyrius shared-types crate — `agent.cyr` / `types.cyr` /
  `security.cyr`) supplies the `AgentManifest` that `MarketplaceManifest` flattens. Add
  `[deps.agnostik]` (`dist/agnostik.cyr`).
- **Tasks**: port the structs (8-byte field layout), the manifest `validate()` rules, the
  dependency-graph build + resolve; hand-write the manifest (de)serialization (the Rust side is
  serde-JSON — pick the wire format and pin it in an ADR).
- **Done when**: manifest build/validate + dep-graph resolve are parity-tested against the Rust
  oracle on the same fixtures; a malformed-manifest fuzz harness exists.

### v0.3.0 — Trust gate (`trust`)
- **Goal**: the load-bearing invariant — *nothing is trusted without a valid signature + digest.*
- **Port**: `rust-old/src/trust.rs` (16 pub fns, 474 lines) — Ed25519 publisher-signature
  verification, SHA-256 download-integrity gating, publisher trust.
- **Dep gate**: **`sigil`** — `ed25519_sign` / `ed25519_verify` / `ed25519_keypair`, `sha256` /
  `sha256_hex`. Add `[deps.sigil]`.
- **Tasks**: port sign/verify + digest-verify; the reject-unsigned and digest-mismatch paths.
- **Done when**: sign→verify round-trips, a tampered artifact + an unsigned artifact are both
  **rejected**, and a known-answer SHA-256/Ed25519 vector matches — all parity-tested + fuzzed.

### v0.4.0 — Transparency log (`transparency`)
- **Goal**: every publication recorded in an append-only, verifiable log.
- **Port**: `rust-old/src/transparency.rs` (12 pub fns, 500 lines).
- **Dep gate**: `sigil` (hashing) + stdlib `fs` (persistence).
- **Tasks**: append-entry, log verification, and tamper/inclusion-proof logic (Merkle/hash-chain
  — port exactly what the Rust does).
- **Done when**: append + full-log verify pass; a mutated entry is **detected**; parity-tested.

### v0.5.0 — Local registry (`local_registry`)
- **Goal**: the on-device store — install / record / query / remove, persisted.
- **Port**: `rust-old/src/local_registry.rs` (19 pub fns, 970 lines — the largest module; break
  into bites).
- **Dep gate**: the v0.2.0 manifest model + stdlib `fs`.
- **Tasks**: registry index, install/record, query/search, remove; on-disk format (pin it in an
  ADR).
- **Done when**: install→query→remove round-trips on disk, the index survives a reopen, parity-
  tested against the Rust registry on the same operations.

### v0.6.0 — Remote client (`remote_client`)
- **Goal**: talk to a marketplace — search / fetch / download / publish, over TLS, no OpenSSL.
- **Port**: `rust-old/src/remote_client.rs` (4 pub fns, 751 lines).
- **Dep gate**: stdlib **`tls`** / `tls_native` + **`sandhi`** (HTTP client). (Targets the Linux
  host first; an `--agnos` build later rides the sandhi agnos-socket fix — out of scope here.)
- **Tasks**: HTTP(S) request/response, the search/fetch/download/publish flows, response parsing.
- **Done when**: the four flows work against a mock (or live) endpoint with response-parse parity;
  TLS is rustls→stdlib-`tls`, OpenSSL absent; response parsers fuzzed.

### v0.7.0 — Sandbox profiles + ratings (`sandbox_profiles`, `ratings`)
- **Goal**: capability disclosure before install, and ratings/reviews.
- **Port**: `rust-old/src/sandbox_profiles.rs` (4 fns, 740 lines) + `rust-old/src/ratings.rs`
  (9 fns, 897 lines).
- **Dep gate**: the manifest model + `agnostik` (`security.cyr` capability/sandbox types).
- **Tasks**: profile parse + capability surfacing; ratings store/aggregate/query.
- **Done when**: profiles surface the declared capabilities pre-install; ratings round-trip;
  both parity-tested.

### v0.8.0 — Packaging (`flutter_packaging`, `flutter_agpkg`)
- **Goal**: build and read the `.agpkg` (AGNOS package) format.
- **Port**: `rust-old/src/flutter_packaging.rs` (5 fns, 561 lines) + `rust-old/src/flutter_agpkg.rs`
  (4 fns, 660 lines).
- **Dep gate**: **`sankoch`** (LZ4/DEFLATE/gzip — replaces Rust `tar` + `flate2`). Add `[deps.sankoch]`.
- **Tasks**: `.agpkg` archive build/inspect/validate; the packaging pipeline.
- **Done when**: build→inspect→validate round-trips, **and a Rust-built `.agpkg` validates in
  Cyrius (cross-validation)** — the format is identical, not merely self-consistent.

---

## Release run (v0.8.1 → v1.0.0)

> Re-sequenced 2026-06-17: the original v0.9.0 "wiring + hardening" is split —
> wiring + benchmarks shipped in **v0.8.1**; the security audit is its own
> **v0.9.0**; the API freeze + docs cleanup is **v0.9.1**. `rust-old/` is retired
> after v1.0, not during the run.

### v0.8.1 — End-to-end wiring + benchmarks ✅ (2026-06-17)
- **Done.** Full flow wired in `src/pipeline.cyr` (package → sign → log → verify →
  capability-surface → install) with **both trust gates enforced**; hot-path benchmarks captured.
  See *Completed*. (Live `sandhi`/`tls` transport stays a local seam — ADR-0006/0009.)

### v0.9.0 — Security audit + hardening ✅ (2026-06-17)
- **Done.** `docs/audit/2026-06-17-audit.md` + `docs/development/threat-model.md`; web research on
  the relevant 0-day / CVE classes folded into findings + the threat model. Concrete hardening:
  the ustar reader's `_tar_entry_safe` zip-slip guard. See *Completed*. Follow-ups (on-disk
  extractor path-confinement, live-transport TLS, keyring provenance) tracked in the audit.

### v0.9.1 — API freeze + documentation cleanup ✅ (2026-06-17)
- **Done.** Public API frozen in `docs/api/` (conventions + per-module stable surface; ser/de
  roundtrip-tested in the parity suite; `0`-sentinel error model, no panics). README / guides /
  examples / architecture refreshed; ADRs reconciled. See *Completed*.

### v1.0.0 — Release
- All parity + end-to-end + audit + benchmarks green; CI green.
- **At least one downstream consumer green against mela** — **`ark`** (package pull) is the
  intended consumer (daimon is the alternative).
- **Retire the oracle** — delete `rust-old/` once Cyrius parity holds **and** test coverage ≥ the
  Rust suite (per the porting standard).
- The `mudra` / `vinimaya` boundary decision finalized (see *Out of scope* — paid distribution
  is post-1.0 unless those repos land first).

---

## v1.0 criteria (the gate)

- [x] All 9 Rust modules ported to Cyrius with **function-level parity** vs `rust-old/`. *(v0.8.0)*
- [x] End-to-end publish→verify→install flow wired; both trust gates **enforced**. *(v0.8.1)*
- [x] Every external-data parser fuzzed. *(coverage ≥ Rust suite to confirm before v1.0)*
- [~] `docs/benchmarks-rust-v-cyrius.md` captured — Cyrius baseline done; Rust column deferred
  (`rust-old` needs `agnos-common` to build). *(v0.8.1)*
- [x] Pre-release security audit passed (`docs/audit/`). *(v0.9.0)*
- [x] Public API frozen + `docs/api/`; CHANGELOG complete from 0.1.0. *(v0.9.1)*
- [ ] ≥1 downstream consumer (**ark**, package pull) green against mela. *(v1.0)*
- [ ] `rust-old/` deleted (parity + coverage met). *(after v1.0)*

---

## Out of scope (post-1.0)

- **Paid distribution** — integrate `mudra` (asset identity / ownership) + `vinimaya`
  (atomic transfers / escrow / settlement). **Both are not yet scaffolded;** until they exist,
  the value surface stays stubbed and the free-distribution path must never block on it. When
  they land, integrate them behind a thin internal boundary (interim stubs first).
- **An `--agnos` target build** — mela runs on the Linux host through the port; an agnos-native
  build follows the other userland tools, and its `remote_client` rides the sandhi agnos
  socket-backend fix (`sandhi/docs/issues/2026-06-14-agnos-socket-backend-gap.md`).
- Advanced discovery (recommendations, federated marketplaces) — feature work after the port
  reaches parity.
