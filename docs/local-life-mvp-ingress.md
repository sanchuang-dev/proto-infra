# Local Life online MVP · Caddy ingress rollout

This is a **one-time, explicitly dispatched** ingress release for the two independently hosted application origins. The source of truth for the two additions is [`ops/local-life-mvp.caddy`](../ops/local-life-mvp.caddy); the existing `Caddyfile` and its legacy static prototype publisher are intentionally untouched.

## Authorized scope

- Resident: `https://local.proto.3cgroup.cn/` → `/srv/proto/local-life-mvp/web/current`
- Admin: `https://local-admin.proto.3cgroup.cn/` → `/srv/proto/local-life-mvp/admin/current`
- Each `/api/*` strips `/api` and reverse-proxies to **the same host-local** Hono service `127.0.0.1:18081`.
- Creates isolated `web`, `admin`, `releases`, `data`, `backups`, `config` directories. Data/backups/config directories are root-only initially and **must stay outside all release cleanup**.
- The initial Caddy-only release must return valid TLS and an honest **404** for the empty UI roots. This is **not** evidence that the MVP app is deployed or usable.

## Release discipline

1. Review and merge through `feat/* → dev → test → prod`, checking the Caddy fragment and bounded installer on every promotion.
2. Run **Publish Local Life MVP ingress (controlled)** with `ref=prod` and `publish=true` only after explicit maintainer authorization. GitHub requires a same-name `workflow_dispatch` registration on the default `main`; that registration contains a permanently skipped job and cannot deploy.
3. The publisher checks current old-site HTTPS, pinned SSH host identity, exact target host, and current Caddy host declarations. It appends only the reviewed new host blocks to the **current live** Caddyfile, validates, reloads Caddy, then verifies new TLS and old sites.
4. If verification fails, it restores the previous Caddyfile **only if the live file still matches the candidate**. Concurrent out-of-band drift fails closed.
5. The GitHub Actions run gives the deployment evidence. Do not claim online UI/API until local-life owns and deploys versioned H5/Admin/API artifacts and checks SQLite backup/restore.

## Deliberate boundaries

- Do not reuse `.github/workflows/deploy-local-life.yml`, which publishes the old `local-life.proto.3cgroup.cn` static prototype.
- Do not copy the infrastructure SSH secrets into the `local-life` repository.
- Do not deploy a dummy API or a fake authentication service to make health checks green.
- API runtime and `mvp` push automation remain owned by `local-life`; the initial API container may be deployed only after the actual application artifact and migration/backup/rollback contract have been reviewed.
- Do not replace the whole shared Caddyfile with the checked-in template; it may include staged changes that are not live.
