# Phân tích «Tổng hợp chấm công» trên điện thoại (góc nhìn chủ cửa hàng nhiều nhân viên)

Ngày 09/11/2026 — nhánh `fix/tingee-agent-scope-deploy` (BOSS so thêm `feat/boss-parity`, phần chấm công hai nhánh giống nhau). Chỉ phân tích, không sửa code.

Ảnh minh họa (390x844, dựng màn thật bằng kit guide_shots, 12 NV mẫu gồm 2 part-time lương theo giờ, ca tối 4 tiếng): thư mục `shots-tong-hop-cham-cong/` cạnh file này.
- `attsum-1-top.png`: đầu trang là 4 KPI, biểu đồ, xếp hạng.
- `attsum-2-kpi.png`: khối «Tổng quan & bộ lọc», sau đó tới đầu danh sách NV.
- `attsum-3-cards.png`, `attsum-4-cards.png`: thẻ NV. Part-time hiện «1.5 Ngày công», «5 ngày Vắng», «1.5/9 công».
- `byshift-*.png`: màn «Tổng hợp theo ca».
- Chữ trong ô thả xuống bị ô đen là do môi trường test thiếu font. Đây không phải lỗi app.

## 1. Màn nào, ở đâu

| Màn | File | Ghi chú |
|---|---|---|
| Tổng hợp chấm công (HRM + BOSS › Quản lý) | `flutter_client/lib/screens/attendance_summary_screen.dart` bọc `screens/attendance/attendance_summary_tab.dart` (6.500 dòng) | Nhánh mobile khi rộng < 600: `attendance_summary_tab.dart:1514-1580`. Admin/chủ thì dùng danh sách thẻ NV `_buildMobileEmployeeSummarySlivers` :4098-4527 |
| Tổng hợp theo ca | `screens/attendance_by_shift_screen.dart` bọc `screens/attendance/attendance_by_shift_tab.dart` (7.500 dòng) | Mobile :1390-1412, thẻ NV :6603+ |
| BOSS › Dashboard | `features/boss/boss_dashboard_screen.dart:338-352` | Thẻ «Đã chấm công X/Y» mở «Nhân viên hôm nay». **onTap = null nếu tài khoản thiếu quyền module Attendance** (:347) |
| BOSS › Nhân viên hôm nay | `features/boss/boss_staff_today_screen.dart:114-133` | 2 thẻ «Đã chấm / Chưa chấm» |
| BOSS › Quản lý | `features/boss/boss_manage_screen.dart:74-77` | Hai lối vào: «Tổng hợp chấm công» và «Tổng hợp theo ca» |
| (Đối chiếu) HRM Dashboard | `screens/dashboard_screen.dart:5713-5913` | Các ô KPI **đã** bấm được, mở danh sách (`_showPresentDetail` :6817, `_showAbsentDetail` :6477, `_showLateDetail` :7149). Đây là mẫu để làm theo |

Lưu ý: «Chấm công mobile» (`mobile_attendance_screen.dart`) là màn chấm GPS/khuôn mặt, không phải báo cáo. «Tổng hợp chấm công mobile» trong báo cáo này hiểu là màn tổng hợp mở trên điện thoại.

## 2. Bảng vấn đề

