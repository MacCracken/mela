# 0012 — Fail-closed install, packaging and transport

**Status**: Accepted
**Date**: 2026-10-15 (v1.1.3)

## Context

The 2026-10-14 parity audit ([`../development/rust-parity.md`](../development/rust-parity.md))
found defects D6–D12. Several were cases where mela reported success but did something else,
where Rust had returned an error:

- **D7:** artifact downloads went through sandhi's buffered client with its default options. Any
  artifact over 256 KiB failed. There was no timeout, so a stalled registry hung the caller, and
  redirects were not followed. Rust's reqwest client had a 30 s request timeout (300 s for
  downloads and publish), followed redirects, and sent a User-Agent.
- **D8:** the packer read each file with a call that stops at 8 MiB without an error. A large
  engine `.so` was packed truncated, and the bundle "succeeded". An unreadable asset was skipped.
  A name over 100 bytes was truncated.
- **D9:** `pipeline_install` recorded the install before extracting, and ignored both the
  extraction and the index save. An `index.json` that was corrupt, over 1 MiB, or held a record
  that did not decode loaded as an **empty** registry, and the next install overwrote it.
- **D10:** `rc_publish` sent no signature. Rust sent an `X-Package-Metadata` header carrying it.
- **D12:** a manifest with an unknown or missing `category` decoded with category `-1` and
  installed.

Every function involved is in the frozen API ([`../api/`](../api/)). Changing what one accepts or
returns needs an ADR. This ADR extends [ADR-0011](0011-fail-closed-decoding-at-the-trust-boundary.md)
from decoding to install, packaging and transport.

## Decision

**Report failure instead of a partial success.** Specifically:

- **Transport** (`mela_fetch_artifact`, `rc_download`, `rc_publish`, every API GET):
  - Every request sets connect and read timeouts of `REQUEST_TIMEOUT_SECS` (30 s), plus an
    overall deadline: `REQUEST_TIMEOUT_SECS` for API calls, `DOWNLOAD_TIMEOUT_SECS` (300 s) for
    downloads and publish.
  - Redirects are followed, up to `RC_MAX_HOPS` (10, reqwest's default). sandhi refuses an
    https→http downgrade and strips credentials across authorities.
  - Every request sends `User-Agent: agnos-marketplace/<MELA_VERSION>`.
  - Buffered API responses are capped at `RC_BUF_MAXLEN` (1 MiB), the size the response cache
    reads back.
  - **Artifacts stream to disk** through `sandhi_http_download_sink_headers`, with no in-memory
    copy.
  - `mela_fetch_artifact` returns 0, and **removes `dest_path`**, on any of: a transport error, a
    timeout, a non-2xx response, an empty body, or more than `RC_DOWNLOAD_MAX_BYTES` (100 MiB,
    Rust's `MAX_PACKAGE_SIZE`).
  - `rc_download` checks its guards before creating the downloads directory.
- **Publish:**
  - `rc_publish` sends Rust's `X-Package-Metadata` (`bundle_name`, `bundle_sha256`,
    `bundle_size`, `signature`), with `signature: null`.
  - New additive `rc_publish_signed(c, bundle, name, sig, sig_len, token)` sends the 64-byte
    Ed25519 signature as **hex**. Rust read its binary `.sig` sidecar with `read_to_string`,
    which cannot carry 64 raw bytes, so hex is the only sound JSON form.
- **Packaging** (`pack_flutter_app`) returns 0, writing nothing, when:
  - any file cannot be read in full: unreadable, or larger than `AGPKG_BUF_MAXLEN` (8 MiB);
  - an entry name exceeds the 100-byte ustar name field;
  - the archive would exceed the reader's 8 MiB inflate buffer, since such a bundle could never
    be installed.

  The asset walk recurses (D11; ADR-0008 corrected) and skips symlinks, as Rust did. The 8 MiB
  ceiling stays until streaming extraction (roadmap v1.2.0).
  *Update (v1.3.0, ADR-0014):* the ceiling is 16 MiB, sankoch's gzip limit, until sankoch can
  stream gzip. Names up to 256 bytes pack through the ustar prefix.
- **Install** (`pipeline_install`):
  - Order: gates, then validation, then `registry_admits` (quota and validation, no side
    effects), then **extract**, then **record and save**, as in Rust.
  - An extraction failure or a save failure returns 0. For a fresh install, the partly written
    install directory is removed.
  - An in-memory registry skips extraction and saving explicitly. It no longer relies on writes
    to `/dev/null` failing.
  - `agpkg_extract_to_dir` returns -1 if any file fails to write.
- **Registry:**
  - `mela_registry_new` returns **0** when an `index.json` exists but cannot be loaded (Rust's
    `new()` returned an error).
  - `registry_load_index` returns 1 if loaded, 0 if there is no index, and -1 if the index is
    unreadable, over the cap, invalid, a directory, or holds a record that does not decode.
  - `registry_save_index` creates parent directories.
  - `registry_install` undoes its index entry and returns 0 if the save fails.
- **Manifest:** `manifest_from_json` returns 0 for an unknown, missing or non-string `category`.

## Consequences

- **Positive**
  - Packages of any size up to 100 MiB download. This includes ark's `.ark` pulls, which were
    capped at 256 KiB.
  - A dead or stalled registry cannot hang the caller.
  - The signature reaches the registry.
  - A bundle reported as packed is complete, and a package reported as installed is on disk.
  - A corrupt index is never silently replaced.
- **Negative**
  - Behavior changes for callers:
    - `mela_registry_new` can now return 0, so callers must check it.
    - `pack_flutter_app` refuses inputs it used to truncate.
    - A manifest without a valid category no longer decodes.
  - Until v1.2.0, a Flutter app whose engine is over 8 MiB cannot be packed at all. Before, it
    packed corrupt.
- **Neutral**
  - `cyrius test` still opens no sockets.
  - The transport behavior is verified by a new live check, `scripts/transport-check.sh`, which
    runs a local python3 server in CI.
  - `MELA_VERSION` is pinned to `VERSION` by a test (`CYRIUS_PKG_VERSION`), so the User-Agent
    cannot drift.

## Alternatives considered

- **Raise sandhi's buffered `max_response_bytes` instead of streaming:** this keeps the whole
  artifact in memory, up to 100 MiB per fetch. sandhi's streaming download exists for exactly
  this case.
- **Open an empty registry on a corrupt index and warn:** this is what mela did before, and the
  next save destroyed every record.
- **Keep truncating long names and oversized files and let install reject them:** the bundle
  would already have been published, signed and logged as valid.
