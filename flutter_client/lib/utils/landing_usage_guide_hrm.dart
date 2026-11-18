import 'package:flutter/material.dart';

import '../theme/sbox_tokens.dart';
import 'device_setup_guide.dart';
import 'landing_usage_guide.dart';

/// Bài hướng dẫn sử dụng phần SBOX HRM. Tách khỏi `landing_usage_guide.dart` để bản SBOX Bán Hàng
/// không biên dịch hàng trăm câu nhắc chấm công / nghỉ phép / tính lương vào gói (Apple 2.5.19).

final List<LandingUsageGuideStep> hrmBasicSteps = <LandingUsageGuideStep>[
  const LandingUsageGuideStep(
    id: 'getting_started',
    icon: Icons.flag_rounded,
    title: 'Bắt đầu nhanh (checklist 7 ngày)',
    desc:
        'Làm theo thứ tự dưới đây trong tuần đầu để cửa hàng chạy được chấm công và tính lương. Mỗi mục tương ứng một bước hướng dẫn chi tiết trong tab Triển khai.',
    bullets: [
      'Ngày 1: Đăng ký cửa hàng → đăng nhập bằng mã cửa hàng + tài khoản admin',
      'Ngày 1–2: Tạo phòng ban / chức vụ → thêm nhân viên (hoặc import Excel)',
      'Ngày 2: Thiết lập ca làm việc + kiểu chấm công trong Thiết lập lương',
      'Ngày 3: Phân lịch làm việc tuần/tháng cho nhân viên',
      'Ngày 3–4: Kết nối máy ZKTeco (máy đời cũ chỉ có LAN: dùng Gateway WiFi) hoặc bật chấm công Mobile → tải NV xuống máy → đăng ký vân tay/face',
      'Ngày 5: Tạo tài khoản app cho quản lý/NV cần đăng nhập; phân quyền theo vai trò',
      'Ngày 5–6: Cấu hình phạt đi trễ/về sớm (nếu dùng) → kiểm tra vài ngày chấm thử trên Chấm công thô',
      'Cuối tháng: Duyệt sửa công, phép, phiếu thưởng–phạt–ứng → xem Tổng hợp theo ca → «Chốt lương» ở Tổng hợp lương',
      'Tùy chọn: bật Zalo bot (Thiết lập SBOX › Zalo bot) để nhân viên nhận phiếu lương, phạt, kết quả duyệt đơn qua Zalo',
      'Nếu gói có POS: sang tab POS — ngành hàng → hàng hóa → máy in → bán thử → xem Báo cáo POS',
      'Hotline hỗ trợ: 0973 024 042 (Zalo hỗ trợ từ xa)',
    ],
    tip:
        'Tuần đầu ưu tiên nhân sự → ca → chấm công → lương. POS và KPI làm sau khi chấm công đã ổn.',
    accent: SboxColors.brand600,
  ),
  const LandingUsageGuideStep(
    id: 'register',
    icon: Icons.app_registration_rounded,
    title: 'Đăng ký phần mềm',
    desc:
        'Tạo cửa hàng trên sboxhrm.com để nhận mã cửa hàng và tài khoản quản trị. Làm lần lượt các bước dưới đây — mất khoảng 5–10 phút.',
    bullets: [
      'Bước 1 — Mở trình duyệt, vào sboxhrm.com → chọn Đăng ký / Đăng ký doanh nghiệp',
      'Bước 2 — Điền tên cửa hàng, mã đăng nhập cửa hàng, email, SĐT, mật khẩu admin',
      'Bước 3 — Đặt mã cửa hàng: chữ thường a–z và số 0–9, liền nhau, không dấu, tối đa 20 ký tự (vd: comganam)',
      'Bước 4 — Chọn gói dịch vụ phù hợp → hoàn tất đăng ký để kích hoạt',
      'Bước 5 — Lưu mã cửa hàng (ghi ra giấy hoặc Zalo) — nhân viên cần mã này mỗi lần đăng nhập',
      'Bước 6 — Đăng nhập lần đầu: Mã cửa hàng + Email/Tên đăng nhập + Mật khẩu',
      'Bước 7 — Nếu quên mật khẩu: dùng Quên mật khẩu trên màn đăng nhập (cần email thật đã đăng ký)',
    ],
    tip:
        'Dùng email và SĐT thật để nhận hỗ trợ kích hoạt và khôi phục tài khoản nhanh. Hotline: 0973 024 042.',
    accent: SboxColors.brand600,
    shots: [
      GuideShot('register-1', afterBullet: 2, caption: '① Nhập tên doanh nghiệp / cửa hàng. ② Mã đăng nhập cửa hàng tự tạo theo tên (sửa được); dòng xanh báo mã còn trống.'),
      GuideShot('register-2', afterBullet: 2, caption: '① Email đăng nhập (dòng xanh báo email dùng được). ② Số điện thoại liên hệ.'),
      GuideShot('register-3', afterBullet: 4, caption: '① Chọn gói dịch vụ / gói dùng thử. ② Đặt mật khẩu và nhập lại. ③ Bấm «Đăng ký doanh nghiệp» để hoàn tất.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'org_structure',
    icon: Icons.account_tree_rounded,
    title: 'Phòng ban, chức vụ & chi nhánh',
    desc:
        'Tổ chức cơ cấu trước khi thêm nhân viên giúp phân ca, phân quyền và báo cáo theo bộ phận chính xác.',
    bullets: [
      'Hồ sơ nhân sự › Phòng ban: tạo các bộ phận (Kế toán, Bếp, Thu ngân…)',
      'Chức vụ: thêm ngay trong form phòng ban (gõ tên chức vụ rồi Enter)',
      'Nếu có nhiều điểm bán: Thiết lập SBOX › Cửa hàng › Chi nhánh (khi gói hỗ trợ)',
      'Gán phòng ban & chức vụ ngay khi thêm nhân viên',
      'Báo cáo và lọc danh sách NV theo phòng ban sau này sẽ dựa trên gán này',
    ],
    tip:
        'Tạo phòng ban trước, rồi mới import Excel nhân viên — tránh phải sửa hàng loạt sau.',
    accent: Color(0xFF455A64),
    shots: [
      GuideShot('org-structure-1', afterBullet: 1, caption: '① Bấm «Thêm phòng ban». ② Chọn một phòng ban để xem người quản lý, chức vụ và nhân viên trong phòng.'),
      GuideShot('org-structure-2', afterBullet: 2, caption: '① Nhập tên phòng ban, mã tự gợi ý theo tên. ② Thêm các chức vụ của phòng (gõ tên rồi Enter). ③ Bấm «Lưu phòng ban».'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'branches',
    icon: Icons.store_mall_directory_rounded,
    title: 'Chi nhánh / nhiều điểm bán',
    desc:
        'Cửa hàng có nhiều điểm bán: khai báo chi nhánh, chọn trụ sở chính và chi nhánh cha, gán quản lý; nhân viên, máy chấm công, kho và báo cáo lọc theo chi nhánh.',
    bullets: [
      'Bước 1 — Thiết lập SBOX › Chi nhánh → «Thêm mới». Tab Danh sách / Sơ đồ / Thống kê hiện khi có từ 2 chi nhánh',
      'Bước 2 — Nhập «Mã chi nhánh *», «Tên chi nhánh *», số điện thoại, địa chỉ (Tỉnh/Thành phố, Quận/Huyện, Phường/Xã)',
      'Bước 3 — Mục «Cấu hình»: chọn «Chi nhánh cha» (nếu có cấp quản lý), «Quản lý chi nhánh», bật «Trụ sở chính» cho cơ sở chính; giờ mở / đóng cửa, mã số thuế → «Tạo mới»',
      'Bước 4 — Tab «Sơ đồ»: cây chi nhánh theo cấp, số nhân viên mỗi nơi; «Mở tất cả» / «Thu gọn»',
      'Bước 5 — Gán chi nhánh cho nhân viên trong hồ sơ nhân sự, cho máy chấm công và kho; báo cáo, chấm công, bán hàng lọc theo chi nhánh đang chọn ở thanh trên cùng',
      'Bước 6 — Số chi nhánh tối đa theo gói dịch vụ — hết hạn mức app báo khi thêm mới',
    ],
    tip:
        'Tạo chi nhánh trước khi thêm nhân viên và máy chấm công của điểm bán mới để dữ liệu vào đúng nơi ngay từ đầu.',
    accent: SboxColors.brand600,
    keywords: ['chi nhánh', 'nhiều điểm bán', 'trụ sở chính', 'chi nhánh cha', 'quản lý chi nhánh', 'sơ đồ chi nhánh'],
    shots: [
      GuideShot('branches-1', afterBullet: 1, caption: '① Bấm «Thêm mới». ② Tab Danh sách / Sơ đồ / Thống kê. ③ Danh sách chi nhánh: mã, quản lý, số nhân viên, địa chỉ, trạng thái.'),
      GuideShot('branches-2', afterBullet: 3, caption: '① Mã và tên chi nhánh. ② Chi nhánh cha và quản lý chi nhánh. ③ Bấm «Tạo mới» để lưu.'),
      GuideShot('branches-3', afterBullet: 4, caption: '① Trụ sở chính ở gốc cây. ② Các chi nhánh trực thuộc kèm số nhân viên. ③ Mở tất cả / thu gọn cây.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'employees',
    icon: Icons.group_add_rounded,
    title: 'Thêm nhân viên',
    desc:
        'Tạo hồ sơ nhân sự làm nền cho chấm công, lương và tài khoản app. Mã nhân viên phải thống nhất giữa hồ sơ và máy chấm công.',
    bullets: [
      'Bước 1 — Vào menu Hồ sơ nhân sự → Thêm nhân viên (hoặc Import Excel nếu thêm hàng loạt)',
      'Bước 2 — Nhập bắt buộc: họ tên, mã nhân viên (PIN — nên dùng số, tối đa 8 chữ số vì máy chấm công chỉ nhận số), phòng ban, chức vụ',
      'Bước 3 — Bổ sung nên có: SĐT, ngày vào làm, trạng thái Đang làm việc',
      'Bước 4 — Nếu Import Excel: tải mẫu trong màn hình → điền đúng cột → tải lên → kiểm tra kết quả',
      'Bước 5 — Kiểm tra không trùng mã nhân viên trước khi đồng bộ xuống máy',
      'Bước 6 — Gán Thiết lập lương và xếp ca ở Chấm công › Ca làm việc (các bước tiếp theo)',
      'Bước 7 — NV nghỉ việc: cập nhật trạng thái nghỉ — không xóa nếu đã có dữ liệu chấm công',
    ],
    tip:
        'Mã nhân viên trên máy ZKTeco phải trùng mã trong hồ sơ thì log chấm công mới khớp tên.',
    accent: Color(0xFF00897B),
    shots: [
      GuideShot('employees-1', afterBullet: 1, caption: '① Bấm «Thêm nhân viên»; thêm hàng loạt thì dùng nút tải lên Excel bên cạnh.'),
      GuideShot('employees-2', afterBullet: 2, caption: '① Mã nhân viên (PIN), phải trùng mã trên máy chấm công. ② Họ tên nhân viên.'),
      GuideShot('employees-3', afterBullet: 3, caption: '① Chọn phòng ban rồi đến chức vụ. ② Ngày vào làm. ③ Trạng thái làm việc.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'shifts',
    icon: Icons.schedule_rounded,
    title: 'Cấu hình ca làm việc',
    desc:
        'Định nghĩa khung giờ làm (ca sáng, ca đêm, ca OT…). Ca quyết định tính đi trễ, về sớm, công và tăng ca.',
    bullets: [
      'Bước 1 — Vào Thiết lập SBOX › Nhân sự & chấm công › Ca làm việc (hoặc Chấm công › Ca làm việc › tab Thiết lập › Ca mẫu) → «Thêm ca»',
      'Bước 2 — Chọn «Mẫu nhanh» hoặc nhập «Tên ca», «Giờ vào», «Giờ ra» (giờ ra nhỏ hơn giờ vào = ca qua đêm), «Loại ca» (Hành chính / Tăng ca / Qua đêm), «Nghỉ giữa ca»',
      'Bước 3 — «Quy tắc chấm công»: Nhận chấm sớm, Miễn trễ, Miễn về sớm, Giới hạn về sớm, Tăng ca trước / sau ca («Nhận chấm sớm» phải lớn hơn «Tăng ca trước ca»)',
      'Bước 4 — Bấm «Lưu ca». Trả lương theo ca: mở lại ca vừa lưu → «Lương ca» → «Thêm mức lương» (cố định / nhân hệ số / theo giờ)',
      'Bước 5 — Gán ca cho nhân viên: xếp lịch ở Chấm công › Ca làm việc › Bảng xếp ca, hoặc giới hạn ca trong Thiết lập lương (ô Ca làm việc)',
      'Bước 6 — Ca đã có dữ liệu không xóa được: dùng «Ngừng dùng» (lịch cũ giữ nguyên). Muốn đổi giờ ca đang dùng: «Nhân bản» rồi sửa bản mới',
      'Bước 7 — Không đổi tên ca đang gắn trong Thiết lập lương: hồ sơ lương lưu ca theo tên, đổi tên sẽ hiện «(ca đã xóa / đổi tên)»',
    ],
    tip:
        'Miễn trễ 5–10 phút giúp tránh phạt oan; số phút phạt đi trễ tính SAU khi trừ phút miễn trễ của ca. Tăng ca tính theo giờ chấm vượt ngưỡng «Tăng ca trước / sau ca».',
    accent: Color(0xFF6A1B9A),
    shots: [
      GuideShot('shifts-1',
          afterBullet: 1,
          caption: '① Bấm «Thêm ca» để tạo ca mới. ② Nút ba chấm trên từng ca: sửa, nhân bản, ngừng dùng.'),
      GuideShot('shifts-2',
          afterBullet: 2,
          caption:
              '① Nhập tên ca. ② Chọn giờ vào – giờ ra (giờ ra nhỏ hơn giờ vào là ca qua đêm). ③ Hoặc bấm một mẫu ca có sẵn.'),
      GuideShot('shifts-3',
          afterBullet: 3,
          caption:
              '① Miễn trễ và giới hạn đi trễ. ② Miễn về sớm và giới hạn về sớm. ③ Số phút ra sớm / về muộn mới tính tăng ca.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'salary',
    icon: Icons.payments_rounded,
    title: 'Thiết lập lương & kiểu chấm công',
    desc:
        'Gán mức lương, phụ cấp và cách tính công cho từng nhân viên. Kiểu chấm công quyết định cần chấm vào/ra hay chỉ một lần/ca.',
    bullets: [
      'Mở Hồ sơ nhân sự › nút ⋮ trên nhân viên › «Thiết lập lương»; thẻ «Chưa thiết lập» lọc người chưa có lương',
      '«Lương chính» › Loại lương: Tháng (lương cơ bản + lương hoàn thành) / Ngày / Ca / Giờ',
      '«Tăng ca»: Theo luật / Cố định / Không tính. «Bảo hiểm xã hội»: không đóng, theo lương cơ bản, lương tối thiểu vùng hoặc mức khác',
      '«Ngày công và chấm công» › «Cách chấm công»: Chấm vào và ra · Chỉ chấm vào · Chỉ chấm ra · Chấm bất kỳ trong ca · Chấm 2 lần trong ngày · Ca nguyên ngày · Không chấm công; ô Ca làm việc để trống = theo lịch phân ca',
      'Cùng khối: ngày nghỉ hưởng lương, số giờ một công, công chuẩn tháng (theo tháng hoặc cố định, vd 26 công)',
      'Bấm «Lưu thiết lập». Khi tăng lương chọn «Đổi lương từ ngày» để giữ lịch sử; nhân rộng: ⋮ › «Sao chép cho nhân viên khác»',
      'Hệ số tăng ca, trả lương ngày lễ, phụ cấp làm đêm: nút «Chính sách lương» trên đầu màn Thiết lập lương',
      'Phụ cấp, Mức phạt, Bảo hiểm, Thuế TNCN (người phụ thuộc), Lương sản phẩm, Phép năm: Thiết lập SBOX › Lương & chính sách. Phụ cấp gán ở mục Phụ cấp, không gán trong trang lương',
    ],
    tip:
        'Cửa hàng chỉ chấm 1 lần/ngày trên máy: chọn «Chỉ chấm vào». Nhân viên chưa có Thiết lập lương thì không có bảng lương và quỹ phép năm.',
    accent: SboxColors.brand600,
    shots: [
      GuideShot('salary-1', afterBullet: 1, caption: '① Chọn nhân viên cần thiết lập; người chưa có lương hiện nhãn «Chưa thiết lập».'),
      GuideShot('salary-2', afterBullet: 2, caption: '① Loại lương: tháng, ngày, ca hoặc giờ. ② Lương cơ bản và lương hoàn thành.'),
      GuideShot('salary-3', afterBullet: 4, caption: '① Chọn cách chấm công (chấm vào và ra, chỉ chấm vào…). ② Các ca được áp dụng; để trống là theo lịch phân ca.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'allowance',
    icon: Icons.card_giftcard_rounded,
    title: 'Phụ cấp',
    desc:
        'Khoản cộng thêm vào lương: cố định hàng tháng, theo ngày công, theo giờ, theo lần hoặc theo ca đủ công. Phụ cấp tự cộng vào bảng lương của nhân viên được áp dụng.',
    bullets: [
      'Bước 1 — Thiết lập SBOX › Phụ cấp → «Thêm phụ cấp». Danh sách lọc theo kiểu (Cố định hàng tháng, Theo ngày công, Theo ca đủ công…); bật / tắt nhanh bằng công tắc trên từng phụ cấp',
      'Bước 2 — Chọn «Mẫu nhanh» (Ăn trưa, Xăng xe, Điện thoại, Chuyên cần, Ca đêm) hoặc nhập «Tên phụ cấp *», chọn «Cách tính» và «Số tiền»',
      'Bước 3 — Phụ cấp theo ca: chọn «Ca được hưởng»; theo ngày / theo ca có thể đặt «Điều kiện nhận» (% thời lượng ca hoặc số giờ tối thiểu)',
      'Bước 4 — Bật / tắt «Tính vào thu nhập chịu thuế TNCN» (tắt với khoản được miễn thuế) và «Tính vào lương đóng bảo hiểm»; đặt thời hạn Từ / Đến nếu chỉ áp dụng một thời gian',
      'Bước 5 — «Áp dụng cho tất cả nhân viên» hoặc tắt để chọn riêng từng người → «Lưu»',
      'Bước 6 — Cuối kỳ: phụ cấp hiện ở dòng «Phụ cấp» trên Tổng hợp lương và phiếu lương nhân viên. Muốn ngừng mà giữ lịch sử thì tắt phụ cấp thay vì xóa',
    ],
    tip:
        'Bảng lương đã chốt giữ nguyên khi sửa / xóa phụ cấp — đổi mức phụ cấp chỉ áp dụng cho kỳ chưa chốt.',
    accent: SboxColors.brand600,
    keywords: ['phụ cấp', 'ăn trưa', 'xăng xe', 'chuyên cần', 'ca đêm', 'phụ cấp theo ca', 'phụ cấp ngày công', 'miễn thuế'],
    shots: [
      GuideShot('allowance-1', afterBullet: 1, caption: '① Bấm «Thêm phụ cấp». ② Lọc theo kiểu phụ cấp. ③ Mỗi phụ cấp: số tiền, cách tính, áp dụng cho ai, ca được hưởng, chịu thuế / đóng BH, công tắc bật / tắt.'),
      GuideShot('allowance-2', afterBullet: 2, caption: '① Chọn mẫu nhanh. ② Tên, cách tính và số tiền. ③ Phụ cấp theo ca: chọn ca được hưởng.'),
      GuideShot('allowance-3', afterBullet: 4, caption: '① Điều kiện nhận: không điều kiện, % thời lượng ca hoặc số giờ tối thiểu. ② Tính vào thu nhập chịu thuế TNCN / lương đóng bảo hiểm. ③ Áp dụng cho tất cả nhân viên hoặc chọn riêng.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'work_schedule_basic',
    icon: Icons.calendar_view_week_rounded,
    title: 'Phân lịch làm việc lần đầu',
    desc:
        'Gán ca theo từng ngày cho nhân viên để hệ thống biết ngày nào phải đi làm, nghỉ và tính công đúng.',
    bullets: [
      'Menu: Chấm công › Ca làm việc › tab «Bảng xếp ca» (máy tính: mở từ Trang chủ hoặc ô tìm chức năng)',
      'Chọn tuần, xem «Cả tuần» hoặc «Từng ngày», lọc «Bộ phận»; chạm ô ngày của nhân viên chưa có lịch',
      'Chọn ca mẫu hoặc «Ngày nghỉ» (lưu ngay); «Thao tác nhanh» › «Sao chép lịch tuần trước» chỉ điền ô còn trống',
      'Ca xoay (sáng – chiều – nghỉ luân phiên): chưa có mẫu tự xoay — xếp tay 1–2 tuần rồi dùng «Sao chép tuần» trong «Lịch làm việc (đầy đủ)» (tối đa 12 tuần)',
      'Xếp hàng loạt, sao chép tháng, xuất Excel: tab Thiết lập › «Lịch làm việc (đầy đủ)» — ở màn này lịch vào «Danh sách chờ gửi», phải bấm «Gửi đăng ký» rồi duyệt',
      'Nên phân ca trước đầu kỳ lương — tránh sửa lịch khi đã có phiếu phạt tự động',
    ],
    tip:
        'Lịch trống + máy có log vẫn có thể khớp ca từ Thiết lập lương, nhưng phân lịch rõ ràng giúp báo cáo và phép chính xác hơn.',
    accent: Color(0xFF7B1FA2),
    shots: [
      GuideShot('work-schedule-1', afterBullet: 2, caption: '① Chọn tuần cần xếp lịch. ② Nhân viên chưa có lịch: chạm vào ô ngày để xếp ca.'),
      GuideShot('work-schedule-2', afterBullet: 3, caption: '① Chọn ca cho ngày đó (Ca sáng, Ca chiều, Hành chính…). ② Hoặc đánh dấu Ngày nghỉ.'),
      GuideShot('work-schedule-3', afterBullet: 3, caption: '① «Thao tác nhanh» → Sao chép lịch tuần trước khi lịch lặp lại hằng tuần.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'device_connect',
    icon: Icons.router_rounded,
    title: 'Kết nối máy chấm công ZKTeco',
    desc:
        'Cấu hình hai phía: máy trỏ về máy chủ ADMS cloud; phần mềm khai báo serial để nhận log real-time. Làm đúng thứ tự để tránh máy Offline.',
    bullets: [
      'Bước 1 — Trên máy ZKTeco: vào ${DeviceSetupGuide.menuPath}',
      'Bước 2 — Nhập Địa chỉ máy chủ: ${DeviceSetupGuide.serverHost} · Port: ${DeviceSetupGuide.serverPort}',
      'Bước 3 — Lưu, khởi động lại máy nếu máy yêu cầu. Máy phải gọi về máy chủ TRƯỚC thì SBOX mới nhận số serial',
      'Bước 4 — Trên SBOX: Thiết lập SBOX › Nhân sự & chấm công › Máy chấm công › «Thêm thiết bị»: nhập Serial Number (hoặc quét mã), bấm «Kiểm tra Serial», đặt tên máy',
      'Bước 5 — Kiểm tra trạng thái Online trên danh sách máy (Online = có tín hiệu trong 2 phút gần nhất)',
      'Bước 6 — Cho NV chấm thử → mở Chấm công thô xác nhận có giờ chấm',
      'Bước 7 — «Kiểm tra Serial» báo «chưa từng kết nối»: làm lại bước 1–3. Báo «đã được sử dụng bởi cửa hàng khác» hoặc vượt số máy của gói: gọi hotline',
    ],
    tip:
        'Máy đời cũ không có menu Máy chủ đám mây: dùng Gateway WiFi (mục kế tiếp). Chưa kết nối được? Gọi hotline 0973 024 042 — hỗ trợ từ xa qua Zalo.',
    accent: const Color(0xFF0277BD),
    shots: [
      GuideShot('device-connect-1', afterBullet: 2, caption: '① Trên máy chấm công: vào menu Máy chủ đám mây, nhập địa chỉ máy chủ và port như hướng dẫn.'),
      GuideShot('device-connect-2', afterBullet: 4, caption: '① Nhập số serial (SN) hoặc quét mã. ② Đặt tên máy. ③ Bấm Thêm.'),
      GuideShot('device-connect-3', afterBullet: 5, caption: '① Máy đang kết nối hiện Online. ② Máy mất kết nối hiện Offline, cần kiểm tra mạng của máy.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'device_users',
    icon: Icons.fingerprint_rounded,
    title: 'Đồng bộ NV & đăng ký vân tay / face',
    desc:
        'Đưa danh sách nhân viên xuống máy rồi đăng ký sinh trắc học. Chỉ khi mã NV khớp, log mới gắn đúng người.',
    bullets: [
      'Menu: Chấm công › Nhân sự chấm công (máy tính: mở từ Trang chủ hoặc ô tìm chức năng)',
      '«Tải hồ sơ NS» (điện thoại: trong nút «…») → chọn máy → tích nhân viên → «Tải N nhân viên»',
      'Đăng ký từ xa: menu của nhân viên › «Quản lý vân tay» (chọn ngón → «Đăng ký», nhân viên đặt ngón lên máy 3 lần) hoặc «Quản lý khuôn mặt» (nhìn vào màn hình máy, cách 0,5–1 m); app chờ tối đa 2 phút',
      'Máy báo «không hỗ trợ đăng ký từ xa» (máy đời cũ, LX35…): đăng ký ngay trên máy rồi bấm «Đồng bộ ngay» / «Tải từ máy»',
      'PIN trên máy chỉ gồm số, tối đa 8 chữ số; tên xuống máy được bỏ dấu. Nhiều máy: «Copy sinh trắc» chép vân tay / khuôn mặt sang máy khác cùng cửa hàng',
      'NV nghỉ việc: «Xóa người dùng» trên máy để tránh chấm nhầm',
    ],
    tip:
        'Kết quả «Đã tải X nhân viên… Y thất bại» kèm PIN đã cấp. Log hiện PIN lạ: mã trên máy và mã trong hồ sơ không khớp.',
    accent: SboxColors.successText,
    shots: [
      GuideShot('device-users-1', afterBullet: 2, caption: '① Nút «Tải hồ sơ NS» (điện thoại: trong nút «…» góc dưới) đẩy nhân viên xuống máy. ② Thẻ «NV chưa có trên máy»: số nhân viên chưa đồng bộ. ③ Cột vân tay / khuôn mặt bằng 0 là chưa đăng ký, chưa chấm công được.'),
      GuideShot('device-users-2', afterBullet: 2, caption: '① Chọn máy chấm công. ② Tích chọn nhân viên cần tải xuống (hoặc «Chọn tất cả»). ③ Bấm «Tải N nhân viên».'),
      GuideShot('device-users-3', afterBullet: 3, caption: '① Số vân tay nhân viên đã đăng ký. ② Chọn ngón tay rồi bấm Đăng ký / Xóa. ③ Ngón màu xanh là đã có vân tay.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'gateway_wifi',
    icon: Icons.wifi_tethering_rounded,
    title: 'Gateway WiFi cho máy chấm công đời cũ',
    desc:
        'Máy ZKTeco cũ chỉ có cổng LAN (TCP 4370), không có menu Máy chủ đám mây: cắm mạch Gateway WiFi (ESP32) trong cùng mạng để đẩy chấm công lên SBOX.',
    bullets: [
      'Chuẩn bị: nguồn USB 5V cho mạch, IP của máy chấm công (menu Comm / Ethernet trên máy), mật khẩu WiFi 2.4GHz (gateway không bắt sóng 5GHz)',
      'Dùng app SBOX trên điện thoại (bản web không cấu hình được): Thiết lập SBOX › Nhân sự & chấm công › Gateway WiFi › «Thêm gateway» → «Bắt đầu bằng Bluetooth»',
      'Chọn đúng SBOX-Gateway-XXXX. Cách cũ: nối WiFi SBOX-Gateway-… (mật khẩu sbox12345) rồi bấm «Tôi đã kết nối, kiểm tra»',
      'Chọn WiFi trong danh sách gateway quét được, nhập mật khẩu, tên gợi nhớ (Cửa trước / Kho…), «IP máy chấm công trong LAN» → «Lưu và kết nối»',
      'Màn Hoàn tất hiện «Gateway đã lên mạng» và số seri máy chấm công',
      'Thêm số seri đó ở Thiết lập SBOX › Máy chấm công như máy thường — chưa thêm thì chấm công chưa vào cửa hàng',
      'Chi tiết gateway: Đẩy danh sách nhân viên, Chỉnh giờ máy chấm công, Đồng bộ lại chấm công, Xóa dữ liệu định kỳ, cập nhật firmware',
    ],
    tip:
        'Lỗi «WiFi timeout»: sai mật khẩu hoặc mạng 5GHz. Mỗi máy chấm công chỉ gắn một mạch. Lần đầu gateway lấy chấm công 30 ngày gần nhất.',
    accent: Color(0xFF0277BD),
    shots: [
      GuideShot('gateway-wifi-1', afterBullet: 2, caption: '① Cần chuẩn bị: nguồn USB, IP máy chấm công, WiFi 2.4GHz. ② Bấm «Bắt đầu bằng Bluetooth».'),
      GuideShot('gateway-wifi-2', afterBullet: 4, caption: '① Chọn WiFi do gateway quét được. ② Mật khẩu WiFi. ③ Tên gợi nhớ và IP máy chấm công trong LAN, rồi bấm «Lưu và kết nối» bên dưới.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'mobile_attendance',
    icon: Icons.phone_android_rounded,
    title: 'Chấm công Mobile & duyệt',
    desc:
        'Cho phép chấm bằng điện thoại (GPS, WiFi cửa hàng, khuôn mặt). Phù hợp khi không có máy ZK hoặc nhân viên ngoài hiện trường.',
    bullets: [
      'Thiết lập SBOX › Nhân sự & chấm công › Chấm công Mobile › tab Cài đặt: bật Khuôn mặt / GPS / Wi-Fi công ty; bật nhiều cách thì chọn «Chỉ cần đạt 1» hoặc «Phải đạt tất cả»',
      'Tab Vị trí: thêm vị trí (địa chỉ, bán kính, MAC router WiFi – BSSID). WiFi mesh nhiều cục phát dễ báo «không khớp» — nên dùng GPS',
      'Nhân viên: Chấm công › Đăng ký chấm công Mobile → chọn vị trí → chụp 5 góc mặt → «Gửi đăng ký»; quản lý duyệt ở tab «Cần duyệt» (hoặc cấp quyền bằng QR)',
      'NV mở app → Chấm công › Chấm công Mobile: QUÉT MẶT / CHẤM VÀO / CHẤM RA',
      'Lượt chấm chờ duyệt: Chấm công › Duyệt chấm công › lọc «Chấm Mobile»; «Duyệt N bản tin cậy» để duyệt nhanh. Chỉ bản đã duyệt mới vào Chấm công thô',
      'Có thể dùng song song máy ZK + mobile cho cùng cửa hàng',
    ],
    tip:
        'Báo «Thiết bị chưa được duyệt hoặc đã bị thu hồi»: quản lý duyệt lại máy. Mỗi tài khoản dùng 1 điện thoại — đổi máy qua «Gửi yêu cầu đổi máy».',
    accent: Color(0xFF00838F),
    shots: [
      GuideShot('mobile-attendance-1', afterBullet: 1, caption: '① Bật cách xác thực: khuôn mặt, GPS, Wi-Fi công ty. ② Khi bật nhiều cách: chỉ cần đạt 1 hay phải đạt tất cả.'),
      GuideShot('mobile-attendance-2', afterBullet: 2, caption: '① Thêm vị trí chấm công. ② Mỗi vị trí có địa chỉ, bán kính, Wi-Fi và số nhân viên được chấm.'),
      GuideShot('mobile-attendance-3', afterBullet: 3, caption: '① Cấp quyền cho điện thoại nhân viên. ② Máy mới đăng ký hiện «Chờ duyệt». ③ Bấm dấu xanh để duyệt, dấu đỏ để từ chối.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'attendance_correction',
    icon: Icons.edit_calendar_rounded,
    title: 'Sửa công, bổ sung công & quên chấm công',
    desc:
        'Nhân viên quên chấm hoặc chấm sai giờ: bổ sung qua phiếu có duyệt, không xóa log máy. Phiếu duyệt xong tự cập nhật giờ chấm và tính lại phạt.',
    bullets: [
      'Bật tính năng: Thiết lập SBOX › Cửa hàng › Tham số hệ thống › «Chấm công bù & quy trình duyệt» → «Cho phép xin sửa / bổ sung công», chọn 1 / 2 / 3 cấp duyệt',
      'Quản lý bổ sung: Báo cáo nhân sự › Tổng hợp chấm công theo ca → bấm ô thiếu («Bấm để bổ sung chấm công thiếu») → «Xác nhận» hoặc «Thêm công và phạt». Tài khoản quản trị / có quyền duyệt được áp dụng ngay',
      'Nhân viên gửi yêu cầu: trên Chấm công Mobile, lượt chấm bị từ chối → «Giải trình» → «Yêu cầu mới»: chọn ngày (trong 30 ngày gần nhất) và loại — «Thêm mới» (giờ vào, giờ ra hoặc cả hai), «Chỉnh sửa» (giờ đã chấm + giờ đúng), «Xóa» (giờ đã chấm) — rồi nhập lý do',
      'Duyệt: Chấm công › Duyệt chấm công → lọc «Sửa / bổ sung công» → tích nhiều phiếu để Duyệt / Từ chối cùng lúc',
      'Mở từng phiếu xem giờ Trước / Sau khi duyệt, lý do, số lần trong tháng, luồng duyệt; từ chối phải ghi lý do',
      'Duyệt đủ cấp: giờ chấm được thêm / sửa, ô giờ có dấu «đã sửa», phiếu phạt tự động của ngày đó bị hủy và tính lại. Muốn vẫn phạt quên chấm: bấm «Duyệt + phạt»',
      'Phạt quên chấm tự động: Thiết lập SBOX › Mức phạt › «Quên chấm công» (0 = không phạt). Ngày có lịch mà chỉ có giờ vào hoặc chỉ giờ ra sinh phiếu chờ duyệt, tự duyệt sau số giờ đã đặt',
    ],
    tip:
        'Ô thiếu chấm hàng loạt thường do chọn sai «Cách chấm công» — sửa trong Thiết lập lương thay vì bổ sung từng ngày.',
    accent: Color(0xFF5E35B1),
    shots: [
      GuideShot('attendance-correction-1', afterBullet: 1, caption: '① Cho phép nhân viên xin sửa / bổ sung công. ② Số cấp duyệt: 1 cấp (quản lý trực tiếp) đến 3 cấp.'),
      GuideShot('attendance-correction-2', afterBullet: 4, caption: '① Lọc «Sửa / bổ sung công». ② «Chọn tất cả» hoặc tích từng phiếu để duyệt nhiều phiếu một lần. ③ Mỗi phiếu: nhân viên, giờ xin bổ sung, lý do.'),
      GuideShot('attendance-correction-3', afterBullet: 6, caption: '① Giờ chấm trước và sau khi duyệt. ② Mức phạt áp dụng nếu chọn «Duyệt + phạt». ③ «Từ chối» (ghi lý do), «Duyệt + phạt» hoặc «Duyệt».'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'raw_attendance',
    icon: Icons.list_alt_rounded,
    title: 'Chấm công thô & duyệt chấm công',
    desc:
        'Chấm công thô là toàn bộ lượt chấm từ máy chấm công và điện thoại, chưa ghép ca. Duyệt chấm công gom các lượt chấm Mobile ngoài vị trí và yêu cầu sửa / bổ sung công cần quản lý xem.',
    bullets: [
      'Bước 1 — Chấm công › Chấm công thô: chọn «Thời gian» (Tuần này, Tháng này…), lọc «Thiết bị», «Kiểu xác thực», «Nhân viên»',
      'Bước 2 — Mỗi dòng: ngày giờ chấm, mã / tên nhân viên, tên trong máy, máy chấm, kiểu xác thực (vân tay, khuôn mặt, thẻ, thủ công)',
      'Bước 3 — Thẻ «Chưa gắn nhân viên» lớn hơn 0: lượt chấm chưa vào bảng công — liên kết mã trên máy với hồ sơ ở Chấm công › Nhân sự chấm công',
      'Bước 4 — «Chấm công thủ công» để nhập tay lượt chấm (máy hỏng, quên chấm); «Excel» để xuất danh sách',
      'Bước 5 — Chấm công › Duyệt chấm công: tab «Cần duyệt» gom chấm Mobile ngoài vị trí và yêu cầu sửa / bổ sung công; lọc Tất cả / Chấm Mobile / Sửa – bổ sung công và theo mức rủi ro',
      'Bước 6 — Chạm từng yêu cầu để xem lý do, ảnh hiện trường, khoảng cách, khớp khuôn mặt → Duyệt hoặc Từ chối; tích nhiều dòng để duyệt hàng loạt',
      'Bước 7 — «Duyệt N bản tin cậy» duyệt nhanh các lượt chấm đạt ngưỡng tin cậy; «Cài đặt duyệt» đặt ngưỡng tự duyệt',
    ],
    tip:
        'Không xóa log máy để sửa công — dùng phiếu sửa / bổ sung công cho quản lý duyệt, lịch sử chấm vẫn giữ nguyên.',
    accent: SboxColors.brand600,
    keywords: ['chấm công thô', 'log chấm công', 'duyệt chấm công', 'chấm ngoài vị trí', 'chấm công thủ công', 'chưa gắn nhân viên', 'kiểu xác thực'],
    shots: [
      GuideShot('raw-attendance-1', afterBullet: 1, caption: '① Bộ lọc: thời gian, thiết bị, kiểu xác thực, nhân viên. ② Kiểu xác thực của từng lượt chấm (vân tay, khuôn mặt…). ③ Chấm công thủ công khi máy hỏng / quên chấm.'),
      GuideShot('raw-attendance-2', afterBullet: 5, caption: '① Lọc yêu cầu: tất cả, chấm Mobile, sửa / bổ sung công. ② Một yêu cầu bổ sung công kèm lý do — chạm để xem và duyệt. ③ Duyệt nhanh các bản tin cậy.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'employee_account',
    icon: Icons.manage_accounts_rounded,
    title: 'Tạo tài khoản & phân quyền',
    desc:
        'Cấp đăng nhập app/web cho quản lý và nhân viên; gán vai trò để mỗi người chỉ thấy đúng chức năng.',
    bullets: [
      'Thiết lập SBOX › Người dùng & bảo mật › Tài khoản nhân viên → «Thêm tài khoản»',
      'Liên kết tài khoản với hồ sơ nhân sự tương ứng',
      'Chọn vai trò (Quản lý, Kế toán, Thu ngân…); chỉnh quyền chi tiết ở Thiết lập SBOX › Người dùng & bảo mật › Phân quyền',
      'NV đăng nhập: mã cửa hàng + tài khoản được cấp',
      'Không dùng chung một mật khẩu cho cả cửa hàng',
      'Thu hồi / khóa tài khoản khi NV nghỉ việc',
    ],
    tip:
        'Admin cửa hàng giữ quyền đầy đủ; kế toán cần xem lương/báo cáo; NV thường chỉ cần chấm công, phép, phiếu lương.',
    accent: SboxColors.brand600,
    shots: [
      GuideShot('employee-account-1', afterBullet: 1, caption: '① Bấm «Thêm tài khoản».'),
      GuideShot('employee-account-2', afterBullet: 2, caption: '① Liên kết hồ sơ nhân viên, form tự điền tên và SĐT. ② Thông tin đăng nhập: họ tên, email, mật khẩu.'),
      GuideShot('employee-account-3', afterBullet: 3, caption: '① Chọn vai trò (Quản lý, Kế toán, Thu ngân…). ② Với thu ngân / order: chọn khu vực bán hàng được xem.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'employee_self_service',
    icon: Icons.phone_iphone_rounded,
    title: 'Dành cho nhân viên: dùng app',
    desc:
        'Nhân viên đăng nhập app SBOX bằng mã cửa hàng + tài khoản được cấp: chấm công trên điện thoại, xem lịch ca, gửi đơn phép / tăng ca / sửa công / đổi ca, xem phiếu lương và nhận thông báo duyệt.',
    bullets: [
      'Bước 1 — Đăng nhập: mã cửa hàng + email / tên đăng nhập + mật khẩu do quản lý cấp (có thể bật đăng nhập bằng vân tay / Face ID của điện thoại)',
      'Bước 2 — Chấm công trên app (nếu cửa hàng bật Chấm công Mobile): mở Chấm công, xác thực khuôn mặt / GPS / WiFi theo cài đặt; chấm ngoài vị trí thì nhập lý do để quản lý duyệt',
      'Bước 3 — Ca làm việc › Lịch của tôi: ca hôm nay, ca cả tuần, tổng giờ; nút ba chấm trên từng ngày để đăng ký ca, xin nghỉ phép, đổi ca với đồng nghiệp',
      'Bước 4 — Gửi đơn: Nghỉ phép, Tăng ca, Sửa / bổ sung công (quên chấm) — theo dõi trạng thái chờ duyệt / đã duyệt ngay trong app',
      'Bước 5 — Phiếu lương: xem thực lĩnh kỳ gần nhất, kỳ chưa thanh toán; chạm một kỳ để xem chi tiết thu nhập (lương, phụ cấp, thưởng, tăng ca) và khấu trừ (BHXH, BHYT, BHTN, thuế, phạt); «Xem bảng chấm công kỳ lương» để đối chiếu công',
      'Bước 6 — Thông báo: chuông báo khi đơn được duyệt / từ chối, có phiếu lương mới, đồng nghiệp xin đổi ca, bài truyền thông bắt buộc đọc',
    ],
    tip:
        'Nhân viên chỉ thấy dữ liệu của chính mình. Sai công thì gửi phiếu sửa công trước ngày chốt lương để kịp vào bảng lương.',
    accent: SboxColors.brand600,
    keywords: ['nhân viên', 'app nhân viên', 'xem phiếu lương', 'lịch ca của tôi', 'gửi đơn', 'chấm công điện thoại', 'đăng nhập'],
    shots: [
      GuideShot('employee-self-service-3', afterBullet: 3, caption: '① Ca hôm nay. ② Tổng ca, giờ làm, ngày nghỉ trong tuần. ③ Nút ba chấm trên từng ngày: đăng ký ca, xin nghỉ, đổi ca.'),
      GuideShot('employee-self-service-1', afterBullet: 5, caption: '① Thực lĩnh kỳ gần nhất. ② Số kỳ chưa thanh toán. ③ Phiếu lương từng kỳ: trạng thái đã chốt / thanh toán — chạm để xem chi tiết.'),
      GuideShot('employee-self-service-2', afterBullet: 5, caption: '① Thu nhập: lương cơ bản, phụ cấp, thưởng, tăng ca. ② Khấu trừ: BHXH, BHYT, BHTN, thuế TNCN, khấu trừ khác. ③ Xem bảng chấm công của kỳ lương.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'penalty_ticket',
    icon: Icons.receipt_long_rounded,
    title: 'Phiếu phạt đi trễ / về sớm',
    desc:
        'Hệ thống có thể tự tạo phiếu phạt từ chấm công theo quy tắc đã cấu hình, hoặc tạo thủ công. Phiếu dùng để theo dõi và thu phạt.',
    bullets: [
      'Thiết lập SBOX › Lương & chính sách › Mức phạt: bậc phút đi trễ / về sớm và số tiền từng bậc; phạt tái phạm',
      'Khi NV chấm trễ vượt ân hạn ca: hệ thống tạo Phiếu phạt (Loại đi trễ)',
      'Mode chỉ chấm vào: vẫn phạt trễ; không phạt «quên chấm ra»',
      'Tài chính nhân sự → tab Cần xử lý / Thưởng & phạt: xem, duyệt, hủy, từ chối phiếu phạt',
      'Thu tiền phạt: khi duyệt chọn trừ lương hoặc thu tiền mặt — phiếu thu tự ghi vào Sổ quỹ (nhãn «Phiếu phạt»)',
      'Bảng lương có thể trừ theo phút trễ đã tổng hợp (tùy cấu hình kỳ)',
      'Báo cáo → Báo cáo phạt',
    ],
    tip:
        'Thiết lập mức phạt và ân hạn ca trước ngày vận hành thật — tránh sửa quy tắc giữa kỳ.',
    accent: Color(0xFFE65100),
    shots: [
      GuideShot('penalty-ticket-1', afterBullet: 1, caption: '① Bậc phạt đi trễ: số phút và số tiền từng bậc. ② Bậc phạt về sớm. Kéo xuống để đặt phạt tái phạm, quên chấm công và cách thu tiền.'),
      GuideShot('penalty-ticket-2', afterBullet: 2, caption: '① Lọc «Phiếu phạt tự động»: phiếu sinh ra từ chấm công. ② Phiếu đi trễ đang chờ duyệt.'),
      GuideShot('penalty-ticket-3', afterBullet: 4, caption: '① «Hủy phiếu» nếu phạt sai (ghi lý do). ② «Duyệt» để trừ lương / thu tiền.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'advance',
    icon: Icons.savings_rounded,
    title: 'Ứng lương',
    desc:
        'Ghi nhận và duyệt tạm ứng; theo dõi còn nợ và trừ khi tính lương hoặc thu qua quỹ.',
    bullets: [
      'Tài chính nhân sự → tab Ứng lương → tạo phiếu (hoặc NV gửi từ app)',
      'Duyệt phiếu trước khi chi tiền',
      'Phiếu đã duyệt: bấm «Chi / thu» khi chi tiền — phiếu chi tự ghi vào Sổ quỹ',
      'Theo dõi đã ứng / còn nợ trên danh sách phiếu',
      'Báo cáo → Báo cáo ứng lương',
      'Phiếu hủy hoặc từ chối không tính vào báo cáo',
    ],
    tip: 'Chi ứng đúng ngày thực tế giúp đối soát quỹ và bảng lương khớp nhau.',
    accent: Color(0xFFAD1457),
    shots: [
      GuideShot('advance-1', afterBullet: 1, caption: '① Chọn nhân viên (hiện hạn mức còn được ứng). ② Số tiền xin ứng. ③ Trừ 1 lần hoặc trả góp nhiều kỳ.'),
      GuideShot('advance-2', afterBullet: 2, caption: '① «Duyệt» phiếu ứng đang chờ. ② Phiếu đã duyệt: bấm «Chi / thu» khi chi tiền.'),
      GuideShot('advance-3', afterBullet: 4, caption: '① Tổng đã chi trong tháng và số sẽ trừ lương kỳ này. ② Lọc phiếu theo trạng thái: chờ duyệt, chờ chi, đã chi.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'bonus_ticket',
    icon: Icons.card_giftcard_rounded,
    title: 'Thưởng phạt',
    desc:
        'Ghi nhận thưởng nóng, thưởng định kỳ hoặc thưởng theo thành tích để cộng vào bảng lương kỳ tương ứng.',
    bullets: [
      'Tài chính nhân sự → tab Thưởng & phạt → Thưởng / phạt',
      'Chọn nhân viên, số tiền, kỳ áp dụng, lý do',
      'Duyệt phiếu trước khi chốt Tổng hợp lương',
      'Kiểm tra dòng thưởng trên bảng lương / phiếu lương NV',
      'Có thể kết hợp với module KPI (tab Nâng cao)',
    ],
    tip: 'Tạo và duyệt thưởng trước ngày chốt bảng lương tháng.',
    accent: Color(0xFF7B1FA2),
    shots: [
      GuideShot('bonus-ticket-1', afterBullet: 1, caption: '① Bấm «Thưởng / phạt» để tạo phiếu. ② Lọc danh sách thưởng / phạt.'),
      GuideShot('bonus-ticket-2', afterBullet: 2, caption: '① Chọn nhân viên. ② Số tiền. ③ Nội dung (hoặc chạm gợi ý nhanh bên dưới).'),
      GuideShot('bonus-ticket-3', afterBullet: 3, caption: '① Chọn cách xử lý tiền: cộng vào lương hoặc chi tiền mặt. ② Bấm «Duyệt».'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'cash',
    icon: Icons.account_balance_wallet_rounded,
    title: 'Thu chi quỹ',
    desc:
        'Sổ quỹ tiền mặt: ghi thu/chi hàng ngày, liên kết ứng lương và thu phạt để đối soát.',
    bullets: [
      'Tài chính nhân sự → tab Sổ quỹ → ghi Thu hoặc Chi',
      'Chọn ngày, số tiền, danh mục, diễn giải',
      'Chi ứng lương: bấm «Chi / thu» trên phiếu ứng — phiếu chi tự liên kết phiếu ứng',
      'Thu phạt: duyệt phiếu phạt và chọn thu tiền mặt — phiếu thu tự liên kết phiếu phạt',
      'Xem tồn quỹ theo ngày; đối soát cuối ngày/tháng',
      'Báo cáo → Báo cáo thu chi',
    ],
    tip: 'Ghi đúng ngày phát sinh — không dồn nhiều ngày vào một phiếu nếu cần đối soát chi tiết.',
    accent: Color(0xFF558B2F),
    shots: [
      GuideShot('cash-1', afterBullet: 1, caption: '① Bấm Thu/Chi (biểu tượng +) để ghi phiếu. ② Phiếu chi ứng lương / thu phạt có liên kết phiếu gốc.'),
      GuideShot('cash-2', afterBullet: 2, caption: '① Chọn Thu hoặc Chi. ② Danh mục. ③ Số tiền và mô tả.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'first_payroll',
    icon: Icons.fact_check_rounded,
    title: 'Chốt công & bảng lương tháng đầu',
    desc:
        'Quy trình cuối kỳ để kiểm tra chấm công rồi chốt lương lần đầu — làm đúng thứ tự để giảm sai sót khi mới triển khai.',
    bullets: [
      'Bước 1 — Kiểm tra Chấm công thô: đủ log, đúng NV, không trùng bất thường',
      'Bước 2 — Báo cáo nhân sự › Tổng hợp chấm công theo ca: kiểm tra công, phút trễ / sớm, ô thiếu chấm (bấm ô thiếu để bổ sung)',
      'Bước 3 — Duyệt hết sửa công, nghỉ phép, đổi ca, phiếu thưởng / phạt / ứng trong kỳ',
      'Bước 4 — Báo cáo nhân sự › Tổng hợp lương → chọn tháng, chi nhánh (bảng lương tự tính khi mở)',
      'Bước 5 — Rà từng NV: công, phụ cấp, BHXH, thuế, ứng, thưởng, phạt',
      'Bước 6 — Xuất Excel nếu cần gửi kế toán',
      'Bước 7 — Bấm «Chốt lương» → chốt NV đã chọn hoặc tất cả → xác nhận. Nhân viên tự nhận thông báo phiếu lương (app, Zalo nếu bật) và xem ở menu Phiếu lương',
    ],
    tip:
        'Chốt lương không khóa chấm công, phép, lịch và chưa có nút mở chốt: sửa dữ liệu sau khi chốt thì bấm «Chốt lương» lại để cập nhật phiếu (phiếu đã trả sẽ báo chênh lệch).',
    accent: Color(0xFFC62828),
    shots: [
      GuideShot('first-payroll-1', afterBullet: 4, caption: '① Chọn kỳ lương (từ ngày đến ngày). ② Lọc theo phòng ban hoặc nhân viên.'),
      GuideShot('first-payroll-2', afterBullet: 5, caption: '① Rà từng nhân viên: công, giờ, tăng ca, thu nhập, khấu trừ. ② Số thực nhận cuối cùng.'),
      GuideShot('first-payroll-3', afterBullet: 7, caption: '① Kiểm tra xong thì bấm «Chốt lương» để tạo phiếu lương cho nhân viên.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'reports',
    icon: Icons.assessment_rounded,
    title: 'Cách xem báo cáo HRM',
    desc:
        'Mọi báo cáo nhân sự nằm ở nhóm menu Báo cáo (sidebar web, hoặc tìm trên app). Chọn khoảng ngày → lọc phòng ban/NV → xem bảng → Xuất Excel nếu cần gửi kế toán.',
    bullets: [
      'Bước 1 — Mở nhóm Báo cáo trên menu trái (web) hoặc ô tìm kiếm module (app)',
      'Bước 2 — Chọn kỳ: hôm nay / tuần / tháng, hoặc tự chọn từ ngày–đến ngày',
      'Bước 3 — Lọc phòng ban hoặc nhân viên nếu chỉ cần một bộ phận',
      'Tổng hợp chấm công — công, phút công, ngày công theo NV',
      'Tổng hợp chấm công theo ca — công, đi trễ, về sớm, thiếu chấm theo từng ca',
      'Đi trễ / Về sớm — danh sách vi phạm giờ (đối chiếu phiếu phạt)',
      'Tính lương / Tổng hợp lương — bảng lương kỳ; Phiếu lương — bản từng NV',
      'Báo cáo phạt · Báo cáo ứng lương · Báo cáo thu chi · Báo cáo nghỉ phép',
      'Báo cáo công tác phí · Báo cáo tài sản · Báo cáo đi đường (nếu dùng)',
      'Bước cuối — nút Xuất Excel trên từng màn; phiếu hủy/từ chối không tính vào số liệu',
    ],
    tip:
        'Số liệu lệch: kiểm tra kiểu chấm công + lịch ca + ân hạn trước khi sửa tay. Báo cáo bán hàng nằm ở tab POS.',
    accent: SboxColors.brand600,
    shots: [
      GuideShot('reports-1', afterBullet: 3, caption: '① Chọn kỳ: hôm nay, tuần, tháng hoặc tự chọn. ② Lọc trạng thái, tìm nhân viên. ③ Bấm «Áp dụng».'),
      GuideShot('reports-2', afterBullet: 10, caption: '① Xuất Excel (điện thoại: trong nút thao tác góc dưới). ② Chuyển xem «Chi tiết» hoặc «Theo NV». ③ Từng phiếu: nhân viên, ngày, loại, trạng thái.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'hr_analytics',
    icon: Icons.analytics_rounded,
    title: 'Báo cáo phân tích & báo cáo đi đường',
    desc:
        'Báo cáo phân tích gom các báo cáo chuyên sâu: chuyên cần, vắng không phép, chấm bất thường, phép còn lại, độ phủ ca, KPI, điều hành tháng. Báo cáo đi đường tổng hợp giờ di chuyển của nhân viên chấm «bắt đầu đi / đến điểm».',
    bullets: [
      'Bước 1 — Báo cáo nhân sự › Báo cáo phân tích: tìm nhanh tên báo cáo hoặc chọn theo nhóm Chấm công, Nghỉ phép & ca, Hiệu suất, Tổng hợp, Tài chính nhân sự',
      'Bước 2 — Mở một báo cáo (vd «Tỷ lệ chuyên cần»): chọn kỳ (tháng / khoảng ngày / năm) ở góc trên',
      'Bước 3 — Xem thẻ tổng quan, biểu đồ xếp hạng theo nhân viên, bảng chi tiết (lọc theo tên, mã, phòng ban, sắp xếp từng cột); xuất Excel / ảnh PNG',
      'Bước 4 — «Báo cáo điều hành tháng»: nhân sự, chấm công, chi phí trong tháng trên một trang cho chủ cửa hàng',
      'Bước 5 — Báo cáo nhân sự › Báo cáo đi đường: chọn kỳ (Hôm nay … Tháng trước, Tùy chọn khác), lọc Đủ cặp / Thiếu chấm, tìm nhân viên',
      'Bước 6 — Đọc thẻ: Chuyến đủ cặp, Tổng giờ (giờ tính lương chỉ gồm lượt đã duyệt), Thiếu chấm, Nhân viên; «Thêm đi đường» để nhập bù lượt đi đường',
    ],
    tip:
        'Giờ đi đường chỉ tính lương khi cặp bắt đầu đi / đến điểm đã được duyệt — duyệt ở Chấm công › Duyệt chấm công.',
    accent: SboxColors.brand600,
    keywords: ['báo cáo phân tích', 'tỷ lệ chuyên cần', 'vắng không phép', 'báo cáo điều hành', 'báo cáo đi đường', 'giờ di chuyển'],
    shots: [
      GuideShot('hr-analytics-1', afterBullet: 1, caption: '① Tìm nhanh báo cáo. ② Nhóm Chấm công — mở «Tỷ lệ chuyên cần». ③ Báo cáo điều hành tháng.'),
      GuideShot('hr-analytics-2', afterBullet: 3, caption: '① Chọn tháng báo cáo. ② Xếp hạng tỷ lệ chuyên cần theo nhân viên. ③ Bảng chi tiết: ngày có mặt, đi trễ, nghỉ phép, vắng.'),
      GuideShot('hr-analytics-3', afterBullet: 5, caption: '① Chọn kỳ báo cáo. ② Tổng giờ di chuyển và giờ tính lương (đã duyệt). ③ Thêm lượt đi đường.'),
    ],
  ),
  const LandingUsageGuideStep(
    id: 'daily_ops',
    icon: Icons.today_rounded,
    title: 'Quy trình hàng ngày & cuối tháng',
    desc:
        'Lịch làm việc của quản lý cửa hàng sau khi đã triển khai xong: buổi sáng duyệt, giữa ngày theo dõi, cuối tháng chốt.',
    bullets: [
      'Sáng: xem Dashboard / chuông thông báo — duyệt phép, đổi ca, chấm mobile chờ duyệt',
      'Trong ngày: Chấm công thô nếu NV báo thiếu log; tạo phiếu thưởng/phạt/ứng khi phát sinh',
      'Cuối ca (nếu kiêm thu ngân): đối soát quỹ Thu chi với tiền mặt ngăn kéo — chi tiết POS ở tab POS',
      'Cuối tuần: rà Tổng hợp theo ca vài ngày; sửa lịch/đổi ca trước khi phát sinh phạt oan',
      'Trước chốt lương 2–3 ngày: duyệt hết phép, OT, thưởng, phạt, ứng trong kỳ',
      'Ngày chốt: Tổng hợp theo ca → Tổng hợp lương → «Chốt lương» (phiếu lương tự gửi cho NV)',
      'Sau chốt: hạn chế sửa lịch / công của kỳ đã chốt (hệ thống không khóa); có sửa thì chốt lại',
    ],
    tip:
        'Một cửa hàng nên có 1 người «chốt kỳ» (kế toán/QL) và 1 người duyệt phép hàng ngày — tránh dồn cuối tháng.',
    accent: Color(0xFF455A64),
  ),
  const LandingUsageGuideStep(
    id: 'common_hrm',
    icon: Icons.help_outline_rounded,
    title: 'Tình huống HRM thường gặp',
    desc:
        'Cách xử lý các trường hợp hay hỏi khi mới vận hành chấm công và lương.',
    bullets: [
      'Đi trễ bị phạt dù vào sớm vài phút: tăng ân hạn trên Thiết lập ca, không sửa từng phiếu',
      'Báo «Thiếu chấm» / không tính công: sai kiểu chấm công — cửa hàng chỉ chấm 1 lần chọn «Chấm vào (đủ ca»)',
      'NV quên chấm: bổ sung ở Tổng hợp chấm công theo ca (bấm ô thiếu) hoặc duyệt yêu cầu ở Duyệt chấm công; không xóa log máy',
      'Máy ZK Offline: kiểm tra mạng máy + SN ở Thiết lập SBOX › Máy chấm công; gọi 0973 024 042 nếu vẫn lỗi',
      'Log hiện PIN lạ: mã trên máy ≠ mã hồ sơ — đồng bộ lại Nhân sự chấm công',
      'Quên mật khẩu: màn đăng nhập → Quên mật khẩu (cần email đã đăng ký)',
      'NV nghỉ việc: đổi trạng thái nghỉ + khóa tài khoản app; không xóa hồ sơ nếu đã có công',
      'Bảng lương lệch: chưa duyệt phép/thưởng/ứng, hoặc đổi ca sau khi đã có phiếu phạt',
      'Không thấy menu: tài khoản thiếu quyền hoặc gói chưa có chức năng — Admin vào Thiết lập SBOX › Phân quyền. Trên máy tính, Ca làm việc, Nghỉ phép, Nhân sự chấm công… mở từ Trang chủ hoặc ô tìm chức năng',
      'Đã duyệt đơn tăng ca nhưng lương không có tiền tăng ca: tiền tăng ca tính theo giờ chấm vượt ngưỡng «Tăng ca trước / sau ca» của ca, không theo đơn',
    ],
    tip:
        'Sửa gốc (ca, mode chấm, ân hạn) trước khi xóa hàng loạt phiếu phạt — tránh phạt lại ngày hôm sau.',
    accent: Color(0xFF6D4C41),
  ),
];

const Map<String, List<String>> _hrmBasicKeywords = <String, List<String>>{
  'getting_started': [
    'bắt đầu',
    'checklist',
    '7 ngày',
    'triển khai',
    'hướng dẫn nhanh',
  ],
  'register': [
    'đăng ký',
    'mã cửa hàng',
    'tài khoản',
    'quên mật khẩu',
    'sboxhrm',
  ],
  'org_structure': [
    'phòng ban',
    'chức vụ',
    'chi nhánh',
    'cơ cấu',
    'tổ chức',
  ],
  'employees': [
    'nhân viên',
    'hồ sơ',
    'import excel',
    'mã nhân viên',
    'pin',
  ],
  'shifts': ['ca làm việc', 'thiết lập ca', 'ân hạn', 'ot', 'tăng ca'],
  'salary': [
    'lương',
    'thiết lập lương',
    'kiểu chấm công',
    'phụ cấp',
    'tính công',
  ],
  'work_schedule_basic': [
    'lịch làm việc',
    'phân ca',
    'đăng ký lịch',
    'lịch tuần',
  ],
  'device_connect': [
    'máy chấm công',
    'zkteco',
    'adms',
    'kết nối máy',
    'serial',
  ],
  'device_users': [
    'vân tay',
    'khuôn mặt',
    'đồng bộ',
    'nhân sự chấm công',
    'face',
  ],
  'gateway_wifi': ['gateway', 'esp32', 'máy chấm công cũ', 'wifi', '4370'],
  'attendance_correction': ['sửa công', 'bổ sung công', 'quên chấm công', 'chấm công bù', 'duyệt chấm công'],
  'mobile_attendance': [
    'chấm công mobile',
    'gps',
    'wifi',
    'điện thoại',
    'duyệt chấm',
  ],
  'employee_account': [
    'tài khoản',
    'phân quyền',
    'đăng nhập',
    'vai trò',
    'nhân viên',
  ],
  'penalty_ticket': [
    'phiếu phạt',
    'đi trễ',
    'về sớm',
    'phạt',
    'tái phạm',
  ],
  'advance': ['ứng lương', 'tạm ứng', 'ứng tiền'],
  'bonus_ticket': ['thưởng', 'phiếu thưởng', 'thưởng nóng'],
  'cash': ['thu chi', 'quỹ', 'tiền mặt', 'sổ quỹ'],
  'first_payroll': [
    'tính lương',
    'chốt lương',
    'bảng lương',
    'tổng hợp lương',
    'cuối tháng',
  ],
  'reports': [
    'báo cáo',
    'xuất excel',
    'tổng hợp chấm công',
    'báo cáo phạt',
    'xem báo cáo',
    'dashboard',
  ],
  'daily_ops': [
    'hàng ngày',
    'cuối tháng',
    'quy trình ngày',
    'duyệt đơn',
    'vận hành hrm',
  ],
  'common_hrm': [
    'đi trễ',
    'quên chấm',
    'thiếu chấm',
    'quên mật khẩu',
    'máy offline',
    'tình huống',
  ],
};

const List<LandingUsageGuideStep> hrmAdvancedSteps = <LandingUsageGuideStep>[
  LandingUsageGuideStep(
    id: 'attendance_modes',
    icon: Icons.rule_rounded,
    title: 'Kiểu chấm công (quan trọng)',
    desc:
        'Mỗi nhân viên/mẫu lương có một chế độ chấm công. Chọn sai mode sẽ thấy «Thiếu chấm», không tính trễ, hoặc phạt quên chấm không đúng.',
    bullets: [
      'Chấm vào & Chấm ra (both): cần đủ cặp vào–ra theo ca; tính trễ và về sớm',
      'Chấm vào đủ ca (checkin/once): 1 lần chấm = đủ ca; tính đi trễ; giờ ra = hết ca; không phạt quên chấm ra',
      'Chấm ra đủ ca (checkout): 1 lần chấm = ra ca; giờ vào = đầu ca; tính về sớm',
      'Chấm 2 lần bất kỳ trong ngày (free2): ≥2 lần chấm/ngày = 1 công; không tính trễ/sớm/OT theo ca',
      'Ca nguyên ngày (fullday): vào ngày N → ra trước mốc sáng ngày N+1 = 1 công (ca ~24h)',
      'Không chấm công (none): không bắt buộc chấm — tránh dùng nếu vẫn muốn phạt quên chấm',
      'Cấu hình tại: Thiết lập lương → chọn NV → mục «Cách chấm công»',
      'Sau khi đổi mode: mở lại Tổng hợp theo ca để xem công/trễ cập nhật',
    ],
    tip:
        'Quán/cửa hàng chỉ chấm 1 lần trên máy (toàn bộ log là CheckIn): chọn «Chấm vào (đủ ca…)».',
    accent: SboxColors.brand600,
    shots: [
      GuideShot('attendance-modes-2', afterBullet: 2, caption: '① Cửa hàng chỉ chấm 1 lần trên máy: chọn «Chỉ chấm vào» (giờ ra lấy hết ca, không phạt quên chấm ra). ② Ca áp dụng cho nhân viên.'),
      GuideShot('attendance-modes-1', afterBullet: 7, caption: '① Chấm vào và ra: cần đủ cặp vào – ra, tính trễ / sớm / tăng ca. ② Chỉ chấm vào hoặc chỉ chấm ra: 1 lần chấm là đủ ca. ③ Chấm 2 lần trong ngày hoặc ca nguyên ngày: không theo giờ ca. ④ Không chấm công: đủ công theo lịch.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'work_schedule',
    icon: Icons.calendar_month_rounded,
    title: 'Ca làm việc: lịch, đăng ký, nghỉ, đổi ca, định mức',
    desc:
        'Một màn «Ca làm việc» cho mọi việc về ca: nhân viên xem lịch và gửi yêu cầu, quản lý xếp ca theo định mức và duyệt tập trung.',
    bullets: [
      'Lịch của tôi: xem ca tuần, bấm ⋮ trên từng ngày để Đăng ký ca (thấy số chỗ còn trống), Xin nghỉ phép, Đổi ca với đồng nghiệp',
      'Đổi ca: chọn ngày và đồng nghiệp đang có ca → đồng nghiệp Đồng ý → quản lý duyệt → lịch 2 người tự hoán đổi',
      'Bảng xếp ca (quản lý): lưới nhân viên × ngày; bấm ô để xếp ca / ngày nghỉ / xoá, duyệt đăng ký ngay trên ô',
      'Hàng «Định mức theo ca»: người có mặt (đã trừ nghỉ phép) / tối thiểu–tối đa; đỏ = thiếu, bấm để kêu gọi bổ sung',
      'Thao tác nhanh: Sao chép lịch tuần trước (chỉ điền ô trống), Nhắc NV chưa đăng ký lịch',
      'Cần duyệt: gom đăng ký ca, đơn nghỉ, đổi ca, ca theo giờ — chọn nhiều để duyệt / từ chối một lần',
      'Thiết lập: Ca mẫu, Định mức nhân sự; màn Lịch làm việc / Nghỉ phép đầy đủ vẫn mở được khi cần tính năng nâng cao',
    ],
    tip: 'Phân ca trước đầu kỳ; hạn chế sửa lịch sau khi đã có nhiều phiếu phạt tự động.',
    accent: Color(0xFF6A1B9A),
    shots: [
      GuideShot('schedule-hub-1', afterBullet: 1, caption: '① Nút ba chấm trên từng ngày: đăng ký ca, xin nghỉ phép, đổi ca với đồng nghiệp. ② Đồng nghiệp xin đổi ca: bấm «Đồng ý» hoặc «Từ chối».'),
      GuideShot('schedule-hub-2', afterBullet: 4, caption: '① Định mức theo ca: số người có mặt / tối thiểu–tối đa, ô đỏ là thiếu người. ② «Thao tác nhanh»: sao chép lịch tuần trước, nhắc nhân viên đăng ký lịch.'),
      GuideShot('schedule-hub-3', afterBullet: 6, caption: '① Lọc theo loại: đăng ký ca, đơn nghỉ, đổi ca, ca theo giờ. ② Tích chọn nhiều yêu cầu. ③ Bấm «Duyệt N» (hoặc «Từ chối») một lần cho tất cả.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'shift_swap',
    icon: Icons.swap_horiz_rounded,
    title: 'Đổi ca làm việc',
    desc:
        'Nhân viên gửi yêu cầu đổi ca với đồng nghiệp hoặc đổi ca trong lịch; quản lý duyệt để cập nhật lịch chính thức.',
    bullets: [
      'NV: menu Đổi ca làm việc → tạo yêu cầu (ngày, ca cũ, ca mới / người nhận)',
      'Người liên quan xác nhận (nếu quy trình yêu cầu)',
      'Quản lý duyệt / từ chối yêu cầu',
      'Sau duyệt: lịch làm việc cập nhật — chấm công tính theo ca mới',
      'Xem hướng dẫn chi tiết ngay trên màn Đổi ca (nút hướng dẫn)',
    ],
    tip: 'Duyệt đổi ca trước ngày làm việc để tránh lệch công và phạt trễ oan.',
    accent: Color(0xFF5E35B1),
    shots: [
      GuideShot('shift-swap-1', afterBullet: 1, caption: '① Ca và ngày của bạn. ② Đồng nghiệp muốn đổi. ③ Ca và ngày muốn nhận. ④ Bấm «Gửi yêu cầu».'),
      GuideShot('shift-swap-2', afterBullet: 3, caption: '① Tab «Chờ QL duyệt». ② Quản lý bấm «Duyệt» hoặc «Từ chối».'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'overtime',
    icon: Icons.more_time_rounded,
    title: 'Tăng ca: đăng ký, duyệt và cách tính tiền',
    desc:
        'Nhân viên xin tăng ca, quản lý duyệt. Lưu ý: tiền tăng ca trên bảng lương tính theo giờ chấm công so với ngưỡng của ca, không theo đơn đã duyệt.',
    bullets: [
      'Mở: ô «Tăng ca» trên Trang chủ hoặc nút «Mở quản lý tăng ca» trên Dashboard (chưa có trong menu)',
      'Nhân viên: «Đăng ký tăng ca» → chọn ngày (tối đa 90 ngày tới), giờ bắt đầu, giờ kết thúc (HH:mm), lý do → «Gửi yêu cầu»',
      'Quản lý: tab «Chờ duyệt» → dấu ✓ để duyệt, ✗ để từ chối (ghi lý do)',
      'Tiền tăng ca tính theo GIỜ CHẤM vượt ngưỡng «Tăng ca trước ca / Tăng ca sau ca» của ca, hoặc toàn bộ giờ của ca loại «Tăng ca» — đơn tăng ca chỉ để xin phép và theo dõi',
      'Hệ số tăng ca (ngày thường / nghỉ tuần / lễ): Thiết lập lương › «Chính sách lương»; cách trả (theo luật / cố định / không tính): khối «Tăng ca» của từng nhân viên',
      'Chỉ muốn trả tăng ca có kế hoạch: tạo ca loại «Tăng ca» và xếp ca đó cho người được duyệt; đặt ngưỡng «Tăng ca sau ca» của ca thường đủ lớn',
    ],
    tip: 'Nhân viên ra muộn quá ngưỡng «Tăng ca sau ca» vẫn được tính tăng ca dù không có đơn — tăng ngưỡng trên ca nếu không muốn trả.',
    accent: Color(0xFFEF6C00),
    shots: [
      GuideShot('overtime-1', afterBullet: 2, caption: '① Chọn ngày tăng ca. ② Giờ bắt đầu và kết thúc (HH:mm). ③ Lý do. ④ Bấm «Gửi yêu cầu».'),
      GuideShot('overtime-2', afterBullet: 3, caption: '① Tab «Chờ duyệt». ② Dấu xanh để duyệt, dấu đỏ để từ chối.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'holidays',
    icon: Icons.celebration_rounded,
    title: 'Ngày lễ & ngày nghỉ đặc biệt',
    desc:
        'Khai báo ngày lễ để tính công/OT ngày lễ và loại trừ khỏi ngày công chuẩn khi cấu hình tương ứng.',
    bullets: [
      'Thiết lập SBOX › Nhân sự & chấm công › Ngày lễ',
      'Thêm ngày lễ cố định / lễ phát sinh trong năm',
      'Kiểm tra hệ số OT ngày lễ trong thiết lập lương / chính sách OT',
      'Đối chiếu Tổng hợp theo ca vào các ngày lễ đã làm việc',
    ],
    tip: 'Cập nhật lịch lễ đầu năm hoặc trước tháng có nghỉ dài để bảng lương không lệch.',
    accent: Color(0xFFD84315),
    shots: [
      GuideShot('holidays-1', afterBullet: 2, caption: '① Thêm một ngày lễ riêng. ② Thêm nhanh các ngày lễ theo quy định còn thiếu trong năm (Tết âm lịch, Giỗ Tổ…).'),
      GuideShot('holidays-2', afterBullet: 3, caption: '① Tên và ngày (có ngày âm lịch). ② Lặp lại hằng năm (chỉ ngày dương lịch cố định). ③ Hệ số lương khi đi làm ngày lễ.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'leave',
    icon: Icons.event_busy_rounded,
    title: 'Nghỉ phép',
    desc:
        'Nhân viên tạo đơn nghỉ; quản lý duyệt. Phép được trừ quỹ phép và phản ánh vào công tùy loại phép.',
    bullets: [
      'Bước 1 — NV vào Chấm công › Nghỉ phép → «Tạo đơn» (hoặc Ca làm việc › Lịch của tôi › ⋮ › Xin nghỉ phép): loại phép, từ ngày–đến ngày, lý do',
      'Bước 2 — Gửi đơn; quản lý nhận thông báo trên web/app',
      'Bước 3 — Quản lý duyệt / từ chối / hủy đơn',
      'Bước 4 — Kiểm tra số ngày phép còn lại (nếu cấu hình quỹ phép)',
      'Bước 5 — Đối chiếu Tổng hợp chấm công: phép đã duyệt không tính nghỉ không phép',
      'Bước 6 — Xem Báo cáo → Báo cáo nghỉ phép; mở hướng dẫn pháp lý trên màn Nghỉ phép khi cần',
      'Thiết lập phép năm: Thiết lập SBOX › Lương & chính sách › Phép năm (số ngày, thâm niên, chuyển phép, tiền phép); cuối năm bấm «Chốt phép năm»',
    ],
    tip: 'Phiếu từ chối hoặc hủy không tính vào báo cáo nghỉ phép.',
    accent: Color(0xFF0284C7),
    shots: [
      GuideShot('leave-1', afterBullet: 1, caption: '① Bấm «Tạo đơn» rồi chọn nhóm chế độ: DN trả lương, không hưởng lương, hoặc BHXH.'),
      GuideShot('leave-2', afterBullet: 1, caption: '① Phép năm còn lại và số ngày đơn này cần. ② Từ ngày – đến ngày. ③ Chọn ca nghỉ. ④ Bấm «Gửi đơn».'),
      GuideShot('leave-3', afterBullet: 3, caption: '① Tab «Chờ duyệt». ② Bấm «Duyệt» hoặc «Từ chối» (điện thoại: chạm vào đơn để mở rồi bấm).'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'insurance_tax',
    icon: Icons.health_and_safety_rounded,
    title: 'Bảo hiểm & thuế TNCN',
    desc:
        'Cấu hình tham gia BHXH/BHYT/BHTN và thuế thu nhập cá nhân để bảng lương trừ đúng phần bắt buộc.',
    bullets: [
      'Thiết lập SBOX › Lương & chính sách › Bảo hiểm: tỷ lệ người lao động / doanh nghiệp, lương cơ sở, vùng',
      'Thiết lập SBOX › Lương & chính sách › Thuế TNCN: biểu thuế lũy tiến, giảm trừ gia cảnh',
      'Người phụ thuộc: Thuế TNCN › mục «Người phụ thuộc của nhân viên»; mức đóng BHXH chọn trên Thiết lập lương từng NV',
      'Kiểm tra cột BH và thuế trên Tổng hợp lương sau khi cấu hình',
    ],
    tip: 'Đối chiếu với kế toán cửa hàng trước kỳ lương đầu tiên có trừ BH/thuế.',
    accent: Color(0xFF00695C),
    shots: [
      GuideShot('insurance-tax-1', afterBullet: 1, caption: '① Tỷ lệ đóng BHXH, BHYT, BHTN: cột trái người lao động, cột phải doanh nghiệp. ② Tổng tỷ lệ bắt buộc của hai bên.'),
      GuideShot('insurance-tax-2', afterBullet: 2, caption: '① Giảm trừ gia cảnh cho bản thân và mỗi người phụ thuộc. ② Biểu thuế lũy tiến từng bậc theo tháng.'),
      GuideShot('insurance-tax-3', afterBullet: 3, caption: '① Mục người phụ thuộc của nhân viên. ② Chạm vào nhân viên để khai số người phụ thuộc và đính kèm hồ sơ.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'kpi',
    icon: Icons.trending_up_rounded,
    title: 'KPI',
    desc:
        'Thiết lập chỉ tiêu, ghi nhận kết quả theo kỳ và gắn với thưởng hiệu suất.',
    bullets: [
      'Menu: KPI (Quản lý vận hành)',
      'Tạo chỉ tiêu, đơn vị đo, trọng số, mức đạt',
      'Giao KPI theo nhân viên hoặc phòng ban / kỳ đánh giá',
      'Nhập kết quả thực tế định kỳ',
      'Dùng kết quả để tạo thưởng hoặc đánh giá',
    ],
    tip: 'Gắn KPI rõ ràng với phiếu thưởng để tránh thưởng tay trùng với KPI.',
    accent: SboxColors.success,
    shots: [
      GuideShot('kpi-1', afterBullet: 3, caption: '① Tab «Chỉ tiêu». ② Bấm «Giao chỉ tiêu» cho nhân viên. ③ Mỗi người: chỉ tiêu, thực đạt và % hoàn thành.'),
      GuideShot('kpi-2', afterBullet: 4, caption: '① Nhập doanh số thực tế cho từng người. ② Bấm «Lưu tất cả».'),
      GuideShot('kpi-3', afterBullet: 5, caption: '① Tab «Lương KPI». ② % KPI và tiền thưởng KPI của từng người. ③ Bấm «Duyệt» để chốt lương KPI.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'bonus',
    icon: Icons.emoji_events_rounded,
    title: 'Thưởng (chính sách)',
    desc:
        'Quản lý các loại thưởng định kỳ, thưởng nóng và thưởng theo KPI — luôn duyệt trước khi chốt lương.',
    bullets: [
      'Tài chính nhân sự → tab Thưởng & phạt',
      'Phân loại thưởng rõ ràng (nóng / tháng / KPI) trong lý do phiếu',
      'Duyệt trước khi chạy Tổng hợp lương',
      'Đối chiếu trên phiếu lương nhân viên',
    ],
    tip: 'Thưởng đã duyệt mới được cộng vào phiếu lương.',
    accent: Color(0xFF7B1FA2),
    shots: [
      GuideShot('bonus-1', afterBullet: 2, caption: '① Lọc «Thưởng». ② Mỗi phiếu ghi rõ lý do để phân biệt thưởng nóng, thưởng tháng, thưởng KPI.'),
      GuideShot('bonus-2', afterBullet: 3, caption: '① Tổng thưởng đã duyệt trong tháng. ② Phiếu còn «Chờ duyệt» chưa được cộng vào lương: duyệt trước khi tính lương.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'penalty',
    icon: Icons.gavel_rounded,
    title: 'Chính sách phạt',
    desc:
        'Quy tắc phạt đi trễ, về sớm, quên chấm, nghỉ không phép — kết hợp ân hạn ca và bậc tiền phạt.',
    bullets: [
      'Thiết lập SBOX › Lương & chính sách › Mức phạt: các bậc phút và số tiền; phạt quên chấm / nghỉ không phép',
      'Phút miễn trễ / miễn về sớm nằm trên từng ca (Ca làm việc), không ở màn Mức phạt',
      'Phiếu tự động sinh khi có log vi phạm (xem Tài chính nhân sự → tab Thưởng & phạt, lọc «Phiếu phạt tự động»)',
      'Mode chỉ chấm vào/ra: hệ thống bỏ ForgotCheck một phía — tránh phạt oan',
      'Thu phạt: khi duyệt chọn trừ lương hoặc tiền mặt (tự ghi Sổ quỹ); theo dõi Báo cáo phạt',
    ],
    tip: 'Nhầm lẫn hay gặp: quên cấu hình ân hạn ca → phạt dù vào trễ 2–3 phút.',
    accent: Color(0xFFE65100),
    shots: [
      GuideShot('penalty-1', afterBullet: 1, caption: '① Phạt quên chấm công và nghỉ không phép (0 = không phạt). ② Cách thu tiền phạt (trừ lương / tiền mặt) và số giờ tự duyệt phạt sau kết ca.'),
      GuideShot('penalty-2', afterBullet: 5, caption: '① Tổng tiền phạt và số đã duyệt (trừ lương / thu tiền mặt). ② Tiền phạt theo loại vi phạm. ③ Xuất Excel.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'production',
    icon: Icons.precision_manufacturing_rounded,
    title: 'Sản lượng / lương sản phẩm',
    desc:
        'Nhập sản lượng theo sản phẩm, ca hoặc nhân viên để tính lương khoán.',
    bullets: [
      'Thiết lập SBOX › Lương & chính sách › Lương sản phẩm: nhóm SP, đơn giá, bậc thang',
      'Menu: Sản lượng → nhập theo ngày/ca/NV',
      'Tổng hợp lương tự cộng phần lương sản phẩm',
      'Đối soát sản lượng trước khi chốt kỳ',
    ],
    tip: 'Khai báo đơn giá trước khi nhập sản lượng hàng loạt.',
    accent: SboxColors.success,
    shots: [
      GuideShot('production-1', afterBullet: 1, caption: '① Nhóm sản phẩm (lọc / sửa nhóm). ② Mỗi sản phẩm có bảng đơn giá theo bậc số lượng.'),
      GuideShot('production-2', afterBullet: 2, caption: '① Bấm «Nhập sản lượng». ② Mỗi dòng: ngày, nhân viên, sản phẩm, số lượng, đơn giá, thành tiền. ③ Tab «Tổng hợp» để đối soát theo nhân viên trước khi chốt kỳ.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'asset',
    icon: Icons.inventory_2_rounded,
    title: 'Tài sản',
    desc:
        'Quản lý tài sản công ty: danh mục, cấp phát, thu hồi, bảo hành và người đang giữ.',
    bullets: [
      'Menu: Tài sản',
      'Thêm tài sản: mã, tên, ngày mua, hạn bảo hành',
      'Cấp phát / thu hồi cho nhân viên hoặc phòng ban',
      'Theo dõi trạng thái đang dùng / hỏng / thanh lý',
      'Báo cáo → Báo cáo tài sản',
    ],
    tip: 'Ghi hạn bảo hành để nhận nhắc trước khi hết hạn.',
    accent: SboxColors.slate700,
    shots: [
      GuideShot('asset-1', afterBullet: 1, caption: '① Bấm «Thêm tài sản». ② Mỗi tài sản hiện trạng thái (đang dùng, trong kho, bảo trì) và người đang giữ.'),
      GuideShot('asset-2', afterBullet: 2, caption: '① Tên tài sản (mã TS tự sinh). ② Chọn loại và danh mục. ③ Giá mua; bên dưới có ngày mua và số tháng bảo hành.'),
      GuideShot('asset-3', afterBullet: 3, caption: '① Nút «…» trên tài sản → Cấp phát: chọn nhân viên nhận. ② Ghi lý do. ③ Bấm «Cấp phát»; thu hồi / chuyển giao cũng ở nút «…».'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'field_checkin',
    icon: Icons.map_rounded,
    title: 'Bản đồ nhân sự / chấm ngoài hiện trường',
    desc:
        'Quản lý xem vị trí tất cả nhân viên trên bản đồ và lộ trình di chuyển trong ca (quãng đường, điểm dừng, chấm công, check-in).',
    bullets: [
      'App SBOX trên điện thoại nhân viên gửi vị trí 30 giây/lần khi đang mở app, chỉ trong giờ ca đã duyệt (hoặc NV được bật chấm ngoài CT)',
      'Bản đồ: xanh = trực tuyến (≤10 phút), cam = vừa mất tín hiệu, xám = ngoại tuyến; vòng tròn là nơi làm việc',
      'Lọc nhanh: đang trong ca, mất tín hiệu trong ca, chưa có vị trí; lọc theo bộ phận, tìm tên',
      'Bấm «Lộ trình»: đường đi trong ca / cả ngày, điểm dừng ≥5 phút, mất tín hiệu, chấm công vào/ra, check-in điểm; tua lại hành trình',
      'Lịch sử vị trí lưu 60 ngày; điểm GPS nhảy bất thường hoặc sai số lớn được tự lọc bỏ',
    ],
    tip: 'Cần có ca làm được duyệt và nhân viên cho phép định vị; nhắc nhân viên giữ app mở trong ca để lộ trình liền mạch.',
    accent: Color(0xFF0277BD),
    shots: [
      GuideShot('field-checkin-1', afterBullet: 3, caption: '① Số nhân viên theo tình trạng: trực tuyến, trong ca, mất tín hiệu, ngoại tuyến — chạm để lọc. ② Tìm tên / mã và lọc theo bộ phận. ③ Nút xem lộ trình của nhân viên.'),
      GuideShot('field-checkin-2', afterBullet: 4, caption: '① Xem lộ trình trong ca hoặc cả ngày. ② Quãng đường, thời gian di chuyển, số lần dừng, mất tín hiệu. ③ Dòng thời gian: chấm công, điểm dừng, check-in khách hàng.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'tasks',
    icon: Icons.task_alt_rounded,
    title: 'Công việc (Tasks)',
    desc:
        'Giao việc, theo dõi tiến độ và hạn hoàn thành trong nhóm — hỗ trợ vận hành hàng ngày ngoài chấm công.',
    bullets: [
      'Menu: Công việc',
      'Tạo việc: tiêu đề, người nhận, hạn, mức ưu tiên',
      'Cập nhật trạng thái: chờ / đang làm / hoàn thành',
      'Lọc theo người phụ trách hoặc hạn tuần này',
    ],
    tip: 'Dùng Task cho việc nội bộ ngắn; quy trình phép/đổi ca vẫn dùng module chuyên biệt.',
    accent: Color(0xFF3949AB),
    shots: [
      GuideShot('tasks-1', afterBullet: 1, caption: '① Bấm «Tạo công việc». ② Lọc nhanh: Của tôi, Quá hạn, Trạng thái, Ưu tiên, Người thực hiện.'),
      GuideShot('tasks-2', afterBullet: 2, caption: '① Tiêu đề công việc. ② Loại và mức ưu tiên. ③ Giao cho một hoặc nhiều người. ④ Thời gian bắt đầu và hạn hoàn thành.'),
      GuideShot('tasks-3', afterBullet: 3, caption: '① Tab Kanban: mỗi cột là một trạng thái (Chờ làm, Đang làm, Đang xem xét, Hoàn thành). ② Kéo thẻ sang cột khác để đổi trạng thái, chạm thẻ để xem chi tiết.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'business_trip',
    icon: Icons.flight_takeoff_rounded,
    title: 'Công tác & tạm ứng công tác phí',
    desc:
        'Tạo hồ sơ công tác, tạm ứng / quyết toán chi phí đi công tác theo quy trình duyệt của cửa hàng.',
    bullets: [
      'Menu: Công tác phí / Công tác (Quản lý vận hành hoặc Tài chính — tùy cấu hình)',
      'Tạo đề xuất công tác: thời gian, địa điểm, tạm ứng',
      'Duyệt đề xuất → chi tạm ứng (có thể qua Thu chi)',
      'Sau chuyến: kê khai hóa đơn / quyết toán → duyệt hoàn ứng hoặc chi bổ sung',
      'Theo dõi báo cáo công tác nếu có trên menu Báo cáo',
    ],
    tip: 'Tách tạm ứng công tác khỏi ứng lương tháng để đối soát quỹ rõ ràng.',
    accent: Color(0xFF00838F),
    shots: [
      GuideShot('business-trip-1', afterBullet: 1, caption: '① Bấm «Hồ sơ mới». ② Mỗi hồ sơ hiện người đi, trạng thái, số tiền đã ứng và đã hạch toán.'),
      GuideShot('business-trip-2', afterBullet: 2, caption: '① Tiêu đề và điểm đến. ② Chọn từ ngày – đến ngày. ③ Bấm «Tạo & nhập chi phí» rồi tạo phiếu ứng nếu cần.'),
      GuideShot('business-trip-3', afterBullet: 3, caption: '① Phiếu ứng công tác: số tiền đề nghị, trạng thái duyệt, đã chi hay chưa. ② Quản lý bấm «Duyệt ứng» hoặc «Từ chối ứng».'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'meal',
    icon: Icons.restaurant_rounded,
    title: 'Chấm cơm',
    desc:
        'Máy chấm công đặt tại căn tin: mỗi lượt chấm in 1 phiếu ăn, tự đếm số người ăn và tính tiền ăn để thu.',
    bullets: [
      'Quản lý buổi ăn: đặt giờ Sáng / Trưa / Tối và giá suất; chấm sớm / trễ tối đa 30 phút vẫn nhận, ngoài khung giờ không tính',
      'Khai báo máy chấm công loại «Chấm cơm» — chấm tại máy này là ghi suất ăn, không phải chấm công',
      'Trạm in phiếu ăn: mở trên máy tính / máy POS cạnh máy chấm, chọn máy in → tự in phiếu (số phiếu, tên, buổi, món)',
      'Căn tin (quyền Sửa «Chấm cơm») nhập thực đơn ở tab Hôm nay / Căn tin; nhân viên xem thực đơn và phiếu của mình ở tab Hôm nay',
      'Tab Căn tin: số suất theo buổi, ai đăng ký mà chưa ăn; tab Báo cáo: suất và tiền ăn từng người, xuất Excel',
      'Tab Công nợ: «Tính tiền cơm» cho tháng, ghi nhận khi nhân viên trả tiền',
    ],
    tip: 'Giá suất được chốt tại lúc chấm — đổi giá buổi ăn không làm thay đổi tiền của các ngày đã ăn.',
    accent: Color(0xFFF97316),
    shots: [
      GuideShot('meal-1', afterBullet: 1, caption: '① Tên buổi ăn (Sáng / Trưa / Tối). ② Giá mỗi suất. ③ Giờ bắt đầu – kết thúc của buổi.'),
      GuideShot('meal-2', afterBullet: 5, caption: '① Tab Căn tin: suất đã phục vụ, đã đăng ký, ăn không đăng ký, đăng ký chưa ăn. ② Từng buổi: số suất, món, danh sách người đăng ký mà chưa ăn.'),
      GuideShot('meal-3', afterBullet: 6, caption: '① Bấm «Tính tiền cơm tháng». ② Mỗi nhân viên: số suất, đã trả, còn nợ; nút thẻ để ghi nhận trả tiền.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'communication',
    icon: Icons.campaign_rounded,
    title: 'Truyền thông nội bộ',
    desc:
        'Đăng tin, nội quy, thông báo tới app nhân viên — kênh chính thức thay cho nhóm chat rời rạc.',
    bullets: [
      'Menu: Truyền thông → tạo bài viết',
      'Ghim tin quan trọng; chọn đối tượng (toàn cửa hàng / nhóm)',
      'Bật «Bắt buộc đọc và xác nhận» khi cần mọi người đọc ngay — xem được ai chưa đọc',
      'NV xem tại Tổng quan hoặc mục Truyền thông',
    ],
    tip: 'Thông báo đổi ca, chính sách phạt, lịch lễ qua Truyền thông để có dấu vết.',
    accent: SboxColors.success,
    shots: [
      GuideShot('communication-1', afterBullet: 1, caption: '① Ô «Chia sẻ điều gì đó…» (điện thoại: nút bút góc dưới) để viết bài. ② Chọn kênh: Bảng tin, Thông báo, Nội quy & chính sách…'),
      GuideShot('communication-2', afterBullet: 2, caption: '① Người nhận: toàn công ty hoặc chọn nhóm / từng người. ② Bắt buộc đọc và xác nhận: xem được ai chưa đọc. ③ Ghim bài lên đầu bảng tin.'),
      GuideShot('communication-3', afterBullet: 4, caption: '① Nhân viên bấm «Tôi đã đọc và cam kết»; thanh bên dưới cho biết bao nhiêu người đã xác nhận. ② Khung «Cần bạn xử lý»: các bài bắt buộc đọc còn chờ.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'feedback',
    icon: Icons.feedback_rounded,
    title: 'Kiến nghị / Khiếu nại',
    desc:
        'Nhân viên gửi khiếu nại, kiến nghị, góp ý (có thể ẩn danh); người xử lý tiếp nhận, trao đổi, giải quyết đúng hạn.',
    bullets: [
      'Gửi: chọn loại (Khiếu nại / Kiến nghị / Góp ý), chủ đề, mức độ, ảnh; gửi hòm thư chung hoặc 1 quản lý',
      'Ẩn danh: không ai kể cả quản trị thấy tên / bộ phận; người gửi vẫn theo dõi và trao đổi trong «Của tôi»',
      'Hạn xử lý theo mức độ: Khẩn 1 ngày, Cao 2 ngày, Bình thường 3 ngày, Thấp 7 ngày; quá hạn được đánh dấu đỏ',
      'Người xử lý: Tiếp nhận → giao người xử lý → trao đổi (ghi chú nội bộ người gửi không thấy) → Đã giải quyết',
      'Người gửi đánh giá 1–5 sao, hoặc mở lại trong 30 ngày nếu chưa thoả đáng; thu hồi khi phiếu chưa được tiếp nhận',
      'Tab Báo cáo: đúng hạn, thời gian phản hồi / giải quyết, hài lòng, chủ đề nóng, hiệu quả người xử lý',
    ],
    tip: 'Nhân viên chỉ thấy phiếu của mình; quản lý thấy hòm thư chung và phiếu gửi / giao cho mình; Admin / Giám đốc thấy tất cả.',
    accent: SboxColors.brand600,
    shots: [
      GuideShot('feedback-1', afterBullet: 1, caption: '① Chọn loại: khiếu nại, kiến nghị hoặc góp ý chung. ② Chọn chủ đề. ③ Nhập tiêu đề và nội dung; kéo xuống để chọn mức độ, người nhận, gửi ẩn danh.'),
      GuideShot('feedback-2', afterBullet: 4, caption: '① Lọc nhanh: đang mở, chờ tiếp nhận, quá hạn, giao cho tôi. ② Phiếu quá hạn có nhãn đỏ «Quá hạn …»; bấm vào phiếu để tiếp nhận, giao người xử lý, trao đổi.'),
      GuideShot('feedback-3', afterBullet: 6, caption: '① Tỷ lệ đúng hạn, thời gian phản hồi và giải quyết trung bình. ② Mức hài lòng và số lần mở lại.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'notifications',
    icon: Icons.notifications_active_rounded,
    title: 'Thông báo & nhắc việc',
    desc:
        'Cấu hình thông báo đẩy và kênh nhắc (duyệt đơn, chấm công, truyền thông) để quản lý không bỏ sót.',
    bullets: [
      'Thiết lập SBOX › Tích hợp & thông báo › Thông báo: bật / tắt từng loại hoặc cả nhóm (tự lưu)',
      'NV bật thông báo trên điện thoại cho app SBOX',
      'Theo dõi chuông thông báo trên web/app: duyệt phép, đổi ca, phiếu chờ',
      'Dùng Truyền thông khi cần broadcast toàn cửa hàng',
    ],
    tip: 'Trên iOS/Android: cho phép thông báo app ngay sau khi cài để nhận duyệt đơn kịp thời.',
    accent: Color(0xFF6D4C41),
    shots: [
      GuideShot('notifications-1', afterBullet: 1, caption: '① Bật / tắt cả một nhóm thông báo. ② Hoặc tắt từng loại (vd máy chấm công mất kết nối); tự lưu khi bật / tắt.'),
      GuideShot('notifications-2', afterBullet: 3, caption: '① Lọc tất cả / chưa đọc / đã đọc, hoặc theo loại. ② Thông báo chưa đọc có chấm đỏ; bấm «Xem chi tiết» để mở và duyệt.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'zalo_bot',
    icon: Icons.forum_rounded,
    title: 'Zalo bot: gửi thông báo cho nhân viên qua Zalo',
    desc:
        'Phiếu lương, phiếu phạt, kết quả duyệt đơn, lịch ca… gửi thêm qua Zalo cho nhân viên đã liên kết. Thông báo trong app vẫn gửi như cũ.',
    bullets: [
      'Quản trị: vào bot.zapps.me (Zalo Bot Platform), đăng nhập Zalo, tạo bot cho cửa hàng (miễn phí)',
      'Thiết lập SBOX › Tích hợp & thông báo › Zalo bot: dán «Token bot» và «Link mở bot» (https://…) → Lưu',
      'Kiểm tra «Nhận tin từ Zalo (webhook)» báo «Hoạt động»; báo lỗi thì bấm «Đăng ký lại»',
      'Bật «Bật gửi qua Zalo», chọn «Nhóm thông báo» (lương, phạt, chấm công, phép, tăng ca, ca làm, phê duyệt…); bật «Ẩn số tiền» nếu không muốn hiện tiền trong tin',
      'Nhân viên: Cài đặt › Liên kết Zalo → «Lấy mã liên kết» (mã 6 số, hết hạn sau 15 phút) → «Mở bot Zalo» → gửi mã cho bot',
      'Bot trả lời «Đã liên kết» là xong; danh sách «Nhân viên đã liên kết» hiện trên màn Zalo bot, bấm «Gửi tin thử cho tôi» để kiểm tra',
      'Hủy liên kết: nhân viên gửi «HUY» cho bot, hoặc quản trị bấm biểu tượng hủy liên kết cạnh tên',
    ],
    tip: 'Dòng «Liên kết Zalo» trong Cài đặt chỉ hiện khi cửa hàng đã bật bot. Token sai hoặc hết hạn: tạo lại token trên bot.zapps.me rồi dán lại.',
    accent: Color(0xFF0068FF),
    shots: [
      GuideShot('zalo-bot-1', afterBullet: 2, caption: '① Làm theo 3 bước tạo bot trên bot.zapps.me. ② Dán token bot và link mở bot rồi bấm Lưu.'),
      GuideShot('zalo-bot-2', afterBullet: 4, caption: '① Webhook «Hoạt động» là nhân viên liên kết được. ② Bật gửi qua Zalo và chọn nhóm thông báo.'),
      GuideShot('zalo-bot-3', afterBullet: 5, caption: '① Mã liên kết 6 số (hết hạn sau 15 phút). ② Bấm «Mở bot Zalo» rồi gửi mã cho bot.'),
    ],
  ),
  LandingUsageGuideStep(
    id: 'ai_assistant',
    icon: Icons.auto_awesome,
    title: 'Trợ lý ảo AI: hỏi, ra lệnh bằng chữ hoặc giọng nói',
    desc:
        'Trợ lý đọc báo cáo bán hàng và nhân sự đúng quyền của bạn để trả lời, và làm thay việc hằng ngày: lập phiếu, xin nghỉ, báo giá, đặt bàn, duyệt đơn… Mọi thao tác chỉ ghi khi bạn xác nhận.',
    bullets: [
      'Mở: biểu tượng ✨ trên thanh trên cùng (điện thoại / máy tính) hoặc POS › Thêm › «Trợ lý ảo»',
      'Hỏi số liệu: «Doanh thu tuần này so với tuần trước?», «Ai đi trễ nhiều nhất tháng này?», «Món nào bán chậm?»',
      'Ra lệnh: «Phạt An 50k đi trễ hôm nay», «Mai tôi xin nghỉ ca tối», «Báo giá cho chị Lan 10 thùng Coca», «Đặt bàn 5 tối nay 7 giờ cho anh Nam, 6 người», «Thêm nhân viên mới Trần Thị Mai, bếp»',
      'Trợ lý hiện THẺ chờ xác nhận: kiểm tra từng dòng rồi bấm «Xác nhận» (hoặc «Bỏ»); lưu xong có «Hoàn tác» trong ít phút',
      'Thẻ xóa / hủy chứng từ màu đỏ: hỏi lại một lần nữa và không hoàn tác được',
      'Nói thay gõ: bấm micro, nói xong im ~2 giây là tự gửi; câu trả lời được đọc to (bật / tắt bằng nút loa)',
      'Rảnh tay: menu ⋮ › «Rảnh tay» — đọc xong tự nghe tiếp; nói «xác nhận», «bỏ», «hoàn tác», «xác nhận thẻ 2»; thẻ xóa / hủy phải nói «chắc chắn xác nhận»; nói «dừng» để tắt',
      'Hỏi cách dùng: «Cách kết nối hóa đơn điện tử?», «Sao máy in bếp không in?» — trợ lý trả lời theo hướng dẫn này và mở đúng bước',
      'Nhật ký: menu ⋮ › «Nhật ký thao tác AI» xem mọi phiếu trợ lý đã lưu (ai ra lệnh, lúc nào)',
      'Quản trị: Thiết lập SBOX › Trợ lý AI — khóa Gemini riêng của cửa hàng, «Hồ sơ cửa hàng cho trợ lý», «Bản tin sáng tự động»',
    ],
    tip:
        'Trợ lý chỉ thấy và làm những gì tài khoản bạn được phân quyền. Không có khóa AI: vẫn hỏi được dữ liệu cá nhân và hướng dẫn, nhưng không phân tích / thao tác.',
    accent: Color(0xFF7C3AED),
    shots: [
      GuideShot('ai-assistant-1', afterBullet: 1, caption: '① Ô hỏi hoặc ra lệnh. ② Nút micro để nói thay gõ. ③ Menu ⋮: rảnh tay, nhật ký thao tác.'),
      GuideShot('ai-assistant-2', afterBullet: 2, caption: '① Câu trả lời kèm số liệu và gợi ý hành động. ② Biểu đồ dựng từ báo cáo trợ lý vừa đọc. ③ Nút mở đúng màn báo cáo để xem chi tiết.'),
      GuideShot('ai-assistant-3', afterBullet: 3, caption: '① Thẻ chờ xác nhận: từng dòng của phiếu sắp lập. ② Bấm «Xác nhận» để lưu, «Bỏ» nếu sai.'),
      GuideShot('ai-assistant-4', afterBullet: 8, caption: '① Trợ lý trả lời theo đúng hướng dẫn sử dụng này. ② Nút mở thẳng bài hướng dẫn tương ứng.'),
      GuideShot('ai-assistant-5', afterBullet: 10, caption: '① Bật / tắt trợ lý và khai khóa riêng của cửa hàng (nhiều khóa thì hết lượt tự chuyển). ② «Hồ sơ cửa hàng cho trợ lý»: giờ mở cửa, nội quy, tên gọi tắt của món.'),
      GuideShot('ai-assistant-6', afterBullet: 9, caption: '① Mọi phiếu trợ lý đã lưu: ai ra lệnh, lúc nào, kết quả. ② Việc rủi ro cao (xóa / hủy chứng từ) được đánh dấu riêng.'),
    ],
  ),
];

const Map<String, List<String>> _hrmAdvancedKeywords = <String, List<String>>{
  'attendance_modes': [
    'kiểu chấm công',
    'checkin',
    'chỉ chấm vào',
    'thiếu chấm',
    'mode',
  ],
  'work_schedule': ['lịch làm việc', 'sao chép tuần', 'duyệt lịch'],
  'shift_swap': ['đổi ca', 'đổi lịch', 'swap'],
  'overtime': ['tăng ca', 'ot', 'làm thêm giờ', 'đăng ký tăng ca'],
  'holidays': ['ngày lễ', 'nghỉ lễ', 'ot ngày lễ'],
  'leave': ['nghỉ phép', 'đơn nghỉ', 'quỹ phép', 'phép năm'],
  'insurance_tax': ['bảo hiểm', 'bhxh', 'thuế', 'tncn'],
  'kpi': ['kpi', 'chỉ tiêu', 'hiệu suất'],
  'bonus': ['thưởng', 'chính sách thưởng'],
  'penalty': ['chính sách phạt', 'quên chấm', 'ân hạn'],
  'production': ['sản lượng', 'lương sản phẩm', 'khoán'],
  'asset': ['tài sản', 'cấp phát', 'thu hồi'],
  'field_checkin': [
    'bản đồ',
    'hiện trường',
    'gps ngoài',
    'field checkin',
  ],
  'tasks': ['công việc', 'task', 'giao việc'],
  'business_trip': ['công tác', 'công tác phí', 'tạm ứng công tác'],
  'meal': ['chấm cơm', 'suất ăn', 'ăn ca'],
  'communication': ['truyền thông', 'thông báo nội bộ', 'tin tức'],
  'feedback': ['góp ý', 'khiếu nại', 'phản ánh'],
  'notifications': ['thông báo', 'push', 'nhắc việc'],
  'zalo_bot': ['zalo', 'bot', 'liên kết zalo', 'tin nhắn'],
  'ai_assistant': ['trợ lý', 'AI', 'giọng nói', 'micro', 'rảnh tay', 'gemini', 'xác nhận'],
};

Map<String, List<String>> get hrmAllKeywords => {..._hrmBasicKeywords, ..._hrmAdvancedKeywords};
