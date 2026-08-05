# SBOX ZK Gateway (ESP32-C3)

Firmware biến một module ESP32-C3 thành cầu nối giữa **máy chấm công ZKTeco đời cũ** (chỉ có
giao thức TCP 4370, không hỗ trợ máy chủ đám mây ADMS) và **máy chủ sboxhrm.com**.

```
[Máy chấm công ZKTeco]  ──TCP 4370 (nhị phân)──  [ESP32-C3]  ──HTTPS──  [sboxhrm.com /iclock/*]
       LAN dây                                      WiFi                   giao thức ADMS push
```

Đối với máy chủ, gateway trông y hệt một máy chấm công đời mới có ADMS: nó dùng đúng số seri
đọc được từ máy thật, tự đăng ký qua `/iclock/cdata`, đẩy chấm công lên `/iclock/cdata?table=ATTLOG`,
hỏi lệnh ở `/iclock/getrequest` và báo kết quả về `/iclock/devicecmd`. **Không cần sửa gì ở phía
máy chủ.**

## Yêu cầu

- Module ESP32-C3 có cổng USB (loại dùng USB Serial/JTAG tích hợp, VID `303A`).
- Máy chấm công ZKTeco nối cùng mạng LAN với WiFi mà ESP32-C3 sẽ vào, đã bật cổng 4370.
- ESP-IDF v5.5.x.

Không cần đấu nối dây gì thêm: ESP32-C3 chỉ cần nguồn USB 5 V và nằm trong vùng phủ WiFi.

## Biên dịch và nạp

ESP-IDF không chạy được với đường dẫn chứa dấu cách. Kho mã này nằm trong `E:\SBOX CURSOR\...`,
nên hãy build qua một junction không dấu cách:

```powershell
cmd /c mklink /J E:\zkgw "E:\SBOX CURSOR\ZKTecoADMS-master\firmware\esp32c3-zk-gateway"

$env:IDF_TOOLS_PATH = "E:\esp\tools"
. E:\esp\esp-idf\export.ps1
cd E:\zkgw
idf.py set-target esp32c3
idf.py build
idf.py -p COM3 flash
```

Xem log mà không cần mở monitor tương tác:

```powershell
python tools\serial_log.py COM3 20 --reset
```

## Cấu hình lần đầu

Có hai đường: dùng app SBOX trên điện thoại (dễ hơn, xem mục dưới) hoặc mở trang web của
chính thiết bị.

1. Cấp nguồn cho ESP32-C3. Khi chưa có cấu hình, nó phát WiFi riêng tên `SBOX-Gateway-XXXX`,
   mật khẩu `sbox12345`.
2. Nối điện thoại/laptop vào mạng đó rồi mở `http://192.168.4.1`.
3. Điền: tên gợi nhớ cho gateway, tên và mật khẩu WiFi của công ty, IP máy chấm công trong
   LAN, địa chỉ máy chủ (`https://sboxhrm.com`), Comm Key nếu máy có đặt.
4. Bấm **Lưu cấu hình**. Gateway sẽ vào WiFi, đọc số seri của máy chấm công và tự đăng ký lên
   máy chủ.

Sau khi đã vào được WiFi công ty, trang cấu hình vẫn truy cập được theo IP LAN mà router cấp
(xem mục Trạng thái trên chính trang đó, hoặc log serial). Nếu mất WiFi quá 60 giây, gateway
tự bật lại điểm phát cấu hình để bạn sửa.

## Cài đặt và quản lý bằng app SBOX

App Flutter có mục **Thiết lập HRM → Gateway WiFi** làm toàn bộ việc này bằng trình hướng dẫn
bốn bước, không cần nhớ địa chỉ IP nào.

Để app tìm được thiết bị, firmware quảng bá qua hai kênh song song — cố tình dư thừa vì mỗi
kênh hỏng theo một cách khác:

| Kênh | Chi tiết | Khi nào cần |
|---|---|---|
| mDNS | `sbox-gateway-XXXX.local`, dịch vụ `_sboxgw._tcp` cổng 80 | Máy tính, iPhone trong mạng thường |
| Quảng bá UDP | App gửi `SBOX_DISCOVER` tới cổng `51820`, thiết bị trả một dòng JSON | Khi router chặn multicast giữa các client |

