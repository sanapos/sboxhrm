import 'package:flutter/material.dart';

import 'landing_usage_guide.dart';

/// Hướng dẫn chi tiết theo ngành hàng (tab «Ngành hàng» trên trang Hướng dẫn).
/// Mỗi ngành: chọn ngành → khai báo hàng / dịch vụ → quy trình bán → tình huống hay gặp.
const landingIndustrySteps = <LandingUsageGuideStep>[
  LandingUsageGuideStep(
    id: 'ind_choose',
    icon: Icons.category_rounded,
    title: 'Chọn ngành hàng & ý nghĩa từng ngành',
    desc:
        'Ngành hàng quyết định màn bán hàng hiện gì: sơ đồ bàn/ghế/phòng, tính giờ, gửi bếp, gói buổi, hoa hồng. '
        'Chọn đúng ngành trước khi nhập hàng hóa.',
    bullets: [
      'Mở: Cài đặt → Ngành hàng & chế độ bán → Chọn ngành hàng → Đổi ngành (lưu ngay, bật sẵn cấu hình mặc định của ngành)',
      'Bán lẻ / Siêu thị — quầy bán, quét mã vạch, cân điện tử, tồn kho. Không có sơ đồ bàn',
      'Nhà hàng / Cafe — sơ đồ bàn, thực đơn, gửi bếp / KDS, QR order tại bàn, hỏi số khách khi mở bàn',
      'Karaoke / Bi-a / Phòng giờ — sơ đồ phòng, tính tiền giờ theo block, gói giờ đếm ngược, tạm dừng / chốt giờ. Bắt buộc chọn phòng khi bán',
      'Salon / Spa / Nail — sơ đồ ghế, dịch vụ, gói liệu trình nhiều buổi, chọn nhân viên làm & hoa hồng',
      'Gym / Yoga — bán thẻ tập (tháng/quý/năm) hoặc gói buổi, check-in hội viên bằng máy chấm công hoặc tại quầy',
      'Khách sạn / Lưu trú — sơ đồ phòng, nhận / trả phòng, tính theo giờ hoặc theo đêm, folio tạm tính, dịch vụ kèm',
      'Sau khi đổi ngành vẫn có thể bật/tắt từng tính năng: Tính giờ, Gói buổi, Hoa hồng NV, Tạm tính, Khóa đơn tạm đa máy, Cho phép tồn âm, Ca thu ngân…',
    ],
    tip:
        'Đổi ngành xong hãy đóng và mở lại màn Bán hàng. Không thấy sơ đồ bàn / tính giờ → kiểm tra lại ngành và các công tắc trong Ngành hàng & chế độ bán.',
    accent: Color(0xFF1565C0),
  ),
  LandingUsageGuideStep(
    id: 'ind_retail',
    icon: Icons.shopping_basket_rounded,
    title: 'Bán lẻ / Siêu thị / Tạp hóa',
    desc:
        'Bán nhanh tại quầy: quét mã → thanh toán → in hóa đơn. Quản lý tồn kho, giá vốn, lô / hạn dùng, cân điện tử.',
    bullets: [
      'Thiết lập: Chế độ bán mặc định «Bán nhanh — quét mã, thanh toán ngay» (hoặc «Bán thường» khi cần nhập khách, ghi chú)',
      'Hàng hóa: nhập mã vạch cho từng sản phẩm; nhiều đơn vị (lon / thùng) khai quy đổi và giá riêng',
      'Cân điện tử: bật «Đọc mã vạch cân điện tử», nhập Đầu mã của cân (vd 20, 21) và Số chữ số mã hàng (PLU) — quét tem cân ra đúng hàng + trọng lượng / thành tiền',
      'Bán hàng: quét hoặc gõ tên (F3) → chỉnh số lượng → F9/Thanh toán → chọn tiền mặt / chuyển khoản / QR → in',
      'Nhiều khách cùng lúc: bấm + để mở hóa đơn mới (HĐ1, HĐ2…), chuyển qua lại không mất giỏ',
      'Khách quen: chọn khách trước khi thanh toán để tích điểm / ghi công nợ',
      'Hết hàng: mặc định chặn bán khi tồn âm; muốn bán trước nhập sau thì bật «Cho phép bán khi hết hàng / tồn âm»',
      'Cuối ngày: Báo cáo POS → Tổng kết cuối ngày; bật «Ca thu ngân» nếu nhiều thu ngân giao ca',
    ],
    tip:
        'Nhập hàng NCC (Nhà cung cấp → Nhập hàng) trước khi bán để giá vốn và lợi nhuận đúng.',
    accent: Color(0xFF2E7D32),
  ),
  LandingUsageGuideStep(
    id: 'ind_restaurant',
    icon: Icons.restaurant_rounded,
    title: 'Nhà hàng / Cafe / Trà sữa',
    desc:
        'Bán theo bàn: mở bàn → gọi món → gửi bếp → tạm tính → thanh toán. Hỗ trợ topping, ghi chú nhanh, QR order tại bàn, màn hình bếp.',
    bullets: [
      'Tạo bàn: trên Sơ đồ bàn bấm Tạo bàn nhanh / Sửa bàn / phòng; chia khu vực (Tầng 1, Sân vườn…)',
      'Thực đơn: món + nhóm món; món có topping (thêm trân châu, size…) và «Hàng thành phần — định lượng» để trừ kho nguyên liệu',
      'Mở bàn: chạm bàn trống → nhập Số khách (nếu bật hỏi số khách) → Vào chọn món / dịch vụ',
      'Gửi bếp: sau khi gọi món bấm Gửi bếp / In bếp; gọi thêm chỉ gửi phần mới. Bếp xem trên Màn hình bếp (KDS): đang làm / sẵn sàng / xong',
      'Tạm tính: in phiếu tạm tính cho khách xem trước khi trả tiền (cần bật «Cho phép tạm tính»)',
      'Chuyển bàn, Gộp bàn vào đây, Tách bàn / Tách hóa đơn: chạm giữ bàn trên sơ đồ để mở menu thao tác',
      'QR order tại bàn: khách quét QR trên bàn gọi món; tùy chọn chỉ gọi khi đã mở bàn, giới hạn GPS trong quán, xác nhận order, tự in phiếu bếp',
      'Thanh toán xong bàn tự về trống; «Trả về bàn trống» khi khách đi mà chưa gọi món',
    ],
    tip:
        'Nhiều máy (thu ngân + điện thoại phục vụ) cùng bán: bật «Khóa đơn tạm đa máy» để 2 người không sửa cùng một bàn.',
    accent: Color(0xFFC62828),
  ),
  LandingUsageGuideStep(
    id: 'ind_room_hourly',
    icon: Icons.mic_external_on_rounded,
    title: 'Karaoke / Bi-a / Phòng giờ',
    desc:
        'Tính tiền giờ theo phòng / bàn: đếm giờ từ lúc mở, làm tròn theo block, cộng đồ uống. Có gói giờ bán trước đếm ngược, tạm dừng và chốt tiền giờ.',
    bullets: [
      'Tạo dịch vụ tính giờ: Hàng hóa → Thêm dịch vụ → mục «Tính giờ / gói buổi» → Cách tính: Theo giờ / Theo phút / Theo block (karaoke / bi-a)',
      'Khai báo: giá mỗi giờ (hoặc block), Phí mở phòng + số phút đã gồm, block làm tròn (vd 15 phút), phút tối thiểu, ân hạn',
      'Cài đặt → Ngành hàng: chọn «Dịch vụ tính giờ / block / ngày» mặc định → mở phòng là tự thêm dòng tiền giờ',
      'Mở phòng: chạm phòng trống → đồng hồ bắt đầu chạy, ô phòng hiện thời gian đã dùng; tiền giờ tự cập nhật trên hóa đơn',
      'Tạm dừng tính giờ / Tiếp tục tính giờ: khách ra ngoài, mất điện… khoảng dừng không tính tiền',
      'Chốt tiền giờ: khách xin tính tiền nhưng còn ngồi — đồng hồ dừng tại giờ chốt, ô phòng hiện «Chốt hh:mm». «Mở chốt giờ» để tính tiếp (khoảng đã chốt không tính)',
      'Gói giờ đếm ngược (vd gói 1 giờ): dịch vụ nhập «Thời lượng gói (phút)», «Báo trước khi hết» và «Dịch vụ tính quá giờ». Trên hóa đơn bấm ▶ Bắt đầu → đếm ngược; sắp hết máy báo, hết giờ báo và tự thêm dòng quá giờ',
      'Đồng hồ riêng từng dòng: mỗi dòng dịch vụ tính giờ có nút Bắt đầu / Dừng / Kết thúc / Tính tiếp — dùng khi 1 phòng có nhiều bàn bi-a hoặc thêm giờ riêng',
      'Chuyển phòng giữ nguyên giờ đã dùng; thanh toán xong phòng về trống',
    ],
    tip:
        'Ô phòng: xanh = đang chạy, vàng = sắp hết gói, đỏ = hết giờ / quá giờ, tím = đã chốt giờ.',
    accent: Color(0xFF6A1B9A),
  ),
  LandingUsageGuideStep(
    id: 'ind_salon',
    icon: Icons.spa_rounded,
    title: 'Salon / Spa / Nail / Barber',
    desc:
        'Sơ đồ ghế / giường, lịch hẹn, dịch vụ theo lần hoặc liệu trình nhiều buổi, chọn nhân viên làm để tính hoa hồng.',
    bullets: [
      'Ghế / giường: tạo trên Sơ đồ ghế (loại Ghế); Lịch hẹn: đặt theo ngày – giờ – dịch vụ – khách',
      'Dịch vụ lẻ: Cách tính «Giá cố định» (cắt, gội) hoặc tính giờ (massage theo giờ) — dịch vụ tính giờ có đồng hồ Bắt đầu / Dừng / Kết thúc trên từng dòng',
      'Gói liệu trình: dịch vụ nhập «Số buổi» (vd 10) và hạn dùng (ngày). Bán gói có gắn khách → khách được cộng buổi',
      'Combo liệu trình: tạo Combo gồm nhiều dịch vụ (vd 10 buổi massage + 5 buổi đắp mặt) — mỗi thành phần có số buổi riêng',
      'Trừ buổi: trên màn bán bấm nút «Trừ buổi» → chọn khách → chọn gói → chọn NV làm buổi → xác nhận trừ 1 buổi',
      'Chọn nhân viên: bấm giữ dòng dịch vụ → chọn NV; combo chọn NV cho từng dịch vụ thành phần. Bật «Bắt buộc chọn NV trên dịch vụ» nếu muốn bắt buộc',
      'Tạm dừng / chốt giờ trên sơ đồ ghế có sẵn khi cửa hàng bật tính tiền giờ',
      'Xem hoa hồng: Báo cáo POS → Hoa hồng nhân viên (theo NV, theo dịch vụ, xuất Excel)',
    ],
    tip:
        'Khách mua gói phải được chọn trên hóa đơn — không có khách thì không cộng buổi được.',
    accent: Color(0xFFAD1457),
  ),
  LandingUsageGuideStep(
    id: 'ind_commission',
    icon: Icons.volunteer_activism_rounded,
    title: 'Hoa hồng nhân viên: tính 1 lần hay mỗi buổi',
    desc:
        'Mỗi hàng hóa / dịch vụ / combo tự khai cách tính hoa hồng. Gói liệu trình chọn tính 1 lần khi bán hoặc tính cho người làm từng buổi.',
    bullets: [
      'Bật: Cài đặt → Ngành hàng & chế độ bán → Hoa hồng nhân viên',
      'Sản phẩm → mục «Hoa hồng nhân viên»: % trên doanh thu dòng / phần combo, Số tiền cố định / 1 lần, hoặc % trên giá niêm yết',
      '«1 lần khi bán»: hoa hồng ghi ngay khi thanh toán cho NV được chọn trên hóa đơn. Combo: tiền combo chia theo giá niêm yết từng thành phần, mỗi thành phần tính theo NV được chọn',
      '«Mỗi buổi làm»: lúc bán gói không cần chọn NV. Mỗi lần trừ buổi, NV làm buổi đó nhận hoa hồng; tiền 1 buổi = tiền bán gói (hoặc phần combo) ÷ số buổi',
      'Ví dụ: gói 10 buổi giá 3.000.000đ, hoa hồng 10% «Mỗi buổi làm» → mỗi buổi NV làm nhận 30.000đ',
      'Tiền cố định khi chọn «Mỗi buổi làm» là số tiền cho mỗi buổi',
      'Combo chọn «Mỗi buổi làm»: chỉ các liệu trình nhiều buổi tính theo buổi; hàng hóa và dịch vụ 1 lần trong combo vẫn tính lúc bán',
      'Báo cáo hoa hồng lọc theo ngày làm buổi (không theo ngày bán gói)',
    ],
    tip:
        'Thẻ tập theo tháng / năm (gym) không chia được theo buổi — hãy dùng «1 lần khi bán».',
    accent: Color(0xFF00838F),
  ),
  LandingUsageGuideStep(
    id: 'ind_gym',
    icon: Icons.fitness_center_rounded,
    title: 'Gym / Yoga / Fitness',
    desc:
        'Bán thẻ tập theo thời gian hoặc gói buổi, hội viên check-in bằng vân tay / khuôn mặt trên máy chấm công ZKTeco (tách riêng chấm công nhân viên).',
    bullets: [
      'Thẻ tháng / quý / năm: dịch vụ bật «Thẻ tập theo thời gian (không giới hạn buổi)» và nhập hạn dùng (30 / 90 / 365 ngày). Mua thêm tự gia hạn nối tiếp',
      'Gói buổi (vd 12 buổi PT): nhập Số buổi + hạn dùng; mỗi lần tập trừ 1 buổi',
      'Bán thẻ: chọn khách (hội viên) → thêm thẻ → thanh toán → khách được cộng thẻ / buổi',
      'Check-in hội viên: menu Check-in hội viên → tab «Hội viên trên máy» → đẩy hội viên lên máy chấm công (mã PIN riêng từ 90000001, không lẫn với nhân viên) → đăng ký vân tay / khuôn mặt',
      'Hội viên chấm máy: hệ thống tự kiểm tra thẻ còn hạn / còn buổi, ghi lượt tập và trừ buổi (thẻ thời gian chỉ ghi lượt)',
      'Check-in tại quầy: tìm hội viên và bấm Check-in khi khách quên thẻ / máy lỗi',
      'Tab «Lượt tập»: ai vào tập lúc nào; tab «Tổng hợp»: số lượt, thẻ / gói còn lại, ngày hết hạn để gọi gia hạn',
      'Máy chấm công dùng chung: lượt chấm của hội viên không vào bảng công nhân viên',
    ],
    tip:
        'Hội viên check-in bị từ chối: xem thông báo «cần kiểm tra» — thường do thẻ hết hạn hoặc hết buổi.',
    accent: Color(0xFFEF6C00),
  ),
  LandingUsageGuideStep(
    id: 'ind_hotel',
    icon: Icons.hotel_rounded,
    title: 'Khách sạn / Nhà nghỉ / Homestay',
    desc:
        'Sơ đồ phòng, nhận phòng – trả phòng, tính theo giờ hoặc theo đêm, folio cộng dồn dịch vụ (minibar, giặt ủi), khai báo khách lưu trú.',
    bullets: [
      'Dịch vụ tiền phòng: Cách tính «Theo ngày (khách sạn)» cho qua đêm, «Theo giờ» cho nghỉ giờ — mỗi hạng phòng một dịch vụ giá riêng',
      'Tính theo đêm: bật «Tính tiền phòng theo đêm», đặt Giờ nhận phòng / Giờ trả phòng và «Ân hạn (phút)» để trả trễ ít phút không tính thêm đêm. Tắt = tính theo khối 24 giờ kể từ lúc nhận',
      '«Ngày qua đêm (báo cáo / cuối ngày)»: ngày kinh doanh bắt đầu 12h trưa để doanh thu đêm không bị chia 2 ngày',
      'Nhận phòng: chạm phòng trống → nhập số khách → thêm tiền phòng; «Khách lưu trú (tạm trú)» để lưu thông tin giấy tờ khách',
      'Trong thời gian ở: thêm minibar, giặt ủi… vào folio; in tạm tính cho khách xem',
      'Đặt phòng trước: Lịch đặt phòng — giữ phòng, nhận cọc; hủy đặt có xử lý cọc',
      'Trả phòng: mở folio → kiểm tra số đêm / giờ tự tính → thanh toán → phòng về trống',
      'Chuyển phòng giữ nguyên folio và giờ nhận phòng',
    ],
    tip: 'Mỗi hạng phòng (đơn, đôi, VIP) nên là một dịch vụ riêng để báo cáo doanh thu theo hạng phòng.',
    accent: Color(0xFF4E342E),
  ),
  LandingUsageGuideStep(
    id: 'ind_docs_log',
    icon: Icons.fact_check_rounded,
    title: 'Mẫu hợp đồng / Word & Lịch sử thao tác',
    desc:
        'Dùng cho mọi ngành: in hợp đồng, phiếu dịch vụ từ file Word của bạn; tra lại ai đã bán, sửa, xóa gì trong 30 ngày.',
    bullets: [
      'Mẫu Word: Cài đặt → Mẫu in → «Tải file Word của bạn» (.docx; file PDF hãy mở bằng Word rồi Lưu thành .docx). Hệ thống giữ nguyên bố cục gốc và AI tự gợi ý chỗ gắn trường dữ liệu (tên khách, SĐT, ngày, tổng tiền, bảng hàng…)',
      'Các tab: «Mẫu gốc» (file bạn tải) · «Soạn mẫu» (bấm vào chữ để chèn / đổi / bỏ trường) · «Mẫu gắn trường» · «Bản in thử» (điền dữ liệu mẫu) — không cần sửa code',
      'In từ hóa đơn: chọn mẫu Word khi in; ảnh (logo, chữ ký) và bảng hàng tự điền',
      'Lịch sử thao tác: menu Lịch sử thao tác — lọc theo ngày, nhân viên, chức năng, loại thao tác (thêm / sửa / xóa), xem giá trị trước và sau, xuất Excel',
      'Lịch sử lưu 30 ngày, tách riêng từng cửa hàng',
    ],
    tip: 'Kết hợp Lịch sử thao tác với Lịch sử hủy / trả để đối chiếu khi lệch tiền cuối ca.',
    accent: Color(0xFF37474F),
  ),
];

