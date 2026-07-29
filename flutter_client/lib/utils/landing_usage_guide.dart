import 'dart:convert';
import '../design_system/design_system.dart';

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
  static final basicSteps = <LandingUsageGuideStep>[
    const LandingUsageGuideStep(
      id: 'register',
      icon: Icons.app_registration_rounded,
      title: 'Đăng ký phần mềm',
      desc:
          'Truy cập sboxhrm.com, chọn Đăng ký doanh nghiệp. Điền tên cửa hàng, mã đăng nhập (chỉ chữ và số liền, không dấu), email, số điện thoại và mật khẩu. Chọn gói dịch vụ để kích hoạt tài khoản quản trị.',
      bullets: [
        'Đường dẫn: sboxhrm.com → Đăng ký',
        'Mã đăng nhập cửa hàng: tối đa 20 ký tự, viết thường a–z và 0–9',
        'Nhận mã cửa hàng (Store ID) sau khi đăng ký thành công',
        'Đăng nhập web/app bằng mã cửa hàng + tài khoản admin',
      ],
      tip: 'Dùng email và số điện thoại thật để nhận hỗ trợ kích hoạt nhanh.',
      accent: AppColors.primary,
    ),
    const LandingUsageGuideStep(
      id: 'employees',
      icon: Icons.group_add_rounded,
      title: 'Thêm nhân viên',
      desc:
          'Vào Hồ sơ nhân sự để tạo danh sách nhân viên: thêm từng người hoặc import Excel. Gán phòng ban, chức vụ, mã nhân viên trước khi phân ca và đồng bộ máy chấm công.',
      bullets: [
        'Menu: Hồ sơ nhân sự',
        'Thêm thủ công hoặc import Excel (tải mẫu trong màn hình)',
        'Gán phòng ban, chức vụ, mã nhân viên',
        'Cập nhật lương cơ bản tại Thiết lập lương (bước sau)',
      ],
      tip: 'Import Excel giúp thêm hàng loạt nhân viên nhanh hơn nhập tay.',
      accent: Color(0xFF00897B),
    ),
    const LandingUsageGuideStep(
      id: 'shifts',
      icon: Icons.schedule_rounded,
      title: 'Cấu hình ca',
      desc:
          'Tạo ca làm việc tại Cài đặt → Thiết lập ca. Sau đó vào Lịch làm việc để phân ca cho từng nhân viên hoặc cả phòng ban.',
      bullets: [
        'Cài đặt → Thiết lập ca: tạo ca sáng/chiều/đêm, ca xoay',
        'Menu Lịch làm việc: phân ca theo ngày/tuần/tháng',
        'Hỗ trợ ca qua đêm và lịch xoay tuần',
        'Duyệt lịch tại Duyệt lịch làm việc (nếu bật quy trình duyệt)',
      ],
      tip: 'Dùng "Nhân bản ca" để tạo nhanh ca tương tự mà không nhập lại.',
      accent: Color(0xFF6A1B9A),
    ),
    const LandingUsageGuideStep(
      id: 'salary',
      icon: Icons.payments_rounded,
      title: 'Thiết lập lương',
      desc:
          'Cấu hình lương cho từng nhân viên và chính sách tính lương: phụ cấp, phạt, bảo hiểm, thuế TNCN. Cuối kỳ xem Tổng hợp lương và Phiếu lương.',
      bullets: [
        'Hồ sơ nhân sự → Thiết lập lương: lương cơ bản từng NV',
        'Cài đặt → Phụ cấp, Phạt, Bảo hiểm, Thuế TNCN',
        'Báo cáo → Tổng hợp lương: bảng lương theo kỳ',
        'Nhân viên xem Phiếu lương trên app',
      ],
      tip: 'Thiết lập chính sách phạt đi trễ/về sớm trước khi vận hành chấm công.',
      accent: Color(0xFF1565C0),
    ),
    LandingUsageGuideStep(
      id: 'device_connect',
      icon: Icons.router_rounded,
      title: 'Kết nối máy chấm công',
      desc:
          'Cấu hình hai phía: trên máy ZKTeco nhập máy chủ ADMS cloud; trên phần mềm thêm serial máy và theo dõi trạng thái online.',
      bullets: [
        'Trên máy: ${DeviceSetupGuide.menuPath}',
        'Địa chỉ máy chủ: ${DeviceSetupGuide.serverHost} · Port: ${DeviceSetupGuide.serverPort}',
        'Trên phần mềm: Cài đặt → Máy chấm công → Thêm máy (SN hoặc quét mã)',
        'Máy online sẽ tự xuất hiện, dữ liệu chấm công đồng bộ real-time',
      ],
      tip: 'Chưa kết nối được? Gọi hotline 0973 024 042 — hỗ trợ từ xa qua Zalo.',
      accent: const Color(0xFF0277BD),
    ),
    const LandingUsageGuideStep(
      id: 'device_users',
      icon: Icons.fingerprint_rounded,
      title: 'Nhân viên chấm công & vân tay',
      desc:
          'Đồng bộ nhân viên từ hồ sơ xuống máy chấm công, sau đó đăng ký vân tay hoặc khuôn mặt trên thiết bị ZKTeco.',
      bullets: [
        'Menu: Nhân sự chấm công',
        'Đồng bộ danh sách NV từ Hồ sơ nhân sự xuống máy',
        'Đăng ký vân tay / khuôn mặt trên máy ZKTeco',
        'Kiểm tra Chấm công thô để xác nhận log vào/ra',
      ],
      tip: 'Mã nhân viên trên máy phải trùng mã trong hồ sơ để đồng bộ chính xác.',
      accent: Color(0xFF2E7D32),
    ),
    const LandingUsageGuideStep(
      id: 'mobile_attendance',
      icon: Icons.phone_android_rounded,
      title: 'Chấm công Mobile & duyệt',
      desc:
          'Bật chấm công bằng điện thoại (GPS, WiFi, Face ID). Nhân viên đăng ký thiết bị; quản lý duyệt tại Duyệt chấm công.',
      bullets: [
        'Cài đặt → Chấm công mobile: GPS, WiFi, vùng chấm công',
        'Menu: Đăng ký chấm công Mobile',
        'NV chấm công tại menu Chấm công Mobile',
        'Quản lý duyệt tại Duyệt chấm công',
      ],
      tip: 'Nên bật WiFi/GPS cửa hàng để chống chấm công ngoài vùng.',
      accent: Color(0xFF00838F),
    ),
    const LandingUsageGuideStep(
      id: 'penalty_ticket',
      icon: Icons.receipt_long_rounded,
      title: 'Tạo phiếu phạt',
      desc:
          'Hệ thống tự sinh phiếu phạt từ chấm công hoặc tạo thủ công tại Tài chính → Phiếu phạt.',
      bullets: [
        'Cài đặt → Phạt: mức phạt đi trễ, về sớm, tái phạm',
        'Tài chính → Phiếu phạt',
        'Duyệt / hủy / từ chối phiếu theo quy trình',
        'Báo cáo → Báo cáo phạt',
      ],
      tip: 'Phiếu đã hủy hoặc từ chối không tính vào báo cáo.',
      accent: Color(0xFFE65100),
    ),
    const LandingUsageGuideStep(
      id: 'advance',
      icon: Icons.savings_rounded,
      title: 'Tạo phiếu ứng lương',
      desc:
          'Nhân viên gửi yêu cầu ứng lương trên app; quản lý duyệt tại Tài chính → Ứng lương.',
      bullets: [
        'Tài chính → Ứng lương: tạo & duyệt phiếu',
        'NV tạo yêu cầu trên app mobile',
        'Theo dõi số tiền đã ứng, còn nợ',
        'Báo cáo → Báo cáo ứng lương',
      ],
      tip: 'Khi chi ứng lương qua Thu chi, hệ thống tự cập nhật trạng thái phiếu.',
      accent: Color(0xFFAD1457),
    ),
    const LandingUsageGuideStep(
      id: 'bonus_ticket',
      icon: Icons.card_giftcard_rounded,
      title: 'Tạo phiếu thưởng',
      desc:
          'Ghi nhận thưởng tại Tài chính → Phiếu thưởng. Số tiền thưởng được tính vào bảng lương kỳ tương ứng.',
      bullets: [
        'Tài chính → Phiếu thưởng',
        'Tạo phiếu thưởng theo nhân viên, kỳ, lý do',
        'Duyệt phiếu trước khi tính lương',
        'Hiển thị trong Tổng hợp lương',
      ],
      tip: 'Tạo phiếu thưởng trước khi chốt bảng lương tháng.',
      accent: Color(0xFF7B1FA2),
    ),
    const LandingUsageGuideStep(
      id: 'cash',
      icon: Icons.account_balance_wallet_rounded,
      title: 'Thu chi',
      desc:
          'Ghi sổ thu chi quỹ tiền mặt tại Tài chính → Thu chi. Liên kết phiếu ứng lương và phiếu phạt khi thu/chi thực tế.',
      bullets: [
        'Tài chính → Thu chi: ghi thu, ghi chi theo ngày',
        'Liên kết phiếu ứng lương khi chi ứng',
        'Liên kết phiếu phạt khi thu phạt',
        'Báo cáo → Báo cáo thu chi',
      ],
      tip: 'Ghi thu chi đúng ngày giúp đối soát quỹ và báo cáo chính xác.',
      accent: Color(0xFF558B2F),
    ),
    const LandingUsageGuideStep(
      id: 'reports',
      icon: Icons.assessment_rounded,
      title: 'Các báo cáo',
      desc:
          'Toàn bộ báo cáo tại menu Báo cáo: chấm công, phạt, ứng lương, thu chi, nghỉ phép, tài sản.',
      bullets: [
        'Tổng hợp chấm công · Tổng hợp theo ca',
        'Tổng hợp lương (menu Tính lương)',
        'Báo cáo phạt · Ứng lương · Thu chi · Nghỉ phép · Tài sản',
      ],
      tip: 'Phiếu hủy/từ chối không tính vào báo cáo ứng lương, phạt và nghỉ phép.',
      accent: Color(0xFF1976D2),
    ),
  ];

  static const advancedSteps = <LandingUsageGuideStep>[
    LandingUsageGuideStep(
      id: 'work_schedule',
      icon: Icons.calendar_month_rounded,
      title: 'Lịch làm việc',
      desc:
          'Phân ca, đổi ca và theo dõi lịch làm việc theo tuần/tháng cho từng nhân viên hoặc phòng ban.',
      bullets: [
        'Menu: Lịch làm việc',
        'Phân ca theo ngày, tuần, tháng',
        'NV gửi yêu cầu đổi ca tại Đổi ca làm việc',
        'Quản lý duyệt tại Duyệt lịch làm việc',
      ],
      tip: 'Nên phân ca trước đầu kỳ để chấm công và tính lương chính xác.',
      accent: Color(0xFF6A1B9A),
    ),
    LandingUsageGuideStep(
      id: 'kpi',
      icon: Icons.trending_up_rounded,
      title: 'KPI',
      desc:
          'Thiết lập chỉ tiêu KPI, giao việc đánh giá và theo dõi kết quả theo kỳ cho từng nhân viên/phòng ban.',
      bullets: [
        'Menu: KPI (Quản lý Vận hành)',
        'Tạo chỉ tiêu, mức đạt và trọng số',
        'Ghi nhận kết quả thực tế theo kỳ',
        'Dùng trong đánh giá hiệu suất và thưởng',
      ],
      tip: 'Gắn KPI với phiếu thưởng để tự động hóa ghi nhận thành tích.',
      accent: Color(0xFF059669),
    ),
    LandingUsageGuideStep(
      id: 'bonus',
      icon: Icons.emoji_events_rounded,
      title: 'Thưởng',
      desc:
          'Quản lý thưởng định kỳ, thưởng nóng và thưởng theo KPI — tích hợp vào bảng lương.',
      bullets: [
        'Tài chính → Phiếu thưởng',
        'Tạo theo nhân viên, kỳ, loại thưởng',
        'Duyệt trước khi chốt Tổng hợp lương',
        'Xem lại tại Tổng hợp lương',
      ],
      tip: 'Thưởng đã duyệt mới được cộng vào phiếu lương.',
      accent: Color(0xFF7B1FA2),
    ),
    LandingUsageGuideStep(
      id: 'leave',
      icon: Icons.event_busy_rounded,
      title: 'Nghỉ phép',
      desc:
          'NV tạo đơn nghỉ phép trên app; quản lý duyệt/từ chối. Hệ thống trừ phép năm và tính vào chấm công.',
      bullets: [
        'Menu: Nghỉ phép',
        'NV tạo đơn, đính kèm lý do và ngày nghỉ',
        'Quản lý duyệt / từ chối / hủy phiếu',
        'Báo cáo → Báo cáo nghỉ phép',
      ],
      tip: 'Phiếu từ chối hoặc hủy không tính vào báo cáo nghỉ phép.',
      accent: Color(0xFF0284C7),
    ),
    LandingUsageGuideStep(
      id: 'penalty',
      icon: Icons.gavel_rounded,
      title: 'Phạt',
      desc:
          'Cấu hình mức phạt đi trễ, về sớm, tái phạm và quản lý phiếu phạt tự động từ chấm công.',
      bullets: [
        'Cài đặt → Phạt: quy tắc và mức phạt',
        'Tài chính → Phiếu phạt: tự động & thủ công',
        'Thu phạt qua Thu chi (liên kết phiếu)',
        'Báo cáo → Báo cáo phạt',
      ],
      tip: 'Thiết lập ngưỡng phút đi trễ trước khi vận hành thực tế.',
      accent: Color(0xFFE65100),
    ),
    LandingUsageGuideStep(
      id: 'production',
      icon: Icons.precision_manufacturing_rounded,
      title: 'Sản lượng',
      desc:
          'Nhập sản lượng theo nhóm sản phẩm, ca hoặc nhân viên để tính lương khoán/sản phẩm.',
      bullets: [
        'Menu: Sản lượng (Quản lý Vận hành)',
        'Cài đặt → Lương sản phẩm: nhóm SP, đơn giá',
        'Nhập sản lượng theo ngày/ca',
        'Tổng hợp lương tự cộng phần lương SP',
      ],
      tip: 'Khai báo đơn giá bậc thang trước khi nhập sản lượng hàng loạt.',
      accent: Color(0xFF059669),
    ),
    LandingUsageGuideStep(
      id: 'asset',
      icon: Icons.inventory_2_rounded,
      title: 'Tài sản',
      desc:
          'Quản lý tài sản, thiết bị công ty: cấp phát, thu hồi, bảo hành và theo dõi người giữ.',
      bullets: [
        'Menu: Tài sản (Quản lý Vận hành)',
        'Thêm tài sản, mã, ngày mua, bảo hành',
        'Gán tài sản cho nhân viên/phòng ban',
        'Báo cáo → Báo cáo tài sản',
      ],
      tip: 'Ghi nhận ngày hết bảo hành để nhận nhắc trước hạn.',
      accent: Color(0xFF334155),
    ),
    LandingUsageGuideStep(
      id: 'communication',
      icon: Icons.campaign_rounded,
      title: 'Truyền thông',
      desc:
          'Đăng tin nội bộ, thông báo, nội quy và bản tin tới toàn bộ hoặc từng nhóm nhân viên.',
      bullets: [
        'Menu: Truyền thông',
        'Tạo bài viết, ghim tin quan trọng',
        'Gửi thông báo push tới app NV',
        'NV xem trên Tổng quan và mục Truyền thông',
      ],
      tip: 'Dùng truyền thông để thông báo chính sách chấm công và lương mới.',
      accent: Color(0xFF059669),
    ),
    LandingUsageGuideStep(
      id: 'feedback',
      icon: Icons.feedback_rounded,
      title: 'Góp ý / Khiếu nại',
      desc:
          'Tiếp nhận phản ánh, góp ý ẩn danh hoặc công khai từ nhân viên; quản lý phản hồi và theo dõi xử lý.',
      bullets: [
        'Menu: Phản ánh / Ý kiến',
        'NV gửi góp ý từ app (ẩn danh hoặc có tên)',
        'Quản lý xem, trả lời và đóng phiếu',
        'Theo dõi trạng thái đã xử lý / chờ xử lý',
      ],
      tip: 'Khuyến khích góp ý ẩn danh để nhận phản hồi trung thực từ tập thể.',
      accent: AppColors.primary,
    ),
    LandingUsageGuideStep(
      id: 'meal',
      icon: Icons.restaurant_rounded,
      title: 'Chấm cơm',
      desc:
          'Ghi nhận suất ăn / chấm cơm theo ca hoặc theo ngày, phục vụ kiểm soát chi phí suất ăn.',
      bullets: [
        'Menu: Chấm cơm',
        'Cấu hình suất ăn theo ca (nếu có)',
        'NV hoặc quản lý ghi nhận suất ăn',
        'Đối soát theo tháng với báo cáo nhân sự',
      ],
      tip: 'Liên kết chấm cơm với ca làm việc để tránh ghi nhận trùng.',
      accent: Color(0xFFF97316),
    ),
    LandingUsageGuideStep(
      id: 'employee_account',
      icon: Icons.manage_accounts_rounded,
      title: 'Tạo tài khoản nhân viên',
      desc:
          'Tạo tài khoản đăng nhập app/web cho nhân viên, gán quyền và liên kết với hồ sơ nhân sự.',
      bullets: [
        'Cài đặt → Tài khoản',
        'Thêm tài khoản, chọn nhân viên HR tương ứng',
        'Gán vai trò tại Cài đặt → Phân quyền',
        'NV đăng nhập bằng mã cửa hàng + tài khoản được cấp',
      ],
      tip: 'Mỗi nhân viên nên có một tài khoản riêng, không dùng chung mật khẩu.',
      accent: Color(0xFF1565C0),
    ),
  ];

  @Deprecated('Use LandingGuideData.defaults.basic')
  static List<LandingUsageGuideStep> get steps => basicSteps;

  @Deprecated('Use LandingGuideData.defaults.basicCount')
  static int get stepCount => basicSteps.length;
}