Rất nhiều router bật chế độ cách ly thiết bị làm mDNS im lặng hoàn toàn, lúc đó kênh UDP vẫn
tới. Nếu cả hai đều bị chặn, app cho nhập IP trực tiếp.

Kiểm tra kênh UDP từ máy tính:

```powershell
python tools\discover.py --timeout 5
```

## API HTTP của thiết bị

| Endpoint | Việc |
|---|---|
| `GET /api/info` | Thẻ tên gọn: sản phẩm, phiên bản, tên, số seri, IP, tình trạng kết nối |
| `GET /api/status` | Trạng thái đầy đủ: WiFi, máy chấm công, máy chủ, số liệu đồng bộ |
| `GET /api/config` | Cấu hình hiện tại (không trả mật khẩu WiFi, chỉ trả `hasWifiPass`) |
| `POST /api/config` | Lưu cấu hình. Chỉ ghi những khoá có trong JSON, khoá thiếu giữ nguyên |
| `GET /api/scan` | Danh sách WiFi do chính gateway quét được |
| `POST /api/action?do=…` | `resync`, `users`, `clock`, `resetmark`, `reboot` |
| `POST /api/ota` | Nạp firmware, thân yêu cầu là tệp `.bin` |

`POST /api/config` chỉ ghi các khoá xuất hiện trong JSON, nên gửi `{"gwName":"Cửa trước"}` là
đổi được tên mà không đụng tới WiFi — và cũng không làm rớt kết nối, vì firmware chỉ nối lại
WiFi khi SSID hoặc mật khẩu thật sự thay đổi.

`GET /api/status` mang thêm ba số liệu để chẩn đoán từ xa khi không có cáp nối máy tính:

- `resetReason` — vì sao mạch khởi động lại lần gần nhất. Phân biệt được mất nguồn
  (`sut dien ap`, `bat nguon`) với lỗi phần mềm (`phan mem sap`, `treo tac vu`), hai nhóm
  nguyên nhân cần cách xử lý hoàn toàn khác nhau.
- `heap` và `heapMin` — bộ nhớ còn trống hiện tại và mức thấp nhất từ lúc khởi động.
  `heapMin` tụt dần qua nhiều giờ là dấu hiệu rò rỉ bộ nhớ.

Lưu ý khi đọc `uptime` và các bộ đếm trong `sync`: tất cả đều tính từ lần khởi động gần nhất,
nên giá trị nhỏ đi so với lần đọc trước có nghĩa là mạch vừa khởi động lại.

## Ghép máy vào cửa hàng trên sboxhrm.com

Lần đầu gateway liên lạc, máy chủ tạo một thiết bị ở trạng thái *Pending* với số seri đọc được
từ máy chấm công. Vào phần Quản lý thiết bị trên sboxhrm.com, thêm thiết bị theo số seri đó và
gán vào cửa hàng. Trước khi được gán cửa hàng, máy chủ vẫn trả `OK` nhưng **bỏ qua dữ liệu**.

## Cách đồng bộ chấm công hoạt động

Giao thức TCP 4370 không cho phép đọc log theo mốc thời gian, chỉ đọc được toàn bộ. Để không
kéo cả log mỗi vòng, gateway làm như sau:

- Mỗi `attlogInterval` giây (mặc định 30) chỉ gửi đúng một lệnh `GET_FREE_SIZES` để lấy số bản
  ghi hiện có. Nếu số này không đổi thì dừng, gần như không tốn gì.
- Khi số bản ghi tăng, gateway đọc cả log theo kiểu chia mảnh (không nạp hết vào RAM) và chỉ
  đẩy lên những bản ghi mới hơn *mốc nước cao* đã lưu trong NVS.
- Mốc nước cao gồm thời điểm của bản ghi cuối cùng và số bản ghi mang đúng thời điểm đó, nên
  nhiều người chấm trong cùng một giây vẫn không bị sót hay trùng.
- Mốc chỉ được ghi lại sau khi **mọi lô** đã lên máy chủ thành công. Nếu mạng đứt giữa chừng,
  vòng sau gửi lại từ đầu; máy chủ tự loại bản trùng theo `DeviceId + PIN + thời gian`.

Lần đồng bộ đầu tiên chỉ lấy log trong `backfillDays` ngày gần nhất (mặc định 30) để tránh
dội cả nhiều năm lịch sử lên máy chủ. Đặt 0 nếu muốn lấy hết.

Khi quản trị viên bấm “Đồng bộ chấm công” trên web, máy chủ trả `ATTLOGStamp=0`; gateway hiểu
đó là yêu cầu gửi lại toàn bộ và kết thúc bằng một POST rỗng đúng như máy ADMS thật.

## Lệnh từ máy chủ

| Lệnh ADMS | Việc thực hiện trên máy chấm công |
|---|---|
| `DATA UPDATE USERINFO PIN=…` | Ghi/sửa nhân viên (`CMD_USER_WRQ`), tự dò cỡ gói 28 hay 72 byte |
| `DATA DELETE USERINFO PIN=…` | Xoá nhân viên (`CMD_DELETE_USER`) |
| `DATA DELETE USERINFO` (không PIN) | Xoá toàn bộ dữ liệu (`CMD_CLEAR_DATA`) |
| `DATA QUERY USERINFO` | Đọc danh sách nhân viên rồi đẩy lên `table=OPERLOG` |
| `DATA QUERY ATTLOG …` | Đọc toàn bộ log rồi đẩy lên `table=ATTLOG` |
| `AC_UNLOCK` | Mở cửa 5 giây (`CMD_UNLOCK`) |
| `CONTROL DEVICE 01xx01yy` | Mở cửa `yy` giây (đọc từ hex) |
| `CLEAR LOG` | Xoá log chấm công (`CMD_CLEAR_ATTLOG`) |
| `CLEAR ALL USERINFO` / `CLEAR DATA` | Xoá toàn bộ dữ liệu |
| `REBOOT` | Khởi động lại máy (`CMD_RESTART`) |
| `SET OPTION` / `SET TIME` | Chỉnh đồng hồ máy theo giờ NTP |
| `INFO` / `CHECK` | Trả về thành công (thông tin máy đã gửi kèm mỗi vòng poll) |
| `ENROLL_FP PIN=… FID=…` | Mở đăng ký vân tay ngay trên máy (`CMD_STARTENROLL`) |
| `DATA DELETE FINGERTMP PIN=… FID=…` | Xoá mẫu vân tay; thiếu `FID` thì xoá cả 10 ngón |

Kết quả mọi lệnh đều được báo về `/iclock/devicecmd` với `Return=0` khi thành công.

### Đăng ký vân tay từ xa

Máy chấm công phải hiện giao diện "đặt ngón tay" và chờ người thật quét, nên lệnh này
khác mọi lệnh còn lại: gateway **giữ kết nối TCP tới 45 giây** cho người dùng quét xong.
Đóng socket giữa đường sẽ làm máy huỷ phiên đăng ký, nên không thể "gửi rồi bỏ đó".

Hệ quả cần biết:

- Cả vòng poll của gateway dừng trong lúc chờ, việc đẩy chấm công bị lùi lại tối đa 45 giây.
- Người cần đăng ký phải **đứng sẵn tại máy** trước khi bấm lệnh, vì cửa sổ chờ bắt đầu
  ngay khi gateway nhận lệnh (chậm nhất 10 giây sau khi máy chủ tạo lệnh).
- Mã trả về phân biệt rõ ba tình huống: `0` đăng ký xong, `-4` đã mở được nhưng không lấy
  được nét vân tay, `-1` máy từ chối (firmware máy không có chức năng này).

Kết quả được xác định bằng cách **đếm lại số mẫu vân tay trên máy**, không bằng cách đọc mã
trong gói sự kiện. Lý do: các gói đó cũng phát ra khi quét lỗi, nên suy từ mã sẽ báo thành
công sai — điều tệ hơn nhiều so với báo thất bại sai.

Khi lệnh có `OVERWRITE=1` (máy chủ luôn gửi cờ này), gateway xoá mẫu cũ của đúng ngón đó
trước khi mở đăng ký, để đăng ký thành công thì số mẫu chắc chắn tăng đúng 1. Đánh đổi phải
biết: **quét không thành công thì ngón đó mất mẫu cũ** và người dùng phải đăng ký lại. Bỏ cờ
`OVERWRITE` thì mẫu cũ được giữ nguyên, đổi lại đăng ký lại một ngón đã có sẽ báo `-4` vì
tổng số mẫu không đổi.

