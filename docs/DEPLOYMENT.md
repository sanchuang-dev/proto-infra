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

A manually dispatched workflow from `prod` only synchronizes the infrastructure portal to `/srv/proto/portal/current`. It does not remotely overwrite the Caddyfile or product build outputs. Product repositories build and publish separately after acceptance. Do not interpret a workflow success alone as confirmation that the live site works.

## Safety

Never store passwords in a committed file or logs. Do not run destructive synchronization by default. Production rollback and Caddy configuration updates require separate validation.
