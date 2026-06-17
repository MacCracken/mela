# Architecture Notes

Invariants, constraints, and quirks a reader **cannot derive from the code alone** — *how the
world is*, not *what we chose* (that's an [ADR](../adr/)) and not *how to do X* (that's a
[guide](../guides/)).

## Conventions

- **Filename**: `NNN-kebab-case-title.md`, zero-padded to three digits, numbered in order of
  discovery. **Never renumber.**
- Index each note below with a one-line hook **and what it affects**, so a reader skimming can
  tell if it touches their work.

## Index

- [`overview.md`](overview.md) — system-level module map, intended data flow, trust gates, and
  the planned `mudra`/`vinimaya` boundary. *Affects: anyone working anywhere in mela.*

_No numbered architecture notes yet — add `NNN-*.md` as non-obvious invariants surface._
