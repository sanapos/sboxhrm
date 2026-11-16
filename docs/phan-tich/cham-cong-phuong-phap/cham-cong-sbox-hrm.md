# Phân tích – Giới thiệu: Các phương pháp chấm công của SBOX HRM

> Tài liệu rà soát trực tiếp từ mã nguồn kho `ZKTecoADMS-master`, chốt ngày **16/11/2026**.
> Mỗi khẳng định đều dẫn `file:dòng`. Chỗ nào là suy đoán / chưa kiểm chứng được bằng code đều ghi rõ **(suy đoán)**.
> Tên tính năng dùng đúng cách sản phẩm đang gọi trong app (đối chiếu `flutter_client/lib/utils/landing_usage_guide.dart`
> và danh mục quyền `src/ZKTecoADMS.Application/Authorization/FeatureModuleCatalog.cs:84-96`).

---

## 0. Bức tranh tổng thể trước khi đi vào từng phương pháp

SBOX HRM chỉ có **một bảng dữ liệu chấm công gốc duy nhất**: `AttendanceLogs`
(entity `Attendance` — `src/ZKTecoADMS.Domain/Entities/Attendance.cs:7-38`), trong app gọi là
**«Chấm công thô»** (`FeatureModuleCatalog.cs:85` — *«Dữ liệu chấm từ máy và điện thoại»*).

Mọi phương pháp chấm công đều phải quy về một dòng trong bảng này mới được tính công:

```
[Máy ZKTeco]        ──ADMS push──┐
[Gateway WiFi ESP32]─────────────┤
[Điện thoại NV]  → MobileAttendanceRecords ──(khi được duyệt)──┤→  AttendanceLogs  →  Bộ tính công/lương
[Chấm công thủ công]─────────────┤                              (chấm công thô)
[Phiếu sửa/bổ sung công đã duyệt]┘
```

Mỗi dòng chấm công thô chỉ giữ 7 thông tin nghiệp vụ (`Attendance.cs:9-32`):
thiết bị (`DeviceId`), nhân sự trên máy (`EmployeeId` → `DeviceUsers`), `PIN`,
**kiểu xác thực** (`VerifyMode`), **vào/ra** (`AttendanceState`), **thời điểm** (`AttendanceTime`),
`WorkCode`, `Note`, và liên kết `MobileAttendanceRecordId` khi lượt chấm đến từ điện thoại.

Hệ quả quan trọng (sẽ nhắc lại ở mục 7 và 10): **bảng chấm công thô không có cột «phương pháp chấm công»**.
Nguồn GPS / Wi-Fi / chấm hộ / bổ sung được suy ra từ *tên thiết bị + VerifyMode + Note + MobileAttendanceRecordId*.

---

## 1. Máy chấm công vân tay / khuôn mặt kết nối realtime (ADMS – ZKTeco)

### Cách hoạt động

Máy ZKTeco đời mới có menu «Máy chủ đám mây» tự gọi về server theo giao thức ADMS/PUSH.
Server mở đúng 5 đầu vào tại `src/ZKTecoADMS.Api/Controllers/IClockController.cs`:

| Đầu vào | Dòng | Việc |
|---|---|---|
| `GET /iclock/cdata?SN=…&options=all` | `:23` | máy đăng ký + nhận cấu hình |
| `POST /iclock/cdata?SN=…&table=ATTLOG` | `:61` | **máy đẩy lượt chấm lên server** |
| `GET /iclock/getrequest?SN=…` | `:84` | máy hỏi lệnh (tải NV, đăng ký vân tay, mở cửa…) |
| `GET /iclock/ping?SN=…` | `:107` | nhịp tim của dòng SenseFace/ZAM |
| `POST /iclock/devicecmd?SN=…` | `:121` | máy báo kết quả thực hiện lệnh |

Cấu hình trả cho máy đặt chế độ **thời gian thực**: `Realtime=1`, `TransInterval=1`, `Delay=5`,
`TimeZone=7` (`src/ZKTecoADMS.Application/Constants/PushDeviceConfigBuilder.cs:42-48`).
Nghĩa là mỗi lần nhân viên áp tay / nhìn camera, máy POST ngay lượt chấm đó lên server, không chờ đến giờ hẹn.
Máy chưa gắn cửa hàng vẫn nhận được cấu hình cơ bản để xác nhận đã kết nối
(`src/ZKTecoADMS.Application/Queries/IClock/CDataGet/CDataGetHandler.cs:48-64`).

Thân bản tin ATTLOG là văn bản tab-separated
`PIN ⇥ giờ chấm ⇥ trạng thái ⇥ kiểu xác thực ⇥ WorkCode ⇥ … `
(`src/ZKTecoADMS.Application/Commands/IClock/CDataPost/Strategy/PostAttendancesStrategy.cs:13`,
chỉ số trường tại `src/ZKTecoADMS.Infrastructure/Services/DeviceOperations/AttendanceOperationService.cs:18-27`).
Bộ phân tích còn đỡ được firmware PUSH ghi cách nhau bằng dấu cách thay vì tab
(`AttendanceOperationService.cs:143-169`).

Xử lý sau khi nhận (`PostAttendancesStrategy.cs:37-180`):

1. Chống trùng 2 lớp: trùng trong cùng lô và trùng với DB theo `(DeviceId, PIN, AttendanceTime)`
   (`AttendanceOperationService.cs:124-138`, `:194-200`).
2. Lưu vào chấm công thô (`PostAttendancesStrategy.cs:76`).
3. Tách lượt quẹt của **hội viên gym** (PIN dải `9xxxxxxx`) ra khỏi công nhân viên (`:80-104`).
4. Tạo phiếu phạt đi trễ / về sớm / quên chấm (`:109`, xem mục 8.4).
5. **Đẩy realtime lên app** cho các lượt chấm trong **15 phút** gần nhất, tối đa 5 thông báo/lô
   (`:17-18`, `:117-122`, `:164`) — cố ý chặn «bão thông báo» khi máy upload log cũ hàng loạt.

### Đẩy lên app bằng SignalR

`AttendanceNotificationService` bắn sự kiện `NewAttendance` qua hub và lưu kèm bản ghi thông báo + FCM
(`src/ZKTecoADMS.Api/Services/AttendanceNotificationService.cs:473`, `:492-506`, `:516`).
Payload gồm tên máy, PIN, mã/tên NV, giờ chấm, `AttendanceState`, `VerifyMode` (`:451-465`).

Người nhận được tính riêng cho từng lượt chấm (`:147-176`):

- chính nhân viên đó (nếu hồ sơ đã gắn tài khoản),
- **quản lý theo phòng ban, lên 2 cấp** (`:161-163`),
- **quản lý trực tiếp theo chuỗi `DirectManagerEmployeeId`, lên 2 cấp** (`:170-172`),
- toàn bộ tài khoản giám sát của cửa hàng (`:107`),
- trừ ai đã tắt nhóm thông báo «attendance» (`:176`).

Lượt chấm cũ hơn **24 giờ** bị loại khỏi thông báo realtime (`:39-49`, `:86`).
Phía app: `flutter_client/lib/services/signalr_service.dart:219` lắng nghe `NewAttendance`,
`flutter_client/lib/screens/main_layout.dart:1482-1523` hiện popup nổi (bản máy tính) và tự làm mới màn chấm công;
nhóm SignalR được khóa theo cửa hàng/người dùng, chỉ `SuperAdmin` được vào nhóm cửa hàng khác
(`src/ZKTecoADMS.Api/Hubs/AttendanceHub.cs:141-186`).

### Kiểu xác thực máy ghi nhận

`VerifyModes` (`src/ZKTecoADMS.Domain/Enums/VerifyModes.cs`): `Password=0`, `Finger=1`, `Badge=2`, `PIN=3`,
các tổ hợp `4–9`, `Face=15`, và `Manual=100` dành cho nhập tay (`:71`).
Bảng quy đổi mã từ máy ở `AttendanceOperationService.cs:337-354`.

Trạng thái vào/ra: máy gửi `0=vào, 1=ra, 2–5=Break/Meal`; server **gộp 2–5 thành CheckIn**
(`AttendanceOperationService.cs:317-331`) để không làm trống tổng hợp theo ca.

### Cần thiết bị / điều kiện gì

- Máy ZKTeco có ADMS (menu Máy chủ đám mây) + internet; nhập **số seri** vào SBOX
  (`landing_usage_guide.dart:902-920`).
- Nhân viên phải được **tải xuống máy** và đăng ký vân tay/khuôn mặt tại chỗ; mã NV trên máy phải trùng mã trong hồ sơ
  (`landing_usage_guide.dart:930-942`, `:787`). PIN chưa gắn hồ sơ → lượt chấm **không vào bảng công**
  (thẻ «Chưa gắn nhân viên», `flutter_client/lib/screens/attendance_screen.dart:2185-2193`).