| # | Màn | Vấn đề (chủ nhìn thấy) | Nguyên nhân trong code | Đề xuất | Ưu tiên / phạm vi |
|---|---|---|---|---|---|
| 1 | Tổng hợp chấm công | 4 ô KPI đầu trang («Tổng giờ công», «Tổng số công», «Nhân viên 12», «TB giờ/NV») bấm không ra gì | `_buildInsight` :1653-1660 tạo `SboxKpi` mà không truyền `onTap`, dù widget có hỗ trợ (`widgets/sbox/sbox_report.dart:143`) | Bấm «Nhân viên» mở danh sách NV kèm giờ, công, vắng. Bấm «Tổng số công» / «Tổng giờ» mở danh sách sắp theo công / giờ | P1 · client |
| 2 | Tổng hợp chấm công | Hàng chip «Bản ghi 108 · Nhân viên 12 · Tổng giờ 545h48 (545.8h…» không bấm được. «Bản ghi», «Số ca» vô nghĩa với chủ. Chip «Tổng giờ» bị cắt chữ trên 390dp | `_buildStatsRow` :2237-2259 (`HrmStatItem` có `onTap` nhưng không dùng) | Mobile bỏ «Bản ghi», «Số ca». Thay bằng chip trạng thái bấm được (xem mục 3 phần đề xuất) | P1 · client |
| 3 | Tổng hợp theo ca | Ô «Đi trễ / Về sớm / Tăng ca» không bấm được. Con số là **lượt ca**, không phải **số người**: «Đi trễ 12» dễ bị hiểu là 12 người | `_buildModernStatCard` không có onTap (:2561-2612). Số đếm lấy theo bản ghi `records.where(lateMinutes>0)` :1349-1351 | Hiển thị «3 người · 12 lượt». Bấm vào mở danh sách người, mỗi người kèm các ngày trễ và số phút | P1 · client |
| 4 | BOSS › Nhân viên hôm nay | Thẻ «Đã chấm công 8 / Chưa chấm 4» bấm không phản hồi. Phải cuộn xuống mới thấy tên | `SboxMetricCard` :116, :124 không truyền `onTap` | Bấm thẻ thì lọc / cuộn tới nhóm đó (dữ liệu từng người **đã có** trong `/api/boss/staff-today`) | P1 · client |
| 5 | BOSS › Dashboard | Có tài khoản bấm «Đã chấm công 8/12» không ra gì | :347 `staffCanOpen(context,'Attendance') ? … : null` | Thiếu quyền thì vẫn mở màn «Nhân viên hôm nay» chỉ đọc (API BOSS riêng). Nếu không, hiện thông báo «Cần quyền Chấm công» thay vì im lặng | P1 · client |
| 6 | Cả hai màn tổng hợp | **NV lương theo giờ vẫn bị tính «công»**. Part-time 4h/ca hiện «1.5 Ngày công», thanh «1.5/9 công», ô ngày màu «Thiếu giờ» như đang làm thiếu. «Tổng số công» cửa hàng cộng lẫn công của NV giờ | `workCount = shiftRec?.workCount` :1049, lấy từ `computeDayWorkCredit` (`src/payroll_engine/lib/utils/shift_records_calculator.dart:1995-2007`). Hàm này chỉ dựa vào giờ, không xét loại lương. Map `_employeeCodeToRateType` đã dựng ở :722-737 nhưng **không chỗ nào đọc**. Tab theo ca không đọc rateType. Bảng lương thì đúng: case Hourly tính `rate × giờ` (`payroll_engine.dart:1570-1596`) | NV có `Benefit.RateType = Hourly` thì hiện **giờ** thay cho công: thẻ ghi «48,5 giờ», bỏ «x/26 công», ô ngày chỉ có 2 màu «có làm / không», tổng công chỉ cộng NV tính công. Excel / PNG ghi «—» ở cột công. Sửa luôn `_parseRateType` :1355-1363: null hiện bị coi là Hourly, ngược với engine (null là Monthly) | P1 · client (dữ liệu đã có, JSON `rateType: "Hourly"`) |
| 7 | Cả hai màn | Part-time / NV không có lịch bị đếm **«Vắng»** mọi ngày không đi (ảnh: «5 ngày Vắng»). Chủ tưởng NV nghỉ không phép | Trạng thái vắng (`dayStatesFor` :4164-4182) chỉ xét ngày nghỉ tuần và hồ sơ lương, không xét «không có lịch ca» với NV làm theo lịch | NV lương giờ hoặc NV có lịch: chỉ tính vắng ngày **có lịch mà không chấm**. Ngày không lịch để «Nghỉ» (xám) | P1 · client (đã có `workSchedules`) |
| 8 | Tổng hợp chấm công | Nhiều NV thì danh sách rất dài. Mỗi thẻ NV cao khoảng 410dp (tên, 2-3 ô số, chip ca, 2 ô số, lịch 30 ô, thanh tiến độ). 12 NV đã khoảng 6 màn hình, 40 NV khoảng 20 màn | `buildEmployeeCard` :4193-4389 | Dòng gọn 2 dòng, khoảng 64dp: «Tên · chi nhánh» / «22 công · 176 giờ · 2 vắng · 3 trễ» kèm chấm màu cảnh báo. Lịch tháng chỉ hiện trong màn chi tiết | P1 · client |
| 9 | Tổng hợp chấm công (+ theo ca) | Không sắp xếp được, không tìm kiếm, không lọc «ai có vấn đề». Luôn xếp theo tên | `employees..sort(by name)` :4129-4130 (theo ca :6632-6633). Lọc NV chỉ qua hộp thoại chọn (`_buildEmployeeFilter` :3458) | Ô tìm kiếm. Sắp theo «Vắng nhiều / Trễ nhiều / Ít công / Nhiều giờ / Tên». Chip lọc «Có vấn đề» (vắng, thiếu chấm, trễ) | P1 · client |
| 10 | Tổng hợp chấm công | Phải cuộn khoảng 1,4 màn mới tới danh sách NV: 4 KPI, biểu đồ, xếp hạng top 5, tổng quan, bộ lọc 4 hàng | Thứ tự khối :1516-1535, :1557-1579 | Mobile: thanh kỳ và chip trạng thái ngay đầu trang, danh sách ngay sau. Biểu đồ thu vào mục «Xem biểu đồ». Bộ lọc gom vào 1 nút mở sheet | P2 · client |
| 11 | Cả hai màn | Không có góc nhìn **theo ngày**. Chủ hỏi «hôm nay / thứ Ba ai đi, ai vắng, ai trễ» thì phải mở từng NV. Cột biểu đồ «Người đi làm theo ngày» không bấm được. Ô ngày trong lịch NV chỉ có tooltip (trên điện thoại phải nhấn giữ) | `SboxBarChart` không có onTap. `widgets/attendance/attendance_day_strip.dart:101` chỉ có Tooltip | Thêm chế độ «Theo ngày»: chọn 1 ngày (dải tuần cuộn ngang), các chip Có mặt / Đi trễ / Về sớm / Vắng / Nghỉ phép / Thiếu chấm / Đang làm, bấm chip ra danh sách. Bấm cột biểu đồ hoặc ô lịch thì nhảy tới ngày đó | P2 · client |
| 12 | Cả hai màn | Không chọn được ngày hoặc khoảng tùy ý (kỳ lương 26→25, một ngày cụ thể). Ô «01/11/26 – 09/11/26» chỉ để hiển thị | `_buildDateRangeDisplay` :5451 là Container, không onTap. Preset chỉ có 6 lựa chọn :5232-5241 | Bấm ô ngày thì mở chọn khoảng. Thêm preset «Kỳ lương này» | P2 · client (cha phải nhận customFrom/To: `AttendanceDateRangePresets.resolve` đã hỗ trợ) |
| 13 | BOSS | «Nhân viên hôm nay» chỉ có Đã chấm / Chưa chấm. Không biết ai trễ, ai nghỉ phép, ai không có ca hôm nay. «Chưa chấm» gồm cả người không có lịch | `BossController.cs:254-297` chỉ trả `firstPunch/lastPunch` | Mở rộng API: trả thêm ca hôm nay, phút trễ, nghỉ phép đã duyệt. «Chưa chấm» chỉ tính người có ca đã tới giờ | P3 · API + client |
| 14 | Cả hai màn | Mở chậm trên 4G khi nhiều NV / kỳ dài. App tải **toàn bộ log thô** (trang 1.000, 6 trang song song) cùng khoảng 15 API khác (ca, lịch, phép, lễ, hồ sơ lương, đi đường…) rồi tự tính. Có lúc thiếu log cuối kỳ (đã có cảnh báo vàng) | `attendance_summary_screen.dart:165-311`, cảnh báo :438-469 | Ngắn hạn: mở mặc định «Hôm nay / Tuần này» trên mobile. Dài hạn: API tổng hợp phía máy chủ dùng chung `payroll_engine` (server đã có), trả sẵn từng NV × ngày | P3 · API |
| 15 | Cả hai màn | Nút «Chọn cột» trên mobile không có tác dụng (cột chỉ dùng cho bảng desktop). Tên trong xếp hạng chỉ có top 5, không bấm được | `attendance_summary_screen.dart:489-505`. `SboxRankList.maxItems=5` (`sbox_charts.dart:571`) | Ẩn «Chọn cột» khi < 600. Xếp hạng: bấm tên mở chi tiết NV, có «Xem tất cả» | P3 · client |
| 16 | BOSS › Quản lý | Hai màn «Tổng hợp chấm công» và «Tổng hợp theo ca» trùng nhau nhiều, chủ không biết dùng màn nào | `boss_manage_screen.dart:74-77` | Trong BOSS gộp thành 1 màn «Chấm công» với 2 chế độ (Theo ngày / Theo nhân viên). «Theo ca» thành bộ lọc | P3 · client |

## 3. Đề xuất thiết kế lại cho điện thoại

**Đầu trang (cố định):** gồm thanh kỳ (Hôm nay · Tuần · Tháng · Kỳ lương · bấm để chọn ngày) và chi nhánh. Bên dưới là nút chuyển **[Theo ngày] [Theo nhân viên]**. Kỳ «Hôm nay / Hôm qua» thì mặc định «Theo ngày», kỳ dài thì mặc định «Theo nhân viên».

**Theo ngày:**
- Có dải chọn ngày cuộn ngang. Mỗi ngày có chấm màu nếu ngày đó có vắng / trễ.
- Hàng chip đếm **người**: Có mặt 8 · Đi trễ 2 · Vắng 1 · Nghỉ phép 1 · Thiếu chấm 1 · Chưa tới ca 3. Bấm chip thì danh sách bên dưới lọc ngay theo nhóm đó, không mở hộp thoại.
- Mỗi dòng: tên, giờ vào–ra, nhãn trạng thái (trễ 12 phút / quên chấm ra…). Bấm dòng mở chi tiết ngày, nơi có sẵn nút sửa chấm công.

**Theo nhân viên:**
- Ô tìm kiếm, nút sắp xếp (Vắng nhiều / Trễ nhiều / Ít công / Nhiều giờ / Tên), chip «Có vấn đề».
- Chia 2 nhóm có tiêu đề riêng:
  - **«Tính theo công»** (lương tháng / ngày / ca): «22/26 công · 3 trễ · 1 vắng».
  - **«Tính theo giờ»** (lương theo giờ): «48,5 giờ · 12 buổi». Không có công, không có x/26, chỉ tính vắng ngày có lịch.
- Bấm dòng mở chi tiết NV: lịch tháng màu, danh sách ngày, tổng.

**KPI đầu trang (thu gọn, bấm được):**
- Tách «Tổng công (N NV tính công)» và «Tổng giờ (M NV theo giờ)».
- «Nhân viên» = số người có đi làm trong kỳ. Bấm vào mở danh sách.

**Ưu tiên làm:**
1. **P1, chỉ client:** mục 1-9. Chip / KPI bấm ra danh sách (cả BOSS staff-today). NV lương giờ hiện giờ, không tính công. Vắng theo lịch. Thẻ NV gọn, có sắp xếp, tìm kiếm, lọc.
2. **P2, client:** mục 10-12. Chế độ «Theo ngày», chọn ngày tùy ý, gọn đầu trang.
3. **P3, cần API:** mục 13-16. BOSS staff-today thêm trễ / phép / ca. API tổng hợp phía máy chủ cho tải nhanh. Gộp 2 màn trong BOSS.

Rủi ro khi sửa: `attendance_summary_tab.dart` và `attendance_by_shift_tab.dart` rất lớn và gánh cả desktop, Excel, PNG. Nên dựng widget mobile mới tách riêng (vd `screens/attendance/mobile/attendance_mobile_view.dart`) nhận `_DailySummary` / `_DailyShiftRecord` đã tính, không sửa bảng desktop. Đổi «công → giờ» cho NV lương giờ phải áp dụng đồng bộ cho cả Excel / PNG và tab theo ca.

## 4. Đã làm P1 (09/11/2026, chưa commit, chưa deploy)

Các file đã sửa:
- `screens/attendance/attendance_summary_tab.dart`
- `screens/attendance/attendance_by_shift_tab.dart`
- `features/boss/boss_staff_today_screen.dart`
- `features/boss/boss_dashboard_screen.dart`

File mới:
- `widgets/attendance/attendance_people_sheet.dart`: sheet danh sách người dùng chung.
- `widgets/attendance/attendance_employee_list.dart`: dòng NV gọn, thanh tìm / sắp / lọc.
- `test/attendance_summary_mobile_test.dart`

**Lương theo giờ** (`Benefit.RateType = Hourly`):
- Áp dụng ở cả hai tab.
- `workCount` được đặt về 0 ngay lúc tính, nên mọi tổng, Excel và PNG đều bỏ công của NV giờ. Ô công ghi «Theo giờ».
- Chỉ tính vắng ngày có lịch mà không chấm (dùng lại luật «tính phép theo lịch»).
- `_parseRateType`: giá trị null mặc định là lương tháng (trước đây là lương giờ).

**Tổng hợp chấm công:**
- 6 ô KPI bấm được: tổng giờ, tổng công, NV đi làm, TB giờ, có ngày vắng, thiếu chấm.
- Điện thoại ẩn «Bản ghi / Số ca».

**Theo ca:**
- 6 ô đếm **người** (kèm số lượt), bấm được.

**Mobile, cả hai tab:**
- Mỗi NV một dòng gọn khoảng 62dp.
- Có tìm kiếm, sắp xếp (nhiều vấn đề / vắng / trễ / ít công / nhiều giờ / tên) và chip lọc.
- Chia 2 nhóm «Tính theo công» / «Lương theo giờ».
- Màn chi tiết NV có đầu trang tổng hợp và lịch màu.

**BOSS:**
- Thẻ Đã chấm / Chưa chấm bấm để lọc nhóm.
- Thẻ dashboard báo khi thiếu quyền Chấm công (API `staff-today` yêu cầu quyền này).

**Kiểm tra:**
- Test mới và test chấm công cũ: 14/14 qua.
- Analyze không có lỗi mới.
- Ảnh sau khi sửa: `shots-sau-khi-sua/`.

**Còn lại:**
- Chưa chạy pipeline i18n (`tool/i18n_*`) cho chuỗi mới; đang có thay đổi i18n chưa commit của phiên khác.
- Nhánh `feat/boss-parity` chưa có sửa BOSS.
- Chưa thử trên máy thật.
- P2, P3 chưa làm.

## 5. Đã làm P2 + P3 (09/11/2026, chưa commit, chưa deploy)

**P2**
- Chọn khoảng ngày tùy ý: bấm ô ngày hoặc chọn «Tùy chọn…».
- Nhớ kỳ đã chọn theo máy (cả hai màn).
- Chế độ «Theo ngày» trên điện thoại (cả hai màn), widget dùng chung `widgets/attendance/attendance_day_view.dart`:
  - Dải ngày có chấm đỏ báo ngày có vấn đề.
  - Chip đếm người: Có mặt / Đang làm / Đi trễ / Về sớm / Thiếu chấm / Vắng / Chưa chấm / Nghỉ phép / Nghỉ.
  - Kỳ chỉ 1 ngày thì mặc định mở chế độ này.
- Đầu trang mobile: bộ lọc ở trên, sau là ô số, biểu đồ thu vào nút «Xem biểu đồ».
- Không có «Kỳ lương này»: hệ thống không có thiết lập kỳ lương (lương theo tháng dương lịch).

**P3**
- Ẩn «Chọn cột» trên điện thoại.
- Bảng «Nhiều giờ công nhất»: bấm tên mở chi tiết NV, có «Xem tất cả».
- `SboxRankList` thêm `onTap` tùy chọn.
- BOSS: gộp 2 ô thành «Tổng hợp chấm công», có nút chuyển Theo ngày công / Theo ca.
  - Có quyền một trong hai màn là mở được.
  - Mã `AttendanceByShift` vẫn mở được qua `_linkedTools`.
- API `GET /api/boss/staff-today` trả thêm: `hasSchedules`, `now`, `hasShift`, `dayOff`, `shiftName`, `shiftStart`, `shiftEnd`, `lateMinutes` (trễ quá LateGraceMinutes so với giờ vào ca sớm nhất), `onLeave`, `leaveHalf`, `leaveType`. Thông tin ca lấy từ WorkSchedule; nghỉ phép là đơn Approved.
- Client BOSS: nhóm Đã tới ca chưa chấm / Chưa tới ca / Nghỉ phép / Không có ca / Đi trễ; thẻ và chip đều bấm được.

**Chưa làm:** API tổng hợp phía máy chủ để tải nhanh (P3-14 bản dài hạn).

**Kiểm tra**
- Widget test 16/16 qua (có BOSS staff-today và chế độ Theo ngày).
- `dotnet build` API thành công.
- Gọi thật API mới trên QA (bản build riêng, cổng 7079, DB `sbox_qa`, cửa hàng QA Gym) với 3 lịch thử: ca sáng → `hasShift`, ca tối → giờ ca đúng, ngày nghỉ → `dayOff`. Lịch thử đã xóa, API 7079 đã tắt.
- Chưa kiểm `lateMinutes` / `onLeave` trên dữ liệu thật, vì NV QA không có máy chấm.
- i18n: thêm 9 chuỗi mới.

Ảnh: `shots-p2-p3/`.

## 6. Thử trên máy thật V2s (09/11/2026)

- **Bản thử:** APK BOSS QA (`boss.sboxpos.com.qa`) build trong worktree `E:\gtmp\wt-attsum` ở HEAD, đã chép các file đã sửa vào.
  - Script: `E:\gtmp\attsum\build-boss-qa.ps1`.
  - API mới chạy ở 7079, V2s nối qua `adb reverse tcp:7070 tcp:7079`.
- **Dữ liệu thử:** trên cửa hàng QA Retail a1f71c (DB `sbox_qa`).
  - Seed: `E:\gtmp\attsum\seed.sql`, xóa bằng `cleanup.sql`.
  - Lịch ca hôm nay tạo qua API, id lưu ở `sched_ids.json`.
- **Bẫy:** app QA trên V2s từng lưu máy chủ sboxpos.com (đăng nhập gần đây là demopos). Đã `pm clear` gói QA trước khi đăng nhập.
  - Bàn phím tiếng Việt (Telex) làm mất ký tự khi `input text` cả chuỗi. Gõ từng ký tự thì được.
- **Kết quả:** chạy đúng 6 ô số bấm được, sheet người, chi tiết NV, nhóm lương giờ, chế độ Theo ngày (chọn ngày, chip), «Theo ca» (đếm người), «Nhân viên hôm nay» («Trễ 26 phút», Tới ca chưa chấm, Không có ca).
- **Đã sửa sau khi thử:**
  - Nút nổi «Thao tác» che thẻ tổng: chừa đáy 96dp.
  - Nhãn «Lương giờ» làm cắt tên: chuyển xuống dòng phụ.
  - Hai nút chuyển cùng chữ «Theo ngày»: nút trên BOSS đổi thành «Công & giờ».
  - Nhãn thẻ bị cắt: đổi thành «Tới ca, chưa chấm».

## 7. Tách lại BOSS + thử SBOX HRM trên V2s (09/11/2026)

- **BOSS:** theo yêu cầu người dùng, bỏ ô gộp. `boss_manage_screen.dart` trả về đúng HEAD: hai ô riêng «Tổng hợp chấm công» và «Tổng hợp theo ca».
- **Bản HRM QA:**
  - Gói `sbox.sana.vn.qa`, cài song song app thật, tắt google-services.
  - Script `E:\gtmp\attsum\build-hrm-qa.ps1`, đăng nhập bằng `E:\gtmp\attsum\login-qa.ps1` (gõ từng ký tự, có chốt gói).
- **Đã thử trên V2s, chạy đúng:**
  - «Tổng hợp chấm công»: ô số và sheet người, chọn khoảng ngày tùy ý (3–6/11 tải lại đúng), «Theo ngày», nhóm lương giờ.
  - «Tổng hợp chấm công theo ca»: ô đếm người, sheet «Nhân viên có ngày vắng».
- Mở mục «Chấm công» ở tab dưới thì app hỏi quyền vị trí; đã từ chối.
