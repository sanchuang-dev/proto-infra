#!/usr/bin/env bash
# One-time Local Life MVP WeChat master-key initialization.
# The key is supplied only on stdin; never pass it as an argument or print it.
set -Eeuo pipefail
umask 077

mode="${1:?mode}"
stage="${2:?stage}"
installer="${3:?installer}"

base=/srv/proto/local-life-mvp
config_dir="$base/config"
env_file="$config_dir/api.env"
key_file="$config_dir/wechat-config-master-key"
container=local-life-mvp-api
sha_file="$base/current.sha"

[[ "$stage" =~ ^/tmp/local-life-mvp-release\.[A-Za-z0-9]+$ ]] || {
    echo 'Invalid temporary stage path' >&2
    exit 1
}
test "$installer" = "$stage/install-local-life-mvp-app.sh" || {
    echo 'Unexpected installer path' >&2
    exit 1
}
test -d "$stage"
test "$(id -u)" -eq 0 || {
    echo 'Bootstrap must run as root' >&2
    exit 1
}
test "$(stat -c '%u:%a' "$stage")" = '0:700' || {
    echo 'Temporary stage must be root-owned mode 0700' >&2
    exit 1
}

sha=''
image=''
mutated=0
cleanup_stage=1
tmp_key=''
tmp_env=''

preflight() {
    test -s "$installer"
    bash -n "$installer"
    test -s "$env_file"
    test ! -L "$env_file"
    test "$(stat -c '%a' "$env_file")" = 600
    test "$(stat -c '%a' "$config_dir")" = 700
    grep -Fxq 'NODE_ENV=production' "$env_file"
    grep -Fxq 'AUTH_DEV_ENABLED=false' "$env_file"
    ! grep -Eq '^COOKIE_DOMAIN=' "$env_file"

    if grep -Eq '^[[:space:]]*WECHAT_CONFIG_MASTER_KEY(_FILE)?[[:space:]]*=' "$env_file"; then
        echo 'A WeChat master-key setting already exists; refusing overwrite or rotation' >&2
        return 1
    fi
    if test -e "$key_file" || test -L "$key_file"; then
        echo 'A WeChat master-key file already exists; refusing overwrite or rotation' >&2
        return 1
    fi

    sha="$(cat "$sha_file")"
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || {
        echo 'Current Local Life MVP SHA is invalid' >&2
        return 1
    }
    image="local-life-mvp-api:$sha"
    docker image inspect "$image" >/dev/null
    docker inspect -f '{{.State.Running}}' "$container" | grep -qx true
    test "$(docker inspect -f '{{.Config.Image}}' "$container")" = "$image"
    mount_state="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/run/wechat-config-master-key"}}present{{end}}{{end}}' "$container")"
    test -z "$mount_state"

    curl -fsS --max-time 5 http://127.0.0.1:18081/healthz |
        grep -Fq '"service":"local-life-api"'
    test "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
        http://127.0.0.1:18081/admin/communities)" = 401
    curl -fsS --max-time 5 http://127.0.0.1:18081/auth/methods |
        grep -Fq '"developmentResidentLogin":false'
}

rollback() {
    local rollback_env="$config_dir/.api.env.wechat-rollback.$$"
    cp "$stage/api.env.before" "$rollback_env" || return 1
    chown root:root "$rollback_env" || return 1
    chmod 0600 "$rollback_env" || return 1
    mv -f "$rollback_env" "$env_file" || return 1
    rm -f "$key_file" || return 1

    if bash "$installer" restart "$stage" "$sha"; then
        mutated=0
        echo 'MVP_WECHAT_MASTER_KEY_ROLLBACK_VERIFIED=yes'
        return 0
    fi
    return 1
}

on_exit() {
    local status=$?
    trap - EXIT INT TERM

    if test "$status" -ne 0 && test "$mutated" = 1; then
        if ! rollback; then
            cleanup_stage=0
            echo 'MVP_WECHAT_MASTER_KEY_ROLLBACK_FAILED=operator_attention_required' >&2
        fi
    fi

    if test -n "$tmp_key"; then rm -f "$tmp_key"; fi
    if test -n "$tmp_env"; then rm -f "$tmp_env"; fi
    if test "$cleanup_stage" = 1; then rm -rf -- "$stage"; fi
    exit "$status"
}

