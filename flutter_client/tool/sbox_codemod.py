"""SBOX Design codemod — đổi mã màu / cỡ chữ lẻ / độ đậm / bo góc viết cứng sang quy chuẩn.

Dùng:  python tool/sbox_codemod.py lib/screens/a.dart lib/widgets/b.dart ...
       python tool/sbox_codemod.py --dry lib/...        (chỉ đếm, không ghi)

Nguyên tắc an toàn:
- Chỉ đổi màu có tương đương rõ ràng trong SboxColors (xám / xanh / trạng thái).
- `const Color(0x..)` -> `SboxColors.x` (SboxColors là const nên ngữ cảnh const vẫn hợp lệ).
- Cỡ chữ: chỉ gom các cỡ lẻ (x.5, 15, 17, 19) về cỡ gần nhất — không đổi 10/11 để tránh tràn chữ ở chỗ chật.
- Bo góc: 5/7 -> 6, 8/9 -> 10, 12/16 -> 14.
"""
import os
import re
import sys

LIB = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', 'lib'))
TOKENS = os.path.join(LIB, 'theme', 'sbox_tokens.dart')

HEX = {
    # Zinc
    '71717A': 'slate500', 'E4E4E7': 'slate200', '18181B': 'slate900', 'A1A1AA': 'slate400',
    'FAFAFA': 'slate50', 'F4F4F5': 'slate100', '52525B': 'slate600', '3F3F46': 'slate700',
    '27272A': 'slate800', 'D4D4D8': 'slate300', 'EEEEF0': 'divider',
    # Gray (Tailwind)
    '6B7280': 'slate500', '9CA3AF': 'slate400', '111827': 'slate900', 'E5E7EB': 'slate200',
    'F3F4F6': 'slate100', '374151': 'slate700', '4B5563': 'slate600', 'D1D5DB': 'slate300',
    'F9FAFB': 'slate50', '1F2937': 'slate800',
    # Slate
    '64748B': 'slate500', 'F1F5F9': 'slate100', 'F8FAFC': 'slate50', '94A3B8': 'slate400',
    'E2E8F0': 'slate200', '0F172A': 'slate900', 'CBD5E1': 'slate300', '475569': 'slate600',
    '334155': 'slate700', '1E293B': 'slate800',
    # Xám lẻ hay gặp
    '333333': 'slate800', '888888': 'slate500', '586064': 'slate600', 'F4F4F4': 'page',
    'E0E4E8': 'slate200', 'EEEEEE': 'slate200', 'E0E0E0': 'slate200', '9E9E9E': 'slate400',
    '757575': 'slate500', '616161': 'slate600', '424242': 'slate700', '212121': 'slate900',
    'F5F5F5': 'slate100',
    # Xanh -> thương hiệu
    '2563EB': 'brand600', '3B82F6': 'brand500', '0C56D0': 'brand600', '1565C0': 'brand600',
    '1976D2': 'brand600', '0056B3': 'brand600', '1E88E5': 'brand500', '0D47A1': 'brand800',
    'EFF6FF': 'brand50', 'DBEAFE': 'brand100', '1D4ED8': 'brand700', '1E40AF': 'brand800',
    '60A5FA': 'brand400', '93C5FD': 'brand200', 'BFDBFE': 'brand100', 'E3F2FD': 'brand50',
    '0078D4': 'brand500', 'DEECF9': 'brand50', 'E8F1FB': 'brand50', '0056C7': 'brand700',
    '3B8CFF': 'brand400', '1E3A8A': 'brand900', '2196F3': 'brand500', 'BBDEFB': 'brand100',
    '90CAF9': 'brand200', '42A5F5': 'brand400', '64B5F6': 'brand300',
    # Trạng thái
    'EF4444': 'danger', 'DC2626': 'danger', 'FEE2E2': 'dangerSoft', 'FEF2F2': 'dangerSoft',
    'B91C1C': 'dangerText', '991B1B': 'dangerText', 'F44336': 'danger', 'E53935': 'danger',
    'D32F2F': 'danger', 'FFEBEE': 'dangerSoft',
    '22C55E': 'success', '16A34A': 'success', '059669': 'success', '10B981': 'success',
    'DCFCE7': 'successSoft', 'F0FDF4': 'successSoft', 'D1FAE5': 'successSoft', 'ECFDF5': 'successSoft',
    '166534': 'successText', '15803D': 'payHover', '047857': 'successText', '065F46': 'successText',
    '4CAF50': 'success', '43A047': 'success', '388E3C': 'success', '2E7D32': 'successText',
    'E8F5E9': 'successSoft', '4CB050': 'pay', '3D9143': 'payHover',
    'F59E0B': 'warning', 'D97706': 'warning', 'FEF3C7': 'warningSoft', 'FFFBEB': 'warningSoft',
    '92400E': 'warningText', 'B45309': 'warningText', 'FF9800': 'warning', 'FB8C00': 'warning',
    'F57C00': 'warning', 'FFF3E0': 'warningSoft', 'FFF7ED': 'warningSoft',
    '7C3AED': 'violet', '8B5CF6': 'violet', 'EDE9FE': 'violetSoft', 'F5F3FF': 'violetSoft',
    '5B21B6': 'violetText', '6D28D9': 'violetText',
}

