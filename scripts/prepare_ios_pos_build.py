#!/usr/bin/env python3
"""Gỡ khuôn mặt và vị trí khỏi bản SBOX POS iOS, ngay trên máy build (không commit kết quả).

Apple từ chối POS 1.0.5 theo 2.3.1(a) vì tính năng ẩn. Ẩn menu chưa đủ: plugin, model và API hệ thống
vẫn nằm trong gói. Script này chỉ chạy trong workflow ios-pos-release, trước `flutter pub get`.
HRM, Android và các app khác không bị ảnh hưởng.

Mọi thay đổi đều phải khớp code hiện tại, không khớp thì dừng build để không gỡ thiếu mà không biết.
Chạy thử: python scripts/prepare_ios_pos_build.py <thư mục flutter_client của bản sao>
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import url2pathname

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "flutter_client"

# local_auth: Apple 2.5.19 (17/11/2026) nêu đích danh «biometric». Bản bán hàng vốn đã ẩn đăng nhập Face ID
# (SboxAppVariant.iosPosApp), nhưng plugin vẫn nhúng framework vào gói nên máy quét của Apple vẫn thấy.
# flutter_map / latlong2 chỉ dùng cho bản đồ chấm công và bản đồ nhân sự.
REMOVED_DEPENDENCIES = (
    "google_mlkit_face_detection",
    "geolocator",
    "tflite_flutter",
    "local_auth",
    "local_auth_android",
    "flutter_map",
    "latlong2",
)
REMOVED_ASSETS = ("assets/mobilefacenet.tflite", "assets/w600k_mbf.onnx")
# Các tệp còn import gói vừa gỡ. Điểm vào lib/main_pos.dart không với tới chúng nên không được biên dịch,
# nhưng vẫn xóa để một import lỡ tay sau này làm hỏng build ngay thay vì lọt vào gói nộp Apple.
REMOVED_FILES = (
    "assets/mobilefacenet.tflite",
    "assets/w600k_mbf.onnx",
    "ios/Runner/NativeFaceEmbedder.swift",
    "ios/Runner/TFLiteSymbolKeepalive.m",
    "lib/services/ios_native_face_embedder.dart",
    "lib/services/mlkit_face_signature_service.dart",
    "lib/services/biometric_auth_local.dart",
    "lib/screens/attendance_approval_v2/aa_detail.dart",
    "lib/screens/staff_map/staff_map_screen.dart",
    "lib/widgets/map_location_picker.dart",
    "lib/widgets/punch_location_preview.dart",
)

GEOLOCATION = """class GeoPosition {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double? speed;
  final DateTime? timestamp;
  GeoPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.speed,
    this.timestamp,
  });
}

class GeoError {
  final int code;
  final String message;
  GeoError(this.code, this.message);
  @override
  String toString() => 'GeoError($code): $message';
}

Future<bool> ensureLocationPermission({bool ask = true}) async => false;

Future<GeoPosition?> getLastKnownPosition() async => null;

Future<GeoPosition> getCurrentPosition({
  bool enableHighAccuracy = true,
  int timeout = 10000,
  int maximumAge = 0,
}) async =>
    throw GeoError(1, 'Not available');
"""

VERIFICATION_CAMERA = """import 'package:flutter/widgets.dart';

class FaceVerificationResult {
  final double matchScore;
  final String? faceImageBase64;
  final bool livenessPassed;
  final String? clientFaceEngine;
  FaceVerificationResult({
    required this.matchScore,
    this.faceImageBase64,
    this.livenessPassed = false,
    this.clientFaceEngine,
  });
}

abstract final class FaceVerificationCamera {
  static Future<FaceVerificationResult?> show(
    BuildContext context, {
    List<String>? registeredFacePaths,
    double minMatchScore = 60.0,
  }) async =>
      null;
}
"""

CIRCLE_CAPTURE = """import 'package:flutter/widgets.dart';

abstract final class CircleFaceCaptureWidget {
  static Future<List<String>?> show(BuildContext context) async => null;
}
"""

NETWORK_INFO_PUBSPEC = """name: network_info_plus
version: 6.0.1
publish_to: none
environment:
  sdk: '>=3.0.0 <4.0.0'
"""

# Không có mã native: plugin thật kéo theo CoreLocation để đọc tên WiFi.
NETWORK_INFO = """import 'dart:io';

