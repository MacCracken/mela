# 0002 — Agent version is a mela-owned Str descriptor

**Status**: Accepted
**Date**: 2026-06-17

## Context

`MarketplaceManifest` flattens the base `AgentManifest`. In the Rust oracle
(`rust-old/src/lib.rs`) the agent's `version` is a `String`, and
`MarketplaceManifest::validate()` exercises it as a string in two rules:

- `version is required` — fires when the string is empty;
- `version '{}' is not valid semver` — fires when `is_valid_semver` rejects it.

The dep gate `agnostik` (mandated by the roadmap as the source of
`AgentManifest`) models `version` differently: a **structured `Version`**
(`major`/`minor`/`patch`/`prerelease`/`build`, at offset 24 of its
`AgentManifest`). A structured `Version` is *always* well-formed —
`version_default()` is `0.0.0`, there is no empty or non-semver state. Flattening
agnostik's `version` field as-is would make both oracle validation rules
**unreachable**, silently weakening the manifest's validation contract.

## Decision

**Wire agnostik in as the agent body, but carry the agent `version` as a
mela-owned `Str` descriptor on `MarketplaceManifest` (offset 24), validated by
`is_valid_semver`.**

- The agent's `name` and `description` are read straight off agnostik's
  `AgentManifest` (`amanifest_name` / `amanifest_description`, both `Str`) — the
  flatten is real for those fields.
- The agent's `version` is **not** taken from agnostik's structured `Version`
  for validation purposes; mela stores the version string it was given and runs
  the oracle's empty + semver checks against it (`man_version`).
- agnostik's structured `Version` remains available via
  `amanifest_version(man_agent(m))` for any consumer that wants the parsed form.

This is the "oracle-faithful `Str`, agnostik still wired" shape: agnostik is the
agent body; the validatable version descriptor is mela's.

## Consequences

- **Positive** — `validate()` reproduces the Rust oracle exactly, including the
  `version is required` and `not valid semver` paths; all of the oracle's
  validate tests port 1:1.
- **Negative** — the version exists in two forms if a consumer also reads
  agnostik's structured `Version`: the mela `Str` descriptor (authoritative for
  validation) and agnostik's parsed `Version`. They must be kept consistent by
  whoever builds the manifest; mela does not cross-check them.
- **Neutral** — when the manifest JSON codec (ADR-0001) lands, the `version`
  string serializes from the mela descriptor, not from agnostik's `Version`.

## Alternatives considered

- **Flatten agnostik's structured `Version` directly** — tightest integration,
  but drops two validation rules the oracle enforces; rejected (would diverge
  from the parity bar without recovering the lost checks).
- **Don't depend on agnostik at all; hold the whole agent body as Strs** —
  simplest for v0.2.0, but contradicts the roadmap's dep gate and the agent body
  (permissions/limits/sandbox) that later modules consume from agnostik.
  Rejected.
