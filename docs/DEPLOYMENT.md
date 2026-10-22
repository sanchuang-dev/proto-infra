# Prototype infrastructure deployment

## Prerequisites

Independent Aliyun Linux server with public IPv4, SSH username/password, and Caddy. Point DNS for `proto.3cgroup.cn` and explicitly configured subdomains to this server. Allow inbound TCP 80/443.

## GitHub Actions configuration

| Kind | Name | Meaning |
|---|---|---|
| Variable | `PROTO_HOST` | Server public IP |
| Variable | `PROTO_USER` | SSH username |
| Variable | `PROTO_SSH_PORT` | SSH port, normally 22 |
| Secret | `PROTO_PASSWORD` | SSH password |

Only four fields. No private SSH key and no manually configured known-hosts secret.

The workflow uses OpenSSH `StrictHostKeyChecking=accept-new` so the first presented host identity is accepted automatically. This *trust-on-first-use* mode removes setup work but **does not independently verify server identity at the first connection**. Hosted GitHub runners are ephemeral, so each run has the same first-connection exposure. Do not describe this as providing verified host authenticity.

## First server setup (administrator)

1. Inspect the *new prototype instance*, its operating system and existing services before changing anything.
2. Install Caddy; set `ACME_EMAIL` in the Caddy service environment.
3. Prepare `/srv/proto/{portal,local-life,ai-mirror,college}/current`, with scoped write access for the login user.
4. Validate the repository Caddyfile before installing it to `/etc/caddy/Caddyfile`. Reload Caddy after validation.
5. Verify DNS, HTTPS and SPA refresh via actual external requests.

## Releases

A manually dispatched workflow from `prod` only synchronizes the infrastructure portal to `/srv/proto/portal/current`. It does not remotely overwrite the Caddyfile or product build outputs. Product repositories build and publish separately after acceptance. Do not interpret a workflow success alone as confirmation that the live site works.

## Safety

Never store passwords in a committed file or logs. Do not run destructive synchronization by default. Production rollback and Caddy configuration updates require separate validation.
