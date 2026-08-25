import 'dart:convert';

import 'package:flutter/material.dart';

import 'device_setup_guide.dart';

/// Kết quả tìm kiếm một mục hướng dẫn.
class LandingGuideSearchHit {
  const LandingGuideSearchHit({
    required this.sectionIndex,
    required this.stepIndex,
    required this.step,
    required this.matchedIn,
  });

  /// 0 = Triển khai (basic), 1 = Nâng cao (advanced), 2 = POS.
  final int sectionIndex;
  final int stepIndex;
  final LandingUsageGuideStep step;

  /// Ví dụ: "Tiêu đề", "Từ khóa", "Nội dung".
  final String matchedIn;

  String get sectionLabel => LandingGuideData.labelForIndex(sectionIndex);
}

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
    this.keywords = const [],
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

  /// Từ khóa giúp khách tìm nhanh (CMS có thể bổ sung).
  final List<String> keywords;

  LandingUsageGuideStep copyWith({
    String? title,
    String? desc,
    String? tip,
    List<String>? bullets,
    List<String>? imageUrls,
    String? videoUrl,
    List<String>? keywords,
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
      keywords: keywords ?? this.keywords,
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
        if (keywords.isNotEmpty) 'keywords': keywords,
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
    List<String>? keywords;
    final rawKw = json['keywords'] ?? json['tags'];
    if (rawKw is List) {
      final parsed = rawKw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parsed.isNotEmpty) keywords = parsed;
    } else if (rawKw is String && rawKw.trim().isNotEmpty) {
      keywords = rawKw
          .split(RegExp(r'[,;|/]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return fallback.copyWith(
      title: (title != null && title.isNotEmpty) ? title : null,
      desc: (desc != null && desc.isNotEmpty) ? desc : null,
      tip: tip != null ? tip : null,
      bullets: bullets,
      imageUrls: images.isNotEmpty ? images : null,
      videoUrl: videoUrl != null ? videoUrl : null,
      keywords: keywords,
    );
  }
}

/// Toàn bộ hướng dẫn landing: triển khai HRM + vận hành nâng cao + POS.
class LandingGuideData {
  const LandingGuideData({
    required this.basic,
    required this.advanced,
    this.pos = const [],
  });

  final List<LandingUsageGuideStep> basic;
  final List<LandingUsageGuideStep> advanced;
  final List<LandingUsageGuideStep> pos;

  int get basicCount => basic.length;
  int get advancedCount => advanced.length;
  int get posCount => pos.length;

  List<LandingUsageGuideStep> stepsAt(int sectionIndex) => switch (sectionIndex) {
        1 => advanced,
        2 => pos,
        _ => basic,
      };

  static String keyForIndex(int sectionIndex) => switch (sectionIndex) {
        1 => 'advanced',
        2 => 'pos',
        _ => 'basic',
      };

  static int indexForKey(String section) => switch (section.trim().toLowerCase()) {
        'advanced' => 1,
        'pos' => 2,
        _ => 0,
      };

  static String labelForIndex(int sectionIndex) => switch (sectionIndex) {
        1 => 'Nâng cao',
        2 => 'POS',
        _ => 'Triển khai',
      };

  static bool isKnownSection(String section) {
    final k = section.trim().toLowerCase();
    return k == 'basic' || k == 'advanced' || k == 'pos';
  }

  Map<String, dynamic> toJson() => {
        'basic': basic.map((e) => e.toJson()).toList(),
        'advanced': advanced.map((e) => e.toJson()).toList(),
        'pos': pos.map((e) => e.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  static LandingGuideData get defaults => LandingGuideData(
        basic: _withKeywords(LandingUsageGuide.basicSteps, _basicKeywords),
        advanced:
            _withKeywords(LandingUsageGuide.advancedSteps, _advancedKeywords),
        pos: _withKeywords(LandingUsageGuide.posSteps, _posKeywords),
      );

  static List<LandingUsageGuideStep> _withKeywords(
    List<LandingUsageGuideStep> steps,
    Map<String, List<String>> map,
  ) {
    return steps
        .map((s) {
          final kw = map[s.id];
          if (kw == null || kw.isEmpty) return s;
          if (s.keywords.isNotEmpty) {
            final merged = {...s.keywords, ...kw}.toList();
            return s.copyWith(keywords: merged);
          }
          return s.copyWith(keywords: kw);
        })
        .toList();
  }

  /// Gợi ý từ khóa phổ biến trên thanh tìm kiếm.
  static const suggestionKeywords = <String>[
    'Đăng ký',
    'Mã cửa hàng',
    'Nhân viên',
    'Import Excel',
    'Ca làm việc',
    'Lịch làm việc',
    'Máy chấm công',
    'Vân tay',
    'Chấm công mobile',
    'Phân quyền',
    'Lương',
    'Tính lương',
    'Phạt đi trễ',
    'Ứng lương',
    'Nghỉ phép',
    'Đổi ca',
    'Báo cáo',
    'Tổng kết cuối ngày',
    'KPI',
    'POS',
    'Máy in',
    'Mẫu in',
    'Gửi bếp',
    'Bàn phòng',
    'Công tác',
    'Quên mật khẩu',
    'Quên chấm',
  ];

  List<LandingGuideSearchHit> search(String query, {int limit = 12}) {
    final q = _fold(query.trim());
    if (q.isEmpty) return const [];
    final hits = <LandingGuideSearchHit>[];
    void scan(int section, List<LandingUsageGuideStep> steps) {
      for (var i = 0; i < steps.length; i++) {
        final s = steps[i];
        final match = _matchStep(s, q);
        if (match == null) continue;
        hits.add(LandingGuideSearchHit(
          sectionIndex: section,
          stepIndex: i,
          step: s,
          matchedIn: match,
        ));
      }
    }

    scan(0, basic);
    scan(1, advanced);
    scan(2, pos);
    hits.sort((a, b) {
      final ra = _rank(a.matchedIn);
      final rb = _rank(b.matchedIn);
      if (ra != rb) return ra.compareTo(rb);
      return a.step.title.compareTo(b.step.title);
    });
    if (hits.length <= limit) return hits;
    return hits.sublist(0, limit);
  }

  static int _rank(String matchedIn) {
    switch (matchedIn) {
      case 'Từ khóa':
        return 0;
      case 'Tiêu đề':
        return 1;
      case 'Mô tả':
        return 2;
      default:
        return 3;
    }
  }

  static String? _matchStep(LandingUsageGuideStep s, String q) {
    for (final kw in s.keywords) {
      if (_fold(kw).contains(q)) return 'Từ khóa';
    }
    if (_fold(s.title).contains(q)) return 'Tiêu đề';
    if (_fold(s.desc).contains(q)) return 'Mô tả';
    if (_fold(s.tip).contains(q)) return 'Mẹo';
    for (final b in s.bullets) {
      if (_fold(b).contains(q)) return 'Các bước';
    }
    return null;
  }

  /// Bỏ dấu tiếng Việt để tìm "cham cong" vẫn ra "chấm công".
  static String _fold(String input) {
    const map = <String, String>{
      'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
      'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
      'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
      'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
      'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
      'đ': 'd',
    };
    final buf = StringBuffer();
    for (final r in input.toLowerCase().runes) {
      final ch = String.fromCharCode(r);
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }

  static const _basicKeywords = <String, List<String>>{
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

  static const _advancedKeywords = <String, List<String>>{
    'attendance_modes': [
      'kiểu chấm công',
      'checkin',
      'chỉ chấm vào',
      'thiếu chấm',
      'mode',
    ],
    'work_schedule': ['lịch làm việc', 'sao chép tuần', 'duyệt lịch'],
    'shift_swap': ['đổi ca', 'đổi lịch', 'swap'],
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
  };

  static const _posKeywords = <String, List<String>>{
    'pos_devices': [
      'a6',
      'a7',
      'sunmi',
      'flutter_pos',
      'hrm pos',
      'thiết bị',
    ],
    'pos_setup': [
      'pos',
      'bán hàng',
      'thiết lập pos',
      'ngành hàng',
      'cửa hàng',
    ],
    'pos_products': ['hàng hóa', 'sản phẩm', 'giá bán', 'danh mục món'],
    'pos_tables': ['bàn', 'phòng', 'sơ đồ bàn', 'đặt bàn', 'đặt lịch'],
    'pos_printers': [
      'máy in',
      'mẫu in',
      'k80',
      'k58',
      'print agent',
      'usb',
      'bluetooth',
    ],
    'pos_kitchen': ['bếp', 'gửi bếp', 'phiếu bếp', 'tem ly', 'kds'],
    'pos_sales': [
      'bán hàng',
      'thu ngân',
      'thanh toán',
      'hóa đơn',
      'order',
    ],
    'pos_customers': ['khách hàng', 'điểm', 'công nợ khách', 'crm'],
    'pos_inventory': ['kho', 'nhập hàng', 'tồn kho', 'kiểm kho', 'ncc'],
    'pos_einvoice': ['hóa đơn điện tử', 'viettel', 'misa', 'einvoice'],
    'pos_reports': [
      'báo cáo pos',
      'doanh thu',
      'tồn kho',
      'lợi nhuận',
      '14 báo cáo',
    ],
    'pos_eod': ['cuối ngày', 'chốt ca', 'tổng kết', 'end of day'],
    'pos_common': [
      'không in',
      'in sai',
      'lệch tiền',
      'hủy đơn',
      'trả hàng',
      'tình huống pos',
    ],
  };

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
    return LandingGuideData(
      basic: merged,
      advanced: base.advanced,
      pos: base.pos,
    );
  }

  static LandingGuideData _mergeSections(
    LandingGuideData base,
    Map<dynamic, dynamic> map,
  ) {
    return LandingGuideData(
      basic: _mergeStepList(base.basic, map['basic']),
      advanced: _mergeStepList(base.advanced, map['advanced']),
      pos: _mergeStepList(base.pos, map['pos']),
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
        'Nếu gói có POS: sang tab POS — ngành hàng → hàng hóa → máy in → bán thử → xem Báo cáo POS',
        'Hotline hỗ trợ: 0973 024 042 (Zalo hỗ trợ từ xa)',
      ],
      tip:
          'Tuần đầu ưu tiên nhân sự → ca → chấm công → lương. POS và KPI làm sau khi chấm công đã ổn.',
      accent: Color(0xFF0C56D0),
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
        'Bước 1 — Vào menu Hồ sơ nhân sự → Thêm nhân viên (hoặc Import Excel nếu thêm hàng loạt)',
        'Bước 2 — Nhập bắt buộc: họ tên, mã nhân viên (PIN), phòng ban, chức vụ',
        'Bước 3 — Bổ sung nên có: SĐT, ngày vào làm, trạng thái Đang làm việc',
        'Bước 4 — Nếu Import Excel: tải mẫu trong màn hình → điền đúng cột → tải lên → kiểm tra kết quả',
        'Bước 5 — Kiểm tra không trùng mã nhân viên trước khi đồng bộ xuống máy',
        'Bước 6 — Gán Thiết lập lương và phân ca trên Lịch làm việc (các bước tiếp theo)',
        'Bước 7 — NV nghỉ việc: cập nhật trạng thái nghỉ — không xóa nếu đã có dữ liệu chấm công',
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
        'Bước 1 — Vào Cài đặt → Thiết lập ca → Thêm ca',
        'Bước 2 — Nhập tên ca, giờ bắt đầu / kết thúc (hỗ trợ ca qua đêm, vd 21:30–06:00)',
        'Bước 3 — Cấu hình phút ân hạn đi trễ, ân hạn về sớm, ngưỡng tính tăng ca',
        'Bước 4 — Phân biệt ca hành chính và ca Tăng ca (OT) nếu cửa hàng dùng',
        'Bước 5 — Gán ca vào mẫu lương / nhân viên tại Thiết lập lương (ô Ca làm việc)',
        'Bước 6 — Phân lịch cụ thể theo ngày tại menu Lịch làm việc',
        'Bước 7 — Mở nút hướng dẫn trong màn Thiết lập ca khi cần chi tiết OT / grace',
      ],
      tip:
          'Dùng «Nhân bản ca» để clone ca tương tự. Ân hạn đi trễ (vd 10 phút) tránh phạt oan khi vào sớm vài phút sau giờ.',
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
          'Cấu hình hai phía: máy trỏ về máy chủ ADMS cloud; phần mềm khai báo serial để nhận log real-time. Làm đúng thứ tự để tránh máy Offline.',
      bullets: [
        'Bước 1 — Trên máy ZKTeco: vào ${DeviceSetupGuide.menuPath}',
        'Bước 2 — Nhập Địa chỉ máy chủ: ${DeviceSetupGuide.serverHost} · Port: ${DeviceSetupGuide.serverPort}',
        'Bước 3 — Bật Cloud / ADMS theo hướng dẫn trên máy; lưu và khởi động lại nếu máy yêu cầu',
        'Bước 4 — Trên SBOX: Cài đặt → Máy chấm công → Thêm máy (nhập SN hoặc quét mã)',
        'Bước 5 — Kiểm tra trạng thái Online trên danh sách máy (có thể mất 1–2 phút)',
        'Bước 6 — Cho NV chấm thử → mở Chấm công thô xác nhận có ATTLOG',
        'Bước 7 — Nếu Offline: kiểm tra mạng cửa hàng cho máy ra internet (HTTPS/ADMS) hoặc gọi hotline',
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
          'Quy trình cuối kỳ để kiểm tra chấm công rồi chốt lương lần đầu — làm đúng thứ tự để giảm sai sót khi mới triển khai.',
      bullets: [
        'Bước 1 — Kiểm tra Chấm công thô: đủ log, đúng NV, không trùng bất thường',
        'Bước 2 — Mở Tổng hợp theo ca / Tổng hợp chấm công: kiểm tra công, phút trễ/sớm, thiếu chấm',
        'Bước 3 — Duyệt xong nghỉ phép, đổi ca, phiếu thưởng / phạt / ứng trong kỳ',
        'Bước 4 — Vào Tính lương / Tổng hợp lương → chọn kỳ → tải lại dữ liệu',
        'Bước 5 — Rà từng NV: công, phụ cấp, BHXH, thuế, ứng, thưởng, phạt',
        'Bước 6 — Xuất Excel / in phiếu lương; gửi NV kiểm tra trên app',
        'Bước 7 — Chỉ chỉnh sửa lịch/ca trước khi chốt — sau chốt nên khóa kỳ nếu có',
      ],
      tip:
          'Tháng đầu nên chấm thử 3–5 ngày rồi xem Tổng hợp theo ca trước khi tin tưởng tự động hoàn toàn.',
      accent: Color(0xFFC62828),
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
      accent: Color(0xFF1976D2),
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
        'Ngày chốt: Tổng hợp theo ca → Tính lương → gửi phiếu lương trên app cho NV kiểm tra',
        'Sau chốt: hạn chế sửa lịch/ca của kỳ đã khóa; phát sinh kỳ sau ghi vào tháng mới',
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
        'NV quên chấm: menu Sửa giờ / Báo quên chấm → quản lý duyệt; không xóa log máy',
        'Máy ZK Offline: kiểm tra mạng máy + SN trên Cài đặt → Máy chấm công; gọi 0973 024 042 nếu vẫn lỗi',
        'Log hiện PIN lạ: mã trên máy ≠ mã hồ sơ — đồng bộ lại Nhân sự chấm công',
        'Quên mật khẩu: màn đăng nhập → Quên mật khẩu (cần email đã đăng ký)',
        'NV nghỉ việc: đổi trạng thái nghỉ + khóa tài khoản app; không xóa hồ sơ nếu đã có công',
        'Bảng lương lệch: chưa duyệt phép/thưởng/ứng, hoặc đổi ca sau khi đã có phiếu phạt',
        'Không thấy menu: tài khoản thiếu phân quyền — Admin vào Cài đặt → Phân quyền',
      ],
      tip:
          'Sửa gốc (ca, mode chấm, ân hạn) trước khi xóa hàng loạt phiếu phạt — tránh phạt lại ngày hôm sau.',
      accent: Color(0xFF6D4C41),
    ),
  ];

  /// Nâng cao: chính sách chuyên sâu, vận hành HRM, hiện trường (POS xem tab POS).
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
        'Bước 1 — NV vào menu Nghỉ phép → tạo đơn (loại phép, từ ngày–đến ngày, lý do)',
        'Bước 2 — Gửi đơn; quản lý nhận thông báo trên web/app',
        'Bước 3 — Quản lý duyệt / từ chối / hủy đơn',
        'Bước 4 — Kiểm tra số ngày phép còn lại (nếu cấu hình quỹ phép)',
        'Bước 5 — Đối chiếu Tổng hợp chấm công: phép đã duyệt không tính nghỉ không phép',
        'Bước 6 — Xem Báo cáo → Báo cáo nghỉ phép; mở hướng dẫn pháp lý trên màn Nghỉ phép khi cần',
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
  ];

  /// POS / bán hàng: máy A6–A7, in, bếp, kho, báo cáo doanh thu.
  static const posSteps = <LandingUsageGuideStep>[
    LandingUsageGuideStep(
      id: 'pos_devices',
      icon: Icons.devices_rounded,
      title: 'Máy thu ngân A6 / A7 & app nào dùng',
      desc:
          'Cùng một cửa hàng SBOX: máy Sunmi T1 (A6) chạy app POS; máy C20Lite (A7) và web/iOS bán hàng trong app HRM.',
      bullets: [
        'A6 Sunmi T1: cài app POS (gói sbox.sana.vn.pos.flutter) — thu ngân + in USB/TSPL + màn hình phụ khách',
        'A7 C20Lite / điện thoại / web: mở app HRM (sbox.sana.vn) → menu Bán hàng (POS nằm trong HRM)',
        'Có thể cài APK POS lên A7 chỉ để thử; luồng thật trên A7 vẫn là HRM → POS',
        'Đăng nhập cùng mã cửa hàng + tài khoản thu ngân đã được phân quyền PosSell',
        'Cài đặt → Phân quyền: thu ngân cần xem/tạo Bán hàng; quản lý thêm Báo cáo POS, kho, mẫu in',
        'Sau khi cài POS trên A6: rút USB/ADB trước khi kiểm tra màn hình phụ khách (USB debug hay làm trắng màn 7")',
      ],
      tip:
          'Mẫu in và máy in là theo từng cửa hàng — cấu hình một lần, A6 và A7 cùng store sẽ dùng chung catalog.',
      accent: Color(0xFFEF6C00),
    ),
    LandingUsageGuideStep(
      id: 'pos_setup',
      icon: Icons.storefront_rounded,
      title: 'Thiết lập POS lần đầu',
      desc:
          'Làm đúng thứ tự: ngành hàng → thông tin cửa hàng → hàng hóa → bàn (F&B) → máy in → bán thử.',
      bullets: [
        'Bước 1 — Cài đặt (hub) → Ngành hàng & bán hàng: chọn retail / nhà hàng / salon / phòng…',
        'Bước 2 — Cài đặt → Thiết lập cửa hàng: tên, địa chỉ, VAT, tài khoản VietQR (nếu thanh toán QR)',
        'Bước 3 — Menu Hàng hóa: danh mục + món/SP (mã, giá, đơn vị, ảnh)',
        'Bước 4 — F&B: Cài đặt → Quản lý bàn / phòng: khu vực, bàn, sức chứa',
        'Bước 5 — Cài đặt → Máy in + Mẫu in (xem bước Máy in bên dưới)',
        'Bước 6 — Phân quyền tài khoản thu ngân / quản kho / quản lý',
        'Bước 7 — Mở Bán hàng, tạo 1 đơn test, in thử, thanh toán 0đ hoặc hủy theo quyền',
      ],
      tip:
          'Sai ngành hàng thì không thấy sơ đồ bàn / gửi bếp. Đổi ngành xong mở lại Bán hàng.',
      accent: Color(0xFFEF6C00),
    ),
    LandingUsageGuideStep(
      id: 'pos_products',
      icon: Icons.inventory_2_rounded,
      title: 'Hàng hóa, giá & combo',
      desc:
          'Danh mục bán nằm ở menu POS → Hàng hóa. Giá trên hóa đơn lấy từ đây (hoặc bảng giá nếu cửa hàng dùng nhiều bảng).',
      bullets: [
        'Menu: Hàng hóa → Thêm sản phẩm / món: mã, tên, giá bán, đơn vị, nhóm',
        'Gắn ảnh để thu ngân chọn nhanh trên màn bán',
        'Combo / món có topping: khai báo thành phần nếu cần trừ kho nguyên liệu',
        'Ngừng kinh doanh: tắt bán thay vì xóa — giữ lịch sử hóa đơn',
        'Giá thay đổi: sửa trên Hàng hóa; đơn đang mở giữ giá lúc thêm món',
      ],
      tip: 'Mã hàng nên ngắn, không dấu — dễ gõ và in tem.',
      accent: Color(0xFF00897B),
    ),
    LandingUsageGuideStep(
      id: 'pos_tables',
      icon: Icons.table_restaurant_rounded,
      title: 'Bàn / phòng & đặt lịch',
      desc:
          'Nhà hàng, quán: bán theo sơ đồ bàn. Salon / spa: dùng Đặt lịch. Retail thường bỏ qua bước này.',
      bullets: [
        'Cài đặt → Quản lý bàn / phòng: tạo khu (tầng 1, sân vườn…) rồi thêm bàn',
        'Bán hàng: chọn bàn trống → thêm món → gửi bếp (nếu bật) → khách ngồi → thanh toán',
        'Ghép / tách / chuyển bàn theo nút trên sơ đồ (đúng quyền)',
        'Menu Đặt lịch: tạo lịch theo ngày–giờ–dịch vụ–khách (salon, phòng)',
        'Đặt bàn F&B: chọn giờ, số khách, bàn — đổi trạng thái khi khách đến',
      ],
      tip: 'Bàn «đang dùng» phải thanh toán hoặc trả bàn trước khi gán khách mới.',
      accent: Color(0xFF6A1B9A),
    ),
    LandingUsageGuideStep(
      id: 'pos_printers',
      icon: Icons.print_rounded,
      title: 'Máy in & mẫu in (K80 / tem)',
      desc:
          'Mỗi cửa hàng chọn máy + mẫu mặc định riêng. Hóa đơn thường K80; tem ly/tem hàng khổ nhỏ; bếp dùng mẫu phiếu bếp.',
      bullets: [
        'Cài đặt → Máy in (thiết bị): thêm máy USB (A6/Agent), Bluetooth, LAN, hoặc in cloud',
        'A6 Sunmi: in USB/TSPL qua Print Agent trên máy; HRM A7 thường Bluetooth/LAN/cloud',
        'Cài đặt → Mẫu in: hóa đơn, phiếu bếp, tem — bấm mặc định cho đúng loại',
        'Gán mẫu theo cửa hàng (không dùng chung mặc định nhầm store khác)',
        'In thử từ màn Mẫu in hoặc từ 1 đơn test trên Bán hàng',
        'Một máy có thể vừa hóa đơn vừa bếp nếu gắn 2 mẫu / 2 máy vật lý khác nhau',
      ],
      tip:
          'A6 và A7 cùng cửa hàng phải thấy cùng mẫu mặc định. Nếu lệch: vào Mẫu in, chọn lại mặc định của store — không copy tay từ máy khác.',
      accent: Color(0xFF0277BD),
    ),
    LandingUsageGuideStep(
      id: 'pos_kitchen',
      icon: Icons.soup_kitchen_rounded,
      title: 'Gửi bếp & phiếu chế biến',
      desc:
          'F&B: sau khi order, gửi bếp để in phiếu / hiện KDS. Phiếu bếp in giờ gọi một lần ở đầu phiếu.',
      bullets: [
        'Trên Bán hàng (bàn đang mở): thêm món → Gửi bếp / In bếp',
        'Món đã gửi sẽ đánh dấu; thêm món sau thì gửi tiếp phần mới',
        'Cài đặt mẫu Phiếu bếp / tem ly; máy in bếp (LAN/USB) khác máy hóa đơn nếu cần',
        'Hủy món đã gửi: theo quyền hủy — bếp nhận phiếu hủy nếu được bật',
        'Không gửi bếp được: kiểm tra ngành hàng F&B + máy in bếp + mẫu phiếu bếp là mặc định',
      ],
      tip:
          'In hóa đơn lúc thanh toán; in bếp lúc gọi món — đừng gán nhầm một mẫu cho cả hai.',
      accent: Color(0xFFC62828),
    ),
    LandingUsageGuideStep(
      id: 'pos_sales',
      icon: Icons.point_of_sale_rounded,
      title: 'Quy trình bán hàng',
      desc:
          'Luồng thu ngân mỗi đơn: chọn hàng (hoặc bàn) → chỉnh SL/giảm giá → thanh toán → in HĐ → (tuỳ) HĐĐT.',
      bullets: [
        'Bước 1 — Menu Bán hàng (A7/HRM) hoặc mở app POS (A6)',
        'Bước 2 — Retail: quét/chọn SP. F&B: chọn bàn rồi chọn món',
        'Bước 3 — Sửa số lượng, ghi chú món, chiết khấu dòng hoặc cả đơn (cần quyền duyệt giá)',
        'Bước 4 — Chọn khách (nếu tích điểm / công nợ) → Thanh toán',
        'Bước 5 — Tiền mặt / chuyển khoản / QR / kết hợp; nhận tiền → hoàn tất',
        'Bước 6 — In hóa đơn; xuất HĐĐT nếu khách cần (bước Hóa đơn điện tử)',
        'Đơn hàng: tra cứu, in lại, hủy (đúng quyền). Trả hàng: menu Trả hàng bán, gắn đơn gốc',
      ],
      tip:
          'Tài khoản thu ngân cần quyền duyệt PosSell mới thanh toán được. Waiter chỉ order thì không hoàn tất HĐ.',
      accent: Color(0xFFE65100),
    ),
    LandingUsageGuideStep(
      id: 'pos_customers',
      icon: Icons.people_outline_rounded,
      title: 'Khách hàng, điểm & công nợ',
      desc:
          'CRM POS: tạo khách, tích điểm, bán nợ (phải thu) — đối soát trên Báo cáo công nợ.',
      bullets: [
        'Menu: Khách hàng POS → Thêm khách (SĐT làm mã nhanh)',
        'Trên đơn: chọn khách trước khi thanh toán để cộng điểm / ghi nợ',
        'Công nợ: thanh toán một phần, thu nợ sau tại khách hoặc báo cáo Công nợ',
        'Cài đặt ngành hàng: bật/tắt điểm, hạn mức nợ nếu cửa hàng dùng',
      ],
      tip: 'Không gắn khách thì đơn vẫn bán được — nhưng không tích điểm / không lên công nợ.',
      accent: Color(0xFF1565C0),
    ),
    LandingUsageGuideStep(
      id: 'pos_inventory',
      icon: Icons.warehouse_rounded,
      title: 'Kho: nhập, kiểm, xuất',
      desc:
          'Tồn kho tăng khi nhập NCC hoàn thành; giảm khi bán (nếu trừ kho), xuất hủy, xuất nội bộ.',
      bullets: [
        'Nhà cung cấp → Nhập hàng NCC: tạo phiếu → duyệt/hoàn thành để tăng tồn',
        'Trả hàng nhập khi hàng lỗi / thừa',
        'Kiểm kho: tạo phiên đếm → nhập SL thực tế → cân bằng lệch',
        'Xuất hủy / Xuất dùng nội bộ theo quy trình cửa hàng',
        'Xem tồn trên Hàng hóa; Báo cáo POS → Tồn kho / Hàng sắp hết hạn',
      ],
      tip: 'Nhập hàng trước khi bán món trừ nguyên liệu — tránh tồn âm giữa ca.',
      accent: Color(0xFF5D4037),
    ),
    LandingUsageGuideStep(
      id: 'pos_einvoice',
      icon: Icons.request_quote_rounded,
      title: 'Hóa đơn điện tử',
      desc:
          'Kết nối Viettel SInvoice, Easy Invoice hoặc MISA để xuất HĐĐT sau khi bán.',
      bullets: [
        'Cài đặt → Hóa đơn điện tử: nhập tài khoản nhà cung cấp HĐĐT của cửa hàng',
        'Kiểm tra MST, địa chỉ trên Thiết lập cửa hàng khớp hồ sơ thuế',
        'Sau thanh toán: nút Xuất HĐĐT trên đơn (đúng quyền)',
        'Khách lấy hóa đơn: gửi email / tra cứu theo mã cơ quan thuế',
        'Lỗi xuất: xem log trên màn HĐĐT — thường sai MST, hết serial, hoặc token hết hạn',
      ],
      tip: 'Xuất HĐĐT sau khi đơn đã hoàn tất — hủy đơn đã xuất phải xử lý điều chỉnh theo NCC HĐĐT.',
      accent: Color(0xFF00695C),
    ),
    LandingUsageGuideStep(
      id: 'pos_reports',
      icon: Icons.analytics_rounded,
      title: 'Cách xem báo cáo POS',
      desc:
          'Menu Báo cáo → Báo cáo POS (hub ~14 báo cáo). Trên A7: tab Tổng quan POS hoặc Nhiều hơn → Báo cáo. Chọn khoảng thời gian rồi mở từng loại.',
      bullets: [
        'Bước 1 — Vào Báo cáo POS (sidebar «Báo cáo», hoặc POS → Nhiều hơn)',
        'Bước 2 — Chọn từ ngày–đến ngày (hôm nay / ca / tháng)',
        'Doanh thu — theo ngày; Hàng hóa bán ra — mặt hàng',
        'Tồn kho · Nhập hàng · Hàng sắp hết hạn',
        'Phương thức thanh toán · Công nợ · Sổ quỹ',
        'Lợi nhuận · Chi phí · Kết quả kinh doanh (P&L)',
        'Doanh thu theo nhân viên (thu ngân) · Voucher',
        'Báo cáo hủy / trả (menu riêng)',
        'Xuất Excel trên từng báo cáo khi gửi kế toán',
      ],
      tip:
          'Không thấy một thẻ báo cáo: thiếu quyền module PosReport… — tick trong Phân quyền / gói dịch vụ.',
      accent: Color(0xFF1976D2),
    ),
    LandingUsageGuideStep(
      id: 'pos_eod',
      icon: Icons.nightlight_round,
      title: 'Tổng kết cuối ngày / chốt ca',
      desc:
          'Đối soát tiền mặt, QR, công nợ trong ca trước khi giao ca. Mở từ Báo cáo POS → Tổng kết cuối ngày, hoặc nút cuối ngày trên màn bán (đúng quyền).',
      bullets: [
        'Bước 1 — Xong đơn đang mở / trả bàn còn khách (F&B)',
        'Bước 2 — Mở Tổng kết cuối ngày, chọn khoảng ca (mở ca–đóng ca)',
        'Bước 3 — Đối chiếu tiền mặt ngăn kéo với cột tiền mặt trên phiếu tổng kết',
        'Bước 4 — Kiểm tra chuyển khoản / QR với sao kê ngân hàng',
        'Bước 5 — Ghi chi phí phát sinh (nếu dùng báo cáo Chi phí / sổ quỹ)',
        'Bước 6 — In hoặc xuất file tổng kết; giao ca cho thu ngân sau',
      ],
      tip:
          'Lệch tiền: xem Đơn hàng trong ca + Báo cáo hủy/trả + PTTT trước khi «bù» tay vào quỹ.',
      accent: Color(0xFF37474F),
    ),
    LandingUsageGuideStep(
      id: 'pos_common',
      icon: Icons.support_agent_rounded,
      title: 'Tình huống POS thường gặp',
      desc:
          'Xử lý nhanh khi không in được, lệch mẫu giữa hai máy, hủy đơn, hoặc A6/A7 khác nhau.',
      bullets: [
        'Không in hóa đơn: Máy in đã Online? Mẫu hóa đơn đã đặt mặc định store? In thử từ Cài đặt → Mẫu in',
        'In được HĐ nhưng không in bếp: gán máy + mẫu phiếu bếp riêng; gửi bếp trước khi thanh toán',
        'A6 in khác A7: cùng StoreId — vào Mẫu in chọn lại mặc định; catalog mẫu là theo cửa hàng',
        'Màn hình phụ A6 trắng: rút cáp ADB/USB debug rồi mở lại POS (DSKernel bị USB chặn)',
        'Không thanh toán được: thiếu quyền duyệt PosSell — nhờ admin tick Approve',
        'Hủy đơn / trả hàng: Đơn hàng hoặc Trả hàng bán; xem Báo cáo hủy/trả cuối ngày',
        'Bàn không hiện: ngành hàng chưa phải F&B, hoặc chưa tạo khu/bàn',
        'Tồn âm: bán trước khi nhập kho hoặc combo chưa khai nguyên liệu',
      ],
      tip: 'Hotline 0973 024 042 (Zalo hỗ trợ từ xa) khi máy in Agent USB không nhận job.',
      accent: Color(0xFF6D4C41),
    ),
  ];

  @Deprecated('Use LandingGuideData.defaults.basic')
  static List<LandingUsageGuideStep> get steps => basicSteps;

  @Deprecated('Use LandingGuideData.defaults.basicCount')
  static int get stepCount => basicSteps.length;
}
