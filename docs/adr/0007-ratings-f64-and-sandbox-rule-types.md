# 0007 — Ratings f64 averages, i64 timestamps; Landlock/Network rule types

**Status**: Accepted
**Date**: 2026-06-17

## Context

v0.7.0 ports two modules:

- **`ratings.rs`** — a deduplicating rating store with aggregate stats. Two Rust
  features need a porting decision: `RatingStats.average_score` is an **`f64`**,
  and `Rating.created_at` / `RatingFilter.from` / `until` are **`chrono`
  `DateTime<Utc>`**, with `add_rating` stamping `Utc::now()`.
- **`sandbox_profiles.rs`** — depends on `LandlockRule` and `NetworkRule`, which
  the Rust oracle defines in **`flutter_agpkg`** (the v0.8.0 packaging module,
  not yet ported).

## Decision

1. **`average_score` is a real `f64`** via Cyrius's float builtins
   (`f64_from` / `f64_to` / `f64_div` / `f64_gt` / `f64_lt`). `get_stats`
   computes `f64_div(total, count)`; `top_rated` ranks with `f64_gt`/`f64_lt`.
   Crucially, **`RatingStore` persists the ratings (integer scores), not the
   stats** — `get_stats` recomputes on read — so no float ever round-trips
   through JSON/disk. (`RatingStats` *can* serialize its `average_score` as a
   JSON float for the standalone stats-serialization path, but the store's
   save/load never depends on float fidelity.)
2. **Time is an `i64` epoch supplied explicitly** to `add_rating`; filters
   compare `i64`s (ADR-0003/0004 precedent). Deterministic, testable, no chrono
   on the rating path.
3. **`LandlockRule` / `NetworkRule` are defined in `sandbox_profiles.cyr`.** They
   are small value structs (`{path, access}` / `{enabled, allowed_hosts}`). The
   Rust oracle houses them in `flutter_agpkg`; when that module ports at v0.8.0
   it shares these exact shapes (no behavioral difference — just where the
   definition lives until then).

## Consequences

- **Positive** — averages and ranking are computed with true floating point
  (not a fixed-point approximation), matching the Rust semantics; every oracle
  test average is a whole number, so assertions via `f64_to` are exact. The
  store's persistence is integer-only and fully deterministic. `sandbox_profiles`
  ports now without waiting on `flutter_agpkg`.
- **Negative** — `RatingStats.average_score`'s JSON representation is a float
  whose exact formatting is bayan's, not serde's (no cross-language stats-JSON
  vector is asserted). `add_rating`'s signature gains an explicit `created_at`
  (diverges from `Utc::now()`). `LandlockRule`/`NetworkRule` live in two places
  conceptually until v0.8.0 unifies them.
- **Neutral** — when `flutter_agpkg` ports, it can re-export or reference the
  `sandbox_profiles` rule types rather than redefining them; the field layout is
  already fixed here.

## Alternatives considered

- **Fixed-point integer average (scaled ×1000)** — avoids floats entirely, but
  Cyrius *has* working f64 builtins, so real floats are both available and a
  closer parity. Rejected.
- **Port `chrono` for timestamps** — calendar machinery on the rating hot path
  for no gain; the filter logic is ordering comparison either way. Rejected.
- **Block `sandbox_profiles` on `flutter_agpkg`** — would stall a self-contained
  module behind a later milestone for two trivial structs. Rejected.
