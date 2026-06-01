#!/bin/bash
echo "=== Downloading full BeVietnamPro fonts from Google Fonts GitHub ==="
mkdir -p /tmp/fonts

# Download from GitHub raw - needs proper handling
FONT_BASE="https://raw.githubusercontent.com/google/fonts/main/ofl/bevietnampro/static"
declare -A FONTS=(
  ["BeVietnamPro-Regular"]="BeVietnamPro-Regular.ttf"
  ["BeVietnamPro-Italic"]="BeVietnamPro-Italic.ttf"
  ["BeVietnamPro-Medium"]="BeVietnamPro-Medium.ttf"
  ["BeVietnamPro-SemiBold"]="BeVietnamPro-SemiBold.ttf"
  ["BeVietnamPro-Bold"]="BeVietnamPro-Bold.ttf"
  ["BeVietnamPro-ExtraBold"]="BeVietnamPro-ExtraBold.ttf"
)

for name in "${!FONTS[@]}"; do
  url="$FONT_BASE/${FONTS[$name]}"
  dest="/tmp/fonts/${FONTS[$name]}"
  curl -sL "$url" -o "$dest"
  size=$(stat -c%s "$dest" 2>/dev/null || echo 0)
  echo "$name: $size bytes"
done

echo ""
echo "=== Check font Vietnamese glyph coverage ==="
python3 - <<'PYEOF'
import struct, os

def get_cmap_chars(filepath):
    try:
        with open(filepath, 'rb') as f:
            data = f.read()
        
        # Read offset table
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
        
        # Read cmap header
        n_subtables = struct.unpack('>H', data[cmap_offset+2:cmap_offset+4])[0]
        chars = set()
        
        for i in range(n_subtables):
            so = cmap_offset + 4 + i * 8
            platform = struct.unpack('>H', data[so:so+2])[0]
            encoding = struct.unpack('>H', data[so+2:so+4])[0]
            offset = struct.unpack('>I', data[so+4:so+8])[0]
            subtable_abs = cmap_offset + offset
            fmt = struct.unpack('>H', data[subtable_abs:subtable_abs+2])[0]
            
            if fmt == 4 and platform in (0, 3):  # Unicode BMP
                length = struct.unpack('>H', data[subtable_abs+2:subtable_abs+4])[0]
                seg_count = struct.unpack('>H', data[subtable_abs+6:subtable_abs+8])[0] // 2
                end_arr = subtable_abs + 14
                start_arr = end_arr + seg_count * 2 + 2
                for j in range(seg_count):
                    end_c = struct.unpack('>H', data[end_arr + j*2:end_arr + j*2 + 2])[0]
                    start_c = struct.unpack('>H', data[start_arr + j*2:start_arr + j*2 + 2])[0]
                    chars.update(range(start_c, end_c + 1))
                break
        
        return chars
    except:
        return set()

# Vietnamese Unicode range: U+1E00-U+1EFF (Latin Extended Additional)
viet_range = set(range(0x1E00, 0x1F00))
key_viet_chars = [0x1EA0, 0x1EA1, 0x1EB0, 0x1EC0, 0x1ED0, 0x1EE0, 0x0103, 0x01A1, 0x01B0]

for fname in ['BeVietnamPro-Regular.ttf', 'BeVietnamPro-Bold.ttf']:
    path = f'/tmp/fonts/{fname}'
    if not os.path.exists(path):
        print(f'{fname}: NOT FOUND')
        continue
    chars = get_cmap_chars(path)
    viet_count = len(chars & viet_range)
    has_key = sum(1 for c in key_viet_chars if c in chars)
    print(f'{fname} ({os.path.getsize(path)} bytes): Latin-Ext-Add={viet_count}, key Vietnamese={has_key}/{len(key_viet_chars)}')
PYEOF