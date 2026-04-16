# ZKTeco ADMS - Complete UI Design Specification
## Hệ thống quản lý chấm công & nhân sự

> Tài liệu mô tả chi tiết từng màn hình, chức năng, và giao diện để gửi cho AI thiết kế UI.
> Ứng dụng hỗ trợ: Web + Mobile (Flutter), Dark/Light mode, Song ngữ Việt-Anh.

---

## TỔNG QUAN HỆ THỐNG

- **Loại ứng dụng**: HR Management + Attendance Tracking (SaaS multi-tenant)
- **Nền tảng**: Web responsive + Mobile (Flutter)
- **Ngôn ngữ**: Tiếng Việt (mặc định), English
- **Theme**: Light mode + Dark mode
- **Design System**: Material Design 3
- **Vai trò người dùng**: SuperAdmin → Admin → Manager → HR → Employee
- **Realtime**: SignalR WebSocket cho chấm công và thông báo

### Color Scheme
- Primary: Navy (#1E3A5F)
- Secondary: Light Blue
- Success/Present: Green (#22C55E)
- Warning/Late: Amber (#F59E0B)
- Error/Absent: Red (#EF4444)
- Background Light: #F1F5F9
- Background Dark: #18181B
- Text Light: #1E293B
- Text Dark: #F8FAFC

### Typography
- Headlines: Material 3 (headlineSmall → headlineLarge)
- Body: bodySmall → bodyLarge
- Monospace: cho mã code, PIN, số liệu kỹ thuật
- Currency: ₫ (VND), format: 1.234.567

---

## NAVIGATION STRUCTURE (MainLayout)

Sidebar navigation với 27+ mục, phân quyền theo vai trò:

```
📊 Dashboard
👥 Nhân viên (Employees)
⏰ Chấm công (Attendance)
📋 Tổng hợp chấm công (Attendance Summary)
🔄 Ca làm việc (Attendance By Shift)
✏️ Điều chỉnh chấm công (Corrections)
✅ Duyệt chấm công (Approvals)
📱 Chấm công Mobile (Mobile Attendance)
📊 Báo cáo chấm công (Attendance Report)
🏢 Phòng ban (Departments)
🌳 Sơ đồ tổ chức (Org Chart)
🏗️ Chi nhánh (Branches)
📅 Lịch làm việc (Work Schedule)
🔄 Đăng ký ca (Shift Registration)
🔀 Đổi ca (Shift Swap)
📝 Nghỉ phép (Leave)
💰 Bảng lương (Payroll)
📄 Phiếu lương (Payslip)
🎁 Thưởng/Phạt (Bonus & Penalty)
💵 Tạm ứng (Advance Requests)
📈 KPI
🗂️ Quản lý tài sản (Assets)
💳 Thu chi (Cash Transactions)
📢 Truyền thông (Communication)
📋 Công việc (Tasks)
🔔 Thông báo (Notifications)
⚙️ Cài đặt (Settings)
🛡️ Quản trị hệ thống (System Admin - SuperAdmin only)
```

---

## MÀN HÌNH 1: LOGIN (Đăng nhập)

**Mục đích**: Đăng nhập cho nhân viên và quản lý

**Layout**: Centered card, max-width 400px, gradient background

**Thành phần UI**:
- Logo: Icon vân tay trong vòng tròn màu primary
- Tiêu đề: "ZKTeco ADMS"
- Phụ đề: "Hệ thống quản lý chấm công"
- Form đăng nhập:
  - TextField "Mã cửa hàng" (Store Code) - bắt buộc
  - TextField "Email" - bắt buộc, validate email format
  - TextField "Mật khẩu" - có icon con mắt ẩn/hiện
  - Checkbox "Nhớ đăng nhập"
- Button "ĐĂNG NHẬP" - full-width, primary color, hiện loading spinner khi xử lý
- Link "Quên mật khẩu?"
- Link "Đăng ký tài khoản mới"

**Feedback**: SnackBar đỏ ở bottom khi lỗi

---

## MÀN HÌNH 2: ADMIN LOGIN (Đăng nhập Admin)

**Mục đích**: Đăng nhập riêng cho Admin/SuperAdmin

**Layout**: Tương tự Login nhưng không có Store Code

**Thành phần UI**:
- TextField "Email"
- TextField "Mật khẩu" với toggle ẩn/hiện
- Button "ĐĂNG NHẬP"

---

## MÀN HÌNH 3: REGISTER (Đăng ký cửa hàng mới)

**Mục đích**: Đăng ký tài khoản cửa hàng mới

**Layout**: Centered card, max-width 500px

**Form**:
- TextField "Tên cửa hàng"
- TextField "Email"
- TextField "Mật khẩu"
- TextField "Xác nhận mật khẩu"
- TextField "Số điện thoại"
- Checkbox "Đồng ý điều khoản sử dụng"
- Button "ĐĂNG KÝ" - full-width
- Link "Đã có tài khoản? Đăng nhập"

---

## MÀN HÌNH 4: QUÊN MẬT KHẨU (Forgot Password)

**Layout**: Centered card nhỏ

**Form**:
- TextField "Email"
- Button "Gửi link đặt lại mật khẩu"
- Link quay về đăng nhập

---

## MÀN HÌNH 5: ĐẶT LẠI MẬT KHẨU (Reset Password)

**Layout**: Centered card nhỏ

**Form**:
- TextField "Mật khẩu mới"
- TextField "Xác nhận mật khẩu mới"
- Button "Đặt lại mật khẩu"

---

## MÀN HÌNH 6: DASHBOARD (Tổng quan)

**Mục đích**: Tổng quan dữ liệu executive, auto-refresh mỗi 30 giây

**AppBar**: Title "Dashboard" + subtitle hiển thị thời gian thực (HH:MM:SS)

**Body Layout**: ScrollView với nhiều section

### Section 1: Thẻ tóm tắt chấm công hôm nay (4 StatCards ngang)
- Card "Có mặt": số lượng + % (icon: ✅, màu xanh lá)
- Card "Vắng mặt": số lượng + % (icon: ❌, màu đỏ)
- Card "Đi muộn": số lượng + % (icon: ⏰, màu cam)
- Card "Tổng check-in/out": số lượng (icon: 📊, màu xanh dương)

### Section 2: Trạng thái thiết bị
- Card "Thiết bị online": số lượng (chấm xanh lá)
- Card "Thiết bị offline": số lượng (chấm xám)

### Section 3: Biểu đồ xu hướng 7 ngày
- Chart type: Line/Bar chart
- Trục X: 7 ngày gần nhất
- Trục Y: Số lượng
- 3 đường/cột: Có mặt (xanh), Vắng (đỏ), Muộn (cam)

### Section 4: Sinh nhật hôm nay
- Danh sách nhân viên có sinh nhật
- Hiển thị avatar + tên + tuổi

### Section 5: Sinh nhật sắp tới (30 ngày)
- Danh sách sắp xếp theo ngày

### Section 6: Tin tức/Thông báo gần đây
- 5 thông báo mới nhất
- Hiển thị title, nội dung rút gọn, badge loại (Tin tức/Thông báo/...)

### Section 7: Duyệt nghỉ phép & Lịch trình
- Số đơn chờ duyệt
- Lịch trình hôm nay

### Section 8: Tóm tắt KPI
- Các chỉ số KPI chính
- Progress indicators

---

## MÀN HÌNH 7: QUẢN LÝ NHÂN VIÊN (Employees)

**Mục đích**: CRUD danh sách nhân viên với đầy đủ thông tin

**AppBar**: Title "Nhân viên" + Buttons [➕ Thêm] [📥 Import] [📤 Export]

### Filter Bar
- TextField tìm kiếm (theo tên, mã, email, SĐT)
- Dropdown "Phòng ban" (multi-select)
- Dropdown "Trạng thái làm việc" (Đang làm, Thử việc, Nghỉ phép, Đã nghỉ)

### DataTable - Các cột:
| Cột | Mô tả |
|-----|--------|
| Avatar | Thumbnail ảnh hoặc chữ cái đầu |
| Mã NV | Employee code |
| Họ tên | FirstName + LastName |
| Email | Email cá nhân |
| SĐT | Phone |
| Phòng ban | Department name |
| Chức vụ | Position |
| Trạng thái | Badge màu (Xanh=Đang làm, Cam=Thử việc, Xám=Nghỉ phép, Đỏ=Đã nghỉ) |
| Thao tác | Icons: [✏️ Sửa] [🗑️ Xoá] [👁️ Chi tiết] |

### Pagination: 50 items/page

### Dialog Thêm/Sửa nhân viên (Multi-tab):

**Tab 1 - Thông tin cá nhân**:
- TextField: Họ, Tên, Giới tính (Dropdown: Nam/Nữ), Ngày sinh (DatePicker)
- TextField: Email, SĐT

**Tab 2 - Tổ chức**:
- Dropdown: Phòng ban, Chức vụ, Cấp bậc
- Dropdown: Quản lý trực tiếp (searchable)

**Tab 3 - Địa chỉ**:
- TextField: Địa chỉ thường trú, Địa chỉ tạm trú, Quê quán
- Dropdown 34 tỉnh thành Việt Nam

**Tab 4 - Thông tin khác**:
- Dropdown: Tình trạng hôn nhân (Độc thân/Đã kết hôn/Ly hôn/Góa)
- Dropdown: Trình độ học vấn
- TextField: CMND/CCCD, Ngày cấp, Nơi cấp
- Upload: Ảnh CMND mặt trước/sau (có crop tool)

**Tab 5 - Ngân hàng**:
- TextField: Tên ngân hàng, Chủ tài khoản, Số tài khoản, Chi nhánh

**Tab 6 - Liên hệ khẩn cấp**:
- TextField: Tên người liên hệ, SĐT

**Nút**: [💾 Lưu] [❌ Hủy]

**Tính năng đặc biệt**:
- Tự động bỏ dấu tiếng Việt cho tên gửi lên thiết bị
- Crop ảnh CMND trước khi upload
- Encode Base64 cho ảnh

---

## MÀN HÌNH 8: CHẤM CÔNG REALTIME (Attendance)

**Mục đích**: Xem bản ghi chấm công realtime, hỗ trợ yêu cầu điều chỉnh

**AppBar**: Title "Chấm công" + Toggle auto-refresh (5 giây) + Indicator kết nối

### Filter Bar:
- DateRange Picker (presets: Hôm nay, Hôm qua, 7 ngày, Tuần trước, Tháng này, Tùy chọn)
- Dropdown "Thiết bị" (multi-select)
- TextField "Tìm PIN/Nhân viên"
- Dropdown "Loại xác thực" (Tất cả, Vân tay, Thẻ, Khuôn mặt, Mật khẩu)
- Toggle sắp xếp (Thời gian tăng/giảm)

### DataTable - Các cột:
| Cột | Mô tả |
|-----|--------|
| Thời gian | HH:MM:SS, sortable |
| PIN | Mã nhân viên trên thiết bị |
| Tên nhân viên | Họ tên |
| Thiết bị | Tên thiết bị |
| Loại xác thực | Icon + text (👆 Vân tay / 💳 Thẻ / 😊 Khuôn mặt / 🔑 Mật khẩu) |
| Trạng thái | CheckIn / CheckOut / MealIn / MealOut / BreakIn / BreakOut |
| Thao tác | [👁️ Xem] [✏️ Sửa] (nếu là manager) |

### Pagination: 25-200 items/page (có chọn)

### Dialog Yêu cầu điều chỉnh:
- Hiển thị thời gian gốc (read-only)
- TimePicker "Thời gian yêu cầu"
- TextField "Lý do"
- Dropdown "Loại" (Thêm / Sửa / Xoá)
- Buttons: [✅ Gửi] [❌ Hủy]

**Tính năng**:
- Cập nhật realtime qua SignalR
- Cache localStorage khi offline
- Auto-refresh toggle 5 giây

---

## MÀN HÌNH 9: TỔNG HỢP CHẤM CÔNG (Attendance Summary)

**Mục đích**: Tóm tắt chấm công hàng ngày theo nhân viên

### Filter:
- Date presets (Tháng này, Tháng trước, Tùy chọn)
- Dropdown "Ca làm" (Tất cả, Thiếu, Đầy đủ)

### DataTable:
| Cột | Mô tả |
|-----|--------|
| Tên NV | Họ tên |
| Ngày | dd/MM/yyyy |
| Ca | Tên ca (nếu có) |
| Giờ vào | HH:MM |
| Giờ ra | HH:MM |
| Trạng thái | Badge: Có mặt(xanh) / Muộn(cam) / Vắng(đỏ) / Nghỉ phép(tím) |
| Giờ làm việc | Số giờ (tính toán tự động) |
| Thao tác | [👁️ Xem chi tiết] [✏️ Yêu cầu điều chỉnh] |

**Tính năng**: Export Excel, nhóm theo ca, multi-select batch

---

## MÀN HÌNH 10: CHẤM CÔNG THEO CA (Attendance By Shift)

**Mục đích**: Tổng quan chấm công theo từng ca

### DataTable:
| Cột | Mô tả |
|-----|--------|
| Tên ca | Shift name |
| NV dự kiến | Expected count |
| Có mặt | Present count |
| Vắng mặt | Absent count |
| Đi muộn | Late count |
| Tỷ lệ % | Coverage = Present/Expected * 100 |
| Thao tác | [👁️ Chi tiết ca] [✅ Duyệt] |

### Biểu đồ: Donut/Pie chart mỗi ca - Xanh(có mặt), Đỏ(vắng), Cam(muộn)

---

## MÀN HÌNH 11: ĐIỀU CHỈNH CHẤM CÔNG (Corrections)

**Mục đích**: Quản lý yêu cầu điều chỉnh chấm công

### Tab 1: Đang chờ (Pending)
| Cột | Mô tả |
|-----|--------|
| Tên NV | Employee name |
| Giờ gốc | Original time |
| Giờ yêu cầu | Requested time |
| Lý do | Reason (rút gọn) |
| Loại | Badge: Thêm(xanh lá) / Sửa(xanh dương) / Xoá(đỏ) |
| Trạng thái | Badge Chờ duyệt (vàng) |
| Thao tác | [🗑️ Xoá] (chỉ của mình) [👁️ Chi tiết] |

### Tab 2: Đã xử lý (Processed)
- Thêm cột: Người duyệt, Ngày duyệt, Lý do từ chối
- Badge: Đã duyệt(xanh) / Từ chối(đỏ)

### Filter: Nhân viên, Loại (Thêm/Sửa/Xoá), Trạng thái, Khoảng thời gian

---

## MÀN HÌNH 12: DUYỆT CHẤM CÔNG (Attendance Approval)

**Mục đích**: Manager duyệt yêu cầu điều chỉnh

### Tab Structure: Chờ duyệt | Đã duyệt | Từ chối

### Tab Chờ duyệt:
| Cột | Mô tả |
|-----|--------|
| Tên NV | Employee |
| Ngày/Giờ mới | New datetime |
| Ngày/Giờ gốc | Original datetime |
| Loại | Badge (Add/Edit/Delete) |
| Lý do | Reason |
| Trạng thái | Pending |
| Thao tác | [✅ Duyệt] [❌ Từ chối] [👁️ Chi tiết] |

**Tính năng**:
- Multi-select checkbox để duyệt/từ chối hàng loạt
- Dialog từ chối yêu cầu nhập lý do
- Audit trail (người duyệt, thời gian)
- Export Excel

---

## MÀN HÌNH 13: BÁO CÁO CHẤM CÔNG (Attendance Report)

**Mục đích**: Phân tích chấm công đa chiều

### Tab 1: Báo cáo ngày
- Date picker/presets
- Table: NV, Có mặt, Vắng, Muộn, Giờ vào, Giờ ra, Trạng thái
- Drill-down chi tiết NV
- Export CSV/Excel

### Tab 2: Báo cáo tháng
- Month selector
- Metrics: Tổng ngày làm, Ngày có mặt, % chấm công
- Table: NV, Ngày có mặt, Ngày vắng, % chấm công, Trạng thái

### Tab 3: Báo cáo muộn/sớm
- Chỉ hiện đi muộn và về sớm
- Filter theo ngưỡng (>5p, >15p, >30p)
- Table: NV, Ngày, Giờ, Số phút muộn/sớm, Lý do

### Tab 4: Phân tích theo phòng ban
- Dropdown phòng ban
- Summary: Tổng, Có mặt, Vắng, % chấm công
- Pie/Donut chart phân bổ
- Drill-down vào nhân viên phòng ban

### Export: CSV, Excel (có format), filename: attendance_report_YYYY-MM-DD.xlsx

---

## MÀN HÌNH 14: CHẤM CÔNG MOBILE (Mobile Attendance)

**Mục đích**: Check-in/out bằng nhận diện khuôn mặt + GPS

**Layout**: Full-screen, card-based, mobile-first

### Main Card:
- Tên NV, mã NV, phòng ban
- Đồng hồ lớn hiển thị real-time (HH:MM:SS)
- Vị trí GPS hiện tại & khoảng cách từ vị trí cho phép
  - Xanh lá = Trong bán kính
  - Đỏ = Ngoài bán kính

### Face Verification Section:
- Nút tròn lớn "Xác thực khuôn mặt" (hiệu ứng pulse)
- Preview ảnh khuôn mặt hoặc placeholder
- Điểm khớp (0-100%)
- Trạng thái: "Đã xác thực ✓" hoặc "Cần xác thực"

### Thông tin vị trí:
- Tên vị trí (VD: "Văn phòng chính")
- Địa chỉ
- Bán kính cho phép (mét)
- Khoảng cách hiện tại

### Nút hành động (bottom):
- Button lớn "CHECK IN" hoặc "CHECK OUT"
- Khi bấm: Camera → Chụp mặt → Kiểm tra GPS → Gửi → Hiện kết quả

### Lịch sử hôm nay:
- Danh sách check-in/out hôm nay
- Mỗi item: Giờ, Loại (Vào/Ra), Badge trạng thái, Điểm khớp, Khoảng cách

**Tính năng**: GPS tracking realtime, face matching >80%, auto-approve nếu trong bán kính

---

## MÀN HÌNH 15: DUYỆT CHẤM CÔNG MOBILE (Mobile Attendance Approval)

**Tương tự Màn hình 12** nhưng dành cho chấm công mobile face-based

---

## MÀN HÌNH 16: LỊCH SỬ CHẤM CÔNG MOBILE (Mobile Attendance History)

**Mục đích**: Xem lại lịch sử check-in mobile

---

## MÀN HÌNH 17: QUẢN LÝ PHÒNG BAN (Departments)

**Mục đích**: CRUD phòng ban dạng phân cấp

### Tab 1: Danh sách
**Filter**: Search box + Toggle "Hiện phòng ban ẩn"

| Cột | Mô tả |
|-----|--------|
| Tên phòng ban | Department name |
| Mã | Code |
| Quản lý | Manager name |
| SL nhân viên | Direct count |
| Tổng NV | Including sub-departments |
| Cấp | Hierarchy level |
| Trạng thái | Badge Active(xanh)/Inactive(xám) |
| Thao tác | [✏️ Sửa] [🗑️ Xoá] [🌳 Xem sơ đồ] [➕ Thêm phòng con] |

### Tab 2: Sơ đồ tổ chức
- Interactive tree/graph layout
- Mỗi node: Tên phòng ban, SL nhân viên, Quản lý
- Zoom/Pan controls
- Click node để highlight đường dẫn từ root
- Màu: Xanh = Active, Xám = Inactive

### Dialog Thêm/Sửa phòng ban:
- TextField: Tên (bắt buộc), Mã, Mô tả
- Dropdown: Phòng ban cha
- Dropdown: Quản lý (searchable employee list)
- Number: Thứ tự sắp xếp
- Toggle: Trạng thái Active/Inactive
- Buttons: [💾 Lưu] [❌ Hủy]

---

## MÀN HÌNH 18: SƠ ĐỒ TỔ CHỨC (Org Chart)

**Mục đích**: Hình ảnh hóa cấu trúc tổ chức toàn bộ

**Layout**: Interactive chart full-screen

- Nodes: Box chức vụ/vai trò + tên nhân viên
- Edges: Đường báo cáo (reporting lines)
- Zoom/Pan controls
- Click nhân viên → popup chi tiết
- Drill-down theo phòng ban

---

## MÀN HÌNH 19: QUẢN LÝ CHI NHÁNH (Branch Management)

**Mục đích**: CRUD chi nhánh/cơ sở

| Cột | Mô tả |
|-----|--------|
| Tên chi nhánh | Branch name |
| Địa điểm | Location |
| Quản lý | Manager |
| SL nhân viên | Employee count |
| SL thiết bị | Device count |
| Trạng thái | Active/Inactive |
| Thao tác | [✏️] [👁️ Xem NV] [📱 Xem thiết bị] |

---

## MÀN HÌNH 20: LỊCH LÀM VIỆC (Work Schedule)

**Mục đích**: Phân ca và quản lý lịch làm việc

### Tab 1: Theo ca (Shift-Centric)
- Header: Week selector (Thứ 2 → Chủ nhật)
- Table: Rows = Ca, Columns = Ngày trong tuần
- Cells: Số NV + click để xem danh sách
- [➕] button mỗi cell để thêm NV vào ca

### Tab 2: Theo nhân viên (Schedule-Centric)
- Header: Week selector + Filter phòng ban/NV
- Table: Row = NV, Columns = Thứ 2→CN
- Cells: Tên ca hoặc "OFF"
- Drag-and-drop để đổi ca (optional)

### Tab 3: Duyệt đăng ký
- Manager duyệt yêu cầu đổi ca
- Table: NV, Ngày yêu cầu, Ca yêu cầu, Lý do
- Actions: [✅ Duyệt] [❌ Từ chối]

### Dialog Phân ca:
- Multi-select nhân viên
- DateRange picker
- Dropdown chọn ca
- TextField lý do (optional)
- [✅ Áp dụng] [❌ Hủy]

**Tính năng**: Di chuyển tuần (trước/sau), Export Excel, bulk assign

---

## MÀN HÌNH 21: ĐĂNG KÝ CA (Shift Registration)

**Mục đích**: Nhân viên đăng ký ca làm việc ưu tiên
**Tương tự WorkSchedule** nhưng cho đăng ký cá nhân

---

## MÀN HÌNH 22: ĐỔI CA (Shift Swap)

**Mục đích**: Yêu cầu đổi ca giữa 2 nhân viên

### Tabs: Yêu cầu của tôi | Yêu cầu đổi | Duyệt

**Tính năng**: Cả 2 NV phải đồng ý, Manager phải duyệt

---

## MÀN HÌNH 23: NGHỈ PHÉP (Leave)

**Mục đích**: Yêu cầu và duyệt nghỉ phép

### Tab 1: Nghỉ phép của tôi (tất cả user)
| Cột | Mô tả |
|-----|--------|
| Ngày bắt đầu | Start date |
| Ngày kết thúc | End date |
| Loại nghỉ | Leave type badge |
| Số ngày | Days count |
| Lý do | Reason |
| Trạng thái | Badge: Chờ(vàng) / Duyệt(xanh) / Từ chối(đỏ) / Huỷ(xám) |
| Thao tác | [👁️ Chi tiết] [❌ Hủy] (nếu đang chờ) |

### Tab 2: Tất cả nghỉ phép (Manager only)
- Thêm cột: Tên NV
- Filter: Tìm NV, Phòng ban, Loại, Trạng thái, Khoảng thời gian

### Tab 3: Chờ duyệt (Manager only)
- Actions: [✅ Duyệt] [❌ Từ chối]
- Dialog từ chối có textarea lý do

### Dialog Tạo nghỉ phép:
- Dropdown: Nhân viên (auto nếu NV thường, dropdown nếu manager)
- DatePicker: Ngày bắt đầu, Ngày kết thúc
- Dropdown: Loại nghỉ (Không lương, Phép năm, Có lương, ...)
- TextField: Lý do
- Dropdown: Ca (nếu áp dụng)
- Tự động tính số ngày nghỉ
- [✅ Gửi] [❌ Hủy]

### Loại nghỉ (Enum):
- Nghỉ không lương (UnpaidLeave)
- Phép năm (AnnualLeave)
- Nghỉ có lương (PaidLeave)
- Nghỉ bệnh (SickLeave)
- Nghỉ thai sản (MaternityLeave)
- ...

---

## MÀN HÌNH 24: CÀI ĐẶT LƯƠNG (Salary Settings)

**Mục đích**: Cấu hình lương và phúc lợi cho từng nhân viên

### Filter:
- Search NV (tên/mã)
- Dropdown: Đã cấu hình / Chưa cấu hình
- Dropdown: Loại lương (Giờ/Ngày/Tháng)
- Dropdown: Bảo hiểm (Bắt buộc/Tự nguyện/Không)

### DataTable:
| Cột | Mô tả |
|-----|--------|
| Mã NV | Code |
| Họ tên | Full name |
| Phòng ban | Department |
| Lương cơ bản | Base salary (formatted VND) |
| Phụ cấp cố định | Fixed allowance |
| Phụ cấp ngày | Daily allowance |
| Bảo hiểm | Insurance type |
| Trạng thái | Badge Đã cấu hình(xanh) / Chưa(xám) |
| Thao tác | [✏️ Sửa] [👁️ Xem hồ sơ] |

### Dialog Cấu hình lương NV:
- **Section Loại lương**: Dropdown (Tháng/Ngày/Giờ)
- **Section Lương**: Input lương cơ bản (format tiền tệ)
- **Section Phụ cấp**:
  - Input: Phụ cấp cố định, Phụ cấp ăn trưa, Phụ cấp trách nhiệm
- **Section Bảo hiểm**:
  - Dropdown: Loại (Bắt buộc/Tự nguyện/Không)
  - Input: % đóng, Số tiền khấu trừ
- **Section Lịch làm việc**:
  - Selector: Số ca/ngày
  - Checkboxes: Ngày nghỉ trong tuần
  - Dropdown: Loại chấm công (Chỉ vào / Vào-Ra / Theo giờ)
- [💾 Lưu] [❌ Hủy]

---

## MÀN HÌNH 25: BẢNG LƯƠNG (Payroll)

**Mục đích**: Tổng hợp bảng lương tháng

**AppBar**: Title "Tổng hợp lương" + Month/Year selector + [📤 Excel] [📸 PNG] + Column selector

### DataTable (cột có thể ẩn/hiện):
| Cột | Mô tả |
|-----|--------|
| Mã NV | Code |
| Họ tên | Full name |
| Chức vụ/PB | Position + Department |
| Ngày có mặt | Days present |
| Ngày vắng | Days absent |
| Ngày muộn | Days late |
| Tổng giờ | Total paid hours |
| Lương cơ bản | Base salary |
| Phụ cấp ăn | Meal allowance |
| Thưởng chuyên cần | Attendance bonus |
| BHXH | Social insurance deduction |
| Thuế | Tax deductions |
| Tổng khấu trừ | Total deductions |
| Lương thực nhận | Net salary |
| Ghi chú | Remarks |

**Tính năng**: Column visibility toggle, sort, multi-select, export Excel (có format header/data/footer), PNG export

---

## MÀN HÌNH 26: PHIẾU LƯƠNG (Payslip)

**Mục đích**: Xem và tải phiếu lương cá nhân

### Danh sách:
- Month/Year selector
- List phiếu lương (mới nhất trước)
- Mỗi item: Tháng, Kỳ, Lương brutto, Lương netto, [👁️ Xem] [📥 PDF]

### Chi tiết phiếu lương:
- Thông tin NV (tên, mã, PB, chức vụ)
- Bảng phân tích lương:
  - Lương cơ bản
  - Các khoản phụ cấp (từng dòng)
  - Các khoản khấu trừ (từng dòng)
  - Lương thực nhận (bold, highlight)
- YTD summary
- Buttons: [📥 PDF] [🖨️ In] [📧 Email]

---

## MÀN HÌNH 27: BÁO CÁO LƯƠNG (Payroll Report)

### Tab 1: Tổng quan
- DateRange, metrics (tổng lương, trung bình, khấu trừ, phụ cấp, SL NV)
- Pie chart: Phân bổ chi phí

### Tab 2: Theo phòng ban
- Table: PB, SL NV, Tổng lương, TB lương, % tổng
- Drill-down

### Tab 3: Theo chức vụ
- Table: Chức vụ, SL, Tổng, TB

### Tab 4: Theo hình thức lương (giờ vs tháng)

---

## MÀN HÌNH 28: THƯỞNG/PHẠT (Bonus & Penalty)

### Tab 1: Danh sách giao dịch
**Filter**: Date presets, Loại (Thưởng/Phạt), Tìm NV

| Cột | Mô tả |
|-----|--------|
| NV | Tên/Mã |
| Loại | Badge: Thưởng(xanh lá) / Phạt(đỏ) |
| Số tiền | Formatted VND |
| Lý do | Reason |
| Ngày | Date |
| Người duyệt | Approver |
| Trạng thái | Badge |
| Thao tác | [👁️] [✏️] [🗑️] |

### Tab 2: Thống kê
- Metrics: Tổng thưởng, Tổng phạt, Chênh lệch, TB/NV
- Bar chart: Xu hướng thưởng vs phạt (7/30/90 ngày)
- Pie chart: Phân bổ theo PB
- Top 5 NV thưởng cao nhất
- Top 5 NV phạt cao nhất

### Dialog Thêm mới:
- Dropdown: Nhân viên (searchable)
- Radio: Thưởng / Phạt
- Input: Số tiền (format VND)
- TextField: Lý do
- DatePicker: Ngày hiệu lực
- [💾 Lưu] [❌ Hủy]

---

## MÀN HÌNH 29: TẠM ỨNG LƯƠNG (Advance Requests)

### Filter: Trạng thái, Date presets, Tìm NV, Sort

| Cột | Mô tả |
|-----|--------|
| Mã/Tên NV | Employee |
| Ngày yêu cầu | Request date |
| Số tiền | Formatted VND |
| Lý do | Reason |
| Trạng thái | Badge: Chờ(cam) / Duyệt(xanh) / Từ chối(đỏ) |
| Ngày duyệt | Approval date |
| Người duyệt | Approver |
| Thao tác | [👁️] [❌ Hủy] (nếu pending và của mình) |

### Pagination: 25/50/100/200

### Dialog Tạm ứng mới:
- Dropdown: NV (auto hoặc dropdown)
- Input: Số tiền (hiển thị max có thể tạm ứng)
- TextField: Lý do
- DatePicker: Ngày yêu cầu
- DatePicker: Ngày hoàn trả (optional)
- [✅ Gửi yêu cầu] [❌ Hủy]

### Dialog Duyệt (Manager):
- Tóm tắt yêu cầu
- Input: Số tiền duyệt (có thể < yêu cầu)
- Dropdown: Lịch trả (1/2/3 tháng)
- [✅ Duyệt] [❌ Từ chối + lý do] [Hủy]

---

## MÀN HÌNH 30: KPI

### Tab 1: Dashboard KPI
- Dropdown chọn kỳ
- Metrics: Tổng NV có KPI, % đạt target, TB thưởng KPI
- Charts: Phân bổ KPI (histogram), Top/Bottom performers (bar), Xu hướng (line)

### Tab 2: Kỳ đánh giá (Periods)
| Cột | Mô tả |
|-----|--------|
| Tên kỳ | Period name |
| Ngày bắt đầu | Start date |
| Ngày kết thúc | End date |
| Trạng thái | Active/Closed |
| Thao tác | [✏️] [👁️ Xem targets] [💰 Xem lương] [🔒 Đóng kỳ] |

### Tab 3: Mục tiêu KPI
- Dropdown kỳ
- Table: NV, Chỉ tiêu, Giá trị mục tiêu, Trọng số %, Giá trị hiện tại, % đạt, Trạng thái

### Tab 4: Lương KPI
- Dropdown kỳ
- Table: NV, Lương cơ bản, Thưởng KPI, Tổng lương, Ngày chi
- [✅ Duyệt chi] [📤 Export sang Payroll]

### Tab 5: Cấu hình Google Sheets
- Trạng thái service account
- Upload file JSON
- Nút test kết nối
- Cấu hình sync (tần suất, dữ liệu sync)

---

## MÀN HÌNH 31: QUẢN LÝ TÀI SẢN (Asset Management)

### Tab 1: Tài sản
**Filter**: Search, Trạng thái (Active/Bảo trì/Hỏng/Thanh lý/Thất lạc/Trong kho), Loại (Điện tử/Nội thất/Xe/Công cụ/Máy móc/Phần mềm/Khác), Danh mục

| Cột | Mô tả |
|-----|--------|
| Mã tài sản | Asset code |
| Tên | Name |
| Loại | Type badge |
| Người giữ | Current owner |
| Vị trí | Location |
| Ngày mua | Acquisition date |
| Trạng thái | Color-coded badge |
| Giá trị | Formatted VND |
| Thao tác | [👁️] [✏️] [🔄 Chuyển] [🗑️] |

### Tab 2: Chuyển giao
- Lịch sử chuyển tài sản: Tên TS, Từ NV, Đến NV, Ngày, Loại chuyển, Trạng thái

### Tab 3: Kiểm kê
- Bản ghi kiểm kê vật lý: Ngày, Người kiểm, Tổng TS, Tình trạng, Status

### Tab 4: Danh mục - CRUD danh mục tài sản

### Tab 5: Thống kê
- Tổng TS theo danh mục, pie chart theo trạng thái, giá trị, khấu hao, chi phí bảo trì

### Dialog Thêm tài sản:
- Mã (auto hoặc manual), Tên, Loại, Danh mục
- DatePicker ngày mua, Giá trị gốc, Tình trạng
- Vị trí, Người giữ (dropdown NV), Nhà cung cấp, Serial number
- Upload ảnh
- [💾 Lưu] [❌ Hủy]

### Dialog Chuyển tài sản:
- Dropdown TS, Từ NV (auto), Đến NV (dropdown)
- Loại chuyển (Giao/Chuyển/Trả/Bảo trì/Thanh lý)
- Đánh giá tình trạng, Lý do, Ngày chuyển
- [✅ Xác nhận] [❌ Hủy]

---

## MÀN HÌNH 32: THU CHI (Cash Transactions)

### Tab 1: Giao dịch
**Filter**: Date presets, Loại (Chi/Thu), Danh mục, Trạng thái

| Cột | Mô tả |
|-----|--------|
| Ngày | Date |
| Loại | Badge: Chi(đỏ) / Thu(xanh lá) |
| Mô tả | Description |
| Danh mục | Category |
| Số tiền | Formatted VND |
| Trạng thái | Badge |
| Thao tác | [👁️] [✏️] [🗑️] |

**Summary Cards**: Tổng thu, Tổng chi, Dòng tiền ròng, Ngân sách vs Thực tế

### Tab 2: Danh mục - CRUD danh mục giao dịch
### Tab 3: Tài khoản ngân hàng - Danh sách TK, Số dư
### Tab 4: VietQR Banks - Danh sách ngân hàng hỗ trợ QR (read-only)

### Dialog Giao dịch mới:
- DatePicker, Loại (Chi/Thu), Danh mục, Số tiền, Mô tả
- Tên người nhận/trả, TK ngân hàng, Trạng thái (Draft/Submitted)
- [💾 Lưu] [❌ Hủy]

---

## MÀN HÌNH 33: TRUYỀN THÔNG NỘI BỘ (Communication)

### Tab 1: Dashboard
- Stats cards: SL tin gần đây, Tổng tin tức, Thông báo chưa đọc, Đào tạo chờ
- Bài viết xem nhiều nhất, Thông báo mới nhất

### Các Tab: Tất cả | Tin tức | Thông báo | Quy định | Đào tạo | Sự kiện | Chính sách

**Mỗi tab**:
- Toggle Grid/List view
- Search box
- Filter: Ưu tiên (Cao/Bình thường/Thấp)
- Sort: Mới nhất, Cũ nhất, Xem nhiều, Thích nhiều

### Card truyền thông:
- Thumbnail / Icon
- Title
- Excerpt (100 ký tự)
- Badge loại (Tin tức=xanh, Thông báo=đỏ, Chính sách=tím, ...)
- Badge ưu tiên
- View count, Like count (❤️)
- Ngày đăng
- Pin indicator (📌)
- [Xem thêm →]

### Chi tiết bài viết (Modal/Page):
- Full title, Cover image, Nội dung rich text
- Loại, Ưu tiên, Ngày đăng, Tác giả (avatar + tên)
- View count, Like/Reaction buttons
- Comments (threaded)
- [🔗 Chia sẻ] [🖨️ In] [📥 PDF]

### Dialog Tạo bài viết (Admin/Manager):
- TextField: Tiêu đề
- Rich Text Editor: Nội dung (WYSIWYG)
- Dropdown: Loại
- Dropdown: Ưu tiên
- Upload: Ảnh bìa
- Dropdown: Đối tượng (Tất cả / Phòng ban / Vai trò cụ thể)
- DateTimePicker: Lên lịch đăng
- Toggle: 📌 Ghim lên đầu
- Toggle: Cho phép comment
- [📤 Đăng] [💾 Lưu nháp] [❌ Hủy]

---

## MÀN HÌNH 34: QUẢN LÝ CÔNG VIỆC (Task Management)

### Tab 1: Danh sách
**Filter**: Search, Trạng thái (To Do/In Progress/In Review/Completed/Cancelled/On Hold), Ưu tiên (Low/Medium/High/Urgent), Loại (Task/Bug/Feature/Improvement/Meeting/Other), Người nhận, DateRange

| Cột | Mô tả |
|-----|--------|
| ID | Task ID |
| Tiêu đề | Title |
| Mô tả | Description (rút gọn) |
| Loại | Type badge |
| Ưu tiên | Badge màu: Low(xanh dương), Medium(xanh lá), High(cam), Urgent(đỏ) |
| Người nhận | Assignee |
| Trạng thái | Status badge |
| Hạn | Due date |
| Tiến độ | Progress bar (0-100%) |
| Thao tác | [👁️] [✏️] [🗑️] |

### Tab 2: Kanban Board
- Columns: To Do | In Progress | In Review | Completed | On Hold | Cancelled
- Cards: Title, priority badge, avatar người nhận, due date, progress %
- Drag-and-drop giữa columns
- Filter controls

### Tab 3: Thống kê
- Pie/Donut: Task theo trạng thái
- Bar chart: Task theo ưu tiên
- Table: Task theo người nhận
- Số task quá hạn (highlight đỏ)
- Tỷ lệ hoàn thành (tuần/tháng/năm)
- TB thời gian hoàn thành
- Phân bổ workload

### Dialog Tạo task:
- TextField: Tiêu đề (bắt buộc)
- Rich Text: Mô tả
- Dropdown: Loại, Ưu tiên
- Dropdown: Người nhận (single/multi)
- DatePicker: Ngày bắt đầu, Hạn chót
- Input: Giờ ước tính
- Upload: Tệp đính kèm (multi-file)
- [✅ Tạo] [💾 Nháp] [❌ Hủy]

### Panel Chi tiết task (Side panel):
- Full info, Status dropdown, Progress slider
- Comments (reply thread)
- History/Activity log
- Linked tasks, Attachments preview
- [✏️ Sửa] [🔒 Đóng] [🗑️ Xoá]

---

## MÀN HÌNH 35: THÔNG BÁO (Notifications)

**AppBar**: Title "Thông báo" + Badge unread count

### Filter chips: Tất cả | Chưa đọc | Đã đọc

### Notification List (infinite scroll, 20 items/load):
- Icon/Avatar (theo loại)
- Title
- Message (rút gọn)
- Timestamp (timeago: "5 phút trước")
- Unread indicator (chấm xanh)
- Type badge: Info(xanh), Success(xanh lá), Warning(cam), Error(đỏ), ApprovalRequired(tím), Reminder(vàng)

### Loại thông báo:
LeaveRequest, AdvanceRequest, AttendanceCorrection, ScheduleRegistration, Payslip, System

### Tính năng:
- SignalR realtime push
- Popup overlay cho thông báo mới
- Click → đánh dấu đã đọc + navigate đến entity liên quan
- Swipe/Delete xoá thông báo

---

## MÀN HÌNH 36: BÁO CÁO HR (HR Report)

### Tab 1: Tổng quan
- Summary cards: Tổng NV active, NV inactive, Tỷ lệ nghỉ việc, TB thâm niên, Nam/Nữ
- Org chart mini, Xu hướng tuyển/nghỉ 3 tháng

### Tab 2: Nhân khẩu học
- Biểu đồ: Giới tính (pie), Tình trạng hôn nhân (pie), Trình độ học vấn (bar)
- Phân bổ độ tuổi (histogram), Phân bổ quê quán

### Tab 3: Thâm niên
- Nhóm: <1 năm, 1-3 năm, 3-5 năm, 5-10 năm, 10+ năm
- Chart + table, sort by join date

### Tab 4: Tỷ lệ nghỉ việc
- Trend chart 12 tháng, Lý do nghỉ, Phân tích theo PB

### Tab 5: Đào tạo
- Chương trình, % hoàn thành, Top khóa phổ biến

### Tab 6: Lương thưởng
- TB lương theo PB, Phân bổ lương (histogram), Lương vs thâm niên (scatter)

### Section Sinh nhật:
- Sinh nhật tháng này, 30 ngày tới

### Export: PDF, Excel, Print

---

## MÀN HÌNH 37: CÀI ĐẶT (Settings)

### Section Tài khoản:
- Avatar + Họ tên + Email + Role badge
- [✏️ Sửa hồ sơ]

### Section Ứng dụng:
- Toggle Dark Mode (On/Off)
- Dropdown Ngôn ngữ (Tiếng Việt / English)
- Toggle Thông báo

### Section Kết nối:
- Server URL hiển thị
- [⚙️ Cấu hình Server]
- Toggle Auto-sync
- Indicator trạng thái sync

### Section Thông tin:
- Phiên bản app
- Links: Điều khoản, Chính sách, Hỗ trợ, Về ứng dụng

### Section Đăng xuất:
- Button [🚪 Đăng xuất] (đỏ)
- Dialog xác nhận

---

## MÀN HÌNH 38: TRUNG TÂM CÀI ĐẶT (Settings Hub)

**Mục đích**: Grid/List navigation đến tất cả cài đặt hệ thống (Admin only)

### Các mục (mỗi mục = Card với icon + title + mô tả + status badge):
1. 💰 Cài đặt lương → SalarySettingsScreen
2. 🔄 Cài đặt ca → ShiftSettingsScreen
3. 🎄 Ngày lễ → HolidaySettingsScreen
4. 🏥 Bảo hiểm → InsuranceSettingsScreen
5. ⚠️ Quy định phạt → PenaltySettingsScreen
6. 💵 Phụ cấp → AllowanceSettingsScreen
7. 📱 Chấm công Mobile → MobileAttendanceSettingsScreen
8. 📟 Thiết bị → DeviceManagementSettingsScreen
9. ☁️ Google Drive → GoogleDriveSettingsScreen
10. 📊 Google Sheets → GoogleSheetsScreen
11. 🔐 Phân quyền vai trò → RolePermissionsScreen
12. 🏢 Phân quyền phòng ban → DepartmentPermissionsScreen
13. ⚙️ Hệ thống → SystemSettingsScreen

---

## MÀN HÌNH 39: CÀI ĐẶT CA LÀM VIỆC (Shift Settings)

| Cột | Mô tả |
|-----|--------|
| Mã ca | Shift code |
| Tên ca | Shift name |
| Giờ bắt đầu | HH:MM |
| Giờ kết thúc | HH:MM |
| Nghỉ giữa ca | Break info |
| Linh hoạt | Toggle |
| Thao tác | [✏️] [🗑️] |

### Dialog Thêm/Sửa:
- Mã ca, Tên ca, TimePicker giờ bắt đầu/kết thúc
- TimePicker giờ nghỉ, Thời lượng nghỉ (phút)
- Toggle linh hoạt, Mô tả
- [💾 Lưu] [❌ Hủy]

---

## MÀN HÌNH 40: CÀI ĐẶT NGÀY LỄ (Holiday Settings)

### Tab 1: Ngày lễ cố định (quốc gia) - read-only
### Tab 2: Ngày lễ công ty - CRUD
### Tab 3: Cấu hình cuối tuần - Checkboxes T2→CN

### Dialog Thêm ngày lễ:
- Tên, DatePicker bắt đầu/kết thúc, Loại (Cả ngày/Nửa ngày), Toggle có lương, Ghi chú

---

## MÀN HÌNH 41: CÀI ĐẶT BẢO HIỂM (Insurance Settings)

| Cột | Mô tả |
|-----|--------|
| Loại BH | Insurance type |
| % Bao phủ | Coverage % |
| % NV đóng | Employee % |
| % Cty đóng | Employer % |
| Ngày hiệu lực | Effective date |
| Trạng thái | Toggle Active/Inactive |
| Thao tác | [✏️] [👁️] |

---

## MÀN HÌNH 42: CÀI ĐẶT PHẠT (Penalty Settings)

| Cột | Mô tả |
|-----|--------|
| Tên quy tắc | Rule name |
| Mô tả | Description |
| Điều kiện | Condition |
| Số tiền/% | Amount or % salary |
| Danh mục | Category |
| Trạng thái | Toggle |
| Thao tác | [✏️] [🗑️] |

---

## MÀN HÌNH 43: CÀI ĐẶT PHỤ CẤP (Allowance Settings)

| Cột | Mô tả |
|-----|--------|
| Tên phụ cấp | Name |
| Loại | Cố định/Ngày/Giờ |
| Số tiền/Mức | Amount or rate |
| Chịu thuế | Toggle |
| Trạng thái | Toggle |
| Thao tác | [✏️] [🗑️] |

---

## MÀN HÌNH 44: CÀI ĐẶT CHẤM CÔNG MOBILE (Mobile Attendance Settings)

### Section 1: Vị trí làm việc
| Cột | Mô tả |
|-----|--------|
| Tên | Location name |
| Địa chỉ | Address |
| Tọa độ | Lat/Long |
| Bán kính | Meters |
| Trạng thái | Active/Inactive |
| Thao tác | [✏️] [🗑️] |

### Section 2: Trung tâm đăng ký khuôn mặt

### Section 3: Quy tắc tự động duyệt
- Input khoảng cách ngưỡng (VD: trong 100m = tự duyệt)
- Input điểm khớp mặt ngưỡng (VD: >95% = tự duyệt)

### Dialog Thêm vị trí:
- Tên, Địa chỉ, GPS picker (bản đồ hoặc manual), Bán kính (m)

---

## MÀN HÌNH 45: CÀI ĐẶT HỆ THỐNG (System Settings)

- Giờ kết thúc ngày (cho chấm công)
- Tiền tệ, Định dạng ngày
- Thông tin công ty (tên, logo, địa chỉ, MST)
- Cài đặt thông báo
- Lịch backup, API timeout, Thời gian giữ log

---

## MÀN HÌNH 46: CÀI ĐẶT GOOGLE DRIVE

- Trạng thái OAuth
- TK đã xác thực
- Cấu hình thư mục Drive (ID, backup, documents)
- Auto-backup frequency
- [🔗 Xác thực Google] [🧪 Test kết nối] [❌ Xoá xác thực]

---

## MÀN HÌNH 47: CÀI ĐẶT GOOGLE SHEETS

- Upload service account JSON
- Danh sách spreadsheets đã kết nối
- Cấu hình sync (tần suất, dữ liệu)
- [🧪 Test] [🔄 Sync ngay]

---

## MÀN HÌNH 48: PHÂN QUYỀN VAI TRÒ (Role Permissions)

**Layout**:
- Dropdown chọn vai trò: Admin, Manager, HR, SuperAdmin, ...
- Ma trận phân quyền bên dưới

### Ma trận:
- Rows: Tính năng (Nhân viên, Chấm công, Lương, KPI, ...)
- Columns: Hành động (Xem, Tạo, Sửa, Xoá, Duyệt, Xuất)
- Values: Checkbox (bật/tắt)
- Màu: Xanh = cho phép, Xám = không

- [📋 Clone vai trò] [🔄 Reset mặc định] [💾 Lưu thay đổi]

---

## MÀN HÌNH 49: PHÂN QUYỀN PHÒNG BAN (Department Permissions)

- Dropdown/Tree chọn phòng ban
- Dropdown chọn vai trò
- Ma trận: Xem NV PB, Quản lý NV PB, Duyệt, Xem lương PB, Xem báo cáo PB

---

## MÀN HÌNH 50: QUẢN LÝ THIẾT BỊ (Devices - ADMS)

**AppBar**: Title "Thiết bị" + [➕ Thêm thiết bị]

| Cột | Mô tả |
|-----|--------|
| Tên thiết bị | Device name |
| Serial | Serial number |
| IP | IP address |
| Vị trí | Location |
| Online | 🟢 Xanh (< 2 phút) / 🔴 Đỏ (> 2 phút) |
| Lần cuối | "2 phút trước" |
| SL users | User count |
| SL chấm công | Attendance count (tháng này) |
| Trạng thái | Active/Inactive badge |
| Thao tác | [👁️] [✏️] [⚙️ Cài đặt] [🗑️] |

### Dialog Thêm thiết bị:
- Tên, Serial, IP, Port (default 4370), Vị trí, Mô tả
- [📱 Đăng ký] [❌ Hủy]

---

## MÀN HÌNH 51: NGƯỜI DÙNG THIẾT BỊ (Device Users)

| Cột | Mô tả |
|-----|--------|
| PIN | Mã trên thiết bị |
| Tên | Name (từ thiết bị) |
| Số thẻ | Card number |
| Cấp | 0=User, 14=Admin |
| Trạng thái | Active/Inactive |
| NV liên kết | Mapped employee |
| Thao tác | [🔗 Liên kết NV] [✏️] [🗑️] [👆 Xem vân tay] |

### Dialog Liên kết:
- Info device user (read-only)
- Dropdown chọn nhân viên (searchable)
- [💾 Lưu] [❌ Hủy]

---

## MÀN HÌNH 52: CẤU HÌNH THIẾT BỊ (Device Management Settings)

- Dropdown chọn thiết bị
- **Device Info** (read-only): Tên, Serial, MAC, Firmware, SL users, SL chấm công
- **Network**: IP, Port, [🧪 Test kết nối]
- **Sync**: Toggle auto-sync, Tần suất, Toggle pull attendance, Toggle push users
- **Quy tắc**: Giờ kết thúc ngày, Timezone
- **Buttons**: [🔒 Khóa/Mở thiết bị] [🔄 Restart] [🗑️ Xoá bộ nhớ]

---

## MÀN HÌNH 53: ĐĂNG KÝ KHUÔN MẶT (Face Registration)

### Quy trình:
1. **Chọn nhân viên**: Dropdown/Search + hiện ảnh mặt hiện có + "2/5 ảnh đã tải"
2. **Upload ảnh**: [➕ Upload] → file picker → preview
3. **Crop ảnh**: Rectangle selector, zoom, rotate → [✂️ Crop & Save]
4. **Kho ảnh**: Grid thumbnail + upload date + quality score + [❌ Xoá]

---

## MÀN HÌNH 54: QUẢN TRỊ HỆ THỐNG (System Admin - SuperAdmin Only)

**AppBar**: Title "Quản trị hệ thống" + Subtitle "SuperAdmin" + Health indicator

### 11 Tabs (TabBar ngang, scroll, icons + labels):

#### Tab 1: Dashboard
- Metrics: Tổng stores, Active stores, Users, Devices, Online/Offline, Attendance hôm nay
- Charts: Top stores by users (bar), Device online ratio (pie)
- Timeline hoạt động gần đây
- Navigation shortcuts

#### Tab 2: Cửa hàng (Stores)
| Cột | Mô tả |
|-----|--------|
| Mã | Store code |
| Tên | Store name |
| Liên hệ | Contact person |
| Email | Contact email |
| SĐT | Phone |
| Gói dịch vụ | Package |
| SL users | Count |
| SL devices | Count |
| Trạng thái | Badge: Active(xanh)/Inactive(xám)/Suspended(đỏ) |
| Thao tác | [👁️] [✏️] [⏸️ Tạm dừng] [▶️ Kích hoạt] [🗑️] |

#### Tab 3: Users
| Cột | Mô tả |
|-----|--------|
| Tên | Username |
| Cửa hàng | Store name |
| Vai trò | Admin/Manager/HR/User |
| Email | Email |
| Trạng thái | Active/Locked |
| Đăng nhập cuối | Last login |
| Thao tác | [✏️] [🔒/🔓] [🗑️] [🔑 Reset mật khẩu] |

#### Tab 4: Devices (Cross-store)
- Tương tự màn hình 50 nhưng có thêm cột "Cửa hàng"

#### Tab 5: Đại lý (Agents)
| Cột | Mô tả |
|-----|--------|
| Mã | Agent code |
| Tên | Name |
| SL cửa hàng | Store count |
| Hoa hồng % | Commission |
| Trạng thái | Active/Inactive |
| Thao tác | [✏️] [⏸️] [👁️ Xem stores] |

#### Tab 6: Licenses
| Cột | Mô tả |
|-----|--------|
| License key | Masked: XXXX-****-XXXX |
| Cửa hàng | Store name |
| Gói | Package |
| Ngày kích hoạt | Activation date |
| Ngày hết hạn | Expiration |
| Trạng thái | Badge: Valid(xanh)/Expiring(cam)/Expired(đỏ) |
| Còn lại | Days remaining |
| Thao tác | [👁️] [🔄 Gia hạn] [❌ Thu hồi] |

#### Tab 7: Cài đặt (Global Settings)
- Company info, SMTP, SMS, API rate limits, Data retention, Backup, Security

#### Tab 8: Database
- Connection status, DB size, Backup status/schedule
- [🔍 Check integrity] [💾 Backup] [📅 Schedule] [🧹 Cleanup] [📄 View logs]

#### Tab 9: Audit Log
| Cột | Mô tả |
|-----|--------|
| Thời gian | Timestamp |
| Người dùng | Username |
| Hành động | Action (Create/Update/Delete/Download) |
| Entity | Type + Name/ID |
| Kết quả | Success/Failure |
| IP | IP address |
| Thiết bị | Device/Browser |

#### Tab 10: Gói dịch vụ (Service Packages)
| Cột | Mô tả |
|-----|--------|
| Tên gói | Package name |
| Giá tháng | Monthly price (VND) |
| Tính năng | Feature count/icons |
| Max users | Limit |
| Max devices | Limit |
| Max chấm công | Monthly limit |
| Trạng thái | Active/Discontinued |
| Thao tác | [✏️] [👁️] |

#### Tab 11: Khuyến mãi (Key Promotions)
| Cột | Mô tả |
|-----|--------|
| Tên KM | Promo name |
| Loại giảm | % or Fixed |
| Giá trị | Discount value |
| Gói áp dụng | Applicable packages |
| Từ ngày | Valid from |
| Đến ngày | Valid to |
| Đã dùng | Usage count |
| Trạng thái | Active/Expired |
| Thao tác | [✏️] [👁️ Xem usage] [⏸️ Tắt] |

---

## MÀN HÌNH 55: QUẢN LÝ NGOÀI GIỜ (Overtime)

### Tabs: Ngoài giờ của tôi | Tất cả yêu cầu | Duyệt | Báo cáo

| Cột | Mô tả |
|-----|--------|
| NV | Employee |
| Ngày | Date |
| Số giờ | Hours |
| Lý do | Reason |
| Trạng thái | Status badge |
| Thao tác | Actions |

---

## MÀN HÌNH 56: PHIẾU PHẠT (Penalty Tickets)

| Cột | Mô tả |
|-----|--------|
| NV | Employee |
| Loại vi phạm | Violation type |
| Ngày | Date |
| Số tiền phạt | Fine amount |
| Trạng thái | Xác nhận/Khiếu nại/Đã xử lý |
| Thao tác | Actions |

### Form khiếu nại: Lý do + bằng chứng

---

## MÀN HÌNH 57: ĐÀO TẠO (Training)

### Tabs: Chương trình | Đào tạo của tôi | Phân công | Chứng chỉ

- Chương trình: Tên, Giảng viên, Lịch, Sức chứa, SL đăng ký, [Đăng ký]
- Của tôi: Khóa đã gán, trạng thái hoàn thành, tải chứng chỉ

---

## MÀN HÌNH 58: TÀI LIỆU HR (HR Documents)

**Quản lý tài liệu nhân sự**

---

## MÀN HÌNH 59: QUY ĐỊNH CÔNG TY (Company Rules)

**Tương tự Communication** nhưng cho nội quy/quy định

---

## MÀN HÌNH 60: QUẢN LÝ TÀI KHOẢN (Account Management)

- Thông tin cá nhân (editable)
- Đổi mật khẩu
- Xác thực 2 bước
- Thiết bị đang đăng nhập
- Lịch sử đăng nhập

---

## MÀN HÌNH 61: CÀI ĐẶT THÔNG BÁO (Notification Settings)

### Toggle theo loại:
- Email, In-app, Push, SMS
- Tần suất: Realtime, Hàng ngày, Hàng tuần

---

## MÀN HÌNH 62: AI SETTINGS

**Cấu hình tích hợp AI**

---

## MÀN HÌNH 63: CONTENT MANAGEMENT

**Quản lý nội dung website/ứng dụng**

---

## MÀN HÌNH 64: GEOFENCE

**Quản lý vùng địa lý cho chấm công**

---

## MÀN HÌNH 65: USER MANAGEMENT

**Quản lý tài khoản người dùng hệ thống**

---

## MÀN HÌNH 66: DIRECT MANAGER VIEW

**Xem nhân viên trực tiếp quản lý** - Filter EmployeesScreen theo managerId = currentUser

---

## REUSABLE WIDGETS

### 1. StatCard
- Icon + Title + Value + Trend indicator
- Màu nền tuỳ loại (success/warning/error/info)

### 2. LoadingWidget
- Circular progress indicator + text "Đang tải..."
- Skeleton shimmer effect

### 3. EmptyState
- Icon lớn + Message + CTA button
- Tuỳ chỉnh theo context

### 4. ResponsiveTable
- Desktop: Full DataTable với sort, pagination
- Mobile: Card list với thông tin chính
- Sticky header, hover effect, checkbox select

### 5. NotificationOverlay
- Toast notification góc trên phải
- Auto-dismiss 5 giây
- Color-coded: success(xanh)/error(đỏ)/warning(cam)/info(xanh dương)

### 6. FaceIdCaptureWidget
- Camera full-screen cho chụp khuôn mặt
- Face detection overlay
- Countdown timer

### 7. ImageCropDialog
- Crop interface rectangle selector
- Zoom/Rotate controls
- Preview

### 8. RichTextEditor
- WYSIWYG editor (web platform)
- Bold, Italic, Underline, Lists, Links, Images, Tables

---

## RESPONSIVE BEHAVIOR

### Mobile (< 768px):
- Table → Card list (scroll ngang ẩn cột phụ)
- Tabs → Icon-only hoặc label-only compact
- Actions → FAB hoặc dropdown menu
- Dialogs → Bottom sheet
- Pagination controls compact

### Tablet (768px - 1024px):
- Multi-column bắt đầu
- Table hiển thị đầy đủ (scroll ngang)
- Side panels collapse/expand

### Desktop (> 1024px):
- Full multi-column layout
- Side panels luôn hiện
- Master-detail view
- Tất cả cột table hiển thị

---

## FORM VALIDATION & FEEDBACK

- Required fields: Dấu * đỏ
- Error: Text đỏ bên dưới field + viền đỏ
- SnackBar: Floating bottom, auto-dismiss 5s, icon + message
- Submit disabled khi chưa valid
- Debounced search (300ms)
- Sort indicators trên column headers

---

## LOCALIZATION

- **Tiếng Việt**: dd/MM/yyyy HH:mm:ss, 1.234.567,89 ₫
- **English**: MM/dd/yyyy HH:mm:ss, 1,234,567.89 ₫
- Tất cả labels, buttons, messages đều song ngữ
- Timeago format: "5 phút trước" / "5 minutes ago"

---

## REALTIME FEATURES

- **SignalR WebSocket**:
  - Attendance updates realtime
  - Device status updates
  - Notification push
  - Toast overlay cho thông báo mới

- **Auto-refresh**:
  - Dashboard: 30 giây
  - Attendance: 5 giây (toggle)
  - Device status: 2 phút

---

## OFFLINE CAPABILITY

- LocalStorage cho: corrections, credentials, preferences
- Sync queue cho API calls thất bại
- Visual indicator pending sync
- Retry khi kết nối lại
