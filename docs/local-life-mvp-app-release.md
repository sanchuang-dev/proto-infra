# Local Life MVP app release · trusted infra executor

This is the trusted deployment executor for reviewed application artifacts from `sanchuang-dev/local-life@mvp`. The existing Caddy ingress has already been installed on the company's independent prototype server through proto-infra's manually dispatched `prod` workflow.

## Ownership and trust

- Product source, migrations, Dockerfile, tests and the immutable SHA are owned by `local-life`.
- The **only** holder of prototype SSH secrets remains `proto-infra`. No SSH secret is copied to application Actions. The app source is publicly readable and the protected `mvp` branch is the sole admitted source.
- The `package` job checks out `mvp`, pins its exact commit SHA, runs frozen install and real checks, independently builds web/admin at `/` and the Linux API image, and uploads a same-run artifact. This job has **no SSH secrets**.
- The trusted `publish` job checks out `proto-infra@prod` only, receives verified same-run artifacts, and uses the repository's pinned host identity to publish.
- This workflow is **manual-only** and only runs its publishing jobs from `proto-infra@prod` with `publish=true`. It is not yet the approved `local-life@mvp` push-to-deploy automation, which requires a narrowly scoped cross-repository dispatch credential. No wide-scope personal access token should be reused.

## Layout

- `/srv/proto/local-life-mvp/releases/<sha>/web`
- `/srv/proto/local-life-mvp/releases/<sha>/admin`
- `/srv/proto/local-life-mvp/web/current` and `admin/current` are atomically replaced symlinks.
- One container `local-life-mvp-api` publishes only `127.0.0.1:18081`, internal port 4080.
- SQLite persists in `/srv/proto/local-life-mvp/data/local-life.sqlite` with restricted root-owned backups; config in `/srv/proto/local-life-mvp/config/api.env`.
- Container is non-root uid 1000 with read-only rootfs, no capabilities, fixed CPU/memory/pid/log bounds.
- Static artifacts are normalized to Caddy-readable directory/file modes after extraction, independent of the SSH user's umask; the installer verifies the Caddy service account can traverse and read both entrypoints before switching.
- Fresh config is generated only if missing. `NODE_ENV=production`, `AUTH_DEV_ENABLED=false`, exact two trusted origins, **no shared COOKIE_DOMAIN**. CRMEB credentials stay absent. The WeChat master key is initialized only by the prod-only OPS-008 bootstrap job, stored in `/srv/proto/local-life-mvp/wechat-secret` and mounted read-only into the API; AppID/AppSecret remain absent until configured by an administrator in the WeChat settings page. See `docs/local-life-mvp-wechat-master-key.md`.

## Release gates

1. A reviewed `dev → mvp` PR must be merged. Build from the exact latest protected `mvp` commit, not an arbitrary source SHA.
2. CI packages immutable two static sites + Linux API image on GitHub-hosted runner. No production secret is present during checkout/build.
3. On the host, reject unexpected Caddy sites/current directory shapes; normalize public file permissions regardless of remote umask and verify Caddy can read both roots; perform native SQLite WAL-aware online backup; verify `PRAGMA quick_check`.
4. Test the candidate image migrations on a *backup copy* with the container's native driver; then stop the previous writer, start exactly one new writer and verify genuine HTTP health and authentication rejections.
5. Switch both static `current` pointers only after API is healthy. Check both public origins' HTTPS, actual `/api/healthz`, their static assets, unauthenticated protected path, and existing old Local Life/Benefit/portal sites.
6. Finalize the SHA only after checks; first deployment writes and validates a seed SQLite backup, including retries after an app rollback.
7. Failure requests a bounded rollback. Revert static pointers; restart the previous API only if the migration count has not changed, otherwise fail closed without reverting or overwriting actual SQLite data. Never restore old DB unconditionally.

## Limits

The first release **does not** create an administrator account or configure external WeChat OAuth, CRMEB outapi, prizes, payout or payment. The OPS-008 key bootstrap only makes encrypted credential storage available; it does not configure a real public account or prove OAuth. Such capabilities must show their existing unavailable state. End-to-end acceptance remains on local-life #65; empty-but-working API+UI is not business acceptance.

For automatic post-merge releases, provision **a dedicated fine-grained token or GitHub App installation limited to `proto-infra` Actions:write**, stored as an **environment-scoped secret** in `local-life@mvp`. Then a small `mvp` push workflow can dispatch this trusted prod-only publisher. Do not use or copy the existing high-privilege `PROTO_*` secrets or the maintainer's personal `gh` login token.
