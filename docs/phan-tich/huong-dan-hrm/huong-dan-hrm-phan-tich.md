# Hướng dẫn nghiệp vụ SBOX HRM: bản phân tích đã đối chiếu code (30/10/2026)

Repo: `E:\SBOX CURSOR\ZKTecoADMS-master`. Viết tắt: FL = `flutter_client/lib`, BE = `src`.
Tài liệu này chỉ để phân tích, chưa sửa file nào trong repo. Phiên «Hướng dẫn sử dụng trang chủ với hình ảnh» đang làm `landing_usage_guide.dart`, `web/guide.html`, ảnh `guide_shots`.

## 0. Quy ước đường đi (quan trọng khi viết hướng dẫn)

- Thứ tự nhóm menu: Tổng quan › Hồ sơ nhân sự › Chấm công › Tài chính › Quản lý Vận hành › POS › Báo cáo kinh doanh › Báo cáo nhân sự › Đại lý › Cài đặt (`main_layout.dart:3700`).
- **Sidebar trên máy tính ẩn các mục có `showInSidebar:false`** (`main_layout.dart:3732`). Các mục bị ẩn: Hồ sơ nhân sự, Phòng ban, Thiết lập lương, Nghỉ phép, Chấm công thô, Ca làm việc, Duyệt chấm công, Duyệt lịch làm việc, Đổi ca làm việc, Nhân sự chấm công. Trên máy tính, các mục này chỉ mở được qua ô ở **Trang chủ** hoặc ô **tìm chức năng**. Drawer trên điện thoại vẫn hiện đủ.
- Không có mục menu tên «Tính lương». Màn tính và chốt lương là **Báo cáo nhân sự › Tổng hợp lương**.
- «Quản lý tăng ca» không có trong menu. Chỉ mở được qua ô «Tăng ca» trên Trang chủ của nhân viên, nút trên Dashboard, thông báo hoặc trợ lý AI.
- «Thiết lập lương» không nằm trên sidebar. Cách mở: ⋮ trên thẻ nhân viên ở Hồ sơ nhân sự (nhãn đang ghi tiếng Anh **«Salary Settings»**, `employees_screen.dart:2251`), hoặc từ Tổng hợp lương.
- Hướng dẫn hiện có (`landing_usage_guide.dart`) còn ghi «Cài đặt → Thiết lập ca / Máy chấm công / Phạt / Bảo hiểm / Tài khoản / Phân quyền / Ngày lễ / Chấm công mobile». Cách ghi này **sai quy ước**: «Cài đặt» là trang cá nhân. Phải đổi thành «Thiết lập SBOX › <nhóm> › <mục>».

## 1. Tạo ca làm việc

**Đường đi**
- Thiết lập SBOX › Nhân sự & chấm công › **Ca làm việc** (quyền `ShiftSetup`).
- Hoặc menu **Ca làm việc** › tab «Thiết lập» › «Ca mẫu».

**Quyền**: thêm và nhân bản cần quyền Thêm; sửa và ngừng dùng cần quyền Sửa; xóa cần quyền Xóa.

**Các bước**
1. Bấm «Thêm ca». Có thể chọn «Mẫu nhanh»: Hành chính 08–17 (nghỉ 12–13), Ca sáng 06–14, Ca chiều 14–22, Ca đêm 22–06, Ca gãy 10–21 (nghỉ 14–17), Tăng ca tối 18–21.
2. Mục «Giờ ca»:
   - «Tên ca *», «Mã ca» (để trống thì tự lấy theo tên).
   - «Loại ca»: Hành chính / Tăng ca (toàn bộ giờ là tăng ca) / Qua đêm.
   - «Giờ vào», «Giờ ra». Giờ ra nhỏ hơn giờ vào thì app hiện «hôm sau» và tự chuyển loại ca sang Qua đêm.
   - «Nghỉ giữa ca»: Không nghỉ / Khung giờ cố định / Linh hoạt (số phút, tối đa 240).
3. Mục «Quy tắc chấm công» (mỗi lần bấm ±5 phút). Mặc định:

   | Trường | Mặc định |
   |---|---|
   | Nhận chấm sớm | 60 |
   | Miễn trễ | 5 |
   | Giới hạn đi trễ | 30 |
   | Miễn về sớm | 5 |
   | Giới hạn về sớm | 30 |
   | Tăng ca trước ca | 30 |
   | Tăng ca sau ca | 30 |

   «Nhận chấm sớm» phải lớn hơn «Tăng ca trước ca».
4. Mục «Trạng thái & ghi chú». Bấm «Lưu ca».
5. Muốn có lương ca: **mở lại ca vừa lưu** › «Lương ca» › «Thêm mức lương». Chọn kiểu Cố định / ca, Nhân hệ số hoặc Theo giờ. Áp dụng cho tất cả nhân viên hoặc chọn từng người.

**Lỗi thường gặp**
- «Nhập tên ca».
- «Giờ vào trùng giờ ra…». Có nút đặt ca gần 24 giờ.
- «Khung nghỉ giữa ca nằm ngoài giờ ca».
- «Tăng ca trước ca (N phút) cần «Nhận chấm sớm» ít nhất N+1 phút».
- Sửa ca đang có lịch: hộp «Đổi giờ / quy tắc của ca đang dùng?». Nên «Nhân bản» thay vì sửa trực tiếp.
- Không xóa được ca đã có dữ liệu. Dùng «Ngừng dùng»: lịch cũ giữ nguyên, ca bị ẩn khi xếp ca mới.

**Điểm yếu**
- Lương ca chỉ thêm được sau khi đã lưu ca.
- Thiết lập lương lưu ca theo **tên**. Đổi tên ca thì hồ sơ lương hiện «(ca đã xóa / đổi tên)».
- Tên gọi không thống nhất: «Ca mẫu» / «Ca làm việc»; «Bậc lương ca» / «mức lương ca».

## 2. Thiết lập lương

**Bước 0: chính sách chung.** Thiết lập lương › nút «Chính sách lương» › hộp «Chính sách tính lương»:
- Theo luật / Tùy chỉnh.
- Hệ số tăng ca ×1,5 / ×2 / ×3.
- Trả lương ngày lễ; trả lương ngày nghỉ có lương đã duyệt.
- Phụ cấp làm đêm; BHXH tháng nghỉ dài.

**Bước 1: chính sách cấp cửa hàng** (Thiết lập SBOX › Lương & chính sách):
- **Phụ cấp**:
  - «Thêm phụ cấp» hoặc mẫu nhanh (Ăn trưa, Xăng xe, Điện thoại, Chuyên cần, Ca đêm).
  - «Cách tính»: Cố định hàng tháng / Theo ngày công / Theo giờ / Theo lần / Theo ca đủ công.
  - Có tùy chọn tính vào thuế TNCN và tính vào lương đóng BH.
  - Áp dụng cho tất cả hoặc chọn từng người.
- **Mức phạt**:
  - Đi trễ / Về sớm: 3 bậc. Phút tính **sau khi trừ phút miễn trễ của ca**.
  - Tái phạm trong tháng: 3 bậc.
  - Quên chấm công: mặc định 100.000. Nghỉ không phép: 500.000.
  - Cách thu: Trừ lương / Tiền mặt.
  - «Tự duyệt phạt sau kết ca»: mặc định 2 giờ.
  - Có khối «Tính thử».
- **Bảo hiểm**: tỷ lệ người lao động / doanh nghiệp; lương cơ sở, mức trần, vùng, lương tối thiểu vùng I–IV; nút «Dùng mức 2026».
- **Thuế TNCN**: giảm trừ bản thân và người phụ thuộc; biểu thuế 5 bậc. Số người phụ thuộc **của từng nhân viên** khai ở trang này (mục «Người phụ thuộc của nhân viên»), không phải trong Thiết lập lương.
- **Lương sản phẩm**: «Thêm nhóm» trước, sau đó «Thêm sản phẩm» và bảng đơn giá theo bậc (Từ SL / Đến SL / Đơn giá).

**Bước 2: từng nhân viên** (Thiết lập lương). Thẻ lọc «Chưa thiết lập». Mở ⋮ › «Thiết lập lương». Các khối:
1. **Lương chính**:
   - Tháng: Lương cơ bản + Lương hoàn thành.
   - Ngày: lương một ngày công.
   - Ca: cố định mỗi ca, hoặc «Theo bậc lương ca» lấy từ ca.
   - Giờ: lương một giờ.
2. **Tăng ca**: Theo luật / Cố định / Không tính; đơn giá giờ tính theo lương cơ bản / hoàn thành; cách tính đi làm ngày nghỉ.
3. **Bảo hiểm xã hội**:
   - Lương tháng: Không đóng / Theo lương cơ bản / Cơ bản + hoàn thành / Tối thiểu vùng / Mức khác.
   - Lương không phải tháng: chỉ có Không đóng / Tối thiểu vùng / Mức khác.
4. **Ngày công và chấm công**:
   - Ngày nghỉ hưởng lương.
   - **Cách chấm công**: Chấm vào và ra / Chỉ chấm vào / Chỉ chấm ra / Chấm bất kỳ trong ca / Chấm 2 lần trong ngày / Ca nguyên ngày / Không chấm công.
   - Ca làm việc (để trống = theo lịch phân ca).
   - Số giờ một công (mặc định 8).
   - Công chuẩn: Theo tháng / Cố định.
5. **Phụ cấp**: chỉ xem, phải gán ở mục Phụ cấp.
6. **Lương đi đường**.
7. **Nghỉ phép**: phép năm có lương (12), nghỉ không lương tối đa.

Khi sửa hồ sơ đã có: chọn «Sửa hồ sơ hiện tại» hoặc «Đổi lương từ ngày». Có «Lịch sử thay đổi lương».

**Bước 3: nhân rộng.** ⋮ › «Sao chép cho nhân viên khác». Có nút «Chọn người chưa thiết lập». Hồ sơ đã có sẽ bị ghi đè.

**KPI** (Quản lý Vận hành › KPI): Thiết lập › Tạo chu kỳ › Chỉ tiêu › Giao chỉ tiêu (Doanh thu / Điểm số, lương khi đạt 100%) › cập nhật số thực tế (tay / Excel / Google Sheet) › Khóa chu kỳ › Tính lương KPI › Duyệt lương.

**Sản lượng** (Quản lý Vận hành › Sản lượng): «Nhập sản lượng» (nhân viên, ngày, sản phẩm, số lượng) hoặc nhập Excel / Google Sheet. Tháng đã chốt lương thì không sửa được.

**Lỗi thường gặp**
- «Nhập lương cơ bản.», «Nhập mức lương đóng BHXH.», «Số công cố định từ 1 đến 31.»…
- Có «Thiếu chấm» hoặc không tính công: chọn sai Cách chấm công. Máy chỉ chấm 1 lần thì chọn «Chỉ chấm vào».
- Nghỉ phép báo «Chưa có quỹ phép năm (gắn hồ sơ lương trong Thiết lập lương)».

**Điểm yếu**
- Nhãn tiếng Anh «Salary Settings».
- Ước tính BHXH trên form cố định 10,5%, không lấy tỷ lệ trong trang Bảo hiểm.
- Sản phẩm tạo được ở 2 nơi (Lương sản phẩm có bậc giá; Sản lượng › Thêm sản phẩm chỉ có 1 đơn giá), dễ ghi đè nhau.
- Nhãn KPI «Chỉ tiêu (s?)» bị lỗi chữ (`kpi_screen.dart:3674`).

## 3. Kết nối máy chấm công ZKTeco (ADMS)

**Điều kiện**
- Gói dịch vụ giới hạn số máy (`MaxDevices`, mặc định 2). Vượt giới hạn thì báo «Cửa hàng đã đạt giới hạn {n} thiết bị…».
- Cần quyền `Device`.

**Các bước (phải làm đúng thứ tự)**
1. **Trên máy**: vào «Thiết lập liên kết → Máy chủ đám mây». Địa chỉ máy chủ `103.133.224.176`, Port `7070` (`device_setup_guide.dart`). Lưu, khởi động lại nếu máy yêu cầu.
2. Đợi máy gọi về máy chủ. Máy chủ tự ghi nhận SN ở trạng thái Pending. Khi chưa gán vào cửa hàng, dữ liệu chấm công **bị bỏ qua**.
3. **Trên SBOX**: Thiết lập SBOX › Nhân sự & chấm công › **Máy chấm công** › «Thêm thiết bị». Nhập «Serial Number *» (có nút quét mã), bấm «Kiểm tra Serial». Nhập «Tên thiết bị *», «Vị trí lắp đặt», «Mô tả». Bấm Thêm.
4. Kết quả «Kiểm tra Serial»:
   - «hợp lệ — máy đang Online»: thêm được ngay.
   - «chưa từng kết nối đến server»: làm lại bước 1.
   - «đã được sử dụng bởi cửa hàng khác»: liên hệ hỗ trợ.
5. Sau khi thêm, hệ thống tự kéo danh sách user đang có trên máy về.
6. Máy Online khi có tín hiệu trong vòng 2 phút gần nhất.
7. «Chi tiết» › «Điều khiển thiết bị»:
   - Khởi động lại.
   - Đồng bộ user.
   - Đồng bộ chấm công (kéo 5 năm).
   - Lấy thông tin.
   - Mở / Đóng cửa (nếu máy hỗ trợ).
   - **Xóa toàn bộ dữ liệu** (nguy hiểm).
8. Cho nhân viên chấm thử, kiểm tra ở Chấm công thô.

**Điểm yếu**
- Form thêm máy không có chi nhánh và múi giờ (múi giờ cố định +07:00).
- Màn ADMS không có nút «Đồng bộ giờ» / «Xóa log» như bên Gateway.
- Nút «Xóa toàn bộ dữ liệu» nằm chung hàng với các nút thường.
- Hướng dẫn hiện có (`landing_usage_guide.dart:92`) ghi «nhập SN hoặc quét mã» nhưng không nói phải cấu hình máy **trước**.

## 4. Gateway WiFi (máy đời cũ chỉ có LAN / TCP 4370)

**Gateway là gì**
- Mạch ESP32-C3, cấp nguồn USB 5V, dùng WiFi **2.4GHz**.
- Đọc SN của máy thật rồi gửi dữ liệu lên `https://sboxhrm.com`. Không cần dây RS485.

**Điều kiện**
- **Chỉ cấu hình được trên app điện thoại.** Trên web app báo «Hãy dùng app trên điện thoại».
- Cần biết IP của máy chấm công (xem menu Comm / Ethernet trên máy).

**Các bước**: Thiết lập SBOX › Gateway WiFi › «Thêm gateway». Trình hướng dẫn 4 bước «Chuẩn bị / Tìm thiết bị / Chọn WiFi / Hoàn tất»:
1. Tìm gateway:
   - Cách khuyên dùng: Bluetooth, tìm `SBOX-Gateway-XXXX`.
   - Cách cũ: nối WiFi `SBOX-Gateway-…` (mật khẩu `sbox12345`).
2. Nhập Tên WiFi, Mật khẩu, Tên gợi nhớ, «IP máy chấm công trong LAN», Comm Key (để 0 nếu máy không đặt). Bấm «Lưu và kết nối».
3. Màn hoàn tất hiện «Gateway đã lên mạng» và SN máy.
4. **Vẫn phải thêm SN** ở mục Máy chấm công như phần 3.

**Chi tiết gateway** có:
- Đổi WiFi / cấu hình.
- «Quản lý trên máy»: user, vân tay, mở cửa, xóa log.
- Đồng bộ lại chấm công, Đẩy danh sách nhân viên, Chỉnh giờ máy.
- Xóa dữ liệu định kỳ.
- Khởi động lại, Reset ESP, Khôi phục xuất xưởng máy ZK (phải gõ RESET), cập nhật firmware OTA.

**Lỗi thường gặp**
- «WiFi timeout»: sai mật khẩu hoặc mạng 5GHz.
- IP trùng: mỗi máy chỉ gắn 1 mạch.
- Không thấy SBOX-Gateway: bật Bluetooth; trên iOS cấp quyền Mạng cục bộ.
- Lần đầu chỉ lấy log 30 ngày.
- Đăng ký vân tay qua gateway có «Ghi đè mẫu cũ»: quét lỗi thì **mất mẫu cũ** của ngón đó.

## 5. Đẩy nhân viên xuống máy

**Đường đi**: menu **Nhân sự chấm công** (nhóm Chấm công, ẩn trên sidebar máy tính). Trên điện thoại, nút «Tải hồ sơ NS» nằm trong nút «…».

**Các bước**
1. Bấm «Tải hồ sơ NS».
2. Chọn thiết bị.
3. Tích chọn nhân viên (hoặc «Chọn tất cả»).
4. Bấm «Tải N nhân viên».
5. Kết quả: «Đã tải X nhân viên… Y thất bại» kèm danh sách PIN đã cấp.

**Quy tắc dữ liệu**
- PIN = mã nhân viên, chỉ gồm số, tối đa 8 chữ số. Mã dài hơn thì lấy 6–8 số cuối hoặc cấp số kế tiếp. Các số từ 90000001 trở lên dành cho hội viên gym.
- Tên bị **bỏ dấu**.
- Quyền luôn là Người dùng (0); thẻ lấy từ hồ sơ; không có mật khẩu.
- Muốn đặt Quản trị viên (14): dùng hộp «Đồng bộ nhân viên vào máy chấm công».

**Nút khác**: «Tải từ máy», «Copy sinh trắc» (sang máy khác cùng cửa hàng; máy nguồn phải online khoảng 1 phút), «Thêm user», «Xóa người dùng».

**Lỗi thường gặp**
- «Nhân viên đã có trên máy với PIN X».
- «PIN X đã có người dùng khác».
- «Hết PIN trống».
- «Tài khoản không có quyền gửi lệnh này» (cần quyền `DeviceUser` Sửa).

**Điểm yếu**
- Thêm / xóa user chỉ báo «Lệnh sẽ gửi đến máy», không có kết quả cuối cùng.
- Lệnh không hết hạn: máy offline lâu thì lệnh tồn đọng.
- PIN có thể khác mã nhân viên nhưng chỉ hiện trong thông báo kết quả.

## 6. Đăng ký vân tay / khuôn mặt từ xa

**Các bước**
1. Nhân sự chấm công › menu của user › «Quản lý vân tay» (hoặc «Quản lý khuôn mặt»).
2. Vân tay: chọn ngón (10 ngón) › «Đăng ký». Nhân viên đặt ngón lên máy, **quét 3 lần**.
   - App chờ tối đa 120 giây, sau đó nhận file thêm khoảng 15–60 giây.
   - Lần lượt hiện: «Đã gửi lệnh…», «Máy đang chờ quét vân tay…», «Vân tay đã trên máy. Đang nhận file…».
3. Khuôn mặt: nhân viên nhìn **màn hình máy chấm công**, đứng cách khoảng 0,5–1 m. Máy có khoảng 60 giây để quét.

**Máy hỗ trợ** (theo «Engine profile» ở Chi tiết máy)
- Dòng khuôn mặt Android (SenseFace / ZAM): có đăng ký mặt từ xa.
- TFT / Linux: có vân tay.
- PushLite (LX35): không đăng ký vân tay từ xa, không có mặt.
- SN bắt đầu 131* (OEM): không đăng ký từ xa.
- Không hỗ trợ lòng bàn tay.

**Lỗi thường gặp**
- «Máy không hỗ trợ đăng ký vân tay từ xa»: đăng ký trực tiếp trên máy rồi bấm «Đồng bộ ngay».
- «Máy chấm công đang offline».
- «Hết thời gian chờ!».
- «Đăng ký thất bại».

## 7. Sửa công / bổ sung công / quên chấm công

**Bật tính năng**: Thiết lập SBOX › Cửa hàng › Tham số hệ thống › thẻ «Chấm công bù & quy trình duyệt»:
- «Cho phép xin sửa / bổ sung công».
- «Duyệt yêu cầu sửa công»: 1 / 2 / 3 cấp. Thứ tự: Quản lý trực tiếp › Quản lý cấp cao › Admin.

**Loại yêu cầu**: chỉ có Thêm mới / Chỉnh sửa / Xóa.

**Nhân viên gửi yêu cầu**
- Không có menu riêng.
- Lối vào duy nhất: màn Chấm công Mobile › lượt chấm bị từ chối › «Giải trình» › trang «Giải trình / xin bổ sung công» › «Yêu cầu mới».
- Form: Loại, Ngày (trong 30 ngày gần nhất), Giờ vào mới / Giờ ra mới, Lý do (bắt buộc).

**Quản lý bổ sung**
- Báo cáo nhân sự › Tổng hợp chấm công theo ca (hoặc Tổng hợp chấm công) › bấm ô thiếu («Bấm để bổ sung chấm công thiếu») › «Bổ sung chấm công thiếu» › «Thêm chấm công».
- Nút: «Xác nhận» hoặc «Thêm công và phạt».
- Tài khoản quyền cao (Admin / Giám đốc / có quyền Duyệt) thì yêu cầu **tự duyệt** và áp dụng ngay.

**Duyệt**: Chấm công › **Duyệt chấm công** › «Cần duyệt»:
- Lọc «Sửa / bổ sung công». Tích chọn nhiều phiếu › Duyệt / Từ chối (lý do ≥3 ký tự, có 4 lý do mẫu).
- Chi tiết phiếu có: trước / sau khi duyệt, «Yêu cầu tháng này», «Mức phạt quên chấm», «Luồng duyệt».
- Từ chối ở bất kỳ cấp nào thì cả phiếu bị từ chối.

**Sau khi duyệt đủ cấp**
- Hệ thống thêm / sửa / xóa log chấm công, ghi chú «[YC:id]».
- Ô giờ trên bảng tổng hợp có dấu «đã sửa».
- **Hủy phiếu phạt tự động của ngày đó** (quên chấm, nghỉ không phép, trễ, sớm) rồi tính lại phạt.
- Muốn vẫn phạt quên chấm thì bấm **«Duyệt + phạt»**. Nếu mức phạt Quên chấm công = 0 thì báo lỗi «chưa cài đặt (0đ)».

**Phạt quên chấm tự động**
- Sau khi đồng bộ, ngày có lịch mà chỉ có Vào hoặc chỉ có Ra: tạo phiếu «Quên chấm vào/ra ngày …» ở trạng thái chờ duyệt.
- Ngày không có lượt chấm nào: tạo phiếu nghỉ không phép.
- Bỏ qua các chế độ chấm 1 lần / chấm bất kỳ.
- Phiếu tự duyệt sau N giờ (mặc định 2 giờ).

**Lỗi và điểm yếu (cần sửa code)**
1. **Lỗi thật**: form «Yêu cầu sửa chấm công» của nhân viên chỉ gửi giờ vào. «Giờ ra mới» không được gửi đi. Form cũng không gửi loại Vào / Ra, không gửi bản ghi cũ khi Sửa / Xóa (`attendance_corrections_screen.dart:254-261`). Hệ quả: xin bổ sung giờ ra hoặc xin sửa / xóa sẽ không đúng, hoặc bị máy chủ báo «Không tìm thấy bản ghi».
2. «Thêm công và phạt» trên bảng công lập phiếu phạt **ngay**, kể cả khi phiếu bổ sung chưa được duyệt. Logic phạt này lặp với «Duyệt + phạt» phía máy chủ.
3. Không có hạn gửi (chỉ giới hạn 30 ngày trên giao diện), không giới hạn số lần / tháng, không khóa theo kỳ đã chốt, không đính kèm ảnh.
4. Không có giao diện «Hoàn duyệt» (API đã có).
5. Số cấp duyệt: giao diện cho 1–3, máy chủ nhận 1–5.
6. Còn file v1 `attendance_approval_screen.dart`, `mobile_attendance_approval_screen.dart`, `attendance_correction_tab.dart` không được dùng.

## 8. Chấm công điện thoại

**Thiết lập**: Thiết lập SBOX › Nhân sự & chấm công › **Chấm công Mobile** (cần quyền Sửa). Có 3 tab:
- **Cài đặt**:
  - Bật Khuôn mặt / GPS / Wi-Fi công ty. Bật từ 2 cách trở lên thì chọn «Chỉ cần đạt 1» hoặc «Phải đạt tất cả».
  - Độ khớp mặt 50–99%; chống ảnh giả.
  - Bán kính GPS 30–1000 m.
  - Tự duyệt khi chấm tại công ty; ảnh hiện trường khi chấm ngoài; chống chấm trùng.
- **Vị trí**: Tên, Địa chỉ, Bán kính, «MAC Router WiFi (BSSID)», chọn tọa độ trên bản đồ. Không có trường SSID.
- **Thiết bị**: cấp quyền bằng QR (hiệu lực 5 phút), danh sách yêu cầu đổi máy.