case "$mode" in
  preflight)
    preflight
    echo 'MVP_WECHAT_MASTER_KEY_PREFLIGHT=PASS'
    ;;
  apply)
    trap on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    preflight

    IFS= read -r key_b64 || {
        echo 'Master key was not supplied on stdin' >&2
        exit 1
    }
    if IFS= read -r extra; then
        echo 'Unexpected extra input after the master key' >&2
        exit 1
    fi
    [[ "$key_b64" =~ ^[A-Za-z0-9+/]{43}=$ ]] || {
        echo 'Master key must be canonical base64 for exactly 32 bytes' >&2
        exit 1
    }
    decoded_size="$(printf '%s' "$key_b64" | base64 --decode | wc -c | tr -d '[:space:]')"
    test "$decoded_size" = 32 || {
        echo 'Master key must decode to exactly 32 bytes' >&2
        exit 1
    }
    canonical="$(printf '%s' "$key_b64" | base64 --decode | base64 | tr -d '\n')"
    test "$canonical" = "$key_b64" || {
        echo 'Master key base64 is not canonical' >&2
        exit 1
    }

    key_id_count="$(grep -Ec '^[[:space:]]*WECHAT_CONFIG_KEY_ID[[:space:]]*=' "$env_file" || true)"
    case "$key_id_count" in
      0)
        key_id='v1'
        ;;
      1)
        key_id="$(grep -E '^[[:space:]]*WECHAT_CONFIG_KEY_ID[[:space:]]*=' "$env_file" |
            tail -n 1 | sed -E 's/^[[:space:]]*WECHAT_CONFIG_KEY_ID[[:space:]]*=[[:space:]]*//')"
        [[ "$key_id" =~ ^[A-Za-z0-9._-]{1,32}$ ]] || {
            echo 'Existing WeChat key id is invalid' >&2
            exit 1
        }
        ;;
      *)
        echo 'Multiple WeChat key id settings found; refusing initialization' >&2
        exit 1
        ;;
    esac

    cp -p "$env_file" "$stage/api.env.before"
    chmod 0600 "$stage/api.env.before"
    mutated=1

    tmp_key="$config_dir/.wechat-config-master-key.$$"
    printf '%s' "$key_b64" > "$tmp_key"
    chown root:1000 "$tmp_key"
    chmod 0440 "$tmp_key"
    mv -f "$tmp_key" "$key_file"
    tmp_key=''

    tmp_env="$config_dir/.api.env.wechat-bootstrap.$$"
    cat "$env_file" > "$tmp_env"
    if test "$key_id_count" = 0; then
        printf '\nWECHAT_CONFIG_KEY_ID=v1\n' >> "$tmp_env"
    fi
    printf 'WECHAT_CONFIG_MASTER_KEY_FILE=/run/wechat-config-master-key\n' >> "$tmp_env"
    chown root:root "$tmp_env"
    chmod 0600 "$tmp_env"
    mv -f "$tmp_env" "$env_file"
    tmp_env=''
    unset key_b64

    test "$(stat -c '%a' "$key_file")" = 440
    test "$(stat -c '%u:%g' "$key_file")" = '0:1000'
    test "$(grep -Fc 'WECHAT_CONFIG_MASTER_KEY_FILE=/run/wechat-config-master-key' "$env_file")" = 1

    # Verify the non-root API uid can read the mounted key without revealing it.
    docker run --rm --user 1000:1000 --read-only \
        --mount "type=bind,source=$key_file,target=/run/wechat-config-master-key,readonly" \
        "$image" node --input-type=module -e \
        'import { readFileSync } from "node:fs"; const value = readFileSync("/run/wechat-config-master-key", "utf8").trim(); const decoded = Buffer.from(value, "base64"); if (decoded.length !== 32 || decoded.toString("base64") !== value) process.exit(1);' \
        >/dev/null

    # Restart exactly the image already pinned by current.sha. The installer
    # verifies local health, auth denial, key-file ownership and read-only mount.
    bash "$installer" restart "$stage" "$sha"

    test "$(cat "$sha_file")" = "$sha"
    test "$(docker inspect -f '{{.Config.Image}}' "$container")" = "$image"
    test "$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/run/wechat-config-master-key"}}{{.RW}}{{end}}{{end}}' "$container")" = false
    docker exec "$container" node --input-type=module -e \
        'import { readFileSync } from "node:fs"; const value = readFileSync("/run/wechat-config-master-key", "utf8").trim(); const decoded = Buffer.from(value, "base64"); if (decoded.length !== 32 || decoded.toString("base64") !== value) process.exit(1);' \
        >/dev/null

    mutated=0
    echo 'MVP_WECHAT_MASTER_KEY_INITIALIZED=yes'
    echo "MVP_WECHAT_MASTER_KEY_ID=$key_id"
    echo "MVP_WECHAT_API_IMAGE_SHA=$sha"
    ;;
  *)
    echo 'Unsupported bootstrap mode' >&2
    exit 2
    ;;
esac
