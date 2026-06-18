# mela — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**0.9.2** — Consumable library + deferred work done (2026-06-17). mela now ships `dist/mela.cyr`
(consumable by ark); on-disk extraction and real HTTP-over-socket transport are **implemented and
proven** (no longer stubbed). All 9 modules ported; both trust gates enforced; API frozen. 6208
lines of Rust preserved at `rust-old/` (retired after v1.0, once coverage ≥ Rust suite).

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
    response types + JSON codec, offline guards, fs response cache, and **real HTTP+HTTPS
    transport via `sandhi`** (`_rc_http_get` → `sandhi_http_get_auto`: DNS + TLS + HTTP/1.1-or-H2;
    rc_search/rc_fetch_manifest do the live online flow). Proven live against localhost + example.com.
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
    transparency log) / `pipeline_install` enforcing **both trust gates** (signature + digest),
    then **extracting the bundle to disk** under the install dir (ADR-0009, ADR-0005).
    `agpkg_extract_to_dir` / `agpkg_read_entry` do the on-disk unpack.
  - `src/main.cyr` wires all twelve source modules.
- **Packaged as a library**: `dist/mela.cyr` (`[lib]` + `cyrius distlib`, ADR-0010) — what ark
  consumes via `[deps.mela]`.
- **Transport is complete** (no caveats): HTTP, HTTPS, and DNS all via `sandhi`.

## Tests

**472/472** parity tests green (`tests/mela.tcyr` — groups across the 9 modules, plus `pipeline`
(end-to-end), `hardening` (zip-slip), `transport` (HTTP logic), and `extraction` (on-disk unpack)). `trust` has SHA-256 + RFC 8032 Ed25519 KAT vectors; `registry-persist`
/ `ratings-persist` do real on-disk round-trips; `agpkg-archive` packs + inspects a gzipped-ustar
`.agnos-agent` (cross-validated against the system `tar` both directions); `pipeline` runs
package→sign→log→verify→install and rejects tampered / digest-mismatch / untrusted / wrong-key.
Fuzz harness at `tests/mela.fcyr` covers every external-data parser (survive arbitrary bytes).
Benchmarks at [`benches/hotpaths.cyr`](../../benches/hotpaths.cyr) /
[`docs/benchmarks-rust-v-cyrius.md`](../benchmarks-rust-v-cyrius.md). `cyrius test` is the gate.

## Dependencies

Direct (declared in `cyrius.cyml`):

- stdlib — string, fmt, alloc, vec, str, syscalls, io, args, assert, hashmap, tagged, result,
  fnptr, trait, bayan (JSON codec), chrono, plus the transitive set the dep bundles need
  (fs, freelist, slice, process, sakshi, ct, keccak, thread, thread_local, random, bench, net,
  async, atomic, mmap, dynlib, fdlopen, regression, http, tls, ws)
- **agnostik** (`dist/agnostik.cyr`, tag 1.3.1) — shared-types crate; supplies the `AgentManifest`.
- **sigil** (`dist/sigil.cyr`, tag 3.8.0) — Ed25519 + SHA-256 + hex (trust gate).
- **sankoch** (`dist/sankoch.cyr`, tag 2.4.3) — gzip/deflate/lz4 (the `.agnos-agent` packer; tar
  is hand-rolled ustar, ADR-0008).
- **sandhi** (`dist/sandhi.cyr`, tag 1.6.7) — HTTP/HTTPS client (DNS resolver + TLS) backing the
  `remote_client` transport (ADR-0006).
- The dep bundles stack shared error/log constants (`ERR_*` / `LOG_*`) → benign "last definition
  wins" duplicate-symbol warnings at build.

## Consumers

- **ark** — first downstream consumer (package pull). **Unblocked in 0.9.2**: mela now ships
  `dist/mela.cyr` with a `[lib]` section, so ark can add `[deps.mela] modules = ["dist/mela.cyr"]`
  (it couldn't before — mela was binary-only). A dist-only consumer was verified running the full
  pipeline. Next: ark wires the dep and goes green (the v1.0 consumer gate). daimon is the alternative.

## Next

See [`roadmap.md`](roadmap.md). Module port complete (9/9); end-to-end flow wired (0.8.1); audit +
threat model done (0.9.0); public API frozen + docs reconciled (0.9.1, [`../api/`](../api/)).
As of **0.9.2** the previously-deferred pieces are done: mela is consumable (`dist/mela.cyr`),
transport is real (HTTP+HTTPS+DNS via sandhi), and install extracts to disk. Remaining for
**v1.0**: get **ark** green against mela as the downstream consumer, confirm test coverage ≥ the
Rust suite, then retire `rust-old/`. No deferred seams remain.
