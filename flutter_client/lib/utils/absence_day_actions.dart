import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/leave_request_form.dart';
import '../widgets/notification_overlay.dart';

/// Menu khi bấm ô **Vắng** (không phép): tạo đơn nghỉ hoặc ghi nhận nghỉ không phép.
class AbsenceDayActions {
  AbsenceDayActions._();

  static String? _resolveHrEmployeeId(
    List<dynamic> employees, {
    String? employeeCode,
    String? applicationUserId,
    String? displayEmployeeId,
  }) {
    for (final raw in employees) {
      if (raw is! Map) continue;
      final e = Map<String, dynamic>.from(raw as Map);
      final code = e['employeeCode']?.toString() ?? '';
      final appId = e['applicationUserId']?.toString() ?? '';
      final id = e['id']?.toString() ?? '';
      if (employeeCode != null &&
          employeeCode.isNotEmpty &&
          (code == employeeCode || id == employeeCode)) {
        return id;
      }
      if (displayEmployeeId != null &&
          displayEmployeeId.isNotEmpty &&
          (code == displayEmployeeId || id == displayEmployeeId)) {
        return id;
      }
      if (applicationUserId != null &&
          applicationUserId.isNotEmpty &&
          appId == applicationUserId) {
        return id;
      }
    }
    return null;
  }

  static Future<void> showForAbsentDay({
    required BuildContext context,
    required ApiService api,
    required String employeeName,
    required String employeeCode,
    required String displayEmployeeId,
    required String? applicationUserId,
    required String? hrEmployeeId,
    required DateTime date,
    List<dynamic>? employees,
    VoidCallback? onCompleted,
  }) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                employeeName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Mã: $employeeCode · ${DateFormat('dd/MM/yyyy').format(date)}',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ngày vắng (chưa có phép duyệt). Chọn xử lý:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.beach_access, color: Color(0xFF0891B2)),
                title: const Text('Tạo phiếu nghỉ phép'),
                subtitle: const Text('Bổ sung đơn nghỉ cho ngày này'),
                onTap: () => Navigator.pop(ctx, 'leave'),
              ),
              ListTile(
                leading: const Icon(Icons.gavel, color: Color(0xFFDC2626)),
                title: const Text('Nghỉ không phép'),
                subtitle: const Text('Tạo phiếu phạt nghỉ không phép'),
                onTap: () => Navigator.pop(ctx, 'unauthorized'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!context.mounted || choice == null) return;

    List<dynamic> empList = employees ?? [];
    if (empList.isEmpty) {
      try {
        final raw = await api.getEmployees(pageSize: 500);
        empList = raw;
      } catch (_) {}
    }

    final hrId = hrEmployeeId ??
        _resolveHrEmployeeId(
          empList,
          employeeCode: employeeCode,
          applicationUserId: applicationUserId,
          displayEmployeeId: displayEmployeeId,
        );

    if (choice == 'leave') {
      await _createLeave(
        context,
        api: api,
        employees: empList,
        hrEmployeeId: hrId,
        employeeName: employeeName,
        employeeCode: employeeCode,
        date: date,
        onCompleted: onCompleted,
      );
    } else if (choice == 'unauthorized') {
      await _createUnauthorizedPenalty(
        context,
        api: api,
        hrEmployeeId: hrId,
        employeeName: employeeName,
        date: date,
        onCompleted: onCompleted,
      );
    }
  }

  static Future<void> _createLeave(
    BuildContext context, {
    required ApiService api,
    required List<dynamic> employees,
    required String? hrEmployeeId,
    required String employeeName,
    required String employeeCode,
    required DateTime date,
    VoidCallback? onCompleted,
  }) async {
    if (hrEmployeeId == null || hrEmployeeId.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: 'Không tìm thấy nhân viên trên hệ thống HR',
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final perm = context.read<PermissionProvider>();
    final role = auth.user?.role ?? '';
    final isManager = role == 'Admin' ||
        role == 'Manager' ||
        role == 'SuperAdmin' ||
        role == 'Agent' ||
        role == 'Director' ||
        role == 'DepartmentHead' ||
        perm.canApprove('Leave') ||
        perm.canCreate('Leave');

    List<dynamic> shifts = [];
    try {
      shifts = await api.getShifts();
    } catch (_) {}

    final dayStr = DateFormat('yyyy-MM-dd').format(date);
    final ok = await LeaveRequestFormDialog.show(
      context,
      shifts: shifts,
      employees: employees,
      apiService: api,
      currentUserId: auth.user?.id,
      isManager: isManager,
      aiPrefill: {
        'date': dayStr,
        'endDate': dayStr,
        'startDate': dayStr,
        'employeeId': hrEmployeeId,
        'employeeCode': employeeCode,
        'reason':
            'Bổ sung phép — vắng ngày ${DateFormat('dd/MM/yyyy').format(date)} ($employeeName)',
      },
    );

    if (ok == true) {
      onCompleted?.call();
    }
  }

  static Future<void> _createUnauthorizedPenalty(
    BuildContext context, {
    required ApiService api,
    required String? hrEmployeeId,
    required String employeeName,
    required DateTime date,
    VoidCallback? onCompleted,
  }) async {
    if (hrEmployeeId == null || hrEmployeeId.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: 'Không tìm thấy nhân viên để tạo phiếu phạt',
      );
      return;
    }

    double defaultAmount = 200000;
    try {
      final settings = await api.getPenaltySettings();
      if (settings['isSuccess'] == true && settings['data'] is Map) {
        final data = settings['data'] as Map;
        final v = data['unauthorizedLeaveDeduction'] ??
            data['UnauthorizedLeavePenalty'];
        if (v is num) defaultAmount = v.toDouble();
      }
    } catch (_) {}

    final amountCtrl =
        TextEditingController(text: defaultAmount.toStringAsFixed(0));
    final descCtrl = TextEditingController(
      text:
          'Nghỉ không phép — ${DateFormat('dd/MM/yyyy').format(date)} ($employeeName)',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Nghỉ không phép'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$employeeName · ${DateFormat('dd/MM/yyyy').format(date)}'),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền phạt',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Ghi chú',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tạo phiếu phạt'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      amountCtrl.dispose();
      descCtrl.dispose();
      return;
    }

    final amountText = amountCtrl.text;
    final description =
        descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim();
    amountCtrl.dispose();
    descCtrl.dispose();

    final amount = double.tryParse(amountText.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: 'Số tiền phạt không hợp lệ',
      );
      return;
    }

    final result = await api.createPenaltyTicket({
      'employeeId': hrEmployeeId,
      'type': 'UnauthorizedLeave',
      'amount': amount,
      'violationDate': DateTime(date.year, date.month, date.day)
          .toIso8601String(),
      'description': description,
    });

    if (!context.mounted) return;

    if (result['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Thành công',
        message: 'Đã ghi nhận nghỉ không phép',
      );
      onCompleted?.call();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: result['message']?.toString() ?? 'Tạo phiếu phạt thất bại',
      );
    }
  }
}
