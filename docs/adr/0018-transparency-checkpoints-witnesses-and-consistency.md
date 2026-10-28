# 0018 — Transparency checkpoints, witness cosignatures and consistency proofs

**Status**: Accepted
**Date**: 2026-10-28 (v1.5.2)

## Context

**The transparency log was tamper-evident, not equivocation-proof.** Each entry is SHA-256
hash-chained to the one before (v2 preimage since v1.4.0, ADR-0015). `tlog_verify_chain` catches an
edited, reordered or re-sequenced entry. It could not catch two things the v1.4.0 threat model
listed under *Known gaps*:
- **Truncation:** a log with entries dropped from its end still verifies.
- **A split view:** a registry can show two clients two different logs, each internally
  consistent. One client sees a version the other never does: a targeted backdoor, for example.

**Detecting either needs a signed statement and something to compare it with.** Certificate
Transparency, Go's checksum database and sigsum do this with:
- signed tree heads (*checkpoints*);
- consistency proofs between two heads;
- independent *witnesses* that cosign only heads consistent with the last one they saw.

The roadmap's item asked for signed tree heads, a consistency proof between two views, and
truncation detection.

**mela's log is a library primitive.** `pipeline_publish` appends to a log the caller owns. Nothing
in mela serves the log over the network or fetches it, so neither does this ADR.

## Decision

**The log signs checkpoints of its hash-chain head. A client keeps the last checkpoint it accepted
and moves only to one that a consistency proof shows extends it. It can require cosignatures from
witnesses it trusts.** Everything is in `src/transparency.cyr`.

### The checkpoint

A checkpoint states "log *origin* has *size* entries, the last of which hashes to *head*", signed
at *timestamp*:
- `origin` names the log, so a checkpoint for one log is never taken for another's.
- `head` is the last entry's `entry_hash`, `""` for an empty log.
- **The head of a hash chain commits to the whole prefix**, as a Merkle root does. Each entry's
  hash covers its sequence number and the hash before it.

The log signs this preimage with Ed25519:
```
len BE8 || "mela.transparency.checkpoint.v1" || len BE8 || origin || size BE8 ||
len BE8 || head || timestamp BE8 (two's complement)
```
- It is tagged and length-prefixed like hash v2: two checkpoints cannot share one.
- The signer's `key_id` and the hex signature travel beside it; the `key_id` only selects the key.
- **A witness cosignature** is a signature over the same fields under the tag
  `"mela.transparency.cosignature.v1"`. A log signature and a cosignature cannot stand in for each
  other, even from one key.
- Known-answer vectors for the preimage, a log signature and a cosignature are pinned in the suite.
  They were computed independently with Python's `cryptography`.

### The calls

- **Log operator:**
  - `tlog_checkpoint(log, origin, sk, timestamp)` signs the current head. It refuses an empty
    origin and a log whose chain does not verify.
  - `tlog_proof(log, size)` is the consistency proof from a checkpoint of `size` entries: the
    entries after them.
  - `ckpt_merge(dst, src)` gathers the cosignatures witnesses added to copies of one checkpoint,
    so witnesses can cosign in parallel. It refuses a `src` that states anything different, and
    skips a cosignature `dst` already holds.
- **Proof transport:** a proof travels as `tlog_to_json(proof)` and is read back with
  `tlog_proof_from_json`. It decodes as strictly as a log but is not chained from entry 0.
- **Witness:** checks a new checkpoint with `ckpt_advance` against its own last one, then
  `ckpt_cosign(cp, sk)`.
- **Client:**
  - `ckpt_policy_new(origin, log_keyring, witness_keyring, threshold)` is the operator's
    configuration for one log.
  - `ckpt_advance(policy, trusted, incoming, proof, now)` returns 1 when the client may replace
    `trusted` with `incoming`.
  - `incoming` must name the policy's origin and be signed by a log key current at `now`. It must
    carry at least `threshold` cosignatures from distinct witness keys; the log's own key never
    counts.
  - After first contact (`trusted` = 0, trust on first use), `proof` must show `incoming` extends
    `trusted`.
- **Building blocks:**
  - `ckpt_verify(cp, keyring, now)` checks the log signature.
  - `ckpt_witnesses(cp, keyring, now)` counts valid cosignatures.
  - `ckpt_consistent(old, new, proof)` checks the proof. Same origin; `new.size = old.size + |proof|`.
    Each entry self-verifies, has the next sequence number and links to the hash before it, and
    hash versions never go down. The last hash is `new.head`.
- **Whole log:** `tlog_matches_ckpt(log, cp)` checks that a log is exactly what a checkpoint
  describes: its chain verifies, with cp's size and head. A truncated log fails it.
