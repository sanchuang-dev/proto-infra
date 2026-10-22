# 第一批：镜面 + 闺蜜机原型上线

## Hostnames / Source of Truth

| 原型 | 仓库（源） | 精确部署 Revision | 源静态目录 | 展示地址 |
|---|---|---|---|---|
| 见趣 · 闺蜜机 | sanchuang-dev/ai-mirror | prod @ e4ac70f | web/ | https://ai-mirror.proto.3cgroup.cn/ |
| AI 美妆镜 | sanchuang-dev/ai-beauty-mirror | main @ da7bb94 | prototype/ | https://beauty-mirror.proto.3cgroup.cn/ |
| AI 美发魔镜 | sanchuang-dev/ai-hair-mirror | main @ 1f65f8d | prototype/ | https://hair-mirror.proto.3cgroup.cn/ |
| AI 试衣魔镜 | sanchuang-dev/ai-fitting-mirror | main @ cac9870 | prototype/ | https://fitting-mirror.proto.3cgroup.cn/ |

Full hashes are pinned exclusively in scripts/prepare-mirror-batch.sh. Sources are not copied into infra Git history. Deployment selects only static web/ or prototype/ trees; it never serves repositories or references/ docs.

ai-mirror is explicitly a prototype; its prod here signifies the accepted static demonstration snapshot, not real AI or hardware capabilities. The other three use a repo-local documented main/Pages exception for preliminary reference prototypes and must not be represented as accepted products.

## Deployment

Infra changes: feat/* → dev → test → prod. Only prod is permitted to mutate the server; prod promotion of this first-batch deploy workflow starts release. It also has a manual re-run trigger on prod.

Requires ONLY the existing Repository Secrets: PROTO_HOST, PROTO_USER, PROTO_SSH_PORT, PROTO_SSH_KEY (SSH **password**). No extra keypair.

The hosted runner fetches exactly pinned public Git revisions, archives their static content, and SSH-copies to the isolated prototype server. The server stores versioned releases, swaps current symlinks, validates Caddy and reloads; local reload failure rolls back Caddyfile, homepage, and release pointers. The workflow then checks external HTTPS response HTML and JS assets.

For later product updates, review and change source SHA in prepare-mirror-batch.sh, then promote through branches. Do not auto-deploy arbitrary main/dev heads.

## DNS / ACME

Expected A records: proto and four site hostnames resolve to the new Aliyun server. An existing wildcard *.proto.3cgroup.cn may satisfy them. Caddy provisions normal per-host certs; no wildcard certificate or DNS plugin is needed. Public TCP 80/443 must remain accessible.

If DNS is missing, deployment can still provision static files and Caddy but public verification will fail; correct domain DNS externally, and rerun verification. Never claim successful public HTTPS without real evidence.