**Nhân viên đăng ký** (chỉ trên app điện thoại): Chấm công › Đăng ký chấm công Mobile › chọn vị trí › chụp 5 góc mặt › «Gửi đăng ký» › chờ duyệt. Mỗi tài khoản dùng 1 điện thoại. Đổi máy qua «Gửi yêu cầu đổi máy».

**Quản lý duyệt máy**: cùng màn, tab «Cần duyệt». Bật từng quyền cho mỗi máy: Khuôn mặt, Định vị, Ngoài công ty, Bắt nhập lý do, Công tác, Ảnh hiện trường. Có nút «Thu hồi».

**Chấm công**: Chấm công › Chấm công Mobile:
- Nút: QUÉT MẶT / CHẤM VÀO / CHẤM RA.
- Có nhóm «Tăng ca trưa» và «Chấm đi đường».

**Duyệt lượt chấm**
- Lượt chấm chờ duyệt nằm ở Duyệt chấm công › lọc «Chấm Mobile». Có nút «Duyệt N bản tin cậy».
- Chỉ lượt đã duyệt mới vào Chấm công thô.

**Lỗi thường gặp**
- «Thiết bị chưa được duyệt hoặc đã bị thu hồi».
- «Nhân viên chưa đăng ký khuôn mặt».
- «MAC WiFi (BSSID) không khớp…»: WiFi mesh có nhiều MAC.
- «Bắt buộc chụp ảnh hiện trường…».
- «Vui lòng nhập lý do chấm công ngoài vị trí».

**Điểm yếu**
- Ngưỡng khớp mặt và tự duyệt mỗi thứ cấu hình ở 2 nơi (Chấm công Mobile › Cài đặt và Duyệt chấm công › «Cài đặt duyệt», mặc định 85%).
- Chỉ khai được 1 BSSID, chưa có SSID.

## 9. Xếp lịch làm việc / ca xoay

**Bảng xếp ca**: Chấm công › **Ca làm việc** › tab «Bảng xếp ca» (chỉ quản lý thấy). Thay đổi **lưu ngay**.
- Chọn tuần; xem Cả tuần / Từng ngày; lọc Bộ phận.
- Chạm ô ngày: «Xếp ca» (chọn ca mẫu) / «Ngày nghỉ» / «Xoá lịch ngày này». Nếu có đăng ký chờ thì có thêm Duyệt / Từ chối.
- «Thao tác nhanh»: Sao chép lịch tuần trước (chỉ điền ô trống), Nhắc NV chưa đăng ký lịch.
- Hàng định mức đỏ = thiếu người. Nút «Kêu gọi bổ sung người».

**Lịch đầy đủ** (Ca làm việc › Thiết lập › «Lịch làm việc (đầy đủ)»):
- Xếp hàng loạt; sao chép ngày / tuần (tối đa 12 tuần) / tháng; Excel; Đối chiếu chấm công; Độ phủ ca.
- Cách lưu **khác** Bảng xếp ca: lịch vào «Danh sách chờ gửi», phải bấm «Gửi đăng ký», rồi đi qua duyệt.

**Ca xoay: CHƯA CÓ tính năng.** Không có mẫu chu kỳ kiểu 2 sáng – 2 chiều – 2 nghỉ. Cách làm hiện tại: xếp tay 1–2 tuần rồi «Sao chép tuần» (tối đa 12 tuần).

**Nhân viên** (tab «Lịch của tôi»): ⋮ trên từng ngày › Đăng ký ca (hiện số chỗ trống) / Xin nghỉ phép / Đổi ca với đồng nghiệp / Huỷ đăng ký.
- Luồng đổi ca: nhân viên gửi › đồng nghiệp Đồng ý › quản lý duyệt › lịch hai người tự hoán đổi.

**Duyệt tập trung**: tab «Cần duyệt», lọc Đăng ký ca / Đơn nghỉ / Đổi ca / Ca theo giờ. Duyệt nhiều phiếu một lần.

**Định mức nhân sự**: Thiết lập SBOX › Định mức nhân sự › «Thêm định mức» (ca + phòng ban, tối thiểu / tối đa theo thứ).

**Điểm yếu**
- Hai luồng xếp ca có cách lưu khác nhau.
- Định mức nằm ở 3 nơi, duyệt nằm ở 3 nơi, đổi ca nằm ở 2 nơi.
- Thiếu tính năng ca xoay.

## 10. Nghỉ phép

**Thiết lập**: Thiết lập SBOX › Lương & chính sách › **Phép năm**:
- Số ngày mặc định, thâm niên, vào làm giữa năm.
- Chỉ trừ ngày làm việc; cho duyệt khi không đủ phép.
- Chuyển phép tối đa; tiền phép.

**Màn Phép năm**: Điều chỉnh phép, Trả tiền phép còn lại, «Chốt phép năm YYYY» (có «Mở lại năm»).

**Nhân viên tạo đơn**: Chấm công › Nghỉ phép › «Tạo đơn».
- Bước 1: chọn nhóm chế độ (DN trả lương / Không lương / BHXH / DN + đối soát BHXH).
- Bước 2: chọn loại nghỉ (Phép năm, Việc riêng có lương, Nghỉ bù, Ốm hưởng BHXH, Thai sản…). Điền Ca nghỉ, Người thay ca, Từ ngày – Đến ngày, Nửa ca, Lý do, Số seri giấy BHXH.
- Có bản rút gọn trong Lịch của tôi › ⋮ › Xin nghỉ phép (6 loại).

