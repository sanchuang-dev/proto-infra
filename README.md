# proto-infra

三创公司原型展示服务器基建：Caddy + 独立子域名。多数原型为静态文件，**系统级原型**可按项目例外反代到宿主机隔离服务。

- 门户：`proto.3cgroup.cn`
- 原型：`<project>.proto.3cgroup.cn`
- 服务器：公司专属阿里云 2C2G，**不触碰现有主服务器**。
- 部署认证：SSH 账号密码；严禁将密码写入 Git / 日志。
- 分支：`feat/* → dev → test → prod`；只有 `prod` 能触发生产部署。
- 仓库只保留服务器配置和发布脚本；各原型仓库仍独立维护。

参见 [AGENTS.md](AGENTS.md) 和 [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)。

## 系统级原型

- `benefit.proto.3cgroup.cn`：Benefit Hub 权益供应与运营平台的**系统级原型**，不是正式用户服务。运行代码与 Docker/SQLite 由 [sanchuang-dev/benefit-hub](https://github.com/sanchuang-dev/benefit-hub) 独立维护，现阶段不启用真实发券。
- 本仓库只管理其 Caddy 反代入口（宿主机 `127.0.0.1:18080`）。站点加入前必须确保后端健康、Caddy 现有配置无未登记漂移；上线后验证本域名、现有原型 HTTPS，以及 noindex 头。
- 演示中心入口页仍由 `base-prototype` 的实验室页面模型生成；将 Benefit Hub 增加到门户卡片是**另一项产品编辑决定**，不因添加域名自动修改页面布局或卡片数量。

## 静态原型发布

- `local-life.proto.3cgroup.cn`：本地生活移动端原型。源代码仍由 `sanchuang-dev/local-life` 维护；本仓库仅固定已验收 `prod` revision、以根路径重新构建并发布到 `/srv/proto/local-life/current`。
- local-life 不自动跟随上游分支 HEAD。更新展示版本时先在产品仓库走 `dev → test → prod`，再更新本仓库的固定 revision，并继续走本仓库 `dev → test → prod`。

