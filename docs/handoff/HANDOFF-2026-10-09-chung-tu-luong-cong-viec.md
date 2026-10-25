# Bàn giao — Chứng từ báo giá, mẫu in, lịch sử lương, Công việc đa ngành (09/10/2026)

Người nhận: một phiên Claude khác. Trả lời người dùng **bằng tiếng Việt**.

## 1. Trạng thái nhanh

- Nhánh: `fix/tingee-agent-scope-deploy`. **7 commit chưa push** (cũ → mới):

| Commit | Nội dung |
|---|---|
| `bf7fda01` | Trình chỉnh sửa mẫu in: xem trước đúng ảnh in, thanh định dạng, căn lề, chèn / căn ảnh |
| `4b85070e` | Làm lại 5 mẫu A4 (báo giá, hợp đồng, bàn giao, nghiệm thu, đề nghị TT) + mẫu Word AI |
| `3b0d37a6` | Sửa riêng từng chứng từ / hoá đơn không ảnh hưởng mẫu chung (lịch sử, mẫu riêng, cảnh báo bản cũ) |
| `2d577b3f` | Báo giá: chặn lập chứng từ trên báo giá đã dừng, `{Dong_Email}`, cọc cục bộ theo giá trước VAT |
| `0f75187e` | Lịch sử thiết lập lương không còn mất mức cũ (bảng SalaryProfileRevisions, mặc định «Đổi lương từ ngày» = hôm nay) |
| `72778946` | Công việc đa ngành — server |
| `5f0d3f27` | Công việc đa ngành — app (flutter_client) |

- **Chưa push, chưa deploy, chưa build iOS / APK.** Chỉ push / deploy khi người dùng yêu cầu.
- **Phiên Claude khác đang sửa ~133 file chưa commit** trong cùng repo (máy in POS, kho, serial, ca làm, thông báo…). Không commit hộ, không sửa file của họ. Với file dùng chung (vd `flutter_client/lib/services/api_service.dart`, `src/ZKTecoADMS.Infrastructure/ZKTecoDbContext.cs`, `src/ZKTecoADMS.Api/DependencyInjectionExtensions.cs`) chỉ stage đúng hunk của mình (`git apply --cached` với patch lọc), như đã làm ở các commit trên.
- **Cảnh báo:** thay đổi dở của phiên kia hiện làm **API local lỗi 500 mọi request** (`StorePackageModuleMiddleware`: «Cache entry must specify a value for Size when SizeLimit is set») và file test `src/ZKTecoADMS.Tests/Pos/PosPrintDispatchTests.cs` (chưa track) **lỗi biên dịch** → cả dự án test không build. Nếu deploy từ thư mục làm việc hiện tại sẽ dính lỗi này — deploy phải từ commit sạch, hoặc chờ phiên kia sửa.

## 2. Quy ước bắt buộc (từ người dùng)

- SSH chỉ bằng khoá `"/c/Users/TH DECOR/.ssh/sbox_deploy_ed25519"`; không dùng mật khẩu người dùng đưa; không in token Codemagic / khoá API.
- Production DB: **chỉ đọc**, chỉ kiểm tra schema / đếm (`SET default_transaction_read_only = on;`). Container: `zkteco_postgres`, `zkteco_api`, `zkteco_flutter` trên sboxhrm `103.133.224.176`.
- Đích deploy mặc định: sboxhrm. Deploy web phải chạy render SEO (`render-site-home.py` / `deploy-flutter-web-only.ps1`), bỏ qua là mất trang chủ SEO.
- Commit kết thúc bằng: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Không commit rác: `.tmp-*`, apk, log, `docs/shots`, firmware, `test/_shots` (harness chụp ảnh giữ ở `$TEMP/_shots_keep`, xoá `test/_shots` sau khi dùng).
- Schema DB: không dùng EF migration — thêm file `src/ZKTecoADMS.Infrastructure/SchemaPatches/*.sql` (embedded, chạy khi API khởi động, viết idempotent `IF NOT EXISTS`).

## 3. Việc đã làm (chi tiết để tiếp tục)

