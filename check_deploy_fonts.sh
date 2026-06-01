#!/bin/bash
# Check the existing deployed fonts for Vietnamese glyph coverage
python3 - <<'PYEOF'
import struct, os

def get_cmap_chars(filepath):
    try:
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
        if cmap_offset is None:
            return set()
        n_subtables = struct.unpack('>H', data[cmap_offset+2:cmap_offset+4])[0]
        chars = set()
        for i in range(n_subtables):
            so = cmap_offset + 4 + i * 8
            platform = struct.unpack('>H', data[so:so+2])[0]
            encoding = struct.unpack('>H', data[so+2:so+4])[0]
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
    except Exception as e:
        return set()

viet_range = set(range(0x1E00, 0x1F00))
key_viet = [0x1EA0, 0x1EA1, 0x1EA3, 0x1EB0, 0x1EB1, 0x1EC0, 0x1ED0, 0x1EE0, 0x0103, 0x01A1, 0x01B0]

fonts_dir = '/app/wwwroot/assets/assets/fonts'
import subprocess
result = subprocess.run(['docker', 'exec', 'zkteco_api', 'ls', fonts_dir], capture_output=True, text=True)
print("Fonts in container:", result.stdout.strip())

# Copy fonts out to check
for fname in ['BeVietnamPro-Regular.ttf', 'BeVietnamPro-Bold.ttf']:
    src = f'{fonts_dir}/{fname}'
    dst = f'/tmp/{fname}'
    subprocess.run(['docker', 'exec', 'zkteco_api', 'cat', src], stdout=open(dst, 'wb'))
    chars = get_cmap_chars(dst)
    size = os.path.getsize(dst)
    viet_count = len(chars & viet_range)
    has_key = sum(1 for c in key_viet if c in chars)
    key_names = [f'U+{c:04X}' for c in key_viet if c in chars]
    print(f'{fname} ({size} bytes): Latin-ExtAdd={viet_count}, keyViet={has_key}/{len(key_viet)} ({key_names[:3]}...)')
PYEOF