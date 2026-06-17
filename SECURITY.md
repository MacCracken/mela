# Security Policy

Mela is the trust boundary between an AGNOS system and the software it installs, so its
security posture is load-bearing. This file is the **public reporting policy**; the
implementer-facing threat model lives in `docs/development/threat-model.md` (when earned) and
audit findings in `docs/audit/`.

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
- **Integrity verification.** Every download is SHA-256-verified against its manifest before
  it is trusted (`trust`).
- **Transparency.** Publications are recorded in an append-only, verifiable transparency log
  (`transparency`) so a compromised or malicious publisher cannot silently backdate, alter, or
  disappear an artifact.
- **Capability disclosure.** Each app ships a sandbox profile (`sandbox_profiles`) declaring
  exactly what it may access; capabilities are surfaced **before** install.
- **TLS.** Marketplace network calls use **rustls only** — OpenSSL is not a dependency and
  must not be introduced.

## Out of scope

- Vulnerabilities in third-party packages distributed *through* the marketplace (report those
  to the package's publisher; the transparency log and signature chain are the auditable
  record).
- Issues requiring a pre-compromised host or a malicious local root.

## Supported versions

Pre-1.0: only the latest `0.x` release receives security fixes. A supported-version matrix
lands at the 1.0 cut.
