# 0008 — Packaging: sankoch gzip + hand-rolled ustar; system-tar cross-validation

**Status**: Accepted
**Date**: 2026-06-17

## Context

v0.8.0 ports the packaging modules. `flutter_packaging.rs` is pure logic (ports
cleanly). `flutter_agpkg.rs` builds a `.agnos-agent` bundle — a **gzipped tar**
of `bin/flutter_engine.so`, `bin/<app>`, `assets/flutter_assets/**`,
`manifest.json`, `sandbox.json` — using Rust `tar` + `flate2`. The roadmap dep
gate is **`sankoch`** (LZ4/DEFLATE/gzip), and the done-when is the strongest of
the whole port: "build→inspect→validate round-trips, **and a Rust-built
`.agpkg` validates in Cyrius (cross-validation) — the format is identical, not
merely self-consistent.**"

Two facts shape the approach:

1. **`sankoch` is compression-only** — it provides `gzip_compress` /
   `gzip_decompress` (and deflate/lz4/bzip2/zlib), but **no tar** archiver. The
   tar container has to be implemented in mela.
2. **The Rust oracle can't be built here** — `rust-old` depends on
   `agnos-common` (path `../agnosticos/userland/agnos-common`), which is absent.
   So a literal "Rust-built `.agpkg`" fixture cannot be produced.

## Decision

1. **gzip via `sankoch`; ustar tar hand-rolled in `flutter_agpkg.cyr`.** A
   minimal POSIX **ustar** writer (`_tar_header` / `_tar_build`: 512-byte
   headers, octal fields, the standard checksum, 1 KiB zero trailer) and reader
   (`_tar_read_name` / `_tar_read_size`, bounds-checked). `pack_flutter_app`
   builds the entry set, tars it, `gzip_compress`es, and writes the
   `.agnos-agent`; `agpkg_inspect` `gzip_decompress`es and lists the entries.
2. **Cross-validate against the system `tar`/`gzip`** as the independent
   reference implementation (in lieu of a Rust-built artifact):
   - **Cyrius → reference**: GNU `tar tzf` lists, and `tar xzf` extracts (with
     correct content), a Cyrius-built `.agnos-agent`.
   - **reference → Cyrius**: a `tar czf`-built archive is read by
     `agpkg_inspect`, which lists its entries.
   This proves the format is *real ustar+gzip*, interoperable with the canonical
   tooling — "identical, not self-consistent" — which is exactly the property
   the done-when targets. (These run via the harness/CI shell, not inside
   `cyrius test`, which cannot spawn processes.)

## Consequences

- **Positive** — packaging produces and consumes standard gzipped-ustar
  archives, verified interoperable with GNU tar both directions; the in-Cyrius
  build→inspect round-trip is parity-tested and the inspector is fuzzed. No
  hand-rolled compression (the security-sensitive part is `sankoch`'s).
- **Negative** — mela now owns ~150 lines of tar format code (header layout,
  octal, checksum). The reader handles the common ustar/GNU regular-file case;
  exotic entries (PAX extended headers, long-name `L`/`K` typeflags, sparse
  files) are not interpreted — adequate for `.agnos-agent`, which mela also
  writes. The asset walk is one directory level (the Flutter build layout);
  deeper trees would need recursion.
- **Neutral** — this unblocks the deferred `local_registry` tarball extraction
  (ADR-0005): `extract_manifest_from_tarball` / `extract_tarball` can now reuse
  this gunzip + ustar reader at v0.9.0. The `LandlockRule`/`NetworkRule` types
  are now shared between `sandbox_profiles` and `flutter_agpkg` (ADR-0007
  follow-through).

## Alternatives considered

- **Defer the archive to v0.9.0 (transport-seam style)** — but packaging *is*
  this milestone's deliverable, and the done-when centers on the archive
  round-trip. Rejected.
- **Wait for a `sankoch` tar module** — sankoch is compression-scoped by design;
  tar belongs to the consumer. Rejected.
- **Treat a Cyrius-built archive as its own reference (self-consistency only)** —
  explicitly *not* what the done-when asks; the system-`tar` cross-check is the
  independent oracle. Rejected.
