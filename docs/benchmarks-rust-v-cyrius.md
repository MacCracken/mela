# Benchmarks — Cyrius port vs Rust

> Captured at **v0.8.1** (2026-06-17). Harness: [`benches/hotpaths.cyr`](../benches/hotpaths.cyr).
> Numbers, not adjectives — per the roadmap release-run gate.

## Method

Each hot path is timed with `clock_now_ns()` over N iterations; the table reports
**ns/op** (total elapsed / N). Run it yourself:

```sh
cyrius run benches/hotpaths.cyr
```

`cyrius bench` is intentionally **not** used: at the pinned toolchain it SIGILLs
once mela's crypto/compression deps (`sigil`, `sankoch`) are linked into the
bench harness — independent of the bench body (even a no-op bench crashes). A
plain `cyrius run` timing loop sidesteps that and produces the same per-op
measurement. The fixtures (a valid manifest, a seeded Ed25519 keypair + signed
message, a one-entry registry, a packed `.agnos-agent` bundle) are built once,
outside the timed loops.

## Cyrius results

| Hot path            | ns/op (Cyrius) | iters | Notes |
|---------------------|---------------:|------:|-------|
| `registry_get`      |             72 | 200k  | hashmap lookup by name |
| `manifest_validate` |            389 | 200k  | name/version/semver/publisher rules |
| `sha256_hash`       |          1,016 | 200k  | SHA-256 of a 58-byte message (sigil) |
| `agpkg_inspect`     |         96,909 | 20k   | gunzip + ustar parse of a small bundle (sankoch + ustar) |
| `ed25519_verify`    |      7,749,099 | 3k    | Ed25519 verify (sigil, constant-time, pure-Cyrius) |

(Indicative single-run figures on the development host; absolute values vary by
machine. The point is the *shape* — lookups and validation are cheap; the
signature verify dominates and is the path to watch.)

### Reading the numbers

- **`registry_get` / `manifest_validate` / `sha256_hash`** are firmly in the
  sub-µs to ~1 µs range — install-time validation and registry queries are not a
  bottleneck.
- **`agpkg_inspect`** (~97 µs) is dominated by gzip inflate; fine for an
  install-time, once-per-package operation.
- **`ed25519_verify`** (~7.7 ms) dominates the trust gate. sigil's verify is
  correct (it matches the RFC 8032 known-answer vectors — see the `trust` test
  group) but is a portable, constant-time, pure-Cyrius implementation with no
  assembly field arithmetic, so it is far slower than a tuned native library.
  This is a `sigil` optimisation opportunity, not a mela one; for the
  marketplace's once-per-install verification it is acceptable, and it is the
  obvious first target if signature throughput ever matters.

## Rust comparison — deferred

The roadmap asks for a Cyrius-vs-`rust-old` comparison on these paths. The Rust
oracle **cannot be built in this environment**: `rust-old/Cargo.toml` depends on
`agnos-common` at `../agnosticos/userland/agnos-common`, which is not present, so
`cargo bench` will not resolve. The comparison column is therefore **left open**
until the Rust workspace is available; the Cyrius figures above stand on their
own as the v0.8.1 baseline and will be diffed against Rust when `agnos-common`
can be checked out alongside the port.

## Caveats

- DCE is not forced in these runs; the figures reflect the as-built binary.
- The duplicate-symbol warnings from stacking `agnostik` + `sigil` + `sankoch`
  (shared `ERR_*` / `LOG_*` constants) are benign and do not affect timing.
