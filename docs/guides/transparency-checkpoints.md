# Transparency checkpoints: signing, witnessing and following the log

mela's transparency log is a hash chain of publications. On its own, the chain shows whether
an entry was edited. Since v1.5.2 ([ADR-0018](../adr/0018-transparency-checkpoints-witnesses-and-consistency.md))
it can also show three more things:
- whether entries were **dropped from its end**;
- whether the log **forked** after a point a client already saw;
- whether a registry showed **two clients two different logs**.

This guide covers the three roles: the log operator, a witness and a client. mela provides the
checks and the formats; carrying the JSON between the roles is the consumer's transport.

## The pieces

- **Checkpoint:** the log's signed statement "log *origin* has *size* entries, the last hashing to
  *head*", made at *timestamp*. JSON from `ckpt_to_json`, read back with `ckpt_from_json`.
- **Consistency proof:** the entries added since a checkpoint. `tlog_proof(log, size)` makes one;
  it travels as `tlog_to_json(proof)` and is read back with `tlog_proof_from_json`.
- **Cosignature:** a witness's signature on a checkpoint it checked against the last one it saw.
  It travels inside the checkpoint's JSON.
- **Policy:** a client's configuration for one log: `ckpt_policy_new(origin, log_keys,
  witness_keys, threshold)`.

## Keys

The log key and each witness key are ordinary Ed25519 keys in ordinary key files
([`keyring-provenance.md`](keyring-provenance.md)). Distribute and protect them the same way:
- out of band, never from the registry whose log they vouch for;
- in their own directories, loaded with `keyring_load_dir`. Since v1.5.2 a file whose `key_id`
  does not derive from its key is skipped.

```cyrius
var log_keys = mela_keyring_new();
keyring_load_dir(log_keys, str_from("/etc/mela/log-keys"));
var witness_keys = mela_keyring_new();
keyring_load_dir(witness_keys, str_from("/etc/mela/witness-keys"));
```

**Keep the three key sets apart.** A log key never counts as a witness for its own log, even if
it is in the witness keyring, but separate directories keep the roles clear.

## Log operator

Append, sign a checkpoint, and answer two questions: "what is your checkpoint?" and "what changed
since size *n*?".

```cyrius
var ORIGIN = str_from("market.example.org/log");
var e = pipeline_publish(log, bundle, publisher_sk, &sig, now);    # appends an entry
var cp = tlog_checkpoint(log, ORIGIN, log_sk, now);                 # 0 if the chain is broken

