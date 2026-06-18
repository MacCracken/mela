# Architecture Decision Records

Decisions about mela — what we chose, the context, and the consequences we accept. Use these when a future reader would reasonably ask *"why did we do it this way?"*

## Conventions

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. Never renumber.
- **One decision per ADR.** If a decision supersedes a prior one, add a new ADR and set the old one's status to `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` or `Deprecated`.
- Use [`template.md`](template.md) as the starting point.

## ADR vs. architecture note vs. guide

| Kind | Lives in | Answers |
|---|---|---|
| ADR | `docs/adr/` | *Why did we choose X over Y?* |
| Architecture note | `docs/architecture/` | *What non-obvious constraint is true about the code?* |
| Guide | `docs/guides/` | *How do I do X?* |

## Index

- [0001 — Manifest wire format is JSON](0001-manifest-wire-format-json.md) — *Accepted* · the
  hand-written manifest codec targets serde-JSON parity; category serializes as the PascalCase
  variant name, not the `Display` form.
- [0002 — Agent version is a mela-owned Str descriptor](0002-agent-version-as-str-descriptor.md) —
  *Accepted* · agnostik is wired as the agent body, but version stays a validatable `Str` (its
  `Version` struct can't be empty/invalid), so `validate()` keeps the oracle's version checks.
- [0003 — Trust: epoch-i64 time, explicit `now`, deferred keyring load](0003-trust-time-and-deferred-keyring-load.md) —
  *Accepted* · key validity windows use `i64` epochs (not chrono); `get_current_key` takes an
  explicit `now` for deterministic trust; the disk `load()` defers to the fs milestone.
- [0004 — Transparency log timestamp is an i64 epoch](0004-transparency-timestamp-epoch.md) —
  *Accepted* · `LogEntry.timestamp` is an explicit `i64` epoch (not chrono), hashed as its
  decimal form and serialized as a JSON int; the chain stays self-consistent + tamper-evident.
- [0005 — Registry on-disk index format + tarball-extraction deferral](0005-registry-index-format-and-tarball-deferral.md) —
  *Accepted* · `index.json` is a name→record JSON object (manifest nested via the ADR-0001 codec);
  install operates on an already-extracted manifest, with gzip/tar extraction deferred to v0.8.0
  (`sankoch`).
- [0006 — Remote client HTTP/TLS transport is a deferred seam](0006-remote-client-transport-seam.md) —
  *Accepted* · URL building, response-type JSON codec, offline guards, and response cache port now;
  the live `sandhi`/`tls` transport (`_rc_http_get`) defers to the v0.9.0 end-to-end wiring.
- [0007 — Ratings f64 averages, i64 timestamps; Landlock/Network rule types](0007-ratings-f64-and-sandbox-rule-types.md) —
  *Accepted* · `average_score` uses real f64 builtins (store persists integer scores, recomputes
  stats); `created_at` is an i64 epoch; `LandlockRule`/`NetworkRule` defined in `sandbox_profiles`
  until `flutter_agpkg` (v0.8.0).
- [0008 — Packaging: sankoch gzip + hand-rolled ustar; system-tar cross-validation](0008-packaging-gzip-ustar-and-cross-validation.md) —
  *Accepted* · gzip via `sankoch`, ustar tar hand-rolled (sankoch is compression-only); the
  format is cross-validated against the system `tar` both directions (rust-old can't be built).
- [0009 — End-to-end pipeline + trust-gate enforcement](0009-end-to-end-pipeline-and-gate-enforcement.md) —
  *Accepted* · `src/pipeline.cyr` wires package→sign→log→verify→install; both trust gates
  (signature + digest) are enforced at install; transport stays a local seam (ADR-0006).
