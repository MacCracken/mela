# Benchmarks — Cyrius port vs Rust

> Captured at **v1.1.0** (2026-10-14, cyrius 6.7.9). Harness: [`tests/mela.bcyr`](../tests/mela.bcyr).
> Numbers, not adjectives — per the roadmap release-run gate.

## Method

`lib/bench.cyr` via `cyrius bench`. Each row runs a fixed batch per clock pair
(`bench_run_batch`), sized so one window is ~1 ms or more, so the clock's own
error stays under 1 % of a window and min/max resolve. The measured clock-read
floor is subtracted from every window and printed with the report. Run it
yourself:

```sh
cyrius bench
```

The fixtures (a valid manifest, a seeded Ed25519 keypair + signed message, a
one-entry registry, a packed `.agnos-agent` bundle) are built once, outside the
timed windows, and each is checked to take its success path before timing.

Up to v1.0.5 the harness was a hand-rolled `clock_now_ns()` loop
(`benches/hotpaths.cyr`, run with `cyrius run`), because at the v0.8.1 toolchain
`cyrius bench` SIGILLed once sigil + sankoch were linked in. On cyrius 6.7.9 it
does not, so the hand loop was retired at v1.1.0. The v0.8.1 column below is from that loop.

## Cyrius results

| Hot path            | v1.1.0 avg ns/op | min – max ns/op     | v0.8.1 ns/op | iters | Notes |
|---------------------|-----------------:|---------------------|-------------:|------:|-------|
| `registry_get`      |               75 | 69 – 82             |           72 | 200k  | hashmap lookup by name |
| `manifest_validate` |              134 | 126 – 145           |          389 | 200k  | name/version/semver/publisher rules |
| `sha256_hash`       |              760 | 738 – 804           |        1,016 | 200k  | SHA-256 of a 58-byte message (sigil) |
| `agpkg_inspect`     |          104,890 | 63,901 – 155,027    |       96,909 | 5k    | gunzip + ustar parse of a small bundle (sankoch + ustar) |
| `ed25519_verify`    |        5,148,000 | 5,043,000 – 5,382,000 |    7,749,099 | 200   | Ed25519 verify (sigil, constant-time, pure-Cyrius) |

(Single run on the development host, timer floor 1.32 µs per clock read. Absolute
values vary by machine and, on this host, between boots. The point is the
*shape*: lookups and validation are cheap, and the signature verify dominates and
is the path to watch.)

### Reading the numbers

- **`registry_get` / `manifest_validate` / `sha256_hash`** are firmly in the
  sub-µs range, so install-time validation and registry queries are not a
  bottleneck.
- **`agpkg_inspect`** (~105 µs) is dominated by gzip inflate; fine for an
  install-time, once-per-package operation. It has the widest window-to-window
  spread of the five rows.
- **`ed25519_verify`** (~5.1 ms) dominates the trust gate. sigil's verify is
  correct (it matches the RFC 8032 known-answer vectors — see the `trust` test
  group) but is a portable, constant-time, pure-Cyrius implementation with no
  assembly field arithmetic, so it is far slower than a tuned native library.
  This is a `sigil` optimisation opportunity, not a mela one; for the
  marketplace's once-per-install verification it is acceptable, and it is the
  obvious first target if signature throughput ever matters.

## Rust comparison

Captured 2026-10-15 on the development host (AMD Ryzen 7 5800H, Linux 7.2.8, clocksource hpet),
in one session: the Rust and Cyrius benches ran alternately, three times each, and the table gives
the median of the three run averages. Both harnesses subtract the measured cost of one clock read
per timed window (Rust ~1.42 µs, Cyrius ~1.35 µs on this host).

| Hot path            | Rust ns/op | Cyrius ns/op | Cyrius ÷ Rust |
|---------------------|-----------:|-------------:|--------------:|
| `registry_get`      |         18 |           70 |          3.9× |
| `manifest_validate` |         62 |          168 |          2.7× |
| `sha256_hash`       |        139 |          816 |          5.9× |
| `agpkg_inspect`     |      7,793 |      110,102 |         14.1× |
| `ed25519_verify`    |     30,742 |    5,504,000 |          179× |

How the Rust side was built and measured:

- **The code** is the Rust original, the `rust-old/` crate as committed before its retirement in
  v1.1.6, built with rustc 1.97.1 `--release`. Its only external piece, the `AgentManifest` type,
  comes from agnostik's Rust crate (agnostik commit `3507c46`, 2026-03-25, the last one whose
  `AgentManifest.version` is a `String`, which is what this code expects). Rust's own suite passes
  on that build: 204/204.
- **The harness** mirrors `tests/mela.bcyr`: the same seed, message and manifest values, the same
  batch sizes and rounds, with `std::hint::black_box` around inputs and results.
- **`agpkg_inspect`** gunzips and lists the identical 416-byte bundle the Cyrius bench inspects,
  with the `flate2` and `tar` crates the Rust original packed with. Rust had no inspect function of
  its own. mela's inspector also decompresses into an 8 MiB working buffer on every call, where the
  Rust crates stream; the wide spread on the Cyrius row (min 73.5 µs, max 149.7 µs) comes from that.
- **`ed25519_verify`** is `ed25519-dalek` against sigil. The gap is the one *Reading the numbers*
  above describes: a portable, constant-time, pure-Cyrius implementation with no assembly field
  arithmetic, against a tuned native library.

## Caveats

- DCE is not forced in these runs; the figures reflect the as-built binary.
- The v0.8.1 and v1.1.0 columns come from different harnesses (one clock pair
  per N iterations vs. one per fixed batch, floor-subtracted). Read the change
  between them as indicative, not as a measured speed-up.