- Quản lý khuôn mặt/vân tay từ server: các lệnh `EnrollFingerprint`, `EnrollFace`, `PushFingerprint`, `PushFace`,
  `PushUserPic`, `SyncFaces`… (`src/ZKTecoADMS.Domain/Enums/DeviceCommandTypes.cs`),
  đồng bộ/sao chép sinh trắc giữa các máy ở `src/ZKTecoADMS.Api/Controllers/BiometricController.cs:141`, `:274`.

### Bật/tắt ở đâu

Thiết lập SBOX › Nhân sự & chấm công › **Máy chấm công** (thêm thiết bị theo seri);
Chấm công › **Nhân sự chấm công** (tải NV xuống máy) — `landing_usage_guide.dart:909`, `:930`.
Quyền: module `Device`, `DeviceUser` (`FeatureModuleCatalog.cs:86`).

### Dữ liệu lưu ra sao

Một dòng `AttendanceLogs` với `DeviceId` = máy thật, `VerifyMode` = vân tay/khuôn mặt/thẻ/mật khẩu,
`AttendanceState` = vào/ra, `AttendanceTime` = **giờ tường của máy** (Kind=Unspecified, coi như giờ VN —
xem ghi chú `PostAttendancesStrategy.cs:20-21`).

### Ưu điểm

- Chính xác nhất về danh tính: sinh trắc đối sánh **trên máy chuyên dụng**, nhân viên không cần điện thoại.
- Realtime thật (`Realtime=1`), không phụ thuộc app NV.
- Có thể lấy lại log cũ khi mất mạng: lệnh `SyncAttendances` + `ATTLOGStamp=0`
  (`CDataGetHandler.cs:123-132`, `PostAttendancesStrategy.cs:182-203`).
- Chạy song song với chấm công Mobile trong cùng cửa hàng (`landing_usage_guide.dart:981`).

### Hạn chế thực tế

- Cần đầu tư máy + đặt tại điểm làm việc; nhân viên đi hiện trường không dùng được.
- Mã PIN/mã NV lệch nhau là mất công — lỗi vận hành phổ biến nhất, phải tự rà thẻ «Chưa gắn nhân viên».
- Máy gửi log cũ hàng loạt sẽ **không** sinh thông báo (quá 15 phút / 24 giờ) — đúng thiết kế nhưng dễ bị hiểu là «mất chấm công».
- Giờ lấy theo đồng hồ của máy; lệch giờ máy → lệch công (server có gửi `SyncTime=1`,
  `PushDeviceConfigBuilder.cs:53`, nhưng việc máy có đồng bộ hay không phụ thuộc firmware — **(suy đoán)**).

### 1b. Gateway WiFi cho máy ZKTeco đời cũ (chỉ có LAN 4370)

Máy cũ không có ADMS: dùng mạch **ESP32-C3** làm cầu nối, đọc máy qua TCP 4370 rồi đẩy lên `/iclock/*`
đúng như một máy ADMS thật, **không sửa gì ở server**
(`firmware/esp32c3-zk-gateway/README.md:1-16`; cấu hình qua Bluetooth trong app, `landing_usage_guide.dart:949-966`).

Khác biệt cần nói rõ với khách: gateway **quét bản ghi mới theo chu kỳ**, mặc định
`attlog_interval_s = 30` giây và hỏi lệnh mỗi `poll_interval_s = 10` giây
(`firmware/esp32c3-zk-gateway/main/app_config.c:29-30`, `main/gateway.c:1008-1013`)
→ là *gần* realtime, trễ tới ~30 giây, không phải push tức thì.
Lần đầu gateway chỉ lấy chấm công 30 ngày gần nhất (`landing_usage_guide.dart:962`).
Mỗi máy chấm công chỉ gắn một mạch; WiFi phải 2.4GHz (`landing_usage_guide.dart:962`).

---

## 2. Chấm công bằng điện thoại nhân viên («Chấm công Mobile»)

Tên trong sản phẩm: **«Chấm công Mobile»** — *«Chấm công bằng điện thoại: khuôn mặt, GPS, WiFi, ảnh hiện trường»*
(`FeatureModuleCatalog.cs:87`). Toàn bộ API ở `src/ZKTecoADMS.Api/Controllers/MobileAttendanceController.cs`
(`[Route("api/mobile-attendance")]`, `:59`).

Điểm thiết kế cốt lõi: **lượt chấm Mobile vào bảng riêng `MobileAttendanceRecords` trước**
(`src/ZKTecoADMS.Domain/Entities/MobileAttendanceRecord.cs`), chỉ khi `auto_approved` / `approved`
mới được ghi sang chấm công thô (`MobileAttendanceController.cs:6757-6787`, `:7960-7978`).

### 2.1. Đăng ký thiết bị + khuôn mặt (một lần, phải được duyệt)

`POST /api/mobile-attendance/register-device` (`MobileAttendanceController.cs:2177-2187`):

- tối đa **5 ảnh** khuôn mặt (`:2203`), chỉ nhận JPEG/PNG thật (kiểm magic bytes, `:2415-2418`);
- nhân viên **phải chọn ít nhất 1 vị trí/chi nhánh** được chấm (`LocationEmployees.cs:210-216`);
- **mỗi tài khoản chỉ 1 thiết bị**: đã có máy thì trả 409 kèm hướng dẫn «Gửi yêu cầu đổi máy»
  (`:2262-2331`, thông điệp tại `:2304`);
- **một máy không dùng cho 2 nhân viên** (`:2340-2355`);
- mặc định tạo ra bản ghi **chờ duyệt** (`IsAuthorized = autoApprove`, `:2582`), trừ khi cửa hàng bật
  «Tự duyệt máy mới» (`MobileAttendanceSetting.AutoApproveNewDevices`, mặc định **tắt** —
  `src/ZKTecoADMS.Domain/Entities/MobileAttendanceSetting.cs:32-33`; đọc tại `:2542`);
- gửi thông báo `ApprovalRequired` cho quản lý (`:2665-2682`).

Quản lý duyệt bằng `POST approve-device/{id}` (`:3092`) hoặc cấp quyền thẳng `POST devices` (`:1722`).
Màn hình: Thiết lập SBOX › Nhân sự & chấm công › Chấm công Mobile › **«Thiết bị được cấp quyền»**
(`flutter_client/lib/screens/mobile_attendance_settings_screen.dart:1659-1662`), tab yêu cầu đổi máy ở `:1759`.

### 2.2. Nhận diện khuôn mặt trên điện thoại

Luồng trên máy nhân viên (`flutter_client/lib/widgets/face_verification_camera.dart`):

1. Google ML Kit phát hiện mặt, yêu cầu đủ lớn/ổn định.
2. **Thách thức chớp mắt (active liveness)**: thấy mắt mở → mắt nhắm → mắt mở lại mới qua,
   trong vòng ~6 giây (`:104-111`, `:238-283`). Sau khi qua phải giữ mắt mở suốt phần đếm ổn định (`:285-290`).
3. Đối sánh **ngay trên máy**: TFLite (FaceNet/MobileFaceNet) → nếu khởi tạo lỗi thì fallback
   «MLKit signature» với ngưỡng thấp hơn 5 điểm nhưng không dưới 55 (`:402`), gửi kèm
   `clientFaceEngine = 'tflite' | 'mlkit'` (`:527`, `:413`).
4. Nếu máy không chạy được bộ so sánh nào → gửi ảnh cho server xử lý (`matchScore = -1`, `:456-462`).

Phía server (`MobileAttendanceController.cs:5695-6410`) **không tin suông điểm của máy**:

- phải có bộ ảnh đăng ký hợp lệ, không có → **chặn thẳng**:
  *«Nhân viên chưa đăng ký khuôn mặt…»* (`:5719-5748`, `:6398-6407`);
- **cổng chống ảnh giả cứng**: bật `EnableLivenessDetection` (mặc định bật,
  `MobileAttendanceSetting.cs:18`) mà client không báo đã chớp mắt → **từ chối bất kể điểm khớp**
  (`:5864-5897`);
- «đường nhanh» tin điểm của máy chỉ khi: đã qua liveness **và** có ảnh **và**
  `clientFaceEngine ∈ {tflite, mlkit}` **và** điểm ≥ ngưỡng (`:5776-5781`, `:5900-5944`);
- ngược lại server tự so: ONNX embedding trong bộ nhớ → ONNX theo file → bộ so sánh gradient
  (`:5947-6035`, `:6087-6186`). Ngưỡng: ONNX dùng đúng mức cài đặt, gradient bị nâng sàn lên **55**
  vì không phân biệt được danh tính (`:6213-6273`);
- **chống ảnh giả thụ động**: model `FaceAntiSpoofService`, xác suất «người thật» < 0.4 là từ chối
  dù điểm khớp đã đạt (`:6278-6301`);
