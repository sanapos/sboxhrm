import 'package:flutter/material.dart';

import '../../widgets/hrm_page_chrome.dart';

/// Nhóm hiển thị theo pháp luật VN.
enum LeaveLegalCategory {
  employerPaid,
  unpaid,
  socialInsurance,
}

/// Nguồn chi trả (khớp API `paymentSource`).
enum LeavePaymentSource {
  employerPaid(0, 'DN trả lương', HrmPageChrome.chip, Icons.account_balance_wallet_rounded),
  unpaid(1, 'Không lương', HrmPageChrome.chipDark, Icons.money_off_rounded),
  socialInsurance(2, 'Trợ cấp BHXH', HrmPageChrome.chipLight, Icons.health_and_safety_rounded),
  employerBhxh(3, 'DN + đối soát BHXH', HrmPageChrome.chipMid, Icons.family_restroom_rounded);

  const LeavePaymentSource(this.value, this.label, this.color, this.icon);
  final int value;
  final String label;
  final Color color;
  final IconData icon;

  static LeavePaymentSource fromValue(dynamic v) {
    final n = v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
    return LeavePaymentSource.values.firstWhere(
      (e) => e.value == n,
      orElse: () => LeavePaymentSource.employerPaid,
    );
  }
}

enum SickLeaveMode {
  notApplicable(0),
  useAnnualLeave(1),
  socialInsurance(2);

  const SickLeaveMode(this.value);
  final int value;

  static SickLeaveMode fromValue(dynamic v) {
    final n = v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
    return SickLeaveMode.values.firstWhere(
      (e) => e.value == n,
      orElse: () => SickLeaveMode.notApplicable,
    );
  }
}

class LeaveCatalogEntry {
  final int leaveType;
  final LeaveLegalCategory category;
  final LeavePaymentSource paymentSource;
  final SickLeaveMode sickLeaveMode;
  final String title;
  final String subtitle;
  final String legalHint;
  final IconData icon;
  final Color color;
  final bool requiresBhxhNote;

  bool get usesAnnualBalance =>
      leaveType == 0 ||
      (leaveType == 4 && sickLeaveMode == SickLeaveMode.useAnnualLeave);

  const LeaveCatalogEntry({
    required this.leaveType,
    required this.category,
    required this.paymentSource,
    this.sickLeaveMode = SickLeaveMode.notApplicable,
    required this.title,
    required this.subtitle,
    required this.legalHint,
    required this.icon,
    required this.color,
    this.requiresBhxhNote = false,
  });
}

class LeaveCatalog {
  static const employerPaidCategory = LeaveLegalCategory.employerPaid;
  static const unpaidCategory = LeaveLegalCategory.unpaid;
  static const insuranceCategory = LeaveLegalCategory.socialInsurance;

  static String categoryTitle(LeaveLegalCategory c) => switch (c) {
        LeaveLegalCategory.employerPaid => 'Doanh nghiệp trả lương',
        LeaveLegalCategory.unpaid => 'Không hưởng lương',
        LeaveLegalCategory.socialInsurance => 'BHXH & chế độ đặc biệt',
      };

  static String categoryDescription(LeaveLegalCategory c) => switch (c) {
        LeaveLegalCategory.employerPaid =>
          'Phép năm, lễ, việc riêng có lương, nghỉ bù — DN trả theo HĐLĐ.',
        LeaveLegalCategory.unpaid =>
          'Nghỉ không lương theo thỏa thuận / nội quy.',
        LeaveLegalCategory.socialInsurance =>
          'Ốm BHXH, thai sản — không hưởng đồng thời lương DN và trợ cấp BHXH cùng ngày.',
      };

  static IconData categoryIcon(LeaveLegalCategory c) => switch (c) {
        LeaveLegalCategory.employerPaid => Icons.work_history_rounded,
        LeaveLegalCategory.unpaid => Icons.event_busy_rounded,
        LeaveLegalCategory.socialInsurance => Icons.medical_services_rounded,
      };

  static Color categoryColor(LeaveLegalCategory c) => switch (c) {
        LeaveLegalCategory.employerPaid => HrmPageChrome.chip,
        LeaveLegalCategory.unpaid => HrmPageChrome.chipDark,
        LeaveLegalCategory.socialInsurance => HrmPageChrome.chipLight,
      };

