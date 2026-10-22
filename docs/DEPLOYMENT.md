# Prototype infrastructure deployment

## Prerequisites

An independent Aliyun instance with Linux, public IPv4, SSH username/password and Caddy installed. DNS records for `proto.3cgroup.cn` and each desired project host must point to this instance. Open inbound TCP 80/443 for ACME and HTTPS.

**Login is SSH password** as requested, without forcing SSH key migration. Use a limited-purpose account where possible. Don't commit passwords or Aliyun console credentials.

## GitHub Actions secrets & variables (in proto-infra)

| Kind | Name | Meaning |
|---|---|---|
| Variable | `PROTO_HOST` | IP or SSH hostname |
| Variable | `PROTO_USER` | SSH login user |
| Variable | `PROTO_SSH_PORT` | SSH port, e.g. 22 |
| Secret | `PROTO_PASSWORD` | SSH login password |
| Secret | `PROTO_KNOWN_HOSTS` | Verified ssh-keyscan known_hosts entry, obtained by checking fingerprint through trusted out-of-band channel |

## First server setup (manual, privileged)

1. Install Caddy on the independent server; configure ACME account email as Caddy environment variable `ACME_EMAIL`.
2. Create `/srv/proto/{portal,local-life,ai-mirror,college}/current`; grant the deployment user write permission only where needed.
3. Install Caddyfile as `/etc/caddy/Caddyfile` after `caddy validate --config Caddyfile`; `systemctl reload caddy`.
4. Ensure host DNS and 80/443 access are configured; inspect Caddy logs and verify live HTTPS.
5. Do not replace an existing Caddyfile or broad server permissions without inspecting the machine.

## Ongoing release

The GitHub manual workflow checks out `prod` and syncs the infrastructure-owned `portal/` files only, to `/srv/proto/portal/current`. Caddy deployment is deliberately a separate server-admin step until an authenticated, privilege-scoped config reload strategy has been verified.

Each product repository builds its own static distribution and can later invoke a controlled upload mechanism, independent of the infra portal. Don't copy product source into this repository.

## Safety and rollback

Files are synced without deletion; stale content may require operator review. Use versioned release directories and atomic switching before enabling deletion or automatic rollback. No workflow job alone establishes that the runtime is healthy.
