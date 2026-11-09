#!/usr/bin/env bash
# Local Life only: immutable static assets + one Hono container + persistent SQLite.
# Called with fixed arguments by proto-infra/prod, never with unreviewed remote commands.
set -Eeuo pipefail
mode="${1:?mode}"
stage="${2:?stage}"
sha="${3:?sha}"
[[ "$stage" =~ ^/tmp/local-life-mvp-release\.[A-Za-z0-9]+$ ]] || exit 1
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || exit 1
test "$(id -u)" -eq 0

base=/srv/proto/local-life-mvp
image="local-life-mvp-api:$sha"
container=local-life-mvp-api
db="$base/data/local-life.sqlite"
release="$base/releases/$sha"
env_file="$base/config/api.env"

read_old() { cat "$stage/old-sha" 2>/dev/null || true; }
mig_count() {
    if test -s "$db"; then
        sqlite3 "$db" "SELECT COUNT(*) FROM __drizzle_migrations;" 2>/dev/null || printf '0\n'
    else
        printf '0\n'
    fi
}
start_api() {
    local selected_image="$1"
    local key_file="$base/config/wechat-config-master-key"
    local secret_mount=()
    if grep -Fxq 'WECHAT_CONFIG_MASTER_KEY_FILE=/run/wechat-config-master-key' "$env_file"; then
        test -s "$key_file" || { echo 'WeChat master-key file is missing' >&2; return 1; }
        test "$(stat -c '%a' "$key_file")" = 440 || { echo 'WeChat master-key file mode must be 0440' >&2; return 1; }
        test "$(stat -c '%u:%g' "$key_file")" = '0:1000' || { echo 'WeChat master-key file owner must be root:1000' >&2; return 1; }
        secret_mount=(--mount "type=bind,source=$key_file,target=/run/wechat-config-master-key,readonly")
    elif grep -Eq '^[[:space:]]*WECHAT_CONFIG_MASTER_KEY(_FILE)?[[:space:]]*=' "$env_file" || test -e "$key_file"; then
        echo 'Inconsistent WeChat master-key file configuration; refusing API start' >&2
        return 1
    fi
    docker run -d --name "$container" \
        --restart unless-stopped \
        --user 1000:1000 \
        --read-only --tmpfs /tmp:rw,nosuid,size=64m \
        --cap-drop ALL --security-opt no-new-privileges \
        --memory 512m --cpus 1.0 --pids-limit 128 \
        --log-opt max-size=10m --log-opt max-file=3 \
        -p 127.0.0.1:18081:4080 \
        --mount "type=bind,source=$base/data,target=/data" \
        "${secret_mount[@]}" \
        --env-file "$env_file" "$selected_image" >/dev/null
}
api_ready() {
    local ok=0
    for _ in $(seq 1 30); do
        if curl -fsS --max-time 3 http://127.0.0.1:18081/healthz 2>/dev/null |
           grep -Fq '"service":"local-life-api"'; then
            ok=1
            break
        fi
        sleep 2
    done
    test "$ok" = 1
    test "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18081/admin/communities)" = 401
    curl -fsS http://127.0.0.1:18081/auth/methods | grep -Fq '"developmentResidentLogin":false'
}

