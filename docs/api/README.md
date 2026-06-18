# mela — public API reference

> **Frozen at v0.9.1.** This is the v1.0-bound public surface that downstream
> consumers (e.g. [`ark`](https://github.com/MacCracken/ark)) build against.
> Additive changes are allowed before v1.0; **signature/semantic changes to a
> listed function require an ADR**. Functions prefixed `_` are internal and may
> change without notice — do not call them.

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
- **Field accessors** follow `<type>_<field>(ptr)` and are not all listed individually below;
  the constructor's field order is the struct layout. Setters are `<type>_set_<field>`.

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
  `CAT_PARSE_FAIL`.

## manifest — `src/manifest.cyr`

- `is_valid_semver(v: Str): i64` — `major.minor.patch` (+ optional `-prerelease`).
- `publisher_new(name, key_id, homepage: Str): PublisherInfo*` — `pub_name` / `pub_key_id` /
  `pub_homepage`.
- `manifest_new(agent, publisher, category, version: Str): MarketplaceManifest*` — `agent` is an
  agnostik `AgentManifest`; accessors `man_name` / `man_version` / `man_description` /
  `man_publisher` / `man_category` / `man_runtime` / `man_screenshots` / `man_changelog` /
  `man_min_agnos_version` / `man_dependencies` / `man_tags`; setters for the optional fields.
- `manifest_validate(m): Vec<Str>` — list of error messages; empty Vec ⇒ valid.
- `manifest_qualified_name(m): Str` — `publisher/agent-name` (publisher lowercased, spaces→`-`).
- Codec: `manifest_to_json(m): Str` / `manifest_from_json(Str): m|0`;
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
  `kv_is_valid_at(kv, when): i64`; `kv_verifying_key(kv): pk|0` (hex→32 bytes, validated).
- `keyring_new()`; `keyring_add_key(kr, kv)`; `keyring_get_current_key(kr, key_id, now): kv|0`;
  `keyring_get_all_versions` / `keyring_len` / `keyring_is_empty`.

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

## local_registry — `src/local_registry.cyr`

- `registry_new(root_dir: Str): reg` (loads `index.json` if present); `registry_in_memory(): reg`.
- `registry_install(reg, manifest, package_hash: Str, installed_size, installed_at): InstallResult*|0`
  — quota check, manifest validation, upgrade detection, index insert + persist. Result:
  `instres_name` / `instres_version` / `instres_install_dir` / `instres_has_upgrade` /
  `instres_upgraded_from`.
- `registry_uninstall(reg, name: Str): i64`; `registry_get_package(reg, name): record|0`;
  `registry_list_installed(reg): Vec` (sorted); `registry_search(reg, query: Str): Vec`;
  `registry_len` / `registry_is_empty` / `registry_total_installed_size` /
  `registry_set_storage_quota(reg, q)` / `registry_packages_dir`.
- Installed record: `imp_name` / `imp_version` / `imp_publisher` / `imp_manifest` /
  `imp_installed_at` / `imp_install_dir` / `imp_package_hash` / `imp_installed_size`.
- `registry_verify_package(keyring, key_id, content, content_len, sig, sig_len, now): i64`
  — the trust gate (current-key lookup → decode → `trust_verify`).
- Persistence: `registry_save_index(reg)` / `registry_load_index(reg)`;
  `registry_index_to_json` / `registry_index_from_json_into`.

## remote_client — `src/remote_client.cyr`

> Transport is real: `_rc_http_get` rides `sandhi` (DNS + TLS + HTTP/1.1/H2). `rc_search` /
> `rc_fetch_manifest` perform live fetches (and cache the result); the offline branches fall back
> to the cache.

- `url_encode(Str): Str`; `sanitize_filename(Str): Str`; `validate_path_segment(Str): i64`.
- URL builders: `build_search_url(base, query, category, has_category, page)`;
  `build_manifest_url(base, name, version)`; `build_download_url(…)`; `build_publish_url(base)`;
  `build_latest_url(base, name)`.
- Response types + codec: `SearchResults` (`sresults_new` / `sresults_to_json` /
  `sresults_from_json`, with `SearchResult` `sresult_new`), `PublishResponse`
  (`presp_new` / `presp_to_json` / `presp_from_json`), `UpdateAvailable`
  (`update_new` / `update_to_json` / `update_from_json`).
- `registry_client_new(base_url, cache_dir: Str): client` (trailing `/` trimmed);
  `client_base_url` / `client_cache_dir` / `client_is_offline` / `client_set_offline`.
- Cache: `registry_cache_search` / `registry_cached_search`; `registry_cache_manifest` /
  `registry_cached_manifest`.
- Flows (offline guards live; online builds URL + parses): `rc_search`, `rc_fetch_manifest`,
  `rc_download_allowed`, `rc_publish_allowed`, `rc_check_updates`.
- Constants: `DEFAULT_REGISTRY_URL`, `REQUEST_TIMEOUT_SECS`, `DOWNLOAD_TIMEOUT_SECS`.

## sandbox_profiles — `src/sandbox_profiles.cyr`

- Presets: `SP_PHOTO_EDITOR` `SP_PRODUCTIVITY` `SP_BROWSER` `SP_GAME` `SP_CLI_TOOL`
  `SP_GPU_COMPUTE` `SP_CUSTOM`; `sandbox_preset_name(p): Str`.
- `ll_new(path, access: Str)` (`LandlockRule`); `nr_new(enabled, allowed_hosts)` (`NetworkRule`).
- `build_photis_nadi_profile()` / `build_aequi_profile()`;
  `build_profile_for_preset(preset, app_name, data_dir): PredefinedProfile*` — accessors
  `profile_preset` / `profile_landlock_rules` / `profile_seccomp_mode` / `profile_network` /
  `profile_max_memory_mb` / `profile_allow_process_spawn`.
- `validate_profile(profile): Str` — `""` if valid, else the first problem.
- Codec: `profile_to_json` / `profile_from_json`; `sandbox_preset_json_name` / `_json_parse`.

## ratings — `src/ratings.cyr`

- Constants: `MAX_REVIEW_LENGTH` `MIN_SCORE` `MAX_SCORE`.
- `rstore_new(): store`.
- `rstore_add_rating(store, agent_id, package_name, score, has_review, review, version_reviewed, created_at): Rating*|0`
  — validates + dedups (one rating per agent per package, latest wins).
- `rstore_get_ratings(store, filter): Vec` (newest first); `filter_new()` + `filter_set_min_score`
  / `_set_package` / `_set_agent` / `_set_from` / `_set_until`.
- `rstore_get_stats(store, package: Str): RatingStats*|0` — `stats_average_score` is an f64
  (`f64_to` for the integer part); `stats_total_ratings` / `stats_dist(s, score)` /
  `stats_latest_review`.
- `rstore_top_rated(store, has_min, min_ratings): Vec` (avg desc, total tiebreak);
  `rstore_total_count` / `rstore_package_count`.
- Persistence: `rstore_save(store, path: Str)` / `rstore_load(path): store|0`;
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
- Archive (gzip + ustar): `pack_flutter_app(build_dir, config, output_dir: Str): path|0`;
  `agpkg_inspect(path: Str): Vec<name>|0`; `agpkg_inspect_bytes(data, len): Vec|0`;
  `agpkg_read_entry(data, len, name: Str): content|0`. The reader rejects symlink/hardlink and
  `..`/absolute entries (v0.9.0 hardening).

## pipeline — `src/pipeline.cyr`

The end-to-end flow (ADR-0009); both trust gates are enforced at install.

- `pipeline_package(manifest, sandbox): bundle` — gzipped-ustar `.agnos-agent` bytes.
- `pipeline_publish(tlog, bundle, sk, sig_out[64], now): LogEntry*` — sign + transparency-log.
- `pipeline_extract_manifest(bundle): manifest|0`; `pipeline_extract_sandbox(bundle): sandbox|0`.
- `pipeline_install(reg, keyring, bundle, sig, sig_len, expected_hash: Str, now): InstallResult*|0`
  — **gate 1** (signature, keyed by publisher key_id) + **gate 2** (SHA-256 digest), then record.
  Returns `0` on any gate failure / malformed bundle / invalid manifest (installs nothing).

---

## Stability notes

- **Error model**: `0` for failure/absence; no panics. Callers check for `0`.
- **Fully wired (v0.9.2)**: HTTP+HTTPS+DNS transport (via `sandhi`) and on-disk tarball
  extraction (`agpkg_extract_to_dir`, run by `pipeline_install`) — no remaining deferred seams.
- **Internal** (`_`-prefixed, e.g. `_tar_*`, `_man_*`, `_rc_*`): not part of this contract.
