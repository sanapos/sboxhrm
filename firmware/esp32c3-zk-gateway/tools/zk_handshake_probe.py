"""Thu nhieu bien the khung goi CMD_CONNECT de tim dinh dang may chap nhan.

    python tools/zk_handshake_probe.py 192.168.1.35
"""

import argparse
import socket
import struct
import sys

MAGIC = struct.pack("<HH", 0x5050, 0x7D82)
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
    value = ~total
    while value < 0:
        value += USHRT_MAX
    return value


def packet(command: int, session_id: int, chk_rid: int, sent_rid: int) -> bytes:
    """chk_rid = reply_id dung khi tinh checksum, sent_rid = reply_id thuc gui."""
    base = struct.pack("<4H", command, 0, session_id, chk_rid)
    return struct.pack("<4H", command, checksum(base), session_id, sent_rid)


def try_tcp(host, port, blob, label, timeout=6.0):
    print(f"\n[{label}]")
    print(f"  gui  ({len(blob)} byte): {blob.hex(' ')}")
    try:
        with socket.create_connection((host, port), timeout) as sock:
            sock.settimeout(timeout)
            sock.sendall(blob)
            try:
                data = sock.recv(1024)
            except socket.timeout:
                print("  nhan : (het thoi gian, khong co byte nao)")
                return False
            if not data:
                print("  nhan : (may dong ket noi ngay)")
                return False
            print(f"  nhan ({len(data)} byte): {data.hex(' ')}")
            decode(data)
            return True
    except OSError as exc:
        print(f"  loi socket: {exc}")
        return False


def try_udp(host, port, blob, label, timeout=6.0):
    print(f"\n[{label}]")
    print(f"  gui  ({len(blob)} byte): {blob.hex(' ')}")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        sock.sendto(blob, (host, port))
        data, _ = sock.recvfrom(1024)
        print(f"  nhan ({len(data)} byte): {data.hex(' ')}")
        decode(data)
        return True
    except socket.timeout:
        print("  nhan : (het thoi gian)")
        return False
    except OSError as exc:
        print(f"  loi socket: {exc}")
        return False
    finally:
        sock.close()


NAMES = {2000: "CMD_ACK_OK", 2001: "CMD_ACK_ERROR", 2002: "CMD_ACK_DATA",
         2005: "CMD_ACK_UNAUTH", 1500: "CMD_PREPARE_DATA", 1501: "CMD_DATA"}


def decode(data: bytes):
    body = data
    if len(data) >= 8 and data[:4] == MAGIC:
        length = struct.unpack("<I", data[4:8])[0]
        print(f"  -> co header TCP, do dai khai bao = {length}")
        body = data[8:]
    if len(body) >= 8:
        cmd, chk, sid, rid = struct.unpack("<4H", body[:8])
        print(f"  -> ma={cmd} ({NAMES.get(cmd, '?')}) checksum={chk} session={sid} reply={rid}")
        if len(body) > 8:
            print(f"  -> phan than: {body[8:].hex(' ')}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("host")
    parser.add_argument("--port", type=int, default=4370)
    args = parser.parse_args()

    CONNECT = 1000

    # pyzk that su: checksum tinh voi reply_id=65534 nhung gui reply_id=0
    pyzk = packet(CONNECT, 0, 65534, 0)
    # checksum khop dung voi byte gui
    exact = packet(CONNECT, 0, 0, 0)
    # reply_id giu nguyen 65534
    keep = packet(CONNECT, 0, 65534, 65534)
    # reply_id = 1
    one = packet(CONNECT, 0, 1, 1)

    tests = [
        ("TCP + header magic, kieu pyzk (rid gui=0)", "tcp", MAGIC + struct.pack("<I", len(pyzk)) + pyzk),
        ("TCP + header magic, checksum khop chinh xac", "tcp", MAGIC + struct.pack("<I", len(exact)) + exact),
        ("TCP + header magic, rid=65534", "tcp", MAGIC + struct.pack("<I", len(keep)) + keep),
        ("TCP + header magic, rid=1", "tcp", MAGIC + struct.pack("<I", len(one)) + one),
        ("TCP khong header magic (goi tran)", "tcp", exact),
        ("UDP goi tran kieu pyzk", "udp", pyzk),
        ("UDP goi tran checksum khop", "udp", exact),
        ("UDP co header magic", "udp", MAGIC + struct.pack("<I", len(exact)) + exact),
    ]

    winners = []
    for label, kind, blob in tests:
        ok = try_tcp(args.host, args.port, blob, label) if kind == "tcp" \
            else try_udp(args.host, args.port, blob, label)
        if ok:
            winners.append(label)

    print("\n=== Ket luan ===")
    if winners:
        for w in winners:
            print(f"  CO tra loi: {w}")
    else:
        print("  Khong bien the nao duoc tra loi.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
