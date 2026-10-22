#!/usr/bin/env bash
# Run only in an interactive, trusted SSH terminal ON THE PROTOTYPE SERVER.
# Passwords are printed to that terminal once and never placed in GitHub Actions/logs.
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo "Requires root on the prototype server" >&2; exit 1; }
[[ -t 0 && -t 1 ]] || { echo "Requires a private interactive terminal; never run in CI" >&2; exit 1; }
[[ -x /usr/local/bin/caddy ]] || { echo "Caddy is not installed" >&2; exit 1; }
file=/etc/caddy/proto-auth.env
mode="${1:-init}"
slug="${2:-}"
case "$mode" in
  init)
    [[ ! -e "$file" ]] || { echo "Credentials already exist; use rotate" >&2; exit 1; }
    ;;
  rotate)
    [[ -f "$file" && ! -L "$file" ]] || exit 1
    [[ "$(stat -c '%a:%u:%g' "$file")" == "600:0:0" ]] || exit 1
    case "$slug" in ai-mirror|beauty-mirror|hair-mirror|fitting-mirror) ;; *) echo "Invalid hostname" >&2; exit 1;; esac
    ;;
  *) echo "Usage: $0 init | rotate <site-slug>" >&2; exit 1;;
esac
umask 077
# No variable expansions from an untrusted location: only the root-owned envfile.
declare -A hashes=()
if [[ "$mode" == rotate ]]; then
  # shellcheck disable=SC1090
  source "$file"
  hashes[ai-mirror]="$PROTO_AI_MIRROR_HASH"
  hashes[beauty-mirror]="$PROTO_BEAUTY_MIRROR_HASH"
  hashes[hair-mirror]="$PROTO_HAIR_MIRROR_HASH"
  hashes[fitting-mirror]="$PROTO_FITTING_MIRROR_HASH"
fi
sites=(ai-mirror beauty-mirror hair-mirror fitting-mirror)
declare -A fresh=()
for s in "${sites[@]}"; do
  if [[ "$mode" == rotate && "$slug" != "$s" ]]; then continue; fi
  pw=$(openssl rand -hex 16)
  [[ "${#pw}" -eq 32 ]] || exit 1
  hash=$(printf '%s' "$pw" | /usr/local/bin/caddy hash-password --algorithm bcrypt)
  fresh["$s"]="$pw"
  hashes["$s"]="$hash"
  unset pw hash
done
tmp=$(mktemp /etc/caddy/.proto-auth.XXXXXX)
old=""
cleanup() { rm -f -- "$tmp"; }
trap cleanup EXIT
{
  printf "PROTO_AI_MIRROR_HASH='%s'\n" "${hashes[ai-mirror]}"
  printf "PROTO_BEAUTY_MIRROR_HASH='%s'\n" "${hashes[beauty-mirror]}"
  printf "PROTO_HAIR_MIRROR_HASH='%s'\n" "${hashes[hair-mirror]}"
  printf "PROTO_FITTING_MIRROR_HASH='%s'\n" "${hashes[fitting-mirror]}"
} > "$tmp"
chmod 600 "$tmp"
chown root:root "$tmp"
if [[ "$mode" == rotate ]]; then
  old=$(mktemp /etc/caddy/.proto-auth-backup.XXXXXX)
  cp -p "$file" "$old"
fi
mv -f "$tmp" "$file"
if [[ "$mode" == rotate ]]; then
  # Updating the EnvironmentFile requires a new service process.
  if ! bash /usr/local/share/proto/validate-proto-auth.sh "$file" /etc/caddy/Caddyfile >/dev/null 2>&1 ||
       ! systemctl restart caddy; then
    mv -f "$old" "$file"
    systemctl restart caddy || true
    echo "Credential rotation failed; restored previous hashes" >&2
    exit 1
  fi
  rm -f -- "$old"
fi
printf '\n--- Prototype access credentials (copy securely NOW; shown once) ---\n'
for s in "${sites[@]}"; do
  if [[ -n "${fresh[$s]:-}" ]]; then
    printf '%s | username: demo | password: %s\n' "$s" "${fresh[$s]}"
  fi
done
printf 'Do not paste these credentials into public GitHub Issues or Actions logs.\n'
