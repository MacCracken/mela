# Keyring provenance: distributing, rotating and pinning publisher keys

mela installs a bundle only if it is signed by a key in the **keyring**: the set of publisher
keys the device trusts. mela checks signatures against the keyring, but it does not decide what
belongs in it. That is the operator's job: the device owner, the OS image, or a consumer such as
ark. This guide is how to do that job safely.

## What a key is

A trusted key is a `KeyVersion` ([`src/trust.cyr`](../../src/trust.cyr)):

| field | meaning |
|---|---|
| `key_id` | lowercase hex of the first 8 bytes of the public key (16 characters); `trust_key_id_from_pk` derives it |
| `public_key_hex` | the 32-byte Ed25519 public key, 64 hex characters |
| `valid_from` | the key is not trusted before this time (an i64 epoch) |
| `has_until`, `valid_until` | when `has_until` is 1, the key is not trusted after `valid_until` |
| `succeeds` *(optional, v1.5.1)* | `key_id`s this key succeeds; an upgrade published under one of them may move to this key (see *Rotating a key*) |

A **key file** is `<anything>.json` holding a JSON array of these objects. Every field is
required, and `valid_until` is required when `has_until` is 1 (ADR-0011):

```json
[
  {"key_id": "d75a980182b10ab7", "valid_from": 1700000000, "has_until": 0, "valid_until": 0,
   "public_key_hex": "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"}
]
```

`keyring_load_dir(kr, dir)` loads every `*.json` file in `dir`.
- **It replaces the keyring.** A file deleted between loads is a key no longer trusted.
- **A file loads whole or not at all.** One malformed entry skips the whole file, and so does one
  whose `key_id` does not derive from its `public_key_hex` (v1.5.2, ADR-0017).
- **A file over 1 MiB is skipped.**
- **A missing directory gives an empty keyring.** Nothing then installs.

## How install uses it

`pipeline_install(reg, keyring, bundle, sig, sig_len, expected_hash, now)`:
1. reads `manifest.json` from the bundle and takes the publisher's `key_id`;
2. takes the first key filed under that `key_id` that is valid at `now` and whose `key_id`
   derives from it (v1.5.2, ADR-0017);
3. verifies the Ed25519 signature over the whole bundle with that key's `public_key_hex`;
4. for an upgrade, requires that key to continue the installed version's key (v1.5.1,
   ADR-0016). It must be the same `key_id`, a declared successor, or one the operator approved.

**The `key_id` only selects a key; the stored public key decides.** A bundle that names a trusted
`key_id` but is signed by a different key fails. That is why the public key in the keyring is the
thing to protect, not the `key_id` or the publisher's name. Since v1.5.2 a keyring entry cannot
file one key under another key's `key_id`: the loader skips such a file, and the gate passes over
such an entry in a keyring built in memory.

## Distributing the keyring

- **Never fetch the keyring from the registry that serves the bundles.** Whoever can change both
  can sign anything. The keyring is configuration, delivered the way the OS itself is: in the
  image, or by the device owner.
