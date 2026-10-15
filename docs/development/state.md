# mela — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**1.1.6** — `rust-old/` retired (2026-10-15): the Rust oracle is deleted; the parity suite,
`rust-parity.md` and ADR-0011/0012/0013 are the oracle. The Rust-vs-Cyrius benchmark comparison is
filled in from the Rust original before its deletion. v1.1.x is complete.

**1.1.5** — every divergence from rust-old decided (2026-10-15, ADR-0013): strict decoding in every
decoder, Unicode text handling, Rust-era ratings files refused; semver overflow, scale-factor text,
messages and `installed_size` matched. 979/979.

**1.1.4** — Rust test coverage closed (2026-10-15): 202 of rust-old's 204 tests covered, 2 N/A with
the reason recorded; chain checks, signature edge cases, rotation and codec fields asserted.
894/894; coverage floor 88%.

**1.1.3** — audit defects D6–D12 fixed (2026-10-15): artifacts stream with Rust's timeouts,
redirects, User-Agent and a 100 MiB cap; publish sends its signature; sandbox presets get their
data dir; the packer fails instead of truncating and walks assets recursively; install extracts
before recording and a corrupt index refuses to open; a manifest needs a valid category
(ADR-0012). 626/626; live transport check in CI.

**1.1.2** — CI runs the gates (2026-10-14): `cyrius deps --locked`, test, fuzz, bench (smoke),
`cyrius coverage --min 76`, and the new GNU tar cross-check (`scripts/tar-crosscheck.sh`,
ADR-0008). No `src/` change.

**1.1.1** — audit defects D1–D5 fixed (2026-10-14): the tar reader validates the whole archive
before use (a crafted bundle no longer crashes `pipeline_install` pre-signature), uninstall no
longer follows symlinks, rating scores and KeyVersions decode fail-closed, `keyring_load_dir`
replaces the keyring (ADR-0011). 553/553.

**1.1.0** — cyrius 6.7.9 (2026-10-14). agnostik 1.12.0; sigil 3.13.11 / sankoch 2.8.3 /
sandhi 1.10.9 from the stdlib. No `src/` change; 492/492; builds for agnos and aarch64. One bench harness:
`tests/mela.bcyr` under `cyrius bench`.

**1.0.5** — JSON lookups migrated to `bayan_json_v_obj_get_by_cstr` (2026-10-14); zero
deprecation warnings at build. Filesystem calls go through the portable `xunlink` / `xrmdir` /
`xmkdir` bridges, so `dist/mela.cyr` compiles for agnos too.

**1.0.4** — cyrius 6.6.20 (2026-10-14). sigil / sankoch / sandhi now come in as stdlib
leaves; agnostik is the only package dep. `lib/` byte-identical to the 6.6.20 snapshot; 492/492.

**1.0.0** — Marketplace trust boundary, released (2026-06-18). Every v1.0 gate is met: full
Rust→Cyrius port with function-level parity (492/492 tests + fuzz), both trust gates enforced
end-to-end, security audit + frozen public API, reproducible `dist/mela.cyr`, and **ark green as
the downstream consumer** (the v1.0 consumer gate). No deferred seams. `rust-old/` is retired
*after* v1.0 once coverage ≥ the Rust suite is confirmed. The format-agnostic fetch primitive that
unblocked ark landed in 0.9.5 (below).