SHADE = {'50': '50', '100': '100', '200': '200', '300': '300', '400': '400',
         '500': '500', '600': '600', '700': '700', '800': '800', '900': '900'}

FONT_SIZE = {'12.5': '13', '13.5': '14', '11.5': '12', '14.5': '14', '10.5': '11',
             '15': '16', '15.5': '16', '17': '18', '19': '18', '9.5': '10'}

RADIUS = {'5': '6', '7': '6', '8': '10', '9': '10', '12': '14', '16': '14'}


def rel_import(path):
    rel = os.path.relpath(TOKENS, os.path.dirname(os.path.abspath(path))).replace('\\', '/')
    return f"import '{rel}';"


def transform(src):
    counts = {'color': 0, 'material': 0, 'font': 0, 'weight': 0, 'radius': 0}

    def hex_sub(m):
        key = m.group(2).upper()
        tok = HEX.get(key)
        if tok is None:
            return m.group(0)
        counts['color'] += 1
        return f'SboxColors.{tok}'

    s = re.sub(r'(const\s+)?Color\(0x[fF]{2}([0-9A-Fa-f]{6})\)', hex_sub, src)

    def mat_sub(fam, tokfam):
        nonlocal s

        def shade(m):
            counts['material'] += 1
            return f'SboxColors.{tokfam}{SHADE[m.group(1)]}'

        s = re.sub(rf'Colors\.{fam}\.shade(50|100|200|300|400|500|600|700|800|900)\b', shade, s)
        s = re.sub(rf'Colors\.{fam}\[(50|100|200|300|400|500|600|700|800|900)\]!?', shade, s)

        def plain(m):
            counts['material'] += 1
            return f'SboxColors.{tokfam}500'

        s = re.sub(rf'Colors\.{fam}(?![A-Za-z0-9_\[])(?!\.shade)', plain, s)

    mat_sub('grey', 'slate')
    mat_sub('blue', 'brand')

    for a, tok in (('black87', 'text'), ('black54', 'textSecondary'), ('black45', 'textMuted'), ('black38', 'textMuted')):
        n = len(re.findall(rf'Colors\.{a}\b', s))
        if n:
            counts['material'] += n
            s = re.sub(rf'Colors\.{a}\b', f'SboxColors.{tok}', s)

    def fs(m):
        v = FONT_SIZE.get(m.group(1))
        if v is None:
            return m.group(0)
        counts['font'] += 1
        return f'fontSize: {v}'

    s = re.sub(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)(?![0-9.])', fs, s)

    n = len(re.findall(r'FontWeight\.w(800|900)\b', s))
    if n:
        counts['weight'] += n
        s = re.sub(r'FontWeight\.w(800|900)\b', 'FontWeight.w700', s)

    def rad(m):
        v = RADIUS.get(m.group(1))
        if v is None:
            return m.group(0)
        counts['radius'] += 1
        return f'BorderRadius.circular({v})'

    s = re.sub(r'BorderRadius\.circular\(([0-9]+)(?:\.0)?\)', rad, s)
    return s, counts


def process(path, dry):
    raw = open(path, encoding='utf-8', newline='').read()
    crlf = '\r\n' in raw
    s = raw.replace('\r\n', '\n')
    out, counts = transform(s)
    if 'SboxColors.' in out and 'sbox_tokens.dart' not in out and 'sbox_ui.dart' not in out:
        imp = rel_import(path)
        m = list(re.finditer(r"^import\s+'[^']+';\s*$", out, re.M))
        if m:
            pos = m[-1].end()
            out = out[:pos] + '\n' + imp + out[pos:]
        else:
            out = imp + '\n' + out
    changed = out != s
    if changed and not dry:
        if crlf:
            out = out.replace('\n', '\r\n')
        open(path, 'w', encoding='utf-8', newline='').write(out)
    return changed, counts


def main(argv):
    dry = '--dry' in argv
    files = [a for a in argv if not a.startswith('--')]
    total = {'color': 0, 'material': 0, 'font': 0, 'weight': 0, 'radius': 0}
    for f in files:
        if os.path.abspath(f) == os.path.abspath(TOKENS):
            continue
        changed, c = process(f, dry)
        for k in total:
            total[k] += c[k]
        if changed:
            print(f'{f}: ' + ', '.join(f'{k}={v}' for k, v in c.items() if v))
    print('TOTAL ' + ', '.join(f'{k}={v}' for k, v in total.items()))


if __name__ == '__main__':
    main(sys.argv[1:])
