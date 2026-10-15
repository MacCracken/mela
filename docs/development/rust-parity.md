# rust-old parity record

> Audited 2026-10-14 against v1.1.0 (cyrius 6.7.9); D1–D5 fixed in v1.1.1. This file is the record that outlives
> `rust-old/`: once the oracle is deleted, every Rust behavior mela chose to keep, drop or change
> must be written here or in an ADR. Work items live in [`roadmap.md`](roadmap.md) § v1.1.x.

## Summary

The port reproduces the Rust surface, and in several places is stricter than Rust. But
`rust-old/` cannot be deleted yet. The suite misses 32 of Rust's 204 tests (23 partial, 9
uncovered; `keyring_load_malformed_file` was covered in v1.1.1). The review also found defects in mela's own code and behavior changes that no ADR
records.

| Rust module → Cyrius | Rust tests | Covered | Partial | Not covered | Verdict |
|---|---:|---:|---:|---:|---|
| `lib.rs` → `category` / `manifest` / `depgraph` | 23 | 22 | 0 | 1 | ready after tests + ADRs |
| `trust.rs` → `trust` | 23 | 21 | 2 | 0 | ready after tests |
| `transparency.rs` → `transparency` | 15 | 15 | 0 | 0 | ready after chain-check tests |
| `local_registry.rs` → `local_registry` + `pipeline` | 19 | 16 | 2 | 1 | ready after `_rmtree` fix + ADR |
| `remote_client.rs` → `remote_client` | 20 | 19 | 0 | 1 | ready after transport fixes |
| `sandbox_profiles.rs` → `sandbox_profiles` | 25 | 17 | 7 | 1 | ready after `data_dir` fix |
| `ratings.rs` → `ratings` | 43 | 33 | 8 | 2 | ready after bounds fix + ADR |
| `flutter_packaging.rs` → `flutter_packaging` | 21 | 15 | 4 | 2 | ready after tests + ADR |
| `flutter_agpkg.rs` → `flutter_agpkg` | 15 | 14 | 0 | 1 | ready after reader fix + size policy |
| **Total** | **204** | **172** | **23** | **9** | |

Reference coverage (`cyrius coverage`) is 247 of 326 `src/` fns (75%). That counts functions
named in a test, not lines executed.

## Defects found

Each one is a bug whatever Rust did. **Reproduced** means a program triggered it. **Read** means
it was confirmed in the source, with the mechanism traced.

| # | Severity | Defect | Status |
|---|---|---|---|
| D1 | Critical | `_tar_read_size` (`flutter_agpkg.cyr`) treats any byte as an octal digit, so a crafted size field is negative and the reader walks backwards. `pipeline_install` parses the manifest **before** the signature gate, so a 138-byte unsigned bundle crashes it (SIGSEGV). The reader also skips the header checksum and treats a leading NUL as end-of-archive. | Fixed v1.1.1 (reproduced) |
| D2 | High | `_rmtree` (uninstall) recurses through `is_dir`, which follows symlinks. A symlink inside an install dir gets its **target's** contents deleted. Rust's `remove_dir_all` removes the link. | Fixed v1.1.1 |
| D3 | High | `rstore_get_stats` indexes a 6-slot buffer by an unchecked score. A ratings file loaded with `"score": 9` writes past the heap allocation. | Fixed v1.1.1 |
| D4 | High | `cat_parse` copies its input into a 64-byte stack buffer with no bound (public API). | Fixed v1.1.1 |
| D5 | High | `keyring_load_dir` never clears the keyring (Rust `keys.clear()`), so a revoked key survives a reload. `kv_from_jv` defaults a missing `has_until` to "never expires". | Fixed v1.1.1 |
| D6 | High | Six of seven sandbox presets pass the `data_dir` Str through `str_from`, so their first rule's path is garbage, not the app's data dir (Custom is correct). | Reproduced |
| D7 | High | Downloads use sandhi's buffered GET with default options: a **256 KiB** response cap, so larger `.ark` / `.agnos-agent` fetches fail. There are no timeouts (`REQUEST_TIMEOUT` / `DOWNLOAD_TIMEOUT` are defined but unused), and redirects are not followed. | Read |
| D8 | High | The packer's `_read_file` stops at 8 MiB with no error, so a large engine `.so` is packed truncated. The 8 MiB decompress cap also makes such bundles uninstallable. Rust's limit was `MAX_PACKAGE_SIZE` = 100 MB compressed. | Read |
| D9 | Medium | `pipeline_install` records the install before extracting and ignores extraction and index-save failures. A corrupt or >1 MiB `index.json` silently loads as empty, and the next save overwrites it. | Read |
| D10 | Medium | `rc_publish` sends no signature or `X-Package-Metadata`, so the signature never reaches the registry. | Read |
| D11 | Medium | The packer walks `flutter_assets/` one level deep and drops `fonts/`, `shaders/` and `packages/**` (Rust recursed). ADR-0008's rationale for this is wrong. | Read |
| D12 | Medium | An unknown or missing `category` decodes to `-1` and installs. Duplicate tar entry names let the disclosed `sandbox.json` differ from the one written to disk. | Read; duplicate names fixed v1.1.1 |

