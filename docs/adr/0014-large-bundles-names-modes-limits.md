# 0014 — Large bundles, part one: long names, file modes and size limits

**Status**: Accepted
**Date**: 2026-10-28 (v1.3.0)

## Context

The roadmap's *Large bundles* milestone (planned as v1.2.0, renumbered v1.3.0) had five items:
- streaming extraction;
- a real package-size limit plus a decompressed ceiling;
- file modes on extraction ([ADR-0013](0013-decided-divergences-from-rust-old.md) §5 deferred them
  here);
- long names ([ADR-0008](0008-packaging-gzip-ustar-and-cross-validation.md),
  [ADR-0012](0012-fail-closed-install-and-transport.md));
- the extracted size counted toward the quota.

**Streaming is blocked upstream.** sankoch, which owns gzip ([ADR-0008](0008-packaging-gzip-ustar-and-cross-validation.md)),
cannot stream it yet:
- **No gzip output beyond 16 MiB.** Every gzip decoder, batch or incremental, stops at sankoch's
  `DECOMPRESS_MAX_OUTPUT` (16 MiB) whatever buffer the caller passes. Measured on 6.7.18:
  16,777,216 bytes decode, 16,777,217 return `-ERR_OUTPUT_LIMIT`. zlib has had a caller override
  since sankoch 2.7.13 (`zlib_decompress_capped`); gzip has none.
- **No bounded-memory output.** Its streaming decoders write into one contiguous `dst` and read
  back-references from it, so the whole tar must still be in memory. sankoch's roadmap moves
  streaming DEFLATE to a ring window at 2.9.5.

The other four items do not depend on streaming. Two gaps also came to light while looking:
- **Long names are read wrong today, silently.** mela ignored the ustar `prefix` field and the GNU
  `L` / PAX `x` records. GNU tar writes those for names over 100 bytes, so mela extracted such a
  file under a truncated name.
- **An over-quota upgrade could leave mixed files.** `pipeline_install` checked the quota against
  the bundle size before extracting. `registry_install` then checked it again with the extracted
  size, after the files were written. An upgrade that failed that second check left the new
  version's files over the old ones, with the old version still recorded.

## Decision

**Ship the four unblocked items now, shape the extractor for streaming, and leave streaming
itself to a later release once sankoch can stream gzip.** The maintainer chose the scope, the
mode rule and long-name support on 2026-10-28.

### 1. Size limits

- **`AGPKG_BUF_MAXLEN` rises from 8 MiB to 16 MiB**, sankoch's gzip ceiling. That is now the
  decompressed ceiling: a bundle whose tar is over 16 MiB does not install. The packer refuses
  such a tar, and any single input file over 16 MiB, as before (ADR-0012).
- **`AGPKG_MAX_PACKAGE_SIZE` = 100 MiB**, Rust's `MAX_PACKAGE_SIZE`, equal to
  `RC_DOWNLOAD_MAX_BYTES` (a test pins the two together). `pipeline_install` refuses a larger
  bundle first, before it gunzips, hashes or verifies anything, as Rust's `install_package` did.
  Under the 16 MiB ceiling no valid bundle comes near it. It is the guard that stays once the
  ceiling lifts.
- **One gunzip per install.** `pipeline_install` used to inflate the bundle three times (the
  manifest, the payload size, the extraction), each into a fresh buffer. It now inflates once.
  The public `agpkg_*` functions keep their signatures and still inflate once per call.

### 2. Quota before any write