/// Từ khóa tìm nhanh cho tab Ngành hàng.
const landingIndustryKeywords = <String, List<String>>{
  'ind_choose': ['ngành hàng', 'đổi ngành', 'chế độ bán', 'cấu hình ngành'],
  'ind_retail': ['bán lẻ', 'siêu thị', 'tạp hóa', 'mã vạch', 'cân điện tử', 'plu', 'tồn âm'],
  'ind_restaurant': ['nhà hàng', 'cafe', 'quán', 'trà sữa', 'bàn', 'gửi bếp', 'kds', 'qr order', 'topping'],
  'ind_room_hourly': [
    'karaoke', 'bi-a', 'bida', 'phòng giờ', 'tính giờ', 'block', 'gói giờ', 'đếm ngược',
    'quá giờ', 'chốt giờ', 'tạm dừng', 'playstation',
  ],
  'ind_salon': ['salon', 'spa', 'nail', 'barber', 'tóc', 'liệu trình', 'trừ buổi', 'lịch hẹn', 'ghế'],
  'ind_commission': ['hoa hồng', 'commission', 'nhân viên làm', 'mỗi buổi', 'tour', 'kỹ thuật viên'],
  'ind_gym': ['gym', 'yoga', 'fitness', 'thẻ tập', 'hội viên', 'check-in', 'pt', 'gói buổi'],
  'ind_hotel': ['khách sạn', 'nhà nghỉ', 'homestay', 'nhận phòng', 'trả phòng', 'theo đêm', 'folio', 'lưu trú'],
  'ind_docs_log': ['hợp đồng', 'mẫu word', 'docx', 'lịch sử thao tác', 'nhật ký', 'ai sửa', 'ai xóa'],
};
