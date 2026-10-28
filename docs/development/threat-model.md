# mela — threat model

> mela distributes, verifies, and installs marketplace packages: it is the
> **trust boundary** that decides what runs on a device. This document states
> what we protect, who the attacker is, where the boundaries are, and which
> control holds each boundary. Pairs with the dated audits in
> [`../audit/`](../audit/).
>
> **Current as of v1.5.2 (2026-10-28).** The v0.9.0 audit's follow-ups are closed: on-disk
> extraction and live transport shipped in v0.9.2, extraction is confined since v1.4.0, and an
> upgrade keeps its publisher key since v1.5.1. Since v1.5.2 a key counts only under the `key_id` it
> derives, and the log has signed checkpoints, witnesses and consistency proofs. The open items are
> restated under *Known gaps*.

## Assets

1. **Device integrity** — only authentic, publisher-signed packages get
   installed; nothing else runs.
2. **Package authenticity & integrity** — the bytes installed are exactly what
   the publisher signed (no tampering in transit or at rest).
3. **Publisher trust** — installs are bound to a trusted publisher key, not to a
   package name.
4. **Auditability** — every publication is recorded in a tamper-evident,
   append-only log, and every client that follows it sees the same log (v1.5.2).
5. **Availability of the installer** — parsing hostile input must not crash or
   exhaust resources.
6. **Files outside the install directory** — installing never writes, truncates or chmods
   anything outside `packages/<name>/`.

## Trust boundaries

```
 publisher ──pack/sign──▶ [bundle + sig] ──distribute──▶ device installer ──▶ local registry
                                                  ▲                  │              │
                                          (B2) untrusted bytes   (B3) on-disk state  (B4) install dir
 keyring (trusted publisher keys) ─────────────────┘                                  ▲
                                                                     installed apps ──┘
```

- **B1 — publisher → artifact**: the publisher signs the bundle offline
  (Ed25519). mela never trusts an artifact's *contents* to assert its own
  authenticity.
- **B2 — network/registry → installer** *(untrusted)*: the bundle, its
  signature, and an expected digest arrive from outside. Everything crossing B2
  is hostile until both trust gates pass.
- **B3 — installer → on-disk registry**: the index and install directory are
  derived only from *validated* manifest fields.
- **B4 — installed apps → install directory** *(untrusted)*: an app that can write inside its own
  install directory can leave symlinks or hard links there for the next upgrade to follow.

## Attacker model

- **Malicious or compromised registry / network MITM** — can serve arbitrary
  bytes, swap bundles, strip or replace signatures, set any digest, send
  decompression bombs, or craft malicious archive structures.
- **Malicious publisher of an *untrusted* key** — can sign their own bundle, but
  their key is not in the victim's keyring.
