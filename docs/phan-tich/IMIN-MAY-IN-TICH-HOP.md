# Máy in tích hợp iMin (58mm / 80mm): tài liệu và cách đưa vào SBOX POS

Ngày 13/11/2026. Chưa thử trên máy iMin thật.

## 0. Đã làm (13/11/2026, chưa commit) — khác đề xuất ban đầu

- **Không dùng plugin Flutter `imin_printer`.** Khi app mở, plugin tự khởi tạo SDK trên mọi máy:
  - Android ≤ 11: SDK 1.0 chạy luồng nền, quét và xin quyền USB, kể cả trên Sunmi và điện thoại.
  - Thay bằng `android/app/src/main/kotlin/vn/sana/sbox/IminPrinterBridge.kt`: chỉ khởi tạo SDK khi đúng máy iMin và có lệnh in.
- **Thư viện:**
  - SDK 1.0: jar `android/app/libs/iminPrinterSDK-V1.3.2.jar` (BSD-3, lấy từ imin_printer 0.7.5).
  - SDK 2.0: `com.github.iminsoftware:IminPrinterLibrary:V2.0.0.18` (JitPack).
  - Đã thêm `<queries>` cho `com.imin.printerservice` và luật proguard `com.imin.**`.
- **Phía Dart:**
  - Kiểu kết nối mới `PosThermalConnectionType.imin` («Máy in iMin») và hãng `PosThermalPrinterBrand.imin`.
  - `lib/utils/pos_imin_printer.dart` gồm kênh gọi, khổ giấy, mã trạng thái.
  - `PosPrinterTransport._sendImin` gửi nguyên ESC/POS. ESC p được gỡ ra, két mở bằng API iMin.
- **Tự nhận máy in:** `PosPrinterAutoDetect` thêm «Máy in iMin (máy này)» làm máy hóa đơn.
  - Máy in trong của đời SDK 1.0 cũng hiện như thiết bị USB, với các VID:PID 0519:2013/2015, 0483:7540, 28E9:028D, 38E9:128D/128E. Trên máy iMin, các mã này được bỏ qua để không thêm trùng.
- **API:** thêm `PosPrinterConnectionType.Imin = 4`, xử lý như Sunmi (máy nội bộ của từng thiết bị). Chưa deploy: đến lúc deploy, đồng bộ máy in iMin lên cloud sẽ bị từ chối, nhưng in trên máy vẫn chạy.
- **Kiểm tra:**
  - `test/pos_imin_printer_test.dart` (11 test) và 140 test máy in cũ đều qua.
  - Build API .NET và APK release flavor hrm (arm64) đều qua.
- `flutter_pos` (Android 6) không đổi.

## 1. Kết luận nhanh

- **iMin có tài liệu chính thức** cho máy in tích hợp, gồm hai thế hệ SDK và một plugin Flutter chính hãng `imin_printer` trên pub.dev (nhà phát hành đã xác minh imin.sg).
- SBOX **đã có sẵn một phần**: app chính nhận ra máy iMin và hướng dẫn người dùng in qua cổng USB nội bộ. Máy SPI (M2-202/203/Pro) và máy đời Android 12L trở lên (Swan 2, Falcon 2, Swift 2 Pro, Crane 1) thì chưa in được.
- Đề xuất: thêm kiểu kết nối mới **«Máy in iMin»**. Vẫn dùng nguyên chuỗi byte ESC/POS mà app đang dựng cho máy LAN/USB/Sunmi, gửi qua `imin_printer`. Chỉ làm cho `flutter_client`; giai đoạn đầu chưa đưa vào `flutter_pos` (Android 6).

## 2. Tài liệu iMin

| Mục | SDK 1.0 (`IminPrintUtils`) | SDK 2.0 (`PrinterHelper`, AIDL) |
|---|---|---|
| Android | Theo tài liệu: Android 11 trở xuống | Theo tài liệu: Android 13 trở lên |
| Kết nối máy in | Chọn khi gọi `initPrinter`: USB / SPI / Bluetooth | Dịch vụ AIDL, không chọn kết nối |
| Máy hỗ trợ (theo tài liệu) | USB: D1, D1w, D1 Pro, D4, M2 Max, Swift 1, Falcon 1. SPI: M2-202, M2-203, M2 Pro | Không có danh sách. Máy đời mới chạy Android 13: Swan 2, Falcon 2, Swift 2 Pro, Crane 1 |
| Máy in Bluetooth ảo | «BluetoothPrinter» | «InnerPrinter» |
| Thư viện | jar `iminPrinterSDK-15_V1.3.2` + `libserial_port_imin.so` | `com.github.iminsoftware:IminPrinterLibrary:V2.0.0.18` (JitPack) |

