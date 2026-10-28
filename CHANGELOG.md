# Changelog

All notable changes to Mela are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Performance claims must
include benchmark numbers; breaking changes get a **Breaking** section with a migration note.

## [1.5.1] - 2026-10-28

**Publisher key continuity on upgrade**
([ADR-0016](docs/adr/0016-publisher-key-continuity-on-upgrade.md)). Until now any key in the
keyring could upgrade any installed package, including another publisher's. Now an upgrade must
be published under one of:
- the installed version's key;
- a successor the keyring declares;
- a key the operator approved for that one install.

The maintainer chose the override mechanism (keyring succession plus one-shot approval) on
2026-10-28.

**Gates:** 1195 passed / 0 failed (was 1146); fuzz 1 / 0; bench 1 / 0; coverage 89% (303/338).
The API surface is 339 public fns (4 added; the CI gate caught them until the snapshot was
updated). The GNU tar cross-check and the live transport check pass, and `--agnos` / `--aarch64`
build with no `src/` warnings.

### Breaking — upgrades under another key are refused

`pipeline_install` returns 0, writing nothing, for an upgrade whose publisher `key_id` differs
from the installed version's, unless the keyring declares the new key a successor or the operator
approved the change. It used to install it. Fresh installs are unaffected (trust on first use),
and so are upgrades under the same key.

**Migration:**
- **For a publisher's key rotation:** add `"succeeds": ["<old key_id>"]` to the new key's entry
  in its key file.
- **For a one-off change** (a package moving to a new publisher): call
  `registry_allow_key_change(reg, name, new_key_id)` before that install.
- **Ask first:** `registry_key_continuous(reg, keyring, pipeline_extract_manifest(bundle))` tells
  a consumer when to ask.

### Added

- **The check:** in `pipeline_install`, after gates 1 and 2 and before the quota and extraction.
  - A refused upgrade leaves the installed version, its files and its index record as they were
    (on disk and after reopening).
  - Gate 1 still runs first, so neither override lets an untrusted key in.
- **`succeeds` on a key-file entry:** optional, an array of `key_id` strings. Anything else
  refuses the whole file (ADR-0011).
  - `kv_to_json` writes it only when non-empty, so existing key files re-export unchanged.
  - Succession is followed transitively across every version of each key, whatever its validity
    window. A visited set ends cycles.
  - `kv_succeeds(kv)` and `kv_add_succeeds(kv, key_id)` read and extend it.
- **`registry_allow_key_change(reg, name, key_id)`** approves the next install of `name` under
  `key_id`:
  - it is held in memory only, not saved;
  - a later call replaces it;
  - the install it allows uses it up, and a failed install leaves it pending;
  - an approval on one registry object does not carry over to another.
- **`registry_key_continuous(reg, keyring, manifest)`:** `1` if the manifest may be installed as
  far as continuity goes, else `0`.
- **Unchanged:** `registry_install`, the low-level, unsigned record call, does not check
  continuity. Its records still pin their `key_id`, which `manifest_validate` already required to
  be non-empty.

### Changed — a test that pinned the old behavior

The v1.4.0 `keyring-provenance` assertion "a second trusted key can upgrade it" now asserts the
refusal, under ADR-0016.

### Verified

- **New tests (49):** the `key-continuity` group, plus the guide's rotation example in
  `keyring-provenance`. They cover:
  - fresh installs, same-key upgrades, refusals;
  - approvals for the wrong package or key;
  - approval use-up, and approval surviving a failed install;
  - the gate-1-first rule;
  - direct, chained and reverse succession, succession declared on an expired version, and
    cycles;
  - a `registry_install` record's pin;
  - on-disk refusal and reopen;
  - the `succeeds` JSON rules and loading from disk.
- **Mutations:** five applied to the new code (no check; approval never used up; succession not
  transitive; approval for any key; succession ignored). All five turn tests red.
- **Bench:** no change to the timed code; `agpkg_inspect` 116.3 µs, `ed25519_verify` 5.30 ms,
  within run-to-run variation.

### Docs

- **ADR-0016** is new.
- **The keyring provenance guide:**
  - the key-file table gains `succeeds`;
  - rotation now declares succession, with a tested example;
  - the pinning section describes the built-in rule, approvals and the ask-first call, where it
    used to tell consumers to write the check themselves.
- **The threat model:** continuity is now a control in the pipeline order. The gap narrows to
  *new names are first come, first served*.
- **Also updated:**
  - the audit status (finding G), SECURITY.md (key continuity), the ADR index, the parity table
    (a stricter-than-Rust row), the API reference, the roadmap (two trust follow-ups remain) and
    state.md;
  - `docs/api-surface.snapshot` (+4).

## [1.5.0] - 2026-10-28

**API and build hygiene.** No behavior change.
- The API freeze is checked in CI.
- The build has no warnings from `src/`.
- The test-only stdlib leaves no longer reach the production binary.

**Gates:** 1146 passed / 0 failed; fuzz 1 / 0; bench 1 / 0; coverage 89% (299/334). The GNU tar
cross-check and the live transport check pass, and `--agnos` / `--aarch64` build.
`cyrius build` OK (3,611,880 B, was 3,629,152).

### Added — the API surface is checked

- **`docs/api-surface.snapshot`** lists all 335 public fns as `module::name/arity`. It is written
  by `cyrius api-surface --update --scope=project`, which is deterministic and sorted.
- **A new CI step** (after the build):
  - `cyrius api-surface --scope=project` fails on a removed fn or a changed arity;
  - `--update` followed by `git diff --exit-code` also fails on an addition missing from the
    snapshot. So the snapshot is always the complete list, and a later removal of an added fn is
    caught too.
  - Checked locally: a removed fn exits 1; an added fn exits 0 from the tool and is then caught
    by the diff.
- **Docs:** `docs/api/README.md` points to the snapshot as the complete list. A one-off check
  found every function the page names public in `src/` (the one exception is the stdlib's
  `str_from`). CONTRIBUTING gains the command and the rule; the roadmap's working rules mention
  the check.

### Fixed — the three `assigning non-pointer to typed pointer` warnings

None hid a bug. Each assigned a `Str` that the compiler saw as `i64` to a local inferred as
`Str`:

| Site | Value | Change |
|---|---|---|
| `src/ratings.cyr` `_rating_from_jv`, `review` | `json_v_str(rv)`, which returns the stored `Str` | read through `_r_jstr(o, "review")` (typed `: Str`), the same lookup |
| `src/flutter_agpkg.cyr` `pfconfig_from_json`, `data_dir` | `json_v_str(ddv)` | read through `_ag_jstr(root, "data_dir")`, the same lookup |
| `src/flutter_agpkg.cyr` `fbuild_validate`, `aot_s` | `_find_aot(root)`, a `Str` or 0, checked before use | `_find_aot` is now typed `: Str` |

Existing tests cover each path (a rating with a review, a config with `data_dir`, the AOT lookup
order). The only build warning left is the stdlib's note about large static data (the Unicode
tables).

### Changed — `assert` / `bench` in `[test] stdlib`

- **What moved:** `cyrius.cyml` moves `assert` and `bench` from `[deps] stdlib` to a new `[test]`
  section (cyrius 6.7.6). They reach `cyrius test`, `bench` and `fuzz` compiles only. No file in
  `src/` or `scripts/` uses them.
- **Unchanged:** `lib/` and `cyrius.lock` (the resolve still vendors and locks test leaves), and
  `dist/mela.deps`. `cyrius deps --locked` passes.
- **The production binary is 17,272 B smaller.**

### Docs

The roadmap's v1.5.0 section is removed, and state.md is updated.

## [1.4.0] - 2026-10-28

**Hardening residuals** ([ADR-0015](docs/adr/0015-confined-extraction-and-transparency-hash-v2.md)):
- extraction is confined below the install directory;
- the transparency hash has an unambiguous v2 that v1 logs coexist with;
- the threat model, the audit's status and SECURITY.md are refreshed;
- a keyring provenance guide is new.

**Gates:** 1146 passed / 0 failed (was 1075); fuzz 1 / 0; bench 1 / 0; coverage 89% (299/334).
The GNU tar cross-check and the live transport check pass, and `--agnos` / `--aarch64` build.
`cyrius build` OK (3,629,152 B).

### Breaking — what extraction refuses, and log compatibility

- **Symlinks fail the extraction.** `agpkg_extract_to_dir` returns `-1`, and `pipeline_install`
  0, when the destination is a symlink, or a symlink sits anywhere below it on a written path.
  It also fails for a non-directory on a directory's path, and for a directory, device or
  symlink where a file goes. These used to be followed or overwritten.