### 3.1 Mẫu chứng từ A4 (commit `4b85070e`)
- Nguồn duy nhất: `src/ZKTecoADMS.Api/PrintTemplates/A4/*.html` (embedded). App dùng bản sinh `lib/utils/pos_commercial_templates.g.dart` — **sửa HTML xong chạy** `python scripts/gen_commercial_templates.py` (ghi cho cả flutter_client và flutter_pos).
- Cú pháp mẫu: `<!--IF:Truong-->…<!--ENDIF:Truong-->`, `<!--IFNOT:…-->`, bảng đợt `<!--BEGIN_STAGES-->…<!--END_STAGES-->` (dữ liệu `_Dot_Thanh_Toan`), `<!--NO_ITEMS-->` (không tự chèn bảng hàng).
- Dữ liệu: `Services/PosQuoteDocumentHtml.cs` (`BuildFieldsAsync` / `BuildData`), giờ VN = UtcNow+7.
- Mẫu Word AI: `PosDocxTemplateAiService` (trường mới, `stageRow`, cảnh báo số tiền / chỗ trống chưa gắn), `DocxTemplateEngine` (lặp dòng đợt), in thử với báo giá thật `GET /api/pos/print-templates/docx/{id}/preview?quoteId=`.

### 3.2 Sửa riêng chứng từ (commit `3b0d37a6`, `2d577b3f`)
- `PosQuoteDocument`: `IsCustomWording`, `SourceHash` (phát hiện bản sửa đã cũ), `PrintTemplateId`; bảng `PosQuoteDocumentRevisions`.
- API: `POST /api/pos/quotes/{id}/preview` (`docId`, `templateId`), `PUT …/documents/{docId}/template`, `…/revisions`, `…/revisions/{revId}/restore`. Lời văn lưu qua `OfficePdfConverter.SanitizeHtml`.
- Hoá đơn bán: `PosSaleOrder.PrintTemplateId`, `PrintNote`; `PUT /api/pos/sales/{id}/print-settings`; app có nút «Tùy chọn in» ở danh sách hoá đơn.

### 3.3 Lịch sử lương (commit `0f75187e`)
- Nguyên nhân cũ: lưu mặc định ghi đè hồ sơ; «Đổi lương từ ngày» luôn lỗi trùng tên hồ sơ. Production lúc kiểm tra: 296 NV, 0 NV có >1 phiên bản, 123/298 hồ sơ đã bị ghi đè (không khôi phục được).
- Giờ: bảng `SalaryProfileRevisions` (correction / replaced / cancelled), API `GET /api/benefits/employees/{id}/salary-log`, màn `flutter_client/lib/screens/salary_v2/sl_history.dart`.

### 3.4 Công việc đa ngành (commit `72778946`, `5f0d3f27`)
- **Server**
  - Gói ngành: `Infrastructure/Services/TaskIndustryPacks.cs` — 5 gói ưu tiên `fnb`, `construction` (khoá cũ `interior` tự đổi), `retail`, `service`, `sales` + 6 gói khác.
  - Biểu mẫu tùy biến: `Infrastructure/Services/TaskFormHelper.cs` (kiểu: text, textarea, number, money, select, date, phone, checkbox, photo, signature, rating).
  - API mới: `Api/Controllers/TasksController.MultiIndustry.cs` — workspace / onboard, Google Drive (connect-url, callback, test, disconnect), form, media (upload / list / delete / content có chữ ký), check-in / check-out, time-logs, report (HTML / PDF), dashboard, piece-rates, by-customer, by-related, from-quote.
  - Lưu ảnh: `Api/Services/TaskMediaService.cs` (máy chủ hoặc Drive OAuth `drive.file`, token mã hoá AES-GCM từ `JwtSettings.AccessTokenSecret`, Drive lỗi → lưu máy chủ).
  - Việc định kỳ theo ca: `Api/Services/TaskRecurrenceBackgroundService.cs` (`AssignOnShift` → người có `WorkSchedule` bao trùm giờ tạo).
  - Khoán: duyệt Completed → `PaymentTransaction` Type `Bonus`, Source `task`, Settlement `salary`; mở lại → huỷ nếu chưa có `PayslipId`.
  - Schema: `SchemaPatches/TaskMultiIndustry.sql`.
