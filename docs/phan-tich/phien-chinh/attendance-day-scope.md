# Tổng hợp chấm công / theo ca — «Đủ ngày trong kỳ» / «Chỉ ngày có chấm» (commit 06689774)

- Tiện ích chung: flutter_client/lib/utils/attendance_day_scope.dart (AttendanceDayScope, AttendanceFillDayKind, attendanceFillDays).
- Khóa nhớ lựa chọn: attendance_by_shift_day_scope_v1, attendance_summary_day_scope_v1 (SharedPreferences).
- Excel / PNG lấy đúng danh sách dòng trên màn hình; dòng «Bộ lọc» có chi nhánh / phòng ban (ReportBranchFilter.filterLabel).
- Server không đổi: Excel dựng ở app, API chỉ trả dữ liệu thô.
- Đã kiểm trên web QA (build E:\gtmp\qa_web_dayscope, cổng 3017, TK Retail, Tháng trước 01–31/10): theo ca 217 ↔ 7 dòng,
  tổng hợp 217 ↔ 7 dòng, file Excel cùng số dòng.

## Đã deploy (02/11, sboxhrm.com, build 1793623410)
- Commit 06689774, 7c769d61, ce8927c2, 2bb84721 đã push và deploy web (chỉ sboxhrm; sboxpos.com vẫn là bản 17/10).
- Test production (TK demo, tháng 10): theo ca 324 ↔ 50 dòng, Excel hằng ngày / theo NV khớp; tổng hợp 324 dòng khớp.
- Sửa thêm sau test: Excel hằng ngày ghi «Vắng» cho NV chưa gán ca / chấm 1 lần mỗi ngày (trước để trống).

## Lưu ý cho phiên khác
- E:\gtmp\pw\flow.js dùng CHUNG file lệnh fcmd.json / fres.json: hai phiên chạy flow.js cùng lúc sẽ nhận lệnh của nhau.
  Phiên này dùng bản riêng ds_flow.js + ds_cmd.js (ds_cmd.json / ds_res.json). Vài lệnh xem / reload của phiên này
  đã lọt sang trình duyệt flow.js của phiên khác lúc ~18:44 ngày 02/11.
- Người dùng chọn: NV chưa đặt ngày nghỉ tuần → Chủ nhật không chấm là «Vắng». Commit 7c769d61 bỏ _dailyIsWeeklyOff
  (mặc định CN nghỉ); màu dòng + Excel hằng ngày giờ dùng _isWeeklyOffDay như cột trạng thái.

## Ca gán chồng giờ (02/11 tối, commit 3a51f191 — đã deploy web build 1793633283 + API)
- Lỗi: alignStrayPunchToShifts (944b7a01) ghép theo mốc mọi ca gán; NV có nhiều ca chồng giờ (P9/S9/P13/P17/C2…)
  vào trễ 17:56 bị coi là ra P13 → «Thiếu vào P13, C2», 0 công. Sửa: ca chồng giờ → bỏ ghép theo mốc.
- API deploy một phần: tarball server + chỉ thay payroll_engine/lib/utils/shift_records_calculator.dart
  (server thiếu nhiều commit POS/AI của phiên khác — không deploy chúng). Bản trước: /root/api_src.before-shift-overlap.tar.gz.