- **Existing files are replaced, not written into.** A regular file already at an entry's path
  is unlinked and recreated, so a hard link elsewhere keeps its bytes.
- **Directories created below the destination are 0755** (umask applied); they were 0777.
- **New transparency entries hash differently (v2)**, and a log containing one does not import
  into mela 1.3.0 or earlier. Logs written by earlier releases import and verify unchanged.

**Migration:**
- An install directory holding a symlink must be cleaned up by hand. mela reports it and does not
  remove it.
- Keep every reader of a shared transparency log on 1.4.0+ before it gains a v2 entry.

### Added — confined extraction (ADR-0015 §1)

- **The walk (Linux, x86_64 and aarch64):**
  - the destination is opened with `O_DIRECTORY | O_NOFOLLOW`;
  - each directory component goes through `mkdirat` + `openat(O_DIRECTORY | O_NOFOLLOW)`;
  - `fstatat(AT_SYMLINK_NOFOLLOW)` must find nothing or a regular file, which is then unlinked;
  - the file is created with `openat(O_CREAT | O_EXCL | O_NOFOLLOW)`, written and `fchmod`ed.
- **agnos** has no `*at` calls, so its build checks each component by path (`is_symlink`) and
  creates with `O_EXCL | O_NOFOLLOW`, with a race window. Built, not run.
- **Rollback:** a fresh install's rollback removes only a real directory. A symlink at
  `packages/<name>` is left as found.

### Added — transparency hash v2 (ADR-0015 §2)

- **The preimage:** `BE8(len(tag)) ‖ "mela.transparency.entry.v2" ‖ BE8(sequence) ‖ BE8(timestamp)`,
  then `BE8(len) ‖ bytes` for package, version, key_id, content_hash, signature_hash and
  previous_hash. v1 was the Rust-shaped concatenation:
  - timestamp `1000` + `1/x` collided with `10001` + `/x`;
  - `a/b` + `11.0.0` collided with `a/b1` + `1.0.0`.

  Both collisions are now asserted for v1 and absent in v2.
- **New API:** `log_hash_version(e)`, `log_set_hash_version(e, v)` (refuses unknown versions),
  and `LOG_HASH_V1` / `LOG_HASH_V2`. `tlog_append` and `log_entry_new` make v2 entries.
- **JSON:** v2 entries carry `"hash_version": 2`; v1 entries carry nothing, so a v1 log
  re-exports byte for byte. A missing field reads as 1; any value other than the integers 1 and 2
  refuses the log.
- **Verification:**
  - `tlog_verify_chain` refuses an entry whose version is lower than the one before it;
  - `log_entry_verify_self` never accepts an unknown version.

### Docs

- **[`docs/guides/keyring-provenance.md`](docs/guides/keyring-provenance.md)** (new) covers:
  - what a key file is, and how install uses it;
  - distributing the keyring, never from the bundle registry;
  - admitting a publisher, including checking the `key_id` derives from the public key;
  - rotation, and why expiry also stops installs of everything the old key signed;
  - revocation, and finding what a key signed;
  - pinning for consumers (ark). Today any trusted key can upgrade any package, and the guide
    gives the check to add.

  A `keyring-provenance` test runs its example key file and both of its checks.
- **Threat model:** current as of v1.4.0.
  - It adds B4 (installed apps writing inside their install directory) and the
    installation-confinement controls.
  - *Known gaps* are restated: key continuity, log equivocation (including dropped tail
    entries), gate 2's independence and empty-digest skip, pre-signature parsing, the 16 MiB
    in-memory tar, agnos's path-based confinement, the operator-owned keyring, and verify cost.
- **Audit:** a *Status at v1.4.0* section maps findings A–J and the v0.9.0 follow-ups to where
  they stand. The dated findings are unchanged.
- **SECURITY.md:**
  - TLS is the stdlib's native TLS with system roots (it said rustls);
  - the digest claim states the empty-digest skip;
  - the transparency claim states it does not prevent equivocation;
  - confinement is listed;
  - security fixes land on the latest 1.x.
- **Roadmap:** v1.4.0 is removed. Three trust follow-ups are proposed, each needing a decision
  and an ADR: key continuity on upgrade, a `key_id` check on key-file load, and log
  equivocation.
- **Also updated:** ADR-0004 and ADR-0013 carry amendment notes; the parity table (containment
  stronger; preimage fixed), the API reference, state.md, the README and the getting-started
  guide link the new guide.

### Verified

- **Tests (71 new):**
  - `confinement`: symlinks below, deep and at the destination; a symlink at the file; hard
    links; a directory or file in the way; nesting with `./` and empty components; directory
    modes; a symlinked install dir and a symlink planted for an upgrade, through the pipeline.
  - `transparency-v2`: two known-answer hashes computed independently with Python `hashlib`
    (one with a negative timestamp); both v1 collisions; a v1 log captured from mela 1.3.0
    (hashes also recomputed in Python) importing, verifying and re-exporting byte for byte;
    appending v2 to it; relabelling; downgrade; unknown and string versions.
  - `keyring-provenance`: the guide's example and checks.
- **A sharpened test:** the strict-decode RFC 3339 test now carries `hash_version: 2` and a
  control, so only its type check can refuse it.
- **Mutations:** ten applied to the new code; nine turn tests red.
  - One of the nine crashes the older `transparency-json` group (it dereferences a refused
    import), which still fails the run.
  - The tenth, making the final create `O_TRUNC`, stays green: the `fstatat` check catches
    those cases first, and `O_EXCL | O_NOFOLLOW` only matters in a race window a
    single-threaded test cannot open.
- **Bench:** no change: `agpkg_inspect` 112.7 µs, `ed25519_verify` 5.08 ms, `sha256_hash` 764 ns,
  `manifest_validate` 152 ns, `registry_get` 65 ns.

## [1.3.0] - 2026-10-28

**Large bundles, part one**
([ADR-0014](docs/adr/0014-large-bundles-names-modes-limits.md)): long names, file modes, a 100 MiB
bundle cap, the quota before any write, and a 16 MiB ceiling. Streaming extraction is blocked on
sankoch and is filed there.

**Gates:** 1075 passed / 0 failed (was 979); fuzz 1 / 0; bench 1 / 0; coverage 89% (296/332; the
floor stays 88). The GNU tar cross-check (now with long names and modes both ways) and the live
transport check pass, and `--agnos` / `--aarch64` build. `cyrius build` OK (3,624,984 B, +8,240).

The maintainer chose three things on 2026-10-28:
- **Scope:** ship what does not need sankoch now.
- **Modes:** 0755 or 0644, not Rust's `mode & 0o777`.
- **Long names:** support them, not reject them.

### Breaking — what install accepts and writes

- **Files with the owner-execute bit extract as 0755.** All others are 0644, as before. Header
  bits are never copied: no setuid, setgid or sticky bit, and nothing group- or world-writable.
  The mode is set with `fchmod` after the write, so an upgraded file takes it too.
- **More archives are rejected outright.** `agpkg_*` return 0 (`-1` from `agpkg_extract_to_dir`)
  and `pipeline_install` returns 0 when:
  - a mode field is not strict octal;
  - a PAX record is malformed, or a PAX `size` disagrees with its header;
  - a global PAX record carries `path` or `size`;
  - a long name is over 1,024 bytes, or has no entry after it;
  - a GNU `L` / `K` or PAX `x` / `g` entry is over 64 KiB.
- **Entries are named by their full name.** Names come from the ustar prefix, GNU `L` and PAX
  `path`, so `agpkg_inspect` lists, and `agpkg_read_entry` matches, the full name. These entries
  used to be read under their truncated 100-byte header name. A name ending in `/` is now skipped
  as a directory.

**Migration:** nothing for bundles mela packed. For a bundle built with another tool, its long
entries now install under their real names. A file that must not be executable must not have the
owner-execute bit in its header.

### Added — long names (ADR-0014 §4)

- **Reading:** the effective name is a PAX `path`, else a GNU `L` name, else ustar prefix + `/` +
  name. The prefix counts only under the POSIX magic; GNU's own magic keeps other data there.
  - Each record applies to the next header only.
  - The absolute, `..` and duplicate checks apply to the effective name.
  - `K` and the other PAX keys are read and ignored.
- **Writing:** names of 101–256 bytes are split across the prefix and name fields at the last `/`
  that fits, GNU tar's rule. A longer name, or a last component over 100 bytes, still fails the
  pack. mela writes no `L` or `x` entries.
