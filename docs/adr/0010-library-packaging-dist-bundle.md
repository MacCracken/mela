# 0010 — Ship mela as a consumable library (dist bundle)

**Status**: Accepted
**Date**: 2026-06-17 (v0.9.2)

## Context

mela's v1.0 gate requires ≥1 downstream consumer (**ark**) green against it. When
ark tried, it found mela was **only a binary**: `cyrius.cyml` declared `[build]`
(entry/output) but **no `[lib]` section and no `dist/mela.cyr` bundle**, so it
could not be added to ark's `[deps]`. ark correctly refused to wire a broken
dependency. Every consumable AGNOS crate (agnostik, sigil, sankoch) ships a
single concatenated `dist/<name>.cyr` produced by `cyrius distlib` from a `[lib]
modules = [...]` list; mela had neither.

This was the real blocker behind "is v1.0 ready?" — the port could be *exercised*
in-repo but not *consumed*.

## Decision

**Declare `[lib]` and ship `dist/mela.cyr`.**

- Add `[lib] modules = [...]` to `cyrius.cyml` listing the 12 `src/` modules in
  dependency order (the `src/main.cyr` include chain). `cyrius distlib`
  concatenates them into `dist/mela.cyr` (the bundle consumers pull via
  `[deps.mela] modules = ["dist/mela.cyr"]`).
- `distlib` strips `lib/` includes (e.g. trust.cyr's `include "lib/thread_local.cyr"`)
  — the bundle carries mela's own code only; the **consumer supplies stdlib** via
  its `[deps] stdlib` list. The "unresolved symbols" note from `distlib` is
  expected (same as sigil/agnostik).
- **Consumer recipe** (documented in the README + `docs/api/`): pin
  `[deps.mela] modules = ["dist/mela.cyr"]`, plus mela's own deps
  (`agnostik`, `sigil`, `sankoch`) and the stdlib list mela uses; and — because
  the stdlib auto-resolver does not pull `thread_local` through a dist bundle —
  `include "lib/thread_local.cyr"` if the consumer calls the crypto/trust path.

## Consequences

- **Positive** — mela is consumable. **Proven**: a standalone program that
  includes *only* `dist/mela.cyr` (no `src/`) runs the full pipeline —
  `cat_parse`, `manifest_validate`, and `pipeline_install` with both trust gates
  — successfully. ark can now wire it.
- **Negative** — `dist/mela.cyr` is a generated artifact that must be regenerated
  (`cyrius distlib`) whenever a public `src/` module changes; it is committed so
  consumers don't have to build it. The `thread_local` include is a consumer-side
  requirement we must keep documented until the auto-resolver handles it.
- **Neutral** — mela remains a binary too (`[build]` is unchanged); it is now
  *both* a binary and a library, like agnostik.

## Alternatives considered

- **Keep it binary-only / tell ark to vendor `src/`** — defeats dependency
  management and the whole point of a shared marketplace layer. Rejected (and
  this is what produced the blocker).
- **Hand-maintain `dist/mela.cyr`** — drifts from `src/`; `cyrius distlib` is the
  supported generator. Rejected.