**0.9.5** — Format-agnostic artifact fetch (consumable by ark) (2026-06-18). Adds
**`mela_fetch_artifact(c, name, version, dest_path)`** — the consumer-facing download primitive:
fetches over the sandhi transport and writes the body **verbatim to a caller-chosen path**, making
**no assumption about the artifact type**. `rc_download` (mela's agent flow) now builds on it but
keeps its `.agnos-agent` convention. This unblocks **ark**, whose packages are takumi `.ark`
binaries (not mela `.agnos-agent` bundles): ark passes its own `.ark` cache path and interprets the
bytes with its own installer. All four remote flows are real over sandhi: search/fetch
(GET+parse+cache), **download** (GET+write to cache), **publish** (POST+auth+parse), check_updates
(per-package diff). **Uninstall removes the extracted files** (recursive `_rmtree`), and **keyring
disk `load()` is implemented** (`keyring_load_dir` + `KeyVersion` JSON codec, closing ADR-0003).
mela ships `dist/mela.cyr`; on-disk extraction + both trust gates enforced. **No deferred seams
remain.** 6208 lines of Rust preserved at `rust-old/` (retired after v1.0, once coverage ≥ Rust suite).

## Toolchain

- **Cyrius pin**: `6.7.9` (in `cyrius.cyml [package].cyrius`). `lib/` is the full 6.7.9 stdlib
  snapshot (`cyrius lib sync --full`) plus the agnostik bundle; `cyrius deps --locked` passes.

## Source

- Rust reference: retired at v1.1.6 (6208 lines; in git history before that release). The parity
  record ([`rust-parity.md`](rust-parity.md)) and the parity suite replace it.
- Cyrius port: **all 9 modules complete** —
  - `src/category.cyr` — `MarketplaceCategory` (`cat_name` / `cat_parse`, Rust `Display`/`FromStr`).
  - `src/manifest.cyr` — `PublisherInfo`, `MarketplaceManifest` (`validate` / `qualified_name`),
    `is_valid_semver`, and the JSON codec (`*_to_json` / `*_from_json`, wire format = ADR-0001).
  - `src/depgraph.cyr` — `DepNode`, `DependencyGraph` (`add` / `len` / `is_empty` /
    `check_missing` / `detect_cycle` / Kahn `resolve`).
  - `src/trust.cyr` — Ed25519 sign/verify + SHA-256 hashing (via `sigil`), hex codec,
    `KeyVersion` (`is_valid_at` / `verifying_key`) + its JSON codec, `PublisherKeyring` with
    on-disk `keyring_load_dir` (scans `*.json`, each a `Vec<KeyVersion>` — ADR-0003 resolved).
  - `src/transparency.cyr` — `LogEntry` + `TransparencyLog`: SHA-256 hash-chained append-only
    log (`compute_hash` / `verify_self` / `append` / `verify_chain` / `find` /
    `entries_for_package` / `latest`), JSON codec re-verifying the chain on import (ADR-0004).
  - `src/local_registry.cyr` — `InstalledMarketplacePackage` + `LocalRegistry`: install/record/
    query/search/remove (**uninstall recursively removes the extracted files via `_rmtree`**),
    `index.json` persisted via `fs` (ADR-0005), signature-verify gate.
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

**979/979** tests green (`tests/mela.tcyr` — groups across the 9 modules, plus `pipeline`
(end-to-end), `hardening` (zip-slip), `tar-reader` (v1.1.1: checksum, strict octal, bounds,
duplicate names, the D1 crash input), `install-txn` (v1.1.3: fail-closed index, save rollback), `strict-decode` (v1.1.5: serde rules,
Unicode), `transport` (HTTP logic), `extraction` (on-disk unpack),
`keyring-load` (disk `load()` + `KeyVersion` JSON round-trip), and `registry-uninstall-fs` (files
gone after uninstall)). `trust` has SHA-256 + RFC 8032 Ed25519 KAT vectors; `registry-persist`
/ `ratings-persist` do real on-disk round-trips; `agpkg-archive` packs + inspects a gzipped-ustar
`.agnos-agent` (cross-validated against the system `tar` both directions); `pipeline` runs
package→sign→log→verify→install and rejects tampered / digest-mismatch / untrusted / wrong-key.
Fuzz harness at `tests/mela.fcyr` covers every external-data parser (survive arbitrary bytes).
Benchmarks at [`tests/mela.bcyr`](../../tests/mela.bcyr) (`cyrius bench`) /
[`docs/benchmarks-rust-v-cyrius.md`](../benchmarks-rust-v-cyrius.md). `cyrius test` is the gate.

## Dependencies

Direct (declared in `cyrius.cyml`):

- stdlib — string, fmt, alloc, vec, str, syscalls, io, args, assert, hashmap, tagged, result,
  fnptr, trait, bayan (JSON codec), chrono, fs, freelist, slice, process, sakshi, ct, keccak,
  thread, thread_local, random, bench, net, async, atomic, mmap, dynlib, fdlopen, regression,
  http, tls, ws, plus the folded stdlib bundles:
  - **sigil** (3.13.11) — Ed25519 + SHA-256 + hex (trust gate).
  - **sankoch** (2.8.3) — gzip/deflate/lz4 (the `.agnos-agent` packer; tar is hand-rolled
    ustar, ADR-0008).
  - **sandhi** (1.10.9) — HTTP/HTTPS client (DNS resolver + TLS) backing the `remote_client`
    transport (ADR-0006).
- **agnostik** (`dist/agnostik.cyr`, tag 1.12.0) — shared-types crate; supplies the `AgentManifest`.
- `dist/mela.deps` (consumer-facing sidecar) lists the stdlib leaves the bundle needs:
  thread_local, sigil, fs, sandhi, sankoch.

## Consumers

- **ark** — first downstream consumer (package pull), **GREEN against mela 0.9.5** (the v1.0
  consumer gate is **met**). ark declares `[deps.mela] tag = "0.9.5" modules = ["dist/mela.cyr"]`,
  vendors the matching 0.9.5 bundle (`lib/mela.cyr`, 4159 lines), and calls
  `mela_fetch_artifact(client, name, version, cache_path)` + `registry_client_new` +
  `sanitize_filename` from `src/marketplace.cyr` — replacing ark's hand-rolled HTTP/download with
  mela's transport + download guards. ark builds clean with **263 tests green**
  (`test_marketplace` exercises the integration end-to-end). Division of labor: mela validates
  name/version + builds URLs + fetches via its client; ark's native installer materializes the
  `.ark`. (daimon was the alternative consumer — not needed now that ark is green.)

## Next

See [`roadmap.md`](roadmap.md). **v1.1.x is complete**: the 2026-10-14 parity audit's twelve
defects are fixed, 202 of the Rust original's 204 tests are covered (2 N/A), every divergence is
decided (ADR-0013) and `rust-old/` is retired. CI runs test, fuzz, bench, an 88% coverage floor
(292/330), the GNU tar cross-check and a live transport check.

The **v1.x** backlog maps large-bundle support, hardening residuals, API and build hygiene,
aarch64 and agnos runtime, and the unscheduled features (discovery, paid distribution).
