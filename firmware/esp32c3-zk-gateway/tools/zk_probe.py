"""Thăm dò máy chấm công ZKTeco qua TCP 4370 từ PC.

Cài đặt tham chiếu của đúng khung truyền mà firmware dùng, để kiểm chứng
định dạng gói, cỡ bản ghi và dữ liệu đọc được trước khi tin vào firmware.
Chỉ dùng lệnh đọc, không ghi gì lên máy.

    python tools/zk_probe.py 192.168.1.35
    python tools/zk_probe.py 192.168.1.35 --comm-key 0 --records 5
"""

import argparse
import socket
import struct
import sys

MAGIC = struct.pack("<HH", 0x5050, 0x7D82)

CMD_CONNECT = 1000
CMD_EXIT = 1001
CMD_AUTH = 1102
CMD_GET_VERSION = 1100
CMD_PREPARE_DATA = 1500
CMD_DATA = 1501
CMD_FREE_DATA = 1502
CMD_DATA_WRRQ = 1503
CMD_READ_BUFFER = 1504
CMD_ACK_OK = 2000
CMD_ACK_ERROR = 2001
CMD_ACK_UNAUTH = 2005
CMD_USERTEMP_RRQ = 9
CMD_OPTIONS_RRQ = 11
CMD_ATTLOG_RRQ = 13
CMD_GET_FREE_SIZES = 50
FCT_USER = 5

USHRT_MAX = 0xFFFF


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
    # Bu 1 (0xFFFF - total), khong dung ~total: may kiem tra tong moi tu 16-bit
    # ke ca o checksum phai bang 0xFFFF. Dung ~ se lech 1 va may bo qua goi.
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


def decode_time(encoded: int):
    second = encoded % 60
    encoded //= 60
    minute = encoded % 60
    encoded //= 60
    hour = encoded % 24
    encoded //= 24
    day = encoded % 31 + 1
    encoded //= 31
    month = encoded % 12 + 1
    encoded //= 12
    return f"{encoded + 2000:04d}-{month:02d}-{day:02d} {hour:02d}:{minute:02d}:{second:02d}"


