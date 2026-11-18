#!/usr/bin/env python3
"""Mở IPA của SBOX POS và dừng build nếu còn sót khuôn mặt hoặc vị trí, trước khi tải lên Apple.

Chạy trên macOS của Codemagic: python3 scripts/verify_ios_pos_ipa.py <đường dẫn .ipa>
"""
from __future__ import annotations

import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

FORBIDDEN_PATHS = re.compile(
    r"mobilefacenet|w600k_mbf|FaceNet|TensorFlowLite|MLKit|MLKFace|GoogleMlKit|tflite_flutter|geolocator|network_info_plus|"
    r"DKImagePickerController|DKCamera|DKPhotoGallery|local_auth",
    re.IGNORECASE,
)
FORBIDDEN_SYMBOLS = re.compile(
    rb"TfLiteModelCreate|MLKFaceDetector|VNDetectFaceRectanglesRequest|VNDetectFaceLandmarksRequest|"
    rb"CIDetectorTypeFace|CLLocation|requestWhenInUseAuthorization|requestAlwaysAuthorization|"
    # Chỉ chặn khi GỌI API sinh trắc. Lớp LAContext tự xuất hiện vì flutter_secure_storage_darwin
    # khoá keychain bằng kSecAccessControl (biometryCurrentSet) — lưu token, không phải chấm công.
    rb"canEvaluatePolicy|evaluatePolicy|LAPolicyDeviceOwnerAuthenticationWithBiometrics"
)

# Apple 2.5.19 (17/11/2026): máy quét đọc mã trong gói và kết luận app «chứa chấm công, sinh trắc, theo dõi
# vị trí và tính lương» dù giao diện đã ẩn — vì bản POS build từ nguyên codebase HRM. Bản POS phải KHÔNG
# biên dịch phần đó vào gói, nên dò luôn trong ảnh Dart (App.framework/App).
# Tên lớp màn hình HRM: có trong ảnh Dart nghĩa là màn đó ĐÃ được biên dịch vào gói — đúng thứ
# Apple nêu ở điều 2.5.19. Nhãn chữ chung chung (tên module, nhãn menu, gợi ý trợ lý) chỉ được
# đếm và in ra ở phần cảnh báo: chúng là dữ liệu, không phải chức năng.
HIDDEN_FEATURE_SYMBOLS = (
    "AttendanceScreen",
    "AttendanceSummaryScreen",
    "MobileAttendanceScreen",
    "PayrollScreen",
    "PayslipScreen",
    "SalarySettingsScreen",
    "LeaveRequestScreen",
    "OvertimeScreen",
    "HrFinanceHubScreen",
    "FaceRegistration",
    "DeviceSyncProgressOverlay",
)

HIDDEN_FEATURE_WORDS = (
    "chấm công",
    "tính lương",
    "bảng lương",
    "phiếu lương",
    "nghỉ phép",
    "khuôn mặt",
)


def _hits(binary: Path, needles) -> list[str]:
    """Chuỗi Dart nằm trong ảnh AOT ở cả dạng một byte lẫn UTF-16LE (chữ có dấu) — phải dò cả hai."""
    data = binary.read_bytes()
    return [w for w in needles
            if w.encode("utf-8") in data or w.encode("utf-16-le") in data]


def feature_symbols_in(binary: Path) -> list[str]:
    return _hits(binary, HIDDEN_FEATURE_SYMBOLS)


def feature_words_in(binary: Path) -> list[str]:
    return _hits(binary, HIDDEN_FEATURE_WORDS)


FORBIDDEN_PLIST_KEYS = (
    "NSLocationWhenInUseUsageDescription",
    "NSLocationAlwaysUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
)


def macho_files(app: Path) -> list[Path]:
    found = [app / app.stem]
    for framework in (app / "Frameworks").glob("*.framework"):
        found.append(framework / framework.stem)
    return [path for path in found if path.is_file()]


def main() -> None:
    ipa = Path(sys.argv[1])
    problems: list[str] = []
    warnings: list[str] = []
    with tempfile.TemporaryDirectory() as tmp, zipfile.ZipFile(ipa) as archive:
        problems += [f"file: {name}" for name in archive.namelist() if FORBIDDEN_PATHS.search(name)]
        archive.extractall(tmp)
        app = next(Path(tmp, "Payload").glob("*.app"))

        with (app / "Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
        problems += [f"Info.plist: {key}" for key in FORBIDDEN_PLIST_KEYS if key in info]
        for key, value in info.items():
            if key.endswith("UsageDescription") and re.search("khuôn mặt|chấm công", str(value), re.IGNORECASE):
                problems.append(f"Info.plist text: {key}")

        for binary in macho_files(app):
            linked = subprocess.run(["otool", "-L", str(binary)], capture_output=True, text=True, check=True).stdout
            # libswiftCoreLocation.dylib là thư viện Swift của hệ thống, tự thêm khi module khác nhập Photos, AVFoundation;
            # không có API nào được gọi (đã kiểm tra bằng FORBIDDEN_SYMBOLS ngay dưới).
            if "CoreLocation.framework" in linked:
                problems.append(f"links CoreLocation: {binary.name}")
            for symbol in sorted(set(FORBIDDEN_SYMBOLS.findall(binary.read_bytes()))):
                problems.append(f"symbol {symbol.decode()}: {binary.name}")
            problems += [f"hidden feature «{name}»: {binary.name}"
                         for name in feature_symbols_in(binary)]
            labels = feature_words_in(binary)
            if labels:
                warnings.append(f"{binary.name}: còn nhãn chữ HRM {labels}")

    for line in warnings:
        print(f"  cảnh báo — {line}")
    if problems:
        print("SBOX POS IPA still contains face or location code:")
        print("\n".join(f"  {problem}" for problem in problems))
        raise SystemExit(1)
    print(f"SBOX POS IPA clean: {ipa.name}")


if __name__ == "__main__":
    main()
