# 0009 — End-to-end pipeline + trust-gate enforcement

**Status**: Accepted
**Date**: 2026-06-17

## Context

With all 9 modules ported (v0.8.0), the release run wires them into the flow the
roadmap specifies: **publish → sign → log → distribute → verify →
capability-surface → install**, with the two trust gates *enforced, not merely
present*. Until now each module was parity-tested in isolation; nothing tied
them together, and two pieces were explicitly deferred:

- the `remote_client` live HTTP/TLS transport (ADR-0006), and
- the `local_registry` tarball extraction (ADR-0005), which needed a gzip+tar
  reader — now available from v0.8.0 (`agpkg_read_entry`).

## Decision

**Add `src/pipeline.cyr` tying the modules together, and enforce both trust
gates at install.**

- `pipeline_package(manifest, sandbox)` → a gzipped-ustar `.agnos-agent` byte
  bundle (the publish/distribute artifact).
- `pipeline_publish(tlog, bundle, sk, sig_out, now)` → Ed25519-signs the bundle
  (`trust`) and appends a `transparency` log entry (content + signature hashes).
- `pipeline_extract_manifest` / `pipeline_extract_sandbox` pull those entries
  back out via the v0.8.0 ustar reader — closing the ADR-0005 gap.
- `pipeline_install(reg, keyring, bundle, sig, sig_len, expected_hash, now)`
  enforces **both gates** before recording into `local_registry`:
  - **gate 1 — signature**: the manifest's `publisher.key_id` must resolve to a
    current keyring key, and `sig` must verify over the bundle bytes
    (`registry_verify_package` → `trust`);
  - **gate 2 — digest**: the bundle's SHA-256 must equal `expected_hash` (the
    download-integrity check; `""` skips the compare for the dev path).
  Any failure — malformed bundle, unknown/invalid key, bad signature, digest
  mismatch, invalid manifest — returns 0 and installs nothing.

**Transport stays a local seam.** "Distribute" moves the signed bundle + its
signature as values rather than over a socket; the `sandhi`/`tls` wiring
(ADR-0006) is still future work. This is sufficient to enforce and *test* both
gates end-to-end without a network.

## Consequences

- **Positive** — the marketplace's load-bearing invariant is demonstrated: a
  happy-path bundle installs; a **tampered bundle**, a **digest mismatch**, an
  **untrusted publisher**, and a **wrong keyring key** are each rejected with
  nothing installed (the `pipeline` test group). The transparency chain records
  every publication and verifies. The ADR-0005 tarball-extraction gap is closed.
- **Negative** — the flow is in-process: there is no live download yet (transport
  seam, ADR-0006), and `expected_hash` is supplied by the caller rather than a
  remote registry. Publisher `key_id` population is the publisher's
  responsibility (the packer leaves it empty, "populated during signing", per the
  Rust oracle) — the pipeline assumes a manifest whose `key_id` matches the
  signing key.
- **Neutral** — when the live transport lands, `pipeline_install` is unchanged;
  only the source of `bundle` + `expected_hash` moves from a local value to a
  `remote_client` download.

## Alternatives considered

- **Fold the wiring into `local_registry`** — but `local_registry` is included
  before `flutter_agpkg`, so it cannot call the ustar reader; a dedicated
  last-in-chain `pipeline` module is the clean seam and keeps the registry
  focused on the index.
- **Wire the live `sandhi`/`tls` transport now** — out of scope for the release
  run (ADR-0006); it adds a heavy, CI-untestable network stack without changing
  what the gates prove. Deferred.