- **Before this:** mela ignored the prefix field and the `L` / `x` records. A long-named entry from
  GNU tar was read under its truncated header name.

### Added — file modes (ADR-0014 §3)

- **Packer:** a source file with any execute bit is packed 0755, otherwise 0644. `manifest.json`
  and `sandbox.json` stay 0644, and uid, gid and mtime stay 0. A bundle is still byte-identical for
  identical inputs, which a test checks.
- **Entries:** `tentry_mode` / `tentry_set_mode` carry the mode; `tentry_new` defaults to 0644.

### Added — size limits and the quota (ADR-0014 §1–2)

- **`AGPKG_MAX_PACKAGE_SIZE` (100 MiB, Rust's `MAX_PACKAGE_SIZE`)** is checked first in
  `pipeline_install`, before it gunzips, hashes or verifies anything. A test pins it equal to
  `RC_DOWNLOAD_MAX_BYTES`. Under the 16 MiB ceiling no valid bundle reaches it, so no test can tell
  it from a missing check yet. It is the guard that stays once the ceiling lifts.
- **The quota is checked on the bundle size and the extracted size, both before extracting.**
  Which installs succeed is unchanged: the extracted-size check already ran in `registry_install`,
  only after the files were written. An upgrade refused there used to leave the new version's
  files over the old ones, with the old version still recorded. Now it writes nothing, which a
  test checks.
- **`AGPKG_BUF_MAXLEN` is 16 MiB (was 8 MiB):** sankoch's gzip output ceiling. Measured: 16,777,216
  bytes decode; one byte more returns `-ERR_OUTPUT_LIMIT`, whatever the buffer. A 9 MiB engine now
  packs and installs (tested end to end, with its 0755 mode). Inputs and tars over 16 MiB still
  fail the pack.
- **New constants:** `AGPKG_NAME_MAX` (1,024) and `AGPKG_EXT_MAX` (64 KiB).

### Changed — one inflate per install, and a tar cursor

- **One inflate:** `pipeline_install` used to inflate the bundle three times (the manifest, the
  payload size, the extraction). It now inflates once. On a 9 MiB tar (5.5 MB gzipped), best of 5:
  the three inflates took **1,005 ms**, the one takes **334 ms**. The public `agpkg_*` functions
  keep their signatures and still inflate once per call.
- **Tar cursor:** the walker (`_tar_cur_next`) yields one entry at a time. Extraction validates the
  whole archive in a first pass, then writes in a second. Once sankoch can stream gzip, each pass
  becomes a streaming inflate feeding the same cursor.

### Verified

- **Tests:** `long-names` (prefix, `L`, PAX, precedence, the malformed cases, extraction under a
  300-byte name), `file-modes` (header bits to disk, upgrade, packer modes, reproducibility) and
  `install-limits` (cap, 9 MiB install, over-ceiling refusal, quota with no write).
- **The 8 MiB assertions:** the three in `agpkg-archive` now assert the 16 MiB ceiling, under
  ADR-0014.
- **Mutations:** nine applied to the new code. Eight turn tests red; the ninth, removing the
  100 MiB check, cannot until the ceiling lifts.
- **Fuzz:** a byte sweep over an archive using all three long-name forms. Every byte of its first
  4,608 takes eight boundary values, and a mutated header is rescanned with its checksum
  recomputed.
- **GNU tar cross-check:**
  - mela → GNU tar: mela packs a 162-byte asset name and an executable engine; GNU tar lists and
    extracts them byte-exact and sees 0755 / 0644.
  - GNU tar → mela: gnu, ustar and pax archives with names of 150 bytes (all three formats) and
    300 bytes (gnu, pax). mela reads them byte-exact and extracts 0750 as 0755 and 0600 as 0644.
- **Bench:** `cyrius bench` medians of three: `agpkg_inspect` 113.5 µs (1.2.0: 111.7 µs);
  `manifest_validate` 153 ns; `sha256_hash` 758 ns; `registry_get` 65 ns; `ed25519_verify`
  5.10 ms. No regression.

### Dist

`dist/mela.deps` gains `syscalls` (`sys_fchmod`, `STAT_MODE`); `cyrius distlib --check` passes.

### Filed — sankoch

`docs/development/issues/2026-10-28-gzip-has-no-output-override-and-no-bounded-memory-inflate.md`
in sankoch:
- a gzip output override like zlib's `*_output_capped`;
- a bounded-memory inflate, to be counted with bote's need at sankoch's planned 2.9.5.

The roadmap parks streaming, bundles over 16 MiB and a streaming packer under *Blocked upstream*.

### Docs

- **ADR-0014** is new.
- **ADR-0008, ADR-0012 and ADR-0013** carry amendment notes.
- **Also updated:** the ADR index, the parity table (modes decided; package cap matched; quota
  kept stricter), the API reference, the roadmap, state.md and the README's leaf list.

## [1.2.0] - 2026-10-28

**cyrius 6.7.9 → 6.7.18, agnostik 1.12.0 → 2.0.0.** `cyrius build` OK (3,616,744 B, was 3,380,536).
979 passed / 0 failed; fuzz 1 / 0; bench 1 / 0; coverage 88% (292/330). The GNU tar cross-check and
the live transport check pass, and `--agnos` / `--aarch64` build. The only `src/` change is
agnostik 2.0.0's accessor rename (two calls) and `MELA_VERSION`.

### Breaking — `dist/mela.cyr` needs agnostik 2.0.0

The bundle now calls agnostik's 2.x accessor names, so a consumer that includes it must have
agnostik **2.0.0 or later** in scope. On agnostik 1.x it fails to compile (`AgentManifest_name` is
undefined). mela's own public API is unchanged.

**Migration:** move the consumer's `[deps.agnostik]` to `tag = "2.0.0"` and run agnostik's
`scripts/migrate-2.0.0.sh` over its sources (agnostik's `docs/migration/` has the full rename
map). ADR-0002's `amanifest_name` / `amanifest_version` are the 1.x spellings of
`AgentManifest_name` / `AgentManifest_version`.

### Changed — deps on the 6.7.18 line

| dep | was | now |
|---|---|---|
| agnostik | 1.12.0 | **2.0.0** (git; accessors renamed `<Struct>_<field>`, nothing removed) |
| sigil | 3.13.11 | **3.13.15** (stdlib) |
| sankoch | 2.8.3 | **2.8.9** (stdlib) |
| sandhi | 1.10.9 | **1.13.7** (stdlib) |

- **lib/:** `lib/agnostik.cyr` is byte-identical to agnostik 2.0.0's `dist/` (tag commit `e6d33aa`).
  Every stdlib file in `lib/` is byte-identical to `~/.cyrius/versions/6.7.18/lib`, the same file
  set with nothing left over (`cyrius lib sync --full --relock`).
- **cyrius.lock:** it now pins only agnostik 2.0.0's commit; the stale 1.7.1 and 1.12.0 pins are
  gone. `cyrius deps --locked` passes.

### Changed — agnostik 2.0.0 accessor rename

agnostik's `scripts/migrate-2.0.0.sh` rewrote `src/manifest.cyr`:
- `man_name` / `man_description` now call `AgentManifest_name` / `AgentManifest_description`
  (were `amanifest_*`);
- the header comment uses the new names.

No mela identifier collided with an old accessor name. AgentManifest's layout is unchanged in 2.0.0
(description still at +8, which `mela_manifest_new` and the test helper write directly).

### Changed — `dist/mela.deps` drops `unicode`

In 6.7.18 sigil includes bayan, which includes the unicode modules. `cyrius distlib` therefore
derives `unicode` as covered by `sigil` and drops it from the sidecar and the bundle's `Requires`
includes. Its compile check passes. The remaining leaves are thread_local, sigil, fs, sandhi and
sankoch.

### Build — one warning fewer

- **Gone:** sigil's "array local over the per-fn frame budget" warning.
- **Static data:** 475,168 → 172,960 B.
- **Still there:** the three `src/` "assigning non-pointer to typed pointer" warnings, as before
  (roadmap v1.5.0). No new warning, deprecated-call warning included.

### Verified — hot paths, no regression

`cyrius bench`, medians of three runs on the 6.7.18 build:

| Hot path | 1.1.6 recorded | 1.2.0 |
|---|---|---|
| `registry_get` | 70 ns | 66 ns |
| `manifest_validate` | 168 ns | 161 ns |
| `sha256_hash` | 816 ns | 759 ns |
| `agpkg_inspect` | 110.1 µs | 111.7 µs |
| `ed25519_verify` | 5.50 ms | 5.12 ms |

The runs were not alternated with the old toolchain, so they show only that nothing regressed.

### Docs

- **Roadmap re-sequenced:** this release takes v1.2.0, so each planned milestone moves up one minor.
  Large bundles is now v1.3.0, hardening residuals v1.4.0, API and build hygiene v1.5.0, and
  targets beyond x86_64 Linux v1.6.0. The ADRs, the parity record and two source comments keep the
  old numbers; a roadmap note maps them.
- **README:** the consumer snippet names agnostik 2.0.0.

## [1.1.6] - 2026-10-15

**`rust-old/` retired: the end of the Rust oracle.** The 6,208-line Rust original was mela's parity
reference from the v0.1.0 port scaffold until now. Everything it specified is carried by:
- the parity suite (`tests/mela.tcyr`, 202 of its 204 tests covered, 2 not applicable);
- the GNU tar and live transport checks in CI;
- [`docs/development/rust-parity.md`](docs/development/rust-parity.md) and ADR-0011/0012/0013.

It remains in git history before this release. No `src/` change apart from `MELA_VERSION`. All 979
tests pass, and every CI gate passes.

### Removed — `rust-old/`

`rust-old/` (`src/`, the Cargo files, `deny.toml`, `codecov.yml`, `rust-toolchain.toml`,
`LINES_OF_RUST.txt`) and its `.gitignore` line are gone. Nothing referenced it at build or test
time. Source and test comments that cite `rust-old/src/*.rs` stay as provenance, and the parity
record says so.

### Docs — the Rust-vs-Cyrius benchmark comparison, filled in

The comparison section of `docs/benchmarks-rust-v-cyrius.md` had been "deferred" since v0.8.1,
on the grounds that the Rust original depended on an `agnos-common` checkout. No such checkout
exists: its one external type, `AgentManifest`, comes from agnostik's own Rust crate. So, before
the deletion, the Rust original was built from git with that dependency pointed at agnostik
`3507c46` (the last commit whose `AgentManifest.version` is a `String`). Rust's own suite passed on
that build, 204/204.

It was then benchmarked against mela on the same host and inputs, with the batches of
`tests/mela.bcyr` and a clock-floor correction on both sides. Medians of three alternating runs,
Rust / Cyrius:

| Hot path | Rust | Cyrius |
|---|---|---|
| `registry_get` | 18 ns | 70 ns |
| `manifest_validate` | 62 ns | 168 ns |
| `sha256_hash` | 139 ns | 816 ns |
| `agpkg_inspect` | 7.8 µs | 110.1 µs |
| `ed25519_verify` | 30.7 µs | 5.50 ms |

Only that section of the document changed.

### Docs — the parity record is the oracle

- **CLAUDE.md** (wording approved by the maintainer):
  - "Cross-check against `rust-old/`" becomes "The parity record is the oracle".
  - "Do not modify `rust-old/`" becomes "Do not weaken or delete a parity assertion in
    `tests/mela.tcyr` without an ADR".
  - The *Scaffolding* and *Project Identity* text says the Rust original was retired.
  - The parity record is added under Documentation.
- **README, CONTRIBUTING, the getting-started guide, state.md, the roadmap and the parity record**
  describe the Rust original as retired. With this release, the parity record's retirement
  checklist is complete.
- **The roadmap's v1.1.x section is complete and removed.** v1.x is the open work.

## [1.1.5] - 2026-10-15

**Every divergence from rust-old decided.** Each behavior the audit found differing from Rust,
with no ADR to say whether that was intended, now either matches Rust or is kept on purpose in
[ADR-0013](docs/adr/0013-decided-divergences-from-rust-old.md). ADR-0013 records the Rust behavior
too, so it survives the deletion of `rust-old/` at v1.1.6. Three of the choices were policy, made
by the maintainer: strict decoding everywhere, Unicode text as Rust handled it, and refusing
Rust-era ratings files. 979 passed / 0 failed (was 894); every CI gate passes, and `--agnos` and
`--aarch64` build. `cyrius build` OK (3,380,536 B, +170 KB of Unicode tables).

### Changed — every decoder is strict, as Rust's serde was

The rule ADR-0011 and ADR-0012 applied to keys, ratings scores, bundles and categories now holds
for every `*_from_json`:

- **Required fields:** missing or of the wrong type means the input is rejected.
- **Optional fields:** absent takes the default; present with the wrong type is rejected.
- **Unsigned fields** reject negative values.
- **Unknown enum names** are rejected. An unknown sandbox preset used to become Custom, and an
  unknown Wayland protocol used to become Core.

This covers manifests, publishers, transparency entries, registry index records, search results,
publish responses, update records, ratings, rating stats, sandbox profiles, the Flutter sandbox
profile and packaging configs. ADR-0013 has the per-decoder field table.

- **Fewer silent defaults:** `{}` is no longer a valid search result, update record or sandbox
  disclosure.
- **`rstore_load`:** returns 0 for a file that is empty, unreadable, a directory or over 1 MiB,
  as Rust's `load` returned an error. It used to return an empty store. A missing file is still
  an empty store.
- **`stats_from_json`:** reads each distribution key whole. Before, `"10"` counted as score 1.
- **Rust-era ratings files** (a `ratings` wrapper and RFC 3339 timestamps) are refused rather than
  loaded as garbage.
- **Proof:** the new `strict-decode` group has 33 assertions that fail against the 1.1.4 decoders.

### Changed — Unicode text, as Rust handled it

- **Lowercasing** (`manifest_qualified_name`, registry search, `cat_parse`) uses the stdlib's
  Unicode lowercase. `ÄRZTE Team` qualifies as `ärzte-team`, and `ÜBER` matches `über`. Rust's
  context-sensitive special cases (final sigma, dotted İ) are noted in the ADR.
- **`sanitize_filename`** keeps letters and digits in any script and turns each other character
  into a single `_`. `café` used to become `caf__`, and `café` / `cafè` shared one cache file.
- **The Unicode modules** are declared in `cyrius.cyml` and add about 170 KB to the binary.
  `distlib` records them as one leaf, so a consumer of the bundle compiles in all of
  `lib/unicode`.

### Changed — the remaining text and accounting differences, matched

- **Semver:** a segment over u64 is rejected, as Rust's parse rejected it. A leading `+` stays
  rejected; that is stricter than Rust and kept on purpose.
- **`FLUTTER_FORCE_SCALE_FACTOR`** is Rust's shortest round-trip form (`4/3` →
  `1.3333333333333333`, not `1.33`; `2` → `2`; NaN / inf spelled as Rust).
