# Proto Infrastructure repository rules

Organization authority: `sanchuang-dev/.github/AGENTS.md` on current main.

Purpose: company prototype hosting on an independent Aliyun instance, with Caddy. Static snapshots are the default; expressly approved system-level prototypes may have isolated loopback reverse-proxy site declarations here. Never affect the existing primary production server.

- **Benefit Hub exception:** `benefit.proto.3cgroup.cn` is a system-level prototype. Its Hono/React Docker app lives in `sanchuang-dev/benefit-hub`, listens only on host `127.0.0.1:18080`, and has no real vendor fulfillment enabled. This repo owns only its Caddy ingress, not the app image, DB, credentials, or deploy workflow. No implied customer-ready status.

- Environment flow: `feat/* → dev → test → prod`. `main` is administrative / landing and must not deploy.
- This repo owns Caddy templates, portal static files, safe setup and deploy scripts. Individual apps own their source/build.
- Domains: `proto.3cgroup.cn`, `<slug>.proto.3cgroup.cn`; explicit Caddy site declarations, no automatic catchall.
- Auth: SSH username/password explicitly requested by maintainer. Do not change login policy without direction. Password must stay in GitHub Secrets, never in code/logs.
- Never disable SSH host key verification, never deploy an arbitrary remote command from untrusted input, and never write directly to unrelated paths.
- No automatic production deployment on PR or dev/test pushes. Require prod source plus explicit dispatch.
- Do not claim production verification without confirmed DNS, HTTPS, SSH and browser checks.
