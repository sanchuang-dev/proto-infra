#!/usr/bin/env bash
# Idempotent bootstrap of the company's otherwise empty prototype instance.
# This intentionally does not touch /root/.ssh, SSH configuration, or another host.
set -euo pipefail
stage="${1:?stage directory missing}"
[[ "$stage" =~ ^/tmp/proto-bootstrap\.[A-Za-z0-9]+$ ]] || { echo "Refusing unexpected stage directory" >&2; exit 1; }
[[ "$(id -u)" -eq 0 ]] || { echo "Root is needed for one-time bootstrap" >&2; exit 1; }
for filename in caddy Caddyfile caddy.service index.html; do
  [[ -f "$stage/$filename" ]] || { echo "Missing staged file: $filename" >&2; exit 1; }
done

if [[ -e /etc/caddy/Caddyfile ]] && ! grep -Fq 'Managed by sanchuang-dev/proto-infra' /etc/caddy/Caddyfile; then
  echo "Refusing to replace non-proto Caddy configuration" >&2
  exit 1
fi
if [[ -e /etc/systemd/system/caddy.service ]] && ! grep -Fq 'Caddy for 3C Prototype Portal' /etc/systemd/system/caddy.service; then
  echo "Refusing to replace non-proto Caddy service" >&2
  exit 1
fi
if ss -ltn 2>/dev/null | awk 'NR>1 {print $4}' | grep -Eq '(:80|:443)$' && ! systemctl is-active --quiet caddy; then
  echo "HTTP/HTTPS port occupied by a non-Caddy service; stop here" >&2
  exit 1
fi

# Minimal dedicated unprivileged user for Caddy. SSH policy unchanged.
if ! id caddy >/dev/null 2>&1; then useradd --system --home-dir /var/lib/caddy --shell /sbin/nologin caddy; fi
install -d -o caddy -g caddy -m 0750 /var/lib/caddy
install -d -o caddy -g caddy -m 0750 /var/lib/caddy/.local /var/lib/caddy/.local/share /var/lib/caddy/.config
install -d -m 0755 /etc/caddy /srv/proto /srv/proto/portal /srv/proto/portal/current
install -m 0755 "$stage/caddy" /usr/local/bin/caddy
install -m 0644 "$stage/Caddyfile" /etc/caddy/Caddyfile
install -m 0644 "$stage/index.html" /srv/proto/portal/current/index.html
install -m 0644 "$stage/caddy.service" /etc/systemd/system/caddy.service

/usr/local/bin/caddy validate --config /etc/caddy/Caddyfile
if command -v restorecon >/dev/null 2>&1; then
  restorecon -F /usr/local/bin/caddy /etc/caddy/Caddyfile /srv/proto/portal/current/index.html || true
fi
systemctl daemon-reload
# Only open the ports on the instance's local firewall, if firewalld is running.
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-service=http
  firewall-cmd --permanent --add-service=https
  firewall-cmd --reload
fi
systemctl enable --now caddy
systemctl is-active --quiet caddy
echo "CADDY_VERSION=$(/usr/local/bin/caddy version | awk '{print $1}')"
echo "CADDY_SERVICE=active"
echo "LOCAL_HTTP_PORT=$(ss -ltn | awk 'NR>1{print $4}' | grep -Ec ':80$' || true)"
echo "LOCAL_HTTPS_PORT=$(ss -ltn | awk 'NR>1{print $4}' | grep -Ec ':443$' || true)"
echo "PORTAL_FILE_PRESENT=$([[ -s /srv/proto/portal/current/index.html ]] && echo yes || echo no)"
rm -rf -- "$stage"
