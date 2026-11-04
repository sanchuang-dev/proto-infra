#!/usr/bin/env bash
# Bounded, reversible Caddy ingress installer for Local Life online MVP.
# Invoked only through the reviewed proto-infra/prod release workflow.
set -euo pipefail

mode="${1:?mode required}"
stage="${2:?staging directory required}"
[[ "$stage" =~ ^/tmp/local-life-mvp-ingress\.[A-Za-z0-9]+$ ]] || exit 1
test "$(id -u)" -eq 0
test -f "$stage/local-life-mvp.caddy"
test -f /etc/caddy/Caddyfile

restore_previous() {
    test -f "$stage/Caddyfile.before"
    install -m 0644 "$stage/Caddyfile.before" /etc/caddy/Caddyfile.restore
    mv -f /etc/caddy/Caddyfile.restore /etc/caddy/Caddyfile
    systemctl reload caddy
}

case "$mode" in
    apply)
        systemctl is-active --quiet caddy
        systemctl is-active --quiet docker
        grep -Fqx '# Managed by sanchuang-dev/proto-infra' /etc/caddy/Caddyfile
        for existing in proto.3cgroup.cn local-life.proto.3cgroup.cn benefit.proto.3cgroup.cn; do
            grep -Fqx "$existing {" /etc/caddy/Caddyfile || {
                echo "Expected existing Caddy host missing: $existing" >&2
                exit 1
            }
        done

        # This root is dedicated to the new application, NEVER the existing /srv/proto/local-life.
        install -d -m 0755 /srv/proto/local-life-mvp
        install -d -m 0755 /srv/proto/local-life-mvp/web
        install -d -m 0755 /srv/proto/local-life-mvp/admin
        install -d -m 0755 /srv/proto/local-life-mvp/releases
        install -d -m 0700 /srv/proto/local-life-mvp/data
        install -d -m 0700 /srv/proto/local-life-mvp/backups
        install -d -m 0700 /srv/proto/local-life-mvp/config

        cp -p /etc/caddy/Caddyfile "$stage/Caddyfile.before"
        if grep -Fq 'local.proto.3cgroup.cn {' /etc/caddy/Caddyfile ||
           grep -Fq 'local-admin.proto.3cgroup.cn {' /etc/caddy/Caddyfile; then
            n="$(wc -l < "$stage/local-life-mvp.caddy" | tr -d ' ')"
            tail -n "$n" /etc/caddy/Caddyfile > "$stage/Caddyfile.tail"
            cmp -s "$stage/Caddyfile.tail" "$stage/local-life-mvp.caddy" || {
                echo "MVP site exists but differs from reviewed fragment; refusing to overwrite" >&2
                exit 1
            }
            cp -p /etc/caddy/Caddyfile "$stage/Caddyfile.candidate"
            printf '0\n' > "$stage/modified"
            echo "MVP_INGRESS_ALREADY_PRESENT=yes"
            exit 0
        fi

        cp -p "$stage/Caddyfile.before" "$stage/Caddyfile.candidate"
        printf '\n' >> "$stage/Caddyfile.candidate"
        cat "$stage/local-life-mvp.caddy" >> "$stage/Caddyfile.candidate"
        caddy_bin="$(command -v caddy)"
        "$caddy_bin" validate --config "$stage/Caddyfile.candidate"
        install -m 0644 "$stage/Caddyfile.candidate" /etc/caddy/Caddyfile.mvp-next
        mv -f /etc/caddy/Caddyfile.mvp-next /etc/caddy/Caddyfile
        if ! systemctl reload caddy; then
            echo "Caddy reload failed; reverting" >&2
            restore_previous || true
            exit 1
        fi
        printf '1\n' > "$stage/modified"
        systemctl is-active --quiet caddy || {
            restore_previous || true
            exit 1
        }
        echo "MVP_INGRESS_APPLIED=yes"
        ;;
    rollback)
        test -f "$stage/modified"
        if grep -Fxq '1' "$stage/modified"; then
            cmp -s /etc/caddy/Caddyfile "$stage/Caddyfile.candidate" || {
                echo "Live Caddy changed after deployment; refusing blind rollback" >&2
                exit 1
            }
            restore_previous
            echo "MVP_INGRESS_RESTORED=yes"
        else
            echo "MVP_INGRESS_UNCHANGED=yes"
        fi
        ;;
    cleanup)
        rm -rf -- "$stage"
        ;;
    *)
        echo "Unknown mode" >&2
        exit 1
        ;;
esac