- ngưỡng khớp: `MinFaceMatchScore` (UI 50–99, mặc định entity 80 —
  `MobileAttendanceSetting.cs:27`, thanh trượt `mobile_attendance_settings_screen.dart:579-586`).
  Lưu ý: nếu cửa hàng **chưa có dòng cài đặt**, mã dùng mặc định **55** (`:5754`), tức dễ hơn giá trị 80 của entity.
  Chấm ngoài công ty được **hạ 10 điểm**, không dưới 50 (`:5755-5758`), và **bỏ qua** anti-spoof thụ động (`:6284`).

Cache embedding ảnh đăng ký 30 phút để không đọc lại kho ảnh mỗi lượt chấm (`:8521-8546`).

### 2.3. Định vị GPS

- App lấy vị trí bằng `Geolocator` (độ chính xác `high`), tự xin quyền, báo lỗi rõ khi dịch vụ vị trí tắt
  (`flutter_client/lib/utils/platform_geolocation_stub.dart:60-95`).
- Trước khi bấm gửi, app **làm mới lại GPS và Wi-Fi** để tránh trường hợp mở màn ở công ty rồi về nhà mới bấm
  (`flutter_client/lib/screens/mobile_attendance_screen.dart:879-882`, `:1252`).
- **Server tự tính khoảng cách**, không tin client nói «tôi đang trong vùng»:
  công thức Haversine (bán kính Trái Đất 6.371.000 m — `:8459-8477`) tới từng vị trí đã khai báo,
  lấy vị trí gần nhất (`:5492-5537`);
  bán kính riêng từng vị trí (`MobileWorkLocation.Radius`, mặc định 100 m —
  `src/ZKTecoADMS.Domain/Entities/MobileWorkLocation.cs:28`), thiếu thì lấy
  `GpsRadiusMeters` của cửa hàng (mặc định 100 m, UI 30–1000 m —
  `MobileAttendanceSetting.cs:26`, `mobile_attendance_settings_screen.dart:610-617`).
- Danh sách vị trí được **giới hạn theo nhân viên**: có phân công thì chỉ các vị trí được gán, không có thì toàn bộ
  vị trí đang bật của cửa hàng (`MobileAttendanceController.LocationEmployees.cs:190-208`).
- `GpsAccuracy` do máy báo được lưu lại và dùng để chấm điểm rủi ro (`MobileAttendanceRecord.cs:95`, mục 2.6).

### 2.4. Nhận diện Wi-Fi của cửa hàng / văn phòng

Mỗi vị trí khai báo `WifiSsid`, `WifiBssid` (MAC router, hỗ trợ **nhiều MAC** cho mesh) và `AllowedIpRange`
(`MobileWorkLocation.cs:33-42`; hàm so khớp nhiều BSSID `MobileAttendanceController.cs:118`).
App đọc BSSID/SSID bằng `NetworkInfo` sau khi có quyền vị trí; BSSID rỗng hoặc `02:00:00:00:00:00`
coi như không đọc được (`mobile_attendance_screen.dart:1509-1541`), và có nút lấy MAC router ngay trong
màn khai báo vị trí (`mobile_attendance_settings_screen.dart:1433-1451`).

Xác thực **hoàn toàn ở server** (comment trong code ghi rõ *«never trust client claims»*,
`MobileAttendanceController.cs:5543`), theo 3 cách, hợp lệ 1 trong 3 là đạt:

1. **BSSID** khớp (`:5567-5585`);
2. **SSID** khớp (`:5588-5606`);
3. **IP** của client nằm trong `AllowedIpRange` — đường dự phòng cho bản web vì trình duyệt không đọc được BSSID
   (`:5612-5645`).

Có endpoint riêng `GET check-wifi` để app hiện trạng thái trước khi chấm, kèm thông điệp chẩn đoán
(`:4678`, thông điệp `:4967-4976`).

### 2.5. Xác thực thiết bị (khóa theo máy đã đăng ký)

Mỗi lượt chấm phải kèm `DeviceId`; server kiểm tra tuần tự (`MobileAttendanceController.cs:5071-5195`):

| Kiểm tra | Dòng | Thông điệp khi sai |
|---|---|---|
| có `DeviceId` | `:5074` | *«Thiếu thông tin thiết bị. Vui lòng đăng ký thiết bị trước.»* |
| máy còn hiệu lực trong cửa hàng | `:5093-5120` | *«Thiết bị này chưa được đăng ký hoặc đã bị thay thế…»* |
| máy thuộc đúng nhân viên đang chấm | `:5138-5153` | *«Thiết bị này đã được đăng ký cho nhân viên khác.»* |
| máy đã được duyệt (`IsAuthorized`) | `:5168-5177` | *«Thiết bị chưa được duyệt hoặc đã bị thu hồi…»* |
| quyền chấm đi đường | `:5183-5192` | *«Thiết bị chưa được cấp quyền chấm công đi đường…»* |

Cờ cấp theo từng máy: `CanUseFaceId`, `CanUseGps`, `AllowOutsideCheckIn`, `AllowTravelCheckIn`,
`RequirePhotoProof`, `RequireOutsideReason` (`src/ZKTecoADMS.Domain/Entities/AuthorizedMobileDevice.cs:38-72`),
bật/tắt qua các endpoint `PATCH devices/{id}/…` (`:1969`, `:2009`, `:2053`) và
`POST outside-reason-devices` (`MobileAttendanceController.ApprovalV2.cs:403`).

**Đổi máy** phải qua phiếu: `POST request-device-change` (`:3403`) → quản lý duyệt
`POST approve-device-change/{id}` (`:4080`); khi duyệt thì **máy cũ + dữ liệu mặt cũ bị xóa**, máy mới được đăng ký
(`src/ZKTecoADMS.Domain/Entities/DeviceChangeRequest.cs:6-9`).

Giới hạn cần nói thẳng: `DeviceId` do **chính app sinh ra** từ `androidInfo.id` /
`identifierForVendor` (web: hash user-agent) rồi lưu `SharedPreferences`
(`flutter_client/lib/utils/mobile_device_id.dart:13-50`). Nó **không phải chứng thư thiết bị**:
cài lại app / xóa dữ liệu app → mã đổi → nhân viên phải xin đổi máy; và một client bị sửa đổi có thể gửi mã tùy ý.

### 2.6. Chấm ngoài công ty, ảnh hiện trường, điểm rủi ro

Server coi là «tại công ty» khi **trong bán kính GPS hoặc khớp Wi-Fi** (`atCompany`, `:6536`).
Nếu không:

- máy phải có cờ `AllowOutsideCheckIn` (hoặc đang chấm đi đường) mới được bỏ qua điều kiện vùng (`:5660-5661`);
- bắt **ảnh hiện trường** khi cửa hàng/máy bật `RequirePhotoProof` — thiếu ảnh là **từ chối** lượt chấm, và nếu
  lưu ảnh thất bại thì **xóa luôn bản ghi vừa tạo** (`:6535-6545`, `:6706-6745`);
- bắt **lý do** nếu máy bật `RequireOutsideReason` (`:6551-6555`, mã lỗi `OUTSIDE_REASON_REQUIRED`);
- **chấm điểm rủi ro 0–100** (`src/ZKTecoADMS.Infrastructure/Services/MobilePunchRiskScorer.cs:45-98`):

| Dấu hiệu | Điểm cộng |
|---|---|
| không xác định được GPS | +50 |
| ≤ `TrustedMaxDistanceMeters` (mặc định 300 m) | +5 |
| vượt bán kính ≤ 1 km / ≤ 5 km / > 5 km | +25 / +40 / +55 |
| sai số GPS > 50 m / > 100 m | +7 / +15 |
| không xác thực khuôn mặt | +10 |
| điểm khớp mặt < `TrustedMinFaceScore` (mặc định 85) | +15 |
| không qua kiểm tra người thật | +10 |
| không có ảnh hiện trường / không có lý do | +5 / +3 |
| lệch giờ ca > 30 phút / > 90 phút | +5 / +15 |
| đã chấm ngoài vị trí ≥ 15 lần trong tháng | +10 |

Mức: `trusted` (≤20 điểm **và** còn trong 300 m), `review` (≤45), `high` (còn lại) — `:94-96`.
Dữ liệu vào gồm cả số lần chấm ngoài trong tháng và độ lệch so với ca trong lịch làm việc
(`MobileAttendanceController.ApprovalV2.cs:83-115`, `:54-81`).

Trạng thái lượt chấm được quyết ngay lúc chấm (`MobileAttendanceController.cs:6556-6569`):

- **ngoài công ty** → `auto_approved` nếu `trusted` + cửa hàng bật `AutoApproveTrusted` (mặc định bật)
  và **không phải chấm đi đường**, ngược lại `pending`
  (`MobilePunchRiskScorer.cs:101-102`);
- **tại công ty** → `auto_approved` nếu người chấm là Admin, hoặc theo cài đặt
  «Tự duyệt khi chấm tại công ty» (`AutoApproveInRange`, mặc định bật);
