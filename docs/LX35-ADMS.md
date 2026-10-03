# Máy chấm công LX35 qua ADMS — kết quả thử thật (02–03/10/2026)

Máy thử: **LX35 test**, cửa hàng `demo`, server 103.133.224.176, SN `1313254900299`, DeviceId `f68df84e-13f2-4a5b-9b7d-29c508761eee`.
INFO: `~Platform=AK3750WIFI_TFT`, `FWVersion=ZLM31-FXO1-3.1.8`, `PushVersion=Ver 3.0.1-20230519`, `FaceFunOn=0`, `FingerFunOn=1`.
Server xếp máy này vào nhóm **`PushLite`** (`AdmsEngineProfiles`, nhận theo Platform AK37/AK39 hoặc pushver 3.0.x).

**Đọc file này trước khi thử lệnh mới trên LX35. Đừng tin tài liệu `E:\rom lx35\ADMS_LX35_LenhGiaoTiep.md`:**
tài liệu đó lấy từ chuỗi ký tự trong firmware, mà lệnh có tên trong firmware chưa chắc chạy được.

## 1. Bảng kết quả (lệnh gửi thật qua getrequest → devicecmd)

| Lệnh | Máy trả | Kết luận |
|---|---|---|
| `INFO` | Return=0, trả đủ thông tin | ✅ Từ `e79d468c` server lưu kết quả qua `GetDeviceInfoStrategy` |
| `DATA UPDATE USERINFO PIN=…` | 0 | ✅ Thêm/sửa nhân viên xuống máy |
| `DATA QUERY ATTLOG StartTime=…\tEndTime=…` (ngày dạng `T` và dạng có dấu cách) | -1002 | ❌ |
| `DATA QUERY ATTLOG` không tham số; tham số cách bằng dấu cách | -1002 | ❌ |
| `DATA QUERY USERINFO` | -1002 | ❌ |
| `ENROLL_FP PIN=…\tFID=…` (cả `OVERWRITE=0` lẫn `OVERWRITE=1` với PIN có sẵn) | -1002 sau 0,6 giây, màn hình đăng ký không mở | ❌ Phải đăng ký vân tay trên máy |
| **`CHECK`** | 0 hoặc -1002, **máy luôn bắt tay lại** (`GET /iclock/cdata?options=all&pushver=3.0.1`) | ✅ Dùng để tải lại dữ liệu |
| `__STAMP_SYNC__` (SyncAttendances, chỉ ở server) + `CHECK` | Máy gửi lại toàn bộ `ATTLOG` (server 1 → 3/3) | ✅ |
| `__STAMP_SYNC__` (SyncDeviceUsers) + `CHECK` | Máy gửi lại `OPERLOG` (user) | ✅ |
| `__STAMP_SYNC__` (SyncFingerprints) + `CHECK` (`BIODATAStamp=0`) | Chỉ gửi OPERLOG, **không có dòng `FP PIN=`** | ❌ |
| Handshake chỉ gửi `TransFlag=1111111111` (bỏ dòng dạng chữ) + đăng ký vân tay trên máy | Không có mẫu vân tay gửi lên | ❌ |
| Chấm công trên máy | Gửi lên ngay (realtime) | ✅ |
| Thêm user trực tiếp trên máy | Tự gửi lên server sau khoảng 2 phút (OPERLOG) | ✅ |
| `CLEAR DATA` | 0 | ⚠️ **Xóa sạch**: user 4→0, vân tay 4→0, **chấm công 5→0** |
| `CLEAR ALL USERINFO` (máy có 1 user) | -1002, user vẫn còn | ❌ Lúc máy trống trả 0, nhưng đó là kết quả giả |
| `CLEAR LOG` | Máy không trả lời (lệnh kẹt ở trạng thái «đã gửi») | ? Chưa rõ |
| `DATA DELETE USERINFO PIN=9001` | 0, UserCount 1→0 | ✅ Dùng cho «Xóa toàn bộ user» |
| Handshake gửi thêm `IsSupportFileSyncData=1` + CHECK | Máy vẫn báo `IsSupportFileSyncData=0`, DATA QUERY USERINFO vẫn -1002 | ❌ Cờ do firmware cố định, không đưa vào code |

