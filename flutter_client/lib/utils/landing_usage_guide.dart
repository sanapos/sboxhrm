import 'dart:convert';

import 'package:flutter/material.dart';

import 'landing_industry_guide.dart';

import 'device_setup_guide.dart';

import '../theme/sbox_tokens.dart';
/// Kết quả tìm kiếm một mục hướng dẫn.
class LandingGuideSearchHit {
  const LandingGuideSearchHit({
    required this.sectionIndex,
    required this.stepIndex,
    required this.step,
    required this.matchedIn,
  });

  /// 0 = Triển khai (basic), 1 = Nâng cao (advanced), 2 = POS, 3 = Ngành hàng.
  final int sectionIndex;
  final int stepIndex;
  final LandingUsageGuideStep step;

  /// Ví dụ: "Tiêu đề", "Từ khóa", "Nội dung".
  final String matchedIn;

  String get sectionLabel => LandingGuideData.labelForIndex(sectionIndex);
}

/// Ảnh minh họa dựng từ màn hình thật (test/guide_shots, scripts/render-guide-shots.ps1),
/// hiện ngay dưới dòng «Bước [afterBullet]». Mỗi ảnh có bản máy tính `<name>.webp`
/// và bản điện thoại `<name>-mobile.webp` trong web/images/guide.
class GuideShot {
  const GuideShot(this.name, {required this.afterBullet, required this.caption});

  final String name;

  /// Số thứ tự dòng bước (1 = dòng đầu) mà ảnh đứng ngay dưới.
  final int afterBullet;

  /// Giải thích các số ①②③ trên ảnh.
  final String caption;

  static const _origin = 'https://sboxhrm.com';

  /// Đường dẫn ảnh; app cài trên máy lấy từ sboxhrm.com, bản web lấy cùng tên miền.
  String url({required bool mobile, required bool web}) =>
      '${web ? '' : _origin}/images/guide/$name${mobile ? '-mobile' : ''}.webp';
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
    this.shots = const [],
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