**Plugin `imin_printer`:**
- Bản mới nhất 0.7.5 (15/05/2026). Nên dùng từ 0.7.4 trở lên, vì 0.7.4 sửa lỗi thiếu thư viện Android.
- Yêu cầu Dart ≥ 3.0.6, Flutter ≥ 3.3; minSdk lấy theo app.
- Gộp cả hai SDK. Plugin tự chọn SDK theo `SDK_INT >= 32` (Android 12L trở lên dùng SDK 2.0). Ở SDK 1.0, máy có tên chứa M2-202, M2-203 hoặc M2-Pro dùng SPI; các máy khác dùng USB.
- API có đủ những gì SBOX cần:
  - khởi tạo và trạng thái: `initPrinter`, `getPrinterStatus`, `getSdkVersion`
  - gửi byte thô: `sendRAWData`, `sendRAWDataHexStr`
  - cắt giấy, két tiền: `partialCut`, `fullCut`, `openCashBox`
  - in ảnh và mã: `printSingleBitmap`, `printQrCode`, `printBarCode`
  - khổ giấy: `setPageFormat` (0 = 80mm, 1 = 58mm); `getPrinterPaperType` chỉ có ở SDK 2.0
  - in tem: các hàm `label…`, chỉ có ở SDK 2.0

**Điểm phải biết (đã đối chiếu mã nguồn plugin):**
- `sendRAWData(bytes)` chỉ chạy ở SDK 2.0. Ở SDK 1.0, hàm này không gửi gì mà vẫn trả `true`.
- Máy SDK 1.0 phải đổi byte sang chuỗi hex rồi gọi `sendRAWDataHexStr`.
- Một số hàm chỉ có ở SDK 2.0 (ví dụ `getPrinterPaperType`) sẽ không bao giờ trả về trên máy SDK 1.0. Vì vậy phải rẽ nhánh theo `getSdkVersion()` và bọc timeout mọi lệnh gọi.
- Theo iMin, máy in «tương thích ESC/POS nhưng hơi khác chuẩn». Các lệnh cắt giấy, mở két và bảng mã cần thử trên máy thật.

**Mã trạng thái `getPrinterStatus`:**

| Mã | Ý nghĩa |
|---|---|
| 0 | Bình thường |
| 1 | Chưa kết nối |
| 3 | Mở nắp |
| 4 | Dao cắt kẹt |
| 5 | Quá nhiệt |
| 7 | Hết giấy |
| 8 | Sắp hết giấy |
| -1, 2, 6, 99 | Lỗi |

**Nguồn:**
- https://oss-sg.imin.sg/docs/en/Printer.html
- https://oss-sg.imin.sg/docs/en/PrinterSDK.html
- PDF SDK 2.0: https://imin-sg-resources.oss-ap-southeast-1.aliyuncs.com/docs/demo/iMinPrinterSDK2.0%20Developer%20Documentation.pdf
- https://pub.dev/packages/imin_printer
- https://github.com/iminsoftware/imin_printer (`IminPrinterPlugin.java`, `Utils.java`)
- https://github.com/iminsoftware/PrinterDemo

## 3. So sánh khổ 58mm và 80mm (K58 / K80)

| | K58 | K80 |
|---|---|---|
| Vùng in | 48mm = 384 điểm (iMin ghi 205 DPI) | 72mm = 576 điểm |
| Ký tự/dòng, font A 12×24 | 32 (tự suy, khớp layout Sunmi K58 của SBOX) | 48 (tự suy) |
| `setPageFormat` / `setTextWidth` tối đa | 1 / 384 | 0 / 576 |
| Dao cắt tự động | Không có (máy cầm tay, Swan 2 bản 58mm) | Một số máy: Swan 2 bản 80mm, dock 80mm của Falcon 2 |
| Két tiền | Thường không | Máy để bàn: SDK 1.0 điều khiển qua GPIO, SDK 2.0 dùng `openDrawer` |
| Máy (cần xác nhận lại) | M2 / M2 Pro, Swift 2 Pro, Swan 2 bản 58 | Swan 2 bản 80, Falcon 2 (dock); D4 / Swan 1 nhiều khả năng là 80mm |
| Đọc khổ giấy tự động | SDK 2.0 có `getPrinterPaperType()`, nhưng tài liệu không nói giá trị nào là 58 hay 80 → phải thử trên máy thật | như bên trái |

Tên «K58/K80» chỉ là cách SBOX gọi khổ giấy. Hãng iMin không có dòng máy tên K58/K80.

## 4. SBOX đang in máy tích hợp thế nào

