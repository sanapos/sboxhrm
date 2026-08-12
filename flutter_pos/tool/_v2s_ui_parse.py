from pathlib import Path
import re
import sys

xml_path = Path(sys.argv[1] if len(sys.argv) > 1 else r"e:\SBOX CURSOR\ZKTecoADMS-master\.tmp-esp-audit\v2s-ui.xml")
xml = xml_path.read_text(encoding="utf-8", errors="ignore")
nodes = re.findall(
    r'text="([^"]*)"[^>]*resource-id="([^"]*)"[^>]*class="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
    xml,
)
if not nodes:
    nodes2 = re.findall(
        r'text="([^"]+)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        xml,
    )
    print("nodes", len(nodes2))
    for t, x1, y1, x2, y2 in nodes2:
        if t.strip():
            print(f"{t} @ ({x1},{y1})-({x2},{y2})")
else:
    print("nodes", len(nodes))
    for t, rid, cls, x1, y1, x2, y2 in nodes:
        if t.strip() or "Edit" in cls or "Button" in cls:
            print(f"{t or rid or cls} @ ({x1},{y1})-({x2},{y2})")
