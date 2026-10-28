# 0016 — Publisher key continuity on upgrade

**Status**: Accepted
**Date**: 2026-10-28 (v1.5.1)

## Context

**Any trusted key could upgrade any package.** mela binds trust to keys, not names: a bundle
installs if the publisher `key_id` in its manifest has a current key in the keyring and that key
verified the signature (gate 1). Nothing compared that key with the one the installed version was
published under. Any key in the keyring could therefore replace any installed package, including
another publisher's. Rust had the same behavior.

The v1.4.0 threat model listed this under *Known gaps*, and the keyring provenance guide told
consumers to check it themselves. A `keyring-provenance` test pinned the behavior.

**A plain "same key only" rule would break key rotation.** A new keypair has a new `key_id`, so
every upgrade after a rotation would be refused. Some changes are legitimate too, such as a
package moving to a new publisher. The maintainer chose the override mechanism on 2026-10-28:
keyring-declared succession plus a one-shot operator approval.

## Decision

**An upgrade must be published under the installed version's key, a key the keyring declares as
its successor, or a key the operator approved for that one install.** `pipeline_install` checks
this after both trust gates and before anything is written. A refused upgrade returns 0, and the
installed version, its files and its record are untouched.

### What is allowed

`registry_key_continuous(reg, keyring, manifest)` returns 1 when any of these holds:
1. **No installed version** of `man_name(manifest)`: a fresh install pins its key (trust on first
   use). A record made by `registry_install` directly pins its `key_id` the same way.
2. **The same `key_id`.**
3. **Succession:** the incoming key's KeyVersions in the keyring list the installed `key_id` in
   `succeeds`, directly or through a chain (C succeeds B, B succeeds A). Every version of a key
   counts, whatever its validity window, because a declaration is a statement about identity;
   gate 1 has already required the incoming key to be current. Chains are followed with a visited
   set, so a cycle ends.
4. **Approval:** `registry_allow_key_change(reg, name, key_id)` recorded approval of exactly this
   package and this incoming `key_id`.

Otherwise it returns 0. A recorded `key_id` is never empty, since `manifest_validate` requires
one. A hand-edited empty one matches no incoming key, so it fails closed. Consumers can call it before `pipeline_install` (with
`pipeline_extract_manifest(bundle)`) to decide whether to ask the operator.

### The two overrides

- **`succeeds`** is a new optional field of a key-file entry: an array of `key_id` strings.
  Absent means none. Present, it must be an array of strings, or the whole file is refused
  (ADR-0011). `kv_to_json` writes it only when it is non-empty, so existing key files re-export
  unchanged. This is how a publisher's rotation is declared, in the same file and by the same
  operator who admits the new key. `kv_succeeds(kv)` and `kv_add_succeeds(kv, key_id)` read and
  extend it.
- **`registry_allow_key_change(reg, name, key_id)`** approves one install of `name` under
  `key_id`:
  - It lives in the registry object in memory and is not saved: it is an operator decision made
    for an install about to happen.
  - A later call for the same name replaces it.
  - The install it allows uses it up. A failed install, or one that did not need it, leaves it
    pending.

**Uninstall then reinstall** also resets the pin, as a fresh install. It removes the installed
files, so it is not the way to move a package between keys.

### What does not change

- **`registry_install`** stays the low-level call that records an already-verified package. It
  takes no keyring and checks no signature, so it does not check continuity either. Its callers
  own both.
- **`registry_admits`** is unchanged.
- **Gate 1:** the incoming key must still have a current key in the keyring and verify the
  signature. Succession or approval never lets an untrusted key in.

## Consequences

- **Positive**
  - A trusted publisher can no longer replace another publisher's package.
  - Key rotation keeps working once the operator declares it.
  - Consumers no longer need their own continuity check; the guide's snippet is replaced by the
    built-in rule.
- **Negative**
  - Behavior change for callers: `pipeline_install` returns 0 for an upgrade under a different,
    undeclared, unapproved key, which it used to install. A rotation that the keyring does not
    declare now blocks upgrades until the operator adds `succeeds` or approves each package.
  - The keyring format grows an optional field. Releases before 1.5.1 ignore it and stay
    permissive.
- **Neutral**
  - New public API: `registry_key_continuous`, `registry_allow_key_change`, `kv_succeeds`,
    `kv_add_succeeds`. The registry and KeyVersion structs each grow one slot (internal layout).
  - Approvals are not persisted. A consumer that needs an approval to outlive a process keeps it
    itself and calls `registry_allow_key_change` again.

## Alternatives considered

- **Same key only, with uninstall + reinstall as the override.** Every rotation would become a
  reinstall of every package, losing the install directory each time.
- **Succession only.** No way to move a single package to a new publisher short of reinstalling.
- **One-shot approval only.** Every rotation would need one approval per installed package.
- **A signed handover:** the old key signs "my successor is K2", as in TUF. It needs no operator
  step, but it needs a statement format and a way to distribute it, and a compromised old key
  could hand a package to an attacker. The keyring is already the operator's trust root, so a
  declaration there costs nothing new.
- **Persisting approvals in `index.json`.** A stale approval would then outlive the decision it
  recorded.
- **Enforcing in `registry_admits` / `registry_install`.** They have no keyring or signature, so
  succession could not be checked there, and the unsigned path would gain half a rule.