**Quản lý duyệt**: tab «Chờ duyệt», hoặc Ca làm việc › Cần duyệt. Hộp duyệt hiện số ngày sẽ trừ, số còn lại, và công tắc «Phép duyệt nhưng vẫn tính công».

**Lỗi thường gặp**
- «Chưa có quỹ phép năm (gắn hồ sơ lương…)»: nhân viên chưa có Thiết lập lương.
- «Không thuộc diện hưởng phép năm».

## 11. Tăng ca

**Quan trọng: tiền tăng ca tính theo giờ chấm công so với ngưỡng của ca. Đơn tăng ca đã duyệt KHÔNG được tính lương.** Đã kiểm tra: bảng Overtimes không được dùng trong tính lương hay phiếu lương.

Cách tính:
- Vào sớm hơn «Tăng ca trước ca» hoặc ra muộn hơn «Tăng ca sau ca» thì được tính tăng ca.
- Ca loại «Tăng ca» thì toàn bộ giờ làm là tăng ca.
- Hệ số theo Chính sách lương: 1,5 / 2 / 3.
- Đơn giá theo khối Tăng ca trong Thiết lập lương.

**Màn «Quản lý tăng ca»**
- Không có trong menu; mở qua ô Tăng ca trên Trang chủ hoặc Dashboard.
- Đăng ký tăng ca: ngày (đến +90 ngày), giờ bắt đầu / kết thúc, lý do › Gửi yêu cầu.
- Quản lý bấm ✓ / ✗ trên thẻ đơn.

**Điểm yếu (lớn)**
- Đơn tăng ca chỉ mang tính ghi nhận. Người dùng dễ tưởng đã duyệt là được trả tiền, và ngược lại không đăng ký vẫn được tính nếu ra muộn.
- Một số lỗi tiếng Anh: «Can only approve pending requests».
- API «complete» (ghi giờ thực tế) có nhưng không có nút.

**Gợi ý**: thêm tùy chọn «Chỉ tính tăng ca khi có đơn duyệt» (giới hạn theo giờ đơn), và đưa «Tăng ca» vào menu Chấm công.

## 12. Chốt bảng lương

**Thứ tự trước khi chốt**
1. Chấm công thô đủ log.
2. Kiểm tra Tổng hợp chấm công theo ca.
3. Duyệt hết sửa công, phép, đổi ca, phạt, thưởng, ứng lương.

**Chốt**: Báo cáo nhân sự › **Tổng hợp lương**.
- Chọn tháng và chi nhánh. Bảng tự tính khi mở; không có nút «Tính lại», đổi tháng là tải lại.
- Bấm «Chốt lương» (cần quyền Duyệt của Payroll). Chọn «Chốt n NV đã chọn» hoặc «Chốt tất cả».
- Kết quả «x mới, y cập nhật, z bỏ qua». App hỏi «Trả lương ngay?».

**Sau khi chốt**
- Phiếu lương được tạo ở trạng thái đã duyệt.
- Nhân viên **tự nhận thông báo** (trong app / push / Zalo): «Phiếu lương đã chốt…».
- Xem phiếu ở Báo cáo nhân sự › Phiếu lương.
- Trả lương: Tiền mặt / Chuyển khoản / Kết hợp; xuất file ngân hàng; chuyển từng người bằng QR.

**Lỗi thường gặp**
- «Không có nhân viên hợp lệ để chốt (n NV chưa có bảng lương)».
- «NV xxx: thiếu bảng lương»: thiếu Thiết lập lương.
- Kỳ lương tối đa 2 tháng.

**Điểm yếu (lớn)**
- **Chốt không khóa chấm công, phép, lịch.** Chỉ sản lượng bị khóa.
- Không có «Mở chốt». Muốn sửa thì sửa dữ liệu rồi chốt lại (ghi đè; nếu đã trả thì có phiếu chi bổ sung hoặc cảnh báo trả thừa).
- Không có nút gửi lại phiếu lương.
- Hướng dẫn hiện có ghi «nên khóa kỳ nếu có»: chưa có tính năng khóa kỳ.

## 13. Zalo bot

