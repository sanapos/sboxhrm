"""Repair double-encoded Vietnamese (UTF-8 read as cp1252) in the C# source.

Works on maximal runs of non-ASCII characters. That is safe because a UTF-8
multi-byte sequence never contains an ASCII byte, so each run round-trips
independently and ASCII punctuation/spacing is never touched. Runs that are not
mojibake (emoji, already-correct Vietnamese) fail the round-trip and are left
alone.

    python tool/fix_mojibake.py           # dry run
    python tool/fix_mojibake.py --apply
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(REPO, 'src')

MOJI = re.compile(r'Ã[\u0080-\u00ff¡-ÿ]|á»|áº|Ä‘|Ä[\u0080-\u00ff]|Æ°|â€|Ãƒ')
NON_ASCII_RUN = re.compile(r'[^\x00-\x7f]+')
VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]')

# Holds mojibake on purpose, to detect it at runtime.
EXCLUDE = {'VietnameseEncodingFix.cs'}


PUNCT_REPAIR = re.compile(r'^[–—‘’“”…•·°→⚠✅🔧🛠️]+$')

# Byte for each character a cp1252/latin-1 misdecode can produce. cp1252 wins where
# it defines a mapping (0x91 -> "’"); the C1 range falls back to latin-1, which is
# what preserved bytes like 0x81 as U+0081 in these files.
_BYTE_OF_CHAR = {}
for _b in range(0x80, 0x100):
    try:
        _BYTE_OF_CHAR.setdefault(bytes([_b]).decode('cp1252'), _b)
    except UnicodeDecodeError:
        pass
for _b in range(0x80, 0x100):
    _BYTE_OF_CHAR.setdefault(chr(_b), _b)


def to_bytes(s):
    """Reverse the misdecode: turn displayed characters back into their bytes."""
    out = bytearray()
    for ch in s:
        o = ord(ch)
        if o < 0x80:
            out.append(o)
            continue
        b = _BYTE_OF_CHAR.get(ch)
        if b is None:
            return None
        out.append(b)
    return bytes(out)


def repair_run(run):
    """Decode a non-ASCII run back to Vietnamese, repeating for double encodings.

    Neither cp1252 nor latin-1 has a code point for a precomposed Vietnamese
    letter, so a run that maps cleanly back to bytes cannot be real Vietnamese —
    which makes a successful round-trip to valid UTF-8 proof that it was mojibake.
    Genuine Vietnamese has no byte mapping and is returned untouched.
    """
    cur = run
    best = None
    for _ in range(4):
        raw = to_bytes(cur)
        if raw is None:
            break
        try:
            nxt = raw.decode('utf-8')
        except UnicodeDecodeError:
            break
        if nxt == cur:
            break
        cur = nxt
        if VN.search(cur) or PUNCT_REPAIR.match(cur):
            best = cur
    return best if best is not None else run


def repair_text(text):
    fixes = [0]

    def sub(m):
        run = m.group(0)
        out = repair_run(run)
        if out != run:
            fixes[0] += 1
        return out

    return NON_ASCII_RUN.sub(sub, text), fixes[0]


def main():
    apply = '--apply' in sys.argv
    total_files = total_fixes = 0
    unresolved = []

    for dirpath, _d, filenames in os.walk(SRC):
        if any(p in dirpath for p in (os.sep + 'obj', os.sep + 'bin')):
            continue
        for fn in filenames:
            if not fn.endswith('.cs') or fn in EXCLUDE:
                continue
            p = os.path.join(dirpath, fn)
            try:
                text = open(p, encoding='utf-8').read()
            except Exception:
                continue
            if not MOJI.search(text):
                continue
            fixed, n = repair_text(text)
            rel = os.path.relpath(p, REPO)
            left = len(MOJI.findall(fixed))
            print(f'{"FIX " if apply else "DRY "}{rel}: {n} runs repaired'
                  + (f', {left} still mojibake' if left else ''))
            if left:
                unresolved.append(rel)
                for ln, line in enumerate(fixed.splitlines(), 1):
                    if MOJI.search(line):
                        print(f'      left {ln}: {line.strip()[:100]}')
                        break
            total_files += 1
            total_fixes += n
            if apply and fixed != text:
                open(p, 'w', encoding='utf-8', newline='').write(fixed)

    print(f'\nfiles: {total_files}, runs repaired: {total_fixes}')
    if unresolved:
        print('needs a manual look:', ', '.join(unresolved))


if __name__ == '__main__':
    main()
