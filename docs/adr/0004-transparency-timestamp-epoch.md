# 0004 — Transparency log timestamp is an i64 epoch

**Status**: Accepted
**Date**: 2026-06-17

## Context

`rust-old/src/transparency.rs` stamps each `LogEntry` with a
`chrono::DateTime<Utc>` set from `Utc::now()` inside `append`, serializes it via
serde (RFC 3339 string), and — critically — folds it into the entry hash as
`timestamp.to_rfc3339().as_bytes()` inside `compute_hash`. The entry hash chains
the log, so the timestamp's byte representation is part of the integrity
preimage.

The Cyrius port inherits the same frictions ADR-0003 faced for the trust gate:
no `chrono::DateTime` value type in the port idiom, and `Utc::now()` makes
`append` (hence every `entry_hash`) non-deterministic and untestable. There is
no cross-language entry-hash vector to match here — the chain is purely
self-consistent (mela computes and verifies both ends), unlike the SHA-256 /
Ed25519 known-answer vectors in the trust gate.

## Decision

**Represent `LogEntry.timestamp` as an `i64` epoch, supplied explicitly to
`tlog_append`, and fold its decimal form into the hash preimage.**

- `tlog_append(..., timestamp)` takes the time as a parameter; the caller owns
  the clock (consistent with `keyring_get_current_key`'s explicit `now`,
  ADR-0003).
- `compute_hash` hashes the timestamp as its decimal string
  (`str_from_int(epoch)`), in place of Rust's `to_rfc3339()`. Every other field
  is hashed exactly as Rust does (sequence as 8 big-endian bytes; the rest as
  their UTF-8 bytes).
- The JSON codec serializes `timestamp` as a JSON integer (epoch), not an
  RFC 3339 string.

## Consequences

- **Positive** — `append`, `compute_hash`, `verify_chain`, and the JSON
  round-trip are fully deterministic and parity-tested (append/verify, tampered
  entry detected, broken link detected, wrong sequence detected, tampered import
  rejected). No chrono dependency on a hot integrity path.
- **Negative** — the `entry_hash` byte values and the serialized `timestamp`
  field differ from the Rust implementation's. This is acceptable: the
  transparency chain's contract is internal self-consistency + tamper-evidence,
  not a byte-identical cross-language log. If a Rust-built log ever needs to
  validate in Cyrius, that becomes its own ADR (it would require matching the
  RFC 3339 preimage and serde shape exactly).
- **Neutral** — the epoch unit (s / ms / ns) is a caller convention, fixed when
  the first real clock consumer wires `append` (same open point as ADR-0003).

## Alternatives considered

- **Port `chrono` + `to_rfc3339` faithfully** — would reproduce Rust's exact
  hash preimage and JSON shape, but pulls calendar formatting into the hash path
  for no behavioral gain, and still needs an explicit clock for deterministic
  tests. Rejected.
- **Keep `Utc::now()` semantics (read a clock in `append`)** — non-deterministic
  `entry_hash`; impossible to pin in parity tests without clock mocking.
  Rejected in favor of an explicit `timestamp` parameter.