**Quản trị**: Thiết lập SBOX › Tích hợp & thông báo › **Zalo bot** (quyền SystemSettings):
1. Vào bot.zapps.me, tạo bot.
2. Dán «Token bot» và «Link mở bot» (https://). Bấm Lưu.
3. Kiểm tra «Nhận tin từ Zalo (webhook)» báo Hoạt động. Nếu lỗi, bấm «Đăng ký lại». Máy chủ phải có tên miền https công khai.
4. «Bật gửi qua Zalo», chọn nhóm thông báo. Mặc định bật: lương, phạt, chấm công, phép, tăng ca, ca làm, phê duyệt. Có tùy chọn «Ẩn số tiền».
5. «Gửi tin thử cho tôi».

**Nhân viên**: Cài đặt › **Liên kết Zalo** (chỉ hiện khi cửa hàng đã bật bot):
1. «Lấy mã liên kết»: mã 6 số, hết hạn sau 15 phút.
2. «Mở bot Zalo», gửi mã cho bot. Bot trả lời «✅ Đã liên kết».
3. Muốn hủy liên kết: gửi «HUY» cho bot.

**Lỗi thường gặp**
- «Nhập token bot trước khi bật».
- «Token bot không đúng hoặc đã hết hạn».
- «Chưa đăng ký được. Máy chủ phải có tên miền https công khai» (môi trường QA local luôn gặp lỗi này).
- «Tài khoản của bạn chưa liên kết Zalo».
- «Mã không đúng hoặc đã hết hạn».

## 14. Tóm tắt gợi ý cải thiện (xếp theo mức ưu tiên)

1. Sửa lỗi form «Yêu cầu sửa chấm công» không gửi giờ ra / loại / bản ghi cũ.
2. Tăng ca: thêm tùy chọn chỉ tính khi có đơn duyệt; đưa vào menu.
3. Chốt lương: khóa sửa chấm công, phép, lịch của kỳ đã chốt; thêm «Mở chốt» có ghi lịch sử.
4. Đưa lối vào cho nhân viên «Xin sửa / bổ sung công» vào menu Chấm công. Hiện chỉ vào được qua nút «Giải trình».
5. Hiện các mục ẩn (Ca làm việc, Nghỉ phép, Nhân sự chấm công, Thiết lập lương, Duyệt chấm công) trên sidebar máy tính. Đổi nhãn «Salary Settings» sang tiếng Việt.
6. Thêm tính năng ca xoay (mẫu chu kỳ N ngày, áp cho nhóm nhân viên, từ ngày đến ngày).
7. «Thêm công và phạt»: chỉ lập phiếu phạt sau khi phiếu bổ sung đã được duyệt.
8. Máy chấm công:
   - Hướng dẫn ghi rõ thứ tự «cấu hình máy trước, thêm SN sau».
   - Hiện kết quả lệnh thêm / xóa user và cho hủy lệnh tồn đọng.
   - Tách nút «Xóa toàn bộ dữ liệu» ra vùng nguy hiểm.
   - Thêm «Đồng bộ giờ».
9. Gộp cấu hình trùng: ngưỡng khớp mặt / tự duyệt mobile; định mức; nơi tạo sản phẩm.
10. Sửa hướng dẫn đang có: «Cài đặt → …» đổi thành «Thiết lập SBOX › …»; bỏ câu «khóa kỳ nếu có»; thêm cảnh báo về tăng ca.

## Cập nhật 30/10 — đã đưa vào hướng dẫn trong app (chưa commit)
- landing_usage_guide.dart: sửa các mục HRM («Cài đặt →» → «Thiết lập SBOX ›», chốt lương, ca xoay, tăng ca); thêm bước gateway_wifi, attendance_correction (basic), overtime, zalo_bot (advanced) có ảnh.
- Test ảnh mới: test/guide_shots/{gateway_wifi,attendance_correction,overtime,zalo_bot}_guide_shots_test.dart; đổi crumbs các test HRM cũ.
- web/guide.html + web/images/guide/*.webp, HelpCorpus/landing-guide.json, AiAssistantHelpCorpus.cs Overlays, i18n (133 chuỗi en/ko/ja/zh).
- Sửa lỗi giao diện phát hiện khi dựng ảnh: overtime_screen (điện thoại lỗi màn hình khi có đơn — SliverOverlapInjector không có absorber), zalo_bot_settings_screen (chip tràn trên máy tính), zk_gateway_setup_screen (ExpansionTile thiếu Material).
- Chưa sửa: form «Yêu cầu sửa chấm công» không gửi giờ ra / loại / bản ghi cũ (attendance_corrections_screen.dart:254); các mục POS trong guide còn «Cài đặt →».

## Cập nhật 31/10 — sửa form «Yêu cầu sửa chấm công» (attendance_corrections_screen.dart)
- Thêm mới: chọn giờ vào và/hoặc giờ ra → mỗi giờ 1 phiếu (newType CheckIn/CheckOut). Mặc định loại = Thêm mới.
- Chỉnh sửa: «Giờ đã chấm cần sửa» + «Giờ đúng» + «Loại chấm» → gửi oldDate/oldTime (backend tìm bản ghi theo NV + giờ) + newTime/newType.
- Xóa: «Giờ đã chấm cần xóa» → oldDate/oldTime. Trước đây sửa/xóa luôn lỗi «Không tìm thấy bản ghi chấm công».
- Khóa nút gửi khi đang gửi; bỏ dispose controller lý do trong finally (gửi lỗi rồi gửi lại bị dùng controller đã hủy).
- Sửa lỗi có sẵn: danh sách «Yêu cầu của tôi» luôn báo «Không thể tải dữ liệu» (`data['items'] ?? data is List ? …` dùng List làm bool).
- Test mới: test/attendance_corrections_form_test.dart (4 ca). Chuỗi mới đã dịch; bullet attendance_correction cập nhật + corpus AI.