- **Validation messages** quote the bad value, word for word as Rust's `format!` strings did.
  `validate_profile` also rejects a negative `max_memory_mb`.
- **`installed_size`** records the extracted size (new `agpkg_payload_size`), as Rust did. The
  quota check before install still uses the bundle size, as Rust's did.
- **Keys:** a file named exactly `.json` is not a key file, matching Rust's `Path::extension()`.

### Kept or deferred, with reasons (ADR-0013)

- **Kept:** normalized archive metadata (reproducible bundles, so the digest is stable) and compact
  JSON inside bundles.
- **Kept, stronger:** path containment. Links, directories, absolute names and `..` are never
  written.
- **Deferred to v1.2.0:** keeping file modes on extraction.
- **Deferred to v1.3.0:** the transparency hash-preimage ambiguity, which needs a versioned hash
  format.

## [1.1.4] - 2026-10-15

**Rust test coverage closed.** Every one of rust-old's 204 tests now has its assertions in the
Cyrius suite (202), or is recorded as not applicable with the reason (2). At the audit the suite
covered 171, with 23 partial and 10 missing. 894 passed / 0 failed (was 626); every CI gate passes,
and `--agnos` and `--aarch64` build. No `src/` change except `MELA_VERSION`.

### Tests — the 22 partial and 8 uncovered Rust tests

- **lib / trust:** `category_all`, the random `generate_keypair` path, and `hex_roundtrip` over
  every byte, including uppercase, which Rust's `from_str_radix` accepts.