- `pending` → gửi thông báo `ApprovalRequired` cho người duyệt (`:6805-6880`).

Ảnh bằng chứng tự xóa theo `EvidenceRetentionDays` (mặc định 30 ngày, `MobileAttendanceSetting.cs:57`);
lượt chấm tại công ty được tự duyệt thì **xóa ảnh hiện trường ngay** (`:6747-6749`), còn
ảnh khuôn mặt lúc chấm **không được lưu** (`persistPunchFaceImage = false`, `:6667-6668`) trừ đường
so sánh phía server phải ghi file tạm (`:6051-6062`).

### 2.7. Các loại lượt chấm Mobile và chống chấm trùng

6 loại (`MobileAttendanceController.cs:5040`, nhãn `:6826-6833`,
quy đổi sang trạng thái thô `:9323-9332`):

| `PunchType` | Nhãn trong app | `AttendanceState` khi ghi thô |
|---|---|---|
| 0 | Vào ca | `CheckIn` |
| 1 | Ra ca | `CheckOut` |
| 2 | **Bắt đầu đi** | `TravelStart` |
| 3 | **Đến điểm làm** | `TravelArrive` |
| 4 | Ra tăng ca trưa | `MealOut` |
| 5 | Vào lại sau nghỉ | `MealIn` |

Chấm đi đường (2/3) **không tính vào giờ ca**, chỉ cộng «giờ đi đường» từ cặp 2→3 và chỉ tính bản đã duyệt
(`src/ZKTecoADMS.Domain/Enums/AttendanceStates.cs:11-14`,
`src/payroll_engine/lib/utils/travel_hours_calculator.dart:53-60`); dòng thô được gắn `WorkCode = "TRAVEL"`
(`MobileAttendanceController.cs:9130-9134`). Chấm đi đường **luôn phải duyệt tay** (không bao giờ tự duyệt,
`MobilePunchRiskScorer.cs:102`).

Chống chấm trùng: tối đa N lượt/ngày (`MaxPunchesPerDay`; không cấu hình = **20**, giá trị ≤0 = không giới hạn,
giá trị cũ 4 được nâng lên 20 — `MobileAttendanceController.cs:177-188`, `:5333-5342`)
và **khoảng cách tối thiểu giữa 2 lượt** `MinPunchIntervalMinutes` (mặc định 5 phút,
`MobileAttendanceSetting.cs:43`, kiểm tra `:5354-5444`).

**Giờ chấm luôn lấy giờ server (Asia/Ho_Chi_Minh)**, không tin đồng hồ điện thoại
(`:5249-5303`, ghi nhận `:6611-6614`) — điểm này đáng nêu khi giới thiệu vì chặn thủ thuật đổi giờ máy.

### 2.8. Chế độ xác thực «Chỉ cần đạt 1» / «Phải đạt tất cả»

Cửa hàng bật từng phương thức: **Khuôn mặt / Vị trí GPS / Wi-Fi công ty**
(`mobile_attendance_settings_screen.dart:498-524`), rồi chọn
**«Chỉ cần đạt 1»** (`any`) hoặc **«Phải đạt tất cả»** (`all`) (`:546-553`).
Server áp dụng lại (`MobileAttendanceController.cs:5677-5689`, `:6425-6529`):

- phương thức chỉ được tính là «đang bật» khi **cả cửa hàng bật và máy được phép**
  (`enableFace = settings.EnableFaceId && device.CanUseFaceId`, `:5677-5680`);
- GPS coi là đạt khi trong vùng, **hoặc** khi máy được phép chấm ngoài và có gửi tọa độ thật (`:6437-6441`);
- khi chấm ngoài công ty, **không đòi Wi-Fi công ty** (`:6453-6454`);
- `all` thiếu bất kỳ cái nào → từ chối và **nêu tên cái thiếu** (`:6472-6505`);
- `any` mà không cái nào đạt → từ chối (`:6511-6520`);
- giá trị `VerificationMode` lạ (ví dụ «ALL» viết hoa lưu từ trước) được quy về `all` cho chắc (`:5686-5689`).

### 2.9. Ưu điểm / hạn chế của Chấm công Mobile

**Ưu điểm**

- Không cần đầu tư máy; chạy được cho NV hiện trường, nhiều chi nhánh.
- Nhiều lớp chống gian lận **đặt ở server**: khoảng cách GPS, BSSID/SSID/IP, liveness chớp mắt,
  anti-spoof thụ động, khóa theo máy đã duyệt, giờ server, điểm rủi ro, hạn mức lượt/ngày.
- Mọi bản ghi giữ đủ bằng chứng để đối chiếu khi khiếu nại: tọa độ, khoảng cách, tên điểm chấm, điểm khớp mặt,
  SSID/BSSID/IP, ảnh hiện trường, lý do, cờ rủi ro (`MobileAttendanceRecord.cs:30-105`).
- Chỉ bản **đã duyệt** mới vào bảng công → sai sót không trực tiếp thành tiền lương.

**Hạn chế**

- **Không phát hiện giả vị trí (fake GPS)**: không có chỗ nào trong mã đọc cờ `isMocked` /
  `isFromMockProvider` (tìm toàn kho `flutter_client/lib`, `src`, `flutter_pos/lib` — không có kết quả).
  Toạ độ do client gửi trong thân yêu cầu (`MobileAttendanceController.cs:6620-6623`);
  phòng vệ hiện có chỉ là *gián tiếp*: khớp Wi-Fi/IP, điểm rủi ro theo sai số GPS và khoảng cách, ảnh hiện trường.
- Wi-Fi mesh nhiều cục phát hay báo «không khớp» — tài liệu hướng dẫn khuyên dùng GPS
  (`landing_usage_guide.dart:977`).
- Trên **bản web** không đọc được BSSID → phải dựa IP (`:5612-5645`), và `DeviceId` chỉ là hash user-agent.
- Phụ thuộc điện thoại nhân viên (camera, quyền vị trí, pin) và chất lượng model trên máy;
  máy yếu rơi về đường so sánh phía server, chậm hơn (comment `:5906-5915`).
- Mỗi tài khoản 1 máy: nhân viên đổi/mất điện thoại phải chờ quản lý duyệt phiếu đổi máy.

---

## 3. Chấm công hộ (quản lý chấm thay)

**Chưa có tính năng tên là «chấm công hộ».** Tìm toàn bộ `flutter_client/lib` chỉ thấy cụm này trong
điều khoản sử dụng (bị cấm — `flutter_client/lib/content/app_legal_pages.dart:205`).
Việc «quản lý chấm thay nhân viên» hiện được làm bằng **3 đường, đều để lại dấu**:

### 3.1. «Chấm công thủ công» (nhập tay một lượt chấm)

`POST /api/Attendances/manual` (`src/ZKTecoADMS.Api/Controllers/AttendancesController.cs:571-768`),
trên app là nút **«Chấm công thủ công»** trong Chấm công thô
(`flutter_client/lib/screens/attendance_screen.dart:877`, `landing_usage_guide.dart:1026`).

- Quyền: module `Attendance` hành động `Create` (`:572`).
- Không phải Admin thì **thiết bị phải thuộc cửa hàng mình** (`:602-609`) và
  **nhân viên phải là cấp dưới** (`GetSubordinateEmployeeIdsAsync`, `:619-626`).
- Vào/ra được **tự suy theo thứ tự lượt trong ngày**: lẻ = vào, chẵn = ra (`:695-712`).
- Ghi `VerifyMode = VerifyModes.Manual` (=100) và `Note` do người nhập ghi
  (`:728-740`, mặc định *«Chấm công thủ công»* — `flutter_client/lib/services/api_service.dart:1535`).
- Chống trùng theo `(DeviceId, PIN, AttendanceTime)` (`:719-726`).

### 3.2. Nhập hàng loạt từ Excel

`POST /api/Attendances/import` — mỗi dòng một lượt chấm, server tự gắn máy / `DeviceUser` / vào-ra
(`AttendancesController.cs:770-789`).

### 3.3. Bổ sung giờ đi đường thay nhân viên

`POST /api/mobile-attendance/manual-travel` (`MobileAttendanceController.cs:7204-7262`):
quản lý nhập cặp «Bắt đầu đi» + «Đến điểm làm», bản ghi được tạo với
`VerifyMethod = "manual"`, `Status = "approved"`, `DeviceId = "MANUAL"`,
`DeviceName = "Bổ sung thủ công"` và `Note` có *«[Bổ sung thủ công bởi {email}]»* (`:7241-7264`).

