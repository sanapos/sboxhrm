import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/attendance/attendance_people_sheet.dart';
import 'late_penalty_sheet.dart';

/// Hai bảng chi tiết **chỉ của SBOX HRM** mà Tổng quan mở ra: danh sách nhân viên theo trạng thái chuyên cần,
/// và danh sách người đi trễ kèm phiếu phạt.
///
/// Tách khỏi `business_overview_screen.dart` (dùng chung với bản bán hàng) để bản SBOX Bán Hàng trên iOS
/// không biên dịch nhóm này vào gói — Apple 2.5.19. `lib/main.dart` gắn qua `hrm_shell_hooks.dart`.
void showHrmOverviewPeopleSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<Map<String, dynamic>> rows,
  VoidCallback? onTapRow,
}) {
  String shift(Map<String, dynamic> r) {
    final s = r['shiftStart'], e = r['shiftEnd'];
    if (s == null) return '';
    return e == null ? 'Ca $s' : 'Ca $s–$e';
  }

  showAttendancePeopleSheet(
    context,
    title: title,
    subtitle: subtitle,
    rows: [
      for (final r in rows)
        AttendancePersonRow(
          name: '${r['fullName'] ?? ''}',
          subtitle: [
            if ('${r['department'] ?? ''}'.isNotEmpty) '${r['department']}',
            if (shift(r).isNotEmpty) shift(r),
            if (r['checkIn'] != null) 'Vào ${r['checkIn']}${r['checkOut'] != null ? ' · Ra ${r['checkOut']}' : ''}',
            if ('${r['note'] ?? ''}'.isNotEmpty) '${r['note']}',
          ].join(' · '),
          trailing: switch ('${r['status']}') {
            'Late' => 'Trễ ${r['lateMinutes'] ?? 0}p',
            'Absent' => 'Vắng',
            'On Leave' => 'Nghỉ phép',
            'Off' => 'Không có ca',
            _ => r['checkIn'] == null ? null : '${r['checkIn']}',
          },
          trailingColor: switch ('${r['status']}') {
            'Late' => SboxColors.warningText,
            'Absent' => SboxColors.dangerText,
            _ => null,
          },
          onTap: onTapRow,
        ),
    ],
  );
}

Future<void> showHrmLatePenaltySheet(
  BuildContext context, {
  required List<Map<String, dynamic>> lateRows,
  required bool canApprove,
  required ApiService api,
  VoidCallback? onOpenPenalties,
}) {
  return showLatePenaltySheet(
    context,
    lateRows: lateRows,
    canApprove: canApprove,
    api: api,
    onOpenPenalties: onOpenPenalties,
  );
}
