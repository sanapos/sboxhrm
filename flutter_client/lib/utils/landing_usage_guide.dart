import 'dart:convert';

import 'package:flutter/material.dart';

import 'landing_industry_guide.dart';

import 'device_setup_guide.dart';

import '../theme/sbox_tokens.dart';
/// Bài hướng dẫn phần SBOX HRM (triển khai, nâng cao) — `lib/main.dart` gắn, bản SBOX Bán Hàng không gắn.
/// Trợ lý AI đọc bài hướng dẫn để trả lời, nên chữ trong đó bị biên dịch thẳng vào gói: 228 lượt nhắc
/// chấm công / lương, đúng thứ Apple quét thấy khi từ chối theo điều 2.5.19.
List<LandingUsageGuideStep> Function()? hrmGuideBasicSteps;
List<LandingUsageGuideStep> Function()? hrmGuideAdvancedSteps;
Map<String, List<String>> Function()? hrmGuideKeywords;

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
        basic: _withKeywords(hrmGuideBasicSteps?.call() ?? const [], hrmGuideKeywords?.call() ?? const {}),
        advanced: _withKeywords(
            hrmGuideAdvancedSteps?.call() ?? const [], hrmGuideKeywords?.call() ?? const {}),
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



  static const _posKeywords = <String, List<String>>{
    'pos_quotes': ['báo giá', 'hợp đồng', 'nghiệm thu', 'cọc', 'VAT', 'gửi báo giá'],
    'pos_booking': ['đặt bàn', 'đặt phòng', 'đặt lịch', 'lịch hẹn', 'cọc', 'không đến', 'tự xếp thợ'],
    'pos_customer_display': ['màn hình phụ', 'màn hình khách', 'màn thứ 2', 'QR', 'quảng cáo'],
    'pos_shipping': ['giao hàng', 'vận đơn', 'GHN', 'GHTK', 'Viettel Post', 'COD', 'in tem'],
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

  /// Nâng cao: chính sách chuyên sâu, vận hành HRM, hiện trường (POS xem tab POS).

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
        'Bước 2 — Thiết lập SBOX → Thông tin cửa hàng: tên, địa chỉ, SĐT in trên hóa đơn. Thuế VAT khi bán đặt ở «Hóa đơn điện tử»; tài khoản VietQR ở «Tài khoản nhận tiền»',
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
        GuideShot('pos-setup-2', afterBullet: 2, caption: '① Tên cửa hàng, địa chỉ, SĐT in trên hóa đơn. Thuế VAT khi bán nay đặt ở «Hóa đơn điện tử».'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_products',
      icon: Icons.inventory_2_rounded,
      title: 'Thêm hàng hóa',
      desc:
          'Danh mục bán nằm ở menu POS → Hàng hóa. Mỗi mặt hàng có mã / mã vạch, nhóm, nhà cung cấp, giá vốn – giá bán và tồn kho. Giá trên hóa đơn lấy từ đây (hoặc bảng giá nếu cửa hàng dùng).',
      bullets: [
        'Bước 1 — Menu POS → Hàng hóa → «Tạo mới» (điện thoại: nút + góc dưới). Danh sách hiện mã, tên, giá bán, tồn; tìm theo mã hoặc tên',
        'Bước 2 — Nhập «Tên hàng *», chọn «Nhóm hàng», chạm khung «Chụp hoặc chọn ảnh» để thêm ảnh, nhập «Giá vốn» và «Giá bán»',
        'Bước 3 — Bán lẻ: nhập «Mã hàng» và «Mã vạch» (gõ hoặc bấm biểu tượng quét), chọn «Nhà cung cấp». Không thấy ô nào thì bấm nút Tùy chọn hiển thị form (góc trên) để bật mục',
        'Bước 4 — Mục «Tồn kho»: ô «Tồn kho» là tồn đầu kỳ (ghi vào Thẻ kho); «Định mức tồn thấp nhất / cao nhất» để báo hàng sắp hết. Sau khi lưu, tồn chỉ đổi qua Nhập hàng / Kiểm kho / bán',
        'Bước 5 — Bấm «Lưu» (hoặc «Lưu & tạo thêm» để nhập liên tiếp). Bỏ tích «Bán trực tiếp» nếu hàng không hiện trên màn bán',
        'Bước 6 — Ngừng kinh doanh: mở chi tiết hàng → bật «Ngừng kinh doanh» (ẩn khỏi mọi kênh bán) hoặc «Ẩn POS» (chỉ ẩn trên màn bán hàng). Không xóa hàng đã phát sinh hóa đơn — lịch sử vẫn giữ',
        'Bước 7 — Đổi giá: sửa trên hàng hóa; đơn đang mở giữ giá lúc thêm món, đơn cũ không đổi',
      ],
      tip:
          'Nhập hàng NCC ngay sau khi tạo hàng để giá vốn và lợi nhuận đúng; tồn đầu kỳ chỉ nhập một lần lúc tạo.',
      accent: Color(0xFF00897B),
      keywords: ['thêm hàng', 'tạo hàng hóa', 'mã vạch', 'barcode', 'tồn đầu kỳ', 'định mức tồn', 'ngừng kinh doanh', 'ẩn POS', 'nhà cung cấp'],
      shots: [
        GuideShot('pos-products-1', afterBullet: 1, caption: '① Bấm «Tạo mới» (điện thoại: nút + góc dưới) để thêm hàng. ② Tìm theo mã / tên hàng. ③ Mỗi dòng: mã, tên, giá bán, tồn.'),
        GuideShot('pos-products-2', afterBullet: 2, caption: '① Chạm khung ảnh để chụp / chọn ảnh món. ② Nhập mã hàng và tên. ③ Chọn nhóm hàng. ④ Giá vốn, giá bán.'),
        GuideShot('pos-products-3', afterBullet: 3, caption: '① Mã hàng và mã vạch (bấm biểu tượng để quét). ② Nhà cung cấp — «Quản lý» / «Tạo mới» ngay bên cạnh.'),
        GuideShot('pos-products-4', afterBullet: 4, caption: '① «Tồn kho»: số lượng đầu kỳ khi tạo hàng. ② Định mức tồn thấp nhất / cao nhất để báo sắp hết hàng.'),
        GuideShot('pos-products-5', afterBullet: 6, caption: '① «Ngừng kinh doanh»: ẩn hàng khỏi mọi kênh bán, giữ lịch sử. ② «Ẩn POS»: chỉ ẩn trên màn bán hàng.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_units',
      icon: Icons.straighten_rounded,
      title: 'Đơn vị tính & bảng giá',
      desc:
          'Một mặt hàng bán theo nhiều đơn vị (lon / lốc / thùng), mỗi đơn vị có giá và mã vạch riêng; tồn kho luôn quy về đơn vị cơ bản. Bảng giá cho giá riêng theo nhóm khách hoặc khoảng ngày.',
      bullets: [
        'Bước 1 — Mở hàng hóa → mục «Đơn vị tính cơ bản»: nhập «Tên đơn vị cơ bản *» là đơn vị nhỏ nhất quản lý tồn (vd Lon, Hộp, Kg)',
        'Bước 2 — Mục «Đơn vị quy đổi» → «Thêm đơn vị quy đổi»: mở «Thiết lập đơn vị tính và thuộc tính»',
        'Bước 3 — Bấm «Thêm đơn vị», nhập «Tên đơn vị» (Lốc, Thùng), số lượng quy đổi (= 6, = 24 Lon) và «Giá bán» riêng; bỏ tích «Bán trực tiếp» nếu đơn vị chỉ dùng khi nhập hàng',
        'Bước 4 — Bảng «Hàng cùng loại» bên dưới: mỗi đơn vị có Mã hàng, Mã vạch (mã thùng), Giá vốn, Giá bán riêng — quét mã thùng khi bán là thêm đúng 1 thùng. Bấm «Lưu»',
        'Bước 5 — Bán và nhập theo đơn vị nào cũng tự quy về đơn vị cơ bản (bán 1 thùng = trừ 24 lon)',
        'Bước 6 — Bảng giá: menu Hàng hóa → Bảng giá → «Thêm bảng giá» (giá sỉ, giá VIP, khuyến mãi). Biểu tượng bánh răng: đặt «Mặc định khi bán» và khoảng ngày áp dụng; biểu tượng sao chép: tạo bảng mới tăng / giảm %',
        'Bước 7 — Mở bảng giá: tìm / «Thêm nhiều SP», nhập giá từng dòng (theo từng đơn vị), «Chiết khấu nhanh» -5% / -10% / -5.000đ…, rồi «Lưu bảng giá». Hàng không có trong bảng vẫn bán theo giá gốc',
        'Bước 8 — Khi bán: chọn bảng giá ở ô «Bảng giá» trên màn Bán hàng; bảng «Mặc định» tự áp khi mở hóa đơn mới',
      ],
      tip:
          'Đặt đơn vị cơ bản là đơn vị nhỏ nhất ngay từ đầu — đổi sau khi đã có tồn sẽ làm sai số lượng.',
      accent: Color(0xFF00897B),
      keywords: ['đơn vị tính', 'ĐVT', 'quy đổi', 'lon lốc thùng', 'mã vạch thùng', 'bảng giá', 'giá sỉ', 'giá khuyến mãi', 'chiết khấu nhanh'],
      shots: [
        GuideShot('pos-units-1', afterBullet: 1, caption: '① Tên đơn vị cơ bản (đơn vị nhỏ nhất quản lý tồn). ② Các đơn vị quy đổi: 1 Lốc = 6 Lon, 1 Thùng = 24 Lon, mỗi đơn vị một giá. ③ «Thêm đơn vị quy đổi».'),
        GuideShot('pos-units-2', afterBullet: 3, caption: '① Đơn vị cơ bản. ② Từng đơn vị quy đổi: tên, số lượng quy đổi, giá bán. ③ «Thêm đơn vị». ④ Bảng hàng cùng loại: mã hàng, mã vạch, giá vốn, giá bán riêng cho từng đơn vị.'),
        GuideShot('pos-units-3', afterBullet: 6, caption: '① «Thêm bảng giá». ② Bảng «Mặc định» kèm khoảng ngày áp dụng. ③ Sao chép bảng giá / cài mặc định và khoảng ngày.'),
        GuideShot('pos-units-4', afterBullet: 7, caption: '① Tìm hoặc «Thêm nhiều SP» vào bảng. ② Giá riêng từng đơn vị (Thùng 375.000 so với gốc). ③ «Chiết khấu nhanh» cho nhiều dòng. ④ «Lưu bảng giá».'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_lots',
      icon: Icons.verified_rounded,
      title: 'Lô / HSD, bảo hành, hàng gia công',
      desc:
          'Các mục nâng cao của form hàng hóa: theo dõi lô và hạn dùng (đồ ăn uống, thuốc), bảo hành và seri (điện máy), hàng gia công tính theo kích thước (nhôm kính, nội thất), vị trí kho và trọng lượng.',
      bullets: [
        'Bước 1 — Form hàng hóa → nút Tùy chọn hiển thị form (góc trên): chọn bộ mục «Theo ngành hàng» hoặc tích từng mục («Bảo hành», «Số seri / IMEI khi bán», «Lô / hạn sử dụng», «Vị trí & trọng lượng», «Đơn vị / hàng cùng loại»…) → «Lưu»',
        'Bước 2 — Bảo hành: nhập «Thời hạn bảo hành (tháng)» — tính từ ngày bán; bật «Bắt buộc nhập seri máy khi bán» với hàng điện máy để mỗi đơn vị bán có seri riêng',
        'Bước 3 — Hạn dùng: bật «Theo dõi lô / HSD» (bắt buộc nhập HSD trên phiếu nhập hàng) và đặt «Cảnh báo trước HSD (ngày)»',
        'Bước 4 — Nhập hàng NCC: mỗi dòng hàng có lô nhập «Mã lô», chọn NSX và HSD (HSD bắt buộc) → Hoàn thành mới cộng tồn theo lô',
        'Bước 5 — Khi bán / xuất: lô hết hạn sớm nhất được trừ trước (FEFO); báo cáo «Hàng sắp hết hạn» theo số ngày cảnh báo',
        'Bước 6 — Hàng gia công: bật «Là hàng gia công» (báo giá nhập rộng × cao từng bộ), «Tính giá theo m²» (giá bán là đơn giá / m²) và «Giá tối thiểu mỗi bộ»',
        'Bước 7 — «Vị trí, trọng lượng»: chọn vị trí kho, nhập trọng lượng và kích thước đóng gói (Dài / Rộng / Cao cm) để ước tính cước vận chuyển',
      ],
      tip:
          'Hàng đã có dữ liệu (bảo hành, lô, vị trí…) thì mục tương ứng luôn hiện khi sửa, kể cả khi đang dùng form gọn.',
      accent: Color(0xFF00897B),
      keywords: ['lô', 'hạn sử dụng', 'HSD', 'NSX', 'FEFO', 'bảo hành', 'seri', 'IMEI', 'hàng gia công', 'nhôm kính', 'tính giá theo m2', 'vị trí kho', 'trọng lượng', 'tùy chọn form'],
      shots: [
        GuideShot('pos-lots-1', afterBullet: 1, caption: '① Tích các mục cần dùng: «Bảo hành», «Số seri / IMEI khi bán», «Lô / hạn sử dụng». ② «Lưu».'),
        GuideShot('pos-lots-2', afterBullet: 2, caption: '① Thời hạn bảo hành (tháng), tính từ ngày bán. ② Bắt buộc nhập seri máy khi bán.'),
        GuideShot('pos-lots-3', afterBullet: 3, caption: '① Bật «Theo dõi lô / HSD» — phiếu nhập bắt buộc nhập HSD. ② Số ngày cảnh báo trước khi hết hạn.'),
        GuideShot('pos-lots-5', afterBullet: 4, caption: '① Mã lô của dòng hàng trên phiếu nhập. ② Ngày sản xuất (NSX) và hạn sử dụng (HSD).'),
        GuideShot('pos-lots-4', afterBullet: 6, caption: '① «Là hàng gia công»: báo giá nhập rộng × cao từng bộ. ② «Tính giá theo m²». ③ Giá tối thiểu mỗi bộ.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_services',
      icon: Icons.timer_rounded,
      title: 'Dịch vụ & tính giờ',
      desc:
          'Dịch vụ không trừ kho: giá cố định (gội, cắt, massage lẻ), tính theo giờ / phút / block (karaoke, bi-a), theo ngày / đêm (khách sạn), gói nhiều buổi hoặc gói giờ đếm ngược.',
      bullets: [
        'Bước 1 — Hàng hóa → Tạo mới → Dịch vụ: nhập «Tên dịch vụ *», «Nhóm dịch vụ»; mở mục «Giá vốn, giá bán» nhập «Giá bán»',
        'Bước 2 — Giá cố định (gội, cắt, massage lẻ): mở «Tính giờ / gói buổi» → «Cách tính giá dịch vụ: Giá cố định», nhập «Thời lượng mặc định (phút)» để xếp lịch hẹn',
        'Bước 3 — Tính theo thời gian (karaoke, bi-a, phòng giờ): tích «Số lượng tính theo thời gian sử dụng?», nhập «Giá bán (1 giờ)», chọn «Giá tính theo» Giờ / Phút (khách sạn có thêm Ngày / đêm)',
        'Bước 4 — Làm tròn: «Block tính thời gian sử dụng dịch vụ (phút)» (vd 15) và «Tính tối thiểu (phút)»; giá riêng giờ đầu: «Số block giờ đầu tiên» + «Giá cho N block giờ đầu tiên». 0 block + có giá = phí mở bàn / mở phòng, cộng ngay khi mở',
        'Bước 5 — Giờ cao điểm: «Thiết lập khung giờ đặc biệt» → «Thêm khung giờ» để tăng / giảm giá theo khung; phút đầu miễn phí… ở «Tùy chọn nâng cao (ít dùng)»',
        'Bước 6 — Kiểm tra bảng «Xem trước: khách dùng bao lâu thì trả bao nhiêu» trước khi bấm Lưu',
        'Bước 7 — Gói nhiều buổi (liệu trình spa): «Cách tính giá dịch vụ: Theo buổi / liệu trình», nhập «Số buổi trong gói» và «Hạn gói (ngày)» — bán gói phải chọn khách',
        'Bước 8 — Gói giờ đếm ngược (vd gói hát 2 giờ): bỏ tích «Số lượng tính theo thời gian sử dụng?», nhập «Thời lượng gói (phút)», «Báo trước khi hết (phút)», chọn «Dịch vụ tính quá giờ»; khi bán bấm ▶ Bắt đầu trên dòng hóa đơn',
      ],
      tip:
          'Dịch vụ không trừ kho. Món pha chế khai là dịch vụ vẫn trừ nguyên liệu nếu khai «Định lượng nguyên vật liệu». Cách dùng riêng cho karaoke, salon, khách sạn xem tab Ngành hàng.',
      accent: Color(0xFF00897B),
      keywords: ['dịch vụ', 'tính giờ', 'block', 'karaoke', 'bi-a', 'phí mở phòng', 'giờ đầu', 'khung giờ đặc biệt', 'gói buổi', 'liệu trình', 'gói giờ', 'đếm ngược'],
      shots: [
        GuideShot('pos-services-1', afterBullet: 2, caption: '① Giá bán của dịch vụ. ② «Cách tính giá dịch vụ: Giá cố định». ③ Thời lượng mặc định (phút) dùng khi xếp lịch hẹn.'),
        GuideShot('pos-services-2', afterBullet: 4, caption: '① Block làm tròn và số phút tính tối thiểu. ② Giá riêng cho giờ đầu (4 block = 60 phút đầu tính 70.000 đ).'),
        GuideShot('pos-services-3', afterBullet: 6, caption: '① Bảng xem trước: khách dùng bao lâu thì số lượng và tiền trên hóa đơn là bao nhiêu (80.000 đ/giờ, block 15 phút, tối thiểu 30 phút).'),
        GuideShot('pos-services-4', afterBullet: 8, caption: '① Thời lượng gói (phút). ② Báo trước khi hết giờ. ③ Dịch vụ tính quá giờ — để «Chưa chọn» thì hết giờ chỉ báo, không tự tính tiền.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_combo',
      icon: Icons.fastfood_rounded,
      title: 'Combo / đóng gói',
      desc:
          'Gộp nhiều món thành một gói có giá riêng (combo sáng, set ăn, gói quà). Bán combo là trừ kho từng thành phần.',
      bullets: [
        'Bước 1 — Hàng hóa → Tạo mới → Combo / Đóng gói: nhập «Tên combo / gói *», nhóm hàng, ảnh',
        'Bước 2 — Mục «Hàng thành phần — định lượng»: bấm ô «Thêm hàng hóa hoặc dịch vụ», chọn từng món và sửa số lượng trong 1 combo',
        'Bước 3 — Dòng «Có thể bán khoảng N combo» cho biết số combo bán được theo thành phần còn ít nhất',
        'Bước 4 — «Quản lý tồn kho combo»: tắt = không giới hạn số gói (bán như dịch vụ); bật = nhập «Số lượng (tồn combo)», bán hết thì không bán tiếp',
        'Bước 5 — «Hiện chi tiết thành phần khi bán»: bật để hóa đơn hiện các món trong combo dưới tên combo',
        'Bước 6 — Mục «Giá bán»: nhập giá combo, đối chiếu «Tổng GT thành phần» để biết combo giảm bao nhiêu',
        'Bước 7 — Hoa hồng: bật «Hoa hồng nhân viên» trong Ngành hàng & cách bán; trên form chưa thấy mục này thì bấm nút «Tùy chọn hiển thị form» (góc trên) để hiện — áp cho cả gói khi một nhân viên bán, thành phần dùng hoa hồng từng món',
      ],
      tip:
          'Khi bán, hàng hóa / NVL / topping trong combo tự trừ kho; thành phần là dịch vụ không trừ. Combo 10 buổi spa: nhập 10 trên combo, hoặc SL 10 cho dịch vụ thành phần.',
      accent: Color(0xFF00897B),
      keywords: ['combo', 'đóng gói', 'set', 'gói quà', 'thành phần', 'tồn kho combo', 'giá combo'],
      shots: [
        GuideShot('pos-combo-1', afterBullet: 2, caption: '① Thêm món vào combo. ② Thành phần và số lượng trong 1 combo; dòng cam cho biết bán được khoảng bao nhiêu combo.'),
        GuideShot('pos-combo-2', afterBullet: 4, caption: '① Quản lý tồn kho combo (tắt = bán không giới hạn số gói). ② Hiện chi tiết thành phần khi bán.'),
        GuideShot('pos-combo-3', afterBullet: 6, caption: '① Giá bán combo. ② Tổng giá trị thành phần để so mức giảm.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_bom',
      icon: Icons.blender_rounded,
      title: 'Nguyên vật liệu & định lượng',
      desc:
          'Món pha chế / chế biến (trà sữa, cà phê, món ăn) bán ra sẽ trừ đúng lượng nguyên liệu đã khai, thay vì trừ món thành phẩm.',
      bullets: [
        'Bước 1 — Hàng hóa → Tạo mới → Nguyên vật liệu: nhập «Tên hàng *», «Nhóm hàng» (vd Nguyên vật liệu), «Giá vốn» theo đơn vị nhỏ nhất (ml, g, cái) và «Tồn kho» ban đầu',
        'Bước 2 — Nguyên vật liệu không hiện trên màn bán (để trống «Bán trực tiếp»); nhập thêm qua Nhập hàng NCC như hàng hóa thường',
        'Bước 3 — Mở món bán (vd Trà sữa trân châu) → mục «Định lượng nguyên vật liệu» → ô «Thêm nguyên vật liệu», chọn từng NVL',
        'Bước 4 — Nhập «SL / 1 món» cho từng NVL theo ĐVT của NVL (vd 120 ml trà, 50 g trân châu, 1 cái ly)',
        'Bước 5 — Bán món: kho tự trừ từng NVL = định lượng × số lượng món; hủy đơn / trả hàng thì cộng lại',
        'Bước 6 — Báo cáo POS → Nguyên vật liệu: NVL hết / sắp hết, còn đủ dùng bao nhiêu ngày, tiền nguyên liệu đã dùng, món chưa khai định lượng',
        'Bước 7 — Cuối tháng Kiểm kho NVL; lệch nhiều thì xem lại định lượng hoặc hao hụt (hủy / kiểm kê thiếu)',
      ],
      tip:
          'Món chưa khai định lượng bán ra không trừ nguyên liệu (báo cáo NVL liệt kê riêng). Topping và món khai là dịch vụ cũng khai định lượng được.',
      accent: Color(0xFF00897B),
      keywords: ['nguyên vật liệu', 'nvl', 'định lượng', 'công thức', 'pha chế', 'trừ nguyên liệu', 'báo cáo nguyên vật liệu', 'sắp hết'],
      shots: [
        GuideShot('pos-bom-1', afterBullet: 1, caption: '① Tên và nhóm của nguyên vật liệu. ② Giá vốn theo đơn vị nhỏ nhất (vd 32 đ/ml). ③ Tồn kho ban đầu.'),
        GuideShot('pos-bom-2', afterBullet: 4, caption: '① Thêm nguyên vật liệu vào món. ② Lượng dùng cho 1 món theo ĐVT của từng NVL.'),
        GuideShot('pos-bom-3', afterBullet: 6, caption: '① NVL hết / sắp hết và cần nhập trong tuần. ② Món bán ra mà chưa khai định lượng (không trừ nguyên liệu).'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_toppings',
      icon: Icons.add_circle_outline_rounded,
      title: 'Topping & tùy chọn thêm',
      desc:
          'Trân châu, thạch, kem phủ… bán kèm món, có giá phụ thu và trừ kho riêng. Nhóm topping dùng chung cho nhiều món, sửa một lần là áp cho tất cả.',
      bullets: [
        'Bước 1 — Tạo hàng topping: Hàng hóa → Tạo mới → Topping (có tồn kho, không hiện ở lưới bán chính); khai định lượng NVL nếu cần',
        'Bước 2 — Hàng hóa → Nhóm topping → «Thêm nhóm»: đặt «Tên nhóm» (vd Topping trà sữa), bấm «Thêm sản phẩm topping», chạm từng topping để sửa giá thêm',
        'Bước 3 — Gắn nhóm vào nhiều món một lần: trên thẻ nhóm bấm «Gắn vào N món — bấm để sửa» (hoặc nút ba chấm → «Gắn vào món…»)',
        'Bước 4 — Hoặc trên từng món: tab «Mô tả» → bật «Cho phép tùy chọn thêm khi bán», chọn chip nhóm ở «Topping (nhóm dùng chung)»; «Thêm tùy chọn cho món này» cho tùy chọn riêng một món',
        'Bước 5 — «Tự mở popup topping khi thêm món»: bật để màn bán hỏi topping ngay khi chọn món',
        'Bước 6 — Khi bán: chọn topping trên dòng món; tiền topping cộng vào dòng, kho trừ topping theo SL món × SL topping',
        'Bước 7 — Báo cáo POS → Topping: % ly có topping, topping bán chạy, lãi topping',
      ],
      tip:
          'Dùng nhóm dùng chung thay vì thêm từng topping cho từng món: đổi giá một lần trong nhóm là mọi món cùng nhóm cập nhật.',
      accent: Color(0xFF00897B),
      keywords: ['topping', 'trân châu', 'thạch', 'tùy chọn thêm', 'nhóm topping', 'món thêm', 'phụ thu'],
      shots: [
        GuideShot('pos-toppings-1', afterBullet: 2, caption: '① Mỗi nhóm: các topping kèm giá thêm, số món đang gắn — bấm dòng gạch chân để gắn vào món. ② «Thêm nhóm» để tạo nhóm mới.'),
        GuideShot('pos-toppings-2', afterBullet: 2, caption: '① Tên nhóm. ② Topping trong nhóm và giá thêm — chạm để sửa giá. ③ Thêm sản phẩm topping vào nhóm.'),
        GuideShot('pos-toppings-3', afterBullet: 4, caption: '① Bật «Cho phép tùy chọn thêm khi bán». ② Chọn nhóm topping dùng chung cho món. ③ «Quản lý nhóm» để tạo / sửa nhóm.'),
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
      title: 'Bán hàng: chọn hàng',
      desc:
          'Mỗi đơn: chọn hàng (hoặc bàn) → sửa món nếu cần → chọn khách & thanh toán. Kho chỉ bị trừ lúc thanh toán; hóa đơn đang mở chỉ giữ chỗ tồn.',
      bullets: [
        'Bước 1 — Mở Bán hàng (app HRM / web) hoặc app POS (máy A6). Nếu cửa hàng bật «Ca thu ngân»: mở ca trước (xem bước Ca thu ngân & tổng kết cuối ngày)',
        'Bước 2 — Thêm hàng: gõ tên / mã hoặc quét mã vạch ở ô «Tìm hàng (F3)», hoặc chạm món trên lưới (điện thoại: «Chọn hàng» / «Quét mã»). Nhà hàng: chọn bàn → gọi món → gửi bếp',
        'Bước 3 — Nhiều khách cùng lúc: bấm «+» (F2) để mở hóa đơn mới HĐ 2, HĐ 3…; chạm tab HĐ để chuyển qua lại, giỏ từng hóa đơn được giữ nguyên',
        'Bước 4 — Chế độ bán mặc định (bán nhanh / bán thường / giao hàng) chọn trong Thiết lập SBOX → Ngành hàng & cách bán',
        'Bước 5 — Sửa món, giá, ghi chú, topping: xem bước «Sửa món trên hóa đơn»; thu tiền: bước «Khách hàng & thanh toán»',
        'Mất mạng lúc bấm Thanh toán: cứ bấm lại — hệ thống nhận ra cùng đơn, không tạo đơn / trừ kho / thu tiền hai lần',
      ],
      tip:
          'Thanh toán cần quyền Duyệt (Approve) module PosSell. Tài khoản phục vụ chỉ có quyền tạo đơn thì order / gửi bếp được nhưng không thu tiền.',
      accent: Color(0xFFE65100),
      keywords: ['bán hàng', 'chọn hàng', 'quét mã', 'nhiều hóa đơn', 'F2', 'F3', 'thêm hóa đơn'],
      shots: [
        GuideShot('pos-sales-1', afterBullet: 2, caption: '① Tìm / quét mã hàng. ② Chạm món để thêm vào hóa đơn (điện thoại: «Chọn hàng»). ③ Sửa số lượng bằng − / +. ④ Thanh toán (F9).'),
        GuideShot('pos-sales-3', afterBullet: 3, caption: '① Mỗi hóa đơn một tab: HĐ 1 đang có hàng, HĐ 2 vừa mở. ② Nút «+» (F2) mở thêm hóa đơn mới.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_sale_edit',
      icon: Icons.edit_note_rounded,
      title: 'Sửa món trên hóa đơn',
      desc:
          'Đổi số lượng, giá, chiết khấu, ghi chú, topping hoặc gán nhân viên hoa hồng ngay trên từng dòng món trước khi thanh toán.',
      bullets: [
        'Bước 1 — Số lượng: bấm − / + trên dòng món, hoặc chạm vào số để nhập',
        'Bước 2 — Giá & chiết khấu dòng: máy tính chạm vào số tiền của dòng; điện thoại bấm «…» trên món → «Giá & chiết khấu». Sửa «Đơn giá», nhập «Chiết khấu» theo % hoặc đ (có nút nhanh 1k, 5k, 10k…) → «Áp dụng»',
        'Bước 3 — Đổi giá / chiết khấu cần quyền «Sửa giá khi bán» / «Giảm giá khi bán»; thiếu quyền app báo «Không đủ quyền» — nhờ quản lý tick trong Phân quyền',
        'Bước 4 — Ghi chú & topping: máy tính chạm tên món; điện thoại «…» → «Ghi chú». Chọn ghi chú nhanh (Ít đá, Mang đi…) hoặc gõ ghi chú khác; phần «Tùy chọn thêm» cộng topping có giá → «Xong»',
        'Bước 5 — Hoa hồng: khi bật «Hoa hồng nhân viên», dòng món hiện «Chọn NV hoa hồng» — chạm để gán nhân viên làm / bán',
        'Bước 6 — Điện thoại: «…» còn có «Tách dòng» / «Gộp dòng» và «Xóa khỏi hóa đơn»; máy tính xóa bằng nút thùng rác đầu dòng',
        'Bước 7 — Giảm giá cả đơn và mã voucher nhập ở màn thanh toán (bước «Khách hàng & thanh toán»)',
      ],
      tip:
          'Giá trên đơn là giá lúc thêm món — đổi giá hàng hóa sau đó không làm đổi các đơn đang mở.',
      accent: Color(0xFFE65100),
      keywords: ['sửa giá', 'chiết khấu', 'giảm giá dòng', 'ghi chú món', 'topping', 'hoa hồng', 'tách dòng', 'xóa món'],
      shots: [
        GuideShot('pos-sale-edit-1', afterBullet: 1, caption: 'Máy tính: ① Đổi số lượng. ② Chạm tên món để ghi chú / topping; «Chọn NV hoa hồng» để gán nhân viên. ③ Chạm số tiền để sửa giá & chiết khấu. Điện thoại (nút «…»): ① Ghi chú ② Giá & chiết khấu ③ Tách / gộp dòng ④ Xóa khỏi hóa đơn.'),
        GuideShot('pos-sale-edit-2', afterBullet: 2, caption: '① Đơn giá của món. ② Chiết khấu theo % hoặc đ (nút nhanh 1k, 5k…). ③ Bấm «Áp dụng».'),
        GuideShot('pos-sale-edit-3', afterBullet: 4, caption: '① Chạm ghi chú nhanh (Ít đá, Không đường, Mang đi). ② «Tùy chọn thêm»: cộng topping có giá. ③ Bấm «Xong».'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_sale_pay',
      icon: Icons.payments_rounded,
      title: 'Khách hàng & thanh toán',
      desc:
          'Màn thanh toán: chọn khách, giảm giá cả đơn / voucher, chọn hình thức trả tiền, nhập tiền khách đưa, in hóa đơn và xuất HĐĐT.',
      bullets: [
        'Bước 1 — Bấm «Thanh toán (F9)» ở màn bán để mở màn thanh toán',
        'Bước 2 — Khách hàng: gõ tên / SĐT ở ô «Tìm khách hàng (F4)» (mặc định «Người tiêu dùng»), nút thêm khách để tạo nhanh. Chọn khách để tích điểm, ghi công nợ hoặc xuất HĐĐT có MST',
        'Bước 3 — «Giảm giá» cả đơn theo % hoặc đ; nhập «Mã voucher» → «Áp dụng». Kiểm tra dòng «Khách cần trả»',
        'Bước 4 — Hình thức: Tiền mặt / Chuyển khoản (hiện QR tài khoản) / Tiền mặt + CK / Ghi nợ (phải chọn khách); «Số tiền từng nguồn» → «Thêm» để trả bằng nhiều nguồn',
        'Bước 5 — Tiền khách đưa: chạm ô số tiền → bấm nút mệnh giá (+50k, +100k, +200k…) hoặc nhập số → «Xong». App hiện «Tiền trả khách» và ghi luôn trên nút hoàn tất',
        'Bước 6 — Chip «In hóa đơn» / «In 2 liên» (và «Xuất HĐĐT» khi đã cấu hình) → «HOÀN TẤT THANH TOÁN (F9)» (điện thoại: «Hoàn thành»)',
        'Bước 7 — Sau thanh toán app báo kết quả HĐĐT: «Đã xuất HĐĐT» (kèm số), «Chưa xuất được HĐĐT» (kèm lý do) hoặc «HĐĐT chờ ký / chờ số» — đơn vẫn hợp lệ, xử lý lại trong Quản lý HĐĐT',
      ],
      tip:
          'Ghi nợ chỉ dùng khi đã chọn khách — khách lẻ không theo dõi được công nợ.',
      accent: Color(0xFFE65100),
      keywords: ['thanh toán', 'khách hàng', 'tích điểm', 'công nợ', 'ghi nợ', 'voucher', 'tiền thối', 'tiền trả khách', 'chuyển khoản', 'in hóa đơn'],
      shots: [
        GuideShot('pos-sale-pay-1', afterBullet: 2, caption: '① Ô khách hàng (F4) và nút thêm khách. ② Giảm giá cả đơn theo % / đ. ③ Mã voucher → Áp dụng. ④ Số khách cần trả.'),
        GuideShot('pos-sales-2', afterBullet: 4, caption: '① Chọn hình thức: tiền mặt, chuyển khoản, tiền mặt + CK hoặc ghi nợ. ② Chip «In hóa đơn» để in khi thanh toán. ③ Hoàn tất thanh toán (F9).'),
        GuideShot('pos-sale-pay-2', afterBullet: 5, caption: '① Nút mệnh giá cộng nhanh tiền khách đưa. ② Số tiền đang nhập. ③ Bấm «Xong».'),
        GuideShot('pos-sale-pay-3', afterBullet: 5, caption: '① Tiền khách đưa. ② «Tiền trả khách» — số phải thối lại. ③ Hoàn tất (máy tính ghi luôn tiền trả khách trên nút).'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_after_sale',
      icon: Icons.receipt_long_rounded,
      title: 'Sau bán: đơn hàng, in lại, hủy, trả hàng',
      desc:
          'Tra cứu đơn đã bán, in lại, hủy đơn hoặc trả hàng — mọi lượt hủy / trả đều được ghi lại kèm lý do và người thao tác.',
      bullets: [
        'Bước 1 — Mở menu Đơn hàng (Hóa đơn): lọc «Trạng thái», «Thời gian», «Thanh toán», «Loại đơn» hoặc tìm mã đơn / khách (điện thoại: nút «Lọc»)',
        'Bước 2 — Chạm một đơn để xem chi tiết: ngày bán, khách, mặt hàng, tổng tiền, lịch sử thanh toán',
        'Bước 3 — «In (n)» in lại hóa đơn (số trong ngoặc là số lần đã in); «Tùy chọn in» chọn mẫu / máy in khác',
        'Bước 4 — «Hủy đơn» (đúng quyền, nhập lý do): gỡ doanh thu, hoàn kho, hoàn điểm / voucher / công nợ. Đơn đã có trả hàng thì không hủy được',
        'Bước 5 — «Trả hàng»: chọn số lượng trả trên đơn gốc — hoàn kho và tiền phần trả; đơn hiện nhãn «Trả một phần»',
        'Bước 6 — «HĐĐT» xuất / xem hóa đơn điện tử của đơn; «Sao chép» tạo đơn mới giống đơn cũ (máy tính)',
        'Bước 7 — Báo cáo → «Lịch sử hủy / trả»: tổng hợp hủy món bếp, hủy đơn, trả hàng; từng lượt có lý do, người làm, thời gian, máy; lọc «Sau tạm tính» để soát lượt hủy sau khi đã in tạm tính',
      ],
      tip:
          'Không xóa đơn đã bán — đơn sai thì hủy hoặc trả hàng để giữ lịch sử và đúng kho.',
      accent: Color(0xFFE65100),
      keywords: ['đơn hàng', 'in lại', 'hủy đơn', 'trả hàng', 'hoàn tiền', 'lịch sử hủy', 'tra cứu hóa đơn'],
      shots: [
        GuideShot('pos-after-sale-1', afterBullet: 1, caption: '① Bộ lọc trạng thái, thời gian, thanh toán (điện thoại: «Lọc»). ② Chạm một đơn để xem chi tiết.'),
        GuideShot('pos-after-sale-2', afterBullet: 3, caption: '① «In (1)» in lại hóa đơn. ② «Hủy đơn» (đúng quyền, nhập lý do). ③ «Trả hàng» chọn số lượng trả.'),
        GuideShot('pos-after-sale-3', afterBullet: 7, caption: '① Tổng số lượt và tiền theo loại: hủy đơn, trả hàng (máy tính có thêm hủy món bếp). ② Từng lượt có lý do, người làm, thời gian.'),
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
      title: 'Kho hàng: tổng quan',
      desc:
          'Kho chạy theo chứng từ: phiếu nhập cộng tồn; bán, trả NCC, xuất hủy, xuất dùng trừ tồn; kiểm kho cân bằng chênh lệch. Phiếu tạm chưa ảnh hưởng kho — hoàn thành mới ghi sổ.',
      bullets: [
        'Bước 1 — Nhập hàng từ nhà cung cấp: phiếu nhập → Hoàn thành mới cộng tồn và công nợ NCC (xem bước «Nhà cung cấp & nhập hàng»)',
        'Bước 2 — Giảm tồn ngoài bán hàng: trả hàng nhập, xuất hủy, xuất dùng nội bộ (xem bước «Trả hàng nhập, xuất hủy, xuất dùng nội bộ»)',
        'Bước 3 — Theo dõi tồn, cảnh báo dưới định mức và Thẻ kho từng mặt hàng (xem bước «Tồn kho & thẻ kho»)',
        'Bước 4 — Đếm thực tế và cân bằng chênh lệch (xem bước «Kiểm kho»)',
        'Bước 5 — Giá vốn bình quân gia quyền theo các lần nhập; hủy phiếu nhập thì giá vốn trả về như trước',
        'Bước 6 — Giữ chỗ, bán âm, lô / HSD: xem bước «Nguyên tắc tồn kho» và «Lô / HSD, bảo hành, hàng gia công»',
      ],
      tip:
          'Không sửa chứng từ đã hoàn thành — muốn đảo ngược thì Hủy phiếu; mọi thay đổi tồn đều có dòng trong Thẻ kho.',
      accent: Color(0xFF00897B),
      keywords: ['kho', 'kho hàng', 'nhập xuất tồn', 'chứng từ kho', 'giá vốn bình quân'],
      shots: [
        GuideShot('pos-inventory-1', afterBullet: 1, caption: '① Tạo phiếu nhập. ② Phiếu tạm: chưa cộng tồn. ③ «Nhập hàng vào kho» (điện thoại: «Hoàn thành nhập») mới cộng tồn và công nợ NCC.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_suppliers',
      icon: Icons.local_shipping_rounded,
      title: 'Nhà cung cấp & nhập hàng',
      desc:
          'Quản lý nhà cung cấp, phiếu nhập hàng và công nợ phải trả NCC. Phiếu nhập tạm chưa ảnh hưởng kho; hoàn thành mới cộng tồn, cập nhật giá vốn và ghi nợ NCC.',
      bullets: [
        'Bước 1 — Menu POS › Nhà cung cấp: danh sách NCC kèm Tổng mua, Công nợ; thẻ «Đang nợ NCC» là tổng tiền đang nợ. Bấm «Thêm NCC» để tạo (mã, tên, SĐT, MST, địa chỉ)',
        'Bước 2 — Tạo phiếu nhập: menu Nhập hàng NCC → «Tạo phiếu nhập». Tìm / quét hàng (F3), nhập số lượng, đơn giá, giảm giá, VAT; hàng có lô nhập «Mã lô», NSX, HSD',
        'Bước 3 — Cột phải phiếu: chọn «Nhà cung cấp», ngày nhập, ký hiệu / số HĐ đầu vào, «Tiền trả nhà cung cấp» và «Phương thức thanh toán» — trả một phần thì phần còn lại ghi nợ NCC',
        'Bước 4 — «Lưu tạm»: phiếu tạm chưa ảnh hưởng tồn kho. «Hoàn thành»: cộng tồn, cập nhật giá vốn bình quân, ghi công nợ NCC',
        'Bước 5 — Trả nợ NCC: ở danh sách NCC bấm nút thao tác của NCC → «Trả nợ» (tiền trừ vào các phiếu còn nợ, phiếu cũ trước)',
        'Bước 6 — «Sổ đối chiếu công nợ»: nhập nợ, đã trả / trả hàng theo khoảng ngày để đối chiếu với NCC; «Nhập nợ đầu kỳ / điều chỉnh» cho nợ cũ trước khi dùng phần mềm',
        'Bước 7 — Phiếu nhập đã hoàn thành bị sai: «Hủy phiếu» (trừ lại tồn, trả giá vốn về như trước) rồi tạo phiếu mới — không sửa phiếu đã hoàn thành',
      ],
      tip:
          'Nhập hàng NCC trước khi bán để giá vốn, lợi nhuận và công nợ NCC đúng ngay từ đầu.',
      accent: Color(0xFF00897B),
      keywords: ['nhà cung cấp', 'NCC', 'nhập hàng', 'phiếu nhập', 'công nợ NCC', 'trả nợ NCC', 'đối chiếu công nợ', 'nợ đầu kỳ', 'giá vốn'],
      shots: [
        GuideShot('pos-suppliers-1', afterBullet: 1, caption: '① «Thêm NCC». ② Tổng đang nợ nhà cung cấp. ③ Mỗi NCC: tổng mua và công nợ (số đỏ là đang nợ).'),
        GuideShot('pos-suppliers-2', afterBullet: 4, caption: '① Hàng nhập: số lượng, đơn giá, giảm giá, VAT; hàng có lô nhập mã lô và HSD. ② Nhà cung cấp, tiền trả và phương thức thanh toán (máy tính: cột phải; điện thoại: kéo xuống cuối phiếu). ③ «Lưu tạm» chưa cộng tồn — «Hoàn thành» mới cộng tồn và công nợ NCC.'),
        GuideShot('pos-suppliers-3', afterBullet: 5, caption: '① «Sổ đối chiếu công nợ» theo khoảng ngày. ② «Trả nợ» — tiền trừ vào các phiếu còn nợ, phiếu cũ trước. ③ Nhập nợ đầu kỳ / điều chỉnh.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_stock_docs',
      icon: Icons.outbox_rounded,
      title: 'Trả hàng nhập, xuất hủy, xuất dùng nội bộ',
      desc:
          'Ba loại phiếu làm giảm tồn ngoài bán hàng: trả lại hàng cho NCC, hủy hàng hỏng / hết hạn, xuất nguyên liệu dùng nội bộ. Phiếu tạm chưa trừ kho; hoàn thành mới trừ.',
      bullets: [
        'Bước 1 — Trả hàng nhập: menu POS › Trả hàng nhập → «Tạo phiếu trả». Chọn NCC / phiếu nhập gốc, hàng, số lượng và giá trả lại',
        'Bước 2 — Kiểm «NCC cần trả» (tiền NCC phải hoàn) rồi bấm «Hoàn thành trả hàng» (điện thoại: «Hoàn thành trả»): trừ tồn và giảm công nợ NCC',
        'Bước 3 — Xuất hủy: menu POS › Xuất hủy → «Tạo phiếu hủy» cho hàng hỏng, hết hạn, đổ vỡ; nhập SL hủy, ghi chú lý do; «Hoàn thành xuất hủy» (điện thoại: «Hoàn thành hủy») mới trừ tồn',
        'Bước 4 — Xuất dùng nội bộ: menu POS › Xuất dùng nội bộ → «Tạo phiếu xuất dùng» (pha chế thử, nhân viên dùng); ghi loại xuất và người nhận; «Hoàn thành xuất» mới trừ tồn',
        'Bước 5 — Phiếu tạm sửa / xóa được và chưa ảnh hưởng kho; phiếu đã hoàn thành muốn đảo ngược thì «Hủy phiếu» — hàng được hoàn về kho',
        'Bước 6 — «Sao chép» tạo phiếu mới giống phiếu cũ, «In phiếu» để ký nhận; mọi phiếu đều ghi vào Thẻ kho của từng mặt hàng',
      ],
      tip:
          'Không xóa phiếu đã hoàn thành — hủy phiếu để giữ lịch sử và đúng tồn kho.',
      accent: Color(0xFF00897B),
      keywords: ['trả hàng nhập', 'trả NCC', 'xuất hủy', 'hàng hỏng', 'hết hạn', 'xuất dùng nội bộ', 'hủy phiếu', 'phiếu kho'],
      shots: [
        GuideShot('pos-stock-docs-1', afterBullet: 2, caption: '① Phiếu trả: NCC, phiếu nhập gốc, trạng thái phiếu tạm. ② Hàng trả và số tiền NCC cần trả lại. ③ «Hoàn thành trả hàng» mới trừ tồn và giảm công nợ NCC.'),
        GuideShot('pos-stock-docs-2', afterBullet: 3, caption: '① Phiếu xuất hủy đang tạm (lý do: hết hạn / hư hỏng). ② Hàng hủy, số lượng, giá vốn, tổng giá trị. ③ «Hoàn thành xuất hủy» mới trừ tồn.'),
        GuideShot('pos-stock-docs-3', afterBullet: 4, caption: '① Phiếu xuất dùng: người nhận (vd quầy bar). ② Nguyên liệu xuất, số lượng, giá vốn. ③ «Hoàn thành xuất» mới trừ tồn.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_stock_card',
      icon: Icons.fact_check_rounded,
      title: 'Tồn kho & thẻ kho',
      desc:
          'Xem tồn từng mặt hàng, phần đang giữ chỗ, cảnh báo dưới định mức / hết hàng, và Thẻ kho ghi mọi biến động kèm chứng từ, người thao tác.',
      bullets: [
        'Bước 1 — Menu POS › Hàng hóa: cột «Tồn» và «Đặt» (đang giữ chỗ cho bàn / đơn tạm); tồn chữ đỏ = hết hàng; «Dự kiến hết» là ngày hàng có thể hết theo tốc độ bán',
        'Bước 2 — Bộ lọc «Tồn kho»: Dưới định mức (cần nhập thêm), Hết hàng, Vượt định mức',
        'Bước 3 — Bấm vào mặt hàng → tab «Tồn kho»: Tồn kho, Khách đặt, Có thể bán (= tồn − khách đặt), Định mức tồn (điện thoại: trang chi tiết hàng, mục «Thông tin»)',
        'Bước 4 — Định mức tồn đặt trên form hàng hóa (Định mức tồn thấp nhất / cao nhất) — xem bước «Thêm hàng hóa»',
        'Bước 5 — Tab «Thẻ kho» (điện thoại: nút «Thẻ kho» cuối trang chi tiết): mọi biến động — chứng từ, thời gian, loại giao dịch (bán, mua, kiểm kê, trả, hủy…), số lượng, tồn cuối, đối tác',
        'Bước 6 — Bấm mã chứng từ để mở phiếu gốc; «Xuất file» để gửi kế toán / đối chiếu',
        'Bước 7 — Báo cáo POS → Tồn kho / Hàng sắp hết hạn để xem toàn bộ kho theo nhóm và giá trị tồn',
      ],
      tip:
          'Tồn lệch hay âm: mở Thẻ kho của mặt hàng để biết chứng từ nào, ai làm, lúc nào.',
      accent: Color(0xFF00897B),
      keywords: ['tồn kho', 'thẻ kho', 'định mức tồn', 'dưới định mức', 'hết hàng', 'có thể bán', 'khách đặt', 'giữ chỗ', 'dự kiến hết'],
      shots: [
        GuideShot('pos-stock-card-1', afterBullet: 3, caption: '① Lọc «Tồn kho»: dưới định mức, hết hàng, vượt định mức. ② Tồn kho, khách đặt, có thể bán và định mức tồn của mặt hàng. ③ Tồn «0» chữ đỏ = hết hàng.'),
        GuideShot('pos-stock-card-2', afterBullet: 5, caption: '① Tab «Thẻ kho» của mặt hàng. ② Mỗi dòng: chứng từ, thời gian, loại giao dịch, số lượng (+ nhập / − xuất), tồn cuối, đối tác. ③ «Xuất file».'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_stock_count',
      icon: Icons.checklist_rounded,
      title: 'Kiểm kho',
      desc:
          'Đếm hàng thực tế, so với tồn hệ thống và cân bằng phần chênh lệch. Cân bằng chỉ cộng / trừ phần lệch nên hàng bán sau lúc đếm vẫn đúng.',
      bullets: [
        'Bước 1 — Menu POS › Kiểm kho → «Tạo phiếu kiểm kê» (điện thoại: nút «Tạo phiếu kiểm»)',
        'Bước 2 — Tìm / quét hàng cần kiểm (F3) hoặc «Quét hàng loạt» bằng máy quét; mỗi dòng hiện tồn hệ thống',
        'Bước 3 — Nhập số «Thực tế» ngay khi đếm (hệ thống chốt tồn sổ lúc nhập) — «SL lệch», «Giá trị lệch» tự tính; lọc Khớp / Lệch / Chưa kiểm',
        'Bước 4 — «Lưu tạm» để đếm tiếp sau; dòng chưa nhập chọn «Khớp tồn» khi đã đếm đúng bằng tồn hệ thống',
        'Bước 5 — «Hoàn thành» (điện thoại: «Cân bằng kho»): kho chỉ cộng / trừ phần chênh lệch',
        'Bước 6 — Cân bằng sai: «Hủy phiếu» để hoàn tồn về trước khi cân bằng; lượt lệch nằm trong Thẻ kho (loại «Kiểm kê kho»)',
        'Bước 7 — Nên kiểm hàng chính / nguyên vật liệu cuối mỗi tháng; lệch nhiều thì xem lại định lượng, xuất hủy, nhập hàng',
      ],
      tip:
          'Nhập số đếm ngay lúc đếm từng mặt hàng — để cuối buổi mới nhập dễ lệch vì hàng đã bán thêm.',
      accent: Color(0xFF00897B),
      keywords: ['kiểm kho', 'kiểm kê', 'cân bằng kho', 'lệch kho', 'số thực tế', 'khớp tồn', 'quét hàng loạt'],
      shots: [
        GuideShot('pos-stock-count-1', afterBullet: 1, caption: '① «Tạo phiếu kiểm kê». ② Phiếu đang kiểm (phiếu tạm) và tổng chênh lệch.'),
        GuideShot('pos-stock-count-2', afterBullet: 3, caption: '① Tìm / quét hàng cần kiểm. ② Nhập số thực tế — lệch và giá trị lệch tự tính. ③ «Hoàn thành» (điện thoại: «Cân bằng kho»).'),
        GuideShot('pos-stock-count-3', afterBullet: 5, caption: '① Tồn kho, thực tế, SL lệch, giá trị lệch từng mặt hàng. ② «Cân bằng kho» để cộng / trừ phần chênh lệch.'),
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
      id: 'pos_quotes',
      icon: Icons.request_page_outlined,
      title: 'Báo giá & hợp đồng',
      desc:
          'Lập báo giá gửi khách (PDF, Word, Zalo…), theo dõi đến khi khách chốt, rồi lập hợp đồng, xuất kho, bàn giao và nghiệm thu.',
      bullets: [
        'Mở POS › Báo giá — tab «Báo giá», «Hợp đồng», «Đề nghị TT», «Nghiệm thu»; bấm «Thêm báo giá»',
        'Chọn khách bằng «Tìm khách (tên / SĐT / MST)» (để trống = «Khách lẻ»), chọn «Bảng giá» nếu có, bấm «Thêm món»',
        'Từng dòng sửa «Đơn giá», «Chiết khấu»; chiết khấu cả phiếu ở «Chiết khấu đơn»',
        '«Thuế VAT»: «Giá đã gồm VAT», «Giá + VAT», «Không VAT» hoặc «VAT theo mặt hàng»; cọc ở «Tiền cọc thực hiện hợp đồng»',
        'Chọn «Mẫu in A4», «Hạn báo giá» (mặc định 15 ngày), tích «Đưa hình ảnh sản phẩm vào phiếu in» nếu cần → «Lưu & in phiếu»',
        'Gửi khách: nút «Gửi / In» → «In», «PDF», «Word», «Excel», «Ảnh PNG», «Email», «Gửi Zalo»',
        'Theo trạng thái: «Phát hành (đã gửi khách)» → «Khách chốt báo giá» / «Khách chốt & lập HĐ» / «Khách từ chối»; khách đòi sửa → «Sửa (tạo bản sửa)»',
        'Sau khi chốt: «Lập hợp đồng» → «Xuất kho», «Bàn giao», «Giao việc thi công» → «Nghiệm thu» → «Đóng hồ sơ»',
        'Đánh số: Thông tin cửa hàng › «Đánh số báo giá & hợp đồng» — «Tự nhảy theo mẫu» ({YYYY}, {MM}, {SEQ:4}…) hoặc «Tự nhập»',
      ],
      tip:
          'Trạng thái: Nháp → Đã gửi → Chấp nhận / Từ chối; quá «Hạn báo giá» tự thành «Hết hạn». Có thể nói với Trợ lý ảo: «Báo giá cho chị Lan 10 thùng Coca».',
      accent: Color(0xFF1565C0),
    ),
    LandingUsageGuideStep(
      id: 'pos_booking',
      icon: Icons.event_seat_outlined,
      title: 'Đặt bàn, đặt phòng, đặt lịch hẹn',
      desc:
          'Giữ bàn / phòng / ghế cho khách theo giờ, thu cọc, nhận khách khi đến; salon tự xếp thợ rảnh.',
      bullets: [
        'Mở POS › Đặt lịch (màn «Đặt chỗ / lịch hẹn») → bấm «Thêm»; hoặc trên màn bán: Menu › «Đặt bàn» / «Đặt phòng» / «Đặt lịch» tùy ngành',
        'Từ sơ đồ bàn: nhấn giữ (hoặc «⋯») bàn trống → «Đặt bàn — <bàn>» → «Ngày đến», «Giờ đến», «Số khách», «Tên khách *», «SĐT» → «Lưu Đặt bàn»',
        'Có thể chọn «Món đặt trước» và nhập «Cọc yêu cầu» (tích «Đã thu ngay» nếu khách đã chuyển)',
        'Salon / spa: chọn «Dịch vụ *» và «Thợ làm» — để «Tự xếp» thì hệ thống chọn thợ quen hoặc thợ ít việc nhất đang có ca',
        'Khách sạn: nhập «Số đêm»; phòng giờ / salon: nhập «Thời lượng»',
        'Khách đến: mở lịch → «Nhận bàn» (phòng / ghế) — đơn bán mở sẵn, cọc trừ vào đơn',
        'Bàn đã đặt mà có khách vãng lai: «Khách vãng lai» (ngồi tạm, vẫn giữ lịch); thu cọc sau: «Thu cọc»',
        'Hủy: «Hủy lịch» / «Hủy đặt» — đã thu cọc thì chọn «Hoàn cọc» hoặc «Mất cọc»',
        'Khách không đến: tự chuyển «Không đến» sau giờ hẹn; hoặc bấm «Đánh dấu khách không đến (quá giờ)»',
      ],
      tip:
          'Trạng thái lịch: Chưa đến → Đã nhận → Đang dùng → Đã thanh toán. Nói với Trợ lý ảo: «Đặt bàn 5 tối nay 7 giờ cho anh Nam, 6 người».',
      accent: Color(0xFF00796B),
    ),
    LandingUsageGuideStep(
      id: 'pos_customer_display',
      icon: Icons.connected_tv_outlined,
      title: 'Màn hình phụ cho khách',
      desc:
          'Màn thứ hai quay về phía khách: hiện món, tổng tiền, mã QR chuyển khoản; lúc chờ thì chiếu ảnh / video quảng cáo.',
      bullets: [
        'Thiết lập SBOX › Màn hình phụ → bật «Màn hình phụ cho khách»',
        '«Loại màn hình phụ»: «Sunmi T1 (ảnh welcome + bill)», «Android Flutter (đầy đủ — media/video)» hoặc «Window / trình duyệt (link máy khác)»',
        'Bật «Tự mở khi vào bán hàng»: máy Android hai màn tự dùng màn thứ hai',
        'Màn khác / TV: «Mở trên máy / TV khác» → sao chép link, mở trên máy đó (không cần đăng nhập, máy thu ngân phải đang ở màn bán)',
        'Lúc chờ khách: «Ảnh trình chiếu» («Upload ảnh»), «Video trình chiếu» (link Google Drive hoặc .mp4 — không dùng YouTube), «Thời gian đổi ảnh / video», «Bật tiếng video»',
        'Khách thấy: «Xin chào quý khách» → bill (Tạm tính, Giảm giá, TỔNG CỘNG) → «Quét mã để chuyển khoản» → «Đã nhận chuyển khoản»',
        'Mở tay trên màn bán: Menu › «Màn hình khách»',
      ],
      tip: 'Ảnh nên 1920×1080 (ngang) hoặc 1080×1920 (dọc); video MP4 H.264 720p/1080p dưới 50MB. Màn phụ A6 trắng: rút cáp USB debug rồi mở lại POS.',
      accent: Color(0xFF5E35B1),
    ),
    LandingUsageGuideStep(
      id: 'pos_shipping',
      icon: Icons.local_shipping_outlined,
      title: 'Giao hàng & vận đơn (GHN, GHTK, Viettel Post…)',
      desc:
          'Kết nối hãng giao hàng, so sánh cước, tạo vận đơn có thu hộ COD và in tem ngay trên đơn bán.',
      bullets: [
        'Thiết lập SBOX › Đơn vị giao hàng: hỗ trợ GHN, GHTK, SPX Express, Viettel Post, AhaMove',
        'Bật hãng → dán «API Token» (GHN thêm «ShopId», GHTK thêm «Partner code»…) → điền «Điểm lấy hàng» → «Lưu» → «Thử kết nối»',
        'Tem: bật «In tem vận đơn (máy này)», chọn «Khổ tem»; «Tự in tem khi tạo vận đơn» nếu muốn in luôn',
        'Trên đơn bán, phần «Giao hàng»: «Địa chỉ giao hàng», «SĐT nhận hàng» → «So sánh cước & tạo vận đơn»',
        'Nhập «KL (g)», kích thước → chọn hãng; người trả cước «Shop trả» / «Khách trả» → «Tạo vận đơn» (COD tự = số tiền khách còn nợ)',
        'Sau khi tạo: «In tem vận đơn», «Đồng bộ hành trình», «Hủy vận đơn»; tự giao thì chọn «Giao hàng nội bộ» và «In tem giao hàng (tự giao)»',
        'Đơn online / QR: nút «Tạo vận đơn» như trên; AhaMove có «Theo dõi đơn»',
        'Báo cáo giao hàng: «Giao thất bại», «Hoàn hàng», «Đối soát COD» (ghi phiếu «Thu hộ COD» vào sổ quỹ), «Chưa tạo vận đơn»',
      ],
      tip: 'Dùng «Sandbox (môi trường test)» để thử trước khi chạy thật. Muốn trạng thái tự cập nhật: làm theo hướng dẫn webhook của từng hãng trên màn thiết lập.',
      accent: Color(0xFFE65100),
    ),
    LandingUsageGuideStep(
      id: 'pos_qr_order',
      icon: Icons.qr_code_2_rounded,
      title: 'Menu QR / bán online',
      desc:
          'Khách quét QR tại bàn để tự gọi món, hoặc đặt hàng online qua link riêng của quán (nhập tên, SĐT, địa chỉ). Đơn về màn «Đơn online» và báo bếp; thu ngân xác nhận, in bếp, thanh toán, giao hàng.',
      bullets: [
        'Bước 1 — Mở POS → Menu QR / Online (QR order tại bàn): nhập «Thương hiệu trang đặt hàng» — tên quán, SĐT, địa chỉ, logo, ảnh quảng cáo hiện khi khách mở QR',
        'Bước 2 — Chọn cách nhận order tại bàn: «Tự in phiếu bếp» (khách gửi món là in phiếu), «Chỉ gọi món khi đã mở bàn», «Chỉ gọi món trong phạm vi quán (GPS)», «Bật xác nhận order (QR)» để thu ngân duyệt trước khi báo bếp',
        'Bước 3 — In QR dán bàn: «In tất cả QR (N bàn)» hoặc nút in / sao chép link trên từng bàn (in tem 60×40 hoặc xuất PDF). Bàn lấy từ sơ đồ bàn — thêm bàn trước nếu danh sách trống',
        'Bước 4 — Bán online ngoài quán: bật «Đặt hàng online ngoài cửa hàng», đặt «Giờ nhận đơn online» và «Quy tắc đơn online» (đơn tối thiểu, phí giao, miễn phí giao từ)',
        'Bước 5 — Tự động hóa (tùy chọn): «Tự xác nhận đơn online», «Tự in bếp khi đơn online được xác nhận», «Tự hoàn thành COD khi xác nhận», «Tự tạo vận đơn khi «Đang giao»»',
        'Bước 6 — Xử lý đơn: mở «Đơn online», lọc Chờ xác nhận / Đang chuẩn bị / Đang giao… → chạm đơn để xem món, ghi chú, khách',
        'Bước 7 — Trong chi tiết đơn: «In bếp», «In tạm tính», «Thanh toán»; «Bước tiếp theo»: «Xác nhận đơn» → «Đang giao hàng» → «Giao thành công», hoặc «Hủy đơn»',
        'Bước 8 — Khách chuyển khoản qua QR Tingee (nếu bật ở Tài khoản nhận tiền) thì đơn tự đánh dấu đã thanh toán',
      ],
      tip:
          'Bật «Bật xác nhận order (QR)» nếu sợ khách ngoài quán quét QR cũ đặt bừa — món chỉ xuống bếp khi thu ngân đồng ý.',
      accent: Color(0xFF00897B),
      keywords: ['QR order', 'menu QR', 'gọi món tại bàn', 'đặt hàng online', 'đơn online', 'link bán hàng', 'in QR bàn', 'giao hàng'],
      shots: [
        GuideShot('pos-qr-order-1', afterBullet: 2, caption: '① «Tự in phiếu bếp» khi khách gửi món. ② «Bật xác nhận order (QR)»: thu ngân duyệt trước khi báo bếp. ③ «In tất cả QR» để dán bàn. ④ Từng bàn: link QR, nút sao chép / in QR.'),
        GuideShot('pos-qr-order-2', afterBullet: 4, caption: '① Bật «Đặt hàng online ngoài cửa hàng». ② «Quy tắc đơn online»: đơn tối thiểu, phí giao, miễn phí giao từ. ③ Tự xác nhận đơn / tự in bếp khi đơn được xác nhận.'),
        GuideShot('pos-qr-order-3', afterBullet: 7, caption: '① Đơn online và trạng thái. ② Món khách đặt, tổng tiền, ghi chú. ③ «In bếp», «In tạm tính», «Thanh toán». ④ «Xác nhận đơn» hoặc «Hủy đơn».'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_kds',
      icon: Icons.soup_kitchen_rounded,
      title: 'Màn hình bếp (KDS)',
      desc:
          'Màn hình cho bếp / bar thay phiếu in: món gửi bếp hiện ngay theo món hoặc theo bàn, có thời gian chờ, báo trễ, đọc tên món; bếp bấm «Đang làm» và «Ra món».',
      bullets: [
        'Bước 1 — Mở POS → Màn hình bếp (KDS) trên tablet / màn hình đặt ở bếp. Món thu ngân gửi bếp (hoặc khách gọi qua QR) hiện ngay',
        'Bước 2 — Chọn cách xem: «Gộp món» (cùng món của nhiều bàn gom một thẻ — nấu một lần) hoặc «Theo bàn» (mỗi bàn một thẻ)',
        'Bước 3 — Lọc «Trạng thái»: Tất cả / Đang làm / Chờ làm / Làm xong; thêm «Lâu nhất», «Trễ», «Bàn chưa làm món nào» để ưu tiên',
        'Bước 4 — Bắt đầu nấu bấm «Đang làm»; nấu xong bấm «Ra món» — món chuyển «Làm xong», thu ngân / phục vụ thấy ngay',
        'Bước 5 — Ghi chú món (Ít hành, Thêm rau…) hiện dưới tên món; số phút chờ chuyển đỏ khi quá ngưỡng «Báo trễ món»',
        'Bước 6 — Nút loa: đọc món cần chế biến (chọn giọng, tốc độ, chuông trước khi đọc); nút màn hình to; menu «Thêm» → Máy in KDS để in phiếu khi bấm «Ra món»',
        'Bước 7 — Món hủy hiện ở «Món hủy — Đồng ý từng dòng» để bếp xác nhận đã biết',
      ],
      tip:
          'Bếp và bar dùng 2 máy: mỗi máy mở KDS riêng; món tự hiện theo phân trạm in bếp đã gán cho mặt hàng.',
      accent: Color(0xFF00897B),
      keywords: ['KDS', 'màn hình bếp', 'bếp', 'bar', 'ra món', 'đang làm', 'món trễ', 'đọc món'],
      shots: [
        GuideShot('pos-kds-1', afterBullet: 2, caption: '① «Gộp món» / «Theo bàn». ② Lọc trạng thái: tất cả, đang làm, chờ làm, làm xong. ③ «Ra món» khi nấu xong (bấm «Đang làm» lúc bắt đầu). ④ Món đã xong hiện «ĐÃ HOÀN THÀNH».'),
        GuideShot('pos-kds-2', afterBullet: 4, caption: '① Thẻ theo bàn: khu · bàn, số món. ② Từng món: số lượng, ghi chú, phút chờ (đỏ = trễ). ③ «Đang làm» / «Ra món» cho cả bàn.'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_warranty',
      icon: Icons.build_circle_rounded,
      title: 'Bảo hành',
      desc:
          'Quản lý máy đã bán theo seri: tiếp nhận bảo hành, in phiếu A5, theo dõi máy ở cửa hàng, trả khách và thu phí sửa, đổi máy trừ kho, nhắc khách sắp hết bảo hành, báo cáo.',
      bullets: [
        'Bước 1 — Khi bán: hàng có «Thời hạn bảo hành (tháng)» và bật «Bắt buộc nhập seri máy khi bán» → nhập seri (chỉnh được số tháng BH lúc nhập); hóa đơn in seri và hạn bảo hành',
        'Bước 2 — Mở POS → Bảo hành, tab «Máy đã bán»: tìm seri / IMEI, tên hoặc SĐT khách, mã đơn; lọc Còn bảo hành / Hết bảo hành / Đã đổi máy / Khách đã trả hàng',
        'Bước 3 — Khách mang máy tới: bấm «Tiếp nhận BH» → ghi lỗi, tình trạng máy, phụ kiện, ngày hẹn trả, người phụ trách → «Tiếp nhận» → in phiếu tiếp nhận (A5) đưa khách giữ',
        'Bước 4 — Tab «Phiếu bảo hành»: lọc Máy ở cửa hàng / Chờ khách lấy / Quá hẹn / Đã trả khách. Đang sửa bấm «Đang xử lý»; xong bấm «Hoàn tất» (hoặc «Từ chối» kèm lý do), «Hẹn / phụ trách» để dời hẹn',
        'Bước 5 — Máy hết bảo hành / lỗi khách: nhập phí sửa khi hoàn tất, chọn thu ngay hoặc thu khi trả máy (ghi phiếu thu «Phí sửa chữa bảo hành»)',
        'Bước 6 — Khách đến lấy: «Trả khách» → thu phí nếu còn → «Đã trả máy» → in phiếu trả máy. Nút «Gọi» / «Zalo» chép sẵn lời nhắn mời lấy máy',
        'Bước 7 — Đổi máy: «Đổi máy» trên máy đã bán → «Lấy máy trong kho cửa hàng» (tự xuất kho 1 máy) hoặc «Máy hãng gửi về» (không trừ kho); máy mới giữ hạn bảo hành còn lại',
        'Bước 8 — Tab «Sắp hết hạn» (30/60/90 ngày): «Nhắn Zalo» / «Gọi» nhắc khách. Tab «Báo cáo»: máy ở cửa hàng, quá hẹn, lượt bảo hành, phí đã / chưa thu, mặt hàng hay bảo hành',
      ],
      tip:
          'Luôn in phiếu tiếp nhận cho khách giữ — phiếu có số phiếu, seri, phụ kiện đã nhận để đối chiếu khi trả máy.',
      accent: Color(0xFF00897B),
      keywords: ['bảo hành', 'seri', 'IMEI', 'tiếp nhận bảo hành', 'phiếu bảo hành', 'đổi máy', 'trả khách', 'phí sửa', 'hết hạn bảo hành'],
      shots: [
        GuideShot('pos-warranty-2', afterBullet: 3, caption: '① Tìm theo seri / IMEI, khách, mã đơn và lọc tình trạng. ② Seri, sản phẩm, số tháng BH, ngày mua, hết hạn BH. ③ «Tiếp nhận BH» khi khách mang máy tới. ④ «Đổi máy».'),
        GuideShot('pos-warranty-1', afterBullet: 4, caption: '① Lọc phiếu: máy ở cửa hàng, chờ khách lấy, quá hẹn, đã trả khách. ② Số phiếu, sản phẩm và trạng thái («Sửa xong — chờ trả»). ③ «Trả khách» / «In phiếu». ④ Máy đang sửa: «Hoàn tất» hoặc «Từ chối».'),
        GuideShot('pos-warranty-3', afterBullet: 8, caption: '① Hiện tại: máy ở cửa hàng, chờ khách lấy, quá hẹn, máy còn bảo hành. ② Phí sửa đã thu / chưa thu trong kỳ. ③ Mặt hàng hay bảo hành (tỉ lệ lượt BH / máy đã bán).'),
      ],
    ),
    LandingUsageGuideStep(
      id: 'pos_bank_account',
      icon: Icons.account_balance_rounded,
      title: 'Tài khoản nhận tiền & VietQR',
      desc:
          'Số tài khoản ngân hàng của cửa hàng để khách chuyển khoản: màn thanh toán hiện QR VietQR đúng số tiền; bật Tingee để tiền về là đơn tự báo đã thanh toán.',
      bullets: [
        'Bước 1 — Thiết lập SBOX → Tài khoản nhận tiền → mục «Tài khoản ngân hàng cửa hàng» → «Thêm STK»',
        'Bước 2 — Chọn «Ngân hàng *», nhập «Tên chủ tài khoản *» (không dấu, đúng tên trên tài khoản) và «Số tài khoản *»; bật «Tài khoản mặc định VietQR» → Lưu',
        'Bước 3 — Có nhiều tài khoản: chọn tài khoản dùng khi bán ở ô «STK nhận tiền»; «Sửa» để đổi thông tin',
        'Bước 4 — Khi thanh toán chọn «Chuyển khoản»: màn bán hiện QR VietQR kèm số tiền và nội dung; khách quét bằng app ngân hàng',
        'Bước 5 — VietQR thường không tự báo có tiền: thu ngân kiểm tra tiền về rồi bấm hoàn tất thanh toán',
        'Bước 6 — Muốn tiền về là đơn tự xong: mục «Tự báo có tiền (Tingee)» → bật «Bật tự báo CK», gắn ngân hàng với Tingee, mua lượt thông báo; nội dung CK phải giữ mã đơn trên QR',
      ],
      tip:
          'Chỉ người có quyền Sửa «Tài khoản ngân hàng» mới đổi được STK nhận tiền — tránh nhân viên đổi STK sang tài khoản khác.',
      accent: Color(0xFF00897B),
      keywords: ['tài khoản nhận tiền', 'VietQR', 'QR chuyển khoản', 'số tài khoản', 'ngân hàng', 'Tingee', 'tự báo có tiền'],
      shots: [
        GuideShot('pos-bank-account-2', afterBullet: 2, caption: '① Chọn ngân hàng. ② Tên chủ tài khoản và số tài khoản. ③ «Tài khoản mặc định VietQR».'),
        GuideShot('pos-bank-account-1', afterBullet: 3, caption: '① «STK nhận tiền» dùng khi khách chuyển khoản. ② «Thêm STK» / «Sửa». ③ «Tự báo có tiền (Tingee)»: tiền về là đơn tự xong.'),
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

}
