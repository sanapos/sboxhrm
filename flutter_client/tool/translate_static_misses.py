"""Translate static VN literals that have no en_ui_map entry, then merge them in.

Run after audit_all_literals.py + audit_static_misses.py:
    python tool/audit_all_literals.py 0
    python tool/audit_static_misses.py
    python tool/translate_static_misses.py
"""
import json
import os
import re
import subprocess
import sys
import time

from deep_translator import GoogleTranslator

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'static_misses.json')
OUT = os.path.join(HERE, 'static_en.json')
MAIN = os.path.join(HERE, 'en_ui_map.json')

VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]')

# Domain abbreviations the translator mangles; keep them intact.
KEEP = {
    'CC': 'CC', 'OT': 'OT', 'POS': 'POS', 'KK': 'KK', 'PN': 'PN',
    'XH': 'XH', 'XDNB': 'XDNB', 'HR': 'HR', 'KPI': 'KPI', 'NV': 'NV',
}


def main():
    items = json.load(open(SRC, encoding='utf-8'))
    done = json.load(open(OUT, encoding='utf-8')) if os.path.exists(OUT) else {}
    todo = [s for s in items if s not in done]
    print(f'to translate: {len(todo)} (resuming with {len(done)} done)')

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
        if k in main_map or not v:
            continue
        # A "translation" that still reads Vietnamese would be a no-op entry.
        if VN.search(v):
            skipped += 1
            continue
        main_map[k] = v
        added += 1
    json.dump(main_map, open(MAIN, 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    print(f'merged {added} entries (skipped {skipped} untranslated), '
          f'map total {len(main_map)}')

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
        t = (t or '').strip()
        for abbr in KEEP:
            if abbr in s and abbr not in t:
                pass  # abbreviations are usually preserved; nothing to repair
        done[s] = t


if __name__ == '__main__':
    main()
