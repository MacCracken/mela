# rust-old parity record

> **`rust-old/` was retired at v1.1.6.** This record, the parity suite (`tests/mela.tcyr`), the GNU
> tar and transport checks, and ADR-0011/0012/0013 are the oracle now. Source and test comments
> that cite `rust-old/src/*.rs` name the retired code they port; it is in git history before v1.1.6.

> Audited 2026-10-14 against v1.1.0 (cyrius 6.7.9). D1–D5 fixed in v1.1.1, D6–D12 in v1.1.3; Rust test
> coverage closed in v1.1.4; every divergence decided in v1.1.5 (ADR-0013). This file is the record that outlives
> `rust-old/`: every Rust behavior mela chose to keep, drop or change is written here or in an ADR.
> The work it drove is CHANGELOG 1.1.1–1.1.6.

## Summary

The port reproduces the Rust surface, and in several places is stricter than Rust. Every one of
Rust's 204 tests is now covered by the Cyrius suite (202) or recorded as not applicable (2, below);
all twelve defects the review found are fixed; and every behavior that differs from Rust is
matched or recorded in ADR-0013 (v1.1.5). Only the retirement itself (v1.1.6) remains.

| Rust module → Cyrius | Rust tests | Covered | N/A | Closed in |
|---|---:|---:|---:|---|
| `lib.rs` → `category` / `manifest` / `depgraph` | 23 | 23 | 0 | v1.1.4 |
| `trust.rs` → `trust` | 23 | 23 | 0 | v1.1.1, v1.1.4 |
| `transparency.rs` → `transparency` | 15 | 15 | 0 | (audit) |
| `local_registry.rs` → `local_registry` + `pipeline` | 19 | 19 | 0 | v1.1.3, v1.1.4 |
| `remote_client.rs` → `remote_client` | 20 | 20 | 0 | v1.1.3 |
| `sandbox_profiles.rs` → `sandbox_profiles` | 25 | 25 | 0 | v1.1.4 |
| `ratings.rs` → `ratings` | 43 | 42 | 1 | v1.1.4 |
| `flutter_packaging.rs` → `flutter_packaging` | 21 | 20 | 1 | v1.1.4 |
| `flutter_agpkg.rs` → `flutter_agpkg` | 15 | 15 | 0 | v1.1.4 |
| **Total** | **204** | **202** | **2** | |

At the audit (v1.1.0) the suite covered 171 of these, 23 partially and 10 not at all.

Reference coverage (`cyrius coverage`): 247 of 326 `src/` fns (75%) at the audit, 253 of 328
(77%) at v1.1.3, 291 of 328 (88%) at v1.1.4. That counts functions named in a test, not lines
executed. The remaining unreferenced functions are internal helpers reached through their callers.

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
| D6 | High | Six of seven sandbox presets pass the `data_dir` Str through `str_from`, so their first rule's path is garbage, not the app's data dir (Custom is correct). | Fixed v1.1.3 (reproduced) |
| D7 | High | Downloads use sandhi's buffered GET with default options: a **256 KiB** response cap, so larger `.ark` / `.agnos-agent` fetches fail. There are no timeouts (`REQUEST_TIMEOUT` / `DOWNLOAD_TIMEOUT` are defined but unused), and redirects are not followed. | Fixed v1.1.3 |
| D8 | High | The packer's `_read_file` stops at 8 MiB with no error, so a large engine `.so` is packed truncated. The 8 MiB decompress cap also makes such bundles uninstallable. Rust's limit was `MAX_PACKAGE_SIZE` = 100 MB compressed. | Fixed v1.1.3 |
| D9 | Medium | `pipeline_install` records the install before extracting and ignores extraction and index-save failures. A corrupt or >1 MiB `index.json` silently loads as empty, and the next save overwrites it. | Fixed v1.1.3 |
| D10 | Medium | `rc_publish` sends no signature or `X-Package-Metadata`, so the signature never reaches the registry. | Fixed v1.1.3 |
| D11 | Medium | The packer walks `flutter_assets/` one level deep and drops `fonts/`, `shaders/` and `packages/**` (Rust recursed). ADR-0008's rationale for this is wrong. | Fixed v1.1.3 |
| D12 | Medium | An unknown or missing `category` decodes to `-1` and installs. Duplicate tar entry names let the disclosed `sandbox.json` differ from the one written to disk. | Fixed (v1.1.1 duplicates, v1.1.3 category) |

## Behavior changes (all decided in v1.1.5)

Every behavior the audit found differing from Rust with no ADR is now either matched or kept on
purpose in [ADR-0013](../adr/0013-decided-divergences-from-rust-old.md), which also records the
Rust behavior so it survives the deletion of `rust-old/`.

