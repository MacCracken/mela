# Getting started with mela

## Build

```sh
cyrius deps                              # resolve dependencies
cyrius build src/main.cyr build/mela    # compile
cyrius test                              # run tests/*.tcyr
```

## Layout

- `src/main.cyr` — entry point; `include`s the module chain below.
- `src/` modules — `category`, `manifest`, `depgraph`, `trust`, `transparency`, `local_registry`,
  `remote_client`, `sandbox_profiles`, `ratings`, `flutter_packaging`, `flutter_agpkg`, `pipeline`
  (the end-to-end flow). The frozen public surface is documented in [`../api/`](../api/).
- `tests/mela.tcyr` — parity test suite (auto-discovered by `cyrius test`); `tests/mela.fcyr` —
  fuzz harness for every external-data parser.
- `benches/hotpaths.cyr` — hot-path benchmarks (`cyrius run benches/hotpaths.cyr`).
- `rust-old/` — original Rust source, the frozen parity oracle. Do not modify. It is **not built
  here** (needs `agnos-common`); parity is asserted by hand in the tests.

## The end-to-end flow

`pipeline.cyr` ties the modules together: `pipeline_package` → `pipeline_publish` (Ed25519 sign
+ transparency log) → `pipeline_install`, which enforces **both trust gates** (signature +
SHA-256 digest) before recording into the registry. See the `pipeline` test group for a worked
example and [`../api/`](../api/) for signatures.

## Extending mela

1. Add or edit a `src/*.cyr` module and `include` it from `src/main.cyr` (after its deps).
2. Keep the public-API contract ([`../api/`](../api/)) stable — signature/semantic changes need
   an ADR ([`../adr/template.md`](../adr/template.md)).
3. Add a parity test group to `tests/mela.tcyr`; fuzz any new external-data parser in
   `tests/mela.fcyr`.
4. `cyrius test` (green gate). Bump `VERSION` + add a CHANGELOG entry before tagging.
