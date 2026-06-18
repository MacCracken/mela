# 0001 — Manifest wire format is JSON

**Status**: Accepted
**Date**: 2026-06-17

## Context

The Rust oracle (`rust-old/src/lib.rs`) derives `Serialize`/`Deserialize` on
`MarketplaceManifest`, `PublisherInfo`, and `MarketplaceCategory`, and the
`test_manifest_serialization` / `test_publisher_info_serialization` tests
round-trip through **serde-JSON**. The Cyrius port has no serde — serialization
is hand-written (per the porting discipline) — so the v0.2.0 milestone must
*choose* and *pin* a wire format rather than inherit one from a derive macro.

Two facts force the choice to be explicit:

1. **No derive.** Cyrius emits and parses bytes by hand. Whatever format we pick,
   we own both directions and every field name.
2. **serde's enum representation is not the `Display` form.** A fieldless enum
   with a bare `#[derive(Serialize, Deserialize)]` (no `rename_all`) serializes
   to its **variant identifier** — `MarketplaceCategory::DesktopApp` → `"DesktopApp"`,
   `DevTool` → `"DevTool"`. That is *different* from the `Display`/`FromStr` form
   ported in `src/category.cyr` (`"desktop-app"`, `"devtool"`). The on-the-wire
   category string and the human-facing category string are not interchangeable.

`MarketplaceManifest` also `#[serde(flatten)]`s the base `AgentManifest` (from
`agnostik`): the agent's own fields sit at the manifest's top level, not nested
under an `"agent"` key.

## Decision

**The manifest wire format is JSON (UTF-8), matching the Rust serde-JSON choice.**

Concretely, for `MarketplaceManifest`:

- The flattened `AgentManifest` identity fields are **top-level** keys:
  `name`, `version`, `description` (the triple `validate()` and the round-trip
  test exercise). Other `AgentManifest` fields (permissions, limits, sandbox)
  remain agnostik's serialization responsibility and are **out of scope** for
  the mela manifest codec at v0.2.0 — mela owns the marketplace envelope, not
  the agent body.
- `publisher` is a nested object: `{ "name", "key_id", "homepage" }`.
- `category` is the **PascalCase serde variant name** — one of
  `"Utility"`, `"Productivity"`, `"Security"`, `"DevTool"`, `"DesktopApp"`,
  `"System"`. **Not** the lowercase `Display` form. The codec carries its own
  enum⇄string mapping, independent of `cat_name`/`cat_parse`.
- The `#[serde(default)]` fields — `runtime` (string), `screenshots` (array),
  `changelog` (string), `min_agnos_version` (string), `dependencies` (object,
  name→version-constraint), `tags` (array) — are **always emitted** on write and
  **default to empty** when absent on read (serde `default` semantics).
- **Write** emits keys in a fixed canonical order (deterministic output, so
  round-trip and golden tests are stable). **Read** is order-independent and
  tolerates missing `default` fields.

`PublisherInfo` serializes standalone as `{ "name", "key_id", "homepage" }`.

## Consequences

- **Positive** — parity target is concrete and testable: a Cyrius write →
  Cyrius read round-trip preserves `name`, `category`, `publisher.key_id` (the
  Rust test's assertions), and the format is the same human-readable JSON the
  Rust side produced.
- **Negative** — we now own a hand-written JSON encoder/decoder for these types
  and must keep the category enum mapping in lock-step with serde's variant-name
  rule; a future `rename_all` on the Rust enum would silently diverge. Guard:
  the round-trip test pins every category string.
- **Neutral** — full byte-for-byte equality with a *live* `agnos_common`
  serde output is not asserted (that crate isn't vendored here); the bar is
  self-consistent round-trip + the field values the oracle's tests check. If a
  cross-language golden vector is later needed, it gets its own ADR.

## Alternatives considered

- **A compact binary/TLV layout** — faster to emit, but breaks parity with the
  Rust serde-JSON oracle, isn't human-inspectable (manifests are reviewed by
  publishers and auditors), and would need its own cross-validation story.
  Rejected.
- **Reusing `cat_name`/`cat_parse` (the `Display` form) for the JSON category** —
  simplest, but wrong: it would write `"desktop-app"` where serde wrote
  `"DesktopApp"`, silently diverging the wire format. Rejected; the codec gets a
  separate mapping.
- **Nesting the agent under an `"agent"` key** — cleaner object shape, but the
  Rust side uses `#[serde(flatten)]`, so the agent fields are top-level. Matching
  the oracle wins over aesthetics.
