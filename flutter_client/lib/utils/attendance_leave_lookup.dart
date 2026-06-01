import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Loại hiển thị ô không có chấm công (phân tích chéo).
enum AbsenceCellKind {
  holiday,
  weeklyOff,
  approvedLeave,
  pendingLeave,
  unpaidAbsent,
}

/// Đối chiếu ngày vắng với đơn nghỉ phép (đã duyệt / chờ duyệt).
class AttendanceLeaveLookup {
  final Set<String> _approvedKeys;
  final Set<String> _pendingKeys;

  AttendanceLeaveLookup._({
    required Set<String> approvedKeys,
    required Set<String> pendingKeys,
  })  : _approvedKeys = approvedKeys,
        _pendingKeys = pendingKeys;

  static String _dateKey(DateTime d) =>
      DateFormat('yyyy-MM-dd').format(DateTime(d.year, d.month, d.day));

  static void _addKeysForLeave(
    Set<String> keys,
    Map<String, dynamic> lv,
    List<Map<String, dynamic>>? employeesList,
  ) {
    final from = DateTime.tryParse(
            lv['fromDate']?.toString() ?? lv['startDate']?.toString() ?? '') ??
        DateTime.tryParse(lv['startDate']?.toString() ?? '');
    final to = DateTime.tryParse(
            lv['toDate']?.toString() ?? lv['endDate']?.toString() ?? '') ??
        from;
    if (from == null || to == null) return;

    final identifiers = <String>{};
    void addId(String? v) {
      if (v != null && v.isNotEmpty) identifiers.add(v);
    }

    addId(lv['employeeCode']?.toString());
    addId(lv['employeeUserId']?.toString());
    addId(lv['employeeId']?.toString());

    final empUserId = lv['employeeUserId']?.toString();
    final hrEmpId = lv['employeeId']?.toString();
    if (employeesList != null) {
      for (final e in employeesList) {
        if (e['applicationUserId']?.toString() == empUserId ||
            e['id']?.toString() == hrEmpId) {
          addId(e['employeeCode']?.toString());
          addId(e['applicationUserId']?.toString());
          addId(e['id']?.toString());
        }
      }
    }

    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    for (var cur = start; !cur.isAfter(end); cur = cur.add(const Duration(days: 1))) {
      final dk = _dateKey(cur);
      for (final id in identifiers) {
        keys.add('$id|$dk');
      }
    }
  }

  factory AttendanceLeaveLookup.fromLeaves(
    List<dynamic> leaves, {
    List<Map<String, dynamic>>? employeesList,
    bool includePending = true,
  }) {
    final approved = <String>{};
    final pending = <String>{};

    for (final lv in leaves) {
      if (lv is! Map<String, dynamic>) continue;
      final status = lv['status'];
      final isApproved = status == 1 ||
          status == 'Approved' ||
          status == 'approved' ||
          status == 'APPROVED';
      final isPending = status == 0 ||
          status == 'Pending' ||
          status == 'pending' ||
          status == 'PENDING';

      if (isApproved) {
        _addKeysForLeave(approved, lv, employeesList);
      } else if (includePending && isPending) {
        _addKeysForLeave(pending, lv, employeesList);
      }
    }

    return AttendanceLeaveLookup._(
      approvedKeys: approved,
      pendingKeys: pending,
    );
  }

  bool _matches(String? code, String? userId, String? hrId, String dateKey) {
    final ids = <String>[
      if (code != null && code.isNotEmpty) code,
      if (userId != null && userId.isNotEmpty) userId,
      if (hrId != null && hrId.isNotEmpty) hrId,
    ];
    for (final id in ids) {
      if (_approvedKeys.contains('$id|$dateKey')) return true;
    }
    return false;
  }

  bool _matchesPending(String? code, String? userId, String? hrId, String dateKey) {
    final ids = <String>[
      if (code != null && code.isNotEmpty) code,
      if (userId != null && userId.isNotEmpty) userId,
      if (hrId != null && hrId.isNotEmpty) hrId,
    ];
    for (final id in ids) {
      if (_pendingKeys.contains('$id|$dateKey')) return true;
    }
    return false;
  }

  AbsenceCellKind classify({
    required DateTime day,
    required String? employeeCode,
    required String? employeeUserId,
    required String? hrEmployeeId,
    required String? displayEmployeeId,
    required bool isHoliday,
    required bool isWeeklyOff,
  }) {
    if (isHoliday) return AbsenceCellKind.holiday;
    if (isWeeklyOff) return AbsenceCellKind.weeklyOff;

    final dk = _dateKey(day);
    final code = employeeCode ?? displayEmployeeId;
    if (_matches(code, employeeUserId, hrEmployeeId, dk)) {
      return AbsenceCellKind.approvedLeave;
    }
    if (_matchesPending(code, employeeUserId, hrEmployeeId, dk)) {
      return AbsenceCellKind.pendingLeave;
    }
    return AbsenceCellKind.unpaidAbsent;
  }

  /// Nhãn ô không có chấm công; ô **Vắng** có [onUnpaidAbsentTap] nếu truyền.
  static Widget buildCell(
    AbsenceCellKind kind, {
    VoidCallback? onUnpaidAbsentTap,
  }) {
    switch (kind) {
      case AbsenceCellKind.holiday:
        return const Center(
          child: Text(
            'Lễ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFFEA580C),
            ),
          ),
        );
      case AbsenceCellKind.weeklyOff:
        return const Center(
          child: Text(
            'Nghỉ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8B5CF6),
            ),
          ),
        );
      case AbsenceCellKind.approvedLeave:
        return const Center(
          child: Text(
            'Phép',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0891B2),
            ),
          ),
        );
      case AbsenceCellKind.pendingLeave:
        return const Center(
          child: Text(
            'Chờ phép',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFFD97706),
            ),
          ),
        );
      case AbsenceCellKind.unpaidAbsent:
        final label = const Center(
          child: Text(
            'Vắng',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFFEF4444),
            ),
          ),
        );
        if (onUnpaidAbsentTap == null) return label;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onUnpaidAbsentTap,
          child: label,
        );
    }
  }
}
