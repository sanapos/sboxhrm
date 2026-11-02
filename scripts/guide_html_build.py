"""Dựng phần nội dung flutter_client/web/guide.html từ hướng dẫn trong app.

Nguồn: src/ZKTecoADMS.Api/Services/HelpCorpus/landing-guide.json (khu → nhóm → bước, kèm ảnh),
do test/guide_shots/guide_corpus_test.dart xuất từ landing_usage_guide.dart / landing_guide_groups.dart.
Giữ nguyên <head>, header, footer của guide.html; sinh lại mục lục + nội dung trong <div class="wrap">.
Cùng một nguồn với màn /guide trong app và trợ lý AI — không sửa tay phần nội dung guide.html.

Dùng: guide_html_build.py <landing-guide.json> <guide.html>
"""
import datetime
import html
import json
import pathlib
import re
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
page = pathlib.Path(sys.argv[2])
with open(page, encoding="utf-8", newline="") as f:
    src = f.read()
NL = "\r\n" if "\r\n" in src else "\n"

# Mốc cũ của guide.html (link ngoài có thể còn trỏ tới) → nhóm mới.
LEGACY = {
    "hrm_setup": ["hrm-start"],
    "hrm_reports": ["hrm-reports", "hrm-daily", "hrm-cases"],
    "hrm_tools": ["hrm-advanced"],
    "pos_init": ["pos-start"],
    "pos_selling": ["pos-sell"],
    "pos_stock": ["pos-stock"],
    "pos_einvoice_group": ["pos-einvoice"],
    "pos_reports_group": ["pos-reports"],
    "pos_rules_group": ["pos-cases", "rules"],
    "ind_start": ["industry"],
}
STEP_PREFIX = re.compile(r"^Bước \d+\s*[—-]\s*")


def e(s):
    return html.escape(s or "", quote=False)


def figure(shot, step):
    name = shot["name"]
    base = f"/images/guide/{name}"
    alt = html.escape(f"{step['title']}: {shot['caption']}", quote=True)
    return (
        f'<figure class="shot"><a href="{base}.webp" target="_blank" rel="noopener"><picture>'
        f'<source media="(max-width: 600px)" srcset="{base}-mobile.webp" width="390" height="844">'
        f'<img src="{base}.webp" width="1280" height="800" loading="lazy" decoding="async" alt="{alt}">'
        f"</picture></a><figcaption>{e(shot['caption'])}</figcaption></figure>"
    )


steps_by_group = {}
for s in doc["steps"]:
    steps_by_group.setdefault((s["area"], s["group"]), []).append(s)

out = []
w = out.append
w('<div class="wrap">')
w('  <nav class="toc" aria-label="Mục lục">')
w("    <h2>Mục lục</h2>")
n = 0
numbered = []
for a in doc["areas"]:
    w(f'    <h3>{e("Hướng dẫn " + a["title"])}</h3>')
    for g in a["groups"]:
        items = steps_by_group.get((a["id"], g["id"]), [])
        if not items:
            continue
        n += 1
        numbered.append((n, a, g, items))
        w(f'    <a href="#{g["id"]}">{n}. {e(g["title"])} <span class="toc-n">({len(items)})</span></a>')
w("  </nav>")
for n, a, g, items in numbered:
    w("")
    for old in LEGACY.get(g["id"], []):
        w(f'  <span id="{old}" class="anchor"></span>')
    w(f'  <article id="{g["id"]}">')
    w(f'    <p class="area">{e("Hướng dẫn " + a["title"])}</p>')
    w(f'    <h2>{n}. {e(g["title"])}</h2>')
    w(f'    <p class="sub">{e(g["subtitle"])}</p>')
    for s in items:
        w(f'    <h3 id="{s["stepId"]}">{e(s["title"])}</h3>')
        if s.get("desc"):
            w(f"    <p>{e(s['desc'])}</p>")
        shots = {}
        for shot in s.get("shots") or []:
            shots.setdefault(shot["afterBullet"], []).append(shot)
        if s.get("bullets"):
            w("    <ol>")
            for i, b in enumerate(s["bullets"], start=1):
                figs = "".join(f"{NL}        {figure(x, s)}" for x in shots.get(i, []))
                end = f"{NL}      </li>" if figs else "</li>"
                w(f"      <li>{e(STEP_PREFIX.sub('', b))}{figs}{end}")
            w("    </ol>")
        if s.get("tip"):
            w(f'    <p class="tip">{e(s["tip"])}</p>')
    w("  </article>")
w("</div>")
body = NL.join(out) + NL

start = src.index('<div class="wrap">')
end = src.index("<footer>")
new = src[:start] + body + src[end:]

# Ngày cập nhật trên đầu trang + JSON-LD.
today = datetime.date.today()
new = re.sub(r"Cập nhật \d{2}/\d{2}/\d{4}", f"Cập nhật {today:%d/%m/%Y}", new)
new = re.sub(r'"dateModified": "\d{4}-\d{2}-\d{2}"', f'"dateModified": "{today:%Y-%m-%d}"', new)

# Kiểu chữ cho phần mới (thêm một lần).
if ".toc h3" not in new:
    css = (
        "    .toc h3 { font-size: 13px; color: #64748b; text-transform: uppercase; letter-spacing: .04em; margin: 14px 0 4px; }" + NL
        + "    .toc-n { color: #94a3b8; font-size: 12px; }" + NL
        + "    article .area { font-size: 12px; font-weight: 700; color: #64748b; text-transform: uppercase; letter-spacing: .04em; margin-bottom: 4px; }" + NL
        + "    article .sub { color: #64748b; font-size: 14px; }" + NL
        + "    article h3 { scroll-margin-top: 12px; border-top: 1px solid #eef2f7; padding-top: 16px; }" + NL
        + "    .anchor { display: block; position: relative; top: -12px; }" + NL
    )
    new = new.replace("  </style>", css + "  </style>", 1)

with open(page, "w", encoding="utf-8", newline="") as f:
    f.write(new)
shots = sum(len(s.get("shots") or []) for s in doc["steps"])
print(f"guide.html: {len(numbered)} groups, {len(doc['steps'])} steps, {shots} images")
