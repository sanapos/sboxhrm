import 'dart:convert';

/// Tính phụ cấp NV từ danh mục — dùng chung Thiết lập lương & Tổng hợp lương.
class AllowanceCalculator {
  AllowanceCalculator._();

  /// API trả Type dạng "Fixed"/"Daily" (JsonStringEnumConverter) hoặc int 0..3.
  static int parseType(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final s = value?.toString().toLowerCase() ?? '';
    switch (s) {
      case 'daily':
      case '1':
        return 1;
      case 'hourly':
      case '2':
        return 2;
      case 'perevent':
      case 'per_event':
      case '3':
        return 3;
      case 'pershift':
      case 'per_shift':
      case '4':
        return 4;
      case 'fixed':
      case '0':
      default:
        return 0;
    }
  }

  /// null employeeIds = áp dụng tất cả NV; danh sách rỗng = không gán ai.
  static bool isAssignedToEmployee(
    Map<String, dynamic> allowance,
    String employeeId, {
    String? employeeCode,
  }) {
    if (employeeId.isEmpty) return false;
    final raw = allowance['employeeIds'];
    if (raw == null) return true;

    List<String> ids = [];
    if (raw is List) {
      ids = raw.map((e) => e.toString()).toList();
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          ids = parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    if (ids.isEmpty) return false;
    final key = employeeId.toLowerCase();
    if (ids.any((id) => id.toLowerCase() == key)) return true;
    if (employeeCode != null && employeeCode.isNotEmpty) {
      final codeKey = employeeCode.toLowerCase();
      if (ids.any((id) => id.toLowerCase() == codeKey)) return true;
    }
    return false;
  }

  static double _amount(Map<String, dynamic> allowance) {
    final amount = allowance['amount'];
    if (amount is num) return amount.toDouble();
    if (amount is String) return double.tryParse(amount) ?? 0;
    return 0;
  }

  /// Tổng mức phụ cấp theo loại (0=cố định, 1=theo ngày, 2=theo giờ, 4=theo ca).
  ///
  /// [benefitFallback] đã bỏ dùng trên UI Thiết lập lương (số meal/responsibility
  /// cũ không sửa được). Giữ tham số để tương thích gọi cũ — không nên truyền.
  static double sumForEmployee({
    required List<Map<String, dynamic>> allowances,
    required String employeeId,
    required int allowanceType,
    bool requireActive = true,
    String? employeeCode,
    Map<String, dynamic>? benefitFallback,
  }) {
    if (employeeId.isEmpty) return 0;
    var total = 0.0;
    for (final a in allowances) {
      if (requireActive && a['isActive'] == false) continue;
      if (parseType(a['type']) != allowanceType) continue;
      if (!isAssignedToEmployee(a, employeeId, employeeCode: employeeCode)) {
        continue;
      }
      final val = _amount(a);
      if (val > 0) total += val;
    }
    return total;
  }

  static List<String> shiftIdsOf(Map<String, dynamic> allowance) {
    final raw = allowance['shiftIds'] ?? allowance['ShiftIds'];
    if (raw == null) return const [];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          return parsed
              .map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  /// Phụ cấp theo ca: mỗi mức chỉ nhân với số lần chấm đủ đúng ca đã chọn.
  static double earnedForShifts({
    required List<Map<String, dynamic>> allowances,
    required String employeeId,
    required Iterable<String?> workedShiftIds,
    bool requireActive = true,
    String? employeeCode,
  }) {
    if (employeeId.isEmpty) return 0;
    final worked = workedShiftIds
        .map((id) => id?.toLowerCase() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (worked.isEmpty) return 0;
    var total = 0.0;
    for (final a in allowances) {
      if (requireActive && a['isActive'] == false) continue;
      if (parseType(a['type']) != 4) continue;
      if (!isAssignedToEmployee(a, employeeId, employeeCode: employeeCode)) {
        continue;
      }
      final ids = shiftIdsOf(a).map((id) => id.toLowerCase()).toSet();
      if (ids.isEmpty) continue;
      final count = worked.where(ids.contains).length;
      if (count == 0) continue;
      final val = _amount(a);
      if (val > 0) total += val * count;
    }
    return total;
  }

  // ═══ Điều kiện nhận (phụ cấp theo ngày / theo ca) ═══

  static double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  /// % thời lượng ca tối thiểu (null = không theo %).
  static double? minWorkPercent(Map<String, dynamic> a) {
    final v = _num(a['minWorkPercent'] ?? a['MinWorkPercent']);
    return v != null && v > 0 ? v.clamp(0, 100).toDouble() : null;
  }

  /// Số giờ tối thiểu trong ca (null = không theo giờ). Bị bỏ qua nếu đã đặt %.
  static double? minWorkHours(Map<String, dynamic> a) {
    if (minWorkPercent(a) != null) return null;
    final v = _num(a['minWorkHours'] ?? a['MinWorkHours']);
    return v != null && v > 0 ? v : null;
  }

  static bool hasWorkRule(Map<String, dynamic> a) => minWorkPercent(a) != null || minWorkHours(a) != null;

  /// Số phút phải làm để nhận phụ cấp, với ca dài [requiredMinutes] phút. Null = không điều kiện.
  static int? thresholdMinutes(Map<String, dynamic> a, int requiredMinutes) {
    final pct = minWorkPercent(a);
    if (pct != null) return (requiredMinutes * pct / 100).ceil();
    final h = minWorkHours(a);
    if (h != null) return (h * 60).round();
    return null;
  }

  /// Mô tả điều kiện cho màn thiết lập, vd «Làm từ 90% thời lượng ca (ca 5 tiếng cần từ 4 giờ 30 phút)».
  static String describeRule(Map<String, dynamic> a, {int exampleShiftMinutes = 300}) {
    final pct = minWorkPercent(a);
    if (pct != null) {
      final t = thresholdMinutes(a, exampleShiftMinutes)!;
      return 'Làm từ ${_trimNum(pct)}% thời lượng ca '
          '(ca ${_trimNum(exampleShiftMinutes / 60)} tiếng cần từ ${fmtMinutes(t)})';
    }
    final h = minWorkHours(a);
    if (h != null) return 'Làm trong ca từ ${fmtMinutes((h * 60).round())}';
    return 'Không điều kiện';
  }

  static String _trimNum(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1).replaceAll('.', ',');

  /// 270 → «4 giờ 30 phút».
  static String fmtMinutes(int m) {
    final h = m ~/ 60, mm = m % 60;
    if (h == 0) return '$mm phút';
    return mm == 0 ? '$h giờ' : '$h giờ $mm phút';
  }

  /// Phụ cấp theo ngày + theo ca có điều kiện thời gian làm trong ca.
  ///
  /// [units]: mỗi ca đã chấm đủ vào/ra (ngày, ca, phút làm trong khung ca, thời lượng ca).
  /// [eligibleDays]: ngày có công (không tính ngày chỉ tăng ca) → công gốc (0.5 / 1), chưa nhân hệ số lễ.
  /// Không điều kiện: theo ngày = mức × tổng công gốc; theo ca = mức × số ca đã chấm đủ.
  /// Có điều kiện: theo ngày = mức × số ngày đạt (tổng phút trong các ca của ngày ≥ ngưỡng);
  /// theo ca = mức × số ca đạt ngưỡng.
  static AllowanceEarned earnedWithRules({
    required List<Map<String, dynamic>> allowances,
    required String employeeId,
    required List<AllowanceWorkUnit> units,
    required Map<String, double> eligibleDays,
    required int standardDayMinutes,
    bool requireActive = true,
    String? employeeCode,
  }) {
    final out = AllowanceEarned();
    if (employeeId.isEmpty) return out;
    final byDay = <String, List<AllowanceWorkUnit>>{};
    for (final u in units) {
      if (eligibleDays.containsKey(u.dayKey)) (byDay[u.dayKey] ??= []).add(u);
    }
    for (final a in allowances) {
      if (requireActive && a['isActive'] == false) continue;
      final type = parseType(a['type']);
      if (type != 1 && type != 4) continue;
      if (!isAssignedToEmployee(a, employeeId, employeeCode: employeeCode)) continue;
      final amount = _amount(a);
      if (amount <= 0) continue;
      final name = '${a['name'] ?? 'Phụ cấp'}';
      final ruled = hasWorkRule(a);

      if (type == 1) {
        if (!ruled) {
          final days = eligibleDays.values.fold(0.0, (s, v) => s + v);
          out.daily += amount * days;
          if (days > out.dailyDays) out.dailyDays = days;
          continue;
        }
        var ok = 0;
        for (final e in byDay.entries) {
          final worked = e.value.fold(0, (s, u) => s + u.workedMinutes);
          final required = e.value.fold(0, (s, u) => s + (u.requiredMinutes ?? standardDayMinutes));
          final need = thresholdMinutes(a, required)!;
          if (worked >= need) {
            ok++;
          } else {
            out.misses.add(AllowanceMiss(e.key, name, null, worked, need));
          }
        }
        out.daily += amount * ok;
        if (ok > out.dailyDays) out.dailyDays = ok.toDouble();
      } else {
        final ids = shiftIdsOf(a).map((id) => id.toLowerCase()).toSet();
        if (ids.isEmpty) continue;
        var ok = 0;
        for (final u in units) {
          if (u.shiftId == null || !ids.contains(u.shiftId!.toLowerCase())) continue;
          final need = ruled ? thresholdMinutes(a, u.requiredMinutes ?? standardDayMinutes)! : 0;
          if (u.workedMinutes >= need) {
            ok++;
          } else {
            out.misses.add(AllowanceMiss(u.dayKey, name, u.shiftName, u.workedMinutes, need));
          }
        }
        out.shift += amount * ok;
        out.shiftCount += ok;
      }
    }
    out.misses.sort((x, y) => x.dayKey.compareTo(y.dayKey));
    return out;
  }
}

/// Một ca đã chấm đủ vào/ra: phút làm trong khung ca và thời lượng ca (null = không có khung ca).
class AllowanceWorkUnit {
  const AllowanceWorkUnit({
    required this.dayKey,
    required this.shiftId,
    required this.workedMinutes,
    required this.requiredMinutes,
    this.shiftName,
  });
  final String dayKey;
  final String? shiftId;
  final String? shiftName;
  final int workedMinutes;
  final int? requiredMinutes;

  static String keyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Ngày / ca bị loại khỏi phụ cấp vì làm không đủ thời gian.
class AllowanceMiss {
  AllowanceMiss(this.dayKey, this.allowanceName, this.shiftName, this.workedMinutes, this.requiredMinutes);
  final String dayKey;
  final String allowanceName;
  final String? shiftName;
  final int workedMinutes;
  final int requiredMinutes;

  String get label {
    final p = dayKey.split('-');
    final d = p.length == 3 ? '${p[2]}/${p[1]}' : dayKey;
    final shift = shiftName == null || shiftName!.isEmpty ? '' : ' $shiftName';
    return '$d$shift: $allowanceName — làm ${AllowanceCalculator.fmtMinutes(workedMinutes)}'
        ' / cần ${AllowanceCalculator.fmtMinutes(requiredMinutes)}';
  }
}

class AllowanceEarned {
  double daily = 0;
  double shift = 0;
  /// Số ngày được phụ cấp theo ngày (khoản nhiều ngày nhất).
  double dailyDays = 0;
  int shiftCount = 0;
  final List<AllowanceMiss> misses = [];
}