- **Evidence:** `ckpt_equivocates(policy, a, b, now)` returns 1 for two checkpoints the log signed
  with the same size and different heads.
- **Codec:** `ckpt_to_json` / `ckpt_from_json`. Every field is required with its type (ADR-0011).
  The result must be well formed: an origin, `size >= 0`, and a head that is `""` exactly when the
  size is 0 and 64 characters otherwise. Signatures are checked by `ckpt_verify`, not the decoder.

Every key lookup uses the ADR-0017 rule: a key counts only under the `key_id` it derives.

### What it guarantees

- **Truncation and rollback:** refused. A shorter checkpoint fails the size equation. A log with
  its end dropped fails `tlog_matches_ckpt`.
- **A fork after the client's checkpoint:** refused. The proof cannot link the old head to both
  branches, so a client that has seen one branch never accepts the other.
- **A split view between clients:** with `threshold` = k, the log must get k witnesses to cosign
  each branch. Each honest witness cosigns only one branch, since its own state then sits on that
  branch. So when clients share a witness keyring of n keys and k > n/2, the two cosigner sets
  overlap, and a split view needs a witness that cosigned both: a dishonest or stateless one. With
  k = 0, clients only catch it by comparing checkpoints (gossip), and `ckpt_equivocates` turns a
  same-size mismatch into evidence.

### What it does not do

- **No transport.** mela neither serves nor fetches checkpoints, proofs or cosignatures; the
  consumer and the registry choose the endpoints. `remote_client` is unchanged.
- **No freshness bound.** A registry can keep serving an old, valid checkpoint to hide new entries
  (a freeze). A client that cares compares `ckpt_timestamp` with its own clock, against a bound it
  chooses.
- **Proofs are linear.** A hash-chain proof is every entry since the client's checkpoint, not a
  Merkle path. A client that follows the log wants those entries anyway. A light client proving
  one entry without the rest would need a Merkle tree, which is a change to the log's structure.
- **`pipeline_install` does not consult the log.** To require that what is installed is in an
  accepted log, a consumer looks the version up in a log that matches an accepted checkpoint. It
  passes that entry's `content_hash` as `expected_hash` (gate 2).
- **The stored checkpoint is not re-verified.** `trusted` is the client's own state, protected like
  its keyring. Not re-verifying it is what lets the log key rotate: an old checkpoint under a
  retired key still anchors the next proof.

## Consequences

- **Positive**
  - Truncation, rollback and forks are detected against any checkpoint the client kept.
  - Split views are prevented up to the witness threshold.
  - Signed checkpoints turn equivocation into transferable evidence.
  - Additive: no existing function changes behavior, and logs, entries and their JSON are
    unchanged.
- **Negative**
  - Clients and witnesses now own state: the last accepted checkpoint per log, stored and
    protected.
  - Operators own two more key sets (log keys, witness keys) and a threshold.
  - Proof size grows with the gap between checkpoints.
- **Neutral**
  - New public API: 20 functions (`tlog_head`, `tlog_checkpoint`, `tlog_proof`,
    `tlog_proof_from_json`, `tlog_matches_ckpt`, `ckpt_*`).
  - `tlog_from_json` now parses through the shared `_tlog_parse`, with the same behavior.
  - Follow-ups: transport endpoints, a freshness policy, inclusion for light clients, and a
    witness network to run.

## Alternatives considered

- **A Merkle tree (RFC 6962 / 9162).** Logarithmic inclusion and consistency proofs, but it
  replaces the chain's structure and hashing, and every stored log would need migrating. The chain
  head already commits to the prefix. Linear proofs suit a marketplace log at its scale, and a
  client that audits new entries downloads them anyway.
- **Signed checkpoints without witnesses.** Catches truncation and forks for one client over time,
  but not a split view between clients without gossip mela does not have. Witness cosignatures are
  small, so they are included, and the threshold lets an operator start at 0.
- **Gossip in mela.** Comparing checkpoints between clients needs a network protocol and peers.
  `ckpt_equivocates` is the piece that belongs in the library.
- **The C2SP signed-note text format for checkpoints.** That format interoperates with existing
  witnesses, but it is a second text format beside mela's JSON. Its signature preimage is a line
  format, and mela's log entries already use tagged binary preimages. The body here is easy to
  render as a note later if interop is wanted.
- **Re-verifying the stored checkpoint on every advance.** That would brick a client once the log
  key it was signed under expires.
- **Require `incoming.timestamp >= trusted.timestamp`.** It adds a rule without adding safety: size
  and the proof already order checkpoints. A log that signed a future timestamp would also lock
  clients out.
