#!/usr/bin/env python3
"""Đổi project iOS dùng chung thành SBOX BOSS hoặc SBOX Nhân Viên, ngay trên máy build Codemagic.

Đổi mã bundle, tên app, icon, và viết câu xin quyền riêng theo đúng chức năng của từng app.
BOSS không có khuôn mặt, vị trí (plugin bị gỡ ở prepare_ios_pos_build.py). Nhân Viên có thêm câu cho API vị trí «luôn luôn» (ITMS-90683).

Cách dùng (trong flutter_client): python3 ../scripts/ios_companion_setup.py boss|staff
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

APPS = {
    "boss": ("boss.sboxpos.com", "SBOX BOSS"),
    # Tên dưới biểu tượng iPhone (CFBundleDisplayName) — «SBOX Nhân Viên» bị cắt; tên App Store giữ nguyên.
    "staff": ("staff.sboxpos.com", "Nhân Viên"),
}
BOSS_USAGE = {
    "NSCameraUsageDescription": "Camera dùng để quét mã vạch và chụp ảnh hàng hóa, chứng từ, chỉ khi bạn chủ động dùng. Ứng dụng không quay video nền.",
    "NSLocalNetworkUsageDescription": "Mạng nội bộ dùng để tìm và kết nối máy in, màn hình bếp trong cùng WiFi cửa hàng.",
    "NSBluetoothAlwaysUsageDescription": "Bluetooth dùng để kết nối máy in hóa đơn và máy in tem.",
    "NSBluetoothPeripheralUsageDescription": "Bluetooth dùng để kết nối máy in hóa đơn và máy in tem.",
    "NSFaceIDUsageDescription": "Face ID dùng để đăng nhập nhanh vào SBOX BOSS thay cho mật khẩu, chỉ khi bạn bật trong Cài đặt.",
}
STAFF_USAGE = {
    "NSCameraUsageDescription": "Camera dùng để chấm công bằng khuôn mặt khi bạn bấm Chấm công, đăng ký khuôn mặt và chụp ảnh hiện trường, chứng từ. Ứng dụng không quay video nền.",
    "NSLocalNetworkUsageDescription": "Mạng nội bộ dùng để kết nối máy in và màn hình bếp trong cùng WiFi cửa hàng khi bạn gọi món.",
    "NSBluetoothAlwaysUsageDescription": "Bluetooth dùng để kết nối máy in khi bạn gọi món.",
    "NSBluetoothPeripheralUsageDescription": "Bluetooth dùng để kết nối máy in khi bạn gọi món.",
    "NSFaceIDUsageDescription": "Face ID dùng để đăng nhập nhanh vào SBOX Nhân Viên thay cho mật khẩu, chỉ khi bạn bật trong Cài đặt.",
    # Info.plist dùng chung ghi micro / thư viện ảnh cho Trợ lý AI, ảnh sản phẩm: Nhân Viên không có các chức năng đó.
    "NSMicrophoneUsageDescription": "Micro chỉ dùng khi bạn bấm nút micro để nhập bằng giọng nói. Ứng dụng không ghi âm nền.",
    "NSSpeechRecognitionUsageDescription": "Nhận dạng giọng nói chuyển lời bạn nói thành chữ, chỉ khi bạn bấm nút micro.",
    "NSPhotoLibraryUsageDescription": "Thư viện ảnh dùng để chọn ảnh đại diện, ảnh chứng từ, hóa đơn đính kèm đơn từ và góp ý, chỉ khi bạn chủ động chọn ảnh.",
    # Apple đòi câu cho API «luôn luôn» vì thư viện vị trí có tham chiếu (ITMS-90683), dù app chỉ xin quyền khi đang dùng.
    "NSLocationAlwaysAndWhenInUseUsageDescription": "SBOX Nhân Viên không dùng vị trí khi chạy nền. Vị trí chỉ được lấy khi bạn đang mở ứng dụng: lúc chấm công, check-in và định kỳ nếu cửa hàng bật Bản đồ nhân sự.",
    "NSLocationAlwaysUsageDescription": "SBOX Nhân Viên không dùng vị trí khi chạy nền. Vị trí chỉ được lấy khi bạn đang mở ứng dụng: lúc chấm công, check-in và định kỳ nếu cửa hàng bật Bản đồ nhân sự.",
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

    # Thông báo đẩy: mỗi bundle có cấu hình Firebase riêng, fcm_service đọc tệp native này.
    firebase = Path(f"ios/flavor_firebase/{app}-GoogleService-Info.plist")
    if f"<string>{bundle}</string>" not in firebase.read_text(encoding="utf-8"):
        raise SystemExit(f"{firebase} is not for {bundle}")
    shutil.copyfile(firebase, "ios/Runner/GoogleService-Info.plist")

    plist(f"Set :CFBundleDisplayName {name}")
    if app == "boss":
        # BOSS gỡ hẳn plugin vị trí (prepare_ios_pos_build.py); verify_ios_pos_ipa.py không cho còn câu vị trí.
        plist("Delete :NSLocationWhenInUseUsageDescription")
    for key, value in (BOSS_USAGE if app == "boss" else STAFF_USAGE).items():
        # Info.plist dùng chung chưa có khóa «luôn luôn»: Set lỗi thì Add.
        try:
            plist(f"Set :{key} {value}")
        except subprocess.CalledProcessError:
            plist(f"Add :{key} string {value}")

    source = f"ios/flavor_icons/{app}-1024.png"
    for icon in ICON_DIR.glob("*.png"):
        info = subprocess.run(["sips", "-g", "pixelWidth", str(icon)], capture_output=True, text=True, check=True).stdout
        px = re.search(r"pixelWidth: (\d+)", info).group(1)
        subprocess.run(["sips", "-s", "format", "png", "-z", px, px, source, "--out", str(icon)], check=True, capture_output=True)
    print(f"iOS project set to {name} ({bundle})")


if __name__ == "__main__":
    main()