## Behavior changes with no ADR

For each, either match Rust or write an ADR. The Rust behavior is written here so the choice
stays possible once `rust-old/` is gone.

- **Lenient JSON decoders.** Rust's serde returns an error on missing or mistyped fields. Cyrius
  substitutes defaults in `manifest`, `publisher`, `kv`, `tlog`, sandbox profile, `pfconfig`,
  ratings, and remote responses. `{}` parses as a valid search result or update. Decide one rule
  for trust-boundary inputs.
- **Install accounting.** `installed_size` is the compressed bundle length; Rust summed the
  extracted entry sizes, so the quota is looser. Files are written `0644` (Rust kept
  `mode & 0o777`). There is no resolved-path containment check (Rust had one; Cyrius rejects
  `..` and absolute names instead).
- **Archive writer.** Every entry gets mode 0644, uid/gid 0 and mtime 0. Reproducible, but
  undecided. Names over 100 bytes are truncated with no ustar `prefix` and no GNU LongLink. An
  unreadable AOT or asset file is skipped silently (Rust errors). Output is compact JSON (Rust
  pretty-printed), which changes the bundle bytes.
- **Text handling.** Lowercasing is ASCII-only in `qualified_name`, `search` and `cat_parse`
  (Rust uses Unicode). `sanitize_filename` is byte-wise, so `café` becomes `caf__`.
  `is_valid_semver` rejects a leading `+` (Rust accepts it) and accepts u64 overflow (only a
  code comment says so). `FLUTTER_FORCE_SCALE_FACTOR` is printed to 2 decimals (Rust prints the
  shortest round-trip form: `4/3` → `1.3333333333333333`).
- **Ratings wire format.** Cyrius writes `{pkg:{agent:Rating}}` with an integer `created_at`.
  Rust wrote `{"ratings":{…}}` with RFC 3339 strings. A Rust-written file loads silently as
  garbage, with no error. `RatingFilter` and `DisplayBackend` have no codec; no consumer reads
  either.
- **Keyring loading.** Validation is per element (Rust skipped a whole file if any element was
  malformed), a read is capped at 1 MiB, and a file named exactly `.json` is loaded.
- **Transparency hash preimage.** A decimal epoch followed by the package name is ambiguous
  (`1000`+`1/x` = `10001`+`/x`). Rust's RFC 3339 timestamp ended in `+00:00`. Changing this
  changes every entry hash, so it needs a versioned format.

## Where Cyrius is stricter than Rust (keep)

- `trust_verify` rejects small-order public keys and non-canonical `y` encodings. dalek's
  non-strict `verify` accepted both. Both reject S ≥ L.
- The hex decoder returns 0 on `"+f"` and on non-ASCII input. Rust's accepted `"+f"` and
  panicked on non-ASCII.
- `pipeline_extract_manifest` requires the exact root `manifest.json`. Rust accepted any path
  ending in it, including `../manifest.json`.
- The tar reader rejects symlink, hardlink and non-regular entries, absolute names, and any
  `..` (zip-slip, CVE-2025-45582 class).
- `pipeline_install` has no keyring-less bypass and adds a SHA-256 digest gate.
- The packer builds in memory and writes once, so no partial tarball is left on a read error.

## Coverage to add

Grouped by `tests/mela.tcyr` group. The Rust tests named here are the 33 partial or uncovered.

- **category / semver / manifest / json:**
  - Rust `category_all`: assert `CAT_COUNT == 6`, and the name/parse round trip for all six
    categories.
  - Semver edge inputs: `1.0.0-`, `-1.0.0`, `1..0`, `+1.0.0`, overflow.
  - Name length 128 vs 129.
  - Round-trip `dependencies`, `screenshots`, `changelog`, `min_agnos_version` and `homepage`.
