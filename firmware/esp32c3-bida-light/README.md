# SBOX Đèn bàn bi-a (ESP32-C3 + relay)

Bộ ESP32-C3 đóng/ngắt relay cấp điện cho đèn trên từng bàn bi-a, theo trạng thái bàn trên POS SBOX:

- **Mở bàn** trên app → đèn bàn đó **sáng**.
- **Thanh toán** (phiên bàn đóng) → đèn **tắt**.
- Bàn đang **tạm dừng giờ**: mặc định vẫn sáng, đổi được trong app.

```
[App POS: mở bàn / thanh toán] ──► [sboxhrm.com] ◄──HTTPS hỏi mỗi 2 giây── [ESP32-C3] ──GPIO──► [Relay] ──► Đèn bàn
```

Thiết bị chủ động hỏi máy chủ (`GET /api/pos/bida-light/state?key=…`) nên không cần mở cổng router
và không cần IP tĩnh. Máy chủ gom các lần hỏi lại, mỗi cửa hàng tối đa 1 truy vấn CSDL / 1,5 giây.
Mở bàn hoặc thanh toán thì chậm nhất khoảng 2–3 giây đèn mới đổi.

## Bật trên app

**Thiết lập SBOX → Bán hàng → Đèn bàn bi-a**:

1. Bật **Bật điều khiển đèn**.
2. Bấm **Sao chép khóa**. Khóa có dạng `<mã cửa hàng 32 ký tự>-<bí mật>`.
3. **Đổi khóa** khi nghi lộ khóa: bộ relay dùng khóa cũ bị từ chối ngay.

Một cửa hàng dùng được nhiều bộ relay với cùng một khóa: ví dụ mỗi tủ điện một bộ 8 kênh.

## Đấu nối

| Kênh | GPIO mặc định | | Kênh | GPIO mặc định |
|---|---|---|---|---|
| 1 | 0 | | 5 | 5 |
| 2 | 1 | | 6 | 6 |
| 3 | 3 | | 7 | 7 |
| 4 | 4 | | 8 | 10 |

Kênh 9, 10 dùng được GPIO 20, 21 (mặc định tắt). GPIO21 là chân TX nên relay trên đó có thể nháy
một chút lúc khởi động. Chân đổi được trên trang cấu hình.
Không dùng GPIO 2, 8, 9 (chân khởi động) và 18, 19 (cổng USB).

- Module relay 5V loại phổ biến (có opto, chân `IN1..IN8`) là loại **kích mức thấp**: giữ nguyên ô
  «Module relay kích mức thấp». Nối `VCC` 5V, `GND` chung với ESP32-C3, `INx` vào GPIO.
- Nếu module có jumper `JD-VCC`, cấp 5V riêng cho cuộn relay để nhiễu khi đóng ngắt không làm
  ESP32-C3 khởi động lại.
- Đèn bàn bi-a dùng điện 220V. Đấu tiếp điểm `COM`/`NO` để **mất điện ESP thì đèn tắt**. Muốn ngược
  lại (ESP hỏng thì đèn vẫn sáng), đấu `COM`/`NC` và bỏ chọn «kích mức thấp».
- Phần 220V phải do thợ điện làm: có CB / cầu chì cho từng nhánh, relay chịu được dòng của đèn
  (đèn LED bàn bi-a thường dưới 1 A, nhưng dòng khởi động của driver LED cao hơn nhiều).

## Biên dịch và nạp

ESP-IDF không chạy được với đường dẫn có dấu cách, nên build qua một junction:

```powershell
cmd /c mklink /J E:\bidalight "E:\SBOX CURSOR\ZKTecoADMS-master\firmware\esp32c3-bida-light"

$env:IDF_TOOLS_PATH = "E:\esp\tools"
. E:\esp\esp-idf\export.ps1
cd E:\bidalight
idf.py set-target esp32c3
idf.py build
idf.py -p COM3 flash monitor
```