**App chính `flutter_client`:**
- Mọi bản in (hóa đơn, bếp, tem, báo cáo) đều dựng thành chuỗi byte ESC/POS. Chữ tiếng Việt in dạng ảnh raster hoặc UTF-8.
- Chuỗi byte đi qua `PosPrinterTransport.send`, với 4 kiểu kết nối: Bluetooth, LAN, USB, Sunmi.
  - Sunmi: gửi `SunmiPrinter.printEscPos` (plugin `sunmi_printer_plus` ^4.1.0), có thêm đường in gốc trong `PosSunmiNativePrint`.
  - USB: viết bằng Kotlin, tự tìm cổng bulk-out, ưu tiên interface máy in (class 7).
- Khổ giấy lưu trong `paperSize` ('K58' | 'K80'); `paperWidthMm` đổi ra 58 hoặc 80. Layout Sunmi: K58 = 32 ký tự, K80 = 48 ký tự.
- Đã có `PosPrinterTransport.isIminDevice()`: so `brand`/`manufacturer` có chứa «imin» hay không. Màn thêm máy in hiện dòng hướng dẫn «Máy iMin: … chọn kết nối USB … M2-202/203/Pro (SPI) chưa hỗ trợ».
- Tự nhận máy in khi mở POS (`PosPrinterAutoDetect`):
  - Máy Sunmi: tự thêm máy in tích hợp, khổ K80 nếu có dao cắt, K58 nếu là máy cầm tay.
  - Máy in USB: tự thêm với khổ **K80 cố định** → máy iMin 58mm sẽ bị đặt sai khổ.
- «Máy in nhiệt nội bộ» chỉ là tên mặc định đặt cho máy in (`pos_local_printers_screen.dart`), không phải một driver riêng.
- Phía API: enum `PosPrinterConnectionType` = Bluetooth 0, Lan 1, Sunmi 2, Usb 3. Bên app, `pos_store_printer_mapper.dart` đổi mọi chuỗi lạ thành **Bluetooth**.

**App Android 6 `flutter_pos`:**
- Cùng cấu trúc với app chính: `sunmi_printer_plus` ^2.1.3, USB Kotlin riêng, 4 kiểu kết nối, minSdk 23, targetSdk 23, AGP 8.6.
- Chưa có gì về iMin.

## 5. Đề xuất tích hợp

**Bước 1 — sửa nhỏ, chưa cần plugin.** Dành cho máy SDK 1.0 nối USB: D1, D4, M2 Max, Falcon 1, Swift 1.
- Nhãn hãng: lấy VID/PID máy in trong của iMin từ máy thật, thêm vào `usbBrandLabel` (Kotlin) và `PosUsbLabels` để hiện tên «iMin».
- Khổ giấy: trên máy iMin, `PosPrinterAutoDetect` chọn khổ theo model (M2 / Swift = K58) thay vì luôn K80.
- Tự thêm máy: khi `isIminDevice()` đúng, tự tạo máy in hóa đơn giống cách làm với Sunmi.

**Bước 2 — kiểu kết nối `imin` dùng plugin `imin_printer`.** Phủ cả máy SPI và máy Android 12L trở lên.
- Thêm `imin_printer: ^0.7.5`. Nếu gradle báo lỗi kho thì thêm JitPack vào `settings.gradle.kts`.
- Thêm `PosThermalConnectionType.imin` («Máy in iMin»).
- Thêm hàm `_sendImin(bytes)` trong transport:
  - `initPrinter` một lần, rồi đọc `getSdkVersion()`.
  - SDK 2.0: gọi `sendRAWData(bytes)`.
  - SDK 1.0: gọi `sendRAWDataHexStr(hex)`.
  - Trước khi in, đọc `getPrinterStatus` để báo «Hết giấy / Mở nắp».
  - Mọi lệnh gọi bọc timeout.
  - Khóa hàng đợi in: `'imin'`.
- Cắt giấy và mở két: giữ lệnh ESC/POS sẵn có (GS V / ESC p). Nếu máy thật không ăn lệnh thì dùng `partialCut` / `openCashBox`.
- Nhận biết máy: giữ cách so `brand`/`manufacturer` hiện có. Thêm đọc thuộc tính hệ thống `ro.neostra.imin_model` qua kênh Kotlin sẵn có (`Build.MODEL` có thể là mã nội bộ như I22M01 hay I23M02), và thử `getPrinterStatus` làm phương án dự phòng.
- Đồng bộ lên cloud: thêm `Imin = 4` vào enum phía API và vào mapper ở app.
  - Rủi ro: bản app cũ gặp «Imin» sẽ hiểu thành Bluetooth và in hỏng. Nên chỉ lưu kiểu `imin` trên máy (local), hoặc đẩy app mới lên trước rồi mới mở cloud.

