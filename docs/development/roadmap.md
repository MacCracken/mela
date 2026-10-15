# mela — Roadmap

> **Last Updated**: 2026-10-14 (v1.1.0) · Live status: [`state.md`](state.md) · History:
> [`../../CHANGELOG.md`](../../CHANGELOG.md) · Parity audit: [`rust-parity.md`](rust-parity.md)
>
> Open work only. Shipped milestones (v0.1.0 port scaffold → v1.0.0 release → v1.1.0) are
> recorded in the CHANGELOG, not here. **v1.1.x** fixes what the 2026-10-14 parity audit found,
> closes the coverage gap and retires `rust-old/`. **v1.x** maps the rest of the backlog. Each
> item is self-contained, so an agent can pick one up cold.

## Working rules

- **One item per patch release** where practical. Each release: `cyrius build` + `cyrius test`
  green (plus `cyrius fuzz` / `cyrius bench` where the item touches them), then `VERSION`,
  CHANGELOG and [`state.md`](state.md).
- **Every fix lands with its regression test.** The D-numbers below refer to
  [`rust-parity.md`](rust-parity.md) § Defects found.
- **Public API is frozen** ([`../api/`](../api/)). Additive changes are fine. Changing what a
  listed function accepts or returns needs an ADR, including a bug fix that starts rejecting
  input that used to be accepted.
- **`rust-old/` is the oracle until v1.1.x deletes it.** Do not edit it. A divergence from it
  needs an ADR, or an entry in `rust-parity.md`.
- **Toolchain bumps** follow cyrius's *Moving a pin* procedure (`ecosystem-migration.md`):
  `cyrius lib sync --full --relock`, `cyrius deps`, `cyrius distlib`, then
  `cyrius deps --locked`.

---

## v1.1.x — Audit fixes, coverage catch-up, retire `rust-old/`

Baseline at v1.1.0:
- Rust tests: 171 of 204 covered, 23 partial, 10 not covered.
- `cyrius coverage`: 247 of 326 `src/` fns (75%).
- CI builds but runs no tests.

v1.1.1 shipped the memory-safety group, D1–D5, plus D12's duplicate-name half (see the
CHANGELOG and ADR-0011).
v1.1.2 shipped the CI gate: `deps --locked`, test, fuzz, bench, `coverage --min 76`, and the
GNU tar cross-check (`scripts/tar-crosscheck.sh`).

### v1.1.3 — Correctness fixes

Defects that make a feature not work.

- **D6, sandbox presets:** `_rule` takes the `data_dir` Str directly. Test: each preset's first
  rule is the app's data dir.
- **D7, transport:**
  - `mela_fetch_artifact` / `rc_download` stream to the destination through
    `sandhi_http_download(url, fd, opts)`, which lifts the 256 KiB cap, with a mela-side size
    ceiling and partial-file cleanup.
  - Apply `REQUEST_TIMEOUT` / `DOWNLOAD_TIMEOUT`, follow redirects, and send a User-Agent.
- **D8, size policy (fail closed now):**
  - The packer fails on any file it cannot read in full, instead of truncating at 8 MiB.
  - Install fails cleanly on a bundle over the cap.
  - Full large-bundle support is v1.2.0.
- **D9, install transaction:**
  - Extract first, record second, and fail on an extraction or index-save error.
  - A corrupt or oversized `index.json` fails closed instead of loading as empty.
  - `registry_save_index` creates parent dirs.
- **D10, publish:** `rc_publish` sends the signature (`X-Package-Metadata`, as Rust did).
- **D11, assets:** walk `flutter_assets/` recursively. Correct ADR-0008's rationale.
- **D12, manifest:** an unknown or missing `category` rejects the manifest. (The
  duplicate-entry half shipped in v1.1.1.)

### v1.1.4 — Coverage catch-up

- Close the 23 partial and 9 uncovered Rust tests, or mark each N/A in `rust-parity.md` with the
  reason. `RatingFilter` / `DisplayBackend` codecs have no consumer, so they are N/A candidates.
- Add the untested-behavior assertions listed per group in `rust-parity.md` § Coverage to add.
  The ones that matter most for the trust boundary:
  - The transparency link, sequence and entry-0 checks, each exercised on its own. Today every
    tamper test breaks the entry hash first.
  - An **on-disk** end-to-end `pipeline_install`, with files under `packages/<name>`, reopen, and
    uninstall.
  - Signature edge cases: `sig_len` 63 / 65, bit flips in R or S, S + L, small-order key.
  - Keyring rotation and inclusive validity edges.
