"""Máy in giả cho QA: nhận lệnh in ESC/POS / TSPL qua TCP, lưu thô + dựng lại ảnh để đo khổ in thật.

    python -I scripts/qa/fake_printer.py [cổng=9100] [thư_mục=scripts/qa/prints]
Thiết bị Android trỏ máy in LAN về 127.0.0.1:<cổng> sau khi: adb -s <serial> reverse tcp:<cổng> tcp:<cổng>
Mỗi lệnh in → <thời gian>_<n>.bin + .png (ảnh raster) + .txt (tóm tắt: lệnh, bề ngang điểm in, SIZE tem…).
"""
import os
import socket
import struct
import sys
import threading
import time
import zlib

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9100
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'prints')
os.makedirs(OUT, exist_ok=True)
counter = [0]


def write_png(path, width, rows):
    """rows: list[bytes] 1 bit/điểm, bit 1 = đen (chuẩn ESC/POS)."""
    raw = b''.join(b'\x00' + bytes(255 - b for b in r) for r in rows)  # PNG 1-bit: 1 = trắng

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, len(rows), 1, 0, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


def parse_escpos(data):
    """Gom ảnh raster GS v 0 (xếp chồng theo chiều dọc) + đếm lệnh khác."""
    info = {'raster_blocks': 0, 'widths_dots': set(), 'cut': 0, 'text_bytes': 0, 'esc_star': 0, 'drawer': 0}
    rows, width_bytes = [], 0
    i, n = 0, len(data)
    while i < n:
        b = data[i]
        if b == 0x1D and i + 1 < n and data[i + 1] == 0x76 and i + 7 < n and data[i + 2] == 0x30:  # GS v 0
            xl, xh, yl, yh = data[i + 4], data[i + 5], data[i + 6], data[i + 7]
            wb, h = xl + xh * 256, yl + yh * 256
            body = data[i + 8:i + 8 + wb * h]
            info['raster_blocks'] += 1
            info['widths_dots'].add(wb * 8)
            width_bytes = max(width_bytes, wb)
            for r in range(h):
                rows.append(body[r * wb:(r + 1) * wb])
            i += 8 + wb * h
            continue
        if b == 0x1D and i + 1 < n and data[i + 1] == 0x56:  # GS V cắt giấy
            info['cut'] += 1
            i += 3
            continue
        if b == 0x1B and i + 1 < n and data[i + 1] == 0x2A:  # ESC * ảnh bit cột
            info['esc_star'] += 1
            m, nl, nh = data[i + 2], data[i + 3], data[i + 4]
            cols = nl + nh * 256
            i += 5 + cols * (3 if m in (32, 33) else 1)
            continue
        if b == 0x1B and i + 1 < n and data[i + 1] == 0x70:  # ESC p mở két
            info['drawer'] += 1
            i += 5
            continue
        if b >= 0x20:
            info['text_bytes'] += 1
        i += 1
    rows = [r.ljust(width_bytes, b'\x00') for r in rows]
    return info, rows, width_bytes * 8


def tspl_bitmap(data):
    """BITMAP x,y,widthBytes,height,mode,<dữ liệu> — TSPL: bit 0 = chấm đen (ngược ESC/POS)."""
    i = data.find(b'BITMAP ')
    if i < 0:
        return None
    head_end = i
    commas = 0
    while head_end < len(data) and commas < 5:
        if data[head_end] == 0x2C:
            commas += 1
        head_end += 1
    parts = data[i + 7:head_end - 1].decode('latin-1').split(',')
    wb, h = int(parts[2]), int(parts[3])
    body = data[head_end:head_end + wb * h]
    rows = [bytes(255 - b for b in body[r * wb:(r + 1) * wb]) for r in range(h)]
    return wb * 8, rows


def parse_tspl(text):
    info = {}
    for line in text.splitlines():
        u = ''.join(ch for ch in line if ' ' <= ch <= '~').strip().upper()
        line = u
        for key in ('SIZE', 'GAP', 'DIRECTION', 'DENSITY', 'PRINT', 'CLS'):
            if u.startswith(key + ' ') or u == key:
                info.setdefault(key, []).append(line.strip())
        if u.startswith('BITMAP'):
            parts = line.split(',')
            if len(parts) >= 4:
                info.setdefault('BITMAP', []).append(f'x={parts[0].split()[-1]} y={parts[1]} widthBytes={parts[2]} '
                                                      f'(={int(parts[2]) * 8} điểm) h={parts[3]}')
        if u.startswith('TEXT') or u.startswith('BARCODE') or u.startswith('QRCODE'):
            info.setdefault('ELEMENTS', []).append(line.strip()[:120])
    return info


def handle(conn, addr):
    conn.settimeout(3)
    data = bytearray()
    try:
        while True:
            try:
                chunk = conn.recv(65536)
            except socket.timeout:
                break
            if not chunk:
                break
            data += chunk
            # Trả lời truy vấn trạng thái: DLE EOT n → «đang online, đủ giấy»; TSPL ~!T → model.
            if b'\x10\x04' in chunk:
                conn.sendall(b'\x12')
            if b'~!T' in chunk:
                conn.sendall(b'QA-FAKE\r\n')
    finally:
        conn.close()
    if not data:
        return
    counter[0] += 1
    base = os.path.join(OUT, time.strftime('%H%M%S') + f'_{counter[0]:03d}')
    with open(base + '.bin', 'wb') as f:
        f.write(data)
    lines = [f'{len(data)} byte từ {addr[0]}']
    head = bytes(data[:4000]).decode('latin-1', 'replace').upper()
    if 'SIZE ' in head and ('PRINT' in head or 'CLS' in head):
        txt = bytes(data).decode('latin-1', 'replace')
        lines.append('TSPL (máy tem):')
        for k, v in parse_tspl(txt).items():
            lines.append(f'  {k}: {v[:6]}')
        bm = tspl_bitmap(bytes(data))
        if bm:
            write_png(base + '.png', bm[0], bm[1])
            lines.append(f'Ảnh tem: {bm[0]}×{len(bm[1])} điểm (= {bm[0] / 8:.1f}×{len(bm[1]) / 8:.1f} mm) → {base}.png')
    else:
        info, rows, wd = parse_escpos(bytes(data))
        lines.append(f'ESC/POS: {info}')
        if rows:
            write_png(base + '.png', wd, rows)
            lines.append(f'Ảnh raster: rộng {wd} điểm (= {wd / 8:.1f} mm ở 203 dpi), cao {len(rows)} điểm '
                         f'(= {len(rows) / 8:.1f} mm) → {base}.png')
    with open(base + '.txt', 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    print('\n'.join(lines), flush=True)


srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('127.0.0.1', PORT))
srv.listen(8)
print(f'Máy in giả lắng nghe 127.0.0.1:{PORT} → {OUT}', flush=True)
while True:
    c, a = srv.accept()
    threading.Thread(target=handle, args=(c, a), daemon=True).start()
