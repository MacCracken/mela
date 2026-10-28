# 0015 — Confined extraction and transparency hash v2

**Status**: Accepted
**Date**: 2026-10-28 (v1.4.0)

## Context

The roadmap's v1.4.0 *Hardening residuals* has two items that change behavior, and so need an
ADR. The other two, keyring provenance and the threat-model refresh, are documentation.

**Extraction followed symlinks.** Since v0.9.2 mela extracts bundles to `packages/<name>/`.
Archive content cannot point outside it: links, directories, absolute names and `..` are never
written (ADR-0011, ADR-0014). But the filesystem already under the install directory was
trusted:
- `_rc_mkdir_p` and `open(O_TRUNC)` followed whatever they found. Something that could write
  inside the install directory between installs could redirect the next upgrade's writes outside
  it. A symlink `bin -> /etc` would send `bin/x` to `/etc/x`.
- A hard link to a file elsewhere would have that file truncated and rewritten through it.
- The v1.3.0 `fchmod` followed the same path.

The likeliest writer is the installed app itself (the threat model's B4); the v0.9.0 audit
(finding A) and CVE-2025-45582 describe the class. ADR-0013 §5 recorded this as the one residual
of Rust's path containment.

**The transparency hash preimage was ambiguous** (ADR-0013 §8). v1 hashes:

```
sequence BE8 || decimal timestamp || package || version || key_id || content_hash || signature_hash || previous_hash
```

with no separators, so:
- timestamp `1000` with package `1/x` hashes like timestamp `10001` with `/x`;
- package `a/b` with version `11.0.0` hashes like `a/b1` with `1.0.0`.

Both collisions are verified here, in Python as well. Any fix changes every entry hash, so logs
written before it must still verify.

## Decision

### 1. Extraction is confined below the destination

**On Linux (x86_64, aarch64) extraction writes only through directory file descriptors it opened
itself.**
- **The walk:**
  - the destination is opened with `O_DIRECTORY | O_NOFOLLOW`;
  - each component of an entry's directory is created with `mkdirat` (0755) and opened with
    `openat(O_DIRECTORY | O_NOFOLLOW)`;
  - `.` and empty components are skipped, and names never contain `..` (ADR-0011).
- **The file:** `fstatat(AT_SYMLINK_NOFOLLOW)` must find nothing or a regular file. A regular
  file is unlinked, and the new one is created with `openat(O_CREAT | O_EXCL | O_NOFOLLOW)`, then
  written and `fchmod`ed.
- **Failure:** a symlink at the destination or anywhere below it, a non-directory on a
  directory's path, or a directory, device or symlink where the file goes, fails the extraction
  (`-1`; `pipeline_install` returns 0).

**Fail, rather than replace.** mela never writes symlinks, so one found there was put there by
something else. Replacing it would hide that, and removing the link would destroy evidence.
- **On rollback:** a fresh install's rollback removes only a real directory. A symlink found at
  `packages/<name>` is left as it was found.
- **On a later install:** the link stays until someone looks at it, and installs of that package
  keep failing until then.

**Replace regular files rather than write into them.** Unlinking first means a hard link
elsewhere keeps its bytes. `O_EXCL` makes a file re-appearing between the unlink and the create a
failure, not a write through it. A single-threaded test cannot open that window; the `fstatat`
check covers the deterministic cases.

**agnos has no `openat` family.** Its build applies the same rules by path:
- `is_symlink` on each component before use;
- `O_EXCL | O_NOFOLLOW` on the create.

A concurrent swap between a check and its use is not excluded there. agnos runtime is
unvalidated in general (roadmap).

### 2. Transparency hash v2

Each `LogEntry` carries a hash version (`log_hash_version`, `LOG_HASH_V1` / `LOG_HASH_V2`).

**The v2 preimage:**

```
BE8(len(tag)) || tag || BE8(sequence) || BE8(timestamp, two's complement)
  || BE8(len) || package || BE8(len) || version || BE8(len) || publisher_key_id
  || BE8(len) || content_hash || BE8(len) || signature_hash || BE8(len) || previous_hash
```

- `tag` is `mela.transparency.entry.v2`.
- Every field has a fixed width or a length, so the encoding is injective.
- The tag keeps a v2 preimage from being read as a v1 one.
- Two known-answer vectors were computed independently, with Python's `hashlib`.

**What reads and writes which version:**
- **`tlog_append`** always writes v2, including after v1 entries. The chain continues across the
  switch, since `previous_hash` is just the prior entry's hash.
- **`tlog_to_json`** writes `"hash_version": 2` on v2 entries, and nothing on v1 entries, so a v1
  log re-exports byte for byte.
- **`tlog_from_json`** reads a missing `hash_version` as 1. The value must be an integer this
  build knows (1 or 2), or the log is refused.
- **`tlog_verify_chain`** also refuses an entry whose hash version is older than the one before
  it, so a log moves to v2 once. An entry relabelled to another version fails its own hash.
- **`log_entry_verify_self`** never accepts an unknown version, even with a matching hash.
- **`log_entry_new`** makes v2 entries; `log_set_hash_version` refuses unknown versions.

## Consequences

- **Positive**
  - Nothing the installed app (or anything else) leaves in its install directory can redirect a
    write, truncate a file elsewhere, or redirect the mode change.
  - Two entries with different fields can no longer share a v2 hash.
  - Every log written before v1.4.0 still imports and verifies unchanged.
- **Negative**
  - Behavior changes for callers:
    - `agpkg_extract_to_dir` returns `-1` for a symlinked destination, and for symlinks or
      special files in the paths it writes; an install or upgrade that met one returns 0;
    - directories created below the destination are 0755 (umask applied) where they were 0777
      (umask applied); the destination itself is created as before;
    - new log entries hash differently.
  - **A log with a v2 entry does not import into mela 1.3.0 or earlier.** Those releases hash
    every entry as v1, so they refuse it. Logs only move forward.
  - The extractor has two implementations, Linux and agnos, and only Linux's is exercised by the
    suite.
- **Neutral**
  - The log is still tamper-evident only. It has no signed tree heads, consistency proofs or
    witnesses (threat model, *Known gaps*).
  - Uninstall (`_rmtree`) already removed a symlink without following it (v1.1.1); it is
    unchanged.

## Alternatives considered

- **Check each resolved path with `realpath` before opening.** It is portable, but it races the
  open, and it follows a symlink inside the destination as long as it stays inside, which still
  lets an app point one of its files at another of its files.
- **Replace symlinks found below the destination with real directories and files.** That heals
  silently and removes what tampering left behind. Failing tells the operator.
- **`O_TRUNC` on an existing file, as before.** That writes through a hard link into a file
  outside the install directory.
- **A log-wide version (one header for the whole log).** The log is a bare JSON array, with
  nowhere to put a header without changing the format for v1 logs too. A per-entry version lets
  v1 and v2 entries share one log.
- **Separators instead of length prefixes.** Every field would then need escaping, since package
  names, versions and hashes are publisher-supplied text in principle. Length prefixes need no
  escaping.
- **Rehash old logs to v2 on import.** That rewrites history: the v1 entry hashes are what
  anyone else holding the log has, and they are the evidence.
