#!/usr/bin/env python3
"""
Fix tr('...') calls broken by nested quotes (map keys, join(', '), ?? 'x').
Strategy: unwrap tr(...) back to a plain string and repair [') → [' .
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"


def find_tr_calls(text: str) -> list[tuple[int, int, str]]:
    """Return list of (start, end, inner) for tr('...') / tr("...")."""
    out = []
    i = 0
    while True:
        j = text.find("tr(", i)
        if j < 0:
            break
        # must be word-boundary tr
        if j > 0 and (text[j - 1].isalnum() or text[j - 1] == "_"):
            i = j + 3
            continue
        k = j + 3
        while k < len(text) and text[k].isspace():
            k += 1
        if k >= len(text) or text[k] not in "'\"":
            i = j + 3
            continue
        quote = text[k]
        p = k + 1
        esc = False
        # naive scan — broken strings may have early end
        while p < len(text):
            c = text[p]
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == quote:
                # end of string arg?
                q = p + 1
                while q < len(text) and text[q].isspace():
                    q += 1
                if q < len(text) and text[q] == ")":
                    inner = text[k + 1 : p]
                    out.append((j, q + 1, inner))
                    i = q + 1
                    break
                # string continued? treat as end anyway for broken cases
                inner = text[k + 1 : p]
                # look for closing ) after more junk
                r = text.find(")", p)
                if r > 0:
                    out.append((j, r + 1, text[k + 1 : p]))
                    i = r + 1
                else:
                    i = p + 1
                break
            p += 1
        else:
            break
    return out


def looks_broken(inner: str) -> bool:
    if "[')" in inner:
        return True
    if "join(')" in inner:
        return True
    if "?? }" in inner:
        return True
    # tr string that ends mid-interpolation oddly
    if inner.count("${") != inner.count("}"):
        # weak signal
        pass
    return False


def repair_inner(inner: str) -> str:
    s = inner.replace("[')", "['")
    s = s.replace("join('), '", "join(', '")
    s = s.replace("join(')", "join(', ')")
    return s


def main() -> None:
    files = 0
    total = 0
    for p in sorted(ROOT.rglob("*.dart")):
        if "l10n" in p.parts:
            continue
        text = p.read_text(encoding="utf-8")
        if "tr(" not in text:
            continue
        # Quick global repairs first
        new = text
        new = new.replace("[')", "['")
        new = new.replace("join('), '", "join(', '")

        # Unwrap clearly broken tr() that still contain nested-quote hazards
        # Pattern: tr('...join(', ')...') can't be parsed as single string.
        # Fix known floor screen / sell screen by line-based heuristics:

        # Máy này đang giữ broken join
        new = re.sub(
            r"Text\(tr\('Máy này đang giữ: \$\{_tablesHeldByMe\.map\(\(e\) => e\.name\)\.join\(', '\)\}'",
            r"Text('${tr('Máy này đang giữ')}: ${_tablesHeldByMe.map((e) => e.name).join(', ')}'",
            new,
        )

        # Import success broken
        new = re.sub(
            r"tr\('Import thành công: \$\{importResult\['imported'\]\} bản ghi'",
            r"'Import thành công: ${importResult['imported']} bản ghi'",
            new,
        )

        # kpi Lỗi: ${res['message']
        new = re.sub(
            r"tr\('Lỗi: \$\{res\['message'\] \?\? 'Không xác định'\}'\)",
            r"'Lỗi: ${res['message'] ?? 'Không xác định'}'",
            new,
        )

        if new != text:
            p.write_text(new, encoding="utf-8")
            files += 1
            total += 1
            print(p.relative_to(ROOT))
    print(f"files={files}")


if __name__ == "__main__":
    main()