class Zk:
    def __init__(self, host: str, port: int = 4370, timeout: float = 8.0):
        self.sock = socket.create_connection((host, port), timeout)
        self.sock.settimeout(timeout)
        self.session_id = 0
        self.reply_id = 0xFFFE
        self.resp = 0
        self.data = b""

    def close(self):
        self.sock.close()

    def _recv_exact(self, count: int) -> bytes:
        out = b""
        while len(out) < count:
            chunk = self.sock.recv(count - len(out))
            if not chunk:
                raise ConnectionError(f"mat ket noi (can {count}, duoc {len(out)})")
            out += chunk
        return out

    def recv(self, sink=None):
        top = self._recv_exact(8)
        if top[:4] != MAGIC:
            raise ValueError(f"sai magic: {top[:4].hex()}")
        length = struct.unpack("<I", top[4:8])[0]

        header = self._recv_exact(8)
        self.resp = struct.unpack("<H", header[0:2])[0]
        self.reply_id = struct.unpack("<H", header[6:8])[0]
        if self.session_id == 0:
            self.session_id = struct.unpack("<H", header[4:6])[0]

        body_len = length - 8
        if sink is not None and self.resp == CMD_DATA:
            remaining = body_len
            while remaining > 0:
                chunk = self._recv_exact(min(remaining, 4096))
                sink(chunk)
                remaining -= len(chunk)
            self.data = b""
        else:
            self.data = self._recv_exact(body_len) if body_len else b""

    def cmd(self, command: int, payload: bytes = b"", sink=None):
        self.reply_id = (self.reply_id + 1) & USHRT_MAX
        head = struct.pack("<4H", command, 0, self.session_id, self.reply_id) + payload
        head = struct.pack("<4H", command, checksum(head), self.session_id, self.reply_id) + payload
        self.sock.sendall(MAGIC + struct.pack("<I", len(head)) + head)
        self.recv(sink)
        return self.resp

    def connect(self, comm_key: int = 0):
        self.cmd(CMD_CONNECT)
        if self.resp == CMD_ACK_UNAUTH:
            print(f"  may yeu cau xac thuc, gui Comm Key={comm_key}")
            self.cmd(CMD_AUTH, make_commkey(comm_key, self.session_id))
        if self.resp != CMD_ACK_OK:
            raise ConnectionError(f"may tu choi ket noi, ma {self.resp}")

    def option(self, name: str) -> str:
        self.cmd(CMD_OPTIONS_RRQ, name.encode() + b"\x00")
        if self.resp != CMD_ACK_OK:
            return ""
        raw = self.data.split(b"\x00")[0].decode("ascii", "replace")
        return raw.split("=", 1)[-1] if "=" in raw else raw

    def sizes(self):
        self.cmd(CMD_GET_FREE_SIZES)
        if self.resp != CMD_ACK_OK or len(self.data) < 80:
            raise ValueError(f"GET_FREE_SIZES tra ve {len(self.data)} byte, ma {self.resp}")
        f = struct.unpack("<20i", self.data[:80])
        return {"users": f[4], "fingers": f[6], "records": f[8], "cards": f[12],
                "users_cap": f[15], "rec_cap": f[16]}

    def read_buffered(self, data_cmd: int, fct: int = 0) -> bytes:
        out = bytearray()
        request = struct.pack("<bhii", 1, data_cmd, fct, 0)
        self.cmd(CMD_DATA_WRRQ, request, sink=out.extend)

        if self.resp == CMD_DATA:
            print(f"  may tra thang trong goi CMD_DATA: {len(out)} byte")
            return bytes(out)
        if self.resp == CMD_ACK_ERROR:
            raise NotImplementedError("may khong ho tro DATA_WRRQ (1503)")
        if len(self.data) < 5:
            raise ValueError(f"tra loi DATA_WRRQ la: ma={self.resp} len={len(self.data)}")

        total = struct.unpack("<I", self.data[1:5])[0]
        print(f"  kich thuoc bo dem tren may: {total} byte")

        start = 0
        while start < total:
            want = min(total - start, 0xFFC0)
            self.cmd(CMD_READ_BUFFER, struct.pack("<ii", start, want), sink=out.extend)
            if self.resp == CMD_PREPARE_DATA:
                announced = struct.unpack("<I", self.data[:4])[0] if len(self.data) >= 4 else want
                seen = 0
                while seen < announced:
                    before = len(out)
                    self.recv(sink=out.extend)
                    if self.resp == CMD_ACK_OK:
                        break
                    if self.resp != CMD_DATA:
                        raise ValueError(f"goi la giua luong: {self.resp}")
                    seen += len(out) - before
                    if len(out) == before:
                        raise ValueError("luong du lieu dung lai")
                else:
                    self.recv()
            elif self.resp != CMD_DATA:
                raise ValueError(f"READ_BUFFER tra ve ma la: {self.resp}")
            start += want

        self.cmd(CMD_FREE_DATA)
        return bytes(out)