| Divergence | Decision | Where |
|---|---|---|
| Lenient JSON decoders (defaults for missing or mistyped fields) | **matched**: every decoder strict, as serde | ADR-0013 §1 (with ADR-0011, ADR-0012) |
| Ratings wire format (`{"ratings":…}`, RFC 3339) | Rust-written files **refused** | ADR-0013 §2 |
| ASCII-only lowercasing; byte-wise `sanitize_filename` | **matched**: Unicode | ADR-0013 §3 |
| Semver u64 overflow accepted | **matched**: rejected | ADR-0013 §4 |
| Semver leading `+` rejected | **kept** (stricter) | ADR-0013 §4 |
| Scale factor to 2 decimals | **matched**: shortest round-trip | ADR-0013 §4 |
| Validation messages without the value; negative memory accepted | **matched** | ADR-0013 §4 |
| `installed_size` = bundle length | **matched**: extracted size | ADR-0013 §5 |
| No `MAX_PACKAGE_SIZE` (100 MB) check at install | **matched** v1.3.0: checked first | ADR-0014 §1 |
| Quota checked on the bundle size only | **kept** (stricter): the extracted size too, both before any write since v1.3.0 | ADR-0014 §2 |
| Files extracted 0644 (Rust kept `mode & 0o777`) | **decided** v1.3.0: 0755 if the owner-execute bit is set, else 0644 | ADR-0014 |
| No resolved-path containment check | **kept**, and since v1.4.0 stronger: extraction never follows a symlink at or below the destination | ADR-0013 §5, ADR-0015 |
| Archive metadata normalized; compact JSON | **kept** (reproducible bundles) | ADR-0013 §6 |
| Long names truncated; unreadable files skipped | **matched**: pack fails; names to 256 bytes pack, and long names read, since v1.3.0 | ADR-0012, ADR-0014 |
| Keyring per-element validation | **matched**: whole file | ADR-0011 |
| A file named `.json` loaded as a key file | **matched**: skipped | ADR-0013 §7 |
| 1 MiB key-file / ratings-file read cap | **kept**, failing closed | ADR-0013 §1, §7 |
| Transparency hash preimage ambiguity | **fixed** v1.4.0: hash v2 for new entries; v1 (the Rust-shaped preimage) still verifies | ADR-0013 §8, ADR-0015 |
| `RatingFilter` / `DisplayBackend` codecs | not ported (no consumer) | Coverage, below |

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

## Coverage (closed in v1.1.4)

Every Rust test listed as partial or uncovered at the audit now has its assertions in
`tests/mela.tcyr`, in the matching group, along with the untested behaviors the review called out:

- **Chain checks on their own.** The transparency link, sequence and entry-0 checks are each
  tampered with the entry hash recomputed, so only that check can catch it. Disabling any one of
  the three in `tlog_verify_chain` fails exactly its test (mutation-checked, v1.1.4).
- **Signature edge cases.** Lengths 63 and 65, bit flips in R and in S, S + L (the malleable
  second encoding), and an identity public key with R = identity, S = 0, which a non-strict
  verifier accepts. All rejected.
- **Keyring.** Rotation under one key_id, the inclusive validity-window edges, uppercase hex.
- **depgraph.** Self-loop, 3-cycle, full diamond ordering, re-add, unknown and duplicate deps,
  sorted roots.
- **Codec fields.** Search results, publish responses, update records, transparency entries,
  manifests (every field) and packaging configs all round-trip field by field.
- **Fuzzing and format.** The tar parser is fuzzed directly (v1.1.1), and GNU tar cross-checks
  the bundle format in CI (v1.1.2).

### Not applicable (2)

- **`ratings.rs` `test_filter_serialization`** and **`flutter_packaging.rs`
  `test_display_backend_serde_roundtrip`.** Both tested serde derives on types that nothing ever
  serializes: a `RatingFilter` is built and applied in-process, and a `DisplayBackend` is chosen
  at launch. No Rust code read or wrote either as JSON, and no mela consumer does. Porting a codec
  only to test it would add unused API surface. If a consumer ever needs either on the wire, the
  codec and its test come with that need.

## Retirement checklist

`rust-old/` was deleted at v1.1.6, when all of these held:

- [x] D1–D12 fixed, each with a regression test. *(D1–D5: v1.1.1; D6–D12: v1.1.3.)*
- [x] Each "behavior change with no ADR" above is either matched to Rust or recorded in an ADR.
  *(v1.1.5, ADR-0013.)*
- [x] The 33 partial or uncovered Rust tests are covered, or marked N/A here with the reason. *(v1.1.4:
  202 covered, 2 N/A.)*
- [x] CI runs `cyrius test`, `cyrius fuzz` and the GNU-tar cross-check. *(v1.1.2)*
- [x] `cyrius coverage --min` is gated in CI at the level reached. *(76% in v1.1.2, 77% in v1.1.3,
  88% in v1.1.4.)*
- [x] The CLAUDE.md "cross-check against `rust-old/`" principle is replaced by "the parity suite
  and this record are the oracle". *(v1.1.6.)*