Lưu ý: trên máy này `-1002` **không có nghĩa là máy không làm gì** (CHECK trả -1002 nhưng vẫn bắt tay lại). Phải nhìn dữ liệu máy gửi lên.

## 2. Phân tích ROM `E:\rom lx35\LX35.bin` (8 MB, chip Anyka)

- `..\Zkfirmware\comm\pushcomm\lib\libpushcommon\pushcmdparse.c`, hàm `PushCommandExecute`, vùng chuỗi ~0x114000:
  lệnh cấp đầu chỉ có **`CHECK`, `CLEAR`, `INFO`, `REBOOT`, `DATA`, `Pause`, `Resume`**, còn lại trả `UNKNOWN CMD`.
  Không có `AC_UNLOCK`, `SET OPTION`, `PutFile`, `UpdateFirmware`.
- `CHECK` → `PushCheckServer` (ghi log `[attLogStamp: %d] [operLogStamp: %d]`), tức đọc lại cấu hình từ server.
- Vùng ~0x16c800–0x16e100: `DATA UPDATE/DELETE USERINFO|FINGERTMP`, `DATA QUERY USERINFO|FINGERTMP|ATTLOG`
  (QUERY FINGERTMP bắt buộc có PIN, QUERY ATTLOG bắt buộc có StartTime/EndTime). Có trong code nhưng máy thật trả -1002.
  Còn các dạng Push cũ: `USER`, `FP`, `DEL_USER`, `DEL_FP`, `SETSK`, `DELALL`, `USER_VALIDDATE`.
- Cấu hình máy đọc lúc bắt tay (`GET OPTION FROM`, ~0xa2374): `Stamp/ATTLOGStamp`, `OpStamp/OPERLOGStamp`, `PhotoStamp`,
  `TimeZone`, `Delay`, `RequestDelay`, `ErrorDelay`, `TransInterval`, `TransFlag` (đọc bằng strspn, mặc định `1101101100`),
  `TransTables`, `TransTimes`, `Realtime`, `Timeout`, `Encrypt`, `SyncTime`, `ServerVer`, `MaxRecordCount`...
- URL gửi dữ liệu lên dùng cố định `table=%s&Stamp=9999` / `OpStamp=9999`: con số trong URL không phản ánh mốc thật.
- `FingerOnlineEnroll` nằm ở vùng giao diện / giao thức nội bộ (gần `UPDATE_PIN_WND`), không thuộc phần push.

## 3. Server đang làm gì với LX35 (commit `0e899818`, đã deploy server demo)

- **Tải chấm công / Tải user**: `DeviceCapabilityService.ResolveCommandAsync` trả `__STAMP_SYNC__`, rồi
  `CreateDeviceCmdHandler` thêm lệnh `CHECK` (CommandType `GetDeviceInfo`; nếu dùng Sync* thì CHECK bị coi là đánh dấu cũ, không giao xuống máy).
  Lần hỏi lệnh đầu server trả cấu hình stamp; lần sau giao CHECK; máy bắt tay lại, nhận Stamp=0 rồi gửi lại.
  Đánh dấu tự đóng sau 10 phút (`AutoCompleteStampSyncMarkersAsync`).
- **Đăng ký vân tay / khuôn mặt / mở-đóng cửa / tải vân tay**: báo lỗi rõ, không tạo lệnh. Nút bị ẩn
  (`GetCapabilityDtoAsync`, `GetAllDevicesHandler`: `UsesCheckStampSync(profile)`).
- Handshake chỉ gửi `TransFlag` dạng số (`UsesDigitTransFlag`). Không giúp gửi vân tay, nhưng vô hại.
- `-1002` trên tải user không đẩy máy PushLite về PullDeny (`LearnFromCommandResultAsync`).
- Test: `DeviceInfoCommandTests`, `Lx35PushLiteTests`.

