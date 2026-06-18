# Example — publish and install, end to end

Walks the full marketplace flow with both trust gates enforced. The runnable
version of this is the `pipeline` group in [`tests/mela.tcyr`](../../tests/mela.tcyr);
signatures are in [`../api/`](../api/).

```cyrius
# 1. Publisher keypair (sk = 64-byte seed‖pk, pk = 32 bytes) + a trusted keyring.
var sk[64];
var pk[32];
var key_id = trust_keypair_from_seed(seed32, &sk, &pk);   # or trust_generate_keypair(&sk, &pk)
var keyring = keyring_new();
keyring_add_key(keyring, kv_new(key_id, valid_from, 0, 0, trust_hex_encode(&pk, 32)));

# 2. Build a signed manifest (publisher.key_id = the signing key_id) + sandbox profile,
#    then package them into a gzipped-ustar .agnos-agent bundle.
var manifest = manifest_new(agent, publisher_new(name, key_id, homepage),
                            CAT_DESKTOP_APP, version);
var sandbox  = generate_sandbox_profile(config);
var bundle   = pipeline_package(manifest, sandbox);        # bytes (Str)

# 3. Publish: sign the bundle + append a transparency-log entry.
var tlog = tlog_new();
var sig[64];
var entry = pipeline_publish(tlog, bundle, &sk, &sig, now);
# tlog_verify_chain(tlog) == 1; log_content_hash(entry) is the expected digest.

# 4. Distribute (here: in-process; live transport is a deferred seam, ADR-0006).

# 5. Install — BOTH gates enforced. Returns 0 (installs nothing) on any failure:
#    bad signature (gate 1), digest mismatch (gate 2), untrusted publisher, or invalid manifest.
var reg = registry_in_memory();                            # or registry_new(root_dir)
var result = pipeline_install(reg, keyring, bundle, &sig, 64, log_content_hash(entry), now);
# result != 0  -> installed; registry_get_package(reg, name) is now present.
```

## What gets rejected

| Attempt | Result |
|---|---|
| Tampered bundle (signature was over the original) | `pipeline_install` → `0` (gate 1) |
| Wrong / mismatched SHA-256 digest | `0` (gate 2) |
| Unsigned / publisher key not in the keyring | `0` (gate 1) |
| Symlink / `..`-traversal tar entry | skipped by the reader (v0.9.0 hardening) |
| Manifest with an invalid name/version | `0` (validation) |

See [`../development/threat-model.md`](../development/threat-model.md) for the full control map.
