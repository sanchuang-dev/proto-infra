#!/usr/bin/env bash
# Install one verified Android APK and its index under the existing prototype portal.
# The portal publisher updates only index.html; /d/ stays independent.
set -euo pipefail
stage="${1:?stage directory required}"
root=/srv/proto/portal/current
target="$root/d"
expected_size=317264746
expected_sha=083e0dd95174280ec39dcd671c7f1b4d426fbe7f3a425532d0832942e9f0ff25

[[ "$(id -u)" -eq 0 ]] || { echo "DOWNLOAD_INSTALL=requires_root" >&2; exit 1; }
[[ "$stage" =~ ^/srv/proto/portal/current/\.android-stage\.[A-Za-z0-9]+$ ]] || {
  echo "DOWNLOAD_INSTALL=unexpected_stage" >&2
  exit 1
}
trap 'rm -rf -- "$stage"' EXIT
test -s "$root/index.html"
test -s "$stage/index.html"
test -s "$stage/3c.apk"
test "$(stat -c '%s' "$stage/3c.apk")" -eq "$expected_size"
printf '%s  %s\n' "$expected_sha" "$stage/3c.apk" | sha256sum -c - >/dev/null
if [[ -e "$target" && ( ! -d "$target" || -L "$target" ) ]]; then
  echo "DOWNLOAD_INSTALL=unsafe_destination" >&2
  exit 1
fi
install -d -m 0755 "$target"
if [[ -e "$target/3c.apk" && -L "$target/3c.apk" ]]; then
  echo "DOWNLOAD_INSTALL=apk_symlink_rejected" >&2
  exit 1
fi
if [[ -e "$target/index.html" && -L "$target/index.html" ]]; then
  echo "DOWNLOAD_INSTALL=index_symlink_rejected" >&2
  exit 1
fi
if [[ -f "$target/3c.apk" ]] && [[ "$(sha256sum "$target/3c.apk" | awk '{print $1}')" == "$expected_sha" ]]; then
  echo "DOWNLOAD_APK=already_current"
else
  mv -f "$stage/3c.apk" "$target/3c.apk.next"
  chmod 0644 "$target/3c.apk.next"
  mv -f "$target/3c.apk.next" "$target/3c.apk"
  echo "DOWNLOAD_APK=installed"
fi
install -m 0644 "$stage/index.html" "$target/index.html.next"
mv -f "$target/index.html.next" "$target/index.html"
test "$(stat -c '%s' "$target/3c.apk")" -eq "$expected_size"
printf '%s  %s\n' "$expected_sha" "$target/3c.apk" | sha256sum -c - >/dev/null
echo "DOWNLOAD_APK_SHA256=$expected_sha"
echo "DOWNLOAD_URL=https://proto.3cgroup.cn/d/3c.apk"
