# 0013 — Every remaining divergence from rust-old, decided

**Status**: Accepted · §5 (file modes) and §6 (header modes, long names) amended by
[ADR-0014](0014-large-bundles-names-modes-limits.md) (v1.3.0); §5 (path containment) and §8 (hash
preimage) amended by [ADR-0015](0015-confined-extraction-and-transparency-hash-v2.md) (v1.4.0)
**Date**: 2026-10-15 (v1.1.5)

## Context

`rust-old/` is deleted at v1.1.6, after which nothing remains to check mela against. The
2026-10-14 parity audit ([`../development/rust-parity.md`](../development/rust-parity.md)) listed
behaviors where mela differed from Rust and no ADR said whether that was intended. Each one now
either matches Rust or is kept here on purpose, with the Rust behavior written down.

The maintainer made three policy decisions on 2026-10-15: strict decoding everywhere, Unicode text
handling as Rust did it, and rejecting ratings files written by the Rust version.

## Decision

### 1. Every decoder is strict, as Rust's serde was (maintainer decision)

This extends [ADR-0011](0011-fail-closed-decoding-at-the-trust-boundary.md), which covered keys,
ratings scores and bundles, and [ADR-0012](0012-fail-closed-install-and-transport.md), which
covered categories. The rule is now the same in every decoder:

- **Required fields** must be present with their type. A field is required wherever Rust's serde
  required it, meaning no `#[serde(default)]` and no `Option`.
- **Optional fields** may be absent and then take their default. If present with the wrong type,
  the input is rejected.
- **u64 / u32 / usize fields** reject negative values.

The decoders, and what each requires:

| Decoder | Required | Optional (default) |
|---|---|---|
| `manifest_from_json` / `_jv` | `name`, `version`, `description`, `publisher`, `category` | `runtime`, `changelog`, `min_agnos_version`, `screenshots`, `tags`, `dependencies` |
| `publisher_from_json` / `_jv` | `name`, `key_id` | `homepage` |
| `tlog_from_json` entries | all nine fields | — |
| registry `index.json` records | all six fields | — |
| `sresults_from_json` | `packages` (each result complete), `total`, `page`, `per_page` | — |
| `presp_from_json` | `name`, `version`, `download_url`, `replaced` | — |
| `update_from_json` | all four fields | — |
| `rating_from_json` / `rstore_from_json` | `agent_id`, `package_name`, `score` (1..5), `created_at`, `version_reviewed` | `review` (absent or null) |
| `stats_from_json` | `package_name`, `average_score`, `total_ratings`, `distribution` (keys `1`..`5`, read whole) | `latest_review` (absent or null) |
| `profile_from_json` | a known `preset`, `landlock_rules`, `seccomp_mode`, `network.enabled`, `max_memory_mb`, `allow_process_spawn` | `network.allowed_hosts` |
| `sbprofile_from_json` | `landlock_paths`, `seccomp_mode`, `network.enabled` | `network.allowed_hosts` |
| `pfconfig_from_json` | `app_name`, `version`, `publisher`, `description` | `category` (DesktopApp), `wayland_requirements`, `network_access`, `data_dir` |

Consequences of the rule:

- `rstore_load` returns 0 for a file that exists but is empty, unreadable, a directory or over
  1 MiB, as Rust's `load` returned an error. A missing file is still an empty store.
- `sandbox_preset_json_parse` returns -1 for an unknown name instead of Custom.
- An unknown Wayland protocol name is rejected instead of becoming Core.

Timestamps stay **i64 epochs** in every mela format ([ADR-0003](0003-trust-time-and-deferred-keyring-load.md),
[ADR-0004](0004-transparency-timestamp-epoch.md), [ADR-0007](0007-ratings-f64-and-sandbox-rule-types.md)).
Rust wrote RFC 3339 strings, so a file in Rust's shape is now refused by type, where before it
loaded silently with zeros.

### 2. Ratings files written by Rust are refused (maintainer decision)

Rust wrote `{"ratings": {pkg: {agent: Rating}}}` with RFC 3339 `created_at`. mela writes
`{pkg: {agent: Rating}}` with integer `created_at`. A Rust-written file now fails strict decoding
(the inner values are not ratings, and the timestamp is a string), so `rstore_load` returns 0. It
used to load as a package named `ratings` holding empty ratings. There is no migration code. If
such files turn up, a converter is a separate tool, not a load-time path.

### 3. Text is handled as Unicode, as Rust did (maintainer decision)

- **Lowercasing** (`manifest_qualified_name`, `mela_registry_search`, `cat_parse`) uses the
  stdlib's `str_lower_unicode`. That is Unicode 17's simple 1:1 mapping. Rust's `to_lowercase`
  uses the full mapping, and the two differ only in a few context-sensitive cases:
  - final sigma: Rust writes `ς` at the end of a word, mela always writes `σ`;
  - `İ`: Rust writes `i̇` (two code points), mela writes `i`.

  Package names are ASCII-only by validation, so this reaches only publisher names,
  descriptions, tags and category input.
- **`sanitize_filename`** maps per character, not per byte. Letters and digits in any script, `-`
  and `_` are kept, and every other character becomes a single `_`. "Letter or digit" is
  general category L*, Nd, Nl or No. Rust's `is_alphanumeric` also includes the
  `Other_Alphabetic` combining marks (for example, Indic vowel signs), which mela turns into `_`.
  An invalid UTF-8 byte becomes `_`.
- **Cost:** the Unicode tables add about 170 KB to mela's binary. `cyrius distlib` records
  `lib/unicode` as a single leaf, so a consumer including `dist/mela.cyr` compiles in the whole
  directory, normalization tables included (about 350 KB of source in total).

