#!/usr/bin/env bash
# Build an immutable, zero-build H5 snapshot from the fitness mirror's design source.
set -euo pipefail
dest="$1"
test -n "$dest"
source_revision="8d618555aabe87c34b0d7d0b0ecd801311047c30"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$dest"
git -C "$work" init -q
git -C "$work" remote add origin https://github.com/sanchuang-dev/ai-fitness-mirror.git
git -C "$work" fetch --quiet --no-tags --depth=1 origin "$source_revision"
git -C "$work" checkout --quiet --detach FETCH_HEAD
test "$(git -C "$work" rev-parse HEAD)" = "$source_revision"
source_dir="$work/prototype"
for path in index.html gym.html hotel.html assets/mirror.css assets/mirror.js assets/stock/credits.json; do
  test -s "$source_dir/$path"
done
node --check "$source_dir/assets/mirror.js"
python3 - "$source_dir" <<'PY'
import pathlib,re,sys
root=pathlib.Path(sys.argv[1])
for page in ("index.html","gym.html","hotel.html"):
    content=(root/page).read_text(encoding="utf-8")
    for url in re.findall(r'''(?:src|href)=["']([^"']+)["']''',content):
        if url.startswith(("https://","http://","#","mailto:","javascript:")): continue
        target=root/url.split("#")[0].split("?")[0]
        if not target.is_file(): raise SystemExit(f"{page}: missing local resource: {url}")
    print(f"FITNESS_ENTRY_CHECK={page}:valid")
PY
tar -czf "$dest/fitness-mirror.tar.gz" -C "$source_dir" .
test -s "$dest/fitness-mirror.tar.gz"
echo "FITNESS_SOURCE_REVISION=$source_revision"
