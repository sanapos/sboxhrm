# APK A6 (SBOX POS) báo «lỗi phân tích cú pháp gói» trên T1 — kết quả điều tra (2026-10-17)

## File đang phát — KHÔNG hỏng
| Link | Kích thước | Kết quả |
|---|---|---|
| https://sboxpos.com/api/app/pos-android-apk và /downloads/sbox-pos.apk | 46 718 340 B, Content-Type application/vnd.android.package-archive | APK thật |
| https://sboxhrm.com/api/app/pos-android-apk và /downloads/sbox-pos.apk | 46 718 322 B | APK thật |

Cả hai: sbox.sana.vn.pos.flutter 1.0.449 (26474), minSdk 23, targetSdk 23, ABI arm64-v8a + armeabi-v7a,
`apksigner verify` đạt v1 + v2 (khóa Android Debug, SHA-256 ca83bddd…). Bằng `apkBytes` trong release JSON.
Landing / publicsettings / nút trên trang đăng nhập đều trỏ về đúng file này. Không có HTML / trang lỗi.

## Thử trên T1 thật đang cắm ADB (T1-G, Android 6.0.1 = API 23, ABI arm64/armeabi-v7a)
- Đẩy file tải từ máy chủ lên /sdcard rồi mở bằng trình cài hệ thống → hiện màn «cài bản cập nhật», KHÔNG lỗi.
- Mở link bằng Chrome 56 của T1 → **NET::ERR_CERT_AUTHORITY_INVALID** (Chrome cũ không tin Let's Encrypt
  YR1/YR2 → ISRG Root X1). Bấm Nâng cao → Tiếp tục thì tải đủ 46 718 340 B, trùng byte với máy chủ.
  Vì đã có `sbox-pos.apk` cũ (1.0.226, 116 MB, 16/08) trong Download, Chrome lưu file mới thành `sbox-pos (1).apk`.
- Trình cài trong app (PosApkInstaller) dùng PackageInstaller session; chỉ khi session lỗi mới mở `file://`
  trong thư mục cache riêng của app → trình cài hệ thống không đọc được → «lỗi phân tích». Chưa tái hiện được.

## Nghi vấn còn lại
1. Máy T1 của khách chạy Android 5.1 (API 22) → minSdk 23 > máy → Android 5/6 báo đúng «lỗi phân tích cú pháp gói».
   Hạ minSdk xuống 21 khả thi về plugin (mọi plugin ≥ 21, Flutter 3.22.3 cho 21) nhưng chưa có máy 5.1 để thử.
2. Người dùng mở nhầm file / mở khi chưa tải xong.

## Cập nhật: đã tái hiện (người dùng xác nhận T1 lỗi chạy Android 6+)
- Mở `sbox-hrm.apk` (app HRM sbox.sana.vn 1.0.556, **minSdk 24 = Android 7.0**) trên T1 Android 6.0.1 → đúng hộp thoại
  «Lỗi phân tích cú pháp — Đã xảy ra sự cố khi phân tích cú pháp gói»; logcat: `PackageInstaller: Parse error when parsing manifest`.
- Mọi bản build từ flutter_client (flavor hrm `sbox.sana.vn` và pos `sbox.sana.vn.pos`, Flutter 3.44) đều minSdk 24 → không cài được trên T1.
  Flavor cũ `android6` (-a6, minSdk 21) trong fix_build.py đã bị tắt.
- Chỉ app flutter_pos (`sbox.sana.vn.pos.flutter`, minSdk 23) mới chạy được trên T1. Link đúng: https://sboxpos.com/api/app/pos-android-apk
  (hoặc sboxhrm.com cùng đường dẫn tùy server dữ liệu).
- Không build / upload / commit gì: file A6 trên máy chủ không lỗi.
