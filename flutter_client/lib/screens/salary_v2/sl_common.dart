import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../utils/allowance_calculator.dart';
import '../../utils/shift_records_calculator.dart';
import '../../widgets/settings/settings_page.dart' show settingsMoney;
import '../../widgets/sbox/sbox_ui.dart';
import 'sl_model.dart';

/// Nhân viên kèm hồ sơ lương đang áp dụng.
class SlEmployee {
  SlEmployee(this.m, this.profile);
  final Map<String, dynamic> m;

  /// EmployeeBenefitDto (null = chưa thiết lập).
  final Map<String, dynamic>? profile;

  String get id => '${m['id'] ?? ''}';
  String get code => '${m['employeeCode'] ?? ''}';
  String get name {
    final n = '${m['lastName'] ?? ''} ${m['firstName'] ?? ''}'.trim();
    return n.isEmpty ? '${m['fullName'] ?? code}' : n;
  }

  String? get department => (m['department'] ?? m['departmentName'])?.toString();
  String? get position => m['position']?.toString();
  String? get branchId => m['branchId']?.toString();
  String? get photo => m['photoUrl']?.toString();

  Map<String, dynamic>? get benefit {
    final b = profile?['benefit'];
    return b is Map ? Map<String, dynamic>.from(b) : null;
  }

  String? get benefitId {
    final id = (profile?['benefitId'] ?? benefit?['id'])?.toString();
    return id == null || id.isEmpty ? null : id;
  }

  bool get configured => benefit != null;

  /// Thay đổi lương đã lên lịch (chưa tới ngày).
  Map<String, dynamic>? get upcoming {
    final u = profile?['upcoming'];
    return u is Map ? Map<String, dynamic>.from(u) : null;
  }

  DateTime? get upcomingFrom => DateTime.tryParse('${upcoming?['effectiveDate'] ?? ''}');

  /// Ngày bắt đầu của mức lương đang áp dụng.
  DateTime? get currentFrom => DateTime.tryParse('${profile?['effectiveDate'] ?? ''}');
  SalaryKind get kind => SalaryKindX.parse(benefit?['rateType']);

  String get initials {
    final p = name.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    if (p.length == 1) return p.first.characters.first.toUpperCase();
    return (p[p.length - 2].characters.first + p.last.characters.first).toUpperCase();
  }
}

/// Dữ liệu dùng chung cho màn thiết lập lương.
class SlContext {
  SlContext({
    required this.api,
    this.shifts = const [],
    this.allowances = const [],
    this.insurance = const {},
    this.store = const {},
  });

  final ApiService api;
  final List<Map<String, dynamic>> shifts;
  final List<Map<String, dynamic>> allowances;
  final Map<String, dynamic> insurance;
  Map<String, dynamic> store;

  double get stdDays {
    final v = store['standardWorkDays'];
    final d = v is num ? v.toDouble() : double.tryParse('$v');
    return d != null && d > 0 ? d : 26;
  }

  double get stdHours => parseStandardWorkHours(salarySettings: store);

  double otRate(String key, double fallback) {
    final v = store[key];
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(',', '.'));
    return d != null && d > 0 ? d : fallback;
  }

  List<String> get shiftNames => [for (final s in shifts) '${s['name'] ?? ''}'.trim()]..removeWhere((s) => s.isEmpty);

  List<Map<String, dynamic>> allowancesOf(SlEmployee e, int type) => [
        for (final a in allowances)
          if (a['isActive'] != false &&
              AllowanceCalculator.parseType(a['type']) == type &&
              AllowanceCalculator.isAssignedToEmployee(a, e.id, employeeCode: e.code))
            a,
      ];

  double allowanceTotal(SlEmployee e, int type) =>
      AllowanceCalculator.sumForEmployee(allowances: allowances, employeeId: e.id, employeeCode: e.code, allowanceType: type);
}

String money(num v) => '${settingsMoney(v)}đ';

/// Tóm tắt một dòng: «12.000.000đ/tháng».
String salarySummary(SlEmployee e) {
  final b = e.benefit;
  if (b == null) return 'Chưa thiết lập';
  final d = SalaryDraft.fromBenefit(b);
  if (d.kind == SalaryKind.shift && d.shiftType == 1) return 'Lương ca theo bậc';
  return '${money(d.mainRate)}${d.kind.unit}';
}

