# mela — Roadmap

> **Last Updated**: 2026-10-28 (v1.5.1) · Live status: [`state.md`](state.md) · History:
> [`../../CHANGELOG.md`](../../CHANGELOG.md) · Parity record: [`rust-parity.md`](rust-parity.md)
>
> Open work only. Shipped milestones (v0.1.0 port scaffold → v1.0.0 release → v1.5.1) are
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
  input that used to be accepted. CI checks names and arities against
  [`../api-surface.snapshot`](../api-surface.snapshot) (v1.5.0); semantics are still the ADR's job.
- **The parity record is the oracle** since `rust-old/` was retired (v1.1.6): `tests/mela.tcyr`,
  the GNU tar and transport checks, [`rust-parity.md`](rust-parity.md) and ADR-0011–0016. A
  behavior change needs an ADR; a parity assertion is never weakened without one.
- **Toolchain bumps** follow cyrius's *Moving a pin* procedure (`ecosystem-migration.md`):
  `cyrius lib sync --full --relock`, `cyrius deps`, `cyrius distlib`, then
  `cyrius deps --locked`.

---

## v1.x — Mapped backlog

Ordered by value to the trust boundary. Version numbers are a plan, not a promise. Re-sequence
here first when something lands early.

**Re-sequenced at v1.2.0 (2026-10-28):** v1.2.0 shipped as the cyrius 6.7.18 / agnostik 2.0.0
bump, so each milestone below moved up one minor. ADR-0008, ADR-0012, ADR-0013, the ADR index and
[`rust-parity.md`](rust-parity.md) still use the old numbers in places. Read their "v1.2.0" as
Large bundles (part one shipped as v1.3.0; streaming is below, blocked upstream) and their
"v1.3.0" as Hardening residuals (now v1.4.0).

### Blocked upstream — Large bundles, part two (streaming)

v1.3.0 shipped long names, file modes, the 100 MiB cap and the quota before any write
([ADR-0014](../adr/0014-large-bundles-names-modes-limits.md)). What remains needs sankoch. Both
asks are filed in sankoch's `docs/development/issues/2026-10-28-gzip-has-no-output-override-and-no-bounded-memory-inflate.md`.

- **Bundles over 16 MiB of tar.** sankoch's gzip decoders stop at 16 MiB of output, whatever
  buffer the caller passes. Needs a gzip output override like zlib's `*_output_capped` (sankoch
  2.7.13). Then pick mela's own decompressed ceiling against gzip bombs and raise
  `AGPKG_BUF_MAXLEN` to it; the packer's input cap follows.
- **Streaming extraction:** gunzip and untar to disk without the whole tar in memory. Needs a
  bounded-memory inflate: sankoch's planned 2.9.5 ring window, with a way to drain output. The tar
  cursor (`_tar_cur_next`) and the two-pass extract (validate, then write) are already shaped for
  it.
- **A streaming packer**, so packing a large engine does not hold every input file in memory.

### Proposed — trust follow-ups from v1.4.0 (each needs a maintainer decision and an ADR)

v1.4.0 shipped the hardening residuals (ADR-0015, the refreshed threat model, the keyring
provenance guide). Writing them down surfaced three follow-ups. Key continuity on upgrade
shipped as v1.5.1 (ADR-0016). These two remain, in the threat model's *Known gaps*:

- **Check a key file's `key_id` against its public key on load.** A mismatched file lets one
  publisher's key sign under another's `key_id`. This is cheap, but it makes `keyring_load_dir`
  stricter.
- **Log equivocation.** Signed tree heads and a consistency proof between two views of the log,
  so a registry cannot show clients different logs, and dropping entries from the end is
  detectable. A design item, not a patch.

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
