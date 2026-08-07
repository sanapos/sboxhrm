# SBOX POS — Flutter 3.22 (Android 6.0)

App Flutter POS độc lập, port UI + logic bán hàng từ `flutter_client`. **Không đụng** `flutter_client`.

| | |
|---|---|
| SDK (FVM) | **Flutter 3.22.3** / Dart 3.4.4 |
| `minSdk` | **23** (Android 6.0) |
| Application ID | `sbox.sana.vn.pos.flutter` |
| API | `https://sboxhrm.com` |

## Trạng thái

- [x] FVM Flutter 3.22.3 (`.fvm/`)
- [x] Port màn POS / bán hàng + widgets / models / API từ `flutter_client`
- [x] Compat Flutter 3.22 (`withOpacity`, `onPopInvoked`, Switch `activeColor`, …)
- [x] Release split APK (armeabi-v7a + arm64-v8a)
- [ ] In Sunmi thật (hiện shim no-op — cần adapter `sunmi_printer_plus` 2.x)
- [ ] QA đầy đủ trên máy Android 6 / Sunmi

## Build release (Sunmi)

```powershell
$env:Path = "C:\Users\TH DECOR\flutter\bin;$env:LOCALAPPDATA\Pub\Cache\bin;$env:Path"
$env:GRADLE_USER_HOME = "E:\gradle-home"
cd "E:\SBOX CURSOR\ZKTecoADMS-master\flutter_pos"
.\.fvm\flutter_sdk\bin\flutter.bat build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

APK copy ra root repo:

- `SBOX-POS-Sunmi-armv7-release.apk` (~29.5 MB) — máy 32-bit / nhiều Sunmi cũ
- `SBOX-POS-Sunmi-arm64-release.apk` (~32.4 MB) — máy 64-bit

```powershell
aapt dump badging SBOX-POS-Sunmi-armv7-release.apk | findstr sdkVersion
# Kỳ vọng: sdkVersion:'23'
```

## FVM hàng ngày

```powershell
cd flutter_pos
fvm flutter run
fvm flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

Không dùng Flutter 3.44 hệ thống cho project này — engine 3.44 ép API 24.