  /// Ảnh minh họa theo từng dòng bước (không chỉnh từ CMS — đi kèm giao diện app).
  final List<GuideShot> shots;

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
      shots: shots,
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
    this.industry = const [],
  });

  final List<LandingUsageGuideStep> basic;
  final List<LandingUsageGuideStep> advanced;
  final List<LandingUsageGuideStep> pos;
  /// Hướng dẫn theo ngành hàng (bán lẻ, F&B, karaoke, salon, gym, khách sạn).
  final List<LandingUsageGuideStep> industry;

  int get basicCount => basic.length;
  int get advancedCount => advanced.length;
  int get posCount => pos.length;
  int get industryCount => industry.length;

  List<LandingUsageGuideStep> stepsAt(int sectionIndex) => switch (sectionIndex) {
        1 => advanced,
        2 => pos,
        3 => industry,
        _ => basic,
      };

  static String keyForIndex(int sectionIndex) => switch (sectionIndex) {
        1 => 'advanced',
        2 => 'pos',
        3 => 'industry',
        _ => 'basic',
      };

  static int indexForKey(String section) => switch (section.trim().toLowerCase()) {
        'advanced' => 1,
        'pos' => 2,
        'industry' => 3,
        _ => 0,
      };

  static String labelForIndex(int sectionIndex) => switch (sectionIndex) {
        1 => 'Nâng cao',
        2 => 'POS',
        3 => 'Ngành hàng',
        _ => 'Triển khai',
      };

  static bool isKnownSection(String section) {
    final k = section.trim().toLowerCase();
    return k == 'basic' || k == 'advanced' || k == 'pos' || k == 'industry';
  }

  Map<String, dynamic> toJson() => {
        'basic': basic.map((e) => e.toJson()).toList(),
        'advanced': advanced.map((e) => e.toJson()).toList(),
        'pos': pos.map((e) => e.toJson()).toList(),
        'industry': industry.map((e) => e.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  static LandingGuideData get defaults => LandingGuideData(
        basic: _withKeywords(LandingUsageGuide.basicSteps, _basicKeywords),
        advanced:
            _withKeywords(LandingUsageGuide.advancedSteps, _advancedKeywords),
        pos: _withKeywords(LandingUsageGuide.posSteps, _posKeywords),
        industry: _withKeywords(landingIndustrySteps, landingIndustryKeywords),
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
    scan(3, industry);
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
      industry: base.industry,
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
      industry: _mergeStepList(base.industry, map['industry']),
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
        'Cài đặt → Phòng ban: tạo các bộ phận (Kế toán, Bếp, Thu ngân…)',
        'Cài đặt → Chức vụ: tạo chức danh (Quản lý, Nhân viên, Thu ngân…)',
        'Nếu có nhiều điểm bán: Cài đặt → Chi nhánh / cửa hàng con (khi gói hỗ trợ)',
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
      accent: SboxColors.brand600,
      shots: [
        GuideShot('salary-1', afterBullet: 1, caption: '① Chọn nhân viên cần thiết lập; người chưa có lương hiện nhãn «Chưa thiết lập».'),
        GuideShot('salary-2', afterBullet: 2, caption: '① Loại lương: tháng, ngày, ca hoặc giờ. ② Lương cơ bản và lương hoàn thành.'),
        GuideShot('salary-3', afterBullet: 4, caption: '① Chọn cách chấm công (chấm vào và ra, chỉ chấm vào…). ② Các ca được áp dụng; để trống là theo lịch phân ca.'),
      ],
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
        'Bước 3 — Bật Cloud / ADMS theo hướng dẫn trên máy; lưu và khởi động lại nếu máy yêu cầu',
        'Bước 4 — Trên SBOX: Cài đặt → Máy chấm công → Thêm máy (nhập SN hoặc quét mã)',
        'Bước 5 — Kiểm tra trạng thái Online trên danh sách máy (có thể mất 1–2 phút)',
        'Bước 6 — Cho NV chấm thử → mở Chấm công thô xác nhận có ATTLOG',
        'Bước 7 — Nếu Offline: kiểm tra mạng cửa hàng cho máy ra internet (HTTPS/ADMS) hoặc gọi hotline',
      ],
      tip:
          'Chưa kết nối được? Gọi hotline 0973 024 042 — hỗ trợ từ xa qua Zalo.',
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
        'Menu: Nhân sự chấm công',
        'Chọn máy → Đồng bộ / đẩy nhân viên từ Hồ sơ nhân sự xuống thiết bị',
        'Trên máy: đăng ký vân tay hoặc khuôn mặt cho từng mã NV',
        'Cho NV chấm thử → mở Chấm công thô xác nhận có giờ vào/ra và đúng tên',
        'Thêm NV mới giữa kỳ: thêm hồ sơ → đồng bộ lại máy → đăng ký vân tay',
        'Xóa/khóa user trên máy khi NV nghỉ (tránh chấm nhầm)',
      ],
      tip:
          'Nếu log hiện PIN lạ: kiểm tra mã trên máy và mã trong hồ sơ có trùng không.',
      accent: SboxColors.successText,
      shots: [
        GuideShot('device-users-1', afterBullet: 2, caption: '① Nút «Tải hồ sơ NS» (điện thoại: trong nút «…» góc dưới) đẩy nhân viên xuống máy. ② Thẻ «NV chưa có trên máy»: số nhân viên chưa đồng bộ. ③ Cột vân tay / khuôn mặt bằng 0 là chưa đăng ký, chưa chấm công được.'),
        GuideShot('device-users-2', afterBullet: 2, caption: '① Chọn máy chấm công. ② Tích chọn nhân viên cần tải xuống (hoặc «Chọn tất cả»). ③ Bấm «Tải N nhân viên».'),
        GuideShot('device-users-3', afterBullet: 3, caption: '① Số vân tay nhân viên đã đăng ký. ② Chọn ngón tay rồi bấm Đăng ký / Xóa. ③ Ngón màu xanh là đã có vân tay.'),
      ],
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
      shots: [
        GuideShot('mobile-attendance-1', afterBullet: 1, caption: '① Bật cách xác thực: khuôn mặt, GPS, Wi-Fi công ty. ② Khi bật nhiều cách: chỉ cần đạt 1 hay phải đạt tất cả.'),
        GuideShot('mobile-attendance-2', afterBullet: 2, caption: '① Thêm vị trí chấm công. ② Mỗi vị trí có địa chỉ, bán kính, Wi-Fi và số nhân viên được chấm.'),
        GuideShot('mobile-attendance-3', afterBullet: 3, caption: '① Cấp quyền cho điện thoại nhân viên. ② Máy mới đăng ký hiện «Chờ duyệt». ③ Bấm dấu xanh để duyệt, dấu đỏ để từ chối.'),
      ],
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
      accent: SboxColors.brand600,
      shots: [
        GuideShot('employee-account-1', afterBullet: 1, caption: '① Bấm «Thêm tài khoản».'),
        GuideShot('employee-account-2', afterBullet: 2, caption: '① Liên kết hồ sơ nhân viên, form tự điền tên và SĐT. ② Thông tin đăng nhập: họ tên, email, mật khẩu.'),
        GuideShot('employee-account-3', afterBullet: 3, caption: '① Chọn vai trò (Quản lý, Kế toán, Thu ngân…). ② Với thu ngân / order: chọn khu vực bán hàng được xem.'),
      ],
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
      shots: [
        GuideShot('first-payroll-1', afterBullet: 4, caption: '① Chọn kỳ lương (từ ngày đến ngày). ② Lọc theo phòng ban hoặc nhân viên.'),
        GuideShot('first-payroll-2', afterBullet: 5, caption: '① Rà từng nhân viên: công, giờ, tăng ca, thu nhập, khấu trừ. ② Số thực nhận cuối cùng.'),
        GuideShot('first-payroll-3', afterBullet: 7, caption: '① Kiểm tra xong thì bấm «Chốt lương» để khóa kỳ.'),
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
        'Bước 1 — NV vào menu Nghỉ phép → tạo đơn (loại phép, từ ngày–đến ngày, lý do)',
        'Bước 2 — Gửi đơn; quản lý nhận thông báo trên web/app',
        'Bước 3 — Quản lý duyệt / từ chối / hủy đơn',
        'Bước 4 — Kiểm tra số ngày phép còn lại (nếu cấu hình quỹ phép)',
        'Bước 5 — Đối chiếu Tổng hợp chấm công: phép đã duyệt không tính nghỉ không phép',
        'Bước 6 — Xem Báo cáo → Báo cáo nghỉ phép; mở hướng dẫn pháp lý trên màn Nghỉ phép khi cần',
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
        'Cài đặt → Bảo hiểm: mức đóng, tỷ lệ công ty / người lao động',
        'Cài đặt → Thuế TNCN: biểu thuế / giảm trừ (theo cấu hình cửa hàng)',
        'Người phụ thuộc: Cài đặt → Thuế TNCN → mục «Người phụ thuộc của nhân viên»; tham gia BH bật trên Thiết lập lương từng NV',
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
        'Cài đặt → Phạt: các bậc phút và số tiền; phạt quên chấm / nghỉ không phép',
        'Ân hạn phút nằm trên từng ca (Thiết lập ca), không chỉ ở màn Phạt',
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
        'Cài đặt → Lương sản phẩm: nhóm SP, đơn giá, bậc thang',
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
        'Cài đặt → Thông báo: bật / tắt từng loại hoặc cả nhóm (tự lưu)',
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
      title: 'Thiết lập SBOX lần đầu cho POS',
      desc:
          'Làm đúng thứ tự: ngành hàng → thông tin cửa hàng → hàng hóa → bàn (F&B) → máy in → bán thử.',
      bullets: [
        'Bước 1 — Thiết lập SBOX → Ngành hàng & cách bán: chọn retail / nhà hàng / salon / phòng…',
        'Bước 2 — Thiết lập SBOX → Thông tin cửa hàng: tên, địa chỉ, VAT, tài khoản VietQR (nếu thanh toán QR)',
        'Bước 3 — Menu Hàng hóa: danh mục + món/SP (mã, giá, đơn vị, ảnh)',
        'Bước 4 — F&B: Cài đặt → Quản lý bàn / phòng: khu vực, bàn, sức chứa',
        'Bước 5 — Cài đặt → Máy in + Mẫu in (xem bước Máy in bên dưới)',
        'Bước 6 — Phân quyền tài khoản thu ngân / quản kho / quản lý',
        'Bước 7 — Mở Bán hàng, tạo 1 đơn test, in thử, thanh toán 0đ hoặc hủy theo quyền',
      ],
      tip:
          'Sai ngành hàng thì không thấy sơ đồ bàn / gửi bếp. Đổi ngành xong mở lại Bán hàng.',
      accent: Color(0xFFEF6C00),
      shots: [
        GuideShot('pos-setup-1', afterBullet: 1, caption: '① Chọn ngành hàng (vd Nhà hàng / Cafe) — đổi ngành lưu ngay và bật sẵn cấu hình của ngành. ② Chế độ bán mặc định: bán nhanh, bán thường hoặc giao hàng.'),
        GuideShot('pos-setup-2', afterBullet: 2, caption: '① Tên cửa hàng, địa chỉ, SĐT in trên hóa đơn. ② Thuế VAT khi bán: giá đã gồm thuế hoặc thuế theo từng mặt hàng.'),
      ],
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
        'Combo: khai báo thành phần (bán combo trừ kho từng thành phần; bật «Quản lý tồn kho combo» nếu combo có tồn riêng)',
        'Món pha chế / nấu: khai báo «Hàng thành phần — định lượng» để bán món tự trừ nguyên liệu; topping gắn món cũng trừ kho',
        'Nhiều ĐVT (lon / lốc / thùng): khai báo quy đổi — bán, nhập theo ĐVT nào cũng quy về ĐVT cơ bản',
        'Tồn ban đầu nhập ở form hàng hóa được ghi «Tồn đầu kỳ» vào Thẻ kho; sau đó chỉnh tồn bằng Nhập hàng / Kiểm kho',
        'Ngừng kinh doanh: tắt bán thay vì xóa — giữ lịch sử hóa đơn',
        'Giá thay đổi: sửa trên Hàng hóa; đơn đang mở giữ giá lúc thêm món',
        'Dịch vụ: mục «Tính giờ / gói buổi» — giá cố định, theo giờ / phút / block / ngày, gói nhiều buổi, gói giờ đếm ngược (xem tab Ngành hàng)',
        'Mục «Hoa hồng nhân viên»: % hoặc tiền cố định; gói liệu trình chọn tính 1 lần khi bán hay mỗi buổi làm',
      ],
      tip: 'Mã hàng nên ngắn, không dấu — dễ gõ và in tem.',
      accent: Color(0xFF00897B),
      shots: [
        GuideShot('pos-products-1', afterBullet: 1, caption: '① Bấm «Tạo mới» (điện thoại: nút + góc dưới) để thêm hàng. ② Tìm theo mã / tên hàng. ③ Mỗi dòng: mã, tên, giá bán, tồn.'),
        GuideShot('pos-products-2', afterBullet: 1, caption: '① Chạm khung ảnh để chụp / chọn ảnh món. ② Nhập mã hàng và tên. ③ Chọn nhóm hàng. ④ Giá vốn, giá bán.'),
      ],
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
        'Phòng tính giờ: chạm giữ ô phòng → Tạm dừng tính giờ / Chốt tiền giờ / Mở chốt giờ',
        'Menu Đặt lịch: tạo lịch theo ngày–giờ–dịch vụ–khách (salon, phòng)',
        'Đặt bàn F&B: chọn giờ, số khách, bàn — đổi trạng thái khi khách đến',
      ],
      tip: 'Bàn «đang dùng» phải thanh toán hoặc trả bàn trước khi gán khách mới.',
      accent: Color(0xFF6A1B9A),
      shots: [
        GuideShot('pos-tables-1', afterBullet: 1, caption: '① Quản lý nhóm (khu: Tầng 1, Sân vườn…), tạo bàn nhanh, thêm bàn. ② Bàn đang dùng hiện số phút, tiền tạm tính, số khách.'),
        GuideShot('pos-tables-2', afterBullet: 3, caption: '① Chạm giữ bàn đang dùng: Chuyển bàn, Tách bàn, Gộp bàn vào đây.'),
      ],
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
        'Hóa đơn A4 / hợp đồng: «Tải file Word của bạn» (.docx) — giữ nguyên mẫu gốc, gắn trường dữ liệu ngay trên bản xem',
        'Một máy có thể vừa hóa đơn vừa bếp nếu gắn 2 mẫu / 2 máy vật lý khác nhau',
        'Đơn đã xuất HĐĐT: hóa đơn in tự thêm khối HĐĐT (ký hiệu, số, mã CQT, mã tra cứu, QR tra cứu). Mẫu tự thiết kế dùng biến {HDDT_So} {HDDT_Ky_Hieu} {HDDT_Ma_CQT} {HDDT_Ma_Tra_Cuu} {HDDT_Link_Tra_Cuu}',
      ],
      tip:
          'A6 và A7 cùng cửa hàng phải thấy cùng mẫu mặc định. Nếu lệch: vào Mẫu in, chọn lại mặc định của store — không copy tay từ máy khác.',
      accent: Color(0xFF0277BD),
      shots: [
        GuideShot('pos-printers-1', afterBullet: 1, caption: '① Tab «Trên máy này» (máy USB / Bluetooth / LAN tại quầy) hoặc «Máy in cloud» (dùng chung cả cửa hàng). ② Bật «In hóa đơn khi thanh toán». ③ Chọn máy in hóa đơn. ④ Chọn mẫu in hóa đơn.'),
        GuideShot('pos-printers-2', afterBullet: 3, caption: '① Chọn loại mẫu: hóa đơn, phiếu bếp («Báo chế biến»), tem. ② «Dùng mẫu này» để đặt làm mẫu mặc định. ③ In thử.'),
      ],
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
      shots: [
        GuideShot('pos-kitchen-1', afterBullet: 1, caption: '① Chạm giữ bàn đang mở: xem số khách, tiền, số món. ② «Báo chế biến» gửi các món chưa báo xuống bếp / bar.'),
        GuideShot('pos-kitchen-2', afterBullet: 2, caption: '① Bàn còn món chưa báo bếp hiện số «bếp» ngay trên ô bàn.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_sales',
      icon: Icons.point_of_sale_rounded,
      title: 'Quy trình bán hàng',
      desc:
          'Mỗi đơn: chọn hàng (hoặc bàn) → chỉnh SL / giảm giá → chọn khách (nếu cần) → thanh toán → in hóa đơn → (tuỳ) HĐĐT. Kho chỉ bị trừ lúc thanh toán.',
      bullets: [
        'Bước 1 — Mở Bán hàng (app HRM / web) hoặc app POS (máy A6). Nếu cửa hàng bật «Ca thu ngân»: Menu ⋮ → Ca thu ngân → Mở ca trước',
        'Bước 2 — Bán lẻ: quét mã / chọn hàng. Nhà hàng: chọn bàn → gọi món → Gửi bếp',
        'Bước 3 — Sửa số lượng, ghi chú, topping; chiết khấu / đổi giá cần quyền duyệt PosSell',
        'Bước 4 — Chọn khách hàng nếu cần tích điểm, ghi công nợ, hoặc xuất HĐĐT có MST (thông tin công ty / MST / email lấy từ hồ sơ khách)',
        'Bước 5 — Thanh toán: tiền mặt / chuyển khoản / VietQR / nhiều hình thức. Chip «In hóa đơn», «Xuất HĐĐT» chọn ngay trên màn thanh toán',
        'Bước 6 — Sau khi thanh toán màn hình báo kết quả HĐĐT: «Đã xuất» (chạm để gửi cho khách), «Chưa xuất được» (kèm lý do) hoặc «Chờ ký»',
        'Mất mạng lúc bấm Thanh toán: cứ bấm lại — hệ thống nhận ra cùng đơn, không tạo đơn / trừ kho / thu tiền hai lần',
        'Đơn hàng: tra cứu, in lại, hủy (đúng quyền). Trả hàng: menu «Trả hàng bán», chọn đơn gốc và số lượng trả',
      ],
      tip:
          'Thanh toán cần quyền Duyệt (Approve) module PosSell. Tài khoản phục vụ chỉ có quyền tạo đơn thì order / gửi bếp được nhưng không thu tiền.',
      accent: Color(0xFFE65100),
      shots: [
        GuideShot('pos-sales-1', afterBullet: 2, caption: '① Tìm / quét mã hàng. ② Chạm món để thêm vào hóa đơn (điện thoại: «Chọn hàng»). ③ Sửa số lượng bằng − / +. ④ Thanh toán (F9).'),
        GuideShot('pos-sales-2', afterBullet: 5, caption: '① Chọn hình thức: tiền mặt, chuyển khoản, tiền mặt + CK hoặc ghi nợ. ② Chip «In hóa đơn» để in khi thanh toán. ③ Hoàn tất thanh toán (F9).'),
      ],
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
      accent: SboxColors.brand600,
      shots: [
        GuideShot('pos-customers-1', afterBullet: 1, caption: '① Bấm «Thêm khách» (SĐT làm mã nhanh). ② Mỗi khách: mã, SĐT, tổng mua, công nợ.'),
        GuideShot('pos-customers-2', afterBullet: 3, caption: '① Công nợ hiện tại của khách. ② «Thu nợ» khi khách trả tiền nợ.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_inventory',
      icon: Icons.warehouse_rounded,
      title: 'Kho: nhập, xuất, kiểm kê',
      desc:
          'Tồn tăng khi nhập NCC hoàn thành, trả hàng bán, hủy đơn; giảm khi thanh toán đơn, xuất hủy, xuất dùng nội bộ, trả hàng nhập. Mọi biến động ghi vào Thẻ kho.',
      bullets: [
        'Nhập hàng: menu «Nhập hàng NCC» → thêm hàng, SL, giá nhập (hàng có lô: nhập số lô + HSD) → Hoàn thành. Phiếu tạm chưa cộng tồn',
        'Giá vốn tính bình quân gia quyền mỗi lần nhập. Hủy phiếu nhập: trừ lại tồn và trả giá vốn về như trước (cần còn đủ tồn để trừ)',
        'Trả hàng cho NCC: menu «Trả hàng nhập» — giảm tồn, giảm công nợ NCC',
        'Xuất hủy (hàng hỏng, hết hạn) / Xuất dùng nội bộ: tạo phiếu → Hoàn thành mới trừ tồn; Hủy phiếu thì cộng lại',
        'Kiểm kho: tạo phiếu → thêm hàng → NHẬP SỐ ĐẾM NGAY KHI ĐẾM (hệ thống chốt tồn sổ lúc nhập) → Hoàn thành để cân bằng',
        'Khi cân bằng chỉ cộng / trừ phần chênh lệch (số đếm − tồn sổ lúc đếm), nên hàng bán sau lúc đếm vẫn được giữ đúng',
        'Xem lịch sử từng mặt hàng: Hàng hóa → chọn hàng → Thẻ kho (ai, lúc nào, chứng từ nào, tồn sau giao dịch)',
        'Báo cáo POS → Tồn kho / Nhập hàng / Hàng sắp hết hạn để theo dõi tổng',
      ],
      tip:
          'Muốn chỉnh tồn cho đúng thực tế: dùng Kiểm kho (có chứng từ, có chênh lệch). Sửa ô tồn trong form Hàng hóa chỉ nên dùng lúc khai báo ban đầu.',
      accent: Color(0xFF5D4037),
      shots: [
        GuideShot('pos-inventory-1', afterBullet: 1, caption: '① Tạo phiếu nhập. ② Phiếu tạm: chưa cộng tồn. ③ «Nhập hàng vào kho» (điện thoại: «Hoàn thành nhập») mới cộng tồn và công nợ NCC.'),
        GuideShot('pos-inventory-2', afterBullet: 5, caption: '① Tồn sổ, số thực tế đếm được, số lệch và giá trị lệch từng mặt hàng. ② «Cân bằng kho» để cộng / trừ phần chênh lệch.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_stock_rules',
      icon: Icons.rule_rounded,
      title: 'Nguyên tắc tồn kho (bán, giữ chỗ, bán âm)',
      desc:
          'Tồn kho là số thực có trong kho. Tồn khả dụng = tồn kho − phần đang giữ chỗ cho bàn / đơn tạm / đơn online chưa thanh toán.',
      bullets: [
        'Đơn tạm, bàn đang mở, đơn QR / online chưa hoàn tất: CHƯA trừ kho, chỉ giữ chỗ — bàn khác không bán được phần đã giữ',
        'Thanh toán (quầy), xác nhận COD hoặc nhận chuyển khoản Tingee (đơn online): nhả giữ chỗ và trừ kho thật',
        'Combo: trừ từng thành phần; bật «Quản lý tồn kho combo» nếu muốn trừ thêm chính combo. Món có định lượng: trừ nguyên liệu. Topping: trừ theo SL món × SL topping',
        'Bán theo ĐVT lớn (thùng, lốc): tự quy về ĐVT cơ bản. Hàng dịch vụ không trừ kho',
        'Hàng «Theo dõi lô / HSD»: bán / xuất lô hết hạn sớm nhất trước (FEFO)',
        'Bán âm: Thiết lập SBOX → Ngành hàng & cách bán → «Cho phép bán khi hết hàng / tồn âm». Tắt: chặn thêm món / thanh toán khi tồn khả dụng không đủ. Bật: vẫn bán, tồn có thể âm (hàng có lô: phần thiếu ghi không lô)',
        'Phiếu xuất hủy / nội bộ không được xuất quá tồn thực, và (khi tắt bán âm) không được lấy phần đang giữ chỗ cho bàn',
        '«Phiếu xuất kho / báo kho» in từ màn bán hàng chỉ là phiếu soạn hàng cho kho — KHÔNG trừ kho lần hai',
        'Hủy đơn đã thanh toán: hoàn đúng số lượng về kho (đúng lô). Đơn đã có trả hàng thì không hủy được — dùng Trả hàng bán',
        'Hai người cùng lúc sửa cùng mặt hàng (vd. đang bán thì kho nhập): một bên nhận thông báo «Tồn kho vừa được thay đổi… thao tác lại» — hệ thống không ghi đè sai số tồn',
        'Giữ chỗ tồn tự đối soát lại với các đơn đang mở mỗi đêm (3 giờ sáng)',
      ],
      tip:
          'Tồn âm thường do: bán trước khi nhập, combo / định lượng khai sai thành phần, hoặc đã bật bán âm. Nhập bù hoặc kiểm kho để đưa về đúng.',
      accent: Color(0xFF4E342E),
    ),
    LandingUsageGuideStep(
      id: 'pos_einvoice',
      icon: Icons.request_quote_rounded,
      title: 'Hóa đơn điện tử: kết nối & xuất',
      desc:
          'Kết nối Viettel SInvoice, Easy Invoice, MISA meInvoice hoặc VNPT Invoice. Xuất ngay khi thanh toán hoặc xuất sau từ danh sách đơn.',
      bullets: [
        'Thiết lập SBOX → Hóa đơn điện tử → chọn Nhà cung cấp, nhập thông tin do hãng cấp:',
        '• Viettel: tài khoản API, MST, mẫu (1/001), ký hiệu (C26TAA)',
        '• Easy Invoice: tài khoản API, MST, Pattern đúng như portal (vd. 1C26MAA), Serial thường để trống',
        '• MISA: AppID (MISA cấp khi đăng ký tích hợp), tài khoản meInvoice, MST, ký hiệu đầy đủ (1C26TAA); chọn ký HSM hoặc HĐ máy tính tiền',
        '• VNPT: địa chỉ web service riêng (https://<MST>-tt78admin.vnpt-invoice.com.vn), Account/ACpass web service, tài khoản phát hành, mẫu số, ký hiệu',
        'Lưu → «Kiểm tra kết nối» (chỉ xác thực, không tạo hóa đơn)',
        'Khi thanh toán: bật chip «Xuất HĐĐT». «Mặc định xuất hóa đơn» + tắt hỏi thu ngân = mọi đơn tự xuất (kể cả đơn online / Tingee)',
        'Khách cần HĐ công ty: chọn khách có tên công ty, MST, địa chỉ, email trước khi thanh toán',
        'Bill in ra có thêm khối HĐĐT: ký hiệu, số HĐ, mã CQT, mã tra cứu và mã QR để khách quét tra cứu (tắt được bằng «In mã tra cứu + QR trên hóa đơn bán hàng»)',
      ],
      tip:
          'Đơn vẫn thanh toán thành công dù HĐĐT lỗi — màn bán báo lỗi, vào Quản lý HĐĐT để xuất lại. MISA / VNPT chưa có lưu nháp qua API.',
      accent: Color(0xFF00695C),
      shots: [
        GuideShot('pos-einvoice-1', afterBullet: 1, caption: '① Chọn nhà cung cấp (Viettel, Easy, MISA, VNPT). ② Nhập tài khoản do hãng cấp: MST, ký hiệu mẫu (1/001), ký hiệu hóa đơn (C26TAA).'),
        GuideShot('pos-einvoice-2', afterBullet: 6, caption: '① Lưu rồi bấm «Kiểm tra» — chỉ xác thực tài khoản, không tạo hóa đơn. ② Kết quả hiện ngay bên dưới.'),
        GuideShot('pos-einvoice-3', afterBullet: 7, caption: '① Bật xuất hóa đơn điện tử. ② «Hỏi thu ngân lúc thanh toán» / «Mặc định xuất hóa đơn». ③ In mã tra cứu + QR trên hóa đơn bán hàng.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_einvoice_manage',
      icon: Icons.fact_check_rounded,
      title: 'Quản lý HĐĐT: xem, gửi, thay thế, hủy, đồng bộ',
      desc:
          'Mở từ Báo cáo POS → Hóa đơn điện tử, hoặc Cài đặt → Hóa đơn điện tử → Quản lý, hoặc menu HĐĐT của từng đơn trong Đơn hàng.',
      bullets: [
        'Xem lại hóa đơn (PDF lấy trực tiếp từ hãng) → in / tải về',
        'Gửi HĐĐT qua ứng dụng khác (Zalo, Messenger, Gmail…): đính kèm PDF + ký hiệu, số, mã tra cứu, link tra cứu',
        'Gửi bản nháp cho khách kiểm tra tên / MST / địa chỉ TRƯỚC khi phát hành (Viettel, Easy, MISA) — bản nháp chưa có giá trị pháp lý',
        'Gửi email: hãng gửi thư phát hành tới email khách (VNPT gửi tới email ghi trên hóa đơn)',
        'Thay thế: lập hóa đơn mới thay HĐ gốc, sửa được tên, công ty, MST, địa chỉ, email người mua. Thay thế lỗi thì HĐ gốc vẫn giữ nguyên',
        'Hủy: theo NĐ 70/2025, hóa đơn đã gửi CQT thường phải thay thế / điều chỉnh thay vì hủy — hãng có thể từ chối lệnh hủy',
        'Đồng bộ (từng đơn) / Đồng bộ hàng loạt (tối đa 100 đơn): cập nhật số HĐ, trạng thái đã hủy, mã CQT từ hãng',
        'Tải danh sách từ hãng (Viettel, Easy): đối chiếu với đơn POS, phát hiện HĐ lập ngoài POS hoặc hãng đã hủy mà POS chưa biết',
        'Trang quản lý của hãng: nút mở portal Viettel / Easy / MISA / VNPT (có thể nhập link riêng trong cấu hình)',
        'Báo cáo: tỷ lệ doanh thu đã xuất HĐĐT, thuế GTGT đã xuất, HĐ thay thế, biểu đồ theo ngày',
      ],
      tip:
          'Lỗi thường gặp: thiếu cấu hình, sai MST / mẫu / ký hiệu, MISA sai AppID, VNPT «ERR:20» (mẫu/ký hiệu), Easy «117» (mẫu máy tính tiền chưa mở API).',
      accent: Color(0xFF00796B),
      shots: [
        GuideShot('pos-einvoice-manage-1', afterBullet: 1, caption: '① Lọc theo trạng thái: tất cả, cần xử lý, đã xuất, lỗi… ② Chạm một hóa đơn để mở thao tác.'),
        GuideShot('pos-einvoice-manage-2', afterBullet: 2, caption: '① Xem lại hóa đơn (PDF). ② Gửi HĐĐT qua Zalo, email… ③ Thay thế hóa đơn. ④ Hủy hóa đơn.'),
        GuideShot('pos-einvoice-manage-3', afterBullet: 9, caption: '① Đồng bộ hàng loạt từ hãng. ② Tải danh sách từ hãng để đối chiếu. ③ Mở trang quản lý của hãng.'),
      ],
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
        'Báo cáo hủy / trả (menu riêng) · Thuế hộ kinh doanh',
        'Xuất Excel trên từng báo cáo khi gửi kế toán',
      ],
      tip:
          'Không thấy một thẻ báo cáo: thiếu quyền module PosReport… — tick trong Phân quyền / gói dịch vụ.',
      accent: SboxColors.brand600,
      shots: [
        GuideShot('pos-reports-1', afterBullet: 1, caption: '① Tìm nhanh báo cáo. ② Doanh thu theo ngày. ③ Kết quả kinh doanh (lãi / lỗ) trong nhóm Tài chính.'),
        GuideShot('pos-reports-2', afterBullet: 2, caption: '① Chọn kỳ báo cáo (hôm nay, tuần, tháng…). ② Xuất Excel gửi kế toán.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_eod',
      icon: Icons.nightlight_round,
      title: 'Ca thu ngân & tổng kết cuối ngày',
      desc:
          'Đối soát tiền mặt, QR, công nợ trong ca trước khi giao ca. Nếu bật «Ca thu ngân» thì mỗi thu ngân mở / đóng ca riêng và phải có ca mở mới thanh toán được.',
      bullets: [
        'Bật ca: Thiết lập SBOX → Ngành hàng & cách bán → «Ca thu ngân (mở ca / đóng két)»',
        'Đầu ca: màn bán hàng → Menu ⋮ → Ca thu ngân → Mở ca (nhập tiền đầu ca)',
        'Cuối ca: thanh toán / trả hết bàn đang mở (F&B), rồi đóng ca và đếm két',
        'Tổng kết cuối ngày: Báo cáo POS → Tổng kết cuối ngày, chọn khoảng ca',
        'Đối chiếu tiền mặt ngăn kéo với cột tiền mặt; chuyển khoản / QR với sao kê ngân hàng',
        'Ghi chi phí phát sinh (sổ quỹ / chi phí) trước khi in hoặc xuất file tổng kết',
      ],
      tip:
          'Lệch tiền: xem Đơn hàng trong ca + Báo cáo hủy / trả + Phương thức thanh toán trước khi «bù» tay vào quỹ.',
      accent: Color(0xFF37474F),
      shots: [
        GuideShot('pos-eod-1', afterBullet: 1, caption: '① Bật «Ca thu ngân (mở ca / đóng két)» trong Ngành hàng & cách bán.'),
        GuideShot('pos-eod-2', afterBullet: 2, caption: '① Nhập tiền mặt đầu ca trong két. ② Bấm «Mở ca» — mở ca rồi mới thanh toán được.'),
        GuideShot('pos-eod-3', afterBullet: 3, caption: '① Tiền mặt kỳ vọng = đầu ca + tiền mặt thu trong ca. ② Nhập tiền mặt đếm được. ③ Bấm «Đóng ca».'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_common',
      icon: Icons.support_agent_rounded,
      title: 'Tình huống POS thường gặp',
      desc:
          'Xử lý nhanh khi không in được, không thanh toán được, lệch tồn, HĐĐT lỗi.',
      bullets: [
        'Không in hóa đơn: máy in Online? Mẫu hóa đơn đã đặt mặc định cho cửa hàng? In thử từ Cài đặt → Mẫu in',
        'In được HĐ nhưng không in bếp: gán máy + mẫu phiếu bếp riêng; gửi bếp trước khi thanh toán',
        'A6 in khác A7: cùng cửa hàng — vào Mẫu in chọn lại mặc định (mẫu theo cửa hàng, không copy tay)',
        'Màn hình phụ A6 trắng: rút cáp ADB / USB debug rồi mở lại POS',
        'Không thanh toán được: thiếu quyền Duyệt PosSell, hoặc cửa hàng bật Ca thu ngân mà chưa mở ca',
        '«Không đủ tồn kho»: tồn khả dụng đã bị bàn / đơn tạm khác giữ chỗ — thanh toán / hủy bớt đơn đó, nhập thêm hàng, hoặc bật bán âm',
        '«Tồn kho vừa được thay đổi… thao tác lại»: có người khác vừa bán / nhập cùng mặt hàng — bấm lại là được',
        'Tồn âm: bán trước khi nhập, combo / định lượng khai sai, hoặc đang bật bán âm → nhập bù hoặc Kiểm kho',
        'Xem ai đã bán / trừ kho: Thẻ kho của mặt hàng (người thao tác, chứng từ); ai sửa / xóa đơn: Lịch sử thao tác (30 ngày)',
        'HĐĐT lỗi sau thanh toán: đơn vẫn hợp lệ — mở Quản lý HĐĐT xem lý do, sửa cấu hình rồi «Phát hành / xuất lại»',
        'HĐĐT «Chờ ký / chờ số»: tài khoản chưa gắn chữ ký số trên hãng — ký trên portal hãng rồi bấm Đồng bộ',
        'Bàn không hiện: ngành hàng chưa phải F&B, hoặc chưa tạo khu / bàn',
        'Tiền giờ vẫn tăng khi khách đã xin tính tiền: dùng Chốt tiền giờ trên sơ đồ phòng',
      ],
      tip: 'Hotline 0973 024 042 (Zalo hỗ trợ từ xa) khi máy in Agent USB không nhận lệnh in.',
      accent: Color(0xFF6D4C41),
    ),
    LandingUsageGuideStep(
      id: 'pos_rules',
      icon: Icons.gavel_rounded,
      title: 'Nguyên tắc chung của phần mềm',
      desc:
          'Các quy tắc hệ thống luôn áp dụng — giúp số liệu doanh thu, kho, công nợ và hóa đơn khớp nhau.',
      bullets: [
        'Chứng từ có 2 trạng thái: Tạm (sửa / xóa được, chưa ảnh hưởng kho / quỹ) và Hoàn thành (đã ghi sổ). Muốn đảo ngược thì Hủy — không sửa chứng từ đã hoàn thành',
        'Không xóa dữ liệu đã phát sinh: hàng ngừng bán thì tắt bán; đơn sai thì hủy / trả hàng — lịch sử luôn được giữ',
        'Mọi thay đổi tồn đều có dòng Thẻ kho (loại giao dịch, số chứng từ, người thao tác); mọi sửa / xóa đơn có trong Lịch sử thao tác',
        'Doanh thu ghi nhận khi đơn hoàn tất; hủy đơn gỡ doanh thu, hoàn kho, hoàn điểm / voucher / công nợ khách',
        'Giá trên đơn là giá lúc thêm món; đổi giá hàng hóa không làm đổi đơn cũ',
        'Quyền: Xem / Tạo / Sửa / Duyệt theo từng module (Phân quyền). Thanh toán, đổi giá, chiết khấu, hủy cần quyền Duyệt',
        'Mỗi cửa hàng có dữ liệu riêng: hàng hóa, kho, mẫu in, máy in, cấu hình HĐĐT không dùng chung giữa cửa hàng',
        'Bấm lại khi mạng chập chờn là an toàn: đơn / phiếu gửi trùng được nhận ra, không ghi hai lần',
        'HĐĐT là chứng từ thuế của hãng: POS lưu trạng thái, số, mã tra cứu; sai sót xử lý bằng thay thế / điều chỉnh theo quy định',
      ],
      tip:
          'Cuối mỗi tháng nên: kiểm kho các mặt hàng chính, đồng bộ HĐĐT hàng loạt, xem báo cáo tỷ lệ xuất HĐĐT và lợi nhuận.',
      accent: Color(0xFF455A64),
    ),
  ];

  @Deprecated('Use LandingGuideData.defaults.basic')
  static List<LandingUsageGuideStep> get steps => basicSteps;

  @Deprecated('Use LandingGuideData.defaults.basicCount')
  static int get stepCount => basicSteps.length;
}
