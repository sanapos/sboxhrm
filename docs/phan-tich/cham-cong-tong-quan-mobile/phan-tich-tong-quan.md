# Phân tích màn «Tổng quan» (góc nhìn chủ quán)

Ngày 09/11/2026, commit `51cf4666`. Chỉ phân tích, chưa sửa code.

Đã xem trên V2s: bản QA của BOSS và HRM, cửa hàng QA Retail. Ảnh trong thư mục `shots-tong-quan/`:
- `ov1`, `ov3`: BOSS «Tổng quan hôm nay».
- `ov4`, `ov6`: HRM «Tổng quan kinh doanh & nhân sự».

## Hai màn

| Màn | File | Dữ liệu |
|---|---|---|
| SBOX BOSS › tab Tổng quan («Tổng quan hôm nay») | `flutter_client/lib/features/boss/boss_dashboard_screen.dart` | `GET /api/pos/reports/boss/dashboard` (`PosReportsController.Boss.cs:24-215`) |
| SBOX HRM / POS › Tổng quan | `flutter_client/lib/screens/overview/business_overview_screen.dart` | Các API: sales summary, kỳ trước, stock, manager dashboard, attendance trends, overview todos |

## Bảng vấn đề

| # | Màn | Chủ quán thấy | Nguyên nhân trong code | Đề xuất | Ưu tiên · phạm vi |
|---|---|---|---|---|---|
| 1 | BOSS | Bấm «Doanh thu hôm nay», «Số đơn», «TB/đơn», «Đã thu» đều không có gì | `_RevenueHero` / `_HeroStat` không có onTap (:146-202) | Doanh thu mở «Kinh doanh» hôm nay (`BossReportDetailScreen(business)`). Số đơn mở danh sách đơn hôm nay (`PosSaleOrderListScreen` qua `_pushPos`). Đã thu mở «Cuối ngày» (tiền két, thực thu) | P1 · client |
| 2 | BOSS | «Doanh thu» khác «Đã thu» mà không biết vì sao | Doanh thu = tổng đơn hoàn tất. Đã thu = phiếu thu bán hàng theo phương thức (API :83-111). Chênh lệch là khách nợ, cọc, thu nợ cũ. API có trả `discount` (:177) nhưng app không hiện | Dòng phụ dưới hero: «Chưa thu X · Giảm giá Y», bấm vào xem giải thích | P1 · client (thêm «chưa thu» cần API) |
| 3 | BOSS | Thẻ «Tuần trước 1,2 tr · −100% cùng giờ» khó hiểu, tưởng là cả tuần trước | Số là doanh thu cùng thứ tuần trước tính tới giờ này, nhưng nhãn chỉ ghi «Tuần trước» (:229-261) | Đổi nhãn «Cùng giờ, thứ … tuần trước». Bấm mở «Kinh doanh» so kỳ | P1 · client |
| 4 | BOSS | «Tiền đã thu theo phương thức» không bấm được | `_PaymentsCard` không có onTap (:298-318) | Bấm mở «Cuối ngày» hoặc «Sổ quỹ» | P1 · client |
| 5 | BOSS | «Bàn đang mở 3 · tạm tính 2 tr» không biết bàn nào, mở từ lúc nào | Thẻ không có onTap (:332-338). API chỉ trả số bàn + tổng tiền (`openTables`) | Bấm ra danh sách bàn đang mở: tên bàn, giờ mở, tạm tính, người phục vụ | P2 · API + client |
| 6 | BOSS | Biểu đồ «Doanh thu theo giờ» chỉ để xem | `SboxLineChart` không bấm được (:263-296) | Bấm một giờ ra các đơn trong giờ đó (lọc danh sách đơn theo giờ) | P3 · client (+ lọc giờ ở API đơn) |
| 7 | BOSS | Thiếu số chủ quán cần mỗi ngày: chi phí / phiếu chi, tiền mặt trong két, hủy món / giảm giá, lãi ước tính, món bán chạy | Các số này có trong tab Báo cáo («Cuối ngày», «Nguy cơ gian lận», «Lãi lỗ») nhưng Tổng quan không nhắc tới, không có lối sang | Thêm khối «Tiền hôm nay» (thu, chi, tồn két → Cuối ngày) và «Bất thường» (hủy sau tạm tính, giảm giá tay → Nguy cơ gian lận) | P2 · client (API đã có) |
| 8 | BOSS | Nút nổi «+» che thẻ «Hôm qua cả ngày» và dòng «Cập nhật lúc…» | ListView không chừa đáy cho nút nổi (:105) | Chừa đáy khoảng 96dp | P1 · client |
| 9 | HRM/POS | 6 ô số đầu trang (Doanh thu, Lợi nhuận, Số đơn, Có mặt, Đi trễ, Vắng / Doanh thu÷NV) bấm không có gì | `SboxKpi` không truyền onTap (:224-244, :253-266, :284), dù widget có hỗ trợ | Doanh thu / Lợi nhuận / Số đơn mở «Báo cáo POS» hoặc «Đơn hàng» đúng kỳ. Có mặt / Đi trễ / Vắng / Nghỉ phép mở danh sách người (dữ liệu đã có ở `_todayTrend['employees']`, dùng lại `showAttendancePeopleSheet`) | P1 · client |
| 10 | HRM/POS | Chọn «Tháng này»: doanh thu là cả tháng, nhưng ô ngay cạnh «Có mặt hôm nay 4/7», «Vắng hôm nay 3» vẫn là hôm nay. Dễ đọc lẫn kỳ | `_combinedKpis` trộn POS theo kỳ với nhân sự theo hôm nay (:270-293) | Tách 2 hàng có tiêu đề «Kỳ: Tháng này» / «Hôm nay». Hoặc khi kỳ ≠ hôm nay thì ô nhân sự đổi sang số của kỳ (tổng lượt vắng / trễ) | P1 · client |
| 11 | HRM/POS | Thẻ «Hôm nay – tình trạng đi làm» và «Cơ cấu thanh toán» không có «Chi tiết». Cột biểu đồ không bấm được | `_todayAttendanceCard` (:351-380) và `_paymentDonut` (:390-401) không có onMore. `SboxBarChart` không có onTap | Thêm onMore (Tổng hợp chấm công · Theo ngày; Sổ quỹ). Bấm cột ngày mở tổng hợp đúng ngày đó | P2 · client |
| 12 | HRM/POS | Bảng «Doanh thu theo nhân viên bán» và «Nhân viên hôm nay» bấm dòng không ra gì | `SboxDataTable` không có onTap dòng (:477-556) | Bấm nhân viên mở đơn của người đó trong kỳ / chi tiết chấm công người đó | P2 · client |
| 13 | HRM/POS | «Lợi nhuận gộp» bị hiểu nhầm là lãi thật (chưa trừ chi phí) | Ô ghi «Lợi nhuận gộp», không nhắc chi phí | Ghi chú «chưa trừ chi phí». Bấm mở «Lãi lỗ» (doanh thu − giá vốn − chi phí) | P1 · client |
| 14 | HRM/POS | «Doanh thu / NV có mặt» khó hiểu với chủ quán | Chỉ số năng suất (:282-289) | Đổi thành «Chưa thu / khách nợ» hoặc «Chi phí hôm nay» — số chủ quán cần hơn | P2 · client |
| 15 | HRM/POS | «Hàng đã hết» (khi máy chủ cũ) không bấm được | Mục dự phòng không có onTap (:467) | Mở Hàng hóa, lọc hết hàng | P3 · client |