## 4. Còn mở

- **Giả thuyết cổng chặn (2 phiên cùng đồng ý, chưa chứng minh 100%)**: INFO báo `IsSupportFileSyncData=0`. Mọi lệnh **không**
  cần máy gửi file kết quả (CLEAR DATA, DATA UPDATE USERINFO, INFO, CHECK) đều chạy; mọi lệnh **cần** gửi file kết quả qua
  `SendCmdExecFile2Server` (DATA QUERY *, ENROLL_FP) đều trả -1002 ngay. Module ADMS trong ROM (~0xa0000, `NOT SUPPORT %d` ở 0xa611c)
  là mã định vị lại nên không dò tham chiếu tĩnh được. Cờ này máy tự báo trong INFO, nhiều khả năng do bản build quyết định, không
  phải option server ghi được. Gửi `IsSupportFileSyncData=1` lúc bắt tay chưa thử, khả năng thành công thấp, cần người dùng quyết.

- **Vân tay**: không gửi được mẫu vân tay từ LX35 lên server, nên không sao chép vân tay sang máy khác được.
  Có thể thử thêm: `TransFlag` với thứ tự bit khác, hoặc `DATA QUERY FINGERTMP PIN=<pin>` (QUERY khác đều -1002, nhiều khả năng cũng vậy).
- **Xóa toàn bộ user** (đã làm, `9e7b2f66`): `CLEAR ALL USERINFO` không chạy, `CLEAR DATA` xóa cả chấm công, nên với PushLite
  `CreateDeviceCmdHandler` tạo một lệnh `DATA DELETE USERINFO PIN=…` (DeleteDeviceUser, ObjectReferenceId = DeviceUser.Id)
  cho mỗi nhân viên Sbox biết trên máy. Chưa có danh sách thì bảo «Tải user» trước. Chưa thử bấm thật từ app.
- **`CLEAR LOG`**: máy không trả lời. Cần thử lại khi máy có lượt chấm (03/10 máy đang trống).
- Máy test sau khi thử (03/10): đã xóa user test 9001, đẩy lại 4 nhân viên từ Sbox (968315, 2, 968314, 868). **Vân tay và
  lượt chấm cũ trên máy đã mất do `CLEAR DATA`** (lượt chấm đã lên Sbox vẫn còn). Lệnh `CLEAR LOG` treo đã đóng ở trạng thái Failed.
- Script thử nhanh trên server demo: `/root/lx35_send.sh "<LỆNH>" <CommandType>` (chỉ gửi tới đúng máy test, chờ và in kết quả).
- Server **103.133.225.67** chưa có bản LX35 (build 02/10 15:29).

## 5. Cách thử lệnh tay (cần người dùng cho phép, ghi vào CSDL production)

```sql
INSERT INTO "DeviceCommands" ("Id","DeviceId","CommandId","Command","Priority","Status","CommandType","ObjectReferenceId","CreatedAt","CreatedBy")
VALUES (gen_random_uuid(),'f68df84e-13f2-4a5b-9b7d-29c508761eee',<id duy nhất>,'<LỆNH>',1,0,<CommandType>,
        '00000000-0000-0000-0000-000000000000',now() at time zone 'utc','<tên phiên>');
```
CommandType: 7 SyncAttendances, 8 SyncDeviceUsers, 9 EnrollFingerprint, 11 SyncFingerprints, 17 GetDeviceInfo (dùng cho CHECK).
Đánh dấu `__STAMP_SYNC__` không tự chuyển trạng thái «đã gửi»: nhớ đóng (Status=2) sau khi thử, nếu không server cứ trả Stamp=0 mỗi lần máy bắt tay.
Xem kết quả: `docker logs zkteco_api | grep 1313254900299` và bảng `DeviceCommands` / `AttendanceLogs` / `DeviceUsers`.
