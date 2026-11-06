import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Biến thể app: HRM (mặc định) hoặc POS độc lập cho Play Store.
///
/// Bật POS bằng `--flavor pos` (package `sbox.sana.vn.pos`) và/hoặc
/// `--dart-define=SBOX_POS_STANDALONE=true`.
/// SBOX KDS (chỉ màn hình bếp, Android 7+): `--flavor kds --dart-define=SBOX_APP=kds`
/// (package `kds.sboxpos.com`) — là một dạng POS độc lập. Bản KDS Android 6 vẫn build từ flutter_pos.
/// SBOX Nhân Viên (app nhân viên: chấm công, lịch, lương, đơn từ, gọi món):
/// `--flavor staff --dart-define=SBOX_APP=staff` (package `staff.sboxpos.com`).
/// SBOX BOSS (app chủ cửa hàng): `--flavor boss` (package `boss.sboxpos.com`) và/hoặc
/// `--dart-define=SBOX_APP=boss` — chỉ chủ / quản lý đăng nhập, mở thẳng màn tổng quan BOSS.
/// Web: `sboxpos.com` chỉ branding POS; `sboxhrm.com` chỉ branding HRM.
abstract final class SboxAppVariant {
  static const androidPosApplicationId = 'sbox.sana.vn.pos';
  static const iosPosBundleId = 'com.sboxpos';
  static const androidKdsApplicationId = 'kds.sboxpos.com';
  static const androidStaffApplicationId = 'staff.sboxpos.com';
  static const androidBossApplicationId = 'boss.sboxpos.com';
  static const posGreen = 0xFF2E7D32;
  static const hrmBlue = 0xFF0C56D0;

  static const bool _fromDefine = bool.fromEnvironment(
    'SBOX_POS_STANDALONE',
    defaultValue: false,
  );

  static const bool _kdsFromDefine =
      String.fromEnvironment('SBOX_APP') == 'kds';
  static const bool _bossFromDefine =
      String.fromEnvironment('SBOX_APP') == 'boss';

  static const bool _staffFromDefine =
      String.fromEnvironment('SBOX_APP') == 'staff';

  static bool _fromPackage = false;
  static bool _kdsFromPackage = false;
  static bool _staffFromPackage = false;
  static bool _bossFromPackage = false;

  /// App SBOX KDS: đăng nhập xong chỉ mở màn hình bếp.
  static bool get kitchenApp => _kdsFromDefine || _kdsFromPackage;

  /// App SBOX Nhân Viên: khung tự phục vụ cho nhân viên ([StaffShell]), không mở menu quản trị HRM.
  static bool get staffApp => _staffFromDefine || _staffFromPackage;

  static bool get standalonePos => _fromDefine || _fromPackage || kitchenApp;

  /// SBOX POS trên iOS: thêm [iosStoreApp], không khuôn mặt, không vị trí, không nhắc chức năng nhân sự.
  static bool get iosPosApp =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && standalonePos && !kitchenApp;

  /// App bán trên App Store (POS, BOSS, Nhân Viên): không đăng ký tài khoản, không mời mua, gia hạn, không nhắc nền tảng khác.
  static bool get iosStoreApp =>
      iosPosApp || (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && (bossApp || staffApp));

  /// App SBOX BOSS: đăng nhập xong mở shell BOSS (tổng quan / cuối ngày), không vào HRM hay POS.
  static bool get bossApp => _bossFromDefine || _bossFromPackage;

  /// BOSS / Nhân Viên / KDS: không hiện thương hiệu HRM, chọn máy chủ cuối màn đăng nhập.
  static bool get companionApp => bossApp || staffApp || kitchenApp;

  /// Mặc định nối sboxpos.com khi chưa chọn máy chủ khác.
  static bool get defaultsToPosServer => standalonePos || bossApp || staffApp;

  /// SBOX POS gắn cố định máy chủ lúc build, không đổi được trong app.
  static bool get fixedServer => standalonePos && !kitchenApp;

  /// Tên miền HRM trong chữ hiển thị — không đụng địa chỉ email (sboxhrm@gmail.com).
  static final RegExp _hrmDomainWord = RegExp(r'(?<!@)sboxhrm(?!@)');
  static final RegExp _hrmWord = RegExp(r'\bHRM\b');
  static final RegExp _packageBlocked =
      RegExp(r'Gói dịch vụ[^"]*không bao gồm chức năng "[^"]*"\.?( Vui lòng nâng cấp gói\.?)?');

  /// Máy chủ từ chối vì gói của cửa hàng không có chức năng (câu gốc kèm mã module).
  static bool isPackageBlocked(String? message) =>
      message != null && _packageBlocked.hasMatch(message);

  /// Tên hiển thị trong app đồng hành: «SBOX HRM» → tên app, «Thiết lập HRM» → «Thiết lập SBOX»,
  /// tên miền HRM → sboxpos.com.
  static String rebrand(String s) {
    if (!companionApp && !standalonePos) return s;
    if (isPackageBlocked(s)) {
      s = s.replaceAll(_packageBlocked, 'Gói dịch vụ của cửa hàng chưa có chức năng này. Liên hệ đại lý để nâng cấp gói.');
    }
    if (iosStoreApp) s = iosPosText(s);
    if (!s.contains(RegExp(r'sboxhrm|\bHRM\b'))) return s;
    return s
        .replaceAll('SBOX HRM · SBOX POS', productLine)
        .replaceAll('SBOX HRM - SBOX POS', productLine)
        .replaceAll('SBOX HRM', productLine)
        .replaceAll(_hrmWord, 'SBOX')
        .replaceAll(_hrmDomainWord, 'sboxpos');
  }

  static final RegExp _renewalPrompt = RegExp(
    // «gia hạn» riêng lẻ là việc của cửa hàng (gia hạn gói hội viên), chỉ lọc khi là lời mời gia hạn SBOX.
    r',?\s*(?:(?:liên hệ (?:đại lý|quản trị viên)(?: để)?|vui lòng|hãy)\s+(?:nâng cấp gói|gia hạn)|nâng cấp gói)[^.]*\.?',
    caseSensitive: false,
  );
  static final RegExp _otherPlatform = RegExp(r'\b(?:Android|Windows|Google Play|CH Play|APK)\b', caseSensitive: false);

  /// App Store: không nhắc nền tảng khác (2.3.10) và không mời mua hay gia hạn dịch vụ ngoài app (3.1.1).
  static String iosPosText(String s) {
    final renewalFree = s.replaceAll(_renewalPrompt, '').trim();
    if (renewalFree.isNotEmpty && renewalFree != s) {
      s = RegExp(r'[.!?:]$').hasMatch(renewalFree) ? renewalFree : '$renewalFree.';
    }
    if (!s.contains(_otherPlatform)) return s;
    return s
        .replaceAll('Cài đặt Android', 'Cài đặt')
        .replaceAll('máy POS Android', 'máy POS')
        .replaceAll('Điện thoại Android', 'Điện thoại')
        .replaceAll(' (Android)', '')
        .replaceAll('Android Flutter', 'Ứng dụng')
        .replaceAll('App Windows', 'Máy tính')
        .replaceAll('app Windows', 'máy tính')
        .replaceAll(_otherPlatform, 'thiết bị');
  }

  /// Chính sách / trợ giúp trong SBOX POS iOS: bỏ phần khuôn mặt, vị trí, chấm công (app không có).
  static String stripIosPosLegal(String s) {
    final kept = <String>[];
    var skipLevel = 0;
    var section = 0;
    for (final line in s.split('\n')) {
      final heading = RegExp(r'^(#{2,3}) ').firstMatch(line);
      final hrTopic = RegExp('khuôn mặt|vị trí|nhân sự', caseSensitive: false).hasMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        if (skipLevel != 0 && level > skipLevel) continue;
        skipLevel = hrTopic ? level : 0;
        if (hrTopic) continue;
      }
      if (skipLevel != 0) continue;
      if (RegExp('khuôn mặt|vị trí|GPS|sinh trắc|chấm công', caseSensitive: false).hasMatch(line)) continue;
      final numbered = RegExp(r'^## \d+\. (.*)$').firstMatch(line);
      kept.add(numbered == null ? line : '## ${++section}. ${numbered.group(1)}');
    }
    return kept.join('\n');
  }

  /// Chính sách / điều khoản: pháp nhân sản phẩm ghi là SBOX POS. Email hỗ trợ giữ nguyên.
  static String rebrandLegal(String s) {
    if (iosPosApp) return stripIosPosLegal(s);
    if (!companionApp) return s;
    return s
        .replaceAll(
          'phần mềm quản lý nhân sự **SBOX HRM** và phần mềm bán hàng **SBOX POS**',
          'phần mềm quản lý bán hàng và nhân sự **SBOX POS**',
        )
        .replaceAll('ứng dụng SBOX (SBOX HRM, SBOX POS)', 'ứng dụng SBOX POS')
        .replaceAll('- **SBOX HRM**:', '- **Nhân sự**:')
        .replaceAll('- **SBOX POS**:', '- **Bán hàng**:')
        .replaceAll(' (sboxhrm.com, sboxpos.com)', '')
        .replaceAll('Website: sboxhrm.com · sboxpos.com', 'Website: sboxpos.com')
        .replaceAll('SBOX HRM', 'SBOX POS');
  }

  /// Thư mục Tải về / Ảnh chứa tệp xuất (khớp MainActivity.exportFolderName).
  static String get exportFolderName => companionApp || standalonePos ? productLine : 'SBOX HRM';

  /// Chức năng nhân sự không có trong app SBOX POS: menu, Trang chủ, tìm nhanh, thanh dưới đều ẩn.
  static const posAppHiddenModules = <String>{
    'Employee', 'DeviceUser', 'Department', 'Leave', 'SalarySettings', 'Attendance', 'WorkSchedule',
    'AttendanceSummary', 'AttendanceByShift', 'LateEarlyReport', 'TravelHoursReport', 'AttendanceApproval',
    'ScheduleApproval', 'MobileAttendanceApproval', 'Payslip', 'Payroll', 'MobileDeviceRegistration',
    'MobileAttendance', 'Meal', 'BonusPenalty', 'AdvanceRequests', 'BusinessTripExpense', 'Asset', 'Task',
    'Communication', 'KPI', 'Production', 'Feedback', 'FieldCheckIn', 'AttendanceReport', 'PenaltyReport',
    'AdvanceReport', 'BusinessTripReport', 'LeaveReport', 'AssetReport', 'PenaltyTickets', 'ShiftSwap',
    'HrAnalyticsReport',
  };

  static bool hidesModule(String? moduleCode) =>
      standalonePos && moduleCode != null && posAppHiddenModules.contains(moduleCode);

  /// SBOX POS dùng cùng khung với POS trong HRM trên mọi cỡ màn (menu trái / thanh dưới); chỉ KDS dùng shell riêng.
  static bool get posUsesMainLayout => standalonePos && !kitchenApp;

  /// Trang web sboxpos.com — chỉ đổi logo/chữ login & marketing, không đổi shell app.
  static bool get posWebHost {
    if (!kIsWeb) return false;
    final h = Uri.base.host.toLowerCase();
    return h == 'sboxpos.com' ||
        h == 'www.sboxpos.com' ||
        h.startsWith('sboxpos.');
  }

  static bool get posBranding => standalonePos || posWebHost;

  static String get productLine => bossApp
      ? 'SBOX BOSS'
      : kitchenApp
      ? 'SBOX KDS'
      : (posBranding ? 'SBOX POS' : (staffApp ? 'SBOX Nhân Viên' : 'SBOX HRM'));

  static String get slogan => bossApp
      ? 'Nắm cửa hàng mọi lúc, mọi nơi'
      : posBranding
      ? 'Giải pháp toàn diện giúp cửa hàng vận hành hiệu quả, tối ưu doanh thu'
      : 'Chấm công nhanh · Tính lương chuẩn';

  static String get loginHeroTitle => bossApp
      ? 'Doanh thu, rủi ro, việc cần duyệt\nngay trên điện thoại'
      : posBranding
      ? 'Bán hàng nhanh\nQuản lý cửa hàng chuẩn'
      : 'Chấm công & tính lương\nthời gian thực';

  static String get loginSubtitle => bossApp
      ? 'Đăng nhập bằng tài khoản chủ / quản lý cửa hàng.'
      : kitchenApp
      ? 'Đăng nhập để mở màn hình bếp SBOX KDS.'
      : posBranding
      ? 'Nhập thông tin để vào SBOX POS.'
      : staffApp
      ? 'Đăng nhập bằng tài khoản nhân viên để chấm công, xem lịch và phiếu lương.'
      : 'Nhập thông tin để truy cập hệ thống quản trị.';

  static String get registerTitle =>
      posBranding ? 'Đăng ký cửa hàng' : 'Đăng ký doanh nghiệp';

  static String get registerSubtitle => posBranding
      ? 'Tạo tài khoản SBOX POS để bắt đầu bán hàng.'
      : 'Tạo tài khoản doanh nghiệp mới để bắt đầu.';

  static String get registerButton =>
      posBranding ? 'Đăng ký cửa hàng' : 'Đăng ký doanh nghiệp';

  static String get copyright => '© 2026 $productLine';

  static String get logoAsset => bossApp
      ? 'assets/sbox_boss_logo.png'
      : staffApp
      ? 'assets/sbox_staff_logo.png'
      : kitchenApp
      ? 'assets/sbox_kds_logo.png'
      : standalonePos
      ? 'assets/sbox_pos_mark.png'
      : (posBranding ? 'assets/sbox_pos_logo.png' : 'assets/logo.png');

  /// Logo «S» trong app (menu, màn khách): HRM giữ logo gốc, SBOX POS chữ S xanh lá, app đồng hành dùng logo riêng.
  static String get markAsset => companionApp
      ? logoAsset
      : (standalonePos ? 'assets/sbox_pos_mark.png' : 'assets/logo.png');

  static String get materialAppTitle => productLine;

  static Future<void> bootstrap() async {
    if (_fromDefine || _kdsFromDefine || _staffFromDefine || _bossFromDefine || kIsWeb) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _fromPackage = info.packageName == androidPosApplicationId || info.packageName == iosPosBundleId;
      _kdsFromPackage = info.packageName == androidKdsApplicationId;
      _staffFromPackage = info.packageName == androidStaffApplicationId;
      _bossFromPackage = info.packageName == androidBossApplicationId;
    } catch (_) {}
  }
}
