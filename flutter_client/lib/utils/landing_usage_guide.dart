import 'dart:convert';

import 'package:flutter/material.dart';

import 'device_setup_guide.dart';

/// Một bước hướng dẫn trên landing (có metadata hiển thị + nội dung chỉnh từ CMS).
class LandingUsageGuideStep {
  const LandingUsageGuideStep({
    required this.id,
    required this.icon,
    required this.title,
    required this.desc,
    required this.bullets,
    required this.tip,
    required this.accent,
    this.imageUrls = const [],
    this.videoUrl = '',
  });

  final String id;
  final IconData icon;
  final String title;
  final String desc;
  final String tip;
  final List<String> bullets;
  final Color accent;
  final List<String> imageUrls;
  final String videoUrl;

  LandingUsageGuideStep copyWith({
    String? title,
    String? desc,
    String? tip,
    List<String>? bullets,
    List<String>? imageUrls,
    String? videoUrl,
  }) {
    return LandingUsageGuideStep(
      id: id,
      icon: icon,
      title: title ?? this.title,
      desc: desc ?? this.desc,
      tip: tip ?? this.tip,
      bullets: bullets ?? this.bullets,
      accent: accent,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrl: videoUrl ?? this.videoUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'desc': desc,
        if (tip.isNotEmpty) 'tip': tip,
        if (bullets.isNotEmpty) 'bullets': bullets,
        if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
        if (videoUrl.isNotEmpty) 'videoUrl': videoUrl,
      };

  static List<String> _parseImageUrls(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(RegExp(r'[\n,]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static LandingUsageGuideStep? fromJson(
    Map<String, dynamic> json,
    LandingUsageGuideStep fallback,
  ) {
    final id = json['id']?.toString() ?? fallback.id;
    if (id != fallback.id) return null;
    final title = json['title']?.toString().trim();
    final desc = json['desc']?.toString().trim();
    final tip = json['tip']?.toString().trim();
    final videoUrl = json['videoUrl']?.toString().trim();
    List<String>? bullets;
    final rawBullets = json['bullets'];
    if (rawBullets is List) {
      bullets = rawBullets
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final images = _parseImageUrls(json['imageUrls'] ?? json['imageUrl']);
    return fallback.copyWith(
      title: (title != null && title.isNotEmpty) ? title : null,
      desc: (desc != null && desc.isNotEmpty) ? desc : null,
      tip: tip != null ? tip : null,
      bullets: bullets,
      imageUrls: images.isNotEmpty ? images : null,
      videoUrl: videoUrl != null ? videoUrl : null,
    );
  }
}

/// Toàn bộ hướng dẫn landing: triển khai cơ bản + nâng cao.
class LandingGuideData {
  const LandingGuideData({
    required this.basic,
    required this.advanced,
  });

  final List<LandingUsageGuideStep> basic;
  final List<LandingUsageGuideStep> advanced;

  int get basicCount => basic.length;
  int get advancedCount => advanced.length;

  Map<String, dynamic> toJson() => {
        'basic': basic.map((e) => e.toJson()).toList(),
        'advanced': advanced.map((e) => e.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  static LandingGuideData get defaults => LandingGuideData(
        basic: LandingUsageGuide.basicSteps,
        advanced: LandingUsageGuide.advancedSteps,
      );

  static LandingGuideData fromApiJson(dynamic raw) {
    final base = defaults;
    if (raw == null) return base;
    try {
      dynamic decoded = raw;
      if (raw is String) {
        final t = raw.trim();
        if (t.isEmpty) return base;
        decoded = jsonDecode(t);
      }
      if (decoded is List) {
        return _mergeLegacyList(base, decoded);
      }
      if (decoded is Map) {
        return _mergeSections(base, decoded);
      }
    } catch (_) {}
    return base;
  }

  static LandingGuideData _mergeLegacyList(
    LandingGuideData base,
    List<dynamic> list,
  ) {
    final merged = <LandingUsageGuideStep>[];
    for (var i = 0; i < base.basic.length; i++) {
      var step = base.basic[i];
      if (i < list.length && list[i] is Map) {
        final parsed = LandingUsageGuideStep.fromJson(
          Map<String, dynamic>.from(list[i] as Map),
          step,
        );
        if (parsed != null) step = parsed;
      } else if (i < list.length) {
        final m = list[i];
        if (m is Map && m['title'] != null) {
          step = step.copyWith(
            title: m['title']?.toString() ?? step.title,
            desc: m['desc']?.toString() ?? step.desc,
          );
        }
      }
      merged.add(step);
    }
    return LandingGuideData(basic: merged, advanced: base.advanced);
  }

  static LandingGuideData _mergeSections(
    LandingGuideData base,
    Map<dynamic, dynamic> map,
  ) {
    return LandingGuideData(
      basic: _mergeStepList(base.basic, map['basic']),
      advanced: _mergeStepList(base.advanced, map['advanced']),
    );
  }

  static List<LandingUsageGuideStep> _mergeStepList(
    List<LandingUsageGuideStep> defaults,
    dynamic rawList,
  ) {
    if (rawList is! List) return defaults;
    final byId = <String, Map<String, dynamic>>{};
    for (final item in rawList) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = m['id']?.toString();
      if (id != null && id.isNotEmpty) byId[id] = m;
    }
    return defaults.map((step) {
      final override = byId[step.id];
      if (override == null) return step;
      return LandingUsageGuideStep.fromJson(override, step) ?? step;
    }).toList();
  }
}

class LandingUsageGuide {
  /// Triển khai: lộ trình người mới → vận hành HR/chấm công/lương cơ bản.
  static final basicSteps = <LandingUsageGuideStep>[
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
        'Ngày 3–4: Kết nối máy ZKTeco (hoặc bật chấm công Mobile) → đồng bộ NV → đăng ký vân tay/face',
        'Ngày 5: Tạo tài khoản app cho quản lý/NV cần đăng nhập; phân quyền theo vai trò',
        'Ngày 5–6: Cấu hình phạt đi trễ/về sớm (nếu dùng) → kiểm tra vài ngày chấm thử trên Chấm công thô',
        'Cuối tháng: Duyệt phép / phiếu thưởng–phạt–ứng → xem Tổng hợp theo ca → chốt Tổng hợp lương',
        'Hotline hỗ trợ: 0973 024 042 (Zalo hỗ trợ từ xa)',
      ],
      tip:
          'Chưa cần làm hết tính năng nâng cao (KPI, POS, tài sản…) trong tuần đầu — ưu tiên nhân sự → ca → chấm công → lương.',
      accent: Color(0xFF0C56D0),
    ),
    const LandingUsageGuideStep(
      id: 'register',
      icon: Icons.app_registration_rounded,
      title: 'Đăng ký phần mềm',
      desc:
          'Tạo cửa hàng trên sboxhrm.com để nhận mã cửa hàng và tài khoản quản trị. Mã cửa hàng dùng mỗi lần đăng nhập web hoặc app.',
      bullets: [
        'Mở sboxhrm.com → chọn Đăng ký / Đăng ký doanh nghiệp',
        'Điền: tên cửa hàng, mã đăng nhập cửa hàng, email, SĐT, mật khẩu admin',
        'Mã cửa hàng: viết thường a–z và 0–9, liền nhau, không dấu, tối đa 20 ký tự (vd: comganam)',
        'Chọn gói dịch vụ theo nhu cầu; hoàn tất để kích hoạt',
        'Lưu lại mã cửa hàng — gửi cho nhân viên khi họ đăng nhập app',
        'Đăng nhập: nhập Mã cửa hàng + Email/Tên đăng nhập + Mật khẩu',
        'Quên mật khẩu: dùng chức năng quên mật khẩu trên màn đăng nhập (cần email thật)',
      ],
      tip:
          'Dùng email và SĐT thật để nhận hỗ trợ kích hoạt và khôi phục tài khoản nhanh.',
      accent: Color(0xFF0C56D0),
    ),
    const LandingUsageGuideStep(
      id: 'org_structure',
      icon: Icons.account_tree_rounded,
      title: 'Phòng ban, chức vụ & chi nhánh',
      desc:
          'Tổ chức cơ cấu trước khi thêm nhân viên giúp phân ca, phân quyền và báo cáo theo bộ phận chính xác.',
      bullets: [
        'Cài đặt → Phòng ban: tạo các bộ phận (Kế toán, Bếp, Thu ngân…)',
        'Cài đặt → Chức vụ: tạo chức danh (Quản lý, Nhân viên, Thu ngân…)',
        'Nếu có nhiều điểm bán: Cài đặt → Chi nhánh / cửa hàng con (khi gói hỗ trợ)',
        'Gán phòng ban & chức vụ ngay khi thêm nhân viên',
        'Báo cáo và lọc danh sách NV theo phòng ban sau này sẽ dựa trên gán này',
      ],
      tip:
          'Tạo phòng ban trước, rồi mới import Excel nhân viên — tránh phải sửa hàng loạt sau.',
      accent: Color(0xFF455A64),
    ),
    const LandingUsageGuideStep(
      id: 'employees',
      icon: Icons.group_add_rounded,
      title: 'Thêm nhân viên',
      desc:
          'Tạo hồ sơ nhân sự làm nền cho chấm công, lương và tài khoản app. Mã nhân viên phải thống nhất giữa hồ sơ và máy chấm công.',
      bullets: [
        'Menu: Hồ sơ nhân sự → Thêm nhân viên',
        'Bắt buộc: họ tên, mã nhân viên (PIN), phòng ban / chức vụ',
        'Nên có: SĐT, ngày vào làm, trạng thái đang làm việc',
        'Import Excel: tải mẫu trong màn hình → điền → tải lên (thêm hàng loạt)',
        'Kiểm tra trùng mã nhân viên trước khi đồng bộ xuống máy',
        'NV nghỉ việc: cập nhật trạng thái / nghỉ việc — không xóa nếu đã có dữ liệu chấm công',
        'Bước sau: gán Thiết lập lương và phân ca trên Lịch làm việc',
      ],
      tip:
          'Mã nhân viên trên máy ZKTeco phải trùng mã trong hồ sơ thì log chấm công mới khớp tên.',
      accent: Color(0xFF00897B),
    ),
    const LandingUsageGuideStep(
      id: 'shifts',
      icon: Icons.schedule_rounded,
      title: 'Cấu hình ca làm việc',
      desc:
          'Định nghĩa khung giờ làm (ca sáng, ca đêm, ca OT…). Ca quyết định tính đi trễ, về sớm, công và tăng ca.',
      bullets: [
        'Cài đặt → Thiết lập ca → Thêm ca',
        'Nhập tên ca, giờ bắt đầu / kết thúc (hỗ trợ ca qua đêm, vd 21:30–06:00)',
        'Cấu hình: phút ân hạn đi trễ, ân hạn về sớm, ngưỡng tính tăng ca',
        'Phân biệt ca hành chính và ca Tăng ca (OT) nếu cửa hàng dùng',
        'Gán ca vào mẫu lương / nhân viên tại Thiết lập lương (ô Ca làm việc)',
        'Phân lịch cụ thể theo ngày tại menu Lịch làm việc',
        'Trong màn Thiết lập ca có nút hướng dẫn chi tiết OT / grace — mở khi cần',
      ],
      tip:
          'Dùng «Nhân bản ca» để clone ca tương tự. ân hạn đi trễ (vd 10 phút) tránh phạt oan khi vào sớm vài phút sau giờ.',
      accent: Color(0xFF6A1B9A),
    ),
    const LandingUsageGuideStep(
      id: 'salary',
      icon: Icons.payments_rounded,
      title: 'Thiết lập lương & kiểu chấm công',
      desc:
          'Gán mức lương, phụ cấp và cách tính công cho từng nhân viên. Kiểu chấm công quyết định cần chấm vào/ra hay chỉ một lần/ca.',
      bullets: [
        'Hồ sơ nhân sự → chọn NV → Thiết lập lương (hoặc màn Thiết lập lương)',
        'Chọn loại lương: theo tháng / theo ngày / theo giờ / sản phẩm (nếu dùng)',
        'Nhập lương cơ bản, phụ cấp cố định; gán ca làm việc áp dụng',
        'Chọn «Chấm công»: Chấm vào & ra · Chỉ chấm vào (đủ ca) · Chỉ chấm ra · 2 lần bất kỳ trong ngày · Ca nguyên ngày…',
        'Chỉ chấm vào: mỗi lần chấm = đủ ca, tính đi trễ theo giờ bắt đầu, giờ ra = hết ca',
        'Công chuẩn tháng / ngày nghỉ có lương: cấu hình trong cùng form (theo lịch phân ca hoặc cố định)',
        'Cài đặt thêm: Phụ cấp, Bảo hiểm, Thuế TNCN, Phạt (menu Cài đặt)',
        'Cuối kỳ: menu Tính lương / Tổng hợp lương để xem bảng lương',
      ],
      tip:
          'Cửa hàng chỉ chấm 1 lần/ngày trên máy: chọn «Chấm vào (đủ ca…)». Chi tiết các mode xem tab Nâng cao → Kiểu chấm công.',
      accent: Color(0xFF1565C0),
    ),
    const LandingUsageGuideStep(
      id: 'work_schedule_basic',
      icon: Icons.calendar_view_week_rounded,
      title: 'Phân lịch làm việc lần đầu',
      desc:
          'Gán ca theo từng ngày cho nhân viên để hệ thống biết ngày nào phải đi làm, nghỉ và tính công đúng.',
      bullets: [
        'Menu: Lịch làm việc',
        'Chọn tuần/tháng → chọn nhân viên hoặc phòng ban',
        'Gán ca theo ngày; dùng sao chép tuần / nhân bản lịch nếu làm việc cố định',
        'Đánh dấu ngày nghỉ / ngày off theo quy định cửa hàng',
        'Nếu bật duyệt lịch: NV đăng ký → quản lý duyệt tại Duyệt lịch làm việc',
        'Nên phân ca trước đầu kỳ lương — tránh sửa lịch khi đã chốt công',
      ],
      tip:
          'Lịch trống + máy có log vẫn có thể khớp ca từ Thiết lập lương, nhưng phân lịch rõ ràng giúp báo cáo và phép chính xác hơn.',
      accent: Color(0xFF7B1FA2),
    ),
    LandingUsageGuideStep(
      id: 'device_connect',
      icon: Icons.router_rounded,
      title: 'Kết nối máy chấm công ZKTeco',
      desc:
          'Cấu hình hai phía: máy trỏ về máy chủ ADMS cloud; phần mềm khai báo serial để nhận log real-time.',
      bullets: [
        'Trên máy ZKTeco: ${DeviceSetupGuide.menuPath}',
        'Địa chỉ máy chủ: ${DeviceSetupGuide.serverHost} · Port: ${DeviceSetupGuide.serverPort}',
        'Bật Cloud / ADMS theo hướng dẫn trên máy; lưu và khởi động lại nếu máy yêu cầu',
        'Trên SBOX: Cài đặt → Máy chấm công → Thêm máy (nhập SN hoặc quét mã)',
        'Theo dõi trạng thái Online / Offline trên danh sách máy',
        'Máy online sẽ tự đẩy ATTLOG; kiểm tra tại Chấm công thô',
        'Firewall/mạng cửa hàng phải cho máy ra internet (HTTPS/ADMS)',
      ],
      tip:
          'Chưa kết nối được? Gọi hotline 0973 024 042 — hỗ trợ từ xa qua Zalo.',
      accent: const Color(0xFF0277BD),
    ),
    const LandingUsageGuideStep(
      id: 'device_users',
      icon: Icons.fingerprint_rounded,
      title: 'Đồng bộ NV & đăng ký vân tay / face',
      desc:
          'Đưa danh sách nhân viên xuống máy rồi đăng ký sinh trắc học. Chỉ khi mã NV khớp, log mới gắn đúng người.',
      bullets: [
        'Menu: Nhân sự chấm công',
        'Chọn máy → Đồng bộ / đẩy nhân viên từ Hồ sơ nhân sự xuống thiết bị',
        'Trên máy: đăng ký vân tay hoặc khuôn mặt cho từng mã NV',
        'Cho NV chấm thử → mở Chấm công thô xác nhận có giờ vào/ra và đúng tên',
        'Thêm NV mới giữa kỳ: thêm hồ sơ → đồng bộ lại máy → đăng ký vân tay',
        'Xóa/khóa user trên máy khi NV nghỉ (tránh chấm nhầm)',
      ],
      tip:
          'Nếu log hiện PIN lạ: kiểm tra mã trên máy và mã trong hồ sơ có trùng không.',
      accent: Color(0xFF2E7D32),
    ),
    const LandingUsageGuideStep(
      id: 'mobile_attendance',
      icon: Icons.phone_android_rounded,
      title: 'Chấm công Mobile & duyệt',
      desc:
          'Cho phép chấm bằng điện thoại (GPS, WiFi cửa hàng, khuôn mặt). Phù hợp khi không có máy ZK hoặc nhân viên ngoài hiện trường.',
      bullets: [
        'Cài đặt → Chấm công mobile: bật GPS / WiFi / Face theo nhu cầu',
        'Thiết lập vùng chấm (tọa độ cửa hàng) hoặc SSID WiFi hợp lệ',
        'Menu Đăng ký chấm công Mobile: NV đăng ký thiết bị; quản lý duyệt thiết bị',
        'NV mở app → Chấm công Mobile để vào/ra',
        'Quản lý duyệt log tại Duyệt chấm công (nếu bật quy trình duyệt)',
        'Có thể dùng song song máy ZK + mobile cho cùng cửa hàng',
      ],
      tip:
          'Bật WiFi hoặc GPS cửa hàng để hạn chế chấm ngoài vùng. Xem thêm Nâng cao → Bản đồ / chấm ngoài hiện trường.',
      accent: Color(0xFF00838F),
    ),
    const LandingUsageGuideStep(
      id: 'employee_account',
      icon: Icons.manage_accounts_rounded,
      title: 'Tạo tài khoản & phân quyền',
      desc:
          'Cấp đăng nhập app/web cho quản lý và nhân viên; gán vai trò để mỗi người chỉ thấy đúng chức năng.',
      bullets: [
        'Cài đặt → Tài khoản → Thêm tài khoản',
        'Liên kết tài khoản với hồ sơ nhân sự tương ứng',
        'Cài đặt → Phân quyền: gán vai trò (Admin cửa hàng, Kế toán, NV…)',
        'NV đăng nhập: mã cửa hàng + tài khoản được cấp',
        'Không dùng chung một mật khẩu cho cả cửa hàng',
        'Thu hồi / khóa tài khoản khi NV nghỉ việc',
      ],
      tip:
          'Admin cửa hàng giữ quyền đầy đủ; kế toán cần xem lương/báo cáo; NV thường chỉ cần chấm công, phép, phiếu lương.',
      accent: Color(0xFF1565C0),
    ),
    const LandingUsageGuideStep(
      id: 'penalty_ticket',
      icon: Icons.receipt_long_rounded,
      title: 'Phiếu phạt đi trễ / về sớm',
      desc:
          'Hệ thống có thể tự tạo phiếu phạt từ chấm công theo quy tắc đã cấu hình, hoặc tạo thủ công. Phiếu dùng để theo dõi và thu phạt.',
      bullets: [
        'Cài đặt → Phạt: bậc phút đi trễ / về sớm và số tiền từng bậc; phạt tái phạm',
        'Khi NV chấm trễ vượt ân hạn ca: hệ thống tạo Phiếu phạt (Loại đi trễ)',
        'Mode chỉ chấm vào: vẫn phạt trễ; không phạt «quên chấm ra»',
        'Tài chính → Phiếu phạt: xem, duyệt, hủy, từ chối',
        'Thu tiền phạt thực tế: Tài chính → Thu chi (liên kết phiếu)',
        'Bảng lương có thể trừ theo phút trễ đã tổng hợp (tùy cấu hình kỳ)',
        'Báo cáo → Báo cáo phạt',
      ],
      tip:
          'Thiết lập mức phạt và ân hạn ca trước ngày vận hành thật — tránh sửa quy tắc giữa kỳ.',
      accent: Color(0xFFE65100),
    ),
    const LandingUsageGuideStep(
      id: 'advance',
      icon: Icons.savings_rounded,
      title: 'Ứng lương',
      desc:
          'Ghi nhận và duyệt tạm ứng; theo dõi còn nợ và trừ khi tính lương hoặc thu qua quỹ.',
      bullets: [
        'Tài chính → Ứng lương → tạo phiếu (hoặc NV gửi từ app)',
        'Duyệt phiếu trước khi chi tiền',
        'Chi ứng qua Thu chi (liên kết phiếu) để cập nhật trạng thái',
        'Theo dõi đã ứng / còn nợ trên danh sách phiếu',
        'Báo cáo → Báo cáo ứng lương',
        'Phiếu hủy hoặc từ chối không tính vào báo cáo',
      ],
      tip: 'Chi ứng đúng ngày thực tế giúp đối soát quỹ và bảng lương khớp nhau.',
      accent: Color(0xFFAD1457),
    ),
    const LandingUsageGuideStep(
      id: 'bonus_ticket',
      icon: Icons.card_giftcard_rounded,
      title: 'Phiếu thưởng',
      desc:
          'Ghi nhận thưởng nóng, thưởng định kỳ hoặc thưởng theo thành tích để cộng vào bảng lương kỳ tương ứng.',
      bullets: [
        'Tài chính → Phiếu thưởng → Tạo phiếu',
        'Chọn nhân viên, số tiền, kỳ áp dụng, lý do',
        'Duyệt phiếu trước khi chốt Tổng hợp lương',
        'Kiểm tra dòng thưởng trên bảng lương / phiếu lương NV',
        'Có thể kết hợp với module KPI (tab Nâng cao)',
      ],
      tip: 'Tạo và duyệt thưởng trước ngày chốt bảng lương tháng.',
      accent: Color(0xFF7B1FA2),
    ),
    const LandingUsageGuideStep(
      id: 'cash',
      icon: Icons.account_balance_wallet_rounded,
      title: 'Thu chi quỹ',
      desc:
          'Sổ quỹ tiền mặt: ghi thu/chi hàng ngày, liên kết ứng lương và thu phạt để đối soát.',
      bullets: [
        'Tài chính → Thu chi → ghi Thu hoặc Chi',
        'Chọn ngày, số tiền, danh mục, diễn giải',
        'Khi chi ứng lương: chọn liên kết phiếu ứng',
        'Khi thu phạt: chọn liên kết phiếu phạt',
        'Xem tồn quỹ theo ngày; đối soát cuối ngày/tháng',
        'Báo cáo → Báo cáo thu chi',
      ],
      tip: 'Ghi đúng ngày phát sinh — không dồn nhiều ngày vào một phiếu nếu cần đối soát chi tiết.',
      accent: Color(0xFF558B2F),
    ),
    const LandingUsageGuideStep(
      id: 'first_payroll',
      icon: Icons.fact_check_rounded,
      title: 'Chốt công & bảng lương tháng đầu',
      desc:
          'Quy trình cuối kỳ để kiểm tra chấm công rồi chốt lương lần đầu — giảm sai sót khi mới triển khai.',
      bullets: [
        '1) Kiểm tra Chấm công thô: đủ log, đúng NV, không trùng bất thường',
        '2) Mở Tổng hợp theo ca / Tổng hợp chấm công: kiểm tra công, phút trễ/sớm, thiếu chấm',
        '3) Duyệt xong nghỉ phép, đổi ca, phiếu thưởng / phạt / ứng trong kỳ',
        '4) Vào Tính lương / Tổng hợp lương → chọn kỳ → tải lại dữ liệu',
        '5) Rà từng NV: công, phụ cấp, BHXH, thuế, ứng, thưởng, phạt',
        '6) Xuất Excel / in phiếu lương; gửi NV kiểm tra trên app',
        '7) Chỉ chỉnh sửa lịch/ca trước khi chốt — sau chốt nên khóa kỳ nếu có',
      ],
      tip:
          'Tháng đầu nên chấm thử 3–5 ngày rồi xem Tổng hợp theo ca trước khi tin tưởng tự động hoàn toàn.',
      accent: Color(0xFFC62828),
    ),
    const LandingUsageGuideStep(
      id: 'reports',
      icon: Icons.assessment_rounded,
      title: 'Các báo cáo thường dùng',
      desc:
          'Menu Báo cáo giúp đối soát vận hành hàng ngày và cuối tháng. Phiếu hủy/từ chối thường không tính vào số liệu.',
      bullets: [
        'Tổng hợp chấm công · Tổng hợp theo ca — công, trễ, sớm theo ngày',
        'Tính lương / Tổng hợp lương — bảng lương kỳ',
        'Báo cáo phạt · Ứng lương · Thu chi',
        'Báo cáo nghỉ phép · Tài sản (nếu dùng)',
        'Bộ lọc theo phòng ban, khoảng ngày, nhân viên',
        'Xuất Excel khi cần gửi kế toán ngoài hệ thống',
      ],
      tip:
          'Khi số liệu lệch: kiểm tra lại kiểu chấm công + lịch ca + ân hạn trước khi sửa tay từng dòng.',
      accent: Color(0xFF1976D2),
    ),
  ];

  /// Nâng cao: chính sách chuyên sâu, vận hành, hiện trường, POS.
  static const advancedSteps = <LandingUsageGuideStep>[
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
        'Cấu hình tại: Thiết lập lương → ô Chấm công',
        'Sau khi đổi mode: mở lại Tổng hợp theo ca để xem công/trễ cập nhật',
      ],
      tip:
          'Quán/cửa hàng chỉ chấm 1 lần trên máy (toàn bộ log là CheckIn): chọn «Chấm vào (đủ ca…)».',
      accent: Color(0xFF0C56D0),
    ),
    LandingUsageGuideStep(
      id: 'work_schedule',
      icon: Icons.calendar_month_rounded,
      title: 'Lịch làm việc nâng cao',
      desc:
          'Quản lý phân ca theo tuần/tháng, đăng ký lịch và quy trình duyệt khi cửa hàng có nhiều ca xoay.',
      bullets: [
        'Menu: Lịch làm việc — xem lưới theo NV hoặc theo ngày',
        'Sao chép lịch tuần trước / nhân bản cho cả phòng ban',
        'NV đăng ký lịch (nếu bật) → quản lý duyệt tại Duyệt lịch làm việc',
        'Điều chỉnh ca giữa kỳ khi đổi lịch thực tế (trước khi chốt lương)',
        'Kết hợp Ngày nghỉ có lương «Theo lịch phân ca» trong thiết lập lương',
      ],
      tip: 'Phân ca trước đầu kỳ; hạn chế sửa lịch sau khi đã có nhiều phiếu phạt tự động.',
      accent: Color(0xFF6A1B9A),
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
    ),
    LandingUsageGuideStep(
      id: 'holidays',
      icon: Icons.celebration_rounded,
      title: 'Ngày lễ & ngày nghỉ đặc biệt',
      desc:
          'Khai báo ngày lễ để tính công/OT ngày lễ và loại trừ khỏi ngày công chuẩn khi cấu hình tương ứng.',
      bullets: [
        'Cài đặt → Ngày lễ (hoặc mục lịch nghỉ lễ trên hệ thống)',
        'Thêm ngày lễ cố định / lễ phát sinh trong năm',
        'Kiểm tra hệ số OT ngày lễ trong thiết lập lương / chính sách OT',
        'Đối chiếu Tổng hợp theo ca vào các ngày lễ đã làm việc',
      ],
      tip: 'Cập nhật lịch lễ đầu năm hoặc trước tháng có nghỉ dài để bảng lương không lệch.',
      accent: Color(0xFFD84315),
    ),
    LandingUsageGuideStep(
      id: 'leave',
      icon: Icons.event_busy_rounded,
      title: 'Nghỉ phép',
      desc:
          'Nhân viên tạo đơn nghỉ; quản lý duyệt. Phép được trừ quỹ phép và phản ánh vào công tùy loại phép.',
      bullets: [
        'Menu: Nghỉ phép → tạo đơn (loại phép, từ ngày–đến ngày, lý do)',
        'NV tạo trên app; quản lý duyệt / từ chối / hủy',
        'Theo dõi số ngày phép còn lại (nếu cấu hình quỹ phép)',
        'Phép đã duyệt thường không bị tính nghỉ không phép',
        'Báo cáo → Báo cáo nghỉ phép',
        'Mở hướng dẫn pháp lý/nghiệp vụ trên màn Nghỉ phép khi cần',
      ],
      tip: 'Phiếu từ chối hoặc hủy không tính vào báo cáo nghỉ phép.',
      accent: Color(0xFF0284C7),
    ),
    LandingUsageGuideStep(
      id: 'insurance_tax',
      icon: Icons.health_and_safety_rounded,
      title: 'Bảo hiểm & thuế TNCN',
      desc:
          'Cấu hình tham gia BHXH/BHYT/BHTN và thuế thu nhập cá nhân để bảng lương trừ đúng phần bắt buộc.',
      bullets: [
        'Cài đặt → Bảo hiểm: mức đóng, tỷ lệ công ty / người lao động',
        'Cài đặt → Thuế TNCN: biểu thuế / giảm trừ (theo cấu hình cửa hàng)',
        'Trên Thiết lập lương từng NV: bật/tắt tham gia BH, phụ thuộc giảm trừ',
        'Kiểm tra cột BH và thuế trên Tổng hợp lương sau khi cấu hình',
      ],
      tip: 'Đối chiếu với kế toán cửa hàng trước kỳ lương đầu tiên có trừ BH/thuế.',
      accent: Color(0xFF00695C),
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
        'Dùng kết quả để tạo Phiếu thưởng hoặc đánh giá',
      ],
      tip: 'Gắn KPI rõ ràng với phiếu thưởng để tránh thưởng tay trùng với KPI.',
      accent: Color(0xFF059669),
    ),
    LandingUsageGuideStep(
      id: 'bonus',
      icon: Icons.emoji_events_rounded,
      title: 'Thưởng (chính sách)',
      desc:
          'Quản lý các loại thưởng định kỳ, thưởng nóng và thưởng theo KPI — luôn duyệt trước khi chốt lương.',
      bullets: [
        'Tài chính → Phiếu thưởng',
        'Phân loại thưởng rõ ràng (nóng / tháng / KPI) trong lý do phiếu',
        'Duyệt trước khi chạy Tổng hợp lương',
        'Đối chiếu trên phiếu lương nhân viên',
      ],
      tip: 'Thưởng đã duyệt mới được cộng vào phiếu lương.',
      accent: Color(0xFF7B1FA2),
    ),
    LandingUsageGuideStep(
      id: 'penalty',
      icon: Icons.gavel_rounded,
      title: 'Chính sách phạt',
      desc:
          'Quy tắc phạt đi trễ, về sớm, quên chấm, nghỉ không phép — kết hợp ân hạn ca và bậc tiền phạt.',
      bullets: [
        'Cài đặt → Phạt: các bậc phút và số tiền; phạt quên chấm / nghỉ không phép',
        'Ân hạn phút nằm trên từng ca (Thiết lập ca), không chỉ ở màn Phạt',
        'Phiếu tự động sinh khi có log vi phạm (xem Tài chính → Phiếu phạt)',
        'Mode chỉ chấm vào/ra: hệ thống bỏ ForgotCheck một phía — tránh phạt oan',
        'Thu phạt qua Thu chi; theo dõi Báo cáo phạt',
      ],
      tip: 'Nhầm lẫn hay gặp: quên cấu hình ân hạn ca → phạt dù vào trễ 2–3 phút.',
      accent: Color(0xFFE65100),
    ),
    LandingUsageGuideStep(
      id: 'production',
      icon: Icons.precision_manufacturing_rounded,
      title: 'Sản lượng / lương sản phẩm',
      desc:
          'Nhập sản lượng theo sản phẩm, ca hoặc nhân viên để tính lương khoán.',
      bullets: [
        'Cài đặt → Lương sản phẩm: nhóm SP, đơn giá, bậc thang',
        'Menu: Sản lượng → nhập theo ngày/ca/NV',
        'Tổng hợp lương tự cộng phần lương sản phẩm',
        'Đối soát sản lượng trước khi chốt kỳ',
      ],
      tip: 'Khai báo đơn giá trước khi nhập sản lượng hàng loạt.',
      accent: Color(0xFF059669),
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
      accent: Color(0xFF334155),
    ),
    LandingUsageGuideStep(
      id: 'field_checkin',
      icon: Icons.map_rounded,
      title: 'Bản đồ nhân sự / chấm ngoài hiện trường',
      desc:
          'Theo dõi vị trí chấm công hoặc điểm check-in khi nhân viên làm việc ngoài cửa hàng (giao hàng, công trình, sale).',
      bullets: [
        'Menu: Bản đồ nhân sự / Field check-in (tùy tên trên menu cửa hàng)',
        'Cấu hình địa điểm hợp lệ hoặc cho phép chấm ngoài (theo quyền)',
        'NV chấm trên app kèm GPS; quản lý xem vị trí trên bản đồ',
        'Kết hợp Duyệt chấm công khi cần xác nhận log ngoài vùng',
      ],
      tip: 'Bật giới hạn GPS/WiFi ở Cài đặt chấm công mobile trước khi mở chấm ngoài rộng.',
      accent: Color(0xFF0277BD),
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
    ),
    LandingUsageGuideStep(
      id: 'meal',
      icon: Icons.restaurant_rounded,
      title: 'Chấm cơm',
      desc:
          'Ghi nhận suất ăn theo ca/ngày phục vụ kiểm soát chi phí ăn ca.',
      bullets: [
        'Menu: Chấm cơm',
        'Cấu hình suất / ca nếu cửa hàng dùng nhiều khung giờ ăn',
        'NV hoặc quản lý ghi nhận suất; quét QR nếu được bật',
        'Đối soát cuối tháng với số ngày công / báo cáo nhân sự',
      ],
      tip: 'Liên kết khung giờ ăn với ca làm việc để giảm ghi nhận trùng.',
      accent: Color(0xFFF97316),
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
        'Gửi push thông báo tới app khi cần đọc ngay',
        'NV xem tại Tổng quan hoặc mục Truyền thông',
      ],
      tip: 'Thông báo đổi ca, chính sách phạt, lịch lễ qua Truyền thông để có dấu vết.',
      accent: Color(0xFF059669),
    ),
    LandingUsageGuideStep(
      id: 'feedback',
      icon: Icons.feedback_rounded,
      title: 'Góp ý / Khiếu nại',
      desc:
          'Kênh phản ánh ẩn danh hoặc công khai; quản lý trả lời và đóng phiếu.',
      bullets: [
        'Menu: Phản ánh / Ý kiến',
        'NV gửi từ app (ẩn danh hoặc có tên)',
        'Quản lý phân loại, trả lời, đóng phiếu',
        'Theo dõi chờ xử lý / đã xử lý',
      ],
      tip: 'Bật góp ý ẩn danh nếu muốn nhận phản hồi trung thực hơn.',
      accent: Color(0xFF0C56D0),
    ),
    LandingUsageGuideStep(
      id: 'notifications',
      icon: Icons.notifications_active_rounded,
      title: 'Thông báo & nhắc việc',
      desc:
          'Cấu hình thông báo đẩy và kênh nhắc (duyệt đơn, chấm công, truyền thông) để quản lý không bỏ sót.',
      bullets: [
        'Cài đặt → Thiết lập thông báo (nếu có trên hub Cài đặt)',
        'NV bật thông báo trên điện thoại cho app SBOX',
        'Theo dõi chuông thông báo trên web/app: duyệt phép, đổi ca, phiếu chờ',
        'Dùng Truyền thông khi cần broadcast toàn cửa hàng',
      ],
      tip: 'Trên iOS/Android: cho phép thông báo app ngay sau khi cài để nhận duyệt đơn kịp thời.',
      accent: Color(0xFF6D4C41),
    ),
    LandingUsageGuideStep(
      id: 'pos_setup',
      icon: Icons.storefront_rounded,
      title: 'POS — Thiết lập bán hàng',
      desc:
          'Bật và cấu hình phân hệ bán hàng: ngành hàng, cửa hàng/kho, máy in, bàn phòng (F&B) trước khi bán.',
      bullets: [
        'Cài đặt (hub) → mục POS: Ngành hàng, Cửa hàng, Máy in, Mẫu in',
        'F&B: thiết lập Khu vực / Bàn phòng trước khi mở order',
        'Tạo danh mục và sản phẩm tại Hàng hóa (mã, giá, đơn vị)',
        'Phân quyền tài khoản thu ngân / quản lý kho',
        'In thử hóa đơn / tem tạm trên máy in đã gắn',
      ],
      tip: 'Chọn đúng ngành hàng (retail / F&B…) để hiện đúng luồng bàn và bếp.',
      accent: Color(0xFFEF6C00),
    ),
    LandingUsageGuideStep(
      id: 'pos_sales',
      icon: Icons.point_of_sale_rounded,
      title: 'POS — Bán hàng & đơn hàng',
      desc:
          'Tạo đơn bán, thanh toán, trả hàng và theo dõi đơn trong ngày trên màn POS.',
      bullets: [
        'Menu: Bán hàng / POS Sell — chọn món/sản phẩm, số lượng, giảm giá',
        'F&B: chọn bàn → order → gửi bếp (nếu bật) → thanh toán',
        'Thanh toán: tiền mặt / chuyển khoản / kết hợp; in hóa đơn',
        'Đơn hàng: tra cứu, in lại, hủy/trả theo quyền',
        'Trả hàng: tạo phiếu trả liên kết đơn gốc',
        'Báo cáo POS: doanh thu theo ngày, thu ngân, mặt hàng',
      ],
      tip: 'Cuối ca: đối soát doanh thu POS với Thu chi / tiền mặt ngăn kéo.',
      accent: Color(0xFFE65100),
    ),
    LandingUsageGuideStep(
      id: 'pos_inventory',
      icon: Icons.warehouse_rounded,
      title: 'POS — Kho & nhập xuất',
      desc:
          'Quản lý tồn kho: nhập nhà cung cấp, trả NCC, kiểm kho, xuất hủy, xuất nội bộ.',
      bullets: [
        'Nhập hàng NCC: tạo phiếu nhập → duyệt/hoàn thành để tăng tồn',
        'Trả hàng NCC khi hàng lỗi / thừa',
        'Kiểm kho: tạo phiên đếm → cân bằng lệch',
        'Xuất hủy / xuất nội bộ theo quy trình cửa hàng',
        'Theo dõi tồn trên Hàng hóa; bật cảnh báo tồn tối thiểu nếu có',
        'Công nợ NCC / khách (nếu module được bật)',
      ],
      tip: 'Nhập hàng trước khi bán combo/F&B có trừ nguyên liệu — tránh tồn âm.',
      accent: Color(0xFF5D4037),
    ),
  ];

  @Deprecated('Use LandingGuideData.defaults.basic')
  static List<LandingUsageGuideStep> get steps => basicSteps;

  @Deprecated('Use LandingGuideData.defaults.basicCount')
  static int get stepCount => basicSteps.length;
}