- **depgraph:**
  - Unknown dep ignored by `resolve`; self-loop; 3-cycle path.
  - Re-adding a node overwrites it.
  - Full diamond ordering.
- **trust / keyversion / keyring:**
  - Rust `generate_keypair`: the random path.
  - Rust `hex_roundtrip`: all bytes.
  - Rust `keyring_load_malformed_file`.
  - `sig_len` 63 and 65; bit flips in R and S; S + L; small-order pk.
  - Inclusive validity-window edges.
  - Rotation under a single key id.
- **transparency:** exercise the link, sequence and entry-0 checks on their own. Today every
  tamper test breaks the entry hash first, so deleting any of the three checks leaves the suite
  green. Also: a reordered or truncated import, `{}` / `[]`, and a timestamp that changes the
  hash.
- **registry / persist / uninstall-fs / pipeline:**
  - Rust `storage_quota`: positive control and boundary.
  - Rust `count_files`.
  - Rust `install_with_missing_signature_file`.
  - Search by description and case.
  - List order.
  - A corrupt index.
  - Symlink-safe uninstall (D2).
  - **An on-disk end-to-end install.** Every `pipeline` test uses `registry_in_memory`, so files
    are never shown to land under `packages/<name>`.
  - Upgrade through the pipeline.
  - A signed bundle carrying an invalid manifest.
- **remote / remote-client:**
  - Rust `default_constants`.
  - `validate_path_segment` of `a..b` and `...`.
  - `url_encode` of `/`, `+`, `~`.
  - The offline cache **hit** paths.
  - Trimming multiple trailing slashes.
- **sandbox:**
  - The `data_dir` rule for every preset (D6).
  - Full rule lists, host lists and memory for productivity, browser, game, CLI and GPU.
  - Rust `aequi_profile_seccomp_and_memory`.
  - All 7 preset names and JSON round trips.
  - `strict` seccomp, upper-case access, a bad rule at index > 0, negative memory.
- **ratings / ratings-persist:**
  - Rust `stats_all_same_score`, `stats_single_rating`, `stats_distribution`,
    `filter_by_*`, `review_exactly_max_length`, `multiple_packages_independence`.
  - Non-integer averages and their ranking.
  - Filter boundaries.
  - A rejected re-rating leaves the store unchanged.
  - Out-of-range scores on load (D3).
  - Rust `filter_serialization`: N/A or port the codec.
- **fpackaging / agpkg / agpkg-archive / hardening / extraction:**
  - Rust `validate_bad_dart_version`.
  - The rest of `build_launch_config_wayland`.
  - `FLUTTER_ENGINE_SWITCH_GL`.
  - Rust `manifest_serializes_to_json`.
  - Rust `display_backend_serde_roundtrip`: N/A or port.
  - AOT and engine precedence.
  - Exact entry count.
  - Packed `manifest.json` / `sandbox.json` re-parse.
  - Nested assets (D11).
  - A >8 MiB file fails closed (D8).
  - Typeflag `1`/`2`/`5` entries rejected.
  - Crafted size fields (D1).
  - Duplicate names (D12).
- **fuzz:** *(done v1.1.1)* the seeds never passed the gzip CRC, so the tar parser had never
  been fuzzed, which is why D1 survived. The harness now runs `_tar_scan` on raw input and
  mutates a real archive's header.
- **Independent format oracle:** script the GNU `tar` cross-check from ADR-0008. It ran once by
  hand, and once `rust-old/` is gone it is the only outside check on the bundle format.

## Retirement checklist

`rust-old/` can be deleted when all of these hold:

- [ ] D1–D12 fixed, each with a regression test. *(D1–D5 and D12's duplicate-name half: v1.1.1.)*
- [ ] Each "behavior change with no ADR" above is either matched to Rust or recorded in an ADR.
- [ ] The 33 partial or uncovered Rust tests are covered, or marked N/A here with the reason.
- [ ] CI runs `cyrius test`, `cyrius fuzz` and the GNU-tar cross-check.
- [ ] `cyrius coverage --min` is gated in CI at the level reached.
- [ ] The CLAUDE.md "cross-check against `rust-old/`" principle is replaced by "the parity suite
  and this record are the oracle".
