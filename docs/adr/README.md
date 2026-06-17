# Architecture Decision Records

Significant design decisions for Mela. Each ADR captures **why not the other thing** — the
context, the decision, its consequences, and the alternatives rejected.

## Conventions

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. **Never renumber.**
- **One decision per ADR.** A supersession adds a new ADR and marks the old one
  `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` / `Deprecated`.
- Start from [`template.md`](template.md).
- Index each ADR below with a one-line hook.

## Index

_None recorded yet._

## To backfill

- **ADR-015 — marketplace architecture.** `src/lib.rs` cites "the marketplace architecture
  defined in ADR-015", but the record was never written here. The scaffold already encodes
  several decisions worth capturing as ADRs:
  - rustls-only TLS (no OpenSSL).
  - Ed25519 publisher signatures mandatory; unsigned artifacts rejected.
  - SHA-256 integrity verification on every download.
  - The append-only transparency log as the publication record.
  - The `.agpkg` (AGNOS package) archive format for Flutter apps.
