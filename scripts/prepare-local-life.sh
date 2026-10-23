#!/usr/bin/env bash
# Build the accepted local-life prod revision for the root of its dedicated proto hostname.
set -euo pipefail
out="${1:?expected output directory}"
source_rev=72de73a858461c87693127bedfa9117ac33a02d1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git -C "$work" init -q
git -C "$work" remote add origin https://github.com/sanchuang-dev/local-life.git
git -C "$work" fetch --quiet --no-tags --depth=1 origin "$source_rev"
git -C "$work" checkout --quiet --detach FETCH_HEAD
test "$(git -C "$work" rev-parse HEAD)" = "$source_rev"

(
  cd "$work"
  npm ci --no-audit --no-fund
  npm run lint
  npx tsc -b
  npx vite build --base /
)

test -s "$work/dist/index.html"
grep -Fq '<title>三创 · 本地生活</title>' "$work/dist/index.html"
if grep -Fq '/local-life/assets/' "$work/dist/index.html"; then
  echo "Unexpected GitHub Pages base in company-server build" >&2
  exit 1
fi
grep -Eq '(src|href)="/assets/' "$work/dist/index.html"

mkdir -p "$out"
tar -czf "$out/local-life.tar.gz" -C "$work/dist" .
echo "LOCAL_LIFE_SOURCE=$source_rev"
echo "LOCAL_LIFE_BASE=root"
