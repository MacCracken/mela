# Contributing to mela

mela is the **app & agent marketplace for AGNOS** — discovery, distribution, and trust
verification (Ed25519 signatures, SHA-256 integrity, an append-only transparency log). It is
a **Cyrius port of a Rust original**, now complete. The Rust source was the parity oracle until
v1.1.6, when it was retired; the parity suite and `docs/development/rust-parity.md` carry what it
specified.

## Ground rules

- **Keep parity, then improve.** `tests/mela.tcyr`, `docs/development/rust-parity.md` and
  ADR-0011/0012/0013 record what the Rust original did. Change behavior only with an ADR, and
  never weaken or delete a parity assertion without one.
- **Correctness is the optimum sovereignty.** Test after every change, not after the feature
  is "done."
- **One change at a time.** Don't bundle unrelated changes.
- **Read [`CLAUDE.md`](CLAUDE.md) first** — the canonical process, conventions, and the Cyrius
  gotchas list that will save you real time.
- **No FFI, first-party only.** Every layer is reimplemented in Cyrius; no OpenSSL, no libc.
  TLS goes through the stdlib `tls`/`tls_native` surface (the marketplace's rustls-only rule,
  carried into the sovereign stack).

## Building and testing

```sh
cyrius deps                              # resolve [deps.*] from cyrius.cyml into lib/
cyrius build src/main.cyr build/mela     # build
cyrius test                              # run tests/*.tcyr (auto-discovered)
cyrius bench tests/mela.bcyr             # benchmarks
cyrius fuzz                              # fuzz harness (tests/mela.fcyr)
bash scripts/tar-crosscheck.sh           # bundle format vs GNU tar, both directions
bash scripts/transport-check.sh          # live HTTP client vs a local python3 server
```

CI runs all of these, plus `cyrius deps --locked` and a `cyrius coverage --min` floor
(`.github/workflows/ci.yml`).

Every change passes the same gates as existing code:

- **Tests green** — add coverage for new behavior in `tests/mela.tcyr`. A change isn't done until
  its behavior is asserted; a change to existing behavior also needs an ADR.
- **Fuzz every parser path** — anything consuming external data (manifests, package bytes,
  signatures, URLs) earns a harness in `tests/mela.fcyr`.
- **Benchmark before claiming perf** — numbers in `tests/mela.bcyr`, against the Rust
  predecessor in `docs/benchmarks-rust-v-cyrius.md`, or it didn't happen.

## Cyrius conventions (the ones that bite)

mela's port follows the AGNOS Cyrius conventions. The sharp edges:

- `var buf[N]` is **N bytes** in a function (N×u64 at module scope) — every buffer is a contract.
- No `break` in a `while` loop that declares a `var` — use a flag + `continue`.
- No negative literals (`(0 - N)`, not `-N`); no mixed `&&`/`||` in one expression (nest `if`s).
- `streq(a, b)` for cstring/raw-buffer compare (NOT `str_eq`, which is for the `Str` type).
- Struct fields are 8 bytes via `load64`/`store64` at an offset; there are no serde derives —
  serialization is hand-written, and every type ported gets a roundtrip test.

Study a working Cyrius program before writing new code (`yukti/src/main.cyr`,
`patra/programs/demo.cyr`), and read `docs/development/rust-parity.md` and the ADRs for why
existing behavior is the way it is.

## Documentation

- **Decisions** → an ADR in [`docs/adr/`](docs/adr/) (use [`template.md`](docs/adr/template.md); never renumber).
- **Non-obvious constraints/quirks** → a numbered note in [`docs/architecture/`](docs/architecture/).
- **How-tos** → [`docs/guides/`](docs/guides/); **runnable examples** → [`docs/examples/`](docs/examples/).
- **Changelog** → [Keep a Changelog](https://keepachangelog.com/); perf claims need numbers,
  breaking changes need a migration note, security fixes get a **Security** section.

## Cross-project requests

mela depends on first-party crates (`sigil`, and the planned `mudra` / `vinimaya` value
cluster) and the Cyrius toolchain. **These repos don't use the GitHub issue tracker.** If mela
needs something from a dependency, draft a backlog entry on *that repo's*
`docs/development/roadmap.md` rather than filing an issue.

## Commits & PRs

The maintainer handles tagging and releases. Keep commits focused, message the *why*, and make
sure the tree is green (tests + build) before you push. Security-sensitive reports go through
[`SECURITY.md`](SECURITY.md), not a public PR.

## Conduct

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
