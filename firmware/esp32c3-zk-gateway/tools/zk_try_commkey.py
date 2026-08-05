"""Thu tim Comm Key cua may cham cong ZKTeco.

May tra CMD_ACK_UNAUTH nghia la co dat Comm Key. Script nay thu lan luot cac
khoa pho bien (va co the quet mot dai so) de tim khoa dung, sau do in ra.
Chi ket noi va xac thuc, khong ghi gi len may.

    python tools/zk_try_commkey.py 192.168.1.35
    python tools/zk_try_commkey.py 192.168.1.35 --scan 0 9999
    python tools/zk_try_commkey.py 192.168.1.35 --keys 0 1234 888888
"""

import argparse
import socket
import struct
import sys

MAGIC = struct.pack("<HH", 0x5050, 0x7D82)
USHRT_MAX = 0xFFFF

CMD_CONNECT = 1000
CMD_EXIT = 1001
CMD_AUTH = 1102
CMD_ACK_OK = 2000
CMD_ACK_UNAUTH = 2005


def checksum(payload: bytes) -> int:
    total = 0
    i = 0
    while i + 1 < len(payload):
        total += payload[i] | (payload[i + 1] << 8)
        if total > USHRT_MAX:
            total -= USHRT_MAX
        i += 2
    if i < len(payload):
        total += payload[i]
    while total > USHRT_MAX:
        total -= USHRT_MAX
    return USHRT_MAX - total


def make_commkey(key: int, session_id: int, ticks: int = 50) -> bytes:
    reversed_bits = 0
    for i in range(32):
        reversed_bits = (reversed_bits << 1) | ((key >> i) & 1)
    value = (reversed_bits + session_id) & 0xFFFFFFFF

    b = list(struct.pack("<I", value))
    b[0] ^= ord("Z")
    b[1] ^= ord("K")
    b[2] ^= ord("S")
    b[3] ^= ord("O")
    swapped = [b[2], b[3], b[0], b[1]]
    B = ticks & 0xFF
    return bytes([swapped[0] ^ B, swapped[1] ^ B, B, swapped[3] ^ B])


class Zk:
    def __init__(self, host, port, timeout=6.0):
        self.host, self.port, self.timeout = host, port, timeout
        self.sock = None
        self.session_id = 0
        self.reply_id = 0xFFFE
        self.resp = 0
        self.data = b""

    def open(self):
        self.sock = socket.create_connection((self.host, self.port), self.timeout)
        self.sock.settimeout(self.timeout)
        self.session_id = 0
        self.reply_id = 0xFFFE

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            finally:
                self.sock = None

    def _recv_exact(self, n):
        out = b""
        while len(out) < n:
            chunk = self.sock.recv(n - len(out))
            if not chunk:
                raise ConnectionError("mat ket noi")
            out += chunk
        return out

    def recv(self):
        top = self._recv_exact(8)
        if top[:4] != MAGIC:
            raise ValueError("sai magic")
        length = struct.unpack("<I", top[4:8])[0]
        header = self._recv_exact(8)
        self.resp = struct.unpack("<H", header[0:2])[0]
        self.reply_id = struct.unpack("<H", header[6:8])[0]
        if self.session_id == 0:
            self.session_id = struct.unpack("<H", header[4:6])[0]
        body_len = length - 8
        self.data = self._recv_exact(body_len) if body_len > 0 else b""

    def cmd(self, command, payload=b""):
        self.reply_id = (self.reply_id + 1) & USHRT_MAX
        head = struct.pack("<4H", command, 0, self.session_id, self.reply_id) + payload
        head = struct.pack("<4H", command, checksum(head), self.session_id, self.reply_id) + payload
        self.sock.sendall(MAGIC + struct.pack("<I", len(head)) + head)
        self.recv()
        return self.resp

    def try_key(self, key: int) -> bool:
        """Mo phien moi, gui CONNECT roi AUTH voi khoa. True neu duoc chap nhan."""
        self.open()
        try:
            self.cmd(CMD_CONNECT)
            if self.resp == CMD_ACK_OK:
                # May khong dat khoa -> bat ky khoa nao cung 'thanh cong'
                return True
            if self.resp != CMD_ACK_UNAUTH:
                return False
            self.cmd(CMD_AUTH, make_commkey(key, self.session_id))
            return self.resp == CMD_ACK_OK
        except OSError:
            return False
        finally:
            try:
                self.cmd(CMD_EXIT)
            except OSError:
                pass
            self.close()


COMMON = [0, 1, 12, 123, 1234, 8888, 88888, 888888, 8888888, 123456,
          654321, 111111, 222222, 0o0, 9999, 6666, 168, 520, 1, 100]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("host")
    parser.add_argument("--port", type=int, default=4370)
    parser.add_argument("--keys", type=int, nargs="*", help="danh sach khoa cu the de thu")
    parser.add_argument("--scan", type=int, nargs=2, metavar=("FROM", "TO"),
                        help="quet dai khoa [FROM, TO]")
    args = parser.parse_args()

    zk = Zk(args.host, args.port)

    # Kiem tra may co dat khoa khong
    if not zk.try_key(-1) and zk.resp == 0:
        print("Khong ket noi duoc TCP.")
        return 1

    zk.open()
    try:
        zk.cmd(CMD_CONNECT)
        no_key = zk.resp == CMD_ACK_OK
        first_resp = zk.resp
    finally:
        try:
            zk.cmd(CMD_EXIT)
        except OSError:
            pass
        zk.close()

    if no_key:
        print("May KHONG dat Comm Key (CONNECT tra ACK_OK ngay). Dung comm_key=0.")
        return 0
    print(f"May co dat Comm Key (CONNECT tra ma {first_resp}). Bat dau thu khoa...\n")

    candidates = []
    if args.keys:
        candidates = args.keys
    else:
        candidates = list(dict.fromkeys(COMMON))
    if args.scan:
        candidates += list(range(args.scan[0], args.scan[1] + 1))

    tried = 0
    for key in candidates:
        if key < 0:
            continue
        tried += 1
        ok = zk.try_key(key)
        if ok:
            print(f"\n>>> TIM THAY Comm Key = {key}")
            print("    Nhap so nay vao o 'Comm Key' trong web portal cua ESP.")
            return 0
        if tried % 200 == 0:
            print(f"  da thu {tried} khoa...")

    print(f"\nKhong tim thay trong {tried} khoa da thu.")
    print("Neu ban biet so khoa, chay: python tools/zk_try_commkey.py "
          f"{args.host} --keys <so>")
    print("Hoac quet rong hon: --scan 0 999999 (se lau).")
    return 1


if __name__ == "__main__":
    sys.exit(main())