def show_attendance(blob: bytes, count: int, show: int):
    if len(blob) < 4 or count == 0:
        print("  khong co ban ghi")
        return
    total = struct.unpack("<I", blob[:4])[0]
    body = blob[4:]
    size = total // count
    print(f"  tong {total} byte / {count} ban ghi -> co ban ghi {size} byte")
    print(f"  thuc nhan {len(body)} byte ({len(body) // size if size else 0} ban ghi)")

    if size not in (8, 16, 40):
        print(f"  CANH BAO: co ban ghi {size} khong nam trong 8/16/40")

    print(f"\n  {show} ban ghi dau va {show} ban ghi cuoi:")
    positions = list(range(min(show, len(body) // size)))
    tail_start = max(len(positions), len(body) // size - show)
    positions += list(range(tail_start, len(body) // size))

    for i in positions:
        rec = body[i * size:(i + 1) * size]
        if size >= 40:
            uid = struct.unpack("<H", rec[0:2])[0]
            pin = rec[2:26].split(b"\x00")[0].decode("ascii", "replace")
            verify = rec[26]
            when = struct.unpack("<I", rec[27:31])[0]
            state = rec[31]
        elif size == 16:
            pin = str(struct.unpack("<I", rec[0:4])[0])
            uid = 0
            when = struct.unpack("<I", rec[4:8])[0]
            verify, state = rec[8], rec[9]
        else:
            uid = struct.unpack("<H", rec[0:2])[0]
            pin = str(uid)
            verify = rec[2]
            when = struct.unpack("<I", rec[3:7])[0]
            state = rec[7]
        print(f"    uid={uid:<5} PIN={pin:<12} {decode_time(when)}  state={state} verify={verify}")


def show_users(blob: bytes, count: int, show: int):
    if len(blob) < 4 or count == 0:
        print("  khong co nhan vien")
        return
    total = struct.unpack("<I", blob[:4])[0]
    body = blob[4:]
    size = total // count
    print(f"  tong {total} byte / {count} nhan vien -> co goi {size} byte")
    if size not in (28, 72):
        print(f"  CANH BAO: co goi {size} khong nam trong 28/72")

    for i in range(min(show, len(body) // size)):
        rec = body[i * size:(i + 1) * size]
        if size >= 72:
            uid = struct.unpack("<H", rec[0:2])[0]
            priv = rec[2]
            name = rec[11:35].split(b"\x00")[0].decode("utf-8", "replace")
            card = struct.unpack("<I", rec[35:39])[0]
            pin = rec[48:72].split(b"\x00")[0].decode("ascii", "replace")
        else:
            uid = struct.unpack("<H", rec[0:2])[0]
            priv = rec[2]
            name = rec[8:16].split(b"\x00")[0].decode("utf-8", "replace")
            card = struct.unpack("<I", rec[16:20])[0]
            pin = str(struct.unpack("<I", rec[24:28])[0])
        print(f"    uid={uid:<5} PIN={pin:<12} ten={name!r:<22} the={card} quyen={priv}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("host")
    parser.add_argument("--port", type=int, default=4370)
    parser.add_argument("--comm-key", type=int, default=0)
    parser.add_argument("--records", type=int, default=5, help="so ban ghi in ra moi dau")
    args = parser.parse_args()

    print(f"Ket noi {args.host}:{args.port}")
    try:
        zk = Zk(args.host, args.port)
    except OSError as exc:
        print(f"khong mo duoc socket: {exc}")
        return 1

    try:
        zk.connect(args.comm_key)
        print(f"  OK, session={zk.session_id}")

        print("\nThong tin may:")
        for key in ("~SerialNumber", "~DeviceName", "~Platform", "~ZKFPVersion", "FaceFunOn"):
            print(f"  {key:<16} = {zk.option(key)!r}")
        zk.cmd(CMD_GET_VERSION)
        firmware = zk.data.split(b"\x00")[0].decode("ascii", "replace")
        print(f"  firmware         = {firmware!r}")

        info = zk.sizes()
        print(f"\nDung luong: {info}")

        print("\nDoc log cham cong:")
        blob = zk.read_buffered(CMD_ATTLOG_RRQ)
        show_attendance(blob, info["records"], args.records)

        print("\nDoc danh sach nhan vien:")
        blob = zk.read_buffered(CMD_USERTEMP_RRQ, FCT_USER)
        show_users(blob, info["users"], args.records)

        zk.cmd(CMD_EXIT)
        print("\nXong.")
    except Exception as exc:
        print(f"\nLOI: {type(exc).__name__}: {exc}")
        return 1
    finally:
        zk.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
