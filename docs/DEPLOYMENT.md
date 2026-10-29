# Prototype infrastructure deployment

## Prerequisites

Independent Aliyun Linux server with public IPv4, SSH username/password, and Caddy. Point DNS for `proto.3cgroup.cn` and explicitly configured subdomains to this server. Allow inbound TCP 80/443.

## GitHub Actions configuration

All four values are existing **Repository Secrets**. Do not move them to Variables or rename them.

| Secret name | Value |
|---|---|
| `PROTO_HOST` | Server public IP |
| `PROTO_USER` | SSH username |
| `PROTO_SSH_PORT` | SSH port, normally 22 |
| `PROTO_SSH_KEY` | **SSH login password**, despite the legacy name |

The workflow explicitly uses password authentication via `sshpass`. `PROTO_SSH_KEY` is only the established secret name; it is **not** interpreted as a private key. If this secret currently contains an SSH private key, its value must be replaced with the password.

No additional secrets are required. In particular, no `PROTO_PASSWORD` or `PROTO_KNOWN_HOSTS`.

The workflow uses OpenSSH `StrictHostKeyChecking=accept-new` so the first presented host identity is accepted automatically. This trust-on-first-use mode removes manual fingerprint setup but does not independently verify server identity on first connection. GitHub-hosted runners are ephemeral; this risk recurs with new runners.

## First server setup (administrator)

1. Inspect the **new prototype instance**, its operating system and existing services before changing anything.
2. Install Caddy; set `ACME_EMAIL` in the Caddy service environment.
3. Prepare `/srv/proto/{portal,local-life,ai-mirror,college}/current`, with scoped write access for the login user.
4. Validate the repository Caddyfile before installing it to `/etc/caddy/Caddyfile`. Reload Caddy after validation.
5. Verify DNS, HTTPS and SPA refresh via actual external requests.

## Releases

### Portal

The portal publisher renders the canonical lab layout and synchronizes only `/srv/proto/portal/current/index.html`.

### Local Life

`local-life.proto.3cgroup.cn` is a static prototype hosted by Caddy from `/srv/proto/local-life/current`.

- Source of truth for application code: `sanchuang-dev/local-life`.
- Current pinned accepted source: `prod@d907981809484ab4250dca0e2153407f255dfbfc`.
- `scripts/prepare-local-life.sh` fetches that exact revision, runs lockfile install + lint + TypeScript + Vite build, and overrides the old GitHub Pages base with `/`.
- `deploy-local-life.yml` is production-only. It creates a versioned release and atomically swaps `current`. Because the repository also contains staged Caddy changes for other prototype hosts that are not necessarily live, the installer preserves the server's currently validated Caddyfile and replaces only the tracked `local-life.proto.3cgroup.cn` block; validation/restart/local HTTPS failure rolls both Caddy and `current` back.
- Public verification must confirm the actual hostname and at least one built asset. A successful branch merge or build alone is not a live-site acceptance result.

Other product publishing remains owned by its documented workflow; do not use local-life's installer as a generic arbitrary-path deployment primitive.

## Safety

Never store passwords in a committed file or logs. Do not run destructive synchronization by default. Production rollback and Caddy configuration updates require separate validation.
