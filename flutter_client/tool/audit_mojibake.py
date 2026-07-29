"""Find Vietnamese text that was double-encoded (UTF-8 read as cp1252) in the C# source."""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(REPO, 'src')

# Sequences that only appear when UTF-8 bytes were decoded as cp1252/latin-1.
MOJI = re.compile(r'Ã[\u0080-\u00ff¡-ÿ]|á»|áº|Ä‘|Ä[\u0080-\u00ff]|Æ°|â€|Ãƒ')
VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ]')


def unmojibake(s, rounds=3):
    """Reverse the cp1252 misdecode, repeating while it still improves the text."""
    best = s
    cur = s
    for _ in range(rounds):
        try:
            nxt = cur.encode('cp1252', errors='strict').decode('utf-8', errors='strict')
        except (UnicodeEncodeError, UnicodeDecodeError):
            try:
                nxt = cur.encode('latin-1', errors='strict').decode('utf-8', errors='strict')
            except (UnicodeEncodeError, UnicodeDecodeError):
                break
        cur = nxt
        if not MOJI.search(cur):
            return cur
        best = cur
    return cur if not MOJI.search(cur) else best


def main():
    hits = []
    for dirpath, _d, filenames in os.walk(SRC):
        if any(p in dirpath for p in (os.sep + 'obj', os.sep + 'bin')):
            continue
        for fn in filenames:
            if not fn.endswith(('.cs', '.json')):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, REPO)
            try:
                text = open(p, encoding='utf-8').read()
            except Exception:
                continue
            for i, line in enumerate(text.splitlines(), 1):
                if MOJI.search(line):
                    hits.append((rel, i, line.strip()[:110]))

    files = sorted({h[0] for h in hits})
    print('mojibake lines:', len(hits), 'in', len(files), 'files')
    for f in files:
        n = sum(1 for h in hits if h[0] == f)
        print(f'  {n:4d}  {f}')

    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 12
    print('--- samples with repair preview ---')
    for rel, ln, line in hits[:limit]:
        fixed = unmojibake(line)
        ok = 'OK ' if VN.search(fixed) and not MOJI.search(fixed) else '?? '
        print(f'{ok}{rel}:{ln}')
        print(f'    before: {line}')
        print(f'    after : {fixed}')

    json.dump(files, open(os.path.join(HERE, 'mojibake_files.json'), 'w',
                          encoding='utf-8'), ensure_ascii=False, indent=1)
    print('wrote tool/mojibake_files.json')


if __name__ == '__main__':
    main()
