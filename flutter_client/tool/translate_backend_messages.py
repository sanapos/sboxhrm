"""Add the API's Vietnamese messages to en_ui_map so tr() can translate them.

The server sends copy like "Không tìm thấy nhân viên" straight into snackbars and
notifications. Whole messages become exact keys; messages with {placeholders} are
also split into fragments so the runtime string still resolves.
"""
import json
import os
import re
import subprocess
import sys
import time

from deep_translator import GoogleTranslator

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'backend_misses.json')
OUT = os.path.join(HERE, 'backend_en.json')
MAIN = os.path.join(HERE, 'en_ui_map.json')

VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]')
PLACEHOLDER = re.compile(r'\{[^{}]*\}')
STRIP = ' \t:·•|/()[]-—,.?!%"\\\n'


def targets():
    msgs = json.load(open(SRC, encoding='utf-8'))
    out = set()
    for m in msgs:
        m = m.replace('\\"', '"').strip()
        if not m:
            continue
        if PLACEHOLDER.search(m):
            for piece in PLACEHOLDER.split(m):
                piece = piece.strip(STRIP)
                if len(piece) >= 4 and VN.search(piece):
                    out.add(piece)
        else:
            out.add(m)
    return sorted(out)


def main():
    items = targets()
    done = json.load(open(OUT, encoding='utf-8')) if os.path.exists(OUT) else {}
    todo = [s for s in items if s not in done]
    print(f'targets: {len(items)}, to translate: {len(todo)}')

    tx = GoogleTranslator(source='vi', target='en')
    batch, blen = [], 0
    for s in todo:
        batch.append(s)
        blen += len(s) + 1
        if blen > 3500 or len(batch) >= 30:
            _flush(tx, batch, done)
            batch, blen = [], 0
            json.dump(done, open(OUT, 'w', encoding='utf-8'),
                      ensure_ascii=False, indent=1)
            print(f'  progress {len(done)}/{len(items)}', flush=True)
            time.sleep(0.3)
    if batch:
        _flush(tx, batch, done)
    json.dump(done, open(OUT, 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)

    main_map = json.load(open(MAIN, encoding='utf-8'))
    added = skipped = 0
    for k, v in done.items():
        if k in main_map or not v or VN.search(v):
            skipped += 1
            continue
        main_map[k] = v
        added += 1
    json.dump(main_map, open(MAIN, 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    print(f'merged {added} (skipped {skipped}), map total {len(main_map)}')

    subprocess.run([sys.executable,
                    os.path.join(HERE, 'generate_en_ui_map_dart.py')], check=True)


def _flush(tx, batch, done):
    try:
        res = tx.translate_batch(batch)
    except Exception as e:
        print('  batch failed, retry single:', e, file=sys.stderr)
        res = []
        for s in batch:
            try:
                res.append(tx.translate(s))
            except Exception:
                res.append('')
            time.sleep(0.25)
    for s, t in zip(batch, res):
        done[s] = (t or '').strip()


if __name__ == '__main__':
    main()