  static const List<LeaveCatalogEntry> all = [
    LeaveCatalogEntry(
      leaveType: 0,
      category: employerPaidCategory,
      paymentSource: LeavePaymentSource.employerPaid,
      title: 'Phép năm',
      subtitle: '100% lương HĐLĐ · trừ quỹ phép',
      legalHint: 'Theo lịch đã thỏa thuận hoặc quy định nội bộ.',
      icon: Icons.beach_access_rounded,
      color: HrmPageChrome.chip,
    ),
    LeaveCatalogEntry(
      leaveType: 1,
      category: employerPaidCategory,
      paymentSource: LeavePaymentSource.employerPaid,
      title: 'Nghỉ lễ, Tết',
      subtitle: 'Hưởng đủ lương ngày lễ',
      legalHint: 'Ngày lễ quốc gia theo Bộ luật Lao động.',
      icon: Icons.celebration_rounded,
      color: HrmPageChrome.chipMid,
    ),
    LeaveCatalogEntry(
      leaveType: 2,
      category: employerPaidCategory,
      paymentSource: LeavePaymentSource.employerPaid,
      title: 'Việc riêng có lương',
      subtitle: 'Tang, hôn nhân, con ốm…',
      legalHint: 'Theo BLLĐ và nội quy công ty.',
      icon: Icons.paid_rounded,
      color: HrmPageChrome.chipLight,
    ),
    LeaveCatalogEntry(
      leaveType: 6,
      category: employerPaidCategory,
      paymentSource: LeavePaymentSource.employerPaid,
      title: 'Nghỉ bù',
      subtitle: 'Bù tăng ca / làm thêm',
      legalHint: 'Ghi nhận theo chính sách nghỉ bù của DN.',
      icon: Icons.swap_horiz_rounded,
      color: HrmPageChrome.chipSoft,
    ),
    LeaveCatalogEntry(
      leaveType: 3,
      category: unpaidCategory,
      paymentSource: LeavePaymentSource.unpaid,
      title: 'Việc riêng không lương',
      subtitle: 'Không tính vào lương',
      legalHint: 'Cần thỏa thuận với quản lý.',
      icon: Icons.money_off_rounded,
      color: HrmPageChrome.chipDark,
    ),
    LeaveCatalogEntry(
      leaveType: 7,
      category: unpaidCategory,
      paymentSource: LeavePaymentSource.unpaid,
      title: 'Nghỉ dài hạn',
      subtitle: 'Không lương / chế độ riêng',
      legalHint: 'Áp dụng theo nội quy hoặc thỏa thuận dài hạn.',
      icon: Icons.hourglass_full_rounded,
      color: HrmPageChrome.chipMuted,
    ),
    LeaveCatalogEntry(
      leaveType: 4,
      category: insuranceCategory,
      paymentSource: LeavePaymentSource.socialInsurance,
      sickLeaveMode: SickLeaveMode.socialInsurance,
      title: 'Nghỉ ốm — hưởng BHXH',
      subtitle: 'Trợ cấp từ quỹ BHXH',
      legalHint:
          'Cần giấy nghỉ hợp lệ. Không đồng thời nhận lương DN cho cùng ngày nghỉ.',
      icon: Icons.local_hospital_rounded,
      color: Color(0xFF003B80),
      requiresBhxhNote: true,
    ),
    LeaveCatalogEntry(
      leaveType: 4,
      category: employerPaidCategory,
      paymentSource: LeavePaymentSource.employerPaid,
      sickLeaveMode: SickLeaveMode.useAnnualLeave,
      title: 'Ốm — dùng phép năm',
      subtitle: 'DN trả 100% HĐLĐ · trừ phép năm',
      legalHint:
          'Chọn khi NV dùng phép năm thay vì chế độ ốm BHXH. Mỗi ngày chỉ một chế độ.',
      icon: Icons.beach_access_outlined,
      color: HrmPageChrome.chip,
    ),
    LeaveCatalogEntry(
      leaveType: 5,
      category: insuranceCategory,
      paymentSource: LeavePaymentSource.employerBhxh,
      title: 'Thai sản',
      subtitle: 'DN + trợ cấp BHXH',
      legalHint:
          'DN đảm bảo thu nhập theo BLLĐ; đối soát trợ cấp thai sản từ BHXH.',
      icon: Icons.child_friendly_rounded,
      color: HrmPageChrome.chipLight,
      requiresBhxhNote: true,
    ),
  ];

  static List<LeaveCatalogEntry> forCategory(LeaveLegalCategory cat) =>
      all.where((e) => e.category == cat).toList();

  static LeaveCatalogEntry? findEntry({
    required int leaveType,
    SickLeaveMode? sickMode,
  }) {
    final sm = sickMode ?? SickLeaveMode.notApplicable;
    for (final e in all) {
      if (e.leaveType == leaveType && e.sickLeaveMode == sm) return e;
    }
    final matches = all.where((e) => e.leaveType == leaveType).toList();
    return matches.isEmpty ? null : matches.first;
  }

  static LeaveDisplay displayFor(Map<String, dynamic> leave) {
    final type = normalizeLeaveType(leave['type']);
    final sm = SickLeaveMode.fromValue(leave['sickLeaveMode'] ?? 0);
    final entry = findEntry(leaveType: type, sickMode: sm);
    final ps = LeavePaymentSource.fromValue(
      leave['paymentSource'] ?? entry?.paymentSource.value ?? 0,
    );
    if (entry != null) {
      return LeaveDisplay(
        title: entry.title,
        subtitle: entry.subtitle,
        color: entry.color,
        icon: entry.icon,
        paymentSource: ps,
        legalHint: entry.legalHint,
      );
    }
    return LeaveDisplay(
      title: 'Loại phép #$type',
      subtitle: ps.label,
      color: ps.color,
      icon: ps.icon,
      paymentSource: ps,
      legalHint: '',
    );
  }
}

class LeaveDisplay {
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final LeavePaymentSource paymentSource;
  final String legalHint;

  const LeaveDisplay({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.paymentSource,
    required this.legalHint,
  });
}

int normalizeLeaveType(dynamic type) {
  if (type is int) return type.clamp(0, 7);
  final s = type?.toString().toLowerCase() ?? '';
  switch (s) {
    case 'annualleave':
    case 'annual':
    case '0':
      return 0;
    case 'holiday':
    case '1':
      return 1;
    case 'personalpaid':
    case '2':
      return 2;
    case 'personalunpaid':
    case '3':
      return 3;
    case 'sickleave':
    case 'sick':
    case '4':
      return 4;
    case 'maternityleave':
    case 'maternity':
    case '5':
      return 5;
    case 'compensatoryleave':
    case 'compensatory':
    case '6':
      return 6;
    case 'longtermleave':
    case 'longterm':
    case '7':
      return 7;
    default:
      return int.tryParse(s) ?? 0;
  }
}
