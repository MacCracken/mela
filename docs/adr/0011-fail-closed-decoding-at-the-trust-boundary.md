# 0011 — Fail-closed decoding for keys, ratings and bundles

**Status**: Accepted
**Date**: 2026-10-14 (v1.1.1)

## Context

The 2026-10-14 parity audit against `rust-old/` ([`../development/rust-parity.md`](../development/rust-parity.md))
found that several mela decoders filled a missing, mistyped or out-of-range field with a default.
Rust's serde returned an error instead. Some of those defaults were unsafe:

- **Bundles (D1).** The ustar reader parsed the size field leniently, so a crafted value went
  negative. The reader then walked backwards and crashed `pipeline_install` **before** the
  signature gate. It did not verify the header checksum. When two entries had the same name,
  `agpkg_read_entry` returned the first while extraction wrote the last, so the sandbox disclosed
  before install could differ from the one installed.
- **Ratings (D3).** `rstore_from_json` accepted any integer score. `rstore_get_stats` then
  indexed a 6-slot distribution with it and wrote past the allocation. `stats_dist` read past it
  for any score outside 0..5.
- **Keys (D5).** `kv_from_jv` decoded a missing `has_until` as "never expires". A Rust-shaped
  file with RFC 3339 strings decoded as a key that is valid from epoch 0 and never expires.
  `keyring_load_dir` added to the keyring without clearing it, so a key file deleted between
  loads stayed trusted. Rust's `load()` began with `keys.clear()`.
- **Categories (D4).** `cat_parse` copied its input into a 64-byte stack buffer with no bound.

These functions are in the frozen API ([`../api/`](../api/)). Changing what they accept needs an
ADR.

## Decision

**At the trust boundary, an input that is malformed or out of range is rejected (the function
returns `0` / `-1`). It is never repaired with a default.** For v1.1.1 that means:

- **`agpkg_inspect_bytes` / `agpkg_read_entry` / `agpkg_extract_to_dir`**, and through them
  `pipeline_extract_manifest`, `pipeline_extract_sandbox` and `pipeline_install`, validate the
  whole archive first, in one walker (`_tar_scan`). The archive is rejected if any header has a
  bad checksum, if a numeric field is not strict octal, if an entry's data runs past the archive,
  or if two safe entries share a name.
  - **Checksum:** either the unsigned or the historic signed byte sum is accepted, as GNU tar
    accepts both.
  - **Numeric fields:** optional leading spaces, then digits 0-7, then only NUL or space.
    Base-256 is rejected.
  - **End of archive:** only an all-zero block ends it. A header with an empty name is skipped,
    not treated as the end.
  - **Unchanged:** link, directory and traversal entries are still skipped, not rejected.
  - **Extraction:** writes nothing unless the whole archive validates.
- **`rating_from_json` / `rstore_from_json` / `rstore_load`** reject a rating whose score is
  outside `MIN_SCORE..MAX_SCORE`, the range `rstore_add_rating` already enforced. One bad rating
  rejects the whole file, the same as any other corrupt file. `stats_dist(s, score)` returns `0`
  for a score outside the distribution.
- **`kv_from_json`** (and the loader) requires each of these fields, with its type:
  - `key_id` and `public_key_hex`: strings;
  - `valid_from` and `has_until`: integers, with `has_until` 0 or 1;
  - `valid_until`: an integer when `has_until` is 1.

  This is exactly what `kv_to_json` writes. Rust's serde treated a missing `valid_until` as
  `None`. mela's explicit `has_until` makes the absence of an expiry visible: a missing
  `has_until` is an error, not "never expires".
- **`keyring_load_dir`** **replaces** the keyring's contents, matching Rust's `load()`.
  - An absent directory empties the keyring and returns 0.
  - A file loads whole or not at all: one malformed version skips the file, matching Rust's
    `Vec<KeyVersion>` parse.
  - A non-JSON file is skipped and the rest still load.
- **`cat_parse`** returns `CAT_PARSE_FAIL` for input longer than 63 bytes. No category name is
  longer than 12.

Out of scope here, and tracked as their own items in [`../development/roadmap.md`](../development/roadmap.md)
v1.1.3 / v1.1.5: lenient decoding of manifests, publishers, transparency logs, sandbox profiles,
packaging configs and remote responses; an unknown `category` (D12); and the rest of the ratings
load leniency (empty file, read error, Rust's wire shape).

## Consequences

- **Positive**
  - No crafted bundle, ratings file or key file reaches a memory error.
  - Revoking a key is now "delete its file and reload". Before, it needed a fresh keyring.
  - The sandbox shown before install is the one installed.
  - A file mela itself wrote still decodes unchanged.
- **Negative**
  - Behavior change for API callers: a caller that added keys by hand and then called
    `keyring_load_dir` on the same keyring loses those keys. Load into a fresh keyring, or add
    the keys after loading.
  - Hand-written key files must now spell out `has_until`.
  - Archives with bad checksums that other readers tolerate are rejected.
- **Neutral**
  - The decode rule now exists for keys, ratings and bundles. v1.1.5 decides it for the
    remaining decoders.
  - The fuzz harness now reaches the tar parser directly (`_tar_scan` on raw input, plus header
    mutations of a real archive). Before, every seed failed the gzip CRC first.

## Alternatives considered

- **Skip bad elements instead of rejecting the file** (keys, ratings): this was mela's behavior
  before v1.1.1. Rejected because it silently drops records, for keys diverges from Rust, and a
  partial load of a tampered file is worse than a refused one.
- **Bounds-check only at the point of use** (`get_stats`): this is kept as defense in depth, but
  on its own it leaves an impossible score in a loaded store.
- **Verify the signature before parsing the manifest** in `pipeline_install`: this needs the
  publisher's `key_id`, which comes from the manifest. The reader has to be safe on unauthenticated
  input whatever the order.
