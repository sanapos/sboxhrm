# Báo cáo: Dịch vụ tính tiền theo thời gian (karaoke, bi-a, phòng giờ)

Nhánh `fix/tingee-agent-scope-deploy`. Sửa cả máy chủ (API), app SBOX (flutter_client) và app POS (flutter_pos).
**Chưa deploy, chưa build** — chờ anh/chị duyệt.

Ảnh màn thiết lập mới: `timed_setup_1100.png` (máy tính) và `timed_setup_390.png` (điện thoại), cùng thư mục với báo cáo này.

---

## Lỗi 1 — Đồng hồ tính giờ «lúc chạy lúc không»

**Nguyên nhân (2 chỗ):**

1. **Đồng hồ chỉ nhảy khi số tiền đổi.** Máy kiểm tra giờ 5 giây một lần, nhưng chỉ vẽ lại màn hình khi số lượng tính tiền thay đổi.
   Với block 15 phút, số block chỉ đổi 15 phút một lần, nên dòng «Từ 19:05 · 23p» đứng im suốt 15 phút.
   Chỉ khi thu ngân bấm gì đó trên màn thì nó mới nhảy. Vì thế nhìn như «lúc chạy lúc không».
2. **Đổi hóa đơn là tắt bộ đếm.** Bộ đếm chỉ xét hóa đơn đang mở. Mở sang hóa đơn không có giờ (bán nước lẻ chẳng hạn) là bộ đếm tắt.
   Quay lại phòng hát thì số tiền đứng yên tới khi có thao tác khác.

**Đã sửa:**
- Dòng giờ giờ có đồng hồ riêng, tự nhảy **từng giây** (`⏱ Từ 19:05 · 23:41`). Khi tạm dừng hay kết thúc thì đồng hồ đứng.
- Bộ đếm chạy khi **bất kỳ** hóa đơn nào còn phòng/bàn đang tính giờ. Đổi hóa đơn thì tính lại tiền ngay, không chờ 5 giây.
- Cách tính tiền vẫn như cũ: theo phút, khớp máy chủ. Giây chỉ để hiển thị.

## Lỗi 2 — Tiền tính theo block nhưng đơn vị hiện «cái»

**Nguyên nhân:** Hàng hóa tạo mới mặc định có đơn vị tính (ĐVT) là «Cái». Dịch vụ tính giờ cũng nhận ĐVT này.
Khi bán, số lượng là số giờ/block (ví dụ 3 block) nhưng dòng hóa đơn lấy ĐVT «Cái», nên hiện «3 cái».

**Đã sửa:**
- ĐVT của dịch vụ tính giờ tự đặt theo cách tính: **Giờ / Phút / Block / Ngày**.
- Nếu chủ quán đã tự đặt ĐVT riêng thì giữ nguyên (ví dụ «Đêm» cho khách sạn). Chỉ thay khi ĐVT đang là «Cái» hoặc để trống.
- Áp ở 3 chỗ, nên **hàng cũ cũng hiện đúng** mà không cần sửa lại từng món:
  - lúc lưu hàng;
  - lúc lưu đơn và mở bàn tự thêm giờ (máy chủ);
  - trên giỏ hàng và hóa đơn in (app).

## Việc 3 — Màn thiết lập gói dịch vụ tính giờ (làm lại theo POS365)

### So sánh với POS365

