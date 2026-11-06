#!/usr/bin/env python3
"""Gỡ khuôn mặt và vị trí khỏi bản SBOX POS iOS, ngay trên máy build (không commit kết quả).

Apple từ chối POS 1.0.5 theo 2.3.1(a) vì tính năng ẩn. Ẩn menu chưa đủ: plugin, model và API hệ thống
vẫn nằm trong gói. Script này chỉ chạy trong workflow ios-pos-release, trước `flutter pub get`.
HRM, Android và các app khác không bị ảnh hưởng.

Mọi thay đổi đều phải khớp code hiện tại, không khớp thì dừng build để không gỡ thiếu mà không biết.
Chạy thử: python scripts/prepare_ios_pos_build.py <thư mục flutter_client của bản sao>
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "flutter_client"

REMOVED_DEPENDENCIES = ("google_mlkit_face_detection", "geolocator", "tflite_flutter")
REMOVED_ASSETS = ("assets/mobilefacenet.tflite", "assets/w600k_mbf.onnx")
REMOVED_FILES = (
    "assets/mobilefacenet.tflite",
    "assets/w600k_mbf.onnx",
    "ios/Runner/NativeFaceEmbedder.swift",
    "ios/Runner/TFLiteSymbolKeepalive.m",
    "lib/services/ios_native_face_embedder.dart",
    "lib/services/mlkit_face_signature_service.dart",
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

Future<bool> ensureLocationPermission() async => false;

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


def patch_pubspec() -> None:
    text = read("pubspec.yaml")
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


def main() -> None:
    patch_pubspec()
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