# a client or witness that last saw n entries:
var proof = tlog_proof(log, n);              # 0 if n is negative or past the end: answer an error
var proof_json = tlog_to_json(proof);
```

**Collecting cosignatures.** Send each witness the checkpoint and the proof from that witness's
last size. Each returns the checkpoint with its cosignature added. Merge the copies into the one
you serve:

```cyrius
var copy = ckpt_from_json(witness_reply);
if (copy != 0) { ckpt_merge(cp, copy); }     # 0 if the copy states a different checkpoint
var cp_json = ckpt_to_json(cp);
```

`ckpt_merge` copies cosignatures without checking them. Clients check them with
`ckpt_witnesses`.

**Origin.** Pick one stable origin per log and never reuse it for another log. Give each log its
own key.

## Witness

A witness keeps the last checkpoint it accepted for each origin. It cosigns a new one only if the
proof shows the new one extends it:

```cyrius
var pol = ckpt_policy_new(ORIGIN, log_keys, 0, 0);    # a witness needs no other witnesses
var incoming = ckpt_from_json(cp_json);
var proof = tlog_proof_from_json(proof_json);
if (incoming != 0) {
    if (ckpt_advance(pol, trusted, incoming, proof, now) == 1) {
        save_state(ORIGIN, ckpt_to_json(incoming));    # first the state...
        ckpt_cosign(incoming, witness_sk);             # ...then the cosignature
        reply(ckpt_to_json(incoming));
    }
}
```

- **Save the new state before you release the cosignature.** A witness that cosigns and then loses
  its state could cosign a fork next. That is the one thing a witness must never do.
- **Never fall back to first contact.** If the saved state does not decode, stop and investigate.
  Do not treat it as `trusted = 0`.

## Client

```cyrius
var pol = ckpt_policy_new(ORIGIN, log_keys, witness_keys, 2);
var trusted = 0;
var saved = load_state(ORIGIN);                # "" only if this device never accepted one
if (str_len(saved) != 0) {
    trusted = ckpt_from_json(saved);
    if (trusted == 0) { /* corrupt state: stop, do NOT start over at first contact */ }
}
# ask the registry for its checkpoint, and the proof from ckpt_size(trusted) (0 on first contact)
var incoming = ckpt_from_json(cp_json);
var proof = tlog_proof_from_json(proof_json);
if (incoming != 0) {
    if (ckpt_advance(pol, trusted, incoming, proof, now) == 1) {
        save_state(ORIGIN, ckpt_to_json(incoming));
    } else {
        if (trusted != 0) {
            if (ckpt_equivocates(pol, trusted, incoming, now) == 1) {
                # two signed heads for one size: keep both checkpoints, they prove the fork
            }
        }
    }
}
```

`ckpt_advance` refuses:
- a checkpoint for another origin, or one not signed by a current log key;
- one with fewer than the threshold's cosignatures from distinct trusted witnesses;
- one that is shorter than `trusted`, or has the same size and a different head;
- one the proof does not link to `trusted`.

On a refusal, keep `trusted`.

**First contact is trust on first use.** With `trusted` = 0, only the signature and the witness
threshold are checked. A client that wants more on its first run fetches the whole log and checks
`tlog_matches_ckpt(log, incoming)`.

**Freshness is yours.** A registry can keep serving an old, valid checkpoint to hide what came
after it. Compare it with the device clock:

```cyrius
if (now - ckpt_timestamp(trusted) > MAX_VIEW_AGE) { /* stale view: warn, or hold installs */ }
```

### Choosing the threshold

The threshold is the number of distinct witnesses from `witness_keys` that must have cosigned.

| threshold | what a split view needs |
|---|---|
| 0 | nothing: clients only see it by comparing checkpoints |
| k ≤ n/2 | the log shows each branch to a different half of the witnesses |
| k > n/2 | at least one witness that cosigned both branches: dishonest, or lost its state |
| n | every witness to cosign both; but one witness offline stops every update |

Here n is the number of witness keys the clients share. A common choice is a majority, for
example 2 of 3.

## Binding installs to the log

`pipeline_install` does not read the log. To install only what the accepted log records, take
gate 2's expected digest from the log:

```cyrius
var log = tlog_from_json(log_json);                          # 0 if the chain is broken
if (tlog_matches_ckpt(log, trusted) == 0) { /* not the log you accepted: refuse */ }
var e = tlog_find(log, str_from("acme/scanner"), str_from("2.1.0"));   # publisher/name, as logged
if (e == 0) { /* not in the log: refuse */ }
var res = pipeline_install(reg, keyring, bundle, sig, 64, log_content_hash(e), now);
```

- `pipeline_publish` logs the bundle's SHA-256 as `content_hash`, the same digest gate 2
  compares.
- **Check for a second entry.** Use `tlog_entries_for_package` to look for another entry for the
  same version. Two logged digests for one version deserve a refusal and a report.

## When the log equivocates

Two checkpoints signed by the log with the same origin and size but different heads
(`ckpt_equivocates`) are proof that it forked. Keep both, as JSON, and send them to:
- the witnesses;
- the log's operator;
- whoever distributes the log key.

Revoking the log key is a keyring change like any other. For two checkpoints of different sizes,
ask the log for the proof between them. If it cannot produce one, it forked.

## See also

- [ADR-0018](../adr/0018-transparency-checkpoints-witnesses-and-consistency.md): the formats and
  the rules, and what they do not cover.
- [ADR-0015](../adr/0015-confined-extraction-and-transparency-hash-v2.md): the entry hash (v2).
- [`../development/threat-model.md`](../development/threat-model.md): where the log sits among the
  trust boundaries.
