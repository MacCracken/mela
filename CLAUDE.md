# mela — Claude Code Instructions

> **Core rule**: this file is **preferences, process, and procedures** —
> durable rules that change rarely. Volatile state (current version,
> module line counts, port progress, test counts, consumers) lives in
> [`docs/development/state.md`](docs/development/state.md).
> Do not inline state here.

## Project Identity

**mela** — Cyrius port of a Rust project. The Rust original was retired at v1.1.6; what it
specified lives in the parity suite and [`docs/development/rust-parity.md`](docs/development/rust-parity.md).

- **Type**: Port (Rust → Cyrius)
- **License**: GPL-3.0-only
- **Language**: Cyrius (toolchain pinned in `cyrius.cyml [package].cyrius`)
- **Version**: `VERSION` at the project root is the source of truth — do not inline the number here
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md) · [First-Party Documentation](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-documentation.md)

## Goal

mela is AGNOS's **marketplace trust boundary**: it owns the distribution, verification, and
on-device installation of apps and agents — deciding what is allowed to install. Every artifact
is Ed25519-signed, SHA-256-integrity-gated, and recorded in an append-only transparency log;
nothing installs without passing both trust gates. (Discovery and capability surfacing ride
along; paid distribution is out of scope until `mudra`/`vinimaya` exist.)

## Current State

> Volatile state lives in [`docs/development/state.md`](docs/development/state.md) —
> port progress, surface parity, in-flight work. Refreshed every release.

This file (`CLAUDE.md`) is durable rules.

## Scaffolding

Project was scaffolded with `cyrius port`. The Rust original (`rust-old/`) was the parity oracle until
v1.1.6, when it was deleted; it remains in git history.

## Quick Start

```sh
cyrius deps                              # resolve dependencies
cyrius build src/main.cyr build/mela    # compile
cyrius test                              # run tests/*.tcyr
```

## Key Principles

- **The parity record is the oracle** — `tests/mela.tcyr`, `scripts/tar-crosscheck.sh`,
  `scripts/transport-check.sh`, `docs/development/rust-parity.md` and ADR-0011/0012/0013 hold what
  the Rust original specified. A behavior change needs an ADR.
- **Correctness over cleverness** — if behavior changes silently, the bugs win
- Test after every change, not after the feature is "done"
- ONE change at a time — never bundle unrelated changes
- Build with `cyrius build`, not raw `cat file | cc5` — the manifest auto-resolves deps
- Source files only need project includes — stdlib auto-resolves from `cyrius.cyml`
- `var buf[N]` = N **bytes**, not N entries

## Rules (Hard Constraints)

- **Do not commit or push** — the user handles all git operations
- **Never use `gh` CLI** — use `curl` to the GitHub API if needed
- Do not weaken or delete a parity assertion in `tests/mela.tcyr` without an ADR
- Do not skip tests before claiming changes work
- Do not modify `lib/` files (vendored stdlib / dep symlinks)
- Do not hardcode toolchain versions in CI YAML — `cyrius = "X.Y.Z"` in `cyrius.cyml` is the source of truth

## Documentation

- [`docs/adr/`](docs/adr/) — Architecture Decision Records (*why X over Y?*)
- [`docs/architecture/`](docs/architecture/) — Non-obvious constraints
- [`docs/guides/`](docs/guides/) — Task-oriented how-tos
- [`docs/examples/`](docs/examples/) — Runnable examples
- [`docs/development/state.md`](docs/development/state.md) — Live state
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — Open milestones (v1.1.x, v1.x backlog)
- [`docs/development/rust-parity.md`](docs/development/rust-parity.md) — the parity record (the oracle since v1.1.6)