**Ưu điểm**: xử lý nhanh khi máy hỏng / NV quên chấm, có kiểm tra phạm vi quản lý.
**Hạn chế**: không có bước duyệt (người có quyền `Attendance.Create` ghi là vào thẳng bảng công);
lượt nhập tay lẫn với lượt chấm Mobile chỉ-GPS vì cả hai đều hiện `VerifyMode = Thủ công` (xem mục 7);
và dòng thêm tay bị gắn vào **một thiết bị bất kỳ của cửa hàng** nếu không chọn máy
(`AttendancesController.cs:593-598`) nên cột «Máy chấm» có thể hiện tên một máy thật.

---

## 4. Yêu cầu sửa / bổ sung giờ công do nhân viên gửi lên

Tên trong sản phẩm: **«Xin sửa / bổ sung công»** (`FeatureModuleCatalog.cs:94`),
màn hướng dẫn gọi là **«Sửa công, bổ sung công & quên chấm công»** (`landing_usage_guide.dart:995`).

### Cách hoạt động

Entity `AttendanceCorrectionRequest` (`src/ZKTecoADMS.Domain/Entities/AttendanceCorrectionRequest.cs`) giữ:
loại hành động (`CorrectionAction`: **Thêm mới / Sửa / Xóa** — `src/ZKTecoADMS.Domain/Enums/NewEnums.cs:63-79`),
giờ cũ (`OldDate/OldTime/OldDevice/OldType`), giờ mới (`NewDate/NewTime/NewPunchType`),
**lý do bắt buộc** (`:73-75`), trạng thái (`CorrectionStatus`: **Pending / Approved / Rejected** —
`NewEnums.cs:84-100`), `TotalApprovalLevels`, `CurrentApprovalStep` (`:100-107`) và danh sách `ApprovalRecords`.

API `src/ZKTecoADMS.Api/Controllers/AttendanceCorrectionsController.cs`:
`GET` danh sách cho quản lý (`:19`), `GET my` của chính mình (`:40`), `POST` tạo (`:66`),
`POST {id}/approve` (`:91`), `DELETE {id}` (`:111`), `POST {id}/undo-approve` (`:128`).
Nhân viên chỉ xem/xóa **đơn của mình** (`:61-62`, `:116-122`).

Khi tạo (`src/ZKTecoADMS.Application/Commands/AttendanceCorrections/AttendanceCorrectionCommands.cs:92-295`):

- bật/tắt bằng cài đặt `allow_manual_correction`; tắt thì chỉ tài khoản quyền cao được vượt
  (`:154-162`) — UI: Thiết lập SBOX › Cửa hàng › Tham số hệ thống › **«Chấm công bù & quy trình duyệt»**
  (`landing_usage_guide.dart:999`);
- với Sửa/Xóa phải **tìm được đúng dòng chấm công thô**, không thấy thì báo lỗi ngay (`:110-131`);
- đọc số cấp duyệt từ `attendance_approval_levels` (nhận 1–5, mặc định 1 — `:306-317`)
  rồi **dựng sẵn chuỗi duyệt** (mục 5);
- tài khoản có quyền quản trị thì **tự duyệt + áp dụng ngay**, ghi chú *«Tự động duyệt — tài khoản quyền quản trị»*
  (`:220-256`).

Khi duyệt đủ cấp, `AttendanceCorrectionApplyHelper` áp vào chấm công thô
(`src/ZKTecoADMS.Application/Helpers/AttendanceCorrectionApplyHelper.cs:183-362`):

- **Thêm mới** → tạo dòng `Attendance` mới với `VerifyMode = Manual` và
  `Note = "Duyệt thêm chấm công ({trạng thái}) [YC:{id đơn}]"` (`:296-309`);
- **Sửa** → đổi `AttendanceTime`, đổi vào/ra nếu phiếu chọn lại, `Note = "Điều chỉnh giờ chấm công [YC:…]"`
  (`:314-338`);
- **Xóa** → xóa dòng chấm, có lưu lại loại cũ (`:341-362`).

Phiếu phạt tự động của ngày đó bị hủy và tính lại; muốn vẫn phạt thì quản lý bấm **«Duyệt + phạt»**
(`landing_usage_guide.dart:1004`, API `POST /api/attendance-approvals/corrections/{id}/approve-and-fine`
— `src/ZKTecoADMS.Api/Controllers/AttendanceApprovalsController.cs:287`, tham số `:50-54`).

### «Dấu đã sửa» trên bảng công

`GET /api/attendance-edit-marks` trả về, cho từng dòng chấm công: hành động (`add`/`edit`),
**giờ gốc**, giờ mới, lý do, ghi chú người duyệt, người duyệt, thời điểm, số lần đã sửa
(`src/ZKTecoADMS.Api/Controllers/AttendanceEditMarksController.cs:152-219`);
nhân viên thường chỉ thấy dấu sửa của chính mình (`:177`).
Trên bảng tổng hợp, ô giờ có chấm nhỏ, rê chuột ra chi tiết (`:152-155`).

### Ưu điểm / hạn chế

**Ưu điểm**: không xóa log máy để sửa công (`landing_usage_guide.dart:1032`); có lý do, người duyệt,
nhiều cấp, dấu vết đầy đủ và tính lại phạt.
**Hạn chế**: giờ bổ sung mang `VerifyMode = Thủ công` nên không phân biệt được với lượt nhập tay của quản lý
nếu không đọc `Note`; nhân viên bị giới hạn **30 ngày gần nhất** khi tự gửi phiếu từ app
(`landing_usage_guide.dart:1001`); đơn sửa công **không** có luồng «chấm điểm rủi ro» như chấm Mobile ngoài vị trí.

---

## 5. Duyệt nhiều cấp, trạng thái và ai được duyệt cái gì

### 5.1. Hai luồng duyệt khác nhau — đừng gộp khi giới thiệu

| | Chấm công Mobile | Phiếu sửa / bổ sung công |
|---|---|---|
| Bảng | `MobileAttendanceRecords` | `AttendanceCorrectionRequests` + `ApprovalRecords` |
| Trạng thái | `pending` / `approved` / `rejected` / `auto_approved` (`MobileAttendanceRecord.cs:52-57`) | `Pending` / `Approved` / `Rejected` (`NewEnums.cs:84-100`) |
| Số cấp | **1 cấp** (một người duyệt là xong — `MobileAttendanceController.ApprovalV2.cs:146-161`) | **1–5 cấp** theo `attendance_approval_levels` (`AttendanceCorrectionCommands.cs:306-317`); UI hướng dẫn nêu 1/2/3 cấp (`landing_usage_guide.dart:999`) |
| Tự duyệt | theo điểm rủi ro / tại công ty / Admin | tài khoản quyền quản trị (`AttendanceCorrectionCommands.cs:220-256`) |

### 5.2. Chuỗi duyệt nhiều cấp của phiếu sửa công

`BuildApprovalChainAsync` (`AttendanceCorrectionCommands.cs:326-398`):

- **Cấp 1 = quản lý trực tiếp** (`Employee.DirectManagerEmployeeId`),
- **Cấp 2 = quản lý của quản lý** (`:346-357`),
- cấp còn lại hoặc thiếu người → **Admin của cửa hàng** làm dự phòng (`:380-385`),
- tên bước: *«Quản lý trực tiếp», «Quản lý cấp cao», «Admin», «Cấp 4», «Cấp 5»* (`:367`).

Khi duyệt (`:450-623`):

- chỉ xử lý phiếu đang `Pending` (`:462`);
- lấy **bước đang chờ đầu tiên**, cho phép **người được giao** hoặc người có quyền module duyệt (`:517-525`);
- **từ chối ở bất kỳ cấp nào là từ chối cả phiếu** (`:537-562`), nhân viên nhận thông báo kèm lý do;
- duyệt xong mà còn cấp sau → chuyển bước, thông báo *«Cần duyệt chỉnh công … Cấp 2/3 …»* cho người tiếp theo
  và báo tiến độ cho nhân viên (`:576-614`);
- hết cấp → `FinalizeApprovedAsync` áp vào chấm công thô (`:571-575`);
- có cả đường cứu trạng thái «mồ côi» (mọi bước đã duyệt mà phiếu vẫn Pending do lần áp dụng trước lỗi — `:490-515`).

### 5.3. Ai được duyệt cái gì — `ApprovalScopeGuard`

Trước đây API duyệt chỉ kiểm **quyền chức năng**, nên trưởng phòng A gọi thẳng API vẫn duyệt được đơn phòng B.
Nay mọi lệnh duyệt đi qua `src/ZKTecoADMS.Api/Services/ApprovalScopeGuard.cs` (chú thích `:8-19`),
thứ tự quyết định (`:67-78`):

1. tài khoản toàn quyền (Admin / SuperAdmin / Agent) → được;
2. **đơn của chính mình → không được tự duyệt** (*«Không thể tự duyệt đơn của chính mình»*, `:25`);
3. Giám đốc / Kế toán (xem cả cửa hàng) → được;
4. **người được giao bước duyệt này** → được, dù không phải cấp trên (`:74`);
5. người duyệt **chưa được giao phạm vi nào** → được như cũ (cửa hàng nhỏ vẫn chạy bình thường, `:75`);
6. còn lại: nhân viên phải thuộc phạm vi mình quản lý, không thì
   *«Nhân viên này không thuộc phạm vi bạn quản lý»* (`:24`, `:76-77`).

