# Prototype Access & GitHub Pages Retirement

Status: **Proposed / design only**. This document does not authorize an immediate public-site unpublish, password cutover, or private repository conversion.

## Goal and non-goals

- Keep https://proto.3cgroup.cn/ public. Protect the four first-batch prototype **hostnames** independently: ai-mirror, beauty-mirror, hair-mirror, and fitting-mirror.
- Give each hostname a separate access password; default candidate is a shared username `demo`, **not** a shared password. Browser HTTP Basic Authentication is acceptable for the initial prototype stage.
- Do not add a login app, backend database, proxy service, or user management system.
- Do not change any SSH login secrets or security policy. Retain the existing `PROTO_HOST`, `PROTO_USER`, `PROTO_SSH_PORT`, and `PROTO_SSH_KEY` GitHub Secrets for deployment only.
- Avoid changes to the company's primary server and the original `lab.3cgroup.cn` aesthetic/template.

## Configuration ownership and minimal implementation

1. **One Caddyfile in proto-infra** owns the host list, static roots, HTTPS and basic_auth declarations. Keep the four explicit hosts (no public catch-all, no copied Caddyfiles per product). A short shared snippet for repeated settings is reasonable; don't invent a config framework for four sites.
2. **One runtime-only credential file** on the prototype server, e.g. `/etc/caddy/proto-auth.env`, owned by root and mode `0600`, contains four distinct **hashed** credentials (not plaintext). Never commit this file, append it to logs, or upload it as an Actions artifact. The Caddy service will load hashes through a systemd EnvironmentFile. Use a Caddy-supported environment placeholder in each site's `basic_auth` block.
3. Choose a supported hash type consistently; bcrypt is the basic_auth default. Generate via `caddy hash-password` with password on stdin (never as a shell command argument, workflow echo or URL). Password handoff to the maintainer should use an explicitly agreed private channel, not public CI logs.
4. **One deployment mechanism** preserves runtime credentials across updates. Existing mirror publisher currently copies the tracked Caddyfile to `/etc/caddy/Caddyfile`; it must validate against the installed envfile before reloading. Update the systemd unit and publisher together with a rollback if configuration validation/reload fails; missing credentials are a release blocker, not a reason to disable authentication.
5. Site asset deploy must not replace the envfile or authentication policy. Password rotation is a separate, minimal server operation: rotate one hash, validate, reload, verify only that hostname, and retain a rollback copy with restricted permissions.
6. The independent portal-only publisher remains separate because it updates just one public HTML file. Avoid re-deploying all four product archives during a homepage text/visual tweak; do not let multiple workflows race over the same Caddyfile.

## Release acceptance contract

| Verification | Expected result |
| --- | --- |
| Public homepage `https://proto.3cgroup.cn/` | HTTPS 200, no authentication prompt |
| Each protected root without Authorization | HTTP 401 with Basic challenge; no application HTML |
| Each protected static asset URL without Authorization | HTTP 401; no JS/CSS/image bypass |
| Wrong username/password | HTTP 401 |
| Correct credentials for its own site | HTTP 200 and real HTML/JS/CSS can load |
| Password from site A used on site B | HTTP 401 |
| Reload, release, and service restart | All four protections persist |
| Bad/missing hash during staged rollout | Release stops/rolls back; never deploy unprotected route |
| Existing URLs | HTTPS works; do not break other prototype hosts |

Don't make CI green by treating a protected site's expected 401 as a failure. Change the current `deploy-mirror-batch.yml` public smoke tests (which expect HTTP 200 without authentication) in the **same PR** that enables auth. HTTP 200 verification with real credentials must use a controlled secure testing path, not echo a password in CI.

## GitHub Pages migration and retirement

Inventory confirmed on 2026-10-22:

- `sanchuang-dev/ai-mirror`: still has `pages.yml` for a separate public **visual review prototype** and a Pages `/dev/` preview distinct from the frozen `prod` files copied to proto. Do not assume these snapshots are byte-for-byte identical.
- `sanchuang-dev/ai-beauty-mirror`, `ai-hair-mirror`, `ai-fitting-mirror`: each has a `pages.yml` on main which publishes `prototype/` automatically. Their main is the documented early reference-only Pages exception.
- `sanchuang-dev/base-prototype` `demos.json`, its README and Pages smoke tests still advertise the four old `github.io` destinations; they need coordinated updates once the protected destinations are usable.
- Do not unpublish **base-prototype** Pages in this batch: it remains a fallback for local-life and lingnan; other unrelated public Pages sites are out of scope.

**Phased cutover, no destructive shortcut:**

1. Provision Caddy access control and validate all four sites (401, cross-site isolation, credentialed 200); maintain existing Pages until this works.
2. Update the canonical `base-prototype` manifest and matching hard-coded checks/documentation to the `https://*.proto.3cgroup.cn/` URLs. Leave the layout design untouched. Validate lab EdgeOne and Pages outputs still work and new card links require credentials.
3. Retire each of the four **product** Pages publishing workflows, respecting each repository's branch policy and review gate. This prevents a future push/manual dispatch from republishing an old public mirror after unpublish.
4. Unpublish the four GitHub Pages deployments through GitHub's Pages setting (or a properly authorized admin/API operation), without deleting any code. Verify old public URLs actually stop serving content; record their HTTP responses and update any stale external docs.
5. Never present a public GitHub repository as confidential: unpublishing Pages removes the hosted preview only; the tracked source/history remains publicly visible unless repository visibility is separately changed with authorization.

## Units of work (small, independently reversible)

- **A · Access boundary**: server-only credential storage, Caddy config, safe validation/reload/rollback, correct tests. No Pages change.
- **B · Consumer migration**: change links in base-prototype and hard-coded assertions/README, verify lab and proto flows. No application rewrite.
- **C · Pages retirement**: disable/retire the four product Pages workflows and unpublish their sites after A/B acceptance; keep a record of actual old/new URL behavior.

## References

- Caddy basic_auth: https://caddyserver.com/docs/caddyfile/directives/basic_auth
- Caddy validation and systemd reload: https://caddyserver.com/docs/command-line
- GitHub unpublish (reversible, independent of repository): https://docs.github.com/en/pages/getting-started-with-github-pages/unpublishing-a-github-pages-site

## Pending operational input

Four strong, independent passwords and their handoff method. No password values, hashes, or new secrets are included in this RFC. Until auth is actually installed and smoke-tested, all four proto sites are still publicly accessible.
