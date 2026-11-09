#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
installer="$root/scripts/install-local-life-mvp-app.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

test -s "$installer" || fail "installer exists"
bash -n "$installer" || fail "installer syntax"

grep -Fq 'WECHAT_CONFIG_MASTER_KEY_FILE=/run/wechat-config-master-key' "$installer" ||
  fail "installer recognizes the exact file-based master-key setting"
grep -Fq 'target=/run/wechat-config-master-key,readonly' "$installer" ||
  fail "installer mounts the key file read-only"
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

printf 'LOCAL_LIFE_WECHAT_INSTALLER_TEST=PASS\n'
