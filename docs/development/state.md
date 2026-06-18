# mela — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**0.6.0** — Remote client (2026-06-17). `lib.rs` + `trust.rs` + `transparency.rs` +
`local_registry.rs` + `remote_client.rs` (logic; transport seam) ported. 6208 lines of Rust
preserved at `rust-old/` for parity reference.

## Toolchain

- **Cyrius pin**: `6.2.19` (in `cyrius.cyml [package].cyrius`). Installed `cycc` is `6.2.21` —
  pin-drift warning is expected and benign; `cyrius lib sync` keeps `lib/` vendored to the pin.

## Source

- Rust reference: 6208 lines at `rust-old/` (frozen, do not edit).
- Cyrius port: **`lib.rs` + `trust.rs` + `transparency.rs` + `local_registry.rs`* +
  `remote_client.rs`† complete (5 of 9 modules)** —
  - `src/category.cyr` — `MarketplaceCategory` (`cat_name` / `cat_parse`, Rust `Display`/`FromStr`).
  - `src/manifest.cyr` — `PublisherInfo`, `MarketplaceManifest` (`validate` / `qualified_name`),
    `is_valid_semver`, and the JSON codec (`*_to_json` / `*_from_json`, wire format = ADR-0001).
  - `src/depgraph.cyr` — `DepNode`, `DependencyGraph` (`add` / `len` / `is_empty` /
    `check_missing` / `detect_cycle` / Kahn `resolve`).
  - `src/trust.cyr` — Ed25519 sign/verify + SHA-256 hashing (via `sigil`), hex codec,
    `KeyVersion` (`is_valid_at` / `verifying_key`), in-memory `PublisherKeyring`. Disk
    `load()` deferred to the fs milestone (ADR-0003).
  - `src/transparency.cyr` — `LogEntry` + `TransparencyLog`: SHA-256 hash-chained append-only
    log (`compute_hash` / `verify_self` / `append` / `verify_chain` / `find` /
    `entries_for_package` / `latest`), JSON codec re-verifying the chain on import (ADR-0004).
  - `src/local_registry.cyr` — `InstalledMarketplacePackage` + `LocalRegistry`: install/record/
    query/search/remove, `index.json` persisted via `fs` (ADR-0005), signature-verify gate.
  - `src/remote_client.cyr` — `RegistryClient`: url_encode / sanitize / validate, URL builders,
    response types + JSON codec, offline guards, fs response cache. Live HTTP/TLS transport is a
    seam deferred to v0.9.0 (ADR-0006).
  - `src/main.cyr` wires all seven.
- Remaining (4): `ratings`, `sandbox_profiles`, `flutter_packaging`/`flutter_agpkg`. Deferred
  pieces: **\*** `local_registry` tarball extraction → **v0.8.0** (`sankoch`, ADR-0005); **†**
  `remote_client` live `sandhi`/`tls` transport → **v0.9.0** end-to-end (ADR-0006).
  Next milestone: **v0.7.0 sandbox_profiles + ratings**.

## Tests

**240/240** parity tests green (`tests/mela.tcyr` — groups `category`, `semver`, `publisher`,
`manifest`, `depgraph-base`, `depgraph-resolve`, `json`, `trust`, `keyversion`, `keyring`,
`transparency`, `transparency-json`, `registry`, `registry-persist`, `registry-signature`,
`remote`, `remote-codec`, `remote-client`). `trust` includes SHA-256 + RFC 8032 Ed25519
known-answer vectors; `registry-persist` does a real on-disk install→reopen round-trip;
`remote-codec` parses a canned mock registry response. Fuzz harness at `tests/mela.fcyr` covers
the manifest JSON, trust hex/key/signature, transparency-log, registry-index, and remote response
parsers (survive arbitrary bytes). `cyrius test` is the gate; each ported module adds its group.

## Dependencies

Direct (declared in `cyrius.cyml`):

- stdlib — string, fmt, alloc, vec, str, syscalls, io, args, assert, hashmap, tagged, result,
  fnptr, trait, bayan (JSON codec), chrono, plus sigil's transitive set (fs, freelist, slice,
  process, sakshi, ct, keccak, thread, thread_local, random, bench)
- **agnostik** (`dist/agnostik.cyr`, tag 1.3.1) — the shared-types crate; supplies the
  `AgentManifest` that `MarketplaceManifest` flattens.
- **sigil** (`dist/sigil.cyr`, tag 3.8.0) — the crypto crate; Ed25519 + SHA-256 + hex for the
  trust gate. Its dist transitively pulls `agnosys` (used only in unexercised TPM paths, DCE'd);
  the resulting duplicate-symbol warnings on shared `ERR_*` / `LOG_*` constants are benign.

## Consumers

_None yet._

## Next

See [`roadmap.md`](roadmap.md). Next milestone: **v0.7.0 — Sandbox profiles + ratings**
(`sandbox_profiles.rs` 740 lines + `ratings.rs` 897 lines; dep gate the manifest model +
`agnostik` security types): capability disclosure before install, and ratings/reviews.