## Cài bằng app qua Bluetooth (khuyên dùng)

Giống gateway chấm công: điện thoại vẫn giữ WiFi / 4G của mình, không phải đổi sang WiFi của thiết bị.

1. App SBOX trên điện thoại → **Thiết lập → Bán hàng → Đèn bàn bi-a** → **Cài bộ đèn qua Bluetooth**.
2. Chọn thiết bị `SBOX-Den-XXXX` trong danh sách dò được.
3. Nhập WiFi quán (2.4 GHz). App tự gửi khóa thiết bị; bộ đèn vào WiFi rồi thử hỏi máy chủ, báo OK mới sang bước sau.
4. **Gán đèn cho bàn**: mỗi kênh bấm **Thử đèn** → relay kênh đó bật 3 giây, nhìn đèn bàn nào sáng thì
   chọn bàn đó. Nút **Gán theo thứ tự** điền nhanh kênh 1 ← bàn đầu tiên trên sơ đồ, kênh 2 ← bàn kế tiếp…
   Đổi được chân GPIO từng kênh và số kênh.
5. **Lưu vào bộ đèn** — áp dụng ngay, không khởi động lại.

Bluetooth chỉ bật khi: chưa cài đặt, 10 phút đầu sau khi cấp điện, hoặc đang mất WiFi. Muốn sửa gán đèn sau
này mà không rút điện: **nhấn nhanh nút BOOT** trên mạch để mở Bluetooth thêm 10 phút. Đã đặt mật khẩu
quản lý trên trang web thì app sẽ hỏi mật khẩu đó.

## Cấu hình qua trang web (không cần app)

1. Cấp nguồn. Khi chưa cấu hình, thiết bị phát WiFi `SBOX-Den-XXXX`, mật khẩu `sbox12345`.
2. Nối điện thoại vào WiFi đó, mở `http://192.168.4.1`.
3. Điền tên WiFi quán (chỉ **2.4 GHz**), mật khẩu, dán **khóa thiết bị**, đặt mật khẩu cho trang này.
4. Mỗi kênh gõ **mã bàn** giống hệt trong Sơ đồ bàn (ví dụ `B01`). Sau lần hỏi máy chủ đầu tiên, ô mã bàn
   có gợi ý danh sách bàn của cửa hàng.
5. Bấm **Lưu & khởi động lại**. Sau khi vào WiFi quán, trang quản lý ở `http://<IP thiết bị>`
   (IP in trong log serial và trên trang của router).

Nếu mất WiFi quá 60 giây, thiết bị tự phát lại `SBOX-Den-XXXX` để sửa cấu hình. Đèn vẫn giữ trạng thái cũ.

## Trên trang quản lý

- Mỗi kênh có 3 chế độ: **Tự động** (theo POS), **Bật** (giữ sáng để dọn bàn / sửa), **Tắt**.
  Chế độ tay được lưu lại qua khởi động lại; bấm **Tự động** để trả về POS.
- Kênh có mã bàn mà POS không có bàn đó → báo «⚠ POS không có bàn này».
- **Mất máy chủ quá N phút thì tắt hết**: mặc định `0` = giữ nguyên trạng thái, không tắt đèn khi khách
  đang chơi mà mạng rớt.

## Hành vi khi sự cố

| Tình huống | Đèn |
|---|---|
| Mất điện rồi có điện lại | Khôi phục trạng thái đã lưu ngay khi khởi động, rồi theo máy chủ |
| Mất WiFi / máy chủ | Giữ nguyên (hoặc tắt sau N phút nếu đã cài) |
| Khóa sai / bị đổi / tắt tính năng trên app | Giữ nguyên, trang quản lý báo «May chu tu choi khoa» |

## Xóa cấu hình

Giữ nút **BOOT** (GPIO9) 5 giây khi thiết bị đang chạy, hoặc bấm **Xóa cấu hình** trên trang quản lý.