- Raise the `cyrius coverage --min` gate in `ci.yml` (76 at v1.1.2) to the level reached.

### v1.1.5 — Decide the unrecorded divergences

One ADR per decision, covering every item in `rust-parity.md` § Behavior changes with no ADR:

- Strict vs lenient JSON decoding at trust-boundary inputs: one rule for every decoder.
- Install accounting: `installed_size` (compressed vs extracted, which changes the quota), file
  modes, resolved-path containment.
- Archive writer: normalized mode/uid/mtime (reproducible), long names, unreadable inputs,
  compact JSON.
- Text: ASCII vs Unicode lowercasing, `sanitize_filename`, semver `+` and overflow,
  scale-factor formatting.
- The ratings wire format vs Rust-written files.
- Keyring per-element vs per-file validation.
- The transparency hash-preimage ambiguity: record it now; fixing it is v1.3.0.

### v1.1.6 — Retire `rust-old/`

- Every box in `rust-parity.md` § Retirement checklist is ticked.
- Delete `rust-old/`. Mark its CHANGELOG entry as the end of the Rust oracle.
- Replace the CLAUDE.md "cross-check against `rust-old/`" principle and its *Scaffolding*
  section: the parity suite plus `rust-parity.md` are the oracle.
- `docs/benchmarks-rust-v-cyrius.md`: close the "Rust comparison — deferred" section. No Rust
  numbers were ever recorded, so the column is dropped, not deferred.

---

## v1.x — Mapped backlog

Ordered by value to the trust boundary. Version numbers are a plan, not a promise. Re-sequence
here first when something lands early.

### v1.2.0 — Large bundles

Real Flutter engines are tens of MB.

- Streaming extraction: gunzip and untar to disk without the whole tar in memory.
- A real `MAX_PACKAGE_SIZE`: Rust used 100 MB compressed, plus a decompressed ceiling against
  gzip bombs.
- Keep file modes (the exec bit); an ADR decides `mode & 0o755` vs normalize.
- Long names: write the ustar `prefix` and read GNU `L` / PAX path records, or reject them
  explicitly. No silent truncation.
- Count extracted size toward the quota (Rust parity), once v1.1.5's ADR decides.

### v1.3.0 — Hardening residuals

- **Extraction confinement:** create every output with `O_NOFOLLOW`, or check the resolved path
  stays under the destination. Pre-existing symlinks in an install dir must not redirect writes.
  This closes the audit's finding-A follow-up properly.
- **Refresh `threat-model.md` and the audit residuals.** Their "Known gaps" still list on-disk
  extraction and live transport as deferred; both shipped in v0.9.2. Restate what is open.
- **Keyring provenance:** document how trusted publisher keys are distributed and rotated, with
  key-pinning guidance for consumers (ark). Open since v0.9.0, meant for before v1.0.
- **Transparency hash v2:** an unambiguous preimage with length prefixes or separators. It must
  be versioned, so v1 logs still verify on import.

### v1.4.0 — API and build hygiene

- Commit a `cyrius api-surface --scope=project` snapshot and gate CI on it. This turns the
  [`../api/`](../api/) freeze into a check.
- Clear the three `assigning non-pointer to typed pointer` warnings
  (`src/ratings.cyr`, `src/flutter_agpkg.cyr`). Check that none hides a real bug first.
- Move `assert` / `bench` to `[test] stdlib` (cyrius 6.7.6), so they leave the build's stdlib
  list.

### v1.5.0 — Targets beyond x86_64 Linux

- **aarch64:** builds today. Run the suite under qemu-user in CI (agnostik's precedent).
- **agnos:** builds today (v1.0.5 routed filesystem calls through `xunlink` / `xrmdir` /
  `xmkdir`). Runtime is unvalidated: registry filesystem operations, and sandhi's transport,
  whose agnos runtime correctness sandhi still lists as open. Validate it once an agnos runner
  exists.

### Later — features (unscheduled)

- **Advanced discovery:** recommendations, federated marketplaces.
- **Paid distribution:** integrate `mudra` (asset identity / ownership) and `vinimaya` (transfers
  / escrow / settlement) behind a thin internal boundary, with interim stubs first. Blocked until
  those repos exist. The free-distribution path must never block on them.
- **Signature throughput:** `ed25519_verify` is ~5 ms/op ([`../benchmarks-rust-v-cyrius.md`](../benchmarks-rust-v-cyrius.md)).
  That is fine per install, but a DoS factor for any server-side bulk verify. It is a `sigil`
  optimisation, tracked upstream.
