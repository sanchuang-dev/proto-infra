#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
installer="$root/scripts/install-local-life-mvp-app.sh"
bootstrap="$root/scripts/bootstrap-local-life-wechat-master-key.sh"
workflow="$root/.github/workflows/publish-local-life-mvp-app.yml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

test -s "$installer" || fail "installer exists"
bash -n "$installer" || fail "installer syntax"

grep -Fq 'WECHAT_CONFIG_MASTER_KEY_FILE=/run/local-life-wechat/master-key.b64' "$installer" ||
  fail "installer recognizes the exact file-based master-key setting"
grep -Fq 'target=/run/local-life-wechat,readonly' "$installer" ||
  fail "installer mounts the key file read-only"
grep -Fq 'Unexpected entries in WeChat master-key directory' "$installer" ||
  fail "installer rejects unexpected files in the mounted secret directory"
grep -Fq 'test ! -L "$secret_dir"' "$installer" ||
  fail "installer rejects a symlinked secret directory"
grep -Fq 'WECHAT_CONFIG_MASTER_KEY(_FILE)?' "$installer" ||
  fail "installer rejects inline production key configuration"
grep -Fq 'restart)' "$installer" ||
  fail "installer has a bounded API restart mode"
grep -Fq 'MVP_API_RESTART_VERIFIED_SHA=' "$installer" ||
  fail "restart mode reports the exact verified image SHA"
grep -Fq 'docker inspect -f' "$installer" ||
  fail "restart mode checks any existing container image before replacing it"
! grep -Fq 'docker inspect -f '\''{{.State.Running}}'\'' "$container" | grep -qx true' "$installer" ||
  fail "restart mode can recover when a failed candidate container is stopped or absent"


test -s "$bootstrap" || fail "one-time bootstrap script exists"
bash -n "$bootstrap" || fail "bootstrap script syntax"
grep -Fq 'IFS= read -r key_b64' "$bootstrap" ||
  fail "bootstrap reads the key from stdin, not command arguments"
grep -Fq 'WECHAT_CONFIG_MASTER_KEY_FILE=/run/local-life-wechat/master-key.b64' "$bootstrap" ||
  fail "bootstrap configures the file-based master-key path"
grep -Fq 'MVP_WECHAT_MASTER_KEY_ROLLBACK_VERIFIED=yes' "$bootstrap" ||
  fail "bootstrap verifies rollback when restart fails"
grep -Fq 'sqlite3 -readonly' "$bootstrap" ||
  fail "bootstrap reads SQLite only in read-only mode"
grep -Fq 'SELECT COUNT(*) FROM wechat_oauth_configs' "$bootstrap" ||
  fail "bootstrap refuses to re-key existing encrypted credential rows"
grep -Fq 'SELECT COUNT(*) FROM wechat_identities' "$bootstrap" ||
  fail "bootstrap refuses to replace an existing WeChat identity history"

test -s "$workflow" || fail "controlled production workflow exists"
grep -Fq 'bootstrap_wechat_master_key:' "$workflow" ||
  fail "controlled workflow exposes a separate key-bootstrap action"
grep -Fq "inputs.bootstrap_wechat_master_key == true" "$workflow" ||
  fail "key-bootstrap job requires explicit confirmation"
grep -Fq "github.ref == 'refs/heads/prod'" "$workflow" ||
  fail "key-bootstrap job is prod-only"
grep -Fq 'openssl pkeyutl -encrypt' "$workflow" ||
  fail "workflow encrypts the backup for the recipient"
grep -Fq 'pkeyopt rsa_oaep_md:sha256' "$workflow" ||
  fail "workflow uses OAEP-SHA256"
grep -Fq 'retention-days: 7' "$workflow" ||
  fail "workflow retains only a short-lived encrypted backup"
prepare_line="$(grep -nF 'id: prepare_key' "$workflow" | cut -d: -f1)"
backup_line="$(grep -nF 'name: Upload only the recipient-encrypted master-key backup' "$workflow" | cut -d: -f1)"
apply_line="$(grep -nF 'id: apply' "$workflow" | cut -d: -f1)"
test "$prepare_line" -lt "$backup_line" && test "$backup_line" -lt "$apply_line" ||
  fail "encrypted backup is uploaded before the server is mutated"
! grep -Fq 'STAGE: ${{ env.STAGE }}' "$workflow" ||
  fail "workflow does not resolve a runner-generated stage through server-side expressions"
grep -Fq 'if [[ -z "${STAGE:-}" ]]' "$workflow" ||
  fail "cleanup handles an absent runtime stage without leaving a temp directory"
! grep -Eq '(^|[[:space:]])set -x' "$bootstrap" "$workflow" ||
  fail "workflow and bootstrap do not enable shell tracing"
! grep -Fq 'echo "$key_b64"' "$bootstrap" "$workflow" ||
  fail "workflow and bootstrap do not print key material"
grep -Fq '::add-mask::$key_b64' "$workflow" ||
  fail "workflow masks the generated key in runner logs"

printf 'LOCAL_LIFE_WECHAT_KEY_BOOTSTRAP_TEST=PASS\n'

