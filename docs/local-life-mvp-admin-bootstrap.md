# Local Life MVP · 首个管理员安全初始化

`admin` 是 Local Life **应用内部**的最高后台角色：可管理全部社区并创建/管理运营员与网格员。它不授予服务器、GitHub Organization 或云账号权限。

## 约束

- 只在 `proto-infra@prod` 手动运行受控发布工作流的 `bootstrap_admin` 分支；绑定 `local-life-mvp` Environment 和已固定 SSH host key 的 infra 凭证。
- 仅当 `/srv/proto/local-life-mvp/data/local-life.sqlite` 中不存在任何 `admin` 账户时才继续；包含 disabled admin 也拒绝。并发运行由生产发布 concurrency group 串行化，应用初始化命令自身再次检查。
- 通过运行中 API 容器内的 `dist/scripts/bootstrap-admin.js` 初始化，不绕过应用脚本。命令使用 scrypt 哈希、数据库事务和 `staff.bootstrap_admin` 审计事件；密码输入不回显。
- 64 位随机十六进制初始密码只在 runner 内存/权限 0600 的临时文件中短暂存在；日志添加 mask。仅用调用方临时 RSA-3072 公钥 + OAEP-SHA256 加密后上传 1 天 artifact。artifact 不含明文密码或服务器凭证。
- 创建后核验账号 role/status 与审计事件，并通过后台 HTTPS Origin 执行真实 CSRF 登录、role 检查和登出。登录失败不删除账号或回滚数据库。
- 不创建默认密码，不打印密码，不把密码放在 workflow input、Issue、PR、日志或仓库。

## 使用方式

1. 在受信任设备生成一次性 RSA-3072 密钥对，私钥仅保存在本机权限受限位置；向 workflow 提交公钥 PEM 的 base64。公钥不是秘密。
2. 在 `proto-infra` 的 `prod` 分支手动运行 `Publish Local Life MVP app (controlled)`，设置 `publish=false`、`bootstrap_admin=true`、用户名、显示名和公钥 base64。
3. 下载 `local-life-mvp-admin-bootstrap-<run id>` artifact。它只含用户名和 RSA 加密的初始密码。
4. 在本机用一次性私钥解密，并将密码存入本机 Keychain；确认保存成功后删除私钥和解密临时文件。
5. 登录 `https://local-admin.proto.3cgroup.cn/` 后，正常创建运营员/网格员。不要共享管理员凭证。

若数据库已有管理员，工作流会拒绝创建；使用现有管理员账户管理后续账号，不提供重置/覆盖路径。
