# mela — Roadmap

> **Last Updated**: 2026-10-28 (v1.2.0) · Live status: [`state.md`](state.md) · History:
> [`../../CHANGELOG.md`](../../CHANGELOG.md) · Parity record: [`rust-parity.md`](rust-parity.md)
>
> Open work only. Shipped milestones (v0.1.0 port scaffold → v1.0.0 release → v1.2.0) are
> recorded in the CHANGELOG, not here. **v1.1.x** — the 2026-10-14 parity audit's fixes, the
> coverage catch-up, the divergence ADRs and the retirement of `rust-old/` — is complete
> (CHANGELOG 1.1.1–1.1.6). **v1.x** maps the backlog. Each item is self-contained, so an agent
> can pick one up cold.

## Working rules

- **One item per patch release** where practical. Each release: `cyrius build` + `cyrius test`
  green (plus `cyrius fuzz` / `cyrius bench` where the item touches them), then `VERSION`,
  CHANGELOG and [`state.md`](state.md).
- **Every fix lands with its regression test.**
- **Public API is frozen** ([`../api/`](../api/)). Additive changes are fine. Changing what a
  listed function accepts or returns needs an ADR, including a bug fix that starts rejecting
  input that used to be accepted.
- **The parity record is the oracle** since `rust-old/` was retired (v1.1.6): `tests/mela.tcyr`,
  the GNU tar and transport checks, [`rust-parity.md`](rust-parity.md) and ADR-0011/0012/0013. A
  behavior change needs an ADR; a parity assertion is never weakened without one.
- **Toolchain bumps** follow cyrius's *Moving a pin* procedure (`ecosystem-migration.md`):
  `cyrius lib sync --full --relock`, `cyrius deps`, `cyrius distlib`, then
  `cyrius deps --locked`.

---

## v1.x — Mapped backlog

Ordered by value to the trust boundary. Version numbers are a plan, not a promise. Re-sequence
here first when something lands early.

**Re-sequenced at v1.2.0 (2026-10-28):** v1.2.0 shipped as the cyrius 6.7.18 / agnostik 2.0.0
bump, so each milestone below moved up one minor. ADR-0008, ADR-0012, ADR-0013, the ADR index,
[`rust-parity.md`](rust-parity.md) and two comments in `src/flutter_agpkg.cyr` still use the old
numbers. Read their "v1.2.0" as Large bundles (now v1.3.0) and their "v1.3.0" as Hardening
residuals (now v1.4.0).

### v1.3.0 — Large bundles

Real Flutter engines are tens of MB.

- Streaming extraction: gunzip and untar to disk without the whole tar in memory.
- A real `MAX_PACKAGE_SIZE`: Rust used 100 MB compressed, plus a decompressed ceiling against
  gzip bombs.
- Keep file modes on extraction (the exec bit). Rust kept `mode & 0o777`; ADR-0013 §5 deferred
  the choice to this release, alongside the extractor rewrite.
- Long names: write the ustar `prefix` and read GNU `L` / PAX path records, or reject them
  explicitly. No silent truncation.
- Count extracted size toward the quota (Rust parity), once v1.1.5's ADR decides.

### v1.4.0 — Hardening residuals

- **Extraction confinement:** create every output with `O_NOFOLLOW`, or check the resolved path
  stays under the destination. Pre-existing symlinks in an install dir must not redirect writes.
  This closes the audit's finding-A follow-up properly.
- **Refresh `threat-model.md` and the audit residuals.** Their "Known gaps" still list on-disk
  extraction and live transport as deferred; both shipped in v0.9.2. Restate what is open.
- **Keyring provenance:** document how trusted publisher keys are distributed and rotated, with
  key-pinning guidance for consumers (ark). Open since v0.9.0, meant for before v1.0.
- **Transparency hash v2:** an unambiguous preimage with length prefixes or separators. It must
  be versioned, so v1 logs still verify on import.

### v1.5.0 — API and build hygiene

- Commit a `cyrius api-surface --scope=project` snapshot and gate CI on it. This turns the
  [`../api/`](../api/) freeze into a check.
- Clear the three `assigning non-pointer to typed pointer` warnings
  (`src/ratings.cyr`, `src/flutter_agpkg.cyr`). Check that none hides a real bug first.
- Move `assert` / `bench` to `[test] stdlib` (cyrius 6.7.6), so they leave the build's stdlib
  list.

### v1.6.0 — Targets beyond x86_64 Linux

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
