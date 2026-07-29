"""Simulate Dart tr() over dynamic tr() templates to measure the true residual gap."""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), 'lib')
DART = os.path.join(LIB, 'l10n', 'en_ui_map.g.dart')

VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]')

src = open(DART, encoding='utf-8').read()
MAP = dict(re.findall(
    r"^\s*r?'((?:[^'\\]|\\.)*)':\s*r?'((?:[^'\\]|\\.)*)',\s*$", src, re.M))
PHRASE_MIN = 10
LONG = sorted([(k, v) for k, v in MAP.items() if len(k) >= PHRASE_MIN],
              key=lambda kv: -len(kv[0]))

PHRASES = sorted(
    [(k, v) for k, v in MAP.items()
     if len(k) >= 2 and VN.search(k) and not VN.search(v)],
    key=lambda kv: -len(kv[0]))

# Letters only, mirroring _wordChar in app_tr.dart: a digit abutting a fragment is
# a real boundary because no Vietnamese word contains one.
WORD = re.compile(r'[^\W\d_]', re.UNICODE)


def replace_fragments(s):
    out, changed = s, False
    for vi, en in PHRASES:
        i = out.find(vi)
        while i >= 0:
            end = i + len(vi)
            before_ok = i == 0 or not WORD.match(out[i - 1])
            after_ok = end >= len(out) or not WORD.match(out[end])
            if before_ok and after_ok:
                out = out[:i] + en + out[end:]
                changed = True
                i = out.find(vi, i + len(en))
            else:
                i = out.find(vi, i + 1)
    if not changed:
        return None
    probe = re.sub(r'(?<![^\W\d_])đ(?![^\W\d_])', '', out, flags=re.I)
    return None if VN.search(probe) else out


def tr(s):
    if s in MAP:
        return MAP[s]
    t = s.strip()
    if t != s and t in MAP:
        return s.replace(t, MAP[t], 1)
    for suf in (':', '...', '…', '.', '!', '?', ' *', '*'):
        if t.endswith(suf):
            core = t[:-len(suf)].rstrip()
            if core in MAP:
                return MAP[core] + suf
    frag = replace_fragments(s)
    if frag is not None:
        return frag
    i = t.find(': ')
    if i > 1 and t[:i] in MAP:
        return MAP[t[:i]] + t[i:]
    for sep in (' • ', ' | ', ' - ', ' / '):
        if sep in t:
            parts = t.split(sep)
            hit = False
            out = []
            for p in parts:
                q = MAP.get(p.strip())
                if q:
                    hit = True
                out.append(q or p)
            if hit:
                return sep.join(out)
    if len(s) < PHRASE_MIN:
        return s
    res, changed = s, False
    for k, v in LONG:
        if k in res:
            res = res.replace(k, v)
            changed = True
    return res if changed else s


# Render a Dart template into a plausible runtime string.
EXPR = re.compile(r'\$\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}|\$[A-Za-z_][A-Za-z0-9_]*')


ESCAPES = {r'\n': '\n', r'\t': '\t', r'\r': '\r', r"\'": "'", r'\"': '"'}


def render(tmpl):
    out = EXPR.sub('7', tmpl)
    # The literals are read straight from source, so an escape is still two
    # characters. Left as-is, the "n" of "\n" looks like a letter and defeats the
    # word-boundary check that Dart applies against a real newline at runtime.
    for esc, ch in ESCAPES.items():
        out = out.replace(esc, ch)
    return out


templates = json.load(
    open(os.path.join(HERE, 'literal_misses.json'), encoding='utf-8'))
still_vn = []
for t in templates:
    out = tr(render(t))
    # the đồng currency symbol is correct in English too
    probe = re.sub(r'(?<![^\W\d_])đ(?![^\W\d_])', '', out, flags=re.I)
    if VN.search(probe):
        still_vn.append((t, out))

print('templates checked:', len(templates))
print('still Vietnamese after tr():', len(still_vn))
limit = int(sys.argv[1]) if len(sys.argv) > 1 else 30
for t, out in still_vn[:limit]:
    print(f'{t[:70]}   ==>   {out[:70]}')

with open(os.path.join(HERE, 'tr_residual.json'), 'w', encoding='utf-8') as f:
    json.dump([t for t, _ in still_vn], f, ensure_ascii=False, indent=1)
print('wrote tool/tr_residual.json')
