# Four independent demo passwords

This is a **customer preview authentication** boundary, not a product user-account service.

## Architecture

- Public `proto.3cgroup.cn` portal: no authentication.
- Protected `ai-mirror`, `beauty-mirror`, `hair-mirror`, `fitting-mirror` prototype hostnames: Caddy `basic_auth` with username `demo` and independent bcrypt passwords.
- `/etc/caddy/proto-auth.env`: the only persistent runtime credential store, **root:root 0600**, containing bcrypt hashes only.
- `ops/caddy.service`: loads the root-only envfile via systemd's `EnvironmentFile`. No credential material is committed or included in GitHub Actions logs.
- `scripts/validate-proto-auth.sh`: refuses absent, symlinked, wrong-mode or invalid credential file before Caddy is changed.
- `scripts/install-mirror-batch.sh`: stages files and validates the *new* Caddyfile against installed runtime hashes **before** touching live Caddy. Backs up existing service/config/portal and symlink release pointers; on failures, restores previous state.
- Caddy changes must not be applied via the legacy benefit-only ingress workflow. That workflow has been made manual and continues to reject unrelated Caddy mutations.
- Mirror-batch deployment is **manual `prod` dispatch only**; pushing a PR or branch alone cannot activate new authentication.

## Password bootstrap — private terminal only

First, the `stage-proto-auth.yml` workflow installs the two scripts in `/usr/local/share/proto/`. **It does not change the live Caddy config or create a password file.**

Then, in a private, interactive SSH terminal on the prototype server, execute as root:

```bash
bash /usr/local/share/proto/manage-proto-auth.sh init
```

This requires an attached TTY; invocation from GitHub Actions is deliberately rejected. It generates four independent random 128-bit hexadecimal passwords on the server. It writes only their bcrypt hashes to the root-only envfile. The four **plaintext passwords are printed once to the operator's private terminal** for delivery through an appropriate password manager or other agreed private channel. They cannot be recovered from the hashes afterward.

To rotate one site's password later:

```bash
bash /usr/local/share/proto/manage-proto-auth.sh rotate ai-mirror
```

The rotate path updates one hash, validates the live Caddy config and restarts the Caddy service, with rollback on failure. Do not run with shell tracing, transcript recording, or copied logs.

## Release and acceptance

After credentials exist, manually run **Publish first mirror + companion batch** on `prod` (now manual-only), then verify:

- Public portal: HTTPS 200.
- Each private root, index and static asset without auth: 401.
- Invalid credentials and cross-site credentials: 401.
- Correct site-specific credentials: HTTPS 200 and working browser interactions (manual acceptance; passwords are not provided to public CI).
- Existing Benefit Hub routing and Caddy service remain healthy after restart.
- Repeated release does **not** reset or bypass authentication.

Only after this passes may `base-prototype` canonical public cards migrate to the new password-protected destinations. Retire the four product Pages publishing workflows and unpublish old Pages sites *after* new links and owner acceptance are confirmed; do not retire unrelated Pages or delete repositories. Public GitHub source history is not made private by unpublishing GitHub Pages.

## Safety caveats

HTTP Basic credentials are cached by browsers and may be forwarded by some clients if misconfigured. Serve only over HTTPS. Browser prompts are intentionally not customized. Existing GitHub Pages remain public until individually unpublished. The initial generated passwords should be saved immediately, because the operator cannot retrieve them after leaving the terminal.
