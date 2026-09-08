# -*- coding: utf-8 -*-
from pathlib import Path
import re

p = Path("flutter_client/web/home.html")
t = p.read_text(encoding="utf-8")
t = t.replace("https://sbox.sana.vn", "https://sboxhrm.com")
t = re.sub(r"(?<!id=)sbox\.sana\.vn", "sboxhrm.com", t)
t = t.replace('href="https://sboxhrm.com/home.html"', 'href="https://sboxhrm.com/"')
t = t.replace('content="https://sboxhrm.com/home.html"', 'content="https://sboxhrm.com/"')
t = t.replace('"url": "https://sboxhrm.com/home.html"', '"url": "https://sboxhrm.com/"')
t = t.replace('href="/home.html"', 'href="/"')
if "hreflang" not in t:
    t = t.replace(
        '<link rel="canonical" href="https://sboxhrm.com/" />',
        '<link rel="canonical" href="https://sboxhrm.com/" />\n'
        '  <link rel="alternate" hreflang="vi" href="https://sboxhrm.com/" />\n'
        '  <link rel="alternate" hreflang="x-default" href="https://sboxhrm.com/" />',
    )
p.write_text(t, encoding="utf-8", newline="\n")
print("sana left:", "sbox.sana.vn" in t and "play.google.com" not in t or "sbox.sana.vn" in t.replace("id=sbox.sana.vn", ""))
for ln in t.splitlines():
    if "canonical" in ln or "og:url" in ln:
        print(ln)
print("faq", 'id="faq"' in t, "FAQPage" in t)
