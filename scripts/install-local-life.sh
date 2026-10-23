#!/usr/bin/env bash
# Install one versioned local-life static release and the tracked Caddy host safely.
set -euo pipefail
stage="${1:?expected stage directory}"
[[ "$stage" =~ ^/tmp/proto-local-life\.[A-Za-z0-9]+$ ]] || exit 1
[[ "$(id -u)" -eq 0 ]] || exit 1
systemctl is-active --quiet caddy
grep -Fq 'Managed by sanchuang-dev/proto-infra' /etc/caddy/Caddyfile

test -s "$stage/local-life.tar.gz"
test -s "$stage/Caddyfile"
test -x /usr/local/share/proto/validate-proto-auth.sh
if [[ -e /srv/proto/local-life/current && ! -L /srv/proto/local-life/current ]]; then
  echo "Refusing to overwrite non-symlink local-life/current" >&2
  exit 1
fi

# Validate the candidate with the existing protected-site runtime hashes before mutation.
bash /usr/local/share/proto/validate-proto-auth.sh /etc/caddy/proto-auth.env "$stage/Caddyfile"

cp -p /etc/caddy/Caddyfile "$stage/caddy.prev"
readlink /srv/proto/local-life/current > "$stage/previous-local-life" || :

rollback() {
  echo "ROLLBACK=starting"
  cp -p "$stage/caddy.prev" /etc/caddy/Caddyfile
  if test -s "$stage/previous-local-life"; then
    ln -sfn "$(cat "$stage/previous-local-life")" /srv/proto/local-life/current.rollback
    mv -Tf /srv/proto/local-life/current.rollback /srv/proto/local-life/current
  else
    rm -f /srv/proto/local-life/current
  fi
  systemctl restart caddy || :
}
trap rollback ERR

install -d -m 0755 /srv/proto/local-life/releases
tag=$(sha256sum "$stage/local-life.tar.gz" | cut -c1-16)
dest="/srv/proto/local-life/releases/$tag"
if [[ ! -d "$dest" ]]; then
  mkdir "$dest"
  tar --no-same-owner -xzf "$stage/local-life.tar.gz" -C "$dest"
  test -s "$dest/index.html"
  grep -Fq '<title>三创 · 本地生活</title>' "$dest/index.html"
  ! grep -Fq '/local-life/assets/' "$dest/index.html"
  find "$dest" -type d -exec chmod 755 {} +
  find "$dest" -type f -exec chmod 644 {} +
fi

test ! -e /srv/proto/local-life/current.next
ln -s "$dest" /srv/proto/local-life/current.next
mv -Tf /srv/proto/local-life/current.next /srv/proto/local-life/current
install -m 0644 "$stage/Caddyfile" /etc/caddy/Caddyfile
systemctl restart caddy
systemctl is-active --quiet caddy
bash /usr/local/share/proto/validate-proto-auth.sh /etc/caddy/proto-auth.env /etc/caddy/Caddyfile

code=$(curl -sS -o "$stage/local-life.html" -w '%{http_code}' --max-time 20 \
  --resolve local-life.proto.3cgroup.cn:443:127.0.0.1 https://local-life.proto.3cgroup.cn/)
[[ "$code" == 200 ]] || { echo "LOCAL_LIFE_LOCAL_SMOKE=$code" >&2; false; }
grep -Fq '<title>三创 · 本地生活</title>' "$stage/local-life.html"
echo "LOCAL_LIFE_DEPLOYED=$tag"
trap - ERR
rm -rf -- "$stage"
