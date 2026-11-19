#!/usr/bin/env bash
# Publish only the Jianqu prototype APK under the existing /d/ directory.
# Never overwrite the original 3C Chromium APK.
set -euo pipefail

stage=${1:?stage directory required}
sha=${2:?SHA-256 required}
bytes=${3:?size required}
root=/srv/proto/portal/current
target="$root/d"

[[ "$(id -u)" -eq 0 ]] || { echo 'JIANQU_INSTALL=requires_root' >&2; exit 1; }
[[ "$stage" =~ ^/srv/proto/\.jianqu-stage\.[A-Za-z0-9]+$ ]] || exit 1
[[ "$sha" =~ ^[a-f0-9]{64}$ ]] || exit 1
[[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 100000 && bytes < 100000000 )) || exit 1

# Reject a different origin or unexpected portal instead of creating an alternate site.
test -s "$root/index.html"
test -d "$target" && test ! -L "$target"
test -s "$target/3c.apk"
test "$(stat -c '%s' "$target/3c.apk")" -eq 317264746
test -s "$stage/jianqu.apk"
test -s "$stage/index.html"
test "$(stat -c '%s' "$stage/jianqu.apk")" -eq "$bytes"
printf '%s  %s\n' "$sha" "$stage/jianqu.apk" | sha256sum -c - >/dev/null
grep -Fq 'href="./3c.apk"' "$stage/index.html"
grep -Fq 'href="./jianqu.apk"' "$stage/index.html"

for file in jianqu.apk jianqu.sha256 index.html; do
  [[ ! -L "$target/$file" && ! -L "$target/$file.next" ]] || {
    echo "JIANQU_INSTALL=unsafe_symlink:$file" >&2
    exit 1
  }
done

# APK first, index last: no broken public download link during publication.
install -m 0644 "$stage/jianqu.apk" "$target/jianqu.apk.next"
mv -f "$target/jianqu.apk.next" "$target/jianqu.apk"
printf '%s  jianqu.apk\n' "$sha" > "$target/jianqu.sha256.next"
chmod 0644 "$target/jianqu.sha256.next"
mv -f "$target/jianqu.sha256.next" "$target/jianqu.sha256"
install -m 0644 "$stage/index.html" "$target/index.html.next"
mv -f "$target/index.html.next" "$target/index.html"

test "$(stat -c '%s' "$target/jianqu.apk")" -eq "$bytes"
printf '%s  %s\n' "$sha" "$target/jianqu.apk" | sha256sum -c - >/dev/null
test "$(stat -c '%s' "$target/3c.apk")" -eq 317264746
echo "JIANQU_APK_SHA256=$sha"
echo 'JIANQU_DOWNLOAD_URL=https://proto.3cgroup.cn/d/jianqu.apk'
