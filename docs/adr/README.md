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