class NetworkInfo {
  Future<String?> getWifiName() async => null;
  Future<String?> getWifiBSSID() async => null;
  Future<String?> getWifiIP() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final interface in interfaces) {
      if (interface.name == 'en0' && interface.addresses.isNotEmpty) {
        return interface.addresses.first.address;
      }
    }
    return null;
  }
}
"""


def read(rel: str) -> str:
    # pubspec.yaml có dòng chú thích không phải UTF-8 hợp lệ, phải giữ nguyên byte.
    return (ROOT / rel).read_text(encoding="utf-8", errors="surrogateescape")


def write(rel: str, text: str) -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", errors="surrogateescape", newline="\n")


def remove_line(text: str, pattern: str, label: str) -> str:
    result, count = re.subn(pattern, "", text, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"Expected one {label}, found {count}")
    return result


def replace_once(text: str, pattern: str, replacement: str, label: str) -> str:
    result, count = re.subn(pattern, replacement, text, flags=re.DOTALL)
    if count != 1:
        raise SystemExit(f"Expected one {label}, found {count}")
    return result


def vendor_file_picker() -> None:
    """Chép file_picker rồi cắt DKImagePickerController: thư viện này kèm DKCamera dùng CLLocationManager.

    Từ iOS 14 plugin chọn ảnh bằng PHPicker của Apple, app yêu cầu iOS 16 nên nhánh DK không bao giờ chạy.
    """
    flutter = os.environ.get("FLUTTER_BIN") or shutil.which("flutter") or "flutter"
    subprocess.run([flutter, "pub", "get"], cwd=ROOT, check=True)
    config = json.loads((ROOT / ".dart_tool/package_config.json").read_text(encoding="utf-8"))
    package = next(p for p in config["packages"] if p["name"] == "file_picker")
    source = Path(url2pathname(urlparse(package["rootUri"]).path))
    target = ROOT / ".pos_stubs/file_picker"
    shutil.copytree(source, target, ignore=shutil.ignore_patterns("example"))

    native = "ios/file_picker/Sources/file_picker/FilePickerPlugin.m"
    plugin = (target / native).read_text(encoding="utf-8", errors="surrogateescape")
    plugin = replace_once(plugin, r"@import DKImagePickerController;\r?\n", "", "DK import")
    plugin = replace_once(plugin, r"@interface FilePickerPlugin\(\) <DKImageAssetExporterObserver>", "@interface FilePickerPlugin()", "DK observer")
    plugin = replace_once(
        plugin,
        r"- \(void\) resolveMultiPickFromGallery:.*?(?=#endif // PICKER_MEDIA)",
        "- (void) resolveMultiPickFromGallery:(MediaType)type withCompressionAllowed:(BOOL)allowCompression {\n"
        "    self->_result(nil);\n"
        "    self->_result = nil;\n"
        "}\n",
        "DK picker method",
    )
    (target / native).write_text(plugin, encoding="utf-8", errors="surrogateescape", newline="\n")

    manifest_path = target / "ios/file_picker/Package.swift"
    manifest = manifest_path.read_text(encoding="utf-8")
    manifest = replace_once(manifest, r"dependencies: \[\s*\.package\(url: \"[^\"]*DKImagePickerController\"[^\n]*\s*\],", "dependencies: [],", "DK package")
    manifest = replace_once(manifest, r"dependencies: \[\s*\.product\(name: \"DKImagePickerController\"[^\n]*\s*\],", "dependencies: [],", "DK product")
    manifest_path.write_text(manifest, encoding="utf-8", newline="\n")
    (target / "ios/file_picker/Package.resolved").unlink()

    podspec_path = target / "ios/file_picker.podspec"
    podspec = podspec_path.read_text(encoding="utf-8")
    podspec = replace_once(podspec, r"[ \t]*s\.dependency 'DKImagePickerController/PhotoGallery'\r?\n", "", "DK pod")
    podspec_path.write_text(podspec, encoding="utf-8", newline="\n")


def patch_pubspec() -> None:
    text = read("pubspec.yaml")
    text = replace_once(text, r"(?m)^  file_picker: [^\n]*$", "  file_picker:\n    path: .pos_stubs/file_picker", "dependency file_picker")
    for name in REMOVED_DEPENDENCIES:
        text = remove_line(text, rf"^  {name}: .*\r?\n", f"dependency {name}")
    for asset in REMOVED_ASSETS:
        text = remove_line(text, rf"^    - {re.escape(asset)}\s*\r?\n", f"asset {asset}")
    text, count = re.subn(
        r"^  network_info_plus: .*$",
        "  network_info_plus:\n    path: .pos_stubs/network_info_plus",
        text,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise SystemExit(f"Expected one dependency network_info_plus, found {count}")
    write("pubspec.yaml", text)


def patch_app_delegate() -> None:
    text = read("ios/Runner/AppDelegate.swift")
    text, count = re.subn(
        r"[ \t]*//[^\n]*native \(CoreML[^\n]*\r?\n"
        r"[ \t]*//[^\n]*\r?\n"
        r"[ \t]*if let registrar = [^\n]*\"NativeFaceEmbedder\"[^\n]*\r?\n"
        r"[ \t]*NativeFaceEmbedder\.register[^\n]*\r?\n"
        r"[ \t]*\}\r?\n",
        "",
        text,
    )
    if count != 1:
        raise SystemExit(f"Expected one NativeFaceEmbedder registration, found {count}")
    write("ios/Runner/AppDelegate.swift", text)



# Từ vựng HRM trong chuỗi giao diện. Apple 2.5.19 đọc mã trong gói, mà bảng chuỗi Việt → Anh được biên dịch
# thẳng vào ảnh Dart: 452 dòng chứa «chấm công», 29 dòng chứa «tính lương». Bản bán hàng không có những màn
# đó nên bỏ hẳn các dòng này, vừa sạch gói vừa nhẹ bớt.
HRM_STRING_WORDS = (
    "chấm công",
    "lương",
    "nghỉ phép",
    "khuôn mặt",
    "bảo hiểm",
    "thuế tncn",
    "tăng ca",
    "phụ cấp",
)


def _is_hrm_line(line: str) -> bool:
    low = line.lower()
    return any(word in low for word in HRM_STRING_WORDS)


def strip_hrm_ui_strings() -> None:
    """Bỏ chuỗi giao diện của HRM khỏi bảng dịch và gói ngôn ngữ của bản bán hàng."""
    rel = "lib/l10n/en_ui_map.g.dart"
    lines = read(rel).split("\n")
    # Bỏ CẢ MỤC chứ không bỏ từng dòng: mục dài được generator xuống dòng, khóa ở dòng này còn bản dịch ở
    # dòng sau. Bỏ mỗi dòng khóa thì dòng dịch mồ côi → tệp hỏng cú pháp, build IPA chết (18/11/2026).
    kept: list[str] = []
    entry: list[str] = []
    dropped = 0
    for line in lines:
        if entry:
            entry.append(line)
        elif line.startswith("  '"):
            entry = [line]
        else:
            kept.append(line)
            continue
        # Mục kết thúc khi dòng cuối đóng bằng dấu phẩy.
        if entry[-1].rstrip().endswith(","):
            if any(_is_hrm_line(l) for l in entry):
                dropped += len(entry)
            else:
                kept.extend(entry)
            entry = []
    kept.extend(entry)
    if dropped == 0:
        raise SystemExit(f"Expected HRM strings in {rel}, found none")
    # Dòng tiếp nối mồ côi = đã cắt sai, dừng build còn hơn nộp gói hỏng.
    for i, l in enumerate(kept):
        if l.startswith("      '") and not kept[i - 1].startswith("  '"):
            raise SystemExit(f"{rel}: dòng {i + 1} mồ côi sau khi lọc")
    write(rel, "\n".join(kept))
    print(f"{rel}: bỏ {dropped} dòng chuỗi HRM")

    # Chính sách / điều khoản / trợ giúp dùng chung 4 app. SboxAppVariant.stripIosPosLegal đã lọc lúc HIỂN THỊ,
    # nhưng nguyên văn vẫn nằm trong gói — đúng thứ máy quét của Apple đọc. Lọc luôn ở mã nguồn.
    legal = "lib/content/app_legal_pages.dart"
    lines = read(legal).split("\n")
    kept = [
        l for l in lines
        if not (_is_hrm_line(l) or re.search(r"khuôn mặt|sinh trắc|vị trí|GPS", l, re.IGNORECASE))
        or l.lstrip().startswith(("static ", "abstract ", "class ", "}", "'''"))
    ]
    dropped = len(lines) - len(kept)
    if dropped == 0:
        raise SystemExit(f"Expected HRM lines in {legal}, found none")
    write(legal, "\n".join(kept))
    print(f"{legal}: bỏ {dropped} dòng")

    # Bảng chuỗi tiếng Việt của app (một mục / một dòng) và bảng tên module phân quyền. Thiếu khóa thì
    # `AppLocalizations.get` trả lại chính khóa và `PermissionModuleLabels.resolve` trả lại mã module,
    # nên bỏ mục là an toàn — bản bán hàng không có màn nào dùng tới chúng.
    for rel in ("lib/l10n/app_localizations.dart", "lib/utils/permission_module_labels.dart"):
        lines = read(rel).split("\n")
        kept, dropped = [], 0
        for line in lines:
            # Chỉ bỏ dòng có dạng trọn vẹn `'khóa': 'giá trị',` — không chạm mã.
            if _is_hrm_line(line) and re.fullmatch(r"\s*'[^']+':\s*'.*',?\s*", line):
                dropped += 1
                continue
            kept.append(line)
        if dropped == 0:
            raise SystemExit(f"Expected HRM entries in {rel}, found none")
        write(rel, "\n".join(kept))
        print(f"{rel}: bỏ {dropped} mục chuỗi HRM")

    for lang in ("en", "ja", "ko", "zh"):
        pack = f"assets/l10n/{lang}.json"
        path = ROOT / pack
        if not path.is_file():
            continue
        data = json.loads(read(pack))
        before = len(data.get("m", {}))
        data["m"] = {k: v for k, v in data.get("m", {}).items() if not _is_hrm_line(k)}
        data["t"] = [p for p in data.get("t", []) if not _is_hrm_line(str(p[0]))]
        write(pack, json.dumps(data, ensure_ascii=False, separators=(",", ":")))
        print(f"{pack}: còn {len(data['m'])}/{before} chuỗi")


def strip_marked_regions() -> None:
    """Bỏ các khối mã đánh dấu `// SBOX-POS-STRIP-BEGIN … // SBOX-POS-STRIP-END` khỏi bản bán hàng.

    Dùng cho nhóm mã chỉ SBOX HRM nằm lẫn trong tệp dùng chung (ví dụ ba lệnh API đăng ký khuôn mặt
    trong `api_service.dart`) — không tách ra tệp riêng được vì chúng gọi thành viên private.
    """
    pattern = re.compile(
        r"[ \t]*//\s*SBOX-POS-STRIP-BEGIN.*?//\s*SBOX-POS-STRIP-END[^\n]*\n",
        re.S,
    )
    total = 0
    for path in sorted((ROOT / "lib").rglob("*.dart")):
        rel = path.relative_to(ROOT).as_posix()
        text = read(rel)
        new, count = pattern.subn("", text)
        if count:
            write(rel, new)
            total += count
            print(f"{rel}: bỏ {count} khối chỉ-HRM")
    if total == 0:
        raise SystemExit("Expected SBOX-POS-STRIP blocks, found none")


def main() -> None:
    vendor_file_picker()
    patch_pubspec()
    strip_hrm_ui_strings()
    strip_marked_regions()
    patch_app_delegate()

    for rel in REMOVED_FILES:
        path = ROOT / rel
        if not path.is_file():
            raise SystemExit(f"Expected file to remove: {rel}")
        path.unlink()

    # Các bản thay thế: cùng API với bản thật để phần code còn lại vẫn biên dịch, không làm gì cả.
    write("lib/services/face_embedding_service.dart", read("lib/services/face_embedding_service_stub.dart"))
    write("lib/utils/platform_geolocation_stub.dart", GEOLOCATION)
    write("lib/widgets/face_verification_camera.dart", VERIFICATION_CAMERA)
    write("lib/widgets/circle_face_capture_widget.dart", CIRCLE_CAPTURE)
    write(".pos_stubs/network_info_plus/pubspec.yaml", NETWORK_INFO_PUBSPEC)
    write(".pos_stubs/network_info_plus/lib/network_info_plus.dart", NETWORK_INFO)
    print("SBOX POS iOS: face and location plugins, models and native code removed")


if __name__ == "__main__":
    main()
