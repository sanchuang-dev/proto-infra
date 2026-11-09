# Local Life MVP · 微信凭证加密主密钥初始化

## 目的与边界

这项运维只初始化 Local Life API 用来加密公众号 AppSecret 的 AES-256-GCM 主密钥。它不配置公众号 AppID/AppSecret，也不代表微信 OAuth 已经验收。

- 主密钥由受控 workflow 在临时 GitHub-hosted runner 生成，长度为 32 随机字节。
- 明文只通过固定 SSH host fingerprint 的连接 stdin 传到服务器。
- GitHub Actions artifact 只保存维护者 RSA 公钥加密后的备份。
- 服务器不把密钥写入 Git、GitHub Secrets、SQLite 或普通日志。
- 初始化是一次性的：发现已有密钥配置或 secret 目录时直接拒绝，不执行覆盖或轮换。

## 服务器存储与容器挂载

| 项目 | 约定 |
| --- | --- |
| 主机密钥文件 | **/srv/proto/local-life-mvp/wechat-secret/master-key.b64** |
| 主机目录权限 | **root:1000，0750** |
| 主机文件权限 | **root:1000，0440** |
| API 容器只读挂载 | **/run/local-life-wechat** |
| API 环境变量 | **WECHAT_CONFIG_MASTER_KEY_FILE=/run/local-life-wechat/master-key.b64** |
| api.env 权限 | **0600** |
| key generation label | 保留现有 WECHAT_CONFIG_KEY_ID；未设置时初始化为 v1 |

API 仍以 uid/gid 1000:1000 运行。secret 目录和文件仅允许 root 与 API 运行组读取；容器内挂载为 read-only。后续正常应用发布会继续挂载同一目录。

初始化只重启 /srv/proto/local-life-mvp/current.sha 对应的现有 API 镜像，不构建镜像、不迁移或修改 SQLite、不切换静态站点、不修改 Caddy 或其它原型服务。

## 准备接收者密钥

在你控制的 Mac 或可信 Linux 设备上执行。私钥和私钥口令始终留在本机，不上传到 GitHub。

~~~sh
umask 077

# 生成带口令保护的 RSA-3072 私钥；OpenSSL 会交互式要求设置口令
openssl genpkey -algorithm RSA \
  -pkeyopt rsa_keygen_bits:3072 \
  -aes-256-cbc \
  -out wechat-master-key-private.pem

# 导出公钥
openssl pkey -in wechat-master-key-private.pem \
  -pubout -out wechat-master-key-public.pem

# 生成单行 base64，复制输出作为 workflow 输入
base64 < wechat-master-key-public.pem | tr -d '\n'
~~~

不要把 wechat-master-key-private.pem 或私钥口令发给我、放进 Issue/PR、上传到 Actions artifact。只有公钥的 base64 会作为 workflow input 提交。

## 执行一次性初始化

在 GitHub 打开 sanchuang-dev/proto-infra：

1. 进入 Actions → Publish Local Life MVP app (controlled)。
2. 选择 Run workflow，分支必须是 prod。
3. 保持 publish=false、bootstrap_admin=false。
4. 设置 bootstrap_wechat_master_key=true。
5. 将上一步的公钥 base64 填入 recipient_public_key_b64。
6. 启动 workflow；如 local-life-mvp Environment 要求审批，按组织的正常授权完成审批。

工作流会先核对固定服务器、SSH host fingerprint、当前容器镜像 SHA、API 健康状态和密钥不存在，再生成密钥、加密备份并执行服务器初始化。任何已有密钥配置都会触发拒绝，不会覆盖。

成功日志必须同时包含：

- MVP_WECHAT_MASTER_KEY_INITIALIZED=yes
- MVP_API_RESTART_VERIFIED_SHA=<current SHA>
- MVP_WECHAT_MASTER_KEY_PUBLIC_HEALTH_AND_AUTH=PASS

如果出现 MVP_WECHAT_MASTER_KEY_ROLLBACK_VERIFIED=yes，表示初始化失败但原配置和 API 已恢复；该次生成的加密 artifact 不应被当作已启用密钥。如果出现 MVP_WECHAT_MASTER_KEY_ROLLBACK_FAILED=operator_attention_required，不要再次运行或清理服务器临时目录，先由维护者检查现场。

## 下载并离线保管加密备份

成功或发生回滚故障时，下载对应 run 的 artifact：

**local-life-mvp-wechat-master-key-backup-<run id>**

artifact 保留 7 天，内容只有：

- master-key.enc：RSA-OAEP-SHA256 加密后的主密钥；
- README.md：本机解密说明。

在持有匹配私钥的本机目录解密：

~~~sh
openssl pkeyutl -decrypt \
  -inkey ./wechat-master-key-private.pem \
  -in ./master-key.enc \
  -out ./master-key.b64 \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256

# 只校验长度，不输出密钥内容
test "$(base64 --decode < ./master-key.b64 | wc -c | tr -d '[:space:]')" = 32
~~~

只有当 workflow 日志包含 MVP_WECHAT_MASTER_KEY_INITIALIZED=yes 时，才把这份备份视为服务器当前启用的主密钥。将解密后的 master-key.b64 存入加密密码库或离线安全备份；不要粘贴到聊天、Issue、PR、终端截图或普通云盘。保留私钥及其口令，或在确认明文备份已安全保存后按你的密钥保管政策处置私钥。

**不要重新生成一把新密钥来“修复”已有配置。** SQLite 中的 AppSecret 密文依赖原主密钥；丢失密钥会导致这些凭证无法解密。轮换必须另行设计、备份并验收。

## 初始化后的下一步：配置真实公众号

初始化完成后：

1. 刷新 https://local-admin.proto.3cgroup.cn/ 的微信公众号设置页。
2. 确认“凭证加密主密钥不可用”提示消失，新增公众号操作可用。
3. 在微信公众平台重置此前有泄露风险的 AppSecret。
4. 直接在后台填写 AppID / 新 AppSecret，执行真实连接验证并显式启用。
5. 再验收微信内 H5 授权、OAuth 回调、居民身份复用、Cookie 会话和活动邀请回跳。

AppSecret 不应通过聊天、Issue、PR、workflow input 或仓库配置传递。主密钥初始化成功不等于真实微信登录成功；真实登录必须单独真机验收。
