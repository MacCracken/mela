# 0003 — Trust: epoch-i64 time, explicit `now`, deferred keyring load

**Status**: Accepted — keyring-load deferral **resolved in v0.9.4**
**Date**: 2026-06-17 (load resolved 2026-06-18)

> **Resolution (v0.9.4)**: decision 3's deferral is closed. `keyring_load_dir(kr, dir)`
> (in `src/trust.cyr`) scans a directory of `*.json` files — each a JSON array of
> `KeyVersion` — and loads them into the keyring, ignoring non-json files. The on-disk
> `KeyVersion` shape is the manifest-style codec promised below: `kv_to_json` /
> `kv_from_json` (+ the `kv_to_jv` / `kv_from_jv` value helpers), reusing the ADR-0001
> JSON approach. Mirrors rust-old `PublisherKeyring::load`. Covered by the `keyring-load`
> test (round-trip + on-disk load + absent-dir). Decisions 1 (epoch-i64 time) and 2
> (explicit `now`) stand unchanged.

## Context

`rust-old/src/trust.rs` models a publisher key's validity window with
`chrono::DateTime<Utc>` (`valid_from`, `valid_until: Option<...>`) and decides
"is this key current?" against `Utc::now()` read inside
`PublisherKeyring::get_current_key`. It also loads trusted keys from disk:
`PublisherKeyring::load()` scans a directory of `*.json` files and deserializes
`Vec<KeyVersion>` from each.

The Cyrius port faces three frictions:

1. **No `chrono::DateTime` value type in the port's idiom.** mela's structs are
   8-byte fields; a wall-clock instant is naturally an `i64` epoch.
2. **`Utc::now()` makes trust decisions non-deterministic** and untestable
   without freezing the clock — bad for a load-bearing security primitive whose
   tests must pin exact boundary behavior.
3. **`load()` needs a filesystem** (directory iteration + per-file JSON). The
   v0.3.0 dep gate is `sigil` (crypto) only; stdlib `fs` and the on-disk key
   format belong to the persistence milestones (v0.4.0 transparency / v0.5.0
   local_registry).

## Decision

1. **Represent validity-window time as `i64` epoch with an explicit
   `has_until` flag** (Cyrius has no `Option`). `kv_is_valid_at(kv, when)` is
   integer comparison: false before `valid_from`, false after `valid_until`
   when `has_until == 1`, else true. Byte-for-byte the same decision the Rust
   `is_valid_at` makes.
2. **`keyring_get_current_key(kr, key_id, now)` takes `now` as a parameter**
   rather than reading a global clock. Trust decisions become a pure function of
   their inputs — deterministic and directly parity-testable. The caller
   supplies the current time (from whatever clock it trusts).
3. **Defer `PublisherKeyring::load()` (the disk loader) to the fs-persistence
   milestone.** Everything else in `trust.rs` ports now: the crypto
   (hash/sign/verify/keypair/key_id), hex codec, `KeyVersion`
   (`is_valid_at` / `verifying_key`), and the in-memory keyring
   (`add_key` / `get_current_key` / `get_all_versions` / `len` / `is_empty`).
   This keeps `sigil` the sole new v0.3.0 dep gate.

## Consequences

- **Positive** — validity logic is deterministic and tested at exact boundaries
  (before / within / after window, no-expiry, not-yet-valid). The crypto core
  is fully ported and known-answer-tested (SHA-256 + RFC 8032 Ed25519 vectors).
  No `fs` dependency pulled ahead of its milestone.
- **Negative** — `get_current_key`'s signature diverges from Rust (gains a `now`
  parameter); callers must pass the time. The epoch unit (seconds vs ms vs ns)
  is a caller convention mela does not yet pin — `is_valid_at` only needs a
  consistent monotonic-ish ordering, so the unit is fixed when the first real
  clock consumer lands.
- **Neutral** — `keyring_load` is a known gap until fs arrives; the on-disk key
  format (the JSON shape of a `KeyVersion` file) gets pinned with that work,
  reusing the manifest JSON-codec approach (ADR-0001).

## Alternatives considered

- **Port `chrono::DateTime` faithfully** — pulls chrono's calendar machinery
  into a hot trust path for no behavioral gain over an `i64` instant; the
  decision is an ordering comparison either way. Rejected.
- **Read a global clock inside `get_current_key`** (mirror `Utc::now()`) — keeps
  the Rust signature but makes the security-critical path non-deterministic and
  forces clock-mocking in tests. Rejected in favor of an explicit `now`.
- **Port `load()` now with stdlib `fs`** — introduces `fs` and an on-disk key
  format a milestone early, ahead of the persistence design. Deferred.
