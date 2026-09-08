import json
from pathlib import Path

p = Path(__file__).with_name("tr_misses_remaining.json")
items = json.loads(p.read_text(encoding="utf-8"))
other = [s for s in items if "$" not in s and len(s) <= 180]
print("other", len(other))
for s in other:
    print(repr(s))
