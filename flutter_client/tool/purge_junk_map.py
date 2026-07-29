"""Drop code-data keys (regex classes, diacritic alphabet constants) from the map."""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from extract_chunks import is_junk as is_junk_chunk  # noqa: E402

RE_ESCAPE = re.compile(r'\\[sSdDwWbBpP]')
# A line comment marker is the reliable tell of source code swept into the map.
# A bare newline is not: plenty of real messages wrap onto a second line.
CODE = re.compile(r'string\.Join\(|\)\.format\(|</|\?\?\s*$|//')


def is_junk(s):
    """A key is code data, not UI copy — kept deliberately narrow.

    Strings such as "Nội dung (hỗ trợ {variable})" are real UI text that happens to
    show a placeholder, so a plain brace is not enough. An unbalanced brace is the
    signature of a chunk cut out of an interpolation. Unbalanced parentheses are
    left alone: a fragment like "Bảo hiểm Y tế (BHYT" still substitutes correctly
    inside the full string, so dropping it would only lose coverage.
    """
    if RE_ESCAPE.search(s) or CODE.search(s):
        return True
    if len(s) > 20 and not re.search(r'\s', s):
        return True
    return s.count('{') != s.count('}')


JSON = os.path.join(HERE, 'en_ui_map.json')
ALL = os.path.join(HERE, 'chunks_all.json')

apply = '--apply' in sys.argv

data = json.load(open(JSON, encoding='utf-8'))
bad = [k for k in data if is_junk(k)]
print(f'map entries: {len(data)}, junk keys: {len(bad)}')
for k in bad[:15]:
    print('   -', k[:80])

chunks = json.load(open(ALL, encoding='utf-8')) if os.path.exists(ALL) else []
bad_chunks = [c for c in chunks if is_junk_chunk(c)]
print(f'chunks_all: {len(chunks)}, junk chunks: {len(bad_chunks)}')

if apply:
    for k in bad:
        data.pop(k, None)
    json.dump(data, open(JSON, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    kept = [c for c in chunks if not is_junk_chunk(c)]
    json.dump(kept, open(ALL, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'kept {len(data)} map entries, {len(kept)} chunks')