Phần đã làm tốt: «Cần xử lý» / «Việc cần xử lý» bấm được, đi đúng màn duyệt. «Đã chấm công» trên BOSS mở «Nhân viên hôm nay».

## Đề xuất thiết kế (điện thoại)

**Mọi con số đều bấm được và ra đúng chi tiết của nó.** Chữ phụ dưới số nói số đó tính thế nào, ví dụ «đơn đã thanh toán», «cùng giờ thứ Hai tuần trước».

**BOSS Tổng quan, theo thứ tự:**
1. Hero «Doanh thu hôm nay», kèm hàng phụ Số đơn · Đã thu · Chưa thu · Giảm giá. Bấm từng mục.
2. «Cần xử lý».
3. «Tiền hôm nay»: tiền mặt trong két, đã chi, chuyển khoản. Mở Cuối ngày.
4. «Bất thường hôm nay»: hủy sau tạm tính, giảm giá tay, ca lệch quỹ. Mở Nguy cơ gian lận.
5. So sánh (nhãn rõ «cùng giờ»).
6. Doanh thu theo giờ (bấm giờ).
7. Bàn đang mở (bấm ra danh sách), Nhân viên hôm nay.

**HRM/POS Tổng quan:**
- Hàng ô «Kỳ đã chọn» (doanh thu, lãi gộp, số đơn) tách khỏi hàng «Hôm nay» (có mặt, trễ, vắng, nghỉ phép).
- Ô nhân sự mở danh sách người, ô bán hàng mở báo cáo / đơn đúng kỳ.

**Ưu tiên:**
1. **P1, chỉ sửa app:** mục 1-4, 8-10, 13.
2. **P2:** mục 5 (cần API danh sách bàn), 7, 11, 12, 14.
3. **P3:** mục 6, 15.
