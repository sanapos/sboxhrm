"""Chèn ảnh hướng dẫn vào flutter_client/web/guide.html.

Trong guide.html đặt chỗ ảnh bằng cặp chú thích:
    <!-- guide-shot:shifts-1 --><!-- /guide-shot -->
Script thay phần giữa bằng <figure> (ảnh máy tính + điện thoại, chú thích lấy từ
manifest.json do test/guide_shots/guide_manifest_test.dart ghi — cùng chú thích với app).

Dùng: guide_html_shots.py <manifest.json> <guide.html>
"""
import html
import json
import pathlib
import re
import sys

manifest = {r["name"]: r for r in json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))}
page = pathlib.Path(sys.argv[2])
with open(page, encoding="utf-8", newline="") as f:
    src = f.read()
NL = "\r\n" if "\r\n" in src else "\n"

MARK = re.compile(r"<!-- guide-shot:([a-z0-9-]+) -->.*?<!-- /guide-shot -->", re.S)
used, missing = set(), []


def figure(m: re.Match) -> str:
    name = m.group(1)
    row = manifest.get(name)
    if row is None:
        missing.append(name)
        return m.group(0)
    used.add(name)
    bullet = re.sub(r"^Bước \d+\s*[—-]\s*", "", row["bullet"])
    alt = html.escape(f"{row['stepTitle']}: {bullet}", quote=True)
    cap = html.escape(row["caption"])
    base = f"/images/guide/{name}"
    return (
        f"<!-- guide-shot:{name} -->{NL}"
        f'<figure class="shot"><a href="{base}.webp" target="_blank" rel="noopener"><picture>'
        f'<source media="(max-width: 600px)" srcset="{base}-mobile.webp" width="390" height="844">'
        f'<img src="{base}.webp" width="1280" height="800" loading="lazy" decoding="async" alt="{alt}">'
        f"</picture></a><figcaption>{cap}</figcaption></figure>{NL}"
        f"<!-- /guide-shot -->"
    )


out = MARK.sub(figure, src)
if out != src:
    with open(page, "w", encoding="utf-8", newline="") as f:
        f.write(out)
print(f"guide.html: {len(used)} images placed")
if missing:
    print("  marker without image (not in manifest): " + ", ".join(missing))
unplaced = sorted(set(manifest) - used)
if unplaced:
    print("  images without marker in guide.html: " + ", ".join(unplaced))
