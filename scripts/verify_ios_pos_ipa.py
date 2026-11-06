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
    r"DKImagePickerController|DKCamera|DKPhotoGallery",
    re.IGNORECASE,
)
FORBIDDEN_SYMBOLS = re.compile(
    rb"TfLiteModelCreate|MLKFaceDetector|VNDetectFaceRectanglesRequest|VNDetectFaceLandmarksRequest|"
    rb"CIDetectorTypeFace|CLLocationManager"
)
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
            if "CoreLocation" in linked:
                problems.append(f"links CoreLocation: {binary.name}")
            for symbol in sorted(set(FORBIDDEN_SYMBOLS.findall(binary.read_bytes()))):
                problems.append(f"symbol {symbol.decode()}: {binary.name}")

    if problems:
        print("SBOX POS IPA still contains face or location code:")
        print("\n".join(f"  {problem}" for problem in problems))
        raise SystemExit(1)
    print(f"SBOX POS IPA clean: {ipa.name}")


if __name__ == "__main__":
    main()
