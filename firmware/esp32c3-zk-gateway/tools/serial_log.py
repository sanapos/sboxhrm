"""Đọc log từ cổng USB của ESP32-C3 trong một khoảng thời gian rồi thoát.

Dùng khi cần xem log mà không muốn mở idf.py monitor ở chế độ tương tác.

    python tools/serial_log.py COM3 20
"""

import sys
import time

import serial


def main() -> int:
    port = sys.argv[1] if len(sys.argv) > 1 else "COM3"
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 15.0

    try:
        link = serial.Serial(port, 115200, timeout=0.2)
    except serial.SerialException as exc:
        print(f"khong mo duoc {port}: {exc}")
        return 1

    if "--reset" in sys.argv:
        # RTS nối chân EN: kéo xuống rồi thả để board khởi động lại từ đầu.
        link.dtr = False
        link.rts = True
        time.sleep(0.15)
        link.rts = False
        time.sleep(0.05)
        link.reset_input_buffer()

    deadline = time.time() + seconds
    pending = b""

    with link:
        while time.time() < deadline:
            chunk = link.read(4096)
            if not chunk:
                continue
            pending += chunk
            *lines, pending = pending.split(b"\n")
            for line in lines:
                sys.stdout.write(line.decode("utf-8", "replace").rstrip("\r") + "\n")
            sys.stdout.flush()

    if pending:
        print(pending.decode("utf-8", "replace"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