- **Keep the directory privileged.**
  - Own it and its files by root (or by the installer's service account).
  - Make the directory 0755 and the files 0644.
  - Make sure nothing that installed apps run as can write there.
- **Load it once per run**, at start-up, with `keyring_load_dir`. Reload only on an explicit
  administrative action, not on a signal from the network.
- **Pass `now` from the device's own clock**, never from a registry response. The validity window
  is only as good as the clock that is compared with it. Use epoch **seconds**: mela's tests and
  examples do, and `valid_from` / `valid_until` must use the same unit as `now` (ADR-0003 leaves
  the unit to the caller).

## Admitting a publisher

1. **Get the full public key out of band.** Use a channel the registry does not control: the
   publisher's own site over HTTPS, a signed release note, or in person. A `key_id` alone is not
   enough: it is 64 bits, and only the full key is what verification uses.
2. **Check the `key_id` derives from the key** before you install the file. Since v1.5.2 the
   loader enforces it and skips a mismatched file whole; checking first tells you why a key is
   missing. A mismatched entry files someone's key under someone else's `key_id`:

   ```cyrius
   if (kv_key_id_derives(kv) == 0) { /* reject the file: not 32 bytes of hex, or another key's id */ }
   ```

3. **Write one file per publisher** (for example `acme.json`), so revoking a publisher is
   deleting one file.

## Rotating a key

A new keypair has a new `key_id`, so rotation is two entries, not an edit of one:
1. Add the new key with `valid_from` = the switch-over time T, and **`"succeeds": ["<old
   key_id>"]`**. Without it, every installed package of that publisher refuses its next upgrade,
   because mela keeps an upgrade on the installed key (ADR-0016).
2. Give the old key `has_until: 1` and a `valid_until` after T. Leave an overlap long enough for
   the publisher to re-sign what is still being installed.
3. The publisher's new manifests carry the new `key_id`.

```json
[
  {"key_id": "3d4017c3e843895a", "valid_from": 1800000000, "has_until": 0, "valid_until": 0,
   "public_key_hex": "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
   "succeeds": ["d75a980182b10ab7"]}
]
```

Succession is transitive: a key that succeeds B also continues packages installed under A if B
succeeds A. Declare it only for the same publisher's keys. It lets the new key take over every
package installed under the old one.

⚠ **Expiry stops installs of everything the old key signed.** mela checks the key against `now`,
the time of install, not the time of signing. After `valid_until`, a bundle signed only with the
old key no longer installs, however old it is. So either re-sign the catalogue with the new key
before the old one expires, or leave the old key without an expiry and only remove it when it
must stop being trusted.

## Revoking a key (compromise)

- **Delete the key's file, or its entry, and reload.** Because `keyring_load_dir` replaces the
  keyring, the key is untrusted from that load on. Setting `valid_until` in the past does the same.
- **Then find what it signed.** Every transparency-log entry records the `publisher_key_id` it
  was published under:

  ```cyrius
  var i = 0;
  while (i < tlog_len(log)) {
      var e = vec_get(log, i);
      if (str_eq(log_key_id(e), compromised_key_id) == 1) { /* log_package(e), log_version(e) */ }
      i = i + 1;
  }
  ```

  Installed packages record it too:
  `pub_key_id(man_publisher(imp_manifest(registry_get_package(reg, name))))`.

## Key continuity, and what a consumer (ark) should add

**mela pins each installed package to the key it was installed under (v1.5.1, ADR-0016).** An
upgrade published under any other key is refused, even a trusted one, unless:
- the keyring declares the new key a successor (`succeeds`, above); or
- the operator approved this one change with
  `registry_allow_key_change(reg, name, new_key_id)`.

An approval:
- is held in memory only;
- covers the next install of that package under that key, and is used up by it;
- stays pending if that install fails.

Uninstalling and reinstalling also resets the pin, but it removes the installed files.

A consumer that installs on a user's behalf can ask first, to know when to prompt:

```cyrius
var incoming = pipeline_extract_manifest(bundle);       # pre-signature: for the prompt only
if (registry_key_continuous(reg, keyring, incoming) == 0) {
    # a key change: show the old and new publisher keys; on the user's yes:
    registry_allow_key_change(reg, man_name(incoming), pub_key_id(man_publisher(incoming)));
}
var res = pipeline_install(reg, keyring, bundle, sig, 64, expected_hash, now);   # checks it all again
```

An approval never lets an untrusted key in: gate 1 still requires the new key in the keyring.

Beyond continuity, a consumer can pin further:

- **Pin names to publishers** if the catalogue has namespaces: for example, accept `acme-*` only
  from Acme's `key_id`. mela's qualified names (`publisher/name`) come from the manifest, which the
  publisher writes, so the binding has to come from the consumer's own table.
- **Pin the expected digest.** Pass `expected_hash` (gate 2) from a source other than the bundle
  server where you have one: a signed catalogue, or the transparency log's `content_hash` for that
  version, from a log that matches a checkpoint you accepted
  ([`transparency-checkpoints.md`](transparency-checkpoints.md)).

## See also

- [ADR-0003](../adr/0003-trust-time-and-deferred-keyring-load.md): time and the keyring loader.
- [ADR-0011](../adr/0011-fail-closed-decoding-at-the-trust-boundary.md): strict key files, and
  reloading as revocation.
- [ADR-0017](../adr/0017-key-id-must-derive-from-the-key.md): a key counts only under the
  `key_id` it derives.
- [`transparency-checkpoints.md`](transparency-checkpoints.md): log and witness keys, which are
  key files like these.
- [`../development/threat-model.md`](../development/threat-model.md): where the keyring sits among
  the trust boundaries.