restore_link() {
    local site="$1"
    local old="$2"
    local target="$base/$site/current"
    if test -L "$target"; then
        local current
        current="$(readlink "$target")"
        if test -n "$old" && test "$current" = "$base/releases/$old/$site"; then
            return 0 # failure happened before static switch
        fi
        if test "$current" != "$release/$site"; then
            echo "Unexpected $site symlink drift; refusing rollback" >&2
            return 1
        fi
        rm -f "$target"
    elif test -e "$target"; then
        echo "Unexpected non-symlink $site current" >&2
        return 1
    fi
    if test -n "$old"; then
        test -f "$base/releases/$old/$site/index.html" || return 1
        ln -s "$base/releases/$old/$site" "$target"
    fi
}
case "$mode" in
  restart)
    test -s "$env_file"
    test "$(stat -c '%a' "$env_file")" = 600
    current_sha="$(cat "$base/current.sha")"
    test "$current_sha" = "$sha"
    docker image inspect "$image" >/dev/null
    if docker inspect "$container" >/dev/null 2>&1; then
        test "$(docker inspect -f '{{.Config.Image}}' "$container")" = "$image"
        if test "$(docker inspect -f '{{.State.Running}}' "$container")" = true; then
            docker stop -t 12 "$container" >/dev/null
        fi
        docker rm "$container" >/dev/null
    fi
    start_api "$image"
    if ! api_ready; then
        docker logs --tail 25 "$container" 2>/dev/null | \
            sed -E 's/(token|password|secret|cookie)=[^[:space:]]+/\\1=[REDACTED]/Ig' >&2 || true
        echo 'API restart failed local HTTP health/security checks' >&2
        exit 1
    fi
    echo "MVP_API_RESTART_VERIFIED_SHA=$sha"
    ;;
  apply)
    for host in local.proto.3cgroup.cn local-admin.proto.3cgroup.cn; do
        grep -Fqx "$host {" /etc/caddy/Caddyfile || {
            echo "Missing approved Caddy site $host" >&2; exit 1;
        }
    done
    systemctl is-active --quiet caddy
    systemctl is-active --quiet docker
    command -v docker >/dev/null
    command -v sqlite3 >/dev/null
    for name in web.tar.gz admin.tar.gz api-image.tar.gz; do
        test -s "$stage/$name"
    done
    for site in web admin; do
        test ! -e "$base/$site/current" || test -L "$base/$site/current" || {
            echo "Non-symlink current/$site; refusing takeover" >&2; exit 1;
        }
    done
    install -d -m 0755 "$base" "$base/releases" "$base/web" "$base/admin"
    install -d -m 0700 -o 1000 -g 1000 "$base/data"
    install -d -m 0700 "$base/config" "$base/backups"
    if test ! -f "$env_file"; then
        umask 077
        cat > "$env_file" <<'ENV'