### 4. Other text behavior

| Behavior | Rust | mela | Decision |
|---|---|---|---|
| A semver segment over u64 | rejected | was accepted | **matched**: rejected |
| A leading `+` in a semver segment (`+1.0.0`) | accepted (`u64::from_str` quirk) | rejected | **kept**: no version is written with a sign, and accepting one widens what a "valid" manifest means for no user |
| `FLUTTER_FORCE_SCALE_FACTOR` | shortest round-trip (`4/3` → `1.3333333333333333`) | 2 decimals (`1.33`) | **matched**: bayan's Grisu2, `1` not `1.0`, NaN / inf / -inf spelled as Rust does. Grisu2 is near-shortest, so in rare cases it prints one digit more than Rust; it never prints a value that reads back differently |
| Validation messages | quote the bad value | omitted it | **matched**: the same `format!` text |
| `validate_profile` with `max_memory_mb` < 0 | impossible (u64) | accepted | **matched**: rejected |

### 5. Install accounting and extraction

- **`installed_size`:** **matched.** It records the extracted size (the summed sizes of the safe
  entries, from the new `agpkg_payload_size`), as Rust did. The quota check before install still
  uses the bundle size, as Rust's did.
- **File modes:** **deferred to v1.2.0.** Rust kept `mode & 0o777` from each tar header. mela
  writes every file as 0644. The extractor is rewritten for streaming at v1.2.0, and keeping the
  executable bit is decided and done there. *Decided at v1.3.0 (ADR-0014): 0755 if the header's
  owner-execute bit is set, otherwise 0644.*
- **Path containment:** **kept, and stronger.** Rust resolved each output path and checked it stayed
  under the destination. mela never writes a symlink, hardlink or directory entry, an absolute
  name, or any name containing `..` ([ADR-0011](0011-fail-closed-decoding-at-the-trust-boundary.md)),
  so archive content cannot point outside the destination. One residual case is a symlink
  already present inside the destination. That is roadmap v1.3.0 (`O_NOFOLLOW`). *Closed at
  v1.4.0 (ADR-0015): extraction walks the destination with `openat` + `O_NOFOLLOW`.*

### 6. The archive writer

- **Normalized header metadata:** **kept.** Every entry is written with mode 0644, uid/gid 0 and
  mtime 0. Rust copied each source file's mode, owner and mtime. Normalizing makes a bundle a pure
  function of its inputs, so the same build produces the same bytes and the same digest. That is
  what the transparency log and `pipeline_install`'s digest gate compare.
- **Compact JSON:** **kept.** `manifest.json` and `sandbox.json` inside a bundle are compact,
  where Rust pretty-printed them. JSON whitespace has no meaning, and nothing compares mela
  bundles to Rust bundles byte for byte.
- **Long names and unreadable files:** both fail the pack ([ADR-0012](0012-fail-closed-install-and-transport.md)).
  Long-name support is v1.2.0. *v1.3.0 (ADR-0014): a source file with an execute bit is written
  0755; names up to 256 bytes pack through the ustar prefix.*

### 7. Keyring loading

The clear-on-load and whole-file skip are [ADR-0011](0011-fail-closed-decoding-at-the-trust-boundary.md).
A file named exactly `.json` is now skipped, matching Rust's `Path::extension()`. The 1 MiB
per-file read cap is **kept**: a larger file reads truncated, fails to parse, and is skipped like
any malformed file.

### 8. The transparency hash preimage

**Recorded; the fix is v1.3.0.** The entry hash covers the decimal timestamp immediately followed
by the package name. So timestamp `1000` with package `1/x` hashes the same as timestamp `10001`
with package `/x`. Rust's RFC 3339 timestamp ended in `+00:00`, a fixed terminator that avoided
this. The package/version boundary is ambiguous in both (`a/b` + `11.0.0` = `a/b1` + `1.0.0`).
Changing the preimage changes every entry hash, so it needs a versioned hash, where v1 logs still
verify on import. Until then, two entries can share a hash only when digits move between the end
of the timestamp and the start of the package name, which a package whose qualified name begins
with a digit makes possible. It is recorded now and fixed as a format change in v1.3.0. *Fixed at
v1.4.0 (ADR-0015): new entries use hash v2; v1 entries still verify.*

## Consequences

- **Positive**
  - Every intentional difference from Rust is written down, so `rust-old/` can be deleted without
    losing the oracle's information.
  - Malformed input fails the same way everywhere.
  - Non-English text behaves as Rust did.
  - Cache filenames no longer collide on non-ASCII queries.
  - The scale factor reaches the engine unrounded.
- **Negative**
  - Behavior changes for callers:
    - Any hand-written JSON a consumer feeds mela must be complete. A `{}` or partial object that
      used to decode now returns 0.
    - `rstore_load` can return 0 where it used to return an empty store.
    - `sandbox_preset_json_parse` can return -1.
  - The binary grows by about 170 KB (Unicode tables), and consumers of the bundle compile in
    all of `lib/unicode`.
- **Neutral**
  - v1.2.0 (file modes) and v1.3.0 (destination symlinks, hash v2) carry the deferred items.

## Alternatives considered

The maintainer weighed these on 2026-10-15:

- **Strict only for input from outside mela, lenient for files mela wrote itself.** Two rules
  instead of one, and a corrupted local file still loaded as half-defaulted state.
- **Keep ASCII-only text handling.** Simpler and smaller, but non-English publisher names and
  descriptions would search case-sensitively, and non-ASCII queries could share cache files.
- **Read the Rust ratings format too, or switch to it.** That means migration code and an RFC 3339
  path for files that may not exist. Rejecting clearly is reversible: a converter can be added if
  such files appear.