| POS365 | SBOX trước | SBOX bây giờ |
|---|---|---|
| ☑ Số lượng tính theo thời gian sử dụng? | Danh sách 6 «Cách tính giá» (cố định, giờ, phút, buổi, block, ngày) | **Có ô tích y hệt.** Quán karaoke/bi-a: dịch vụ mới tự tích sẵn, block 15 phút |
| Giá bán | Ô giá nằm ở mục khác («Giá vốn, giá bán»), xa phần tính giờ | Ô giá nằm ngay trong phần tính giờ. Ghi rõ «Giá bán (1 giờ)» hay «(1 block 15 phút)», kèm dòng quy đổi «1 giờ = 120.000đ, tức 1 block 15 phút = 30.000đ» |
| ☐ Giá bán được thiết lập cho từng block? | Phải chọn «Theo block» trong danh sách, thêm ô «Nhập theo giá 1 giờ» | **Có ô tích y hệt.** Tích/bỏ tích thì máy **tự quy đổi giá** (120.000đ/giờ ↔ 30.000đ/block), không bị nhập nhầm |
| Block tính thời gian sử dụng (phút) = 15 | «Mỗi block» / «Làm tròn» tùy chế độ, mặc định 5 | Một ô duy nhất, **mặc định 15** |
| Số block giờ đầu tiên + Giá cho N block giờ đầu tiên | «Phí mở phòng/bàn» + «Phút gồm trong phí mở» (nhập theo phút) | **Khung xanh giống POS365**: nhập số block. Tên ô tự đổi thành «Giá cho 4 block giờ đầu tiên». Có ghi chú «Để trống nếu không dùng» |
| Thiết lập khung giờ đặc biệt (Từ – Đến, ±, % / giá trị) | **Chưa có** | **Mới.** Thêm được nhiều khung: Từ giờ, Đến giờ (qua đêm được, vd 22:00–02:00), Tăng/Giảm, theo % hoặc số tiền mỗi giờ/block |
| Giá vốn, ĐVT, Báo chế biến, Extra/Topping, Không in tem | Đã có ở các mục khác | Giá vốn, topping, báo chế biến (máy in) giữ ở mục cũ. **ĐVT ẩn đi** với dịch vụ tính giờ vì máy tự đặt. «Không in tem» chưa có trên SBOX (dịch vụ giờ không cần in tem ly), chưa làm |

### Cách chạy của khung giờ đặc biệt

Phần thời gian của khách rơi vào khung nào thì cộng hoặc trừ theo khung đó.

Ví dụ: giá 60.000đ/giờ, khung 18:00–23:00 tăng 50%. Khách vào 17:30, về 19:30:
- 30 phút trước 18:00 tính giá thường;
- 90 phút sau 18:00 được cộng thêm 45.000đ.

Ngoài ra:
- Phần đã gồm trong «giá N block giờ đầu» thì không cộng/trừ thêm.
- Khách sạn tính theo đêm thì không áp khung giờ.
- Giới hạn: lúc tạm dừng giữa chừng, giờ tính khung lấy theo giờ bắt đầu cộng số phút đã dùng (không lùi theo lúc tạm dừng).

### Gọn hơn

- Bỏ ô «Nhập theo giá 1 giờ (tự tính giá block)». Ô tích «từng block» đã tự quy đổi giá.
- Bỏ danh sách 6 cách tính. Quán spa/gym bỏ tích tính giờ thì vẫn chọn được «Giá cố định / Theo buổi».
- «Phút miễn đầu giờ», «Tính tối thiểu», «Chỉ làm tròn khi quá …» gom vào **Tùy chọn nâng cao (ít dùng)**.
- Bảng xem trước đổi sang lời dễ hiểu: «Khách dùng 1 giờ 30 phút → hóa đơn 0,5 giờ + giờ đầu → 160.000đ».
- Ô «Thời lượng mặc định» chỉ hiện với dịch vụ không tính giờ.

---

## Kiểm tra (test)

- **.NET:** 26 test tính giờ qua, thêm mới:
  - ĐVT không còn «cái» (8 trường hợp);
  - khung giờ: tăng %, giảm theo tiền/block, khung qua đêm, dữ liệu hỏng.
- **.NET toàn bộ:** 950/954 qua. 4 bài lỗi có từ trước, không dính tới việc này:
  - 3 bài GymDoorTests (phụ thuộc giờ chạy);
  - 1 bài `PosQuoteDocumentTests.Gia_da_gom_VAT…` (mẫu báo giá).
- **Flutter** (`flutter_client/test/pos_timed_service_setup_test.dart` + test tính giờ cũ): 17/17 qua.
  - Công thức khung giờ cho ra đúng số như máy chủ.
  - Đồng hồ tự nhảy từng giây, khi tạm dừng thì đứng.
  - Tích «từng block» quy đổi 120.000đ → 30.000đ; 2 block đầu → 30 phút; thêm khung 18:00–23:00 +20% lưu đúng; bỏ tích về giá cố định.
  - Chụp ảnh màn điện thoại và máy tính, không lỗi giao diện.
- `flutter analyze` cả 2 app: không có lỗi.

## Cần làm khi deploy

- Máy chủ tự thêm cột `PosProducts.TimeSurchargesJson` khi khởi động (SchemaPatches). Cần deploy API **trước** rồi mới đến web/app.
- Chưa thử trên máy thật C20Lite.
