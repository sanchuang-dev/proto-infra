#!/usr/bin/env bash
# Render proto's landing page from the lab site's canonical template + registry.
# No local fork of the layout, styles or project data is kept in proto-infra.
set -euo pipefail
out="${1:?expected output directory}"
source_rev=339c4f7db3713b133546f6d2096a109d7f8eb351
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q
git -C "$work" remote add origin https://github.com/sanchuang-dev/base-prototype.git
git -C "$work" fetch --quiet --no-tags --depth=1 origin "$source_rev"
git -C "$work" checkout --quiet --detach FETCH_HEAD
test "$(git -C "$work" rev-parse HEAD)" = "$source_rev"
(
  cd "$work"
  python3 scripts/render_portal.py
)
mkdir -p "$out"
python3 - "$work/_site/index.html" "$out/index.html" <<'PY'
from pathlib import Path
import sys

src, dst = map(Path, sys.argv[1:])
html = src.read_text(encoding="utf-8")
# Keep the lab template, all 6 original cards, copy, typography and colors.
# Only hosting destinations differ: our four first-batch apps have live Caddy hosts.
links = {
    'href="https://sanchuang-dev.github.io/ai-mirror/dev/"': 'href="https://ai-mirror.proto.3cgroup.cn/"',
    'href="https://sanchuang-dev.github.io/ai-beauty-mirror/"': 'href="https://beauty-mirror.proto.3cgroup.cn/"',
    'href="https://sanchuang-dev.github.io/ai-hair-mirror/"': 'href="https://hair-mirror.proto.3cgroup.cn/"',
    'href="https://sanchuang-dev.github.io/ai-fitting-mirror/"': 'href="https://fitting-mirror.proto.3cgroup.cn/"',
    # Lingnan remains hosted at lab, not on proto: never emit a broken local route.
    'href="./lingnan/"': 'href="https://lab.3cgroup.cn/lingnan/"',
}
for old, new in links.items():
    if html.count(old) != 1:
        raise SystemExit(f"Expected exactly one upstream link: {old}")
    html = html.replace(old, new, 1)
if (html.count('class="project ') != 6 or
        "让想法" not in html or
        "先被看见" not in html or
        "三创 · 演示中心" not in html or
        "<!--DEMO_CARDS-->" in html or
        "<!--DEMO_COUNT-->" in html):
    raise SystemExit("Unexpected upstream portal structure")
for expected in ['ai-mirror', 'beauty-mirror', 'hair-mirror', 'fitting-mirror']:
    if f'https://{expected}.proto.3cgroup.cn/' not in html:
        raise SystemExit(f"Missing local host: {expected}")
dst.write_text(html, encoding="utf-8")
print(f"PROTO_PORTAL_FROM_LAB={src.stat().st_size} upstream_bytes")
print(f"PROTO_PORTAL_CARDS={html.count('class=\"project ')}")
print(f"PROTO_PORTAL_WRITTEN={dst}")
PY
