"""Máy in giả cho QA phần dò / đổi IP qua UDP broadcast (pos_lan_printer_netconfig.dart, SboxPrintAgent NetConfig.cs).

    python -I scripts/qa/fake_udp_printer.py [ip_giả=192.168.123.100]
Giả lập 3 họ giao thức (định dạng: docs/printers/lan-printer-ip-protocols.md):
- Xprinter UDP 9000: XP0001FIND → XP0001FOUND (trả bằng broadcast tới cổng 9000, như máy in khác lớp mạng),
  XP0001SAVE + MAC khớp → đổi IP giả.
- Rongta UDP 1460: MP4200FIND → MP4200FOUND (trả về đúng nguồn), MP4200SAVE.
- Epson ENPC UDP 3289: gói "EPSON" + chữ hoa → trả "EPSON" + chữ thường.
Mỗi lần nhận SAVE in ra IP / mask / gateway mới để đối chiếu.
"""
import socket
import sys
import threading

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

state = {
    'xp': {'mac': bytes.fromhex('001122334455'), 'ip': sys.argv[1] if len(sys.argv) > 1 else '192.168.123.100',
           'mask': '255.255.255.0', 'gw': '192.168.123.1', 'dhcp': 0},
    'rt': {'mac': bytes.fromhex('00AABBCCDDEE'), 'ip': '192.168.123.101', 'mask': '255.255.255.0',
           'gw': '192.168.123.1', 'dhcp': 1},
}


def ip_b(s):
    return socket.inet_aton(s)


def ip_s(b):
    return socket.inet_ntoa(bytes(b))


def found(tag, st):
    # FOUND: tag(11) + MAC(6) + 2 byte + IP + mask + gw + 2 byte + DHCP (byte 33)
    return tag + st['mac'] + b'\x00\x00' + ip_b(st['ip']) + ip_b(st['mask']) + ip_b(st['gw']) + b'\x00\x00' + bytes([st['dhcp']])


def apply_save(name, st, data, const1, const2):
    if len(data) != 33 or data[10:16] != st['mac']:
        print(f'[{name}] SAVE bỏ qua (MAC khác / sai độ dài {len(data)})', flush=True)
        return
    if data[16:18] != const1 or data[30:32] != const2:
        print(f'[{name}] SAVE SAI HẰNG SỐ: {data[16:18].hex()} {data[30:32].hex()}', flush=True)
        return
    st['ip'], st['mask'], st['gw'], st['dhcp'] = ip_s(data[18:22]), ip_s(data[22:26]), ip_s(data[26:30]), data[32]
    print(f"[{name}] SAVE OK → ip={st['ip']} mask={st['mask']} gw={st['gw']} dhcp={st['dhcp']}", flush=True)


def sock(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.bind(('', port))
    return s


def xprinter():
    s = sock(9000)
    while True:
        data, addr = s.recvfrom(2048)
        if data == b'XP0001FIND':
            print(f'[xp] FIND từ {addr}', flush=True)
            s.sendto(found(b'XP0001FOUND', state['xp']), ('255.255.255.255', 9000))
        elif data.startswith(b'XP0001SAVE'):
            apply_save('xp', state['xp'], data, b'\x22\x00', b'\x8c\x17')


def rongta():
    s = sock(1460)
    while True:
        data, addr = s.recvfrom(2048)
        if data == b'MP4200FIND':
            print(f'[rt] FIND từ {addr}', flush=True)
            s.sendto(found(b'MP4200FOUND', state['rt']), ('255.255.255.255', addr[1]))
        elif data.startswith(b'MP4200SAVE'):
            apply_save('rt', state['rt'], data, b'\x0f\x00', b'\x05\xb4')


def epson():
    s = sock(3289)
    while True:
        data, addr = s.recvfrom(2048)
        if data[:5] == b'EPSON' and len(data) > 5 and 0x41 <= data[5] <= 0x5A:
            print(f'[epson] {chr(data[5])} từ {addr}', flush=True)
            s.sendto(b'EPSON' + bytes([data[5] + 0x20]) + bytes(8), ('255.255.255.255', addr[1]))


for fn in (xprinter, rongta, epson):
    threading.Thread(target=fn, daemon=True).start()
print('fake_udp_printer: nghe UDP 9000 / 1460 / 3289 — Ctrl+C để dừng', flush=True)
threading.Event().wait()
