#!/usr/bin/env bash
# Deploy the four read-only public prototype snapshots without touching SSH settings.
set -euo pipefail
stage="$1"
[[ "$stage" =~ ^/tmp/proto-mirrors\.[A-Za-z0-9]+$ ]] || exit 1
[[ "$(id -u)" -eq 0 ]] || exit 1
systemctl is-active --quiet caddy
grep -Fq 'Managed by sanchuang-dev/proto-infra' /etc/caddy/Caddyfile
for slug in ai-mirror beauty-mirror hair-mirror fitting-mirror; do
  test -s "$stage/$slug.tar.gz"
  if [[ -e "/srv/proto/$slug/current" && ! -L "/srv/proto/$slug/current" ]]; then
    echo "Refusing to overwrite non-symlink site: $slug" >&2; exit 1
  fi
done
test -s "$stage/Caddyfile"
test -s "$stage/index.html"
test -s "$stage/caddy.service"
test -s "$stage/validate-proto-auth.sh"
test -s "$stage/manage-proto-auth.sh"
# Fail closed before any live mutation; never reload a protected site without hashes.
bash "$stage/validate-proto-auth.sh" /etc/caddy/proto-auth.env "$stage/Caddyfile"
cp -p /etc/caddy/Caddyfile "$stage/caddy.prev"
cp -p /srv/proto/portal/current/index.html "$stage/portal.prev"
[[ -f /etc/systemd/system/caddy.service ]] || { echo "Missing existing Caddy unit" >&2; exit 1; }
cp -p /etc/systemd/system/caddy.service "$stage/caddy.service.prev"
install -d -m 0755 /usr/local/share/proto
for name in validate-proto-auth.sh manage-proto-auth.sh; do
  if [[ -f "/usr/local/share/proto/$name" ]]; then
    cp -p "/usr/local/share/proto/$name" "$stage/$name.prev"
  fi
done
for slug in ai-mirror beauty-mirror hair-mirror fitting-mirror; do
  readlink "/srv/proto/$slug/current" > "$stage/previous-$slug" || :
done
rollback() {
  echo "ROLLBACK=starting"
  cp -p "$stage/caddy.prev" /etc/caddy/Caddyfile
  cp -p "$stage/portal.prev" /srv/proto/portal/current/index.html
  cp -p "$stage/caddy.service.prev" /etc/systemd/system/caddy.service
  for name in validate-proto-auth.sh manage-proto-auth.sh; do
    if [[ -f "$stage/$name.prev" ]]; then cp -p "$stage/$name.prev" "/usr/local/share/proto/$name"
    else rm -f "/usr/local/share/proto/$name"; fi
  done
  for slug in ai-mirror beauty-mirror hair-mirror fitting-mirror; do
    if test -s "$stage/previous-$slug"; then
      ln -sfn "$(cat "$stage/previous-$slug")" "/srv/proto/$slug/current.rollback"
      mv -Tf "/srv/proto/$slug/current.rollback" "/srv/proto/$slug/current"
    else
      rm -f "/srv/proto/$slug/current"
    fi
  done
  systemctl daemon-reload || :
  systemctl restart caddy || :
}
trap rollback ERR
for slug in ai-mirror beauty-mirror hair-mirror fitting-mirror; do
  install -d -m 0755 "/srv/proto/$slug/releases"
  tag=$(sha256sum "$stage/$slug.tar.gz" | cut -c1-16)
  dest="/srv/proto/$slug/releases/$tag"
  if [[ ! -d "$dest" ]]; then
    mkdir "$dest"
    tar --no-same-owner -xzf "$stage/$slug.tar.gz" -C "$dest"
    test -s "$dest/index.html"
    find "$dest" -type d -exec chmod 755 {} +
    find "$dest" -type f -exec chmod 644 {} +
  fi
  test ! -e "/srv/proto/$slug/current.next"
  ln -s "$dest" "/srv/proto/$slug/current.next"
  mv -Tf "/srv/proto/$slug/current.next" "/srv/proto/$slug/current"
done
install -m 0644 "$stage/index.html" /srv/proto/portal/current/index.html
install -m 0644 "$stage/Caddyfile" /etc/caddy/Caddyfile
install -m 0644 "$stage/caddy.service" /etc/systemd/system/caddy.service
install -m 0755 "$stage/validate-proto-auth.sh" /usr/local/share/proto/validate-proto-auth.sh
install -m 0755 "$stage/manage-proto-auth.sh" /usr/local/share/proto/manage-proto-auth.sh
systemctl daemon-reload
systemctl restart caddy
systemctl is-active --quiet caddy
bash /usr/local/share/proto/validate-proto-auth.sh /etc/caddy/proto-auth.env /etc/caddy/Caddyfile
# Keep the rollback trap armed until the newly restarted, local HTTPS gateway
# is confirmed to challenge anonymous requests for every private hostname.
for slug in ai-mirror beauty-mirror hair-mirror fitting-mirror; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 12 \
    --resolve "$slug.proto.3cgroup.cn:443:127.0.0.1" "https://$slug.proto.3cgroup.cn/")
  [[ "$code" == 401 ]] || { echo "AUTH_SMOKE_FAILED=$slug:$code" >&2; false; }
done
echo 'LOCAL_AUTH_SMOKE=all_401'
for slug in ai-mirror beauty-mirror hair-mirror fitting-mirror; do
  test -s "/srv/proto/$slug/current/index.html"
  echo "SITE_DEPLOYED=$slug"
done
trap - ERR
echo 'CADDY_AUTH_RESTARTED=ok'
rm -rf -- "$stage"
