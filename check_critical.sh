#!/bin/bash
python3 - <<'PYEOF'
import struct, subprocess

def get_cmap_chars(filepath):
    with open(filepath, 'rb') as f: data = f.read()
    num_tables = struct.unpack('>H', data[4:6])[0]
    cmap_offset = None
    for i in range(num_tables):
        o = 12 + i * 16
        tag = data[o:o+4].decode('ascii', errors='replace')
        if tag == 'cmap':
            cmap_offset = struct.unpack('>I', data[o+8:o+12])[0]
            break
    if cmap_offset is None: return set()
    n_subtables = struct.unpack('>H', data[cmap_offset+2:cmap_offset+4])[0]
    chars = set()
    for i in range(n_subtables):
        so = cmap_offset + 4 + i * 8
        platform = struct.unpack('>H', data[so:so+2])[0]
        offset = struct.unpack('>I', data[so+4:so+8])[0]
        subtable_abs = cmap_offset + offset
        fmt = struct.unpack('>H', data[subtable_abs:subtable_abs+2])[0]
        if fmt == 4 and platform in (0, 3):
            seg_count = struct.unpack('>H', data[subtable_abs+6:subtable_abs+8])[0] // 2
            end_arr = subtable_abs + 14
            start_arr = end_arr + seg_count * 2 + 2
            for j in range(seg_count):
                end_c = struct.unpack('>H', data[end_arr + j*2:end_arr + j*2 + 2])[0]
                start_c = struct.unpack('>H', data[start_arr + j*2:start_arr + j*2 + 2])[0]
                chars.update(range(start_c, end_c + 1))
            break
    return chars

subprocess.run(['docker', 'exec', 'zkteco_api', 'cat', '/app/wwwroot/assets/assets/fonts/BeVietnamPro-Regular.ttf'], 
               stdout=open('/tmp/BVP.ttf', 'wb'), stderr=subprocess.DEVNULL)
chars = get_cmap_chars('/tmp/BVP.ttf')

# The ACTUAL characters in "Duy?t ch?m c?ng"  
critical = {
    0x1EC7: 'e-circ+dot (Duy[e]t)',
    0x1EA5: 'a-circ+acute (ch[a]m)',
    0x00F4: 'o-circ (c[o]ng)',
    0x1ED5: 'o-circ+hook (T[o]ng)',
    0x1EED: 'u-hook+hook (ng[u]i)',
    0x1EDD: 'o-hook+grave (ng[u]oi)',
    0x1EB1: 'a-breve+grave (ch[a]m)',
    0x1ECB: 'i-dot (v[i]ec)',
    0x1ED3: 'o-circ+grave (ng[o]i)',
    0x1EA7: 'a-circ+grave (ch[a]ng)',
}

print("Critical character check:")
missing = []
for cp, desc in sorted(critical.items()):
    ok = cp in chars
    status = "OK" if ok else "MISSING!"
    print(f"  U+{cp:04X} ({desc}): {status}")
    if not ok: missing.append(f"U+{cp:04X}")

print(f"\nResult: {len(missing)} missing chars")
if missing:
    print("Missing:", missing)
    print("=> These chars will show as boxes/? in the UI!")

# Print all ranges with gaps
ranges = []
sorted_chars = sorted(c for c in chars if 0x00C0 <= c <= 0x1EFF)
if sorted_chars:
    start = sorted_chars[0]
    prev = start
    for c in sorted_chars[1:]:
        if c > prev + 1:
            ranges.append((start, prev))
            start = c
        prev = c
    ranges.append((start, prev))
print(f"\nChar ranges in font (U+00C0-U+1EFF): {len(ranges)} ranges, {len(sorted_chars)} chars total")
for r in ranges[:10]:
    print(f"  U+{r[0]:04X}-U+{r[1]:04X}")
PYEOF