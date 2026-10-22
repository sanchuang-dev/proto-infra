#!/usr/bin/env bash
# Fail closed before touching live Caddy config or its systemd service.
set -euo pipefail
auth_file="${1:-/etc/caddy/proto-auth.env}"
config="${2:-/etc/caddy/Caddyfile}"
[[ "$(id -u)" == 0 ]] || { echo "AUTH_VALIDATION=requires_root" >&2; exit 1; }
[[ -f "$auth_file" && ! -L "$auth_file" ]] || { echo "AUTH_VALIDATION=missing_or_symlink" >&2; exit 1; }
[[ "$(stat -c '%a:%u:%g' "$auth_file")" == 600:0:0 ]] || { echo "AUTH_VALIDATION=insecure_file_mode" >&2; exit 1; }
# Only the four expected names with quoted bcrypt values are permitted.
# The root-owned file is sourced intentionally and must never be taken from repo input.
unset PROTO_AI_MIRROR_HASH PROTO_BEAUTY_MIRROR_HASH PROTO_HAIR_MIRROR_HASH PROTO_FITTING_MIRROR_HASH || true
set -a
# shellcheck disable=SC1090
source "$auth_file"
set +a
for key in PROTO_AI_MIRROR_HASH PROTO_BEAUTY_MIRROR_HASH PROTO_HAIR_MIRROR_HASH PROTO_FITTING_MIRROR_HASH; do
  value="${!key:-}"
  if [[ ! "$value" =~ ^\$2[aby]\$[0-9]{2}\$[./a-zA-Z0-9]{53}$ ]]; then
    echo "AUTH_VALIDATION=missing_or_invalid_hash:$key" >&2
    exit 1
  fi
done
# Caddy output is suppressed: it may contain expanded config values.
if ! /usr/local/bin/caddy validate --config "$config" >/dev/null 2>&1; then
  echo "AUTH_VALIDATION=caddy_rejected_config" >&2
  exit 1
fi
echo "AUTH_VALIDATION=passed"
