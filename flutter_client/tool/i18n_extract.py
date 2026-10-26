#!/usr/bin/env python3
"""Collect every Vietnamese UI string the app can show, for ko/ja/zh (and missing en).

Sources:
  * lib/l10n/en_ui_map.g.dart  — the existing VI→EN map (keys = runtime strings)
  * tr('...') / trN / trOr literals in lib/ — static ones and interpolated ones
    (interpolations become {0}, {1}… templates matched at runtime by app_tr.dart)
  * the 'vi' section of lib/l10n/app_localizations.dart

Writes tool/i18n/source.json.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from dart_scan import skip_braces, skip_string

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
OUT_DIR = ROOT / "tool" / "i18n"

VN = re.compile(
    r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
    r"ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ]"
)
# Mojibake leftovers (Ã, Â, â€…) — never real UI copy.
# (A bare "Ã" is real Vietnamese — "MÃ CỬA HÀNG" — so only match the byte pairs.)
MOJIBAKE = re.compile(r"[ÃÂ][\u0080-¿]|â€|Ä‘|Æ°|á»|áº")
TR_CALL = re.compile(r"(?<![\w.$])tr(?:N|Or)?\(\s*")
PLACEHOLDER = re.compile(r"\{(\d+)\}")


def dart_unescape(s: str) -> str:
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "t": "\t", "r": ""}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def parse_map(path: Path) -> dict[str, str]:
    pair = re.compile(r"^\s*'((?:[^'\\]|\\.)*)':\s*'((?:[^'\\]|\\.)*)',\s*$")
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = pair.match(line)
        if m:
            out[dart_unescape(m.group(1))] = dart_unescape(m.group(2))
    return out


def literal_to_template(lit: str) -> tuple[str, int] | None:
    """Dart string literal source (with quotes) → (text with {n} holes, hole count)."""
    raw = lit.startswith("r")
    body = lit[1:] if raw else lit
    q = body[0]
    term = q * 3 if body.startswith(q * 3) else q
    body = body[len(term):-len(term)]
    out: list[str] = []
    holes = 0
    i = 0
    while i < len(body):
        c = body[i]
        if not raw and c == "\\" and i + 1 < len(body):
            out.append(dart_unescape(body[i:i + 2]))
            i += 2
            continue
        if not raw and c == "$" and i + 1 < len(body):
            if body[i + 1] == "{":
                i = skip_braces(body, i + 1)
            else:
                j = i + 1
                while j < len(body) and (body[j].isalnum() or body[j] == "_"):
                    j += 1
                if j == i + 1:
                    out.append(c)
                    i += 1
                    continue
                i = j
            out.append("{%d}" % holes)
            holes += 1
            continue
        if c in "{}":
            return None  # literal braces would clash with holes
        out.append(c)
        i += 1
    return "".join(out), holes


def scan_tr_literals() -> tuple[set[str], set[str]]:
    statics: set[str] = set()
    templates: set[str] = set()
    for p in sorted(LIB.rglob("*.dart")):
        if "l10n" in p.parts or p.name.endswith(".g.dart"):
            continue
        text = p.read_text(encoding="utf-8", errors="ignore")
        for m in TR_CALL.finditer(text):
            i = m.end()
            if i >= len(text):
                continue
            if not (text[i] in "'\"" or (text[i] == "r" and text[i + 1:i + 2] in ("'", '"'))):
                continue
            end = skip_string(text, i)
            # Adjacent-literal concatenation ('a' 'b') is rare; skip it.
            rest = text[end:end + 40].lstrip()
            if rest[:1] in ("'", '"'):
                continue
            conv = literal_to_template(text[i:end])
            if not conv:
                continue
            s, holes = conv
            if not VN.search(s) or MOJIBAKE.search(s):
                continue
            if holes == 0:
                statics.add(s)
            else:
                static_part = PLACEHOLDER.sub("", s)
                # Adjacent holes cannot be split back apart at runtime.
                if re.search(r"\}\{", s) or not VN.search(static_part):
                    continue
                templates.add(s)
    return statics, templates


# Long legal / help documents are kept in their source language on purpose.
SKIP_LITERAL_FILES = {"app_legal_pages.dart"}
# Diacritic tables used by search/normalisation code ('àáạảã…').
CHAR_TABLE = re.compile(r"(?:[àáạảãâầấậẩẫăằắặẳẵ]{3}|[èéẹẻẽ]{3}|[ìíịỉĩ]{3}|[òóọỏõ]{3})")


def scan_all_literals() -> tuple[set[str], set[str]]:
    """Every Vietnamese string literal in lib/, not only direct tr('…') arguments.

    Much UI copy reaches tr() through a variable, getter or config list
    (tr(item.title), tr(SboxAppVariant.loginHeroTitle)); the runtime lookup only
    works when that copy is in the pack too.
    """
    statics: set[str] = set()
    templates: set[str] = set()
    for p in sorted(LIB.rglob("*.dart")):
        if "l10n" in p.parts or p.name.endswith(".g.dart") or p.name in SKIP_LITERAL_FILES:
            continue
        t = p.read_text(encoding="utf-8", errors="ignore")
        n = len(t)
        i = 0
        while i < n:
            c = t[i]
            if t.startswith("//", i):
                j = t.find("\n", i)
                i = n if j < 0 else j
                continue
            if t.startswith("/*", i):
                j = t.find("*/", i)
                i = n if j < 0 else j + 2
                continue
            is_raw = c == "r" and t[i + 1:i + 2] in ("'", '"') and not (i and (t[i - 1].isalnum() or t[i - 1] == "_"))
            if c in "'\"" or is_raw:
                e = skip_string(t, i)
                conv = literal_to_template(t[i:e])
                i = e
                if not conv:
                    continue
                s, holes = conv
                if (len(s.strip()) < 2 or not VN.search(s) or MOJIBAKE.search(s)
                        or CHAR_TABLE.search(s)):
                    continue
                if holes == 0:
                    statics.add(s)
                elif "}{" not in s and VN.search(PLACEHOLDER.sub("", s)):
                    templates.add(s)
                continue
            i += 1
    return statics, templates


def app_localizations_vi() -> set[str]:
    src = (LIB / "l10n" / "app_localizations.dart").read_text(encoding="utf-8")
    start = src.find("'vi': {")
    end = src.find("'en': {")
    seg = src[start:end]
    vals = re.findall(r"'[A-Za-z0-9_]+'\s*:\s*'((?:[^'\\]|\\.)*)'", seg)
    return {dart_unescape(v) for v in vals}


def main() -> None:
    en_map = parse_map(LIB / "l10n" / "en_ui_map.g.dart")
    statics, templates = scan_tr_literals()
    all_statics, all_templates = scan_all_literals()
    statics |= all_statics
    templates |= all_templates
    loc_vi = app_localizations_vi()

    texts = set()
    for k in en_map:
        if k.strip() and re.search(r"[^\W\d_]", k) and not MOJIBAKE.search(k):
            texts.add(k)
    texts |= statics
    texts |= {v for v in loc_vi if VN.search(v)}

    en_missing = sorted(t for t in texts if en_map.get(t, t) == t)
    OUT_DIR.mkdir(exist_ok=True)
    data = {
        "texts": sorted(texts),
        "templates": sorted(templates),
        "en_missing_texts": en_missing,
    }
    (OUT_DIR / "source.json").write_text(
        json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    chars = sum(len(t) for t in texts) + sum(len(t) for t in templates)
    print(f"texts={len(texts)} templates={len(templates)} "
          f"en_missing={len(en_missing)} chars={chars}")


if __name__ == "__main__":
    main()