Guard phủ cả `MobilePunch`, `MobileDevice`, `MobileDeviceChange`, `AttendanceCorrection`,
`Leave`, `Advance`, `Overtime`, `Penalty` (`:22`, `:80-114`).

### 5.4. Quyền (module) liên quan

`FeatureModuleCatalog.cs:84-96`, `:104`, `:130`, `:204`:

| Module | Tên hiển thị |
|---|---|
| `Attendance` | Chấm công thô |
| `DeviceUser` | Nhân sự trên máy chấm công |
| `MobileAttendance` | Chấm công Mobile |
| `MobileDeviceRegistration` | Đăng ký điện thoại chấm công |
| `AttendanceCorrection` | Xin sửa / bổ sung công |
| `AttendanceApproval` | Duyệt chấm công |
| `MobileAttendanceApproval` | Duyệt chấm công Mobile |
| `AttendanceSummary` / `AttendanceByShift` | Tổng hợp chấm công / theo ca |
| `TravelHoursReport` | Báo cáo đi đường |
| `Geofence` | Vùng chấm công |
| `FieldCheckIn` | Bản đồ nhân sự |

Chính sách vai trò tối thiểu: xem cài đặt/vị trí cho mọi người đăng nhập, **sửa cài đặt và duyệt yêu cầu
`AtLeastManager`** (ví dụ `MobileAttendanceController.cs:552`, `:789`, `:7884`;
`MobileAttendanceController.ApprovalV2.cs:205`, `:222`).

### 5.5. Hộp duyệt gộp («Duyệt chấm công»)

`GET /api/attendance-approvals/inbox` (`AttendanceApprovalsController.cs:87-222`) gom **cả hai loại** vào một hộp:

- gộp lượt chấm Mobile `pending` và phiếu sửa công `Pending` (`:104`, `:142`);
- lọc theo chi nhánh đang xem, theo loại (`mobile` / `correction`), theo mức rủi ro, theo tên/mã NV (`:178-210`);
- đếm nhanh: tất cả / Mobile / sửa công / ngoài vị trí / tin cậy / rủi ro cao / **quá 24 giờ chưa xử lý** (`:186-195`);
- sắp xếp: rủi ro cao trước, rồi quá hạn, rồi mới nhất (`:211-212`);
- thống kê 30 ngày tỉ lệ tự duyệt / duyệt tay / từ chối của lượt chấm ngoài vị trí (`:214-221`).

Thao tác duyệt: từng bản (`MobileAttendanceController.cs:7881`), **hàng loạt tối đa 500 bản**
(`ApprovalV2.cs:204-218`), hoặc **«Duyệt N bản tin cậy»** — duyệt hết bản `trusted` trừ chấm đi đường
(`ApprovalV2.cs:221-234`). Từ chối **bắt buộc có lý do** (`:209-210`).
Xem ngữ cảnh một bản trước khi quyết: các lượt chấm cùng ngày, ca trong lịch, dòng chấm công thô của ngày,
số lần chấm ngoài trong tháng, 6 lần gần nhất đã xử lý, danh sách vị trí, thông tin máy
(`ApprovalV2.cs:259-334`).

Nhân viên được báo kết quả: duyệt → *«Chấm vào 08:05 12/11 đã duyệt / Đã ghi vào bảng công»*,
từ chối → kèm lý do và gợi ý **gửi giải trình / xin bổ sung công** (`ApprovalV2.cs:167-202`).

---

## 6. Người duyệt lượt chấm Mobile được chọn thế nào

`ResolvePunchApproversAsync` (`ApprovalV2.cs:117-142`): **quản lý trực tiếp** của nhân viên (nếu có tài khoản đang hoạt động);
không có thì **toàn bộ tài khoản `Manager` / `Admin` / `StoreOwner`** của cửa hàng.
Khác với luồng thông báo chấm công từ máy (mục 1) vốn đi theo *phòng ban + chuỗi quản lý, 2 cấp*.

---

## 7. Dữ liệu chấm công hiển thị ra sao

### 7.1. Màn «Chấm công thô»

Bộ lọc: thời gian, **thiết bị**, **kiểu xác thực**, nhân viên; mỗi dòng có ngày giờ chấm, mã/tên NV,
tên trong máy, máy chấm, kiểu xác thực (`landing_usage_guide.dart:1023-1024`).
Dải thẻ thống kê đếm theo kiểu xác thực: **Vân tay (1) · Khuôn mặt (15, 9) · Thẻ từ (2) · Thủ công (100) ·
Chưa gắn nhân viên** (`flutter_client/lib/screens/attendance_screen.dart:2120-2194`).

Nhãn kiểu xác thực dùng chung một bảng (`src/payroll_engine/lib/models/attendance.dart:321-342`):
`-1 Không xác định · 0 Mật khẩu · 1 Vân tay · 2 Thẻ từ · 9,15 Khuôn mặt · 100 Thủ công · khác «Khác (n)»`.

Mở chi tiết một dòng đến từ điện thoại thì hiện thêm:
**«Nguồn: Chấm công mobile»**, **«Điểm chấm»** (tên vị trí), **bản đồ vị trí GPS lúc chấm**, **ảnh hiện trường**
(`attendance_screen.dart:4015-4081`, widget `punch_location_preview.dart`, `punch_photo_preview.dart`).
Trên Trang chủ, lượt chấm từ điện thoại hiện chữ **«Mobile»** thay cho kiểu xác thực
(`flutter_client/lib/screens/dashboard_screen.dart:11162`).
Cờ `isFromMobile` được suy ra từ `mobileAttendanceRecordId` **hoặc** `Note` chứa `mobile:`
(`src/payroll_engine/lib/models/attendance.dart:52-55`).

### 7.2. KIỂU chấm được ghi/suy ra như thế nào (điểm cần nói chính xác)

Lượt chấm Mobile khi được duyệt sẽ ghi sang chấm công thô bằng
`SyncMobileRecordToAttendanceLog` (`MobileAttendanceController.cs:8979-9282`):

- thiết bị là **máy ảo của cửa hàng**: serial `MOB-{storeId}`, tên **«Chấm công Mobile»**
  (`:8822-8871`);
- `VerifyMode` = **`Face`** nếu `VerifyMethod` có thành phần `face`, **ngược lại `Manual`**
  (`:9092-9096`);
- `Note` = `"Mobile: {verifyMethod}"` với `verifyMethod` ∈ `face`, `gps`, `wifi`, `face_gps`,
  `face_gps_wifi`, … hoặc `manual` khi không phương thức nào đạt
  (`DetermineVerifyMethod`, `:8495-8519`; gán `:6650`, ghi note `:9103`);
- chấm đi đường thêm `WorkCode = "TRAVEL"` và note *«Mobile đi đường: …»* (`:9100-9102`, `:9130-9134`);
- liên kết 1-1 qua `MobileAttendanceRecordId`, có xử lý trùng khóa `(Device, PIN, Time)` và cả tình huống đua
  (`:9111-9211`).

⚠️ **Vì vậy, trong bảng chấm công thô:**

| Thực tế | Hiện ở cột «Kiểu xác thực» | Phân biệt bằng |
|---|---|---|
| Máy ZKTeco, vân tay | Vân tay | — |
| Máy ZKTeco, khuôn mặt | Khuôn mặt | — |
| Mobile, có khuôn mặt (kèm GPS/Wi-Fi) | Khuôn mặt | tên máy «Chấm công Mobile», Note `Mobile: face_gps` |
| **Mobile, chỉ GPS hoặc chỉ Wi-Fi** | **Thủ công** | Note `Mobile: gps` / `Mobile: wifi` |
| Quản lý nhập tay | Thủ công | Note người nhập / *«Chấm công thủ công»* |
| Phiếu bổ sung công đã duyệt | Thủ công | Note `Duyệt thêm chấm công (…) [YC:…]` + dấu «đã sửa» |
| Giờ đi đường | Thủ công / Khuôn mặt | `WorkCode = TRAVEL`, Note *«Mobile đi đường…»* |

Toàn bộ chi tiết «đẹp» (khoảng cách, điểm khớp mặt, ảnh, lý do, điểm rủi ro) **nằm ở
`MobileAttendanceRecords`**, không nằm ở bảng thô — xem qua `GET records/{id}` (`:7015`),
`GET records/{id}/context` (`ApprovalV2.cs:259`), lịch sử `GET history` (`:7494`).

### 7.3. Từ lượt chấm thành giờ công – ngày công

Bộ tính công dùng chung Dart ở `src/payroll_engine/lib/utils/shift_records_calculator.dart`
(tab **«Tổng hợp theo ca»** và bảng lương dùng cùng một bộ này).

