# 0005 — Registry on-disk index format + tarball-extraction deferral

**Status**: Accepted · **tarball extraction implemented in v0.9.2**
**Date**: 2026-06-17

> **Update (v0.9.2):** the deferral below is **resolved**. `agpkg_extract_to_dir`
> (`src/flutter_agpkg.cyr`) unpacks a gzipped-ustar bundle to disk — gunzip +
> per-entry `_tar_entry_safe` zip-slip guard + parent-dir creation + write —
> and `pipeline_install` now extracts onto the install dir after the gates pass.
> Tested on disk (`extraction` group: files written, content re-parses, a
> `../escaped.so` entry is **not** written). The text below is the original
> rationale for the temporary deferral.

## Context

`rust-old/src/local_registry.rs` is the largest module (970 lines). It does two
separable jobs:

1. **A file-backed index** of installed packages — `install` / `uninstall` /
   `get` / `list` / `search`, persisted to `index.json` (serde JSON of
   `HashMap<String, InstalledMarketplacePackage>`) and reloaded on open.
2. **Tarball handling** — `install_package(tarball_path, keyring)` reads a
   gzipped `.agnos-agent` tar, extracts `manifest.json` and the file tree
   (`extract_manifest_from_tarball`, `extract_tarball`), reads a `.sig` sidecar,
   verifies the signature, then records the result.

The v0.5.0 dep gate is **the manifest model (v0.2.0) + stdlib `fs`**. gzip + tar
are a *different* dependency: the roadmap introduces `sankoch` (LZ4 / DEFLATE /
gzip, replacing Rust `tar` + `flate2`) at **v0.8.0 packaging**. Pulling tar/gzip
into v0.5.0 would front-run that milestone, and the registry's own contract —
"install → query → remove round-trips on disk, the index survives a reopen" — is
about the *index*, not the archive format.

## Decision

**Port the index + lifecycle + persistence now; defer tarball extraction to
v0.8.0. Pin the `index.json` on-disk format here.**

On-disk `index.json` is a JSON **object** keyed by package name; each value is a
record:

```json
{
  "<package-name>": {
    "manifest":       { …MarketplaceManifest per ADR-0001… },
    "installed_at":   <int epoch>,
    "install_dir":    "<string>",
    "package_hash":   "<sha-256 hex string>",
    "auto_update":    <bool>,
    "installed_size": <int bytes>
  }
}
```

- The nested `manifest` reuses the ADR-0001 manifest codec (via the new
  `manifest_to_jv` / `manifest_from_jv` value-tree entry points, so it composes
  without re-serializing through a string).
- `installed_at` is an `i64` epoch (ADR-0003/0004 precedent), not chrono.
- `install` takes an **already-extracted** manifest + content hash + size +
  timestamp. It performs the quota check, manifest validation, upgrade
  detection, index insert, and `save_index` — everything except reading the
  archive.
- The **signature-verify gate** is ported as `registry_verify_package`
  (`get_current_key` → `verifying_key` → `trust_verify` over caller-supplied
  content + signature bytes). The `.sig` *sidecar file read* defers with the
  tarball work; install-time *enforcement* of the gate is wired at v0.9.0.
- **Deferred to v0.8.0**: `extract_manifest_from_tarball`, `extract_tarball`
  (gzip + tar via `sankoch`), the `.sig` sidecar read, and `count_files` /
  physical install-dir removal on uninstall.

## Consequences

- **Positive** — the done-when is met with the correct dep gate: real
  filesystem round-trips (install → reopen → query → uninstall → reopen) are
  parity-tested on disk, and the trust gate's three outcomes (valid / wrong key
  / unknown key) are tested. No tar/gzip dependency a milestone early.
- **Negative** — `install` does not yet accept a `.agnos-agent` path; a caller
  must extract the manifest + hash + size itself until v0.8.0 supplies the
  archive reader. `uninstall` removes the index entry but not on-disk files
  (there are none to remove without extraction), and does not yet report a
  `files_removed` count.
- **Neutral** — the `index.json` format is fixed now; the v0.8.0 archive work
  plugs into the existing `registry_install` (extract → hash → call install) and
  can wire the deferred trust keyring `load()` (ADR-0003) at the same time.

## Alternatives considered

- **Port `install_package` whole now, pulling `sankoch` early** — collapses the
  v0.5.0 / v0.8.0 boundary and front-runs the packaging design. Rejected.
- **Stub tarball extraction with a hand-rolled gzip/tar reader** — duplicates
  what `sankoch` will provide and risks a format mismatch with the eventual
  `.agpkg` cross-validation (v0.8.0 done-when). Rejected.
