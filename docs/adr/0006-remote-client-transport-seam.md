# 0006 — Remote client HTTP/TLS transport is a deferred seam

**Status**: Superseded by the v0.9.2 implementation — transport is real (sandhi)
**Date**: 2026-06-17

> **Update (v0.9.2): the seam is gone — transport is fully implemented via
> `sandhi`.** `_rc_http_get` (`src/remote_client.cyr`) calls
> `sandhi_http_get_auto`, which does URL parse → **DNS resolution** → **TLS**
> (https) → HTTP/1.1-or-H2 → response framing over real sockets. `rc_search` /
> `rc_fetch_manifest` run the live online flow. **Proven both ways**: HTTP from a
> local `python3 -m http.server`, and `https://example.com/` (DNS + TLS) returning
> the real page. There are **no** IPv4-only or HTTPS-pending caveats — that
> earlier framing was wrong (sandhi ships a DNS resolver + TLS; this ADR's whole
> "sandhi is too heavy / server-only" premise below was mistaken). The text below
> is the original (superseded) rationale, kept for history.

## Context

`rust-old/src/remote_client.rs` is an HTTP client (`reqwest` + rustls) for the
registry: `search`, `fetch_manifest`, `download_package`, `publish`,
`check_updates`. The roadmap names the v0.6.0 dep gate as stdlib `tls` /
`tls_native` + **`sandhi`** (HTTP client), host-first.

Two facts shape the port:

1. **The Rust test suite never opens a socket.** Every `#[test]` /
   `#[tokio::test]` exercises *pure* logic — `url_encode`, `sanitize_filename`,
   `validate_path_segment`, the response-type JSON (de)serialization, the
   trailing-slash trim, the offline-mode guards, and the on-disk response cache.
   The online request paths are never hit in tests (there is no mock server).
2. **`sandhi` is heavy and server/async-oriented.** Its dist pulls an async
   runtime, `tls` (via `dynlib` / `fdlopen` / `mmap`), `atomic`, `regression`,
   etc., and does not expose a drop-in `http_get`. Wiring it in for v0.6.0 would
   add a large transitive surface as **dead, DCE'd, untested-in-CI code** — the
   transport can't be exercised by `cyrius test` without a live or mock server.

The roadmap's own done-when frames the bar as "the four flows work against a
**mock** endpoint with **response-parse parity**; response parsers fuzzed" —
all achievable without live networking.

## Decision

**Port the full request/response logic now; make the live HTTP/TLS transport a
seam, deferred to the v0.9.0 end-to-end wiring.**

Ported and tested in v0.6.0:

- `url_encode`, `sanitize_filename`, `validate_path_segment` (pure).
- URL builders for all five endpoints (search / manifest / download / publish /
  latest).
- Response types `SearchResults` / `SearchResult` / `PublishResponse` /
  `UpdateAvailable` with JSON encode + decode — the **response-parse parity**,
  tested both by round-trip and by parsing a **canned (mock) response** document.
- `RegistryClient` (base-url trailing-slash trim, cache dir, offline flag).
- The **offline-mode guards** for each flow (search/manifest fall back to cache;
  download/publish are blocked; check_updates returns empty).
- The on-disk **response cache** (`cache_search` / `cached_search`,
  `cache_manifest` / `cached_manifest`) over stdlib `fs`.

The seam is `_rc_http_get` (and a future `_rc_http_post`): currently returns 0
("no response"). Each flow's online branch builds the correct URL, would call
the seam, and parses the result with the already-tested parsers. v0.9.0 wires
the seam to `sandhi` / stdlib `tls` (host-first; the `--agnos` socket-backend gap
remains out of scope per the roadmap).

## Consequences

- **Positive** — the entire testable surface of the module is ported with
  parity, the response parsers are fuzzed, and the four flows are demonstrated
  against mock responses — meeting the done-when without dragging a large,
  untested network stack into the build. Matches the Rust test suite exactly.
- **Negative** — no live request is issued yet; `sandhi` / `tls` are *not* added
  as deps at v0.6.0 (a deviation from the roadmap's literal dep-gate timing).
  The online flows return "no response" until v0.9.0 wires the seam. `download`
  and `publish` are exposed as guard predicates (`rc_download_allowed` /
  `rc_publish_allowed`) rather than performing fetch/upload.
- **Neutral** — v0.9.0 plugs `sandhi`/`tls` into `_rc_http_get`/`_rc_http_post`
  with no change to the URL builders, response parsers, cache, or offline logic;
  that is also where the two trust gates get enforced end-to-end.

## Alternatives considered

- **Wire `sandhi` + `tls` now** — honors the literal roadmap gate, but adds a
  heavy transitive surface as dead code that `cyrius test` cannot exercise, and
  duplicates the transport wiring that v0.9.0 does anyway. Rejected.
- **Hand-roll a minimal HTTP/TLS client** — security-sensitive and redundant
  with `sandhi`/stdlib `tls`; a TLS stack is not something to reimplement for a
  seam. Rejected.
