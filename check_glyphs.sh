#!/bin/bash
python3 - <<'PYEOF'
import struct, subprocess, os

def get_cmap_chars(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
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

# Copy font from container
subprocess.run(['docker', 'exec', 'zkteco_api', 'cat', '/app/wwwroot/assets/assets/fonts/BeVietnamPro-Regular.ttf'], 
               stdout=open('/tmp/BVP-Regular.ttf', 'wb'))
chars = get_cmap_chars('/tmp/BVP-Regular.ttf')

# Specific Vietnamese characters in UI labels
test_chars = {
    0x1EB9: '? (e-dot-below)',   # in Duy?t
    0x1EA5: '? (a-circ-grave)',  # in ch?m  
    0x00F4: '? (o-circ)',        # in c?ng
    0x1ED5: '? (o-circ-hook)',   # in T?ng
    0x1EE3: '? (o-hook-dot)',    # in h?p
    0x1EA7: '? (a-circ-grave)',  # in ch?m -> ch?m?
    0x1EA3: '? (a-hook)',        # in c?
    0x1EBF: '? (e-circ-acute)', # in th?
    0x1ED1: '? (o-circ-acute)', # in s?
    0x1ECD: '? (o-dot-below)',  # in h?
    0x1EDD: '? (o-hook-grave)', # in ng??i
    # These seem to render OK in data:
    0x1EA4: '? (A-circ-acute)', # in NH?T (caps)
    0x00CA: '? (E-circ caps)',  # in L?
    0x00C0: '? (A-grave caps)', # in B?
    0x01B0: '? (u-horn)',       # in Tr??ng
    0x01A1: '? (o-horn)',       # in Owner
}

print("Char coverage in BeVietnamPro-Regular:")
missing = []
for cp, desc in sorted(test_chars.items()):
    present = cp in chars
    status = "?" if present else "? MISSING"
    print(f"  U+{cp:04X} {desc}: {status}")
    if not present:
        missing.append(cp)

print(f"\nMissing: {len(missing)} chars")
print("Latin-1 (U+00C0-U+00FF):", len([c for c in chars if 0x00C0 <= c <= 0x00FF]))
print("Latin-ExtAdd (U+1E00-U+1EFF):", len([c for c in chars if 0x1E00 <= c <= 0x1EFF]))
PYEOF