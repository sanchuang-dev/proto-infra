#!/usr/bin/env bash
# Install exactly one static fitness-mirror site while preserving other live Caddy hosts.
set -euo pipefail
stage="$1"
[[ "$stage" =~ ^/tmp/proto-fitness\.[A-Za-z0-9]+$ ]] || exit 1
[[ "$(id -u)" -eq 0 ]] || { echo "DEPLOY=requires_root" >&2; exit 1; }
systemctl is-active --quiet caddy
grep -Fq '# Managed by sanchuang-dev/proto-infra' /etc/caddy/Caddyfile
test -s "$stage/fitness-mirror.tar.gz"
test -s "$stage/Caddyfile"
if [[ -e /srv/proto/fitness-mirror/current && ! -L /srv/proto/fitness-mirror/current ]]; then
  echo "Refusing to overwrite a non-symlink fitness mirror site" >&2
  exit 1
fi
# Append only the reviewed fitness host block to the LIVE file. Never replace
# the complete live Caddyfile with an unrelated staged proto-infra snapshot.
python3 - "$stage/Caddyfile" /etc/caddy/Caddyfile "$stage/Caddyfile.next" <<'PY'
from pathlib import Path
import re,sys
desired,live,out=map(Path,sys.argv[1:])
host='fitness-mirror.proto.3cgroup.cn'
def block(src):
    match=re.search(r'(?m)^'+re.escape(host)+r' *\{',src)
    if not match: return None
    count=0
    for i in range(match.start(),len(src)):
        if src[i]=='{': count+=1
        if src[i]=='}':
            count-=1
            if count==0:
                return src[match.start():i+1]
    raise SystemExit('Unbalanced Caddy block')
approved=block(desired.read_text(encoding='utf8'))
if not approved or desired.read_text(encoding='utf8').count(host+' {')!=1:
    raise SystemExit('Expected one approved fitness host in repository Caddyfile')
old=live.read_text(encoding='utf8')
existing=block(old)
if existing is not None and existing!=approved:
    raise SystemExit('Existing fitness Caddy host differs; refuse overwrite')
next_config=old if existing else old.rstrip()+'\n\n'+approved+'\n'
out.write_text(next_config,encoding='utf8')
print('FITNESS_CADDY_CHANGE='+('already_current' if existing else 'isolated_append'))
PY
/usr/local/bin/caddy validate --config "$stage/Caddyfile.next"
prev_link="$(readlink /srv/proto/fitness-mirror/current 2>/dev/null || true)"
cp -p /etc/caddy/Caddyfile "$stage/Caddyfile.prev"
rollback() {
  echo "FITNESS_ROLLBACK=starting" >&2
  cp -p "$stage/Caddyfile.prev" /etc/caddy/Caddyfile
  if [[ -n "$prev_link" ]]; then
    ln -sfn "$prev_link" /srv/proto/fitness-mirror/current.rollback
    mv -Tf /srv/proto/fitness-mirror/current.rollback /srv/proto/fitness-mirror/current
  else
    test ! -L /srv/proto/fitness-mirror/current || rm -f /srv/proto/fitness-mirror/current
  fi
  systemctl reload caddy || true
}
trap rollback ERR
install -d -m 0755 /srv/proto/fitness-mirror/releases
release_tag="$(sha256sum "$stage/fitness-mirror.tar.gz" | cut -c1-16)"
release="/srv/proto/fitness-mirror/releases/$release_tag"
if [[ ! -d "$release" ]]; then
  mkdir -p "$release"
  tar --no-same-owner -xzf "$stage/fitness-mirror.tar.gz" -C "$release"
  for path in index.html gym.html hotel.html assets/mirror.css assets/mirror.js assets/stock/credits.json; do
    test -s "$release/$path"
  done
  find "$release" -type d -exec chmod 755 {} +
  find "$release" -type f -exec chmod 644 {} +
fi
ln -s "$release" /srv/proto/fitness-mirror/current.next
mv -Tf /srv/proto/fitness-mirror/current.next /srv/proto/fitness-mirror/current
if ! cmp -s /etc/caddy/Caddyfile "$stage/Caddyfile.next"; then
  install -m 0644 "$stage/Caddyfile.next" /etc/caddy/Caddyfile.next
  mv -f /etc/caddy/Caddyfile.next /etc/caddy/Caddyfile
fi
systemctl reload caddy
systemctl is-active --quiet caddy
/usr/local/bin/caddy validate --config /etc/caddy/Caddyfile
# Newly introduced hostname may need first-time ACME issuance.
site_ok=0
for attempt in $(seq 1 16); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 12 \
    --resolve fitness-mirror.proto.3cgroup.cn:443:127.0.0.1 \
    https://fitness-mirror.proto.3cgroup.cn/ 2>/dev/null || true)"
  if [[ "$code" == 200 ]]; then site_ok=1; break; fi
  sleep 5
done
[[ "$site_ok" -eq 1 ]] || { echo "FITNESS_HTTPS_SMOKE=failed" >&2; false; }
test -s /srv/proto/fitness-mirror/current/gym.html
test -s /srv/proto/fitness-mirror/current/hotel.html
echo "FITNESS_MIRROR_DEPLOYED=$release_tag"
echo "FITNESS_HTTPS_PUBLIC=200"
trap - ERR
rm -rf -- "$stage"