- **local_registry:** `count_files` (through `_rmtree`'s count), `install_with_missing_signature_file`,
  and the positive side of `storage_quota` (exactly full installs, one byte over is refused).
- **sandbox_profiles:** the seven partial preset tests in full, and the uncovered
  `aequi_profile_seccomp_and_memory`. The GPU profile's six hosts and thirteen rules are checked in
  Rust's order.
- **ratings:** the eight partial tests in full (stored package and version, the 2000-character
  review, every distribution slot, single-rating stats, filters where every result must match,
  per-package averages), and `stats_all_same_score`.
- **flutter_packaging / flutter_agpkg:** `validate_bad_dart_version`, the bad-engine message,
  the Wayland launch socket and scale, `FLUTTER_ENGINE_SWITCH_GL` in both modes, and
  `manifest_serializes_to_json`.
- **Not applicable (2):** `filter_serialization` and `display_backend_serde_roundtrip` tested
  serde derives on types nothing serializes, in Rust or in any mela consumer. The reason is
  recorded in `docs/development/rust-parity.md`. No unused codec was ported to satisfy them.

### Tests — behavior the Rust suite never checked

- **Transparency chain checks, each on its own.** Every earlier tamper test broke the entry's own
  hash first, so deleting a chain check left the suite green. The link, sequence and entry-0
  checks are now tampered with the hash recomputed. Disabling any one of them in
  `tlog_verify_chain` fails exactly its test (checked by mutation). Reordered and truncated imports
  are refused, and `[]` imports as an empty log.
- **Signature edge cases.** Lengths 63 and 65, a bit flip in R and in S, S + L (the malleable
  second encoding RFC 8032 §5.1.7 forbids), and an identity public key with R = identity, S = 0,
  which a non-strict verifier accepts. All rejected.
- **Keys:** rotation under one key_id, the inclusive validity-window edges (Rust compares with
  `<` / `>`), and uppercase hex keys.
- **depgraph:** self-loop and 3-cycle paths, full diamond ordering, re-add replaces, unknown and
  duplicate dependencies, sorted roots.
- **Manifests:** name length at 128 and 129, each invalid character class, exact error counts,
  semver edge inputs per Rust's split on the first `-` with three u64 segments, and every field
  round-tripped.
- **Ratings:** a non-integer average (4.5) ranks above 4.0, inclusive filter bounds, newest-first
  order all the way down, a rejected re-rating leaves the store unchanged, and the last call wins a
  dedup and replaces every field.
- **Registry and pipeline:** search over description and case, the name-sorted list, an upgrade
  through the pipeline, a signed bundle with an invalid manifest, and a bundle with no
  `manifest.json`.
- **Codecs:** search results, publish responses, update records, transparency entries and packaging
  configs all round-trip field by field.

### CI

- Reference coverage rises from 77% to **88%** (291/328), and the CI floor moves with it
  (`cyrius coverage --min 88`).

## [1.1.3] - 2026-10-15

**Correctness: audit defects D6–D12 fixed.** These are the cases where mela reported success but
did something else ([`docs/development/rust-parity.md`](docs/development/rust-parity.md)). Each fix
has a regression test. Run against the 1.1.2 sources, the D6, D9, D11 and D12 tests fail, and the
D8 tests crash the old test binary. D7 and D10's tests use new functions, so they can't run against
the old code; the old download path was instead probed directly (below). 626 passed / 0 failed
(was 553); fuzz, bench, the GNU tar cross-check and the new live
transport check all pass; `--agnos` and `--aarch64` build. `cyrius build` OK (3,210,272 B). New
[ADR-0012](docs/adr/0012-fail-closed-install-and-transport.md) records the changes in behavior.

### Fixed — artifact downloads failed over 256 KiB and could hang forever (D7)

`mela_fetch_artifact` (ark's download entry point) and `rc_download` used sandhi's buffered GET
with its default options. That meant a 256 KiB response cap, no timeout and no redirects. Probed
against a local server, that path returns status 0 with an empty body for a 1.5 MB file. The new
path gets all 1,500,000 bytes.

- **Streaming:** artifacts now stream to disk through a sink that enforces Rust's 100 MiB
  `MAX_PACKAGE_SIZE` (`RC_DOWNLOAD_MAX_BYTES`). Any failure removes the partial file.
- **On every request** (`_rc_options` / `_rc_headers`), as Rust's reqwest client did:
  - Rust's timeouts: 30 s connect/read, and a 30 s or 300 s deadline;
  - redirects followed, with a 10-hop cap;
  - `User-Agent: agnos-marketplace/<version>`. The version comes from a new `MELA_VERSION`, which
    a test pins to `VERSION`.
- **Buffered API responses** may be up to 1 MiB, the cache's read cap.

New **`scripts/transport-check.sh`** runs the real client against a local python3 server, and CI
runs it. It checks a 1.5 MB stream byte-exact, a 302 redirect, a 404 leaving no file, the size cap
leaving no partial file, a stalled server abandoned at a 2 s deadline, the User-Agent on every
request, and the publish metadata. `cyrius test` still opens no sockets.

### Fixed — publish never sent the signature (D10)

`rc_publish` now sends Rust's `X-Package-Metadata` header (`bundle_name`, `bundle_sha256`,
`bundle_size`, `signature: null`). The new additive **`rc_publish_signed`** sends the 64-byte
Ed25519 signature as hex. Rust read its binary `.sig` sidecar as a string, which can't carry 64
raw bytes.

### Fixed — six sandbox presets granted read-write to a garbage path (D6)

The presets passed the app's `data_dir` (already a Str) through `str_from`, which read the Str
header as a C string. PhotoEditor, Productivity, Browser, Game, CLI and GPU each got a 3-byte
garbage path as their first rule, instead of the app's data directory. All seven presets are now
tested; against 1.1.2 only Custom passes.

### Fixed — the packer truncated large files and dropped nested assets (D8, D11)

- **Truncation.** `file_read_all` stops at its limit without an error, so a 9 MiB engine was
  packed as its first 8 MiB, and the result "succeeded". The packer now fails on:
  - any file over 8 MiB or not fully readable (Rust errored; an unreadable asset used to be
    skipped);
  - any entry name over the 100-byte ustar field (it used to be truncated);
  - any archive the reader could not inflate.

  Real large bundles wait for streaming extraction (v1.2.0).
- **Nested assets.** The asset walk was one level deep, so it dropped `flutter_assets/fonts`,
  `shaders` and `packages/**`. It now recurses and skips symlinks, as Rust's `add_dir_to_tar` did.
  ADR-0008's "one level is the build layout" was wrong and is corrected. The GNU tar cross-check
  fixture now carries a nested font (7 entries).

### Fixed — installs were recorded before extraction; a corrupt index was silently emptied (D9)

- **Extract before record.** `pipeline_install` recorded the package, then extracted, and ignored
  the result of both the extraction and the index save. It now goes gates → `registry_admits`
  (new: quota and validation, no side effects) → extract → record and save, as Rust did. A
  failure at extract or save returns 0, and a fresh install's partial directory is removed.
  `agpkg_extract_to_dir` now fails on any write error.
- **Fail-closed index.** `mela_registry_new` returns **0** for an `index.json` that exists but
  won't load: unreadable, over 1 MiB, invalid, a directory, or holding a record that does not
  decode. It used to open as an empty registry, and the next install wrote over every record.
- **Saves.** `registry_save_index` creates missing parent directories, and `registry_install`
  undoes its insert if the save fails.
- **New tests.** The first **on-disk** end-to-end install (files under `packages/<name>`, reopen,
  uninstall), an install blocked at extraction, and a new `install-txn` group.

### Fixed — a manifest with an unknown or missing category installed as category -1 (D12)

`manifest_from_json` returns 0 for an unknown, missing or non-string `category`, as Rust's serde
did. The duplicate-entry half of D12 shipped in 1.1.1. All six categories round-trip by wire name.

### CI

- The live transport check runs in CI.
- The coverage floor rises to **77%** (253/328, from 249/326).
- `test_default_constants` and `test_storage_quota` are now covered (Rust tests: 174 covered /
  22 partial / 8 not, from 172 / 23 / 9).

### Behavior changes for callers (ADR-0012)

- `mela_registry_new` can return 0.
- `pack_flutter_app` refuses inputs it used to truncate.
- `manifest_from_json` needs a valid category.
- `mela_fetch_artifact` removes `dest_path` on failure.

## [1.1.2] - 2026-10-14

**CI now tests what it ships.** Until this release `ci.yml` resolved dependencies and built, and
nothing else: no tests, no fuzzing, no format check. The 1.1.1 fixes and everything after them
now land under a gate. No `src/` change: 553 passed / 0 failed.

### CI — the build job runs the gates

`.github/workflows/ci.yml`, which `release.yml` calls as its CI Gate, now runs:

- **`cyrius deps --locked`** (replaces `cyrius deps`, also in `release.yml`'s build). It
  resolves the tags and writes nothing; it fails, naming the file, if the committed `lib/` or
  `cyrius.lock` differ. Checked: one appended byte in `lib/agnostik.cyr` fails it.
- **`cyrius test`**, **`cyrius fuzz`**, and **`cyrius bench`** (a smoke run: the exit status is
  the gate; runner timings are not compared). Checked: a failing `.tcyr` makes `cyrius test`
  exit 1.
- **`cyrius coverage --min 76`**: the floor is the level reached, 249 of 326 `src/` fns. The
  v1.1.x coverage catch-up raises it and never lowers it.
- **The GNU tar cross-check** (below).

All seven steps were run in a clean copy of the tree, holding only the files git tracks plus the
new ones, and each exits 0. (`act` is not installed here, so the workflow itself has not run.)
The job keeps its name, `Build`, so a branch-protection rule that requires it still matches.

### Added — `scripts/tar-crosscheck.sh`, the format oracle

ADR-0008's cross-validation against GNU tar was run once, by hand, at v0.8.0. Once `rust-old/`
is deleted it is the only independent check that mela's bundles are real gzip + ustar, so it is
now a script and runs in CI. A small helper, `scripts/tar-crosscheck.cyr`, exposes mela's real
packer and reader (`pack` / `list` / `get`).

- **mela → GNU tar:** a Flutter build dir is packed with `pack_flutter_app`. `gzip -t` passes;
  GNU `tar -tzf` lists exactly the six expected entries, all regular files; `tar -xzf` extracts
  them. Each entry matches its source and mela's own reader byte for byte.
- **GNU tar → mela:** archives built by `tar --format=gnu|ustar|pax` list the same regular files
  in mela, and every one reads back byte for byte.

It runs in about 3 s. Checked: a packer that writes an off-by-one header checksum fails it at
"GNU tar cannot list mela's bundle".

## [1.1.1] - 2026-10-14

**Memory safety and the trust gate: audit defects D1–D5 fixed** (from
[`docs/development/rust-parity.md`](docs/development/rust-parity.md)). Each fix comes with a
regression test that fails against v1.1.0. `cyrius build` OK (3,206,056 B); 553 passed /
0 failed (was 492); fuzz 1 / 0; bench 1 / 0. `--agnos` and `--aarch64` build, and `distlib`
compile-verifies the bundle. New [ADR-0011](docs/adr/0011-fail-closed-decoding-at-the-trust-boundary.md)
records the stricter decoding.

### Security — a crafted bundle crashed `pipeline_install` before the signature gate (D1)

The ustar reader parsed the size field with `v*8 + (c-48)` for any byte, so `"!(1"` produced a
negative size. The reader then walked backwards. `pipeline_install` reads `manifest.json` out of
the bundle to find the publisher's key, before verifying anything, so an **unsigned 138-byte
bundle crashed it with SIGSEGV**.

One validating walker, `_tar_scan`, now sits behind inspect, read and extract, and the whole
archive is checked before anything is read or written. It rejects:
- a header whose checksum fails (unsigned or signed sum, as GNU tar accepts);
- a numeric field that is not strict octal;
- an entry whose data runs past the archive;
- two safe entries with the same name. Previously `agpkg_read_entry` returned the first copy
  while extraction wrote the last, so the sandbox disclosed before install could differ from
  the one installed (the duplicate-name half of D12).

Only an all-zero block now ends the archive. GNU, ustar and pax archives from GNU tar still read
byte-exact. New `tar-reader` test group (23 assertions), including the audit's crash input
through `pipeline_install`.

**Fuzzing now reaches the parser.** Every seed in `tests/mela.fcyr` failed the gzip CRC, so the
tar parser had never been fuzzed. The harness now:
- runs `_tar_scan` directly on raw input;
- mutates all 512 bytes of a real archive's first header to 8 boundary values, scanning each as
  is and again with the checksum recomputed;
- sends size-field mutations through gzip into `pipeline_extract_manifest`.

Performance: the stricter scan costs nothing measurable. `agpkg_inspect` divided by
`sha256_hash` within one run is 139–141× (138× at v1.1.0); absolute rows varied ±50% between
runs on a noisy host.

### Security — uninstall followed symlinks out of the install dir (D2)

`_rmtree` recursed whenever `is_dir` was true, and `is_dir` stats through symlinks. A link an
app left in its own install dir (`data -> $HOME`) got its **target's** contents deleted on
uninstall, and so did an install dir that was itself a link. `_rmtree` now unlinks a symlink
without following it, as Rust's `remove_dir_all` did. Tests plant both kinds of link; against
v1.1.0 they fail with the target's files gone.

### Security — out-of-range rating scores wrote past the heap (D3)

`rstore_from_json` accepted any score, and `rstore_get_stats` then indexed its 6-slot
distribution with it. A score outside 1..5 now rejects the ratings file (`rating_from_json` /
`rstore_from_json` / `rstore_load` → 0). `get_stats` guards the index as well. `stats_dist(s,
score)` returns 0 outside 0..5 instead of reading past the buffer. The fuzz harness runs
`rstore_top_rated` on every store it parses.

### Security — `cat_parse` overran a 64-byte stack buffer (D4)

Input longer than 63 bytes now returns `CAT_PARSE_FAIL`; the longest category name is 12 bytes.

### Security — revoked keys survived a reload; incomplete keys never expired (D5)

- `keyring_load_dir` **replaces** the keyring, as Rust's `load()` did with `keys.clear()`. A key
  file deleted between loads is now revoked. Before, it stayed trusted until the process made a
  fresh keyring.
  - An absent dir empties the keyring.
  - A file with one malformed version is skipped whole (Rust's `Vec<KeyVersion>` parse).
- `kv_from_json` requires every field `kv_to_json` writes. A missing `has_until` used to decode
  as "never expires", and a Rust-shaped file with RFC 3339 strings decoded as a key valid from
  epoch 0 forever. Now both decode to 0.

**Behavior change (ADR-0011):** a caller that added keys by hand and then called
`keyring_load_dir` on the same keyring loses them. Load into a fresh keyring, or add the keys
after loading. Hand-written key files must spell out `has_until`.

### Docs — `rust-old/` parity audit; roadmap rewritten

- **New `docs/development/rust-parity.md`.** All 204 Rust tests mapped to the Cyrius suite:
  171 covered, 23 partial, 10 not covered.
- **Twelve defects (D1–D12)** recorded with severity and proof status. Two were reproduced: a
  138-byte unsigned bundle crashes `pipeline_install` before the signature gate, and six sandbox
  presets carry a garbage data-dir rule.
- **Behavior changes with no ADR** listed, each with the Rust behavior written down so it
  survives the deletion of `rust-old/`.
- **`roadmap.md` rewritten.** Completed milestones are dropped (they live here). v1.1.x holds the
  fixes, a CI test gate, coverage catch-up, the divergence ADRs and the `rust-old/` retirement.
  v1.x maps the backlog.

## [1.1.0] - 2026-10-14

**cyrius 6.6.20 → 6.7.9.** `cyrius build` OK (3,201,960 B), 492 passed / 0 failed, fuzz 1 / 0,
bench 1 / 0. No `src/` change was needed: the build has the same four warnings as 1.0.5, and it
also builds for `--agnos` and `--aarch64`.

### Changed — deps on the 6.7.9 line

| dep | was | now |
|---|---|---|
| agnostik | 1.7.1 | **1.12.0** (git; additive only — no removals or signature changes since 1.7.1) |
| sigil | 3.13.10 | **3.13.11** (stdlib) |
| sankoch | 2.8.1 | **2.8.3** (stdlib) |
| sandhi | 1.10.8 | **1.10.9** (stdlib) |

`lib/agnostik.cyr` is byte-identical to agnostik 1.12.0's `dist/`, and every stdlib leaf in `lib/`
is byte-identical to `~/.cyrius/versions/6.7.9/lib` (`cyrius lib sync --full --relock`).

### Changed — git-first resolution (cyrius 6.7.6)

`cyrius.lock` gains agnostik's commit pin, the one-time diff 6.7.6 announces. `cyrius deps --locked`
reports `lib/` and the lock exactly as the tags resolve. The roadmap's 6.7.6 pin-move note is
marked applied.

### Changed — one bench harness: `tests/mela.bcyr` under `cyrius bench`

Both harnesses failed to compile, and neither break came from the bump:
- `benches/hotpaths.cyr` called `manifest_new`, which the pre-1.0 namespace pass renamed to
  `mela_manifest_new`.
- `tests/mela.bcyr` was the original `cyrius init` scaffold. It called `bench(...)`, which no
  stdlib version defines (cyrius fixed the template in 5.11.62), so `cyrius bench` failed.

The hand-rolled loop existed only because `cyrius bench` SIGILLed with sigil + sankoch linked in
at the v0.8.1 toolchain. On 6.7.9 it does not, so the five hot paths moved into
`tests/mela.bcyr` on `lib/bench.cyr` and `benches/hotpaths.cyr` is removed. CONTRIBUTING.md
already named `tests/mela.bcyr` as the place for benchmark numbers.
- Each row uses a fixed batch (`bench_run_batch`) sized so one window is about 1 ms or more.
  That clears the stdlib's 100× clock-error bar on this hpet host (floor 1.32 µs), so every
  row resolves its min and max.
- Every fixture is checked to take its success path before it is timed (verify returns 1, the
  manifest is valid, the lookup hits, the bundle inspects). Otherwise a row could time an early
  reject.

`cyrius bench` exits 0. Single run, avg (min – max) per op:

| Hot path | v1.1.0 | v0.8.1 (hand loop) |
|---|---|---|
| `registry_get` | 75 ns (69 – 82) | 72 ns |
| `manifest_validate` | 134 ns (126 – 145) | 389 ns |
| `sha256_hash` | 760 ns (738 – 804) | 1,016 ns |
| `agpkg_inspect` | 104.9 µs (63.9 – 155.0) | 96.9 µs |
| `ed25519_verify` | 5.15 ms (5.04 – 5.38) | 7.75 ms |

The two columns come from different harnesses, so they show no regression but are not a
measured speed-up. `docs/benchmarks-rust-v-cyrius.md` is re-captured at v1.1.0. The README,
getting-started guide and state.md now point at `cyrius bench`.

## [1.0.5] - 2026-10-14

**Zero deprecation warnings.** `cyrius build` OK (3,140,544 B, unchanged), 492 passed / 0 failed.

### Changed — `json_v_obj_get` → `bayan_json_v_obj_get_by_cstr`

All 39 call sites across 8 modules migrated off the name bayan deprecated in 1.5.10. Every key is
a C-string literal — the 21 direct calls, and all 70 calls into the per-module `_*_jstr` /
`_*_jint` / `_*_jbool` helpers — so `_by_cstr` is the right lookup everywhere and none needed
`_by_str`. No behavior change: the deprecated name already forwarded to `_by_cstr`. Build
warnings drop from 43 to 4 (the remaining four predate the 6.6.20 bump).

### Fixed — raw `sys_*` filesystem calls were wrong on agnos

agnos's `sys_unlink` / `sys_rmdir` / `sys_mkdir` are length-carrying — `(path, pathlen)` — where
Linux takes `(path)` / `(path, mode)`. Four call sites used the raw Linux shape:

- `_rmtree` (`src/local_registry.cyr`): `sys_unlink(path)` and `sys_rmdir(path)` — an arity error,
  so `dist/mela.cyr` did not compile for `x86_64-agnos` (the 1.0.4 `distlib` warning).
- `registry_save_index` (`src/local_registry.cyr`) and the cache-dir walk in
  `src/remote_client.cyr`: `sys_mkdir(path, 0o777)` — same arity on both targets, so it compiled
  and silently passed the mode as agnos's `pathlen`.

All four now go through the stdlib's portable bridges in `lib/io.cyr` (`xunlink` / `xrmdir` /
`xmkdir`), which compute the length on agnos and route Windows through kernel32. Linux behavior is
unchanged. `src/` has no raw `sys_*` calls left; `cyrius distlib` compile-verifies the bundle for
agnos with no warning, and `cyrius build --agnos` succeeds (3,100,624 B).

## [1.0.4] - 2026-10-14

**cyrius 6.6.2 → 6.6.20.** `cyrius build` OK (3,140,544 B), 492 passed / 0 failed.

### Changed — sigil, sankoch, sandhi come in as stdlib leaves

All three ship folded into the 6.6.20 stdlib, so their `[deps.*]` git blocks are gone and they
are listed in `[deps] stdlib` instead. This also ends the stacked `ERR_*` / `LOG_*`
duplicate-symbol warning the separate bundles produced.

| dep | was | now |
|---|---|---|
| agnostik | 1.6.0 (git) | **1.7.1** (git — last tag pinned to 6.6.20) |
| sigil | 3.12.16 (git) | **3.13.10** (stdlib) |
| sankoch | 2.7.14 (git) | **2.8.1** (stdlib) |
| sandhi | 1.9.16 (git) | **1.10.8** (stdlib) |

`lib/agnostik.cyr` is byte-identical to agnostik 1.7.1's `dist/`.

### Changed — `cyrius.cyml` is a manifest again

Dropped the commentary from `[lib]` and `[deps]`. Also dropped `path = "../agnostik"`: under
6.6.20 a `path` beside `git`/`tag` still wins locally, so it would have built against the sibling
checkout (agnostik main, pinned to 6.7.9) instead of the 1.7.1 tag that CI resolves.

### Changed — vendored stdlib re-synced to the 6.6.20 snapshot

`cyrius lib sync --full --relock` after the pin move: every stdlib leaf in `lib/` is byte-identical
to `~/.cyrius/versions/6.6.20/lib`, including the files outside the declared closure that
`cyrius deps` does not refresh.

### Changed — `dist/mela.deps` is now compile-derived

6.6.20's `cyrius distlib` verifies the bundle and records only the leaves it needs:
`thread_local`, `sigil`, `fs`, `sandhi`, `sankoch` (was a 37-entry copy of the stdlib list).

### Known — new warnings, not fixed here

- 39 `json_v_obj_get` deprecation warnings (bayan in 6.6.20 points at
  `bayan_json_v_obj_get_by_cstr` / `_by_str`). Build output is unaffected.
- `distlib` now also compile-checks `x86_64-agnos` and reports that `_rmtree` in
  `src/local_registry.cyr` calls `sys_unlink` / `sys_rmdir` with one argument, where agnos takes
  `(path, pathlen)`. Informational: agnos is checked but not required, and Linux is unaffected.

## [1.0.3] - 2026-09-10

**Every lib and dep brought current.** `cyrius build` OK (2,746,728 B), tests pass.

### Fixed — CI could not build: package dep tags were years stale

`[deps.*]` entries carry both `path` and `git`+`tag`. Locally the `path` wins, so builds resolved
the sibling working copies and passed; **CI has no `../` siblings, so it cloned the pinned tags**
and got pre-value-form sources — `lib/agnostik.cyr` was overwritten with the 1.3.1 artifact and
`lib/sandhi.cyr` with 1.7.0, producing a wall of `a ': stack' enum returns two values` errors.
Local success was an artifact of the `path` override.

| dep | was | now |
|---|---|---|
| agnostik | 1.3.1 | **1.6.0** |
| sigil | 3.9.7 | **3.12.16** |
| sankoch | 2.4.6 | **2.7.14** |
| sandhi | 1.7.0 | **1.9.16** |

Each verified against `git ls-remote` before bumping — all four exist and are pushed, so CI can
actually fetch them. agnostik, sandhi and sankoch now resolve byte-identical to their upstream
`dist/`.

### Changed — vendored stdlib re-synced to the 6.6.2 snapshot

`cyrius lib sync --full`. Six bundles were shadowing the pinned stdlib with stale copies —
ganita 1.0.1 → 1.2.4, niyama 1.0.5 → 1.0.10, yukti 2.2.6 → 2.3.10, patra 1.11.4 → 1.14.1,
vani 0.9.5 → 1.2.4, mabda 3.2.7 → 4.1.1. Every stdlib leaf in `lib/` is now byte-identical to
`~/.cyrius/versions/6.6.2/lib`.

### Removed — `lib/agnosys.cyr` (orphan)

Dated 2026-06-18, carrying **32 calls to the deleted `payload()`/`tag()`**. It is not in cyrius's
stdlib at all any more, nothing in mela includes it, and ⚠ `lib sync` copies but never deletes —
so it would have sat there indefinitely. `lib/` now has zero retired-name calls.

### CI — `install.sh` instead of a hand-rolled tarball extract

Both workflows now read the `cyrius.cyml` pin and pipe it to the upstream installer, matching
patra. The old step copied `bin/`+`lib/` into a **flat** `~/.cyrius`, with no `versions/<v>/`
layout and no `current` — and since 6.5.37 the pin redirect looks for
`~/.cyrius/versions/<pin>/bin/cyrius`, so CI died before compiling. Also added `set -e`: every
copy in the old step ended in `|| true`, so a failed install reported success.

### Fixed — 11 files were not canonically formatted

Pre-existing drift: cyrfmt only began tracking paren depth at v6.5.28 and mela was pinned 6.2.21,
so these had never been checked. Whitespace only — `git diff -w` empty, build byte-identical.

## [1.0.2] - 2026-09-10

**cyrius 6.2.21 → 6.6.2**, plus two real defects the bump surfaced. 492 assertions, 0 failures.

### Fixed — ⛔ use-after-return in `build_env_vars` (latent for years, surfaced by the bump)

`FLUTTER_FORCE_SCALE_FACTOR` was built with `str_new(&scbuf, sclen)` where `scbuf` is a **stack
local** of `build_env_vars`. `str_new` **aliases** — it stores the pointer and does not copy
(`lib/str.cyr:51`) — so the `Str` handed to the env map pointed into a frame that dies on return.
`_trim_trailing_zeros` did not help: `str_sub` also *"shares data with parent"* (`lib/str.cyr:199`).

It had "worked" by luck — the dead frame simply had not been overwritten before the map was read.
The 6.2.21 → 6.6.2 bump changed the stack layout and it stopped working: measured `str_len` = 4
(correct) with the four bytes reading back as **spaces**. Now `str_clone`d into heap memory, which
outlives the frame. ⚠ The `str_clone` is load-bearing and commented as such so it is not tidied away.

⭐ Swept for the shape rather than the site: this is the only `str_new(&local, …)` in `src/`.

### Fixed — stale bayan API: `json_v_parse_str` → `json_v_parse_buf` (13 sites, 7 files)

bayan renamed its explicit buf+len JSON entry point `_str` → `_buf` during **its own** 6.6
value-form migration (bayan `97bdc73`). mela sat four minors behind, so every call had gone stale
and the test suite would not compile. `flutter_agpkg` 2, `local_registry` 1, `manifest` 2,
`ratings` 3, `remote_client` 3, `sandbox_profiles` 1, `transparency` 1, `trust` 2.

### Changed — cyrius pin **6.2.21 → 6.6.2**, agnostik bundle refreshed to **1.6.0**

No first-party `payload()`/`tagged_new()`/`tag()` sites, so the value-form flip required no source
change here. `lib/agnostik.cyr` refreshed 120,192 B → 160,515 B (it was from 2026-06-18, ~40 KB
behind) and now carries agnostik 1.6.0's `boxed_*` reads.

`dist/mela.cyr` regenerated (4,133 lines).

## [Unreleased]

## [1.0.1] — Transitive dependency refresh for cyrius 6.3.5 consumers

### Changed

- **Bumped transitive pins** so downstream consumers resolve cleanly against the
  cyrius 6.3.5 toolchain: **sigil `3.8.0` → `3.9.7`** (provides `sha384_init_into`,
  which the 6.3.5 stdlib TLS now requires, and drops the external **agnosys**
  dependency via the agnosys→agnodrm decomposition — sigil internalized the trust
  primitives it needs), **sandhi `1.6.7` → `1.7.0`**, **sankoch `2.4.3` → `2.4.6`**.
  No mela API or behavior change; mela's bundle is unchanged and already builds
  green against sigil 3.9.x.

## [1.0.0] — Marketplace trust boundary, released

The port from Rust to Cyrius is complete and **a downstream consumer is green
against it**: every v1.0 gate is met. mela owns AGNOS's marketplace trust
boundary — signed, integrity-gated, transparency-logged distribution and
on-device install — with no deferred seams.

### Highlights — what v1.0 guarantees

- **Full port, function-level parity.** All 9 Rust modules (6208 lines at
  `rust-old/`) ported to Cyrius across 12 source modules; behavior cross-checked
  against the frozen oracle. **492/492 parity tests** + a fuzz harness over every
  external-data parser; `cyrius test` is the gate.
- **Both trust gates enforced end-to-end.** `pipeline_install` rejects an
  artifact unless it carries a valid Ed25519 publisher signature (keyed by
  `key_id`) **and** a matching SHA-256 content digest; every publication is
  recorded in the append-only, hash-chained transparency log.
- **Real I/O, no stubs.** HTTP/HTTPS/DNS transport via `sandhi`; on-disk install
  extraction (zip-slip-guarded ustar reader); recursive uninstall; keyring disk
  `load()`. No deferred seams remain anywhere in the tree.
- **Consumable + consumed.** Ships `dist/mela.cyr` (`[lib]` + `cyrius distlib`,
  reproducible). **ark consumes mela 0.9.5 and is green** (263 tests): it calls
  `mela_fetch_artifact` / `registry_client_new` / `sanitize_filename` to fetch
  `.ark` packages through mela's transport — the **v1.0 consumer gate**.
- **Audited + frozen.** Security audit + threat model (`docs/audit/`,
  `docs/development/threat-model.md`); public API frozen in `docs/api/` (additive
  changes pre-1.0 only; signature/semantic changes require an ADR).

### Known limitations (carried forward, by design)

- **Rust benchmark column deferred** — the Cyrius hot-path baseline is captured
  (`docs/benchmarks-rust-v-cyrius.md`); the Rust comparison column can't be run
  because `rust-old` needs `agnos-common` to build.
- **`rust-old/` retained** — the parity oracle is retired *after* v1.0, once
  Cyrius test coverage is confirmed ≥ the Rust suite (porting standard).
- **Paid distribution out of scope** — `mudra` / `vinimaya` integration is post-1.0
  (neither is scaffolded yet); the free-distribution path never blocks on it.

## [0.9.5] — Format-agnostic artifact fetch (consumable by ark)

### Added

- **`mela_fetch_artifact(c, name, version, dest_path)`** — the consumer-facing
  download primitive. Fetches the artifact over the sandhi transport and writes
  the body **verbatim to a caller-chosen path**, making **no assumption about
  the artifact type**. `rc_download` (mela's agent flow) now builds on it but
  keeps its `.agnos-agent` convention. This unblocks **ark**, whose packages are
  takumi `.ark` binaries, not mela `.agnos-agent` bundles: ark passes its own
  `.ark` cache path and interprets the bytes with its own installer, instead of
  being forced into mela's agent-bundle layout/extension. 492 tests (+2 guards);
  `dist/mela.cyr` regenerated.

## [0.9.4] — Every load-bearing seam is now real on disk

The remaining "deferred" stubs are gone: artifact fetch+write, uninstall file
removal, and keyring disk-load are all **implemented and proven by tests** (not
ADRs). **490/490 parity tests** green (was 475; +`keyring-load`, +`registry-uninstall-fs`).

### Added — the last deferred transport pieces are real now
Addresses the ark-agent finding that *"mela's own artifact fetch+write is still
deferred (ADR-0006)"*. It was: `rc_download` was a guard-only stub. No longer —
all remote flows do real I/O over sandhi:
- **`rc_download`** — actually **fetches** the package (`GET …/download`) and
  **writes** it to `<cache_dir>/downloads/<name>-<version>.agnos-agent`, returning
  the path. Proven live (server → bytes on disk, read back identical).
- **`rc_publish`** — actually **uploads**: `POST …/publish` with a Bearer token +
  `X-Package-SHA256`/`X-Package-Name` headers, then parses the `PublishResponse`.
  Proven live against a POST server.
- **`rc_check_updates`** — fetches each installed package's latest manifest and
  emits `UpdateAvailable` for version diffs (was an empty-vec stub).
- **`registry_uninstall` now removes the extracted files from disk** (recursive
  `_rmtree` = unlink files + rmdir dirs), not just the index entry — parity with
  rust-old `uninstall_package`'s `remove_dir_all`. New `registry-uninstall-fs`
  test materializes a nested install dir and asserts it's gone after uninstall.
- **`PublisherKeyring` disk `load()` is implemented** (`keyring_load_dir` + the
  `KeyVersion` JSON codec `kv_to_json`/`kv_from_json`/`kv_to_jv`/`kv_from_jv`) —
  scans a dir of `*.json`, each a `Vec<KeyVersion>` array, ignoring non-json
  files. Parity with rust-old `PublisherKeyring::load`, closing the ADR-0003
  deferral. New `keyring-load` test covers the round-trip + on-disk load.

### Changed
- **Cyrius toolchain pin `6.2.19` → `6.2.21`** in `cyrius.cyml` (matches the
  installed `cycc`; clears the pin-drift warning). `lib/` re-vendored via
  `cyrius lib sync`; build + 490 tests green on 6.2.21.

### Fixed — stale "deferred" comments
- Corrected now-false comments in `remote_client.cyr`, `local_registry.cyr`,
  `pipeline.cyr`, and `flutter_agpkg.cyr` that still said transport/extraction
  were deferred seams. **No deferred seams remain anywhere in the codebase.**

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
