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
caddy validate --config "$stage/Caddyfile"
cp -p /etc/caddy/Caddyfile "$stage/caddy.prev"
cp -p /srv/proto/portal/current/index.html "$stage/portal.prev"
for slug in ai-mirror beauty-mirror hair-mirror fitting-mirror; do
  readlink "/srv/proto/$slug/current" > "$stage/previous-$slug" || :
done
rollback() {
  echo "ROLLBACK=starting"
  cp -p "$stage/caddy.prev" /etc/caddy/Caddyfile
  cp -p "$stage/portal.prev" /srv/proto/portal/current/index.html
  for slug in ai-mirror beauty-mirror hair-mirror fitting-mirror; do
    if test -s "$stage/previous-$slug"; then
      ln -sfn "$(cat "$stage/previous-$slug")" "/srv/proto/$slug/current.rollback"
      mv -Tf "/srv/proto/$slug/current.rollback" "/srv/proto/$slug/current"
    else
      rm -f "/srv/proto/$slug/current"
    fi
  done
  systemctl reload caddy || :
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
systemctl reload caddy
systemctl is-active --quiet caddy
for slug in ai-mirror beauty-mirror hair-mirror fitting-mirror; do
  test -s "/srv/proto/$slug/current/index.html"
  echo "SITE_DEPLOYED=$slug"
done
trap - ERR
echo 'CADDY_RELOADED=ok'
rm -rf -- "$stage"
