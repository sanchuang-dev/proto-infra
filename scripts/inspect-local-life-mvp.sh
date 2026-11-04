#!/usr/bin/env bash
# Read-only server inventory for the Local Life online MVP ingress.
# Never inspect secret values, SQLite data, or application environment files.
set -euo pipefail

printf 'LOCAL_LIFE_MVP_PREFLIGHT=READ_ONLY\n'
printf 'KERNEL=%s\n' "$(uname -s)"
printf 'ARCH=%s\n' "$(uname -m)"
printf 'CPU_CORES=%s\n' "$(getconf _NPROCESSORS_ONLN)"
awk '/^MemTotal:/ {printf "RAM_TOTAL_KB=%s\n", $2} /^MemAvailable:/ {printf "RAM_AVAILABLE_KB=%s\n", $2}' /proc/meminfo
if test -d /srv/proto; then
  df -Pm /srv/proto | awk 'NR==2 {printf "PROTO_DISK_TOTAL_MB=%s\nPROTO_DISK_FREE_MB=%s\n", $2, $4}'
else
  printf 'PROTO_ROOT_PRESENT=no\n'
fi
for executable in caddy docker node sqlite3; do
  if command -v "$executable" >/dev/null 2>&1; then
    printf 'BINARY_%s=present\n' "$executable"
  else
    printf 'BINARY_%s=missing\n' "$executable"
  fi
done
for service in caddy docker; do
  if command -v systemctl >/dev/null 2>&1; then
    printf 'SERVICE_%s=%s\n' "$service" "$(systemctl is-active "$service" 2>/dev/null || true)"
  else
    printf 'SERVICE_%s=unknown_no_systemctl\n' "$service"
  fi
done

# Print occupied TCP listening PORT NUMBERS only, not internal addresses or process details.
if command -v ss >/dev/null 2>&1; then
  printf 'LISTENING_TCP_PORTS='
  ss -H -ltn | awk '{n=split($4,a,":"); p=a[n]; if (p ~ /^[0-9]+$/) print p}' | sort -nu | paste -sd, -
fi

if test -r /etc/caddy/Caddyfile; then
  printf 'CADDYFILE_READABLE=yes\n'
  sha256sum /etc/caddy/Caddyfile | awk '{printf "CADDYFILE_SHA256=%s\n", $1}'
  for host in proto.3cgroup.cn local-life.proto.3cgroup.cn benefit.proto.3cgroup.cn local.proto.3cgroup.cn local-admin.proto.3cgroup.cn; do
    if grep -Fqx "$host {" /etc/caddy/Caddyfile; then
      printf 'CADDY_SITE_%s=declared\n' "$host"
    else
      printf 'CADDY_SITE_%s=absent\n' "$host"
    fi
  done
else
  printf 'CADDYFILE_READABLE=no\n'
fi

# This inventory does not read the contents of SQLite files or backup directories.
for dir in /srv/proto/local-life-mvp /srv/proto/local-life-mvp/data /srv/proto/local-life-mvp/releases; do
  if test -d "$dir"; then
    printf 'MVP_DIR_%s=present\n' "${dir##*/}"
  else
    printf 'MVP_DIR_%s=absent\n' "${dir##*/}"
  fi
done
printf 'LOCAL_LIFE_MVP_PREFLIGHT=COMPLETE\n'