NODE_ENV=production
HOST=0.0.0.0
PORT=4080
DATABASE_PATH=/data/local-life.sqlite
WEB_BASE_URL=https://local.proto.3cgroup.cn/
TRUSTED_ORIGINS=https://local.proto.3cgroup.cn,https://local-admin.proto.3cgroup.cn
AUTH_DEV_ENABLED=false
ENV
        chmod 0600 "$env_file"
    fi
    # Fail closed if dev auth or a shared Cookie Domain has been introduced.
    grep -Fxq 'AUTH_DEV_ENABLED=false' "$env_file"
    ! grep -Eq '^COOKIE_DOMAIN=' "$env_file"
    grep -Fxq 'NODE_ENV=production' "$env_file"
    test "$(stat -c '%a' "$env_file")" = 600
    docker load -i <(gzip -dc "$stage/api-image.tar.gz") >/dev/null
    docker image inspect "$image" >/dev/null
    if test ! -d "$release"; then
        tmp="$base/releases/.stage-$sha"
        test ! -e "$tmp" || { echo 'Stale staged release' >&2; exit 1; }
        install -d -m 0755 "$tmp/web" "$tmp/admin"
        tar -xzf "$stage/web.tar.gz" --no-same-owner --no-same-permissions -C "$tmp/web"
        tar -xzf "$stage/admin.tar.gz" --no-same-owner --no-same-permissions -C "$tmp/admin"
        test -s "$tmp/web/index.html"
        test -s "$tmp/admin/index.html"
        mv "$tmp" "$release"
    fi
    # A remote root shell may have umask 077; Caddy must still read public assets.
    test -s "$release/web/index.html"
    test -s "$release/admin/index.html"
    chmod 0755 "$release" "$release/web" "$release/admin"
    chmod -R a+rX "$release/web" "$release/admin"
    caddy_user="$(systemctl show -p User --value caddy 2>/dev/null || true)"
    if test -n "$caddy_user"; then
        command -v runuser >/dev/null
        runuser -u "$caddy_user" -- test -x "$release/web"
        runuser -u "$caddy_user" -- test -r "$release/web/index.html"
        runuser -u "$caddy_user" -- test -x "$release/admin"
        runuser -u "$caddy_user" -- test -r "$release/admin/index.html"
    fi
    echo 'MVP_STATIC_READABLE_BY_CADDY=yes'
    old="$(cat "$base/current.sha" 2>/dev/null || true)"
    if test -n "$old"; then [[ "$old" =~ ^[0-9a-f]{40}$ ]] || exit 1; fi
    printf '%s\n' "$old" > "$stage/old-sha"
    mig_count > "$stage/old-migrations"
    if test -s "$db"; then
        backup="$base/backups/pre-$sha-$(date -u +%Y%m%dT%H%M%SZ).sqlite"
        sqlite3 "$db" ".backup '$backup'"
        test "$(sqlite3 "$backup" 'PRAGMA quick_check;')" = ok
        chmod 0600 "$backup"
        echo 'MVP_DB_HOT_BACKUP_VERIFIED=yes'
    fi
    # Exercise candidate migrations on a COPY, never against the active DB.
    install -d -m 0700 -o 1000 -g 1000 "$stage/test-db"
    if test -s "$db"; then
        cp "$backup" "$stage/test-db/local-life.sqlite"
        chown 1000:1000 "$stage/test-db/local-life.sqlite"
    fi
    docker run --rm --user 1000:1000 --read-only \
        --tmpfs /tmp:rw,nosuid,size=64m \
        --mount "type=bind,source=$stage/test-db,target=/data" \
        "$image" node --input-type=module -e \
        "import { createDatabase } from './dist/db/client.js'; const { sqlite } = createDatabase('/data/local-life.sqlite', '/app/db/migrations'); if (sqlite.pragma('quick_check', {simple:true}) !== 'ok') process.exit(1); sqlite.close();" \
        >/dev/null
    echo 'MVP_MIGRATION_COPY_VERIFIED=yes'
    printf '1\n' > "$stage/applied"
    if docker container inspect "$container" >/dev/null 2>&1; then
        docker stop -t 12 "$container" >/dev/null
        docker rm "$container" >/dev/null
    fi
    start_api "$image"
    if ! api_ready; then
        docker logs --tail 25 "$container" 2>/dev/null | \
            sed -E 's/(token|password|secret|cookie)=[^[:space:]]+/\1=[REDACTED]/Ig' >&2 || true
        echo 'New API failed real HTTP health/security checks' >&2
        exit 1
    fi
    for site in web admin; do
        ln -s "$release/$site" "$base/$site/current.new"
        mv -Tf "$base/$site/current.new" "$base/$site/current"
    done
    printf '%s\n' "$sha" > "$base/current.sha.next"
    mv -f "$base/current.sha.next" "$base/current.sha"
    echo "MVP_APP_SWITCHED_SHA=$sha"
    ;;
  rollback)
    if ! test -f "$stage/applied"; then
        echo MVP_APP_NO_SWITCH_TO_ROLLBACK=yes
        exit 0
    fi
    old="$(read_old)"
    for site in web admin; do restore_link "$site" "$old"; done
    if test -z "$old"; then rm -f "$base/current.sha"; else printf '%s\n' "$old" > "$base/current.sha"; fi
    docker stop -t 10 "$container" >/dev/null 2>&1 || true
    docker rm "$container" >/dev/null 2>&1 || true
    if test -n "$old"; then
        before="$(cat "$stage/old-migrations")"
        after="$(mig_count)"
        if test "$before" = "$after"; then
            start_api "local-life-mvp-api:$old"
            api_ready || { echo 'Rollback API failed health check' >&2; exit 1; }
            echo 'MVP_COMPATIBLE_APP_ROLLBACK=yes'
        else
            echo 'MVP_SCHEMA_CHANGED_NO_UNSAFE_CODE_ROLLBACK=yes' >&2
            exit 1
        fi
    fi
    echo MVP_APP_ROLLED_BACK=yes
    ;;
  finalize)
    test -f "$stage/applied"
    test "$(cat "$base/current.sha")" = "$sha"
    test "$(sqlite3 "$db" 'PRAGMA quick_check;')" = ok
    if test -z "$(read_old)"; then
        # First deploy (including a retry after app rollback): keep a verified seed backup.
        seed="$base/backups/initial-$sha.sqlite"
        if ! test -s "$seed"; then
            sqlite3 "$db" ".backup '$seed'"
            chmod 0600 "$seed"
        fi
        test "$(sqlite3 "$seed" 'PRAGMA quick_check;')" = ok
        echo MVP_SEED_BACKUP_VERIFIED=yes
    fi
    rm -rf -- "$stage"
    echo "MVP_DEPLOYED_SHA=$sha"
    ;;
  *)
    echo 'Unknown mode' >&2
    exit 1
    ;;
esac
