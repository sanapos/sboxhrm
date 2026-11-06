#!/usr/bin/env python3
"""Đổi project iOS dùng chung thành SBOX BOSS hoặc SBOX Nhân Viên, ngay trên máy build Codemagic.

Đổi mã bundle, tên app, icon. BOSS không có khuôn mặt, vị trí nên câu xin quyền được viết riêng;
Nhân Viên giữ câu mặc định vì có chấm công bằng khuôn mặt và vị trí.

Cách dùng (trong flutter_client): python3 ../scripts/ios_companion_setup.py boss|staff
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

APPS = {
    "boss": ("boss.sboxpos.com", "SBOX BOSS"),
    "staff": ("staff.sboxpos.com", "SBOX Nhân Viên"),
}
BOSS_USAGE = {
    "NSCameraUsageDescription": "Camera dùng để chụp ảnh chứng từ gửi cho Trợ lý AI, chỉ khi bạn chủ động dùng. Ứng dụng không quay video nền.",
    "NSLocalNetworkUsageDescription": "Mạng nội bộ dùng để tìm và kết nối máy in, màn hình bếp trong cùng WiFi cửa hàng.",
    "NSBluetoothAlwaysUsageDescription": "Bluetooth dùng để kết nối máy in hóa đơn và máy in tem.",
    "NSBluetoothPeripheralUsageDescription": "Bluetooth dùng để kết nối máy in hóa đơn và máy in tem.",
    "NSFaceIDUsageDescription": "Face ID dùng để đăng nhập nhanh vào SBOX BOSS thay cho mật khẩu, chỉ khi bạn bật trong Cài đặt.",
}
PLIST = "ios/Runner/Info.plist"
OLD_BUNDLE = "PRODUCT_BUNDLE_IDENTIFIER = vn.sana.sbox;"
ICON_DIR = Path("ios/Runner/Assets.xcassets/AppIcon.appiconset")


def plist(command: str) -> None:
    subprocess.run(["/usr/libexec/PlistBuddy", "-c", command, PLIST], check=True)


def main() -> None:
    app = sys.argv[1]
    bundle, name = APPS[app]

    project = Path("ios/Runner.xcodeproj/project.pbxproj")
    text = project.read_text(encoding="utf-8")
    count = text.count(OLD_BUNDLE)
    if count != 3:
        raise SystemExit(f"Expected 3 Runner bundle ids, found {count}")
    project.write_text(text.replace(OLD_BUNDLE, f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};"), encoding="utf-8")

    plist(f"Set :CFBundleDisplayName {name}")
    if app == "boss":
        plist("Delete :NSLocationWhenInUseUsageDescription")
        for key, value in BOSS_USAGE.items():
            plist(f"Set :{key} {value}")

    source = f"ios/flavor_icons/{app}-1024.png"
    for icon in ICON_DIR.glob("*.png"):
        info = subprocess.run(["sips", "-g", "pixelWidth", str(icon)], capture_output=True, text=True, check=True).stdout
        px = re.search(r"pixelWidth: (\d+)", info).group(1)
        subprocess.run(["sips", "-s", "format", "png", "-z", px, px, source, "--out", str(icon)], check=True, capture_output=True)
    print(f"iOS project set to {name} ({bundle})")


if __name__ == "__main__":
    main()
