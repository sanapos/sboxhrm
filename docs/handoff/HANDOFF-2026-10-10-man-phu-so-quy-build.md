# Bàn giao — Build màn hình phụ (T1 / video / tiếng) + sổ quỹ + kho (10/10/2026)

Người nhận: một phiên Claude khác. Trả lời người dùng **bằng tiếng Việt**.
Việc chính: **build và kiểm thử** các commit dưới đây (đặc biệt APK POS cho máy Sunmi). Code đã xong, đã commit.

## 1. Trạng thái

- Nhánh: `fix/tingee-agent-scope-deploy`. Các commit **chưa push** của phiên này (cũ → mới):

| Commit | Nội dung | Cần build |
|---|---|---|
| `97a16727` | Dữ liệu cũ không gán chi nhánh = trụ sở (chấm công thô, hồ sơ nhân sự, báo cáo…) | API + web + app |
| `039ad1a8` | Môi trường test local kho (`tools/local-test/`); sửa công nợ NCC khi hủy phiếu trả NCC | API |
| `78a0d7e0` | Sổ quỹ: Tingee / tên ngân hàng không còn ghi Tiền mặt; số dư quỹ không cộng trùng; báo cáo Sổ quỹ có tồn đầu – cuối kỳ | API + web + app |
| `4d823cb8` | Màn hình phụ: video phát đúng, bố cục theo tỉ lệ màn, QR thanh toán lớn | web + app + **APK POS** |
| `a41e25d8` | Màn hình phụ: Sunmi T1 trình chiếu ảnh thật (Kotlin); tùy chọn «Bật tiếng video» | **APK POS** + web + app |

- Chưa push, chưa deploy, chưa build iOS / APK. **Push / deploy chỉ khi người dùng yêu cầu.**
- Một phiên Claude khác đang sửa file chưa commit trong cùng repo (khách hàng / loyalty / báo giá chăm sóc:
  `pos_customer.dart`, `pos_customers_screen.dart`, `api_service.dart`, `PosCustomersController.cs`,
  `DependencyInjectionExtensions.cs`, `PosQuoteCareBoard.cs`, …). **Không commit hộ, không sửa file của họ.**
  Build / deploy từ **commit sạch** (git worktree tại `a41e25d8`), không build từ thư mục làm việc.

## 2. Việc cần làm

### 2.1 APK POS (flutter_pos) — quan trọng nhất
Hai file Kotlin đã sửa nhưng **chưa biên dịch được** trên máy này (Gradle báo
`java.io.IOException: Unable to establish loopback connection`, cả trong lẫn ngoài sandbox):
- `flutter_pos/android/app/src/main/kotlin/vn/sana/sbox/sbox_pos/SunmiDsCustomerDisplay.kt`
- `flutter_pos/android/app/src/main/kotlin/vn/sana/sbox/sbox_pos/CustomerDisplayHost.kt`

Việc: build APK (local nếu Gradle chạy được, hoặc Codemagic workflow `android-pos-release` / tương đương).
Lỗi biên dịch Kotlin (nếu có) thì sửa trong 2 file trên. Đóng gói / phát hành APK theo `scripts/deploy-pos-apk.ps1`
(chỉ khi người dùng đồng ý; script cần mật khẩu qua biến môi trường — **không** dùng mật khẩu người dùng gửi trong chat,
SSH chỉ bằng khoá `"/c/Users/TH DECOR/.ssh/sbox_deploy_ed25519"`).

Kiểm thử trên máy Sunmi T1 thật (người dùng cắm máy / tự thử):
1. Thiết lập → Màn hình phụ: bật, đích «Sunmi T1», có ≥ 2 ảnh trình chiếu, thời gian đổi 8 giây.
2. Chờ khách: màn phụ đổi ảnh mỗi ~8 giây, ảnh hiện trọn trong khung 1024×600, có dải tên + giá (ảnh hàng hóa).
3. Thêm món → hiện hóa đơn; xóa giỏ → quay lại trình chiếu.
4. `adb logcat -s SunmiDsCustomerDisplay` — mong đợi `SHOW_IMG_WELCOME fileId=…` lặp lại; không có `all … images failed`.

### 2.2 Web + app HRM (flutter_client) và iOS
Như các lần trước: web qua `scripts/deploy-flutter-web-only.ps1 -Target sboxhrm` từ worktree sạch (có render SEO);
iOS qua `scripts/trigger-codemagic-ios.ps1 -Workflow ios-release -Branch fix/tingee-agent-scope-deploy`
(cần push trước). Không in token Codemagic.

### 2.3 API (cho `78a0d7e0`, `039ad1a8`, `97a16727`)
Deploy kiểu cũ: `git archive HEAD:src` → scp → `_deploy_api.sh`, gắn tag rollback trước. Không cần đổi schema DB.

## 3. Đã kiểm thử ở phiên này
- Backend: 660/660 test (`dotnet test -o "$TEMP/sbox-tests-out"`, đặt `SBOX_TEST_PG` từ `appsettings.Development.json`).
- `tools/local-test/cashbook-e2e.js` 24/24, `warehouse-e2e.js` 65/65 (API local cổng 7199, xem `tools/local-test/README.md`).
- Màn phụ web: chụp 1024×600, 1280×800, 1920×1080, 800×1280 — chờ khách (toàn màn), đang bán, chờ QR, đã nhận tiền;
  video phát / chuyển mục; bật tiếng khi trình duyệt chặn → phát tắt tiếng + nút «Chạm để bật tiếng».
- `flutter analyze` sạch lỗi cho các file màn phụ ở cả `flutter_client` và `flutter_pos`.
- **Chưa** chạy trên máy Android / Sunmi thật.

## 4. Việc còn treo — chờ người dùng quyết định (đừng tự làm)
- **Upload video màn phụ thẳng lên Google Drive backup**: thiết kế đã có (API nhận khúc 8MB → phiên upload resumable của
  Drive, thư mục `SBOX-Media/customer-display/<mã cửa hàng>`; phát qua API chuyển tiếp có Range, link có chữ ký).
  Bị hệ thống chặn vì định đọc `rclone.conf` của backup để dùng lại token. Người dùng chọn: (a) cho phép dùng lại token
  rclone (mount chỉ đọc vào container), hoặc (b) tự cấp `MediaDrive:ClientId/ClientSecret/RefreshToken` riêng.
  **Không tự đọc / sao chép bí mật backup.**
- Sửa dữ liệu cũ trên prod: 8 phiếu thu Tingee (222.000đ) và 1 phiếu 1.800.000đ (demopos) đang ghi «Tiền mặt».
- Chức năng hủy phiếu thu nợ khách / trả nợ NCC (hiện không hủy được).
- Các việc treo từ trước: deploy sboxpos, sửa dữ liệu prod đơn online, tự hủy đơn online > 24h, tên pháp nhân cho chính sách, Print Agent trên sboxpos.

## 5. Quy ước (từ người dùng)
- Production DB chỉ đọc. Commit kết thúc bằng `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Không commit rác (`.tmp-*`, apk, log, `docs/shots`, `test/_shots`, `.claude/launch.json`, `tools/local-test/out/`).
- Không tắt server của phiên khác (vd API cổng 7099). API / web local của phiên này: cổng 7199 / 8190.
