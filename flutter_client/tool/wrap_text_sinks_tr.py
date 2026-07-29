#!/usr/bin/env python3
"""Wrap display sinks with tr() so dynamic Vietnamese strings translate too.

Targets the *render* site (Text(...), Tab(text:), tooltip:, hintText:, ...)
instead of every source literal, so strings coming from variables, lists,
ternaries or API data are translated as well.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dart_scan import first_arg_span, value_span  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
SKIP_DIRS = {"l10n"}

CTORS = re.compile(r"(?<![\w.$'\"])(Text|SelectableText)\s*\(")
NAMED = re.compile(
    r"(?<![\w.$])(text|tooltip|hintText|labelText|helperText|semanticLabel|"
    r"errorText|prefixText|suffixText|counterText)\s*:"
)
ALREADY = re.compile(r"^(tr|trOr|trN)\s*\(")
NON_STRING = re.compile(
    r"^(const\s+)?(Text|RichText|TextSpan|WidgetSpan|InlineSpan|Icon|Row|Column|"
    r"Container|Widget|Padding|SizedBox|Expanded|Flexible|Center|Align|Wrap|"
    r"Stack|Tooltip)\b"
)
NUMERIC = re.compile(r"^[\d\s.,+\-*/()]+$")


def should_wrap(arg: str) -> bool:
    arg = arg.strip()
    if not arg or ALREADY.match(arg):
        return False
    if NON_STRING.match(arg) or NUMERIC.match(arg):
        return False
    if arg in ("null", "'", '"'):
        return False
    if arg.startswith("'") and arg.endswith("'") and len(arg) <= 2:
        return False
    if arg.startswith('"') and arg.endswith('"') and len(arg) <= 2:
        return False
    return True


def wrap_positional(text: str) -> tuple[str, int]:
    n = 0
    for m in reversed(list(CTORS.finditer(text))):
        # Skip Text.rich / Text.new handled elsewhere (regex already excludes).
        span = first_arg_span(text, m.end() - 1)
        if span is None:
            continue
        s, e = span
        arg = text[s:e].rstrip()
        if not should_wrap(arg):
            continue
        text = text[:s] + f"tr({arg})" + text[s + len(arg):]
        n += 1
    return text, n


def is_named_arg(text: str, start: int) -> bool:
    """True when the identifier at [start] really opens a named argument."""
    j = start - 1
    while j >= 0 and text[j] in " \t\r\n":
        j -= 1
    return j >= 0 and text[j] in "(,"


def wrap_named(text: str) -> tuple[str, int]:
    n = 0
    for m in reversed(list(NAMED.finditer(text))):
        if not is_named_arg(text, m.start()):
            continue
        span = value_span(text, m.end() - 1)
        if span is None:
            continue
        s, e = span
        arg = text[s:e].rstrip()
        if not should_wrap(arg):
            continue
        text = text[:s] + f"tr({arg})" + text[s + len(arg):]
        n += 1
    return text, n


def ensure_import(text: str, path: Path) -> str:
    if "l10n/app_tr.dart" in text:
        return text
    rel = "/".join([".."] * len(path.relative_to(LIB).parts[:-1]) or ["."])
    line = f"import '{rel}/l10n/app_tr.dart';\n"
    lines = text.splitlines(keepends=True)
    last = -1
    for i, ln in enumerate(lines):
        if ln.startswith("import ") and ln.rstrip().endswith(";"):
            last = i
    if last < 0:
        return line + text
    lines.insert(last + 1, line)
    return "".join(lines)


def main() -> None:
    files = 0
    total = 0
    for p in sorted(LIB.rglob("*.dart")):
        if SKIP_DIRS & set(p.parts):
            continue
        src = p.read_text(encoding="utf-8")
        out, a = wrap_positional(src)
        out, b = wrap_named(out)
        if a + b == 0:
            continue
        out = ensure_import(out, p)
        p.write_text(out, encoding="utf-8")
        files += 1
        total += a + b
        print(f"{p.relative_to(LIB)}\tpositional={a} named={b}")
    print(f"\nfiles={files} wrapped={total}")


if __name__ == "__main__":
    main()
