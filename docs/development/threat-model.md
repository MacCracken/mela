# mela — threat model

> mela distributes, verifies, and installs marketplace packages: it is the
> **trust boundary** that decides what runs on a device. This document states
> what we protect, who the attacker is, where the boundaries are, and which
> control holds each boundary. Pairs with the dated audits in
> [`../audit/`](../audit/).

## Assets

1. **Device integrity** — only authentic, publisher-signed packages get
   installed; nothing else runs.
2. **Package authenticity & integrity** — the bytes installed are exactly what
   the publisher signed (no tampering in transit or at rest).
3. **Publisher trust** — installs are bound to a trusted publisher key, not to a
   package name.
4. **Auditability** — every publication is recorded in a tamper-evident,
   append-only log.
5. **Availability of the installer** — parsing hostile input must not crash or
   exhaust resources.

## Trust boundaries

```
 publisher ──pack/sign──▶ [bundle + sig] ──distribute──▶ device installer ──▶ local registry
                                                  ▲                  │
                                          (B2) untrusted bytes   (B3) on-disk state
 keyring (trusted publisher keys) ─────────────────┘
```

- **B1 — publisher → artifact**: the publisher signs the bundle offline
  (Ed25519). mela never trusts an artifact's *contents* to assert its own
  authenticity.
- **B2 — network/registry → installer** *(untrusted)*: the bundle, its
  signature, and an expected digest arrive from outside. Everything crossing B2
  is hostile until both trust gates pass.
- **B3 — installer → on-disk registry**: the index and install directory are
  derived only from *validated* manifest fields.

## Attacker model

- **Malicious or compromised registry / network MITM** — can serve arbitrary
  bytes, swap bundles, strip or replace signatures, set any digest, send
  decompression bombs, or craft malicious archive structures.
- **Malicious publisher of an *untrusted* key** — can sign their own bundle, but
  their key is not in the victim's keyring.
- **Look-alike / typosquatting publisher** — relies on the user confusing names.

Out of scope: a compromised trusted publisher key (key custody is the
publisher's responsibility); local root on the installing device; side channels
in the underlying crypto library beyond what `sigil` already hardens.

## Controls (mapped to boundaries)

| Boundary | Threat | Control |
|---|---|---|
| B1 | forged authorship | Ed25519 signature over the whole bundle; `key_id` = first 8 bytes of the public key |
| B2 | tampered / swapped bundle | **gate 2** — SHA-256 content digest must match the expected hash before install |
| B2 | unsigned / signature-stripped | **gate 1** — install refuses a bundle whose publisher `key_id` is absent from the keyring or whose signature fails |
| B2 | signature malleability | `sigil` enforces RFC 8032 §5.1.7 (`S < L`) + canonical encoding; mela requires a 64-byte signature |
| B2 | decompression bomb | bounded inflate into a fixed buffer (`AGPKG_BUF_MAXLEN`); fails closed past the cap |
| B2 | zip-slip / symlink escape | `_tar_entry_safe` rejects non-regular typeflags and `..` / absolute names in the ustar reader |
| B2 | malformed input → crash | every external-data parser fuzzed; bounds-checked ustar reader; parsers return 0, not faults |
| B2 | expired/rotated key | `keyring_get_current_key(key_id, now)` honours `KeyVersion` validity windows |
| B3 | path traversal at install | manifest name validated to `[a-z0-9-]` before forming `packages/<name>` |
| audit | silent substitution / equivocation | append-only hash-chained transparency log; `verify_chain` detects any mutation |
| resolve | dependency confusion | single explicit dependency graph; `check_missing` surfaces gaps, no cross-registry version race |

## Enforcement points (in code)

- `pipeline_install` — the single choke point: extract manifest → **gate 1**
  (signature) → **gate 2** (digest) → manifest validation → record. Any failure
  installs nothing. (`src/pipeline.cyr`, ADR-0009.)
- `trust_verify` / `registry_verify_package` — signature gate; `trust_hash_data`
  — digest. (`src/trust.cyr`, `src/local_registry.cyr`.)
- `_tar_entry_safe` — archive entry safety. (`src/flutter_agpkg.cyr`.)
- `manifest_validate` — name/version/publisher rules. (`src/manifest.cyr`.)
- `tlog_verify_chain` — auditability. (`src/transparency.cyr`.)

## Known gaps / future work

- **On-disk extraction** (deferred, ADR-0005): when bundles are unpacked to disk,
  apply `_tar_entry_safe` per write **and** verify each resolved path stays
  within the destination (defeats the CVE-2025-45582 two-step symlink case).
- **Live transport** (deferred, ADR-0006): the HTTPS client is not yet wired; it
  must use stdlib `tls` (no OpenSSL), validate the server certificate, and feed
  the bounded decompressor + verified-install path unchanged.
- **Keyring provenance**: the process for distributing/rotating trusted publisher
  keys is operational and out of mela's code; document it for consumers (ark)
  before v1.0.
