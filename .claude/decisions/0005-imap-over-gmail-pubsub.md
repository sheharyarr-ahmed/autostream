# ADR 0005 — Email: IMAP polling over Gmail Pub/Sub

**Status:** Accepted (Phase 1)
**Date:** 2026-05-14

## Context

Workflow 3 (Email Classification) needs an inbox source. Two options:

- **Gmail API + Pub/Sub push notifications** — sub-second latency from arrival to webhook fire; requires a Google Cloud project, OAuth credentials, Pub/Sub topic + subscription, domain verification for some scopes.
- **IMAP polling every 5 minutes** — works against any IMAP-compatible mailbox (Gmail, Fastmail, Proton via Bridge, self-hosted Maddy, etc.); no GCP project required; 5-min ceiling on latency.

## Decision

Use **IMAP polling at 5-minute cadence**.

## Rationale

- **Portability.** IMAP works against any mailbox AutoStream's reader might want to wire up. Gmail Pub/Sub locks the demo to Gmail.
- **No GCP project required.** A GCP project for a portfolio demo is significant complexity for minor latency gain.
- **Latency tolerance.** Email classification is not a 1-second-matters workflow. A 5-minute ceiling on routing-to-Slack is fine for a shared inbox.
- **Failure mode is benign.** If IMAP polling fails, the email stays UNSEEN and is retried at the next 5-min poll. No backlog, no Pub/Sub subscription leak.
- **Zero credential complexity.** Username + app-password (or app-specific password) — done. OAuth + scopes + token refresh is a multi-hour setup.

## Consequences

- **Positive**: see rationale.
- **Negative**: up to 5 minutes of latency between email arrival and Slack routing. Documented in README's Demo table.
- **Negative**: IMAP TLS cert errors are a real failure mode (`TROUBLESHOOTING.md` covers them). Pub/Sub avoids this entirely.

## Reconsideration triggers

- A specific high-volume Gmail-only mailbox needs sub-minute latency. (At which point, AutoStream is past Phase 1 anyway.)
- Phase 2's "multi-account email" feature adds the option of mixing IMAP + Gmail Pub/Sub. Different accounts can use different ingestion strategies if it earns the complexity.
