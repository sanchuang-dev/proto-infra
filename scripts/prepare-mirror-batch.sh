#!/usr/bin/env bash
set -euo pipefail
dest="$1"; mkdir -p "$dest"
fetch_static() {
  repo="$1"; sha="$2"; sub="$3"; slug="$4"
  checkout=$(mktemp -d)
  git -C "$checkout" init -q
  git -C "$checkout" remote add origin "https://github.com/sanchuang-dev/$repo.git"
  git -C "$checkout" fetch --quiet --no-tags --depth=1 origin "$sha"
  git -C "$checkout" checkout --quiet --detach FETCH_HEAD
  test "$(git -C "$checkout" rev-parse HEAD)" = "$sha"
  test -s "$checkout/$sub/index.html"
  tar -czf "$dest/$slug.tar.gz" -C "$checkout/$sub" .
  rm -rf "$checkout"
  echo "SOURCE=$repo:$sha"
}
# Exact revisions, not volatile branch HEADs: zero-build static snapshots.
fetch_static ai-mirror e4ac70f46ed99bfd84191f906af705df445ebd4e web ai-mirror
fetch_static ai-beauty-mirror da7bb94c5446d7037f02e8909c043eb17c97da9b prototype beauty-mirror
fetch_static ai-hair-mirror 1f65f8dcd07b2b6fc22a8ef83a477068923311b2 prototype hair-mirror
fetch_static ai-fitting-mirror cac98705321b08db55ed93b42fcb62642e8be93a prototype fitting-mirror
