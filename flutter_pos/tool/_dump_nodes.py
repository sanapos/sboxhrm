# -*- coding: utf-8 -*-
import re
import sys

src = sys.argv[1]
dst = sys.argv[2]
raw = open(src, encoding="utf-8", errors="replace").read()
out = []
for m in re.finditer(
    r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
    raw,
):
    if m.group(1):
        d = m.group(1).replace("\n", " / ")
        out.append(f"{m.group(2)},{m.group(3)}-{m.group(4)},{m.group(5)} | {d}")
open(dst, "w", encoding="utf-8").write("\n".join(out))
print(len(out))