**a) Cách chấm công (`Benefit.AttendanceMode`)** — chọn trong **Thiết lập lương › «Ngày công và chấm công» ›
«Cách chấm công»** (`landing_usage_guide.dart:830-849`), 7 lựa chọn
(`shift_records_calculator.dart:10-47`, `:29`, `:33`):

| Giá trị | Nghĩa |
|---|---|
| (mặc định) | Chấm vào và ra |
| `once` / `checkin` | **Chỉ chấm vào** — tính trễ theo giờ vào ca, giờ ra = hết ca (`:16-21`) |
| `checkout` | **Chỉ chấm ra** — tính về sớm, không tính trễ (`:23-24`) |
| `any` | **Chấm bất kỳ trong ca** — một lượt trong khung ca là đủ ca, không tính trễ/sớm (`:31-33`) |
| `free2` | **Chấm 2 lần bất kỳ trong ngày** → 1 công, không xét ca, không trễ/sớm/tăng ca (`:10-14`) |
| `fullday` | **Ca nguyên ngày** (~24h), ghép cặp theo thời gian, ngày công = ngày của lượt vào (`:26-29`) |
| — | «Không chấm công» (có trong UI, `landing_usage_guide.dart:837`) |

Chế độ `once` còn ảnh hưởng tới lúc ghi dữ liệu thô: mọi lượt chấm Mobile vào/ra đều ghi `CheckIn`
(`MobileAttendanceController.cs:9334-9351`).

**b) Gán ca cho lượt chấm** — `src/ZKTecoADMS.Application/Helpers/ShiftMatchHelper.cs`
(bản C# khớp đúng `findBestMatchingShift` của Flutter, chú thích `:3-7`):

- ca qua đêm nhận biết bằng giờ vào > giờ ra (`:16`);
- chọn ca theo **điểm phạt nhỏ nhất** (trễ + về sớm sau grace), rồi gần giờ vào nhất,
  hòa thì chọn **ca dài hơn** (`:150-177`);
- loại ca nếu vào sớm quá `EarlyCheckInMinutes` hoặc cách giờ vào > **180 phút** (`:227`, `:64`);
- tham số lấy từ **Ca mẫu** (`src/ZKTecoADMS.Domain/Entities/ShiftTemplate.cs:20-43`):
  `MaximumAllowedLateMinutes` (30), `MaximumAllowedEarlyLeaveMinutes` (30),
  `EarlyCheckInMinutes` (30), `LateGraceMinutes` (5), `EarlyLeaveGraceMinutes` (5),
  `OvertimeMinutesThreshold` (30), `EarlyOvertimeMinutesThreshold` (30), `BreakTimeMinutes`,
  giờ nghỉ trưa. UI: **«Quy tắc chấm công»: Nhận chấm sớm, Miễn trễ, Miễn về sớm, Giới hạn về sớm,
  Tăng ca trước / sau ca** (`landing_usage_guide.dart:804`).

**c) Trễ / về sớm**: phút trễ = giờ chấm − giờ vào ca, **phút trong hạn «Miễn trễ» (grace) tính bằng 0**
(`ShiftMatchHelper.cs:231-233`); về sớm tương tự với grace về sớm (`:235-242`);
vào trễ quá `MaximumAllowedLateMinutes` **vẫn khớp ca và vẫn tính đủ phút trễ** (chú thích `:41-44`).

**d) Ngày công**: `computeDayWorkCredit` (`shift_records_calculator.dart:133-167`):

- dưới `minHalfDayHours` (mặc định 1 giờ, `:130`) → **0 công**;
- **bật «công thập phân»** → làm tròn về bậc 0,1 công theo tỉ lệ giờ làm / giờ chuẩn 1 công (`:153-161`);
- **tắt** → đạt ≥ `minPercent`% giờ chuẩn (mặc định **80%**) = **1 công**, không đạt = **0,5 công** (`:163-166`);
- giờ chuẩn 1 công lấy từ hồ sơ lương `hoursPerWorkDay`, mặc định 8 giờ (`:196-217`).

**e) Làm tròn giờ công**: `AppSettings` khóa `rounding_rule`
(`src/ZKTecoADMS.Application/Helpers/WorkHoursHelper.cs:6-30`): `none` (giữ nguyên),
`round_up`, `round_down`, `round_nearest` — **bậc 15 phút** (`:22`).

**f) Kết quả mỗi ngày** là `DailyShiftRecord` (`shift_records_calculator.dart:267-323`):
danh sách giờ chấm, tên ca, **phút trễ, phút về sớm, phút tăng ca**, giờ công, giờ thập phân,
công (`workCount`), giờ theo từng ca trong ngày, trạng thái + màu, và chi tiết trễ/sớm theo từng ca.
Giờ OT được phân loại vào các bậc lương ở `:3351-3453`.

**g) Giờ đi đường** tính riêng từ cặp «Bắt đầu đi» → «Đến điểm làm», chỉ bản đã duyệt
(`travel_hours_calculator.dart:53-60`), báo cáo riêng **«Báo cáo đi đường»** (`FeatureModuleCatalog.cs:104`),
và theo chú thích thì **tính giờ lương thường, không tính tăng ca**
(`AuthorizedMobileDevice.cs:47-48`).

### 7.4. Phạt tự động sinh ra từ dữ liệu chấm công

`src/ZKTecoADMS.Infrastructure/Services/AttendanceService.cs:186` (`UpdateShiftAttendancesAsync`) tạo phiếu phạt:

- **Nghỉ không phép** khi ngày có lịch làm mà không có lượt chấm nào và không có đơn nghỉ đã duyệt (`:900-913`);
- **Quên chấm công** khi chỉ có giờ vào **hoặc** chỉ có giờ ra (`:915-927`);
- bỏ qua với các cách chấm công không đòi đủ vào+ra (`free2`, `fullday`, `once`, `checkin`, `checkout` — `:876-880`).
Mức phạt: Thiết lập SBOX › **Mức phạt** › «Quên chấm công» (0 = không phạt), phiếu chờ duyệt và tự duyệt sau
số giờ đã đặt (`landing_usage_guide.dart:1005`).

---

## 8. Bảng so sánh nhanh các phương pháp

| | Máy ZKTeco (ADMS) | Gateway WiFi (máy LAN cũ) | Chấm công Mobile | Chấm công thủ công | Xin sửa / bổ sung công |
|---|---|---|---|---|---|
| Thiết bị cần | Máy ZK có ADMS + internet | Máy ZK LAN + mạch ESP32-C3 + WiFi 2.4G | Điện thoại NV (camera, GPS, quyền vị trí) | Không | Không |
| Danh tính xác thực bằng | Vân tay / khuôn mặt / thẻ / mật khẩu **trên máy** | như trên | Khuôn mặt trên máy + liveness chớp mắt, đối sánh lại ở server | Tin người nhập | Tin người duyệt |
| Vị trí | Mặc định theo nơi đặt máy | như trên | GPS bán kính + Wi-Fi (BSSID/SSID/IP) | Không | Không |
| Realtime | **Tức thì** (`Realtime=1`) | **~30 giây** (chu kỳ quét) | Tức thì khi gửi; **chỉ vào bảng công sau khi duyệt** | Ngay | Sau khi duyệt đủ cấp |
| Cần duyệt | Không | Không | Có, trừ trường hợp tự duyệt (tại công ty / `trusted` / Admin) | **Không** | **Có, 1–5 cấp** |
| Số cấp duyệt | — | — | **1** | — | **1–5** |
| Ghi vào chấm công thô | Trực tiếp | Trực tiếp | Qua `MobileAttendanceRecords` | Trực tiếp | Qua phiếu đã duyệt |
| `VerifyMode` lưu | 0,1,2,…,15 | như trên | `Face` (có mặt) / `Manual` (chỉ GPS-Wi-Fi) | `Manual` (100) | `Manual` (100) |
| Bằng chứng kèm theo | — | — | Toạ độ, khoảng cách, điểm mặt, SSID/BSSID/IP, ảnh hiện trường, lý do, điểm rủi ro | Ghi chú | Lý do, giờ cũ/mới, người duyệt, dấu «đã sửa» |
| Bật/tắt ở | Thiết lập SBOX › Nhân sự & chấm công › Máy chấm công | … › Gateway WiFi | … › Chấm công Mobile (Cài đặt / Vị trí / Thiết bị) | Quyền `Attendance.Create` | Tham số hệ thống › Chấm công bù & quy trình duyệt |
| Rủi ro chính | Lệch mã PIN, lệch giờ máy | Trễ ~30 giây, phụ thuộc mạch | **Không chặn fake GPS**, Wi-Fi mesh, phụ thuộc máy NV | Không có bước duyệt | Phụ thuộc người duyệt |

---

## 9. Chưa hỗ trợ / còn thiếu