- **App (chỉ flutter_client — flutter_pos không có module này)**
  - Gọi API riêng `lib/services/work_api.dart` (không đụng `api_service.dart`).
  - Màn: `screens/work/work_setup.dart` (chọn ngành, giao nhanh, thiết lập Drive, bảng điều khiển, khoán), `work_field_sections.dart` (khách hàng, biểu mẫu, ký tên, check-in GPS, ảnh, PDF, đánh giá, nhắc việc), `work_template_editor.dart`.
  - Đã bỏ menu «Giao diện cũ» (file `task_management_screen.dart` vẫn còn vì `main_layout.dart` dùng callback của nó).

## 4. Việc còn lại / gợi ý tiếp

1. **Google Drive cần cấu hình** (người dùng tự làm trên Google Cloud): OAuth Client (Web), bật Drive API, redirect `https://sboxhrm.com/api/tasks/drive/callback`; đặt env server `GoogleDrive__ClientId`, `GoogleDrive__ClientSecret`, `App__PublicBaseUrl=https://sboxhrm.com`. Sau đó thử kết nối thật (chưa từng chạy với Google thật). Ứng dụng OAuth chưa xác minh chỉ cho tối đa 100 tài khoản test — `drive.file` là scope không nhạy cảm nên xác minh nhẹ.
2. **Deploy** (khi được yêu cầu): push nhánh, deploy API + web sboxhrm (nhớ render SEO), build iOS Codemagic / APK. Schema patch tự chạy khi API khởi động. Deploy từ commit sạch vì thư mục làm việc đang có thay đổi hỏng của phiên kia (mục 1).
3. **Chưa bấm thử giao diện thật** cho các màn Công việc / lương / chứng từ: khung trình duyệt ẩn nên app web không vẽ được. Đã có ảnh chụp widget qua harness (`$TEMP/work_shots/*.png`). Nên thử trên điện thoại: check-in GPS, chụp ảnh, ký tên, xuất PDF.
4. Phần chưa làm, có thể làm thêm:
   - Màn khách hàng POS hiển thị việc của khách (API `by-customer` đã có).
   - Chọn mẫu riêng ngay lúc lập chứng từ (hiện chọn sau qua menu).
   - Thông báo đẩy khi gần hạn theo ngành.
5. Dữ liệu không khôi phục: 123 hồ sơ lương bị ghi đè trước đây (chỉ có thể từ backup DB nếu có).

## 5. Cách kiểm tra

- **Test server**: `cd src && dotnet test ZKTecoADMS.Tests -c Release`. Hiện bị chặn bởi file lỗi của phiên kia → chạy từ bản sao:
  - Sao chép `src/ZKTecoADMS.Tests` ra thư mục tạm, bỏ `Pos/PosPrintDispatchTests.cs`, đổi `ProjectReference` sang đường dẫn tuyệt đối.
  - Đặt `SBOX_TEST_PG` = chuỗi kết nối trong `src/ZKTecoADMS.Api/appsettings.Development.json`.
  - Các test mới: `TaskMultiIndustryTests`, `PosQuoteDocumentTests`, `DocxTemplateEngineTests`.
- **Test Flutter**: `"/c/Users/TH DECOR/flutter/bin/flutter.bat" test test/work_multi_industry_test.dart test/salary_history_test.dart test/pos_commercial_documents_test.dart`.
- **API local**:
  - Cấu hình `api-local` (cổng 7099, DB `sbox_uidemo`) đang lỗi do phiên kia.
  - Đã dùng bản sạch: `git archive HEAD src | tar -x` vào thư mục tạm + `appsettings.Development.json`, chạy `dotnet run --urls http://localhost:7098` (cấu hình `api-clean` trong `E:\SBOX CURSOR\.claude\launch.json`, script trong scratchpad của phiên trước — tạo lại nếu mất).
  - Tài khoản demo đọc từ file thông tin đăng nhập test của DB demo (không in ra).
  - Kịch bản E2E đã dùng: báo giá 63 bước, lương 15 bước, Công việc 34 bước — đều đạt.
