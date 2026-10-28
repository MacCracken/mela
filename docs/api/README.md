# mela — public API reference

> **Frozen at v0.9.1.** This is the v1.0-bound public surface that downstream
> consumers (e.g. [`ark`](https://github.com/MacCracken/ark)) build against.
> Additive changes are allowed before v1.0; **signature/semantic changes to a
> listed function require an ADR**. Functions prefixed `_` are internal and may
> change without notice — do not call them.
>
> **Checked since v1.5.0:** [`../api-surface.snapshot`](../api-surface.snapshot) lists every
> public fn as `module::name/arity` (`cyrius api-surface --scope=project`). CI fails when a fn
> is removed or its arity changes, and when the snapshot does not match the source exactly, so
> additions are recorded too. The snapshot is the complete list; this page explains it and does
> not list every accessor.

## Conventions

- **Strings** are the stdlib `Str` fat pointer (`{data; len}`). Build one with
  `str_from("…")`; compare with `str_eq` / `str_eq_cstr`.
- **Error / absence is the integer `0`.** Constructors return a heap pointer (non-zero);
  parse/lookup functions return `0` on failure or "not found". There are no exceptions or
  panics — every path returns a value. Boolean-ish results are `1` (true) / `0` (false).
- **Time** is an `i64` epoch supplied by the caller (no wall-clock reads inside the library;
  ADR-0003/0004). The unit is a caller convention (seconds recommended).
- **Wire format** is JSON (ADR-0001): category & enum values serialize as their PascalCase
  serde variant name; `*_to_json` / `*_from_json` round-trip; `from_json` returns `0` on a
  parse error.
- **Decoding is strict (v1.1.5, ADR-0013).** Every `*_from_json` / `*_from_jv` follows Rust's
  serde rules: a required field missing or of the wrong type, an optional field present with the
  wrong type, a negative value in an unsigned field, or an unknown enum name returns `0`. Absent
  optional fields take their default. Timestamps are integers in every mela format. The
  per-decoder field table is in ADR-0013.
- **Text is Unicode-aware (v1.1.5, ADR-0013):** case-insensitive comparisons lowercase with
  Unicode simple case mapping; `sanitize_filename` keeps letters and digits in any script.
- **Field accessors** follow `<type>_<field>(ptr)` and are not all listed individually below;
  the constructor's field order is the struct layout. Setters are `<type>_set_<field>`.
- **Namespacing (v0.9.3):** 15 public symbols that collided with co-bundled deps (nous, sigil) are
  **`mela_`-prefixed**: `mela_registry_new`, `mela_registry_search`, `mela_manifest_new`,
  `mela_manifest_to_json`, `mela_update_to_json`, `mela_keyring_new`, `mela_keyring_add_key`,
  `mela_keyring_get_all_versions`, `mela_keyring_is_empty`, `mela_keyring_len`, `mela_kv_key_id`,
  `mela_kv_valid_from`, `mela_kv_valid_until`, `mela_kv_public_key_hex`, `mela_kv_is_valid_at`.
  Everything else keeps its bare name (e.g. `kv_new`, `keyring_get_current_key`, `manifest_from_json`).

Public modules (all under `src/`, wired by `src/main.cyr`):
`category`, `manifest`, `depgraph`, `trust`, `transparency`, `local_registry`,
`remote_client`, `sandbox_profiles`, `ratings`, `flutter_packaging`, `flutter_agpkg`,
`pipeline`.

---

## category — `src/category.cyr`

- Constants: `CAT_UTILITY` `CAT_PRODUCTIVITY` `CAT_SECURITY` `CAT_DEVTOOL` `CAT_DESKTOP_APP`
  `CAT_SYSTEM`; `CAT_COUNT`; `CAT_PARSE_FAIL` (sentinel).
- `cat_name(cat): cstring` — canonical lowercase display name (`Display`).
- `cat_parse(s): i64` — case-insensitive `FromStr` (+ `dev-tool`/`desktopapp` aliases), or
  `CAT_PARSE_FAIL` (also for input over 63 bytes).

## manifest — `src/manifest.cyr`

- `is_valid_semver(v: Str): i64` — `major.minor.patch` (+ optional `-prerelease`).
- `publisher_new(name, key_id, homepage: Str): PublisherInfo*` — `pub_name` / `pub_key_id` /
  `pub_homepage`.
- `mela_manifest_new(agent, publisher, category, version: Str): MarketplaceManifest*` — `agent` is an
  agnostik `AgentManifest`; accessors `man_name` / `man_version` / `man_description` /
  `man_publisher` / `man_category` / `man_runtime` / `man_screenshots` / `man_changelog` /
  `man_min_agnos_version` / `man_dependencies` / `man_tags`; setters for the optional fields.
- `manifest_validate(m): Vec<Str>` — list of error messages; empty Vec ⇒ valid.
- `manifest_qualified_name(m): Str` — `publisher/agent-name` (publisher Unicode-lowercased,
  spaces→`-`).
- Codec: `mela_manifest_to_json(m): Str` / `manifest_from_json(Str): m|0` (0 for an unknown,
  missing or non-string `category`, v1.1.3, ADR-0012);
  `manifest_to_jv` / `manifest_from_jv` (json-value tree, for nesting);
  `publisher_to_json` / `publisher_from_json`; `cat_json_name(cat): Str` /
  `cat_json_parse(Str): cat` (PascalCase wire form).

## depgraph — `src/depgraph.cyr`

- `depnode_new(name, version: Str, deps: Vec<Str>): DepNode*` — `depnode_name` / `_version` / `_deps`.
- `depgraph_new(): graph`; `depgraph_add(g, node)`; `depgraph_len` / `depgraph_is_empty` /
  `depgraph_contains(g, name)` / `depgraph_get(g, name)`.
- `depgraph_check_missing(g): Vec<pair>` — `(owner, missing-dep)` pairs (`dep_pair_a` / `dep_pair_b`).
- `depgraph_detect_cycle(g): path|0` — cycle path Vec, or `0` if acyclic.
- `depgraph_resolve(g): order|0` — topological install order (Vec<Str>), or `0` on a cycle.

## trust — `src/trust.cyr`

- `trust_hash_data(data, len): Str` — SHA-256 hex.
- `trust_hex_encode(data, len): Str` / `trust_hex_decode(Str): buf|0`.
- `trust_sign(sk, data, len): sig` — 64-byte Ed25519 signature (sk is 64 bytes: seed‖pk).
- `trust_verify(data, len, sig, sig_len, pk): i64` — `1` iff `sig` is exactly 64 bytes and
  verifies over `data` against the 32-byte `pk` (RFC 8032 §5.1.7 non-malleable, via sigil).
- `trust_keypair_from_seed(seed, sk_out[64], pk_out[32]): key_id` (deterministic);
  `trust_generate_keypair(sk_out, pk_out): key_id` (CSPRNG); `trust_key_id_from_pk(pk): Str`
  (hex of first 8 bytes).
- `kv_new(key_id, valid_from, has_until, valid_until, public_key_hex): KeyVersion*`;
  `mela_kv_is_valid_at(kv, when): i64`; `kv_verifying_key(kv): pk|0` (hex→32 bytes, validated).
- `mela_keyring_new()`; `mela_keyring_add_key(kr, kv)`; `keyring_get_current_key(kr, key_id, now): kv|0`;
  `mela_keyring_get_all_versions` / `mela_keyring_len` / `mela_keyring_is_empty`.
- `keyring_load_dir(kr, dir: Str): count` — **replace** the keyring's contents with every
  `*.json` key file in `dir` (each a JSON array of `KeyVersion`); a file with one malformed
  version is skipped whole, non-json files are ignored, an absent dir empties the keyring and
  returns 0 (parity with rust-old `PublisherKeyring::load`; v1.1.1, ADR-0011). `KeyVersion` JSON
  codec: `kv_to_json(kv): Str` / `kv_from_json(json: Str): kv|0` — every field `kv_to_json`
  writes is required (`has_until` 0/1; `valid_until` when it is 1); nothing defaults.
- *v1.5.1 (ADR-0016):* a `KeyVersion` may carry `succeeds`, the `key_id`s it succeeds:
  `kv_succeeds(kv): Vec<Str>` and `kv_add_succeeds(kv, key_id)`. In a key file it is optional
  (absent, or an array of strings, or the file is refused), and `kv_to_json` writes it only when
  it is non-empty.
- *v1.5.2 (ADR-0017):* `kv_key_id_derives(kv): i64` — `1` iff `public_key_hex` is 32 bytes of hex
  and its `trust_key_id_from_pk` is exactly `key_id` (lowercase). `keyring_load_dir` skips a file
  with any entry that fails it. `kv_from_json`, `mela_keyring_add_key` and
  `keyring_get_current_key` do not check it, but no gate uses an entry that fails it.

## transparency — `src/transparency.cyr`

- `tlog_new(): log`.
- `tlog_append(log, package, version, key_id, content_hash, signature_hash: Str, timestamp): LogEntry*`
  — chains `previous_hash`, stamps `sequence`, computes `entry_hash`.
- `tlog_verify_chain(log): i64` — `1` iff every entry self-verifies, links, and is correctly
  sequenced.
- `tlog_find(log, package, version): entry|0`; `tlog_entries_for_package(log, package): Vec`;
  `tlog_latest(log): entry|0`; `tlog_len` / `tlog_is_empty`.
- `log_entry_compute_hash(e): Str`; `log_entry_verify_self(e): i64`; entry accessors `log_seq` /
  `log_timestamp` / `log_package` / `log_version` / `log_key_id` / `log_content_hash` /
  `log_signature_hash` / `log_previous_hash` / `log_entry_hash`.
- Codec: `tlog_to_json(log): Str` / `tlog_from_json(Str): log|0` (re-verifies the chain on import).
- *v1.4.0 (ADR-0015):* each entry has a hash version. `log_hash_version(e)` and
  `log_set_hash_version(e, v): 0|-1` (unknown versions refused) are added, with the constants
  `LOG_HASH_V1` / `LOG_HASH_V2`.
  - `tlog_append` and `log_entry_new` make v2 entries: a tagged, length-prefixed preimage.
  - `log_entry_compute_hash` uses the entry's own version.
  - `tlog_to_json` writes `"hash_version": 2` on v2 entries and nothing on v1 ones.
  - `tlog_from_json` reads a missing field as 1, and refuses any value other than the integers 1
    and 2.
  - `tlog_verify_chain` also refuses a version lower than the entry before it.
  - Logs written before v1.4.0 import and verify unchanged. A log with v2 entries does not import
    into earlier releases.
- *v1.5.2 (ADR-0018):* checkpoints, witnesses and consistency proofs. Guide:
  [`../guides/transparency-checkpoints.md`](../guides/transparency-checkpoints.md).
  - `tlog_head(log): Str` — the last entry's hash, `""` if empty.
  - `tlog_checkpoint(log, origin: Str, sk, timestamp): ckpt|0` — the log's signed checkpoint
    (`sk` = seed‖pk); 0 for an empty origin or a chain that does not verify. Accessors
    `ckpt_origin` / `ckpt_size` / `ckpt_head` / `ckpt_timestamp` / `ckpt_key_id`.
  - `tlog_proof(log, size): Vec|0` — the entries after the first `size` (0 if `size` is negative
    or past the end). It travels as `tlog_to_json(proof)` and is read back with
    `tlog_proof_from_json(Str): Vec|0` (strict entries, not chained from 0).
  - `ckpt_cosign(cp, sk): 0` — add a witness cosignature. `ckpt_merge(dst, src): i64` — add
    `src`'s cosignatures to `dst` if both state the same checkpoint (`0` otherwise).
  - `ckpt_verify(cp, keyring, now): i64` — well formed and signed by a current log key.
    `ckpt_witnesses(cp, keyring, now): i64` — distinct witness keys with a valid cosignature (the
    log's own key never counts).
  - `ckpt_consistent(old, new, proof): i64` — `proof` links `old.head` to `new.head`: same origin,
    sizes add up, every entry self-verifies, is in sequence and links, hash versions never go
    down. A proof of 0 counts as empty. Signatures are not checked.
  - `tlog_matches_ckpt(log, cp): i64` — the log's chain verifies, with cp's size and head.
  - `ckpt_policy_new(origin, log_keyring, witness_keyring, threshold): policy`;
    `ckpt_advance(policy, trusted, incoming, proof, now): i64` — the client's rule (`trusted` = 0
    on first contact); `ckpt_equivocates(policy, a, b, now): i64` — two signed heads of one size.
  - Codec: `ckpt_to_json(cp): Str` / `ckpt_from_json(Str): ckpt|0` — every field required,
    well formed; signatures not checked.

## local_registry — `src/local_registry.cyr`

- *v1.5.1 (ADR-0016):* `registry_key_continuous(reg, keyring, manifest): i64` — `1` if the
  manifest may be installed as far as key continuity goes (no installed version, the same
  `key_id`, a declared successor, or an approval), else `0`. `registry_allow_key_change(reg, name,
  key_id): 0` approves the next install of `name` under `key_id`; it is held in memory and used up
  by that install. `registry_install` does not check continuity.
- `mela_registry_new(root_dir: Str): reg|0` — loads `index.json` if present; **0 if one exists
  but cannot be loaded** (unreadable, over 1 MiB, invalid, or a record that does not decode —
  v1.1.3, ADR-0012). `registry_in_memory(): reg`.
- `registry_admits(reg, manifest, installed_size): i64` *(added v1.1.3)* — 1 if the manifest
  validates and fits the quota; no side effects.
- `registry_install(reg, manifest, package_hash: Str, installed_size, installed_at): InstallResult*|0`
  — quota check, manifest validation, upgrade detection, index insert + persist; 0 (with the
  insert undone) if the index cannot be saved. Result:
  `instres_name` / `instres_version` / `instres_install_dir` / `instres_has_upgrade` /
  `instres_upgraded_from`.
- `registry_uninstall(reg, name: Str): i64` — removes the extracted files from disk (recursive)
  **and** the index entry, then persists; `registry_get_package(reg, name): record|0`;
  `registry_list_installed(reg): Vec` (sorted); `mela_registry_search(reg, query: Str): Vec`;
  `registry_len` / `registry_is_empty` / `registry_total_installed_size` /
  `registry_set_storage_quota(reg, q)` / `registry_packages_dir`.
- Installed record: `imp_name` / `imp_version` / `imp_publisher` / `imp_manifest` /
  `imp_installed_at` / `imp_install_dir` / `imp_package_hash` / `imp_installed_size`.
- `registry_verify_package(keyring, key_id, content, content_len, sig, sig_len, now): i64`
  — the trust gate (current-key lookup → decode → `trust_verify`). Since v1.5.2 (ADR-0017) the
  lookup takes the first version valid at `now` whose `key_id` derives from its key.
- Persistence: `registry_save_index(reg): bytes|<0` (creates parent dirs) /
  `registry_load_index(reg): 1|0|-1` (loaded / no index / unloadable);
  `registry_index_to_json` / `registry_index_from_json_into`.

## remote_client — `src/remote_client.cyr`

> Transport is real: `_rc_http_get` rides `sandhi` (DNS + TLS + HTTP/1.1/H2). `rc_search` /
> `rc_fetch_manifest` perform live fetches (and cache the result); the offline branches fall back
> to the cache.

- `url_encode(Str): Str`; `sanitize_filename(Str): Str` (per character: letters and digits in any
  script, `-`, `_` kept, everything else one `_`; v1.1.5); `validate_path_segment(Str): i64`.
- URL builders: `build_search_url(base, query, category, has_category, page)`;
  `build_manifest_url(base, name, version)`; `build_download_url(…)`; `build_publish_url(base)`;
  `build_latest_url(base, name)`.
- Response types + codec: `SearchResults` (`sresults_new` / `sresults_to_json` /
  `sresults_from_json`, with `SearchResult` `sresult_new`), `PublishResponse`
  (`presp_new` / `presp_to_json` / `presp_from_json`), `UpdateAvailable`
  (`update_new` / `mela_update_to_json` / `update_from_json`).
- `registry_client_new(base_url, cache_dir: Str): client` (trailing `/` trimmed);
  `client_base_url` / `client_cache_dir` / `client_is_offline` / `client_set_offline`.
- Cache: `registry_cache_search` / `registry_cached_search`; `registry_cache_manifest` /
  `registry_cached_manifest`.
- Flows (all real over sandhi): `rc_search` / `rc_fetch_manifest` (GET → parse → cache);
  **`rc_download`** (GET → write `<cache>/downloads/<name>-<version>.agnos-agent`, returns the
  path); **`rc_publish`** (POST bundle + Bearer auth + `X-Package-Metadata` → `PublishResponse`);
  **`rc_publish_signed(c, bundle, name, sig, sig_len, token)`** *(added v1.1.3)* — the same with
  the 64-byte Ed25519 signature, hex, in the metadata; `rc_check_updates`
  (per-package latest diff → `UpdateAvailable[]`). Guards: `rc_download_allowed` /
  `rc_publish_allowed`.
- **`mela_fetch_artifact(c, name, version, dest_path: Str): i64`** *(added v0.9.5)* — the
  consumer-facing download primitive. GETs the artifact over the sandhi transport and writes the
  body **verbatim to the caller-chosen `dest_path`**, making **no assumption about artifact type**
  (no `.agnos-agent` extension/layout). `rc_download` now builds on it but keeps mela's agent-bundle
  convention. This is **ark's** download entry point (ark's packages are takumi `.ark` binaries):
  ark passes its own `.ark` cache path and interprets the bytes with its own installer.
  *v1.1.3 (ADR-0012):* the body streams to disk (no 256 KiB buffered cap); returns 0 and removes
  `dest_path` on a transport error, timeout, non-2xx, empty body, or more than
  `RC_DOWNLOAD_MAX_BYTES` (100 MiB).
- Every request: connect/read timeouts of `REQUEST_TIMEOUT_SECS`, an overall deadline of
  `REQUEST_TIMEOUT_SECS` (API) or `DOWNLOAD_TIMEOUT_SECS` (download, publish), redirects followed
  up to `RC_MAX_HOPS`, `User-Agent: agnos-marketplace/<MELA_VERSION>` (v1.1.3).
- Constants: `DEFAULT_REGISTRY_URL`, `REQUEST_TIMEOUT_SECS`, `DOWNLOAD_TIMEOUT_SECS`,
  `RC_MAX_HOPS`, `RC_DOWNLOAD_MAX_BYTES`, `MELA_VERSION`.

## sandbox_profiles — `src/sandbox_profiles.cyr`

- Presets: `SP_PHOTO_EDITOR` `SP_PRODUCTIVITY` `SP_BROWSER` `SP_GAME` `SP_CLI_TOOL`
  `SP_GPU_COMPUTE` `SP_CUSTOM`; `sandbox_preset_name(p): Str`.
- `ll_new(path, access: Str)` (`LandlockRule`); `nr_new(enabled, allowed_hosts)` (`NetworkRule`).
- `build_photis_nadi_profile()` / `build_aequi_profile()`;
  `build_profile_for_preset(preset, app_name, data_dir): PredefinedProfile*` — accessors
  `profile_preset` / `profile_landlock_rules` / `profile_seccomp_mode` / `profile_network` /
  `profile_max_memory_mb` / `profile_allow_process_spawn`.
- `validate_profile(profile): Str` — `""` if valid, else the first problem.
- Codec: `profile_to_json` / `profile_from_json`; `sandbox_preset_json_name` /
  `sandbox_preset_json_parse` (`-1` for an unknown name, v1.1.5; it was Custom).
- `validate_profile(p): Str` — `""` if valid, else Rust's message naming the bad value.

## ratings — `src/ratings.cyr`

- Constants: `MAX_REVIEW_LENGTH` `MIN_SCORE` `MAX_SCORE`.
- `rstore_new(): store`.
- `rstore_add_rating(store, agent_id, package_name, score, has_review, review, version_reviewed, created_at): Rating*|0`
  — validates + dedups (one rating per agent per package, latest wins).
- `rstore_get_ratings(store, filter): Vec` (newest first); `filter_new()` + `filter_set_min_score`
  / `_set_package` / `_set_agent` / `_set_from` / `_set_until`.
- `rstore_get_stats(store, package: Str): RatingStats*|0` — `stats_average_score` is an f64
  (`f64_to` for the integer part); `stats_total_ratings` / `stats_dist(s, score)` (0 outside
  0..5) /
  `stats_latest_review`.
- `rstore_top_rated(store, has_min, min_ratings): Vec` (avg desc, total tiebreak);
  `rstore_total_count` / `rstore_package_count`.
- Persistence: `rstore_save(store, path: Str)` / `rstore_load(path): store|0` — a missing file is
  an empty store; a file that is empty, unreadable, over 1 MiB, incomplete, has a score outside
  1..5, or is in the Rust version's format is `0` (v1.1.1, v1.1.5);
  `rating_to_json`/`from_json`, `stats_to_json`/`from_json`, `rstore_to_json`/`from_json`.

## flutter_packaging — `src/flutter_packaging.cyr`

- Enums: `WL_*` (Wayland requirements, `wayland_req_name`); `DB_WAYLAND` / `DB_XWAYLAND`
  (`display_backend_name`).
- `fmanifest_new(runtime, engine_version, dart_version, wayland_protocols, platform_channels, aot_compiled): FlutterAppManifest*`.
- `is_dotted_version(Str): i64`; `validate_flutter_manifest(m): Vec<Str>`;
  `determine_backend(m, caps): backend`.
- `build_launch_config(m, app_name, compositor_socket, scale_f64): cfg` (`launch_*` accessors);
  `build_env_vars(cfg): map`.
- `layout_for_app(app_name): layout` (`layout_engine_path` / `_app_binary_path` / `_assets_path` /
  `_manifest_path` / `_sandbox_path`).

## flutter_agpkg — `src/flutter_agpkg.cyr`

- `pfconfig_new(app_name, version, publisher, description, category, wayland_requirements, network_access, has_data_dir, data_dir): PackFlutterConfig*`; `pfconfig_from_json(Str): cfg|0`.
- `fbuild_validate(root: Str): result` — `fbres_ok` / `fbres_error` / `fbres_build`
  (`fbuild_engine_lib` / `fbuild_has_aot` / `fbuild_aot_binary` / `fbuild_assets_dir`).
- `generate_manifest(config): MarketplaceManifest*`; `generate_sandbox_profile(config): SandboxProfile*`
  (`sbprofile_landlock_paths` / `sbprofile_seccomp_mode` / `sbprofile_network`,
  `sbprofile_to_json` / `from_json`).
- Archive (gzip + ustar): `pack_flutter_app(build_dir, config, output_dir: Str): path|0` — walks
  `flutter_assets/` recursively (symlinks skipped); 0 if any file cannot be read in full or is over
  `AGPKG_BUF_MAXLEN`, an entry name cannot be stored (over 256 bytes, or not splittable into the
  ustar prefix and name fields), or the archive would not fit the reader (v1.1.3, ADR-0012). A
  source file with an execute bit is packed 0755, the rest 0644 (v1.3.0, ADR-0014);
  `agpkg_inspect(path: Str): Vec<name>|0`; `agpkg_inspect_bytes(data, len): Vec|0`;
  `agpkg_payload_size(data, len): bytes|-1` *(added v1.1.5)* — what the bundle extracts to;
  `agpkg_read_entry(data, len, name: Str): content|0`. The reader skips symlink/hardlink and
  `..`/absolute entries (v0.9.0 hardening), and rejects the whole archive (`0`, or `-1` from
  `agpkg_extract_to_dir`) on a bad header checksum, a non-octal numeric field, data past the end
  of the archive, or two entries with the same name (v1.1.1, ADR-0011).
  `agpkg_extract_to_dir` also returns `-1` if any file fails to write (v1.1.3).
  *v1.3.0 (ADR-0014):* names come from the ustar prefix, GNU `L` and PAX `path` records too, and the
  safety checks apply to that full name (a name ending in `/` is skipped as well). The whole archive
  is also rejected for a non-octal mode field, a malformed PAX record, a PAX `size` that disagrees
  with its header, a global `path` / `size`, a long name over `AGPKG_NAME_MAX` or with no entry
  after it, or an extension entry over `AGPKG_EXT_MAX`. Extracted files are 0755 if the header's
  owner-execute bit is set, else 0644, set with `fchmod`.
  *v1.4.0 (ADR-0015):* `agpkg_extract_to_dir` writes only through directories it opened with
  `O_NOFOLLOW`, below a destination that must not itself be a symlink. It returns `-1` for a
  symlink at or below the destination, a non-directory on a directory's path, or a directory /
  device / symlink where a file goes. An existing regular file is unlinked and recreated
  (`O_EXCL`), never written into. Directories it creates are 0755.
- Constants *(v1.3.0)*: `AGPKG_BUF_MAXLEN` (16 MiB, sankoch's gzip ceiling; 8 MiB before),
  `AGPKG_MAX_PACKAGE_SIZE` (100 MiB, `== RC_DOWNLOAD_MAX_BYTES`), `AGPKG_NAME_MAX` (1,024),
  `AGPKG_EXT_MAX` (64 KiB). `tentry_mode` / `tentry_set_mode` *(added v1.3.0)* beside
  `tentry_new` / `tentry_name` / `tentry_data` / `tentry_len`.

## pipeline — `src/pipeline.cyr`

The end-to-end flow (ADR-0009); both trust gates are enforced at install.

- `pipeline_package(manifest, sandbox): bundle` — gzipped-ustar `.agnos-agent` bytes.
- `pipeline_publish(tlog, bundle, sk, sig_out[64], now): LogEntry*` — sign + transparency-log.
- `pipeline_extract_manifest(bundle): manifest|0`; `pipeline_extract_sandbox(bundle): sandbox|0`.
- `pipeline_install(reg, keyring, bundle, sig, sig_len, expected_hash: Str, now): InstallResult*|0`
  — **gate 1** (signature, keyed by publisher key_id) + **gate 2** (SHA-256 digest), then quota,
  then **extract** to `packages/<name>`, then record and save (v1.1.3: extract-first, as Rust).
  `installed_size` is the extracted size (`agpkg_payload_size`, v1.1.5), as Rust recorded it.
  Returns `0` on any gate failure / malformed bundle / invalid manifest / quota / failed
  extraction / failed index save; a fresh install's partial directory is removed.
  *v1.3.0 (ADR-0014):* a bundle over `AGPKG_MAX_PACKAGE_SIZE` returns `0` before anything is read;
  the quota is checked against the bundle size and the extracted size, both before any file is
  written; the bundle is inflated once.
  *v1.4.0 (ADR-0015):* extraction is confined (see `agpkg_extract_to_dir`). A fresh install's
  rollback removes only a real directory; a symlink at `packages/<name>` is left as found.
  *v1.5.1 (ADR-0016):* after both gates, an upgrade must keep its publisher key: the installed
  version's `key_id`, a successor the keyring declares, or one approved with
  `registry_allow_key_change`. Otherwise it returns `0` and nothing is written. An approval it
  uses is used up.

---

## Stability notes

- **Error model**: `0` for failure/absence; no panics. Callers check for `0`.
- **Fully wired (v0.9.2)**: HTTP+HTTPS+DNS transport (via `sandhi`) and on-disk tarball
  extraction (`agpkg_extract_to_dir`, run by `pipeline_install`) — no remaining deferred seams.
- **Internal** (`_`-prefixed, e.g. `_tar_*`, `_man_*`, `_rc_*`): not part of this contract.
