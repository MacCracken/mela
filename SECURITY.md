# Security Policy

Mela is the trust boundary between an AGNOS system and the software it installs, so its
security posture is load-bearing. This file is the **public reporting policy**; the
implementer-facing threat model lives in [`docs/development/threat-model.md`](docs/development/threat-model.md),
audit findings in [`docs/audit/`](docs/audit/), and how to manage trusted publisher keys in
[`docs/guides/keyring-provenance.md`](docs/guides/keyring-provenance.md).

## Reporting a vulnerability

**Do not open a public GitHub issue for a security vulnerability.** Instead, report privately
to the maintainers via the [agnosticos](https://github.com/MacCracken/agnosticos) security
contact. Include:

- A description of the vulnerability and its impact.
- Steps to reproduce (a proof-of-concept where possible).
- The affected version(s) and module(s).

You'll receive an acknowledgement, and we'll coordinate a fix and disclosure timeline with you.

## Security model (what Mela guarantees)

- **Signature enforcement.** Every package and agent must carry a valid Ed25519 publisher
  signature. Unsigned artifacts are **rejected**, not warned about (`trust`).
- **Key continuity.** An upgrade must be signed under the key the installed version was published
  under, a successor the keyring declares, or a key the operator approved for that one install
  (ADR-0016).
- **Integrity verification.** A bundle's SHA-256 must match the expected digest the caller
  supplies before it is installed (`trust`, `pipeline`). An empty expected digest skips the
  comparison; the signature check never is.
- **Transparency.** Publications are recorded in an append-only, hash-chained transparency log
  (`transparency`). Altering, reordering or backdating a recorded entry is detectable by anyone
  holding the log. It does not yet prevent a registry from showing different clients different
  logs (see the threat model).
- **Capability disclosure.** Each app ships a sandbox profile (`sandbox_profiles`) declaring
  exactly what it may access; capabilities are surfaced **before** install.
- **Confined installation.** Installing writes only inside the package's install directory. On
  Linux it never follows a symlink and never writes into an existing file's inode (ADR-0015).
- **TLS.** Marketplace network calls use the Cyrius stdlib's native TLS, verifying the server's
  certificate chain against the system roots. OpenSSL is not a dependency and must not be
  introduced.

## Out of scope

- Vulnerabilities in third-party packages distributed *through* the marketplace (report those
  to the package's publisher; the transparency log and signature chain are the auditable
  record).
- Issues requiring a pre-compromised host or a malicious local root.

## Supported versions

Security fixes land on the latest `1.x` release. Earlier releases are not patched; upgrade to
the latest `1.x`.
