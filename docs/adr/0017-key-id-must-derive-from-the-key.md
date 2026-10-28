# 0017 — A key counts only under the key_id its public key derives

**Status**: Accepted
**Date**: 2026-10-28 (v1.5.2)

## Context

**A `key_id` names a key; the stored public key is what verifies.** A bundle's manifest names its
publisher's `key_id`. Gate 1 looks that id up in the keyring and verifies the signature with the
public key stored under it. `trust_key_id_from_pk` defines the id as the lowercase hex of the
public key's first 8 bytes, but nothing checked that a keyring entry's id was the one its key
derives.

**A mismatched entry lets one publisher sign as another.** An entry with A's `key_id` and B's public
key makes every bundle B signs and labels with A's id pass gate 1 as A's. Since v1.5.1 that matters
more: key continuity (ADR-0016) pins installed packages to `key_id`s, so such an entry would also let
B upgrade A's packages. Rust had the same gap.

The keyring is the operator's (keyring provenance guide). The guide told operators to run the check
themselves before admitting a key. The v1.4.0 threat model listed it under *Known gaps*, and the
roadmap proposed checking it on load.

## Decision

**A keyring entry is used only if its `key_id` is the one its public key derives.** The new
predicate `kv_key_id_derives(kv)` returns 1 when `public_key_hex` decodes to 32 bytes and
`trust_key_id_from_pk` of them equals `key_id` exactly. A key_id in uppercase hex does not match;
uppercase `public_key_hex` decodes to the same key and is fine.

The check runs in three places:
1. **`keyring_load_dir`:** a key file with any entry that fails the check is skipped whole, as a
   malformed one is (ADR-0011). The other files still load.
2. **Gate 1 (`registry_verify_package`, and so `pipeline_install`):** the signature is verified
   with the first version of the `key_id` that is valid at `now` *and* derives. A version that does
   not derive is passed over, however the keyring was built (`mela_keyring_add_key` included). The
   new internal lookup is `_keyring_trusted_key`; checkpoint and witness signatures (ADR-0018) use
   it too.
3. **Succession (ADR-0016):** a `succeeds` declaration counts only from a version that derives.

### What does not change

- **`kv_from_json` / `kv_from_jv`** stay format decoders. Strictness about the key's meaning lives
  in the loader and the gates, so a codec round-trip of a test key still works.
- **`mela_keyring_add_key` and `keyring_get_current_key`** keep their Rust shape. A keyring built in
  memory may hold anything, but no gate uses an entry that does not derive.

## Consequences

- **Positive**
  - A keyring entry cannot make one key sign under another's `key_id`, at install or through
    succession.
  - The operator's check in the guide is now mela's. The guide keeps it as a pre-flight test.
- **Negative**
  - **Behavior change:** `keyring_load_dir` now skips a key file it used to load. Such a file only
    ever worked as a forgery or a mistake: a bundle naming that `key_id` and verifying under that
    key had to be signed by a key whose id is something else.
  - A key file with an uppercase `key_id` is now skipped. Manifests carry the lowercase id
    (`trust_key_id_from_pk`), so such an entry never matched a manifest anyway.
  - Gate 1 now passes over a non-deriving version where it used to try it.
- **Neutral**
  - New public API: `kv_key_id_derives`.
  - The `keyring-load` test fixtures moved from made-up ids over an all-zero key to real derived
    keys (RFC 8032 test keys 2 and 3). Every assertion keeps its meaning.

## Alternatives considered

- **Check only on load.** A keyring built in memory, by a consumer reading its own config, would
  still reach gate 1 unchecked. The gate is the choke point, so the check belongs there too.
- **Refuse the entry in `mela_keyring_add_key`.** That catches every path, but changes a
  Rust-shaped function that many keyring-mechanics tests use with made-up ids, and it returns no
  error today. Passing over the entry at the gate is equivalent for trust.
- **Refuse it in `kv_from_jv`.** That would make the codec carry a trust rule, and only cover what
  comes from JSON.
- **Drop the `key_id` and look keys up by the whole public key.** That changes the manifest format
  and the log entry. The 8-byte id is fine once it is bound to its key.