- **A log operator that equivocates** — signs checkpoints for its own log, and can show different
  clients different logs or drop entries (since v1.5.2: refused against a client's last checkpoint,
  and split views need dishonest witnesses beyond the client's threshold).
- **A trusted publisher acting outside its own packages** — its key is in the keyring. It can
  install new package names, but since v1.5.1 it cannot upgrade a package installed under another
  key (ADR-0016).
- **Look-alike / typosquatting publisher** — relies on the user confusing names.
- **A running installed app** — unprivileged, but able to write inside its own install directory
  between installs (B4).

Out of scope: a compromised trusted publisher key (key custody is the
publisher's responsibility); local root on the installing device; side channels
in the underlying crypto library beyond what `sigil` already hardens; the
contents of a correctly signed package (what an app does once installed is the
sandbox profile's concern, not the installer's).

## Controls (mapped to boundaries)

| Boundary | Threat | Control |
|---|---|---|
| B1 | forged authorship | Ed25519 signature over the whole bundle; `key_id` = first 8 bytes of the public key |
| B1 | one key filed under another's `key_id` | a key counts only under the `key_id` it derives: `keyring_load_dir` skips such a file, gate 1 and succession pass over such an entry (ADR-0017) |
| B2 | tampered / swapped bundle | **gate 2** — SHA-256 content digest must match the expected hash before install |
| B2 | unsigned / signature-stripped | **gate 1** — install refuses a bundle whose publisher `key_id` is absent from the keyring or whose signature fails |
| B2 | signature malleability | `sigil` enforces RFC 8032 §5.1.7 (`S < L`) + canonical encoding, and rejects small-order keys; mela requires a 64-byte signature |
| B2 | oversized bundle | `AGPKG_MAX_PACKAGE_SIZE` (100 MiB) refused before anything is read; downloads stream to disk under the same cap (ADR-0012, ADR-0014) |
| B2 | decompression bomb | inflate stops at 16 MiB (sankoch's gzip ceiling, `AGPKG_BUF_MAXLEN`); fails closed past it |
| B2 | crafted archive structure | the whole archive is validated before any write: checksums, strict octal fields, bounds, duplicate names, malformed long-name / PAX records (ADR-0011, ADR-0014) |
| B2 | zip-slip via names | non-regular entries and absolute / `..` / trailing-`/` names are skipped, judged on the full name (ustar prefix, GNU `L`, PAX `path`) |
| B2 | disk exhaustion | the storage quota is checked on the bundle size and the extracted size before anything is written (ADR-0014) |
| B2 | malformed input → crash | every external-data parser fuzzed; bounds-checked ustar reader; parsers return 0, not faults |
| B2 | expired/rotated key | `keyring_get_current_key(key_id, now)` honours `KeyVersion` validity windows |
| B2 | another trusted publisher replacing a package | **key continuity** — an upgrade must be published under the installed version's key, a successor the keyring declares (`succeeds`), or a key the operator approved for that one install (ADR-0016) |
| B2 | transport MITM | HTTPS through the stdlib's native TLS (no OpenSSL), verifying the server chain against the system roots; https→http redirects refused (ADR-0006, ADR-0012) |
| B3 | path traversal at install | manifest name validated to `[a-z0-9-]` before forming `packages/<name>` |
| B4 | symlink / hard-link redirection | extraction walks the install dir with `openat` + `O_NOFOLLOW`: a symlink anywhere at or below it fails the install; an existing file is unlinked and recreated with `O_EXCL`, never written into (ADR-0015) |
| B4 | permission escalation through modes | files extract 0755 or 0644 only (no setuid, nothing group/world-writable); directories 0755 (ADR-0014, ADR-0015) |
| audit | silent substitution / reordering | append-only hash-chained transparency log; `verify_chain` detects any mutation, reorder or truncation of the front; hash v2 makes each entry's preimage unambiguous (ADR-0015) |
| audit | truncation, rollback, fork | signed checkpoints of the chain head; `ckpt_advance` moves a client only to a checkpoint a consistency proof shows extends its last one; `tlog_matches_ckpt` catches a log with its end dropped (ADR-0018) |
| audit | split view (equivocation) | witness cosignatures: a client can require k of its witness keys, each of which cosigns only checkpoints consistent with its own last one; `ckpt_equivocates` turns two signed heads of one size into evidence (ADR-0018) |
| resolve | dependency confusion | single explicit dependency graph; `check_missing` surfaces gaps, no cross-registry version race |

## Enforcement points (in code)

- `pipeline_install` — the single choke point, in order (`src/pipeline.cyr`, ADR-0009, ADR-0012,
  ADR-0014, ADR-0015):
  1. size cap;
  2. one inflate, with the whole archive validated;
  3. manifest;
  4. **gate 1** (signature);
  5. **gate 2** (digest);
  6. key continuity;
  7. manifest validation and the quota, on both sizes;
  8. confined extraction;
  9. record and save.

  Any failure installs nothing. A fresh install's partial directory is removed, but a symlink
  found in its place is left alone.
- `trust_verify` / `registry_verify_package` — signature gate; `trust_hash_data`
  — digest. (`src/trust.cyr`, `src/local_registry.cyr`.)
- `_tar_cur_next` / `_tar_entry_safe` — archive validation and entry safety;
  `_agpkg_extract` / `_agpkg_put` — confined writes. (`src/flutter_agpkg.cyr`.)
- `manifest_validate` — name/version/publisher rules. (`src/manifest.cyr`.)
- `tlog_verify_chain` — auditability; `ckpt_advance` / `ckpt_consistent` /
  `tlog_matches_ckpt` — one log for every client (ADR-0018). (`src/transparency.cyr`.)
- `_keyring_trusted_key` — the key lookup behind gate 1 and checkpoint signatures; `kv_key_id_derives`
  at load and in succession (ADR-0017). (`src/trust.cyr`.)

## Known gaps / future work

- **New names are first come, first served.** Key continuity (v1.5.1) protects an installed
  package. Any trusted key can still install a name that is not installed yet. Binding names or
  namespaces to publishers is the consumer's table:
  [`../guides/keyring-provenance.md`](../guides/keyring-provenance.md).
- **Log checkpoints are building blocks, not a service.** Since v1.5.2 (ADR-0018) the checks
  exist, but:
  - **No transport:** mela neither serves nor fetches checkpoints, proofs or cosignatures; the
    consumer wires them.
  - **First contact is trust on first use**, unless the client checks the whole log.
  - **Split-view protection is only as strong as the witness threshold.** A threshold of 0 relies
    on clients comparing checkpoints.
  - **Freshness is the client's:** a registry can keep serving an old checkpoint (a freeze).
  - **`pipeline_install` does not consult the log.** Binding an install to it means taking gate 2's
    digest from the accepted log
    ([`../guides/transparency-checkpoints.md`](../guides/transparency-checkpoints.md)).
  - **Proofs are linear** in the entries since the client's checkpoint. A light client proving one
    entry would need a Merkle tree.
- **Gate 2 is only as independent as its digest.**
  - `expected_hash` = `""` skips the comparison (the digest is still recorded).
  - A digest supplied by the same server as the bundle protects transport integrity, not
    authenticity; authenticity is gate 1's job.
- **The archive is parsed before the signature is checked.** The publisher's `key_id` is read from
  `manifest.json` inside the bundle, so the gunzip and the tar walk run on unauthenticated bytes.
  The controls are a strict, fuzzed parser and the 16 MiB / 100 MiB bounds. A detached,
  signed manifest would remove the exposure.
- **Large bundles hold the whole tar in memory.** That is bounded at 16 MiB today. Streaming, and
  bundles over 16 MiB, wait on sankoch (filed upstream; the roadmap tracks it).
- **agnos confinement is path-based.** agnos has no `openat` family, so its build checks each
  component and then opens it, which leaves a window for a concurrent swap. agnos runtime
  correctness is unvalidated in general (roadmap: targets beyond x86_64 Linux).
- **The keyring is the operator's.** mela checks that each key's `key_id` derives from it
  (v1.5.2), but which keys belong in the keyring is the operator's call. Validity windows trust the
  caller's `now`. The provenance guide covers both:
  [`../guides/keyring-provenance.md`](../guides/keyring-provenance.md).
- **`ed25519_verify` costs about 5 ms.** That is fine per install, but a DoS factor for any bulk,
  server-side verify. It is a `sigil` optimisation.