**`flutter_pos` (Android 6):** chưa thêm plugin.
- Lý do: plugin kéo theo Glide 4.16, RxJava/RxAndroid, multidex và JitPack, dễ xung đột build với AGP 8.6 / minSdk 23 và làm APK OTA nặng thêm.
- iMin cũng không ghi máy nào chạy Android 6. Máy iMin đời cũ cứ dùng đường USB (bước 1) nếu cần.

## 6. File cần sửa

| File | Việc |
|---|---|
| `flutter_client/pubspec.yaml` | Thêm `imin_printer` |
| `flutter_client/android/settings.gradle.kts` | JitPack (nếu cần) |
| `flutter_client/lib/utils/pos_thermal_printer_settings.dart` | Thêm enum `imin`, `availableOnThisDevice(includeImin)`, chế độ chữ mặc định khi in iMin |
| `flutter_client/lib/utils/pos_printer_transport.dart` | `_portKey`, `_sendNow`, `_sendImin`, đọc trạng thái, cải thiện `isIminDevice` |
| `flutter_client/lib/utils/pos_printer_auto_detect.dart` | Tự thêm máy in iMin, đặt khổ theo model |
| `flutter_client/lib/screens/pos/pos_local_printers_screen.dart` | Hiện lựa chọn «Máy in iMin», thay dòng hướng dẫn USB hiện tại |
| `flutter_client/lib/utils/pos_store_printer_mapper.dart` + `src/ZKTecoADMS.Domain/Enums/PosPrintEnums.cs` | Thêm `Imin` (nếu đồng bộ cloud) |
| `flutter_client/android/app/src/main/kotlin/vn/sana/sbox/UsbEscPosPrinter.kt`, `lib/utils/pos_usb_labels.dart` | Nhãn hãng iMin theo VID (bước 1) |
| `flutter_client/android/app/src/main/kotlin/vn/sana/sbox/MainActivity.kt` (hoặc `PosPrinterHardware.kt`) | Đọc `ro.neostra.imin_model` |
| Các nhánh `switch` trên `PosThermalConnectionType` (orchestrator, readiness, peripheral, agent service…) | Thêm nhánh `imin`; chạy `flutter analyze` để tìm hết |
| `tool/i18n/*` | Chuỗi mới phải chạy quy trình dịch ko/ja/zh |

## 7. Rủi ro

- **Chưa thử trên máy thật:**
  - giá trị `brand`/`manufacturer` thật của máy iMin
  - VID/PID máy in USB trong
  - giá trị `getPrinterPaperType`
  - bảng mã tiếng Việt khi in UTF-8 (nên mặc định in ảnh như với máy LAN)
- **Lỗi plugin:**
  - `sendRAWData` không gửi gì trên SDK 1.0 mà vẫn trả `true`
  - một số hàm chỉ có ở SDK 2.0 bị treo trên máy SDK 1.0
  - bản ≤ 0.6.17 treo `initPrinter`
- **Xung đột build:** Glide / Rx / multidex với các plugin hiện có. Cần build thử APK release và kiểm tra kích thước.
- **Hai đường in cùng một máy in:** máy D4 nếu đã cấu hình USB mà lại thêm kiểu `imin` thì hai đường cùng ghi vào một máy in. Cần gộp hoặc cảnh báo (giống cách đang giữ chỗ máy in hóa đơn).

## 8. Thử khi không có máy iMin

1. **Kiểm tra byte:** dựng hóa đơn K58 (384 điểm) và K80 (576 điểm) rồi gửi ra `fake_printer.py` (cổng 9100 → ảnh PNG), xem đúng khổ chưa. Đường này đã dùng với C20.
2. **Unit test:** giả lập `MethodChannel('imin_printer')`, trả `getSdkVersion` lần lượt là "1.0.0" và "2.0.0", rồi kiểm tra:
   - SDK 1.0 gọi `sendRAWDataHexStr` với chuỗi hex đúng
   - SDK 2.0 gọi `sendRAWData`
   - timeout và mã trạng thái 7 / 3 hiện đúng thông báo
3. **Giả lập Android:** build có plugin, kiểm tra app không crash khi `initPrinter` lỗi trên máy không phải iMin. Không được tự chọn kiểu `imin` trên máy khác.
4. **Máy thật:** mượn hoặc thuê một máy SDK 1.0 (ví dụ D4 hoặc M2) và một máy SDK 2.0 (Swan 2 hoặc Falcon 2) từ nhà phân phối. Cài song song gói `.qa`, chạy bản in thử và test bán hàng.