Các điểm dưới đây đều kiểm chứng bằng cách tìm trong mã nguồn; đã nêu rõ đâu là suy đoán.

1. **Không phát hiện giả vị trí (fake GPS / mock location).**
   Không có chỗ nào đọc `isMocked` / `isFromMockProvider` / `MockLocation` trong
   `flutter_client/lib`, `src`, `flutter_pos/lib`; app chỉ lấy toạ độ qua
   `Geolocator.getCurrentPosition` (`flutter_client/lib/utils/platform_geolocation_stub.dart:81-94`)
   và server nhận toạ độ từ thân yêu cầu (`MobileAttendanceController.cs:6620-6623`).
   Hiện chỉ có phòng vệ gián tiếp: điểm rủi ro theo khoảng cách + sai số GPS, khớp Wi-Fi/IP, ảnh hiện trường.
2. **Chấm công Mobile chỉ có 1 cấp duyệt.** Không có `TotalApprovalLevels` / chuỗi `ApprovalRecords`
   cho `MobileAttendanceRecords`: một người duyệt là xong (`ApprovalV2.cs:146-161`).
   «Quản lý → chủ doanh nghiệp» nhiều cấp **chỉ có ở phiếu sửa / bổ sung công**.
3. **Không có tính năng «chấm công hộ» đúng nghĩa** (quản lý quét mặt/bấm chấm thay NV ngay lúc đó).
   Thay thế bằng «Chấm công thủ công» (nhập giờ, không duyệt) và «manual-travel».
   Cụm «chấm công hộ» trong sản phẩm chỉ xuất hiện ở điều khoản sử dụng như hành vi **bị cấm**
   (`flutter_client/lib/content/app_legal_pages.dart:205`).
4. **«Chấm công thủ công» không qua bước duyệt** — ai có `Attendance.Create` là ghi thẳng vào bảng công
   (`AttendancesController.cs:571-742`). Chỉ có giới hạn phạm vi (cấp dưới + thiết bị cùng cửa hàng).
5. **Bảng chấm công thô không có cột «phương pháp chấm»**: lượt Mobile chỉ-GPS và lượt nhập tay đều
   hiện **«Thủ công»**, phải đọc `Note`/`MobileAttendanceRecordId` mới phân biệt (mục 7.2).
6. **Bảng `Geofences` («Vùng chấm công») không tham gia luồng chấm công.**
   Có entity + API (`src/ZKTecoADMS.Domain/Entities/Geofence.cs`,
   `src/ZKTecoADMS.Api/Controllers/GeofencesController.cs:28-59`) nhưng
   luồng chấm Mobile dùng `MobileWorkLocation`; và `getGeofences()` trong
   `flutter_client/lib/services/api_service.dart:13402` **không được màn hình nào gọi**
   (tìm `getGeofences(` trong `flutter_client/lib` chỉ ra chính nó) → di sản cũ.
   Các cột `Geofence.CheckInToleranceMinutes` / `CheckOutToleranceMinutes` vì vậy cũng không có tác dụng.
7. **Không khóa thiết bị bằng khóa mật mã.** `DeviceId` do client sinh và lưu trong
   `SharedPreferences` (`flutter_client/lib/utils/mobile_device_id.dart:13-50`) — không có attestation
   (SafetyNet / Play Integrity / DeviceCheck). Trên web, mã chỉ là hash user-agent.
8. **Không có nhận diện khuôn mặt phía quản lý trên máy dùng chung** (kiểu «kiosk»): mỗi lượt chấm Mobile
   bắt buộc gắn với **một máy đã đăng ký cho đúng một nhân viên** (`:5138-5153`, `:2340-2355`).
9. **Chưa có chấm công bằng NFC/thẻ trên điện thoại, QR, Bluetooth beacon hay chấm công bằng giọng nói.**
   `VerifyModes` chỉ liệt kê các kiểu của máy ZKTeco; `VerifyMethod` của Mobile chỉ nhận
   `face`, `gps`, `wifi`, tổ hợp của chúng, hoặc `manual` (`:8495-8519`).
10. **Bản ghi thêm tay không chọn máy sẽ bị gắn vào một thiết bị bất kỳ của cửa hàng**
    (`AttendancesController.cs:593-598`; tương tự khi áp phiếu bổ sung công —
    `AttendanceCorrectionApplyHelper.cs:200-209`) → cột «Máy chấm» có thể hiện tên máy thật
    dù lượt chấm là nhập tay.
11. **Thông báo realtime bỏ qua lượt chấm cũ**: quá 15 phút (`PostAttendancesStrategy.cs:17-18`)
    hoặc quá 24 giờ (`AttendanceNotificationService.cs:39-49`) thì không đẩy, dù dữ liệu vẫn vào bảng.
    Đúng thiết kế nhưng hay bị hiểu là lỗi.
12. **«Bản đồ nhân sự» (FieldCheckIn) không phải chấm công.** Check-in điểm bán / lộ trình ghi vào
    `VisitReports`, không ghi `AttendanceLogs` (`src/ZKTecoADMS.Api/Controllers/FieldCheckInController.cs:538-560`;
    tìm `AttendanceLogs` trong file này không có kết quả) → không sinh giờ công.
13. **Giới hạn «30 ngày gần nhất» khi gửi phiếu sửa công chỉ là chặn ở giao diện**, không phải quy tắc của server:
    nó là `firstDate` của hộp chọn ngày (`flutter_client/lib/screens/attendance_corrections_screen.dart:196-201`,
    nêu trong hướng dẫn `landing_usage_guide.dart:1001`); trong
    `src/ZKTecoADMS.Application/Commands/AttendanceCorrections/AttendanceCorrectionCommands.cs`
    **không có chỗ nào kiểm tra mốc 30 ngày**. Gọi API trực tiếp vẫn xin sửa được ngày cũ hơn.
14. **Mặc định ngưỡng khớp mặt không nhất quán**: entity khai 80 (`MobileAttendanceSetting.cs:27`)
    nhưng luồng chấm dùng 55 khi cửa hàng chưa có dòng cài đặt (`MobileAttendanceController.cs:5754`).
    Nên tạo sẵn dòng cài đặt cho mỗi cửa hàng trước khi bật Face ID.

---

## 10. Phụ lục — bảng mã hay dùng khi đọc dữ liệu

**`VerifyMode`** (`src/ZKTecoADMS.Domain/Enums/VerifyModes.cs`):
`-1` Không xác định · `0` Mật khẩu · `1` Vân tay · `2` Thẻ từ · `3` PIN · `4`–`9` tổ hợp ·
`15` Khuôn mặt · `100` Thủ công.

**`AttendanceState`** (`src/ZKTecoADMS.Domain/Enums/AttendanceStates.cs`):
`0` CheckIn · `1` CheckOut · `2` MealIn · `3` MealOut · `4` BreakIn · `5` BreakOut ·
`6` TravelStart · `7` TravelArrive.

**`MobileAttendanceRecord.VerifyMethod`**: `face`, `gps`, `wifi`, `face_gps`, `face_wifi`,
`face_gps_wifi`, `gps_wifi`, `manual` (`MobileAttendanceController.cs:8495-8519`).

**`MobileAttendanceRecord.Status`**: `pending`, `approved`, `rejected`, `auto_approved`
(`MobileAttendanceRecord.cs:52-57`).

**`RiskLevel`**: `trusted`, `review`, `high` (`MobilePunchRiskScorer.cs:41-43`).

**`CorrectionAction`** / **`CorrectionStatus`**: Add/Edit/Delete · Pending/Approved/Rejected
(`src/ZKTecoADMS.Domain/Enums/NewEnums.cs:63-100`).

**Cài đặt theo cửa hàng** (`src/ZKTecoADMS.Domain/Entities/MobileAttendanceSetting.cs`):
`EnableFaceId` (bật), `EnableGps` (bật), `EnableWifi` (tắt), `EnableLivenessDetection` (bật),
`VerificationMode` (`all`), `GpsRadiusMeters` (100), `MinFaceMatchScore` (80),
`AutoApproveInRange` (bật), `AllowManualApproval` (bật), `AutoApproveNewDevices` (tắt),
`MaxPhotosPerRegistration` (5), `MaxPunchesPerDay` (4 → hiểu là 20), `RequirePhotoProof` (tắt),
`MinPunchIntervalMinutes` (5), `AutoApproveTrusted` (bật), `TrustedMaxDistanceMeters` (300),
`TrustedMinFaceScore` (85), `EvidenceRetentionDays` (30).

**Khóa `AppSettings` liên quan**: `allow_manual_correction`, `attendance_approval_levels` (1–5),
`rounding_rule` (`none` / `round_up` / `round_down` / `round_nearest`, bậc 15 phút),
`min_work_day_percent` (mặc định 80), `decimalWorkDayEnabled`, `min_hours_for_work_day` (cũ).
