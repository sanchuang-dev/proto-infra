# Proto Infrastructure repository rules

Organization authority: `sanchuang-dev/.github/AGENTS.md` on current main.

Purpose: company prototype **static hosting only** on an independent Aliyun instance, with Caddy. Never affect the existing primary production server.

- Environment flow: `feat/* → dev → test → prod`. `main` is administrative / landing and must not deploy.
- This repo owns Caddy templates, portal static files, safe setup and deploy scripts. Individual apps own their source/build.
- Domains: `proto.3cgroup.cn`, `<slug>.proto.3cgroup.cn`; explicit Caddy site declarations, no automatic catchall.
- Auth: SSH username/password explicitly requested by maintainer. Do not change login policy without direction. Password must stay in GitHub Secrets, never in code/logs.
- Never disable SSH host key verification, never deploy an arbitrary remote command from untrusted input, and never write directly to unrelated paths.
- No automatic production deployment on PR or dev/test pushes. Require prod source plus explicit dispatch.
- Do not claim production verification without confirmed DNS, HTTPS, SSH and browser checks.
