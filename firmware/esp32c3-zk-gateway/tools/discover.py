"""Do tim gateway SBOX trong mang LAN bang quang ba UDP.

Cai dat tham chieu cho phan do tim ma app Flutter se lam, dung de kiem chung
firmware tra loi dung dinh dang.

    python tools/discover.py
    python tools/discover.py --timeout 5
"""

import argparse
import json
import socket
import sys

PORT = 51820
PROBE = b"SBOX_DISCOVER"


def discover(timeout: float):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(0.6)

    found = {}
    deadline = timeout
    elapsed = 0.0
    step = 0.6

    # Gui lap lai vai lan vi UDP co the mat goi.
    while elapsed < deadline:
        try:
            sock.sendto(PROBE, ("255.255.255.255", PORT))
        except OSError as exc:
            print(f"khong gui duoc quang ba: {exc}")
            break

        while True:
            try:
                data, addr = sock.recvfrom(2048)
            except socket.timeout:
                break
            try:
                info = json.loads(data.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if info.get("product") != "sbox-zk-gateway":
                continue
            found[addr[0]] = info

        elapsed += step

    sock.close()
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=4.0)
    args = parser.parse_args()

    print(f"Dang quang ba SBOX_DISCOVER tren cong UDP {PORT}...")
    found = discover(args.timeout)

    if not found:
        print("Khong thay gateway nao.")
        return 1

    print(f"\nTim thay {len(found)} gateway:\n")
    for ip, info in found.items():
        name = info.get("name") or "(chua dat ten)"
        print(f"  {ip}  {name}")
        print(f"     host        : {info.get('host')}.local")
        print(f"     serial may  : {info.get('serial') or '(chua doc)'}")
        print(f"     IP may      : {info.get('deviceIp') or '(chua cau hinh)'}")
        print(f"     may online  : {info.get('deviceOnline')}")
        print(f"     server online: {info.get('serverOnline')}")
        print(f"     da cau hinh : {info.get('provisioned')}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
