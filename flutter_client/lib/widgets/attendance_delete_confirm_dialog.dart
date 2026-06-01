import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_responsive_dialog.dart';
import 'attendance_correction_reason_field.dart';

/// Dialog xóa chấm công — mobile full-screen, nút Hủy/Xóa cố định dưới (không bị che).
Future<String?> showAttendanceDeleteConfirmDialog({
  required BuildContext context,
  required String employeeName,
  required String employeeCode,
  required DateTime date,
  required int punchIndex,
  required DateTime punchTime,
  required bool isIn,
  required bool directApply,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final reasonController = TextEditingController();

  try {
    return await AppResponsiveDialog.show<String>(
      context: context,
      title: 'Xác nhận xóa',
      icon: Icons.delete_forever,
      iconColor: const Color(0xFFEF4444),
      maxWidth: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            directApply
                ? 'Bạn có chắc muốn xóa lần chấm công này? (áp dụng ngay)'
                : 'Bạn có chắc muốn yêu cầu xóa lần chấm công này?',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.red.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nhân viên: $employeeName',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('Mã: $employeeCode'),
                  Text('Ngày: ${DateFormat('dd/MM/yyyy').format(date)}'),
                  Text(
                    'Lần chấm: $punchIndex (${isIn ? 'Vào' : 'Ra'}) — '
                    '${DateFormat('HH:mm').format(punchTime)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AttendanceCorrectionReasonField(
            controller: reasonController,
            kind: AttendanceCorrectionReasonKind.delete,
            employeeName: employeeName,
            employeeCode: employeeCode,
            date: date,
            originalTimeText: DateFormat('HH:mm').format(punchTime),
            punchLabel: isIn ? 'Vào' : 'Ra',
            autoFillOnInit: false,
          ),
        ],
      ),
      actions: _DeleteDialogActions(reasonController: reasonController),
    );
  } finally {
    reasonController.dispose();
  }
}

class _DeleteDialogActions extends StatelessWidget {
  final TextEditingController reasonController;

  const _DeleteDialogActions({required this.reasonController});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Vui lòng chọn gợi ý hoặc nhập lý do xóa'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              Navigator.pop(context, reason);
            },
            icon: const Icon(Icons.delete, size: 20),
            label: const Text('Xóa'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