`pipeline_install` checks the quota against the bundle size (Rust's check) **and** against the
extracted size, both before extracting. Which installs succeed is unchanged: the second check
already ran in `registry_install`, only too late. A refused install now writes nothing. The
extracted size has counted toward the quota since v1.1.5, when `installed_size` became the
extracted size (ADR-0013 §5). That closes the roadmap item.

### 3. File modes: 0755 or 0644 (maintainer decision)

- **Extraction:** each file is written as **0755 if its header's owner-execute bit (0o100) is set,
  otherwise 0644**, applied with `fchmod` after the write. That covers files that already exist
  (an upgrade), and the result does not depend on the umask. Nothing is installed group- or
  world-writable, and setuid, setgid and sticky bits are never kept.
- **Packing:** the writer stores **0755 for a source file with any execute bit, otherwise 0644**.
  `manifest.json` and `sandbox.json` are 0644. uid, gid and mtime stay 0. A bundle is still a pure
  function of its inputs (ADR-0013 §6); the execute bit is now one of those inputs.
- **Strict field:** the header's mode field must be strict octal, like the size field
  ([ADR-0011](0011-fail-closed-decoding-at-the-trust-boundary.md)), or the archive is rejected.

Rust kept `mode & 0o777`. This diverges on purpose, and ADR-0013 §5's deferral ends here.

### 4. Long names (maintainer decision: support)

**Reading.** The effective name of an entry is, in order of precedence:
1. a PAX `x` record's `path`;
2. a GNU `L` entry's data, up to its first NUL;
3. the POSIX ustar `prefix` + `/` + `name`. This applies only under the POSIX magic
   `ustar\0` `00`; GNU's `ustar  \0` keeps other data in that area.
4. Otherwise, the 100-byte `name` field.

Each `L` / `x` record applies to the next header only. The checks that already apply to `name`
apply to the effective name: an absolute name, a `..` or an empty name is skipped, and a
duplicate rejects the archive. A name ending in `/` (a pre-POSIX directory) is skipped too.

The whole archive is rejected when:
- an extension entry (`L`, `K`, `x`, `g`) is over `AGPKG_EXT_MAX` (64 KiB);
- an effective name is over `AGPKG_NAME_MAX` (1,024 bytes), or a PAX `path` contains a NUL;
- PAX records do not tile their data exactly (`<len> <key>=<value>\n`, with `<len>` counting the
  whole record);
- a PAX `size` disagrees with the header it applies to;
- a global `g` record carries `path` or `size`;
- an `L` or `x` is followed by no header (it dangles at the end of the archive).

Other PAX keys (times, owners, xattrs) and `K` (long link names, which only links use) are read
and ignored.

**Writing.** A name over 100 bytes is split into `prefix` / `name` at the last `/` that leaves at
most 155 bytes of prefix, GNU tar's rule, so names up to 256 bytes pack. A longer name, or one
whose last component is over 100 bytes, still fails the pack (ADR-0012). mela writes no `L` or
`x` entries.

### 5. The extractor's shape

The tar walker is now a cursor (`_tar_cur_next`): it yields one entry at a time and carries the
pending long-name state from header to header. Extraction makes two passes over the inflated
archive:
1. a validating pass that writes nothing (checksums, fields, bounds, names, duplicates);
2. a writing pass that writes each entry as the cursor yields it.

When sankoch can stream gzip, each pass becomes a streaming inflate feeding the same cursor, and
the whole archive is still validated before anything is written.

## Consequences

- **Positive**
  - Bundles up to 16 MiB of tar install: twice the old ceiling. That covers small Flutter
    engines; the large ones wait for streaming.
  - Long names round-trip with GNU tar in all three formats instead of being cut short silently.
  - Executables keep their execute bit, and nothing lands writable by other users.
  - A refused install writes nothing, upgrades included.
  - One inflate per install instead of three.
- **Negative**
  - Behavior changes for callers:
    - bundles with a malformed mode field, a bad PAX record, a dangling long name or a name over
      1,024 bytes are now rejected;
    - files extracted from a header with the owner-execute bit set are 0755 (they were 0644);
    - names of 101–256 bytes now pack instead of failing.
  - mela owns more tar code: three name sources and a PAX record parser, both fuzzed.
  - The 16 MiB ceiling is sankoch's constant. mela cannot raise it on its own.
- **Neutral**
  - Streaming extraction and bundles over 16 MiB move to a later release. Both wait on sankoch:
    a gzip output override like zlib's, and the 2.9.5 ring-window decoder. Both are filed with
    sankoch.
  - A symlink already present in the install directory still redirects a write, and now also the
    `fchmod` that follows it. That is the roadmap's extraction-confinement item (`O_NOFOLLOW`).

## Alternatives considered

- **Wait for sankoch and ship the whole milestone at once.** That holds back fixes that need
  nothing from sankoch, including the silent mis-naming of long entries.
- **Inflate gzip in mela.** ADR-0008 keeps compression in sankoch, the audited codec. A second
  inflater at the trust boundary is the risk that rule exists to avoid.
- **Reach into sankoch's decoder context to lift the ceiling.** The context layout is private and
  changes between releases (2.7.13 added a slot). A bundle would install or not depending on a
  sankoch internal.
- **Keep `mode & 0o777`, as Rust did.** A bundle could install world-writable files, which another
  local user could modify after the install was verified.
- **Reject long names explicitly.** A smaller parser, but bundles built by GNU tar with long asset
  paths would not install at all. Support costs one record parser and the same safety checks.
- **Switch to sankoch's own `tar.cyr` reader.** It reads the same long-name forms, but inflates the
  whole archive in RAM with its own ceiling and its own path policy. It would also replace a reader
  whose strictness (checksums, octal, bounds, duplicates) the parity suite pins. Worth revisiting
  when streaming lands.
