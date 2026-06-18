# mela — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**0.9.1** — API freeze + documentation cleanup (2026-06-17). All 9 modules ported; end-to-end flow
wired (both gates enforced); audit + threat model done; **public API frozen** ([`../api/`](../api/))
and docs reconciled. 6208 lines of Rust preserved at `rust-old/` (retired after v1.0, once
coverage ≥ Rust suite).

## Toolchain

- **Cyrius pin**: `6.2.19` (in `cyrius.cyml [package].cyrius`). Installed `cycc` is `6.2.21` —
  pin-drift warning is expected and benign; `cyrius lib sync` keeps `lib/` vendored to the pin.

## Source

- Rust reference: 6208 lines at `rust-old/` (frozen, do not edit).
- Cyrius port: **all 9 modules complete** —
  - `src/category.cyr` — `MarketplaceCategory` (`cat_name` / `cat_parse`, Rust `Display`/`FromStr`).
  - `src/manifest.cyr` — `PublisherInfo`, `MarketplaceManifest` (`validate` / `qualified_name`),
    `is_valid_semver`, and the JSON codec (`*_to_json` / `*_from_json`, wire format = ADR-0001).
  - `src/depgraph.cyr` — `DepNode`, `DependencyGraph` (`add` / `len` / `is_empty` /
    `check_missing` / `detect_cycle` / Kahn `resolve`).
  - `src/trust.cyr` — Ed25519 sign/verify + SHA-256 hashing (via `sigil`), hex codec,
    `KeyVersion` (`is_valid_at` / `verifying_key`), in-memory `PublisherKeyring`. Disk
    `load()` deferred to the fs milestone (ADR-0003).
  - `src/transparency.cyr` — `LogEntry` + `TransparencyLog`: SHA-256 hash-chained append-only
    log (`compute_hash` / `verify_self` / `append` / `verify_chain` / `find` /
    `entries_for_package` / `latest`), JSON codec re-verifying the chain on import (ADR-0004).
  - `src/local_registry.cyr` — `InstalledMarketplacePackage` + `LocalRegistry`: install/record/
    query/search/remove, `index.json` persisted via `fs` (ADR-0005), signature-verify gate.
  - `src/remote_client.cyr` — `RegistryClient`: url_encode / sanitize / validate, URL builders,
    response types + JSON codec, offline guards, fs response cache. Live HTTP/TLS transport is a
    seam deferred to v0.9.0 (ADR-0006).
  - `src/sandbox_profiles.cyr` — `SandboxPreset`, `PredefinedProfile` (+ Landlock/Network rules),
    Photis Nadi / Aequi / per-preset builders, `validate_profile`, JSON codec (ADR-0007).
  - `src/ratings.cyr` — `RatingStore` (dedup), `add_rating`/`get_ratings`/`get_stats` (f64 avg)/
    `top_rated`, filters, save/load JSON via `fs` (ADR-0007).
  - `src/flutter_packaging.cyr` — Flutter manifest/layout/launch/env + `validate_flutter_manifest`
    + `determine_backend` (pure).
  - `src/flutter_agpkg.cyr` — `PackFlutterConfig`, build-dir validation, `generate_manifest`/
    `generate_sandbox_profile`, and the `.agnos-agent` packer/inspector (`sankoch` gzip +
    hand-rolled ustar, ADR-0008).
  - `src/pipeline.cyr` — **end-to-end flow**: `pipeline_package` / `pipeline_publish` (sign +
    transparency log) / `pipeline_install` enforcing **both trust gates** (signature + digest)
    before recording into the registry (ADR-0009). `agpkg_read_entry` closed the ADR-0005 gap.
  - `src/main.cyr` wires all twelve source modules.
- Deferred (remains a local seam): **†** `remote_client` live `sandhi`/`tls` transport (ADR-0006) —
  "distribute" is in-process for now; `pipeline_install` is unchanged when it lands.

## Tests

**463/463** parity tests green (`tests/mela.tcyr` — 25 groups across the 9 modules, plus the
`pipeline` end-to-end and `hardening` (tar zip-slip rejection) groups). `trust` has SHA-256 + RFC 8032 Ed25519 KAT vectors; `registry-persist`
/ `ratings-persist` do real on-disk round-trips; `agpkg-archive` packs + inspects a gzipped-ustar
`.agnos-agent` (cross-validated against the system `tar` both directions); `pipeline` runs
package→sign→log→verify→install and rejects tampered / digest-mismatch / untrusted / wrong-key.
Fuzz harness at `tests/mela.fcyr` covers every external-data parser (survive arbitrary bytes).
Benchmarks at [`benches/hotpaths.cyr`](../../benches/hotpaths.cyr) /
[`docs/benchmarks-rust-v-cyrius.md`](../benchmarks-rust-v-cyrius.md). `cyrius test` is the gate.

## Dependencies

Direct (declared in `cyrius.cyml`):

- stdlib — string, fmt, alloc, vec, str, syscalls, io, args, assert, hashmap, tagged, result,
  fnptr, trait, bayan (JSON codec), chrono, plus sigil's transitive set (fs, freelist, slice,
  process, sakshi, ct, keccak, thread, thread_local, random, bench)
- **agnostik** (`dist/agnostik.cyr`, tag 1.3.1) — the shared-types crate; supplies the
  `AgentManifest` that `MarketplaceManifest` flattens.
- **sigil** (`dist/sigil.cyr`, tag 3.8.0) — the crypto crate; Ed25519 + SHA-256 + hex for the
  trust gate. Its dist transitively pulls `agnosys` (used only in unexercised TPM paths, DCE'd);
  the resulting duplicate-symbol warnings on shared `ERR_*` / `LOG_*` constants are benign.
- **sankoch** (`dist/sankoch.cyr`, tag 2.4.3) — gzip/deflate/lz4 compression for the `.agnos-agent`
  packer (tar is hand-rolled ustar on top, ADR-0008).

## Consumers

- **ark** — intended first downstream consumer (package pull). A v1.0 gate is ≥1 consumer green
  against mela; ark is the planned one (daimon is the alternative). Not yet wired.

## Next

See [`roadmap.md`](roadmap.md). Module port complete (9/9); end-to-end flow wired (0.8.1); audit +
threat model done (0.9.0); public API frozen + docs reconciled (0.9.1, [`../api/`](../api/)).
Remaining for **v1.0**: confirm test coverage ≥ the Rust suite, get **ark** green against mela as
the downstream consumer, then retire `rust-old/`. Deferred seams to wire at/by v1.0: live
`remote_client` transport (ADR-0006) and on-disk tarball extraction (ADR-0005).