SboxTone kindTone(SalaryKind k) => switch (k) {
      SalaryKind.monthly => SboxTone.brand,
      SalaryKind.daily => SboxTone.success,
      SalaryKind.shift => SboxTone.violet,
      SalaryKind.hourly => SboxTone.warning,
    };

class SlAvatar extends StatelessWidget {
  const SlAvatar(this.e, {super.key, this.size = 40});
  final SlEmployee e;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: e.configured ? SboxColors.brand50 : SboxColors.slate100,
          shape: BoxShape.circle,
        ),
        child: Text(e.initials,
            style: TextStyle(
              color: e.configured ? SboxColors.brand700 : SboxColors.slate500,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.36,
            )),
      );
}

void slToast(BuildContext context, String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(m)),
      backgroundColor: error ? SboxColors.danger : null,
      behavior: SnackBarBehavior.floating,
    ));

/// Lưu hồ sơ lương cho một nhân viên: cập nhật hồ sơ đang dùng hoặc tạo mới rồi gán.
/// Trả về null khi thành công, ngược lại là thông báo lỗi.
Future<String?> saveSalaryFor(SlContext ctx, SlEmployee e, SalaryDraft d, {bool forceNew = false, DateTime? effectiveFrom}) async {
  final existing = forceNew || effectiveFrom != null ? null : e.benefitId;
  // Tên hồ sơ duy nhất trong cửa hàng: đính chính giữ tên đang dùng; phiên bản mới mang ngày áp dụng
  // (trước đây tạo trùng tên «Lương <tên> (<mã>)» → máy chủ từ chối, đổi lương từ ngày không lưu được).
  final currentName = (e.benefit?['name'] ?? '').toString().trim();
  final baseName = salaryProfileName(e.name, e.code);
  final name = existing != null && currentName.isNotEmpty
      ? currentName
      : (e.configured || effectiveFrom != null)
          ? '$baseName · từ ${dmy(effectiveFrom ?? DateTime.now())}'
          : baseName;
  final body = d.toBenefit(
    name: name,
    fixedAllowanceTotal: ctx.allowanceTotal(e, 0),
    dailyAllowanceTotal: ctx.allowanceTotal(e, 1),
    insuranceSettings: ctx.insurance,
    storeWeekendRate: ctx.otRate('weekendRate', 2.0),
  );
  String msg(Map r, String f) {
    final m = r['message']?.toString();
    if (m != null && m.isNotEmpty) return m;
    final errs = r['errors'];
    return errs is List && errs.isNotEmpty ? errs.join('\n') : f;
  }

  // Đổi lương từ một ngày: tạo hồ sơ mới, bản cũ kết thúc hôm trước (bảng lương tách đoạn).
  if (existing != null) {
    final r = await ctx.api.updateSalaryProfile(existing, body);
    return r['isSuccess'] == true ? null : msg(r, 'Không lưu được hồ sơ lương.');
  }
  var r = await ctx.api.createSalaryProfile(body);
  if (r['isSuccess'] != true && msg(r, '').contains('already exists')) {
    // Cùng ngày đã có hồ sơ cùng tên (đổi lương 2 lần trong ngày / hồ sơ cũ còn sót) → thêm giờ cho khác tên.
    final now = DateTime.now();
    final hm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    r = await ctx.api.createSalaryProfile({...body, 'name': '$name $hm'});
  }
  if (r['isSuccess'] != true) return msg(r, 'Không tạo được hồ sơ lương.');
  final data = r['data'];
  final id = data is Map ? data['id']?.toString() : null;
  if (id == null) return 'Máy chủ không trả về mã hồ sơ lương.';
  final a = await ctx.api.assignSalaryProfile({
    'employeeId': e.id,
    'benefitId': id,
    'effectiveDate': _ymd(effectiveFrom ?? DateTime.now()),
  });
  return a['isSuccess'] == true ? null : msg(a, 'Không gán được hồ sơ lương cho nhân viên.');
}

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
