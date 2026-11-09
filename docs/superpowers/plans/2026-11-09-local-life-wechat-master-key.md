# Local Life WeChat master-key bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Safely initialize the Local Life MVP WeChat encryption key once and preserve it across future API releases.

**Architecture:** A prod-only manual workflow creates the key and an RSA-OAEP encrypted backup, then streams the plaintext over pinned SSH stdin to a bounded server script. The server stores a root-owned, API-group-readable key file, points the API config at it, and restarts the exact currently deployed image. The regular installer mounts the file read-only on future releases.

**Tech Stack:** GitHub Actions, Bash, OpenSSL, SSH, Docker, existing Local Life Hono API.

**Spec:** `docs/superpowers/specs/2026-11-09-local-life-wechat-master-key-design.md`

## Global Constraints
- Source implementation base is `dev`; environment flow remains `feat/* → dev → test → prod`.
- The only deployment host is the currently approved prototype host, and its SSH fingerprint must match the pinned value already used by proto-infra.
- The key is exactly 32 random bytes, encoded as base64 for `WECHAT_CONFIG_MASTER_KEY_FILE`.
- The server key file is `root:1000` mode `0440`; `api.env` remains mode `0600`.
- The container remains non-root and receives the key only through a read-only bind mount.
- No key value may appear in logs, command arguments, Issues, PRs, or plaintext artifacts.
- Initialization must refuse to overwrite any existing key or key configuration.
- The restart must use the exact SHA recorded in `/srv/proto/local-life-mvp/current.sha`; no image build, database migration, or data write is allowed.

## Review Focus
- Existing inline/file master-key configuration or an orphan key file: initialization refuses before mutation.
- Invalid public key or non-3072-bit RSA key: workflow stops before SSH.
- Unreadable/malformed server key file: container health fails and rollback restores the previous config.
- Existing API container SHA drift: restart refuses instead of silently deploying another image.
- Future normal release: installer keeps mounting the same key file and fails closed if env/file state drifts.

---

### Task 1: Preserve file-based master-key mount in the API installer

**Files:**
- Modify: `scripts/install-local-life-mvp-app.sh`
- Test: `scripts/test-local-life-wechat-key-bootstrap.sh`

**Interfaces:**
- `start_api(image)` mounts `$base/config/wechat-config-master-key` read-only at `/run/wechat-config-master-key` only when `api.env` contains the exact file-path setting.
- New `restart` mode accepts the existing bounded stage path and exact current SHA, refuses image/container drift, and performs the same local health/security checks as a normal deploy.

- [ ] Add a failing static regression check for the file mount, path consistency, and restart mode.
- [ ] Run the test and confirm it fails because the installer does not yet implement the contract.
- [ ] Update `start_api` with the optional read-only bind mount and strict env/file consistency checks.
- [ ] Add the bounded `restart` mode that uses only the current immutable image.
- [ ] Run the test and `bash -n scripts/install-local-life-mvp-app.sh`.

### Task 2: Add the one-time server bootstrap and protected workflow

**Files:**
- Create: `scripts/bootstrap-local-life-wechat-master-key.sh`
- Modify: `.github/workflows/publish-local-life-mvp-app.yml` (prod-only job and new dispatch input)
- Test: `scripts/test-local-life-wechat-key-bootstrap.sh`

**Interfaces:**
- The remote script accepts `apply <stage> <installer>`; the key is read from stdin, never an argument.
- The existing controlled workflow input `bootstrap_wechat_master_key` defaults to `false`; the privileged job runs only for `workflow_dispatch` from `refs/heads/prod` with the input set to true and both other action inputs false.
- The workflow requires a base64-encoded 3072-bit RSA public key; the encrypted backup uses RSA-OAEP with SHA-256 and is the only key-bearing artifact.

- [ ] Extend the regression test with workflow gates, host fingerprint, no-plaintext-artifact and rollback assertions.
- [ ] Run the test and confirm it fails before the workflow/script exist.
- [ ] Implement the remote preflight, atomic file/config write, same-SHA restart, and bounded rollback.
- [ ] Implement runner-side key generation, recipient encryption, pinned SSH, public health checks, and encrypted artifact upload.
- [ ] Run the regression test and `bash -n` on both scripts.

### Task 3: Register the input on main, document the operational handoff, and verify the branch

**Files:**
- Create: `docs/local-life-mvp-wechat-master-key.md`
- Modify: `.github/workflows/bootstrap-local-life-wechat-master-key.yml` only if validation reveals a defect.

- [ ] Add a separate PR for the job-free main-branch registration stub, adding only the new dispatch input and preserving the registration-only job.\n- [ ] Document public-key creation, encrypted artifact decryption, key backup custody, one-time execution, and the separate AppSecret/OAuth acceptance.
- [ ] Run all repository shell-script checks relevant to the changed files and inspect the complete diff.
- [ ] Confirm the workflow contains no automatic deploy trigger and no secret value in repository content.
- [ ] Create the PR against `dev`; retain the Issue open until online initialization evidence exists.

## Verification commands
- `bash -n scripts/install-local-life-mvp-app.sh scripts/bootstrap-local-life-wechat-master-key.sh scripts/test-local-life-wechat-key-bootstrap.sh`
- `bash scripts/test-local-life-wechat-key-bootstrap.sh`
- GitHub Actions PR validation for the changed workflow paths.
- After controlled promotion, manually dispatch the workflow from `prod` and verify its actual run, API health, unchanged SHA, and encrypted backup artifact.