Lệnh xoá mẫu cũng đối chiếu số mẫu vì máy trả ACK OK cả khi ngón đó vốn trống. Xoá một ngón
không có mẫu được coi là thành công, vì trạng thái mong muốn đã đạt.

### Chưa hỗ trợ

`ENROLL_BIO` (khuôn mặt), `DATA QUERY FINGERTMP` và `DATA DELETE FACE` trả về `Return=-1`.
Máy standalone không xuất được mẫu sinh trắc ra ngoài, và dòng máy chỉ có cảm biến vân tay
thì không có phần cứng khuôn mặt để đăng ký. Dữ liệu vân tay vẫn nằm nguyên trên máy.

## Thao tác trên trang cấu hình

- **Đồng bộ lại toàn bộ chấm công** — bỏ qua mốc nước cao cho một lần chạy.
- **Đẩy danh sách nhân viên** — gửi toàn bộ nhân viên trên máy lên `table=OPERLOG`.
- **Chỉnh giờ máy chấm công** — ghi giờ NTP xuống máy (gateway cũng tự làm mỗi 12 tiếng).
- **Xoá mốc đồng bộ** — xoá mốc trong NVS rồi gửi lại tất cả từ đầu.
- **Nạp firmware** — cập nhật OTA bằng tệp `build/zk_gateway.bin`, có hai phân vùng OTA nên
  bản cũ vẫn còn nếu bản mới không khởi động được.

## Xử lý sự cố

| Hiện tượng | Nguyên nhân thường gặp |
|---|---|
| `khong ket noi duoc may cham cong` | Sai IP, máy khác dải mạng với WiFi, hoặc cổng 4370 bị tắt |
| `xac thuc that bai - kiem tra Comm Key` | Máy có đặt Comm Key, cần điền đúng số vào cấu hình |
| `khong doc duoc so seri` | Firmware máy quá cũ; điền tay số seri vào ô “Số seri gửi lên máy chủ” |
| `server tra ve FAIL` | Thiết bị chưa được gán vào cửa hàng trên sboxhrm.com |
| Log lên máy chủ nhưng không thấy trong báo cáo | PIN trên máy chưa khớp nhân viên nào trong hệ thống |

Một máy chấm công ZKTeco thường chỉ chấp nhận một kết nối SDK tại một thời điểm. Gateway mở
kết nối theo từng việc rồi đóng ngay, nhưng nếu bạn đang mở phần mềm ZKTeco trên PC cùng lúc
thì hai bên sẽ tranh nhau.

## Cấu trúc mã nguồn

| Tệp | Vai trò |
|---|---|
| `main/zk_proto.c` | Khung gói TCP 4370, checksum, phiên, đọc khối dữ liệu lớn theo mảnh |
| `main/zk_client.c` | Thao tác mức cao: đọc seri, log chấm công, nhân viên, ghi/xoá nhân viên, mở cửa |
| `main/adms_client.c` | Bên client của giao thức ADMS push, giữ lại một kết nối HTTPS dùng chung |
| `main/cmd_exec.c` | Dịch lệnh ADMS sang thao tác ZK |
| `main/gateway.c` | Vòng lặp chính, mốc nước cao, gom lô dữ liệu |
| `main/wifi_mgr.c` | WiFi STA, tự bật điểm phát cấu hình khi mất mạng |
| `main/web_portal.c` + `main/portal.html` | Trang cấu hình, giám sát và nạp OTA |
| `main/discovery.c` | mDNS và bộ trả lời quảng bá UDP để app tự tìm thiết bị |

Phía app tương ứng nằm ở `flutter_client/lib/screens/gateway/` (giao diện),
`lib/services/zk_gateway_client.dart` (gọi API) và `lib/models/zk_gateway.dart` (dữ liệu).
Phần dò tìm tách thành `zk_gateway_discovery_io.dart` / `_stub.dart` sau conditional import,
vì `dart:io` không tồn tại trên web và chỉ cần import là bản build web đứt.
