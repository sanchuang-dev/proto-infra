# proto-infra

三创公司原型展示服务器基建：Caddy + 独立子域名 + 静态文件。

- 门户：`proto.3cgroup.cn`
- 原型：`<project>.proto.3cgroup.cn`
- 服务器：公司专属阿里云 2C2G，**不触碰现有主服务器**。
- 部署认证：SSH 账号密码；严禁将密码写入 Git / 日志。
- 分支：`feat/* → dev → test → prod`；只有 `prod` 能触发生产部署。
- 仓库只保留服务器配置和发布脚本；各原型仓库仍独立维护。

参见 [AGENTS.md](AGENTS.md) 和 [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)。

> 当前仅仓库初始化。未提供机器访问参数、DNS 与 GitHub Actions 凭证前，不宣称服务器已上线。
