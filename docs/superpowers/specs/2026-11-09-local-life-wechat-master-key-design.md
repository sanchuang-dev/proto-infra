# Local Life WeChat master-key bootstrap design

## Intent
Initialize the existing Local Life MVP API's AES-256-GCM master key so the WeChat public-account admin page can save credentials, without exposing key material or changing business data.

## Goals
- Generate one fresh 32-byte key only when no key is configured.
- Keep the durable key in a dedicated server-side file, not in Git, GitHub Secrets, workflow logs, or the application database.
- Make the existing API container read the key through a read-only file mount.
- Preserve the mount on every later application release.
- Provide an encrypted, recipient-specific backup and a fail-closed rollback path.

## Non-goals
- Do not configure AppID/AppSecret or claim OAuth is working.
- Do not rotate or overwrite an existing key.
- Do not modify SQLite, Caddy, other sites, SSH policy, or application source.

## Approaches considered
1. **Inline environment value in `api.env`** — operationally simple, but the application explicitly recommends `WECHAT_CONFIG_MASTER_KEY_FILE` for deployments. Rejected.
2. **Dedicated key file + read-only Docker bind mount** — matches the application's deployment contract, keeps the key out of ordinary environment values, and can be preserved by the existing installer. Selected.
3. **Introduce a secret manager** — stronger central management, but no secret-manager integration exists in this prototype deployment; it would widen scope and delay the immediate fix. Rejected.

## Selected design
A separately guarded job in the existing `publish-local-life-mvp-app.yml` workflow can run only from `proto-infra@prod`, behind an explicit boolean confirmation and the existing `local-life-mvp` GitHub Environment. The job-free default-branch registration stub receives only the new input declaration so GitHub exposes it in the dispatch form. The runner generates a 32-byte random key, encrypts a backup to a maintainer-supplied 3072-bit RSA public key using OAEP-SHA256, and sends the plaintext base64 only over the pinned SSH connection's stdin.

The server-side script verifies the fixed Local Life MVP paths, current immutable image SHA, running container, file permissions, absence of any prior master-key configuration, and read-only zero-row counts in both `wechat_oauth_configs` and `wechat_identities`. It writes the key to `/srv/proto/local-life-mvp/wechat-secret/master-key.b64` as `root:1000 0440` inside a `root:1000 0750` dedicated directory, adds only the `WECHAT_CONFIG_MASTER_KEY_FILE=/run/local-life-wechat/master-key.b64` pointer to `api.env`, and restarts the same image. The installer mounts that directory read-only on all future deployments. Failure restores the original env file and restarts the same image without the key; if rollback cannot be verified, the workflow fails closed and retains the diagnostic stage.

## Acceptance
A successful run proves the application starts with the 32-byte key file readable by its non-root runtime, API health and existing auth-denial checks pass, the running image SHA is unchanged, and the only downloadable key backup is encrypted for the maintainer. Real AppSecret verification and WeChat OAuth remain separate acceptance steps.
