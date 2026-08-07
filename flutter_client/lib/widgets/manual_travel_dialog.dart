import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _theme = HrmPageChrome.primaryNavy;

/// Dialog bổ sung / chỉnh cặp chấm đi đường (Bắt đầu đi → Đến điểm làm).
/// Nếu truyền [existingStartRecordId] / [existingArriveRecordId] thì gắn vào phiếu thiếu
/// (chỉ tạo chấm còn thiếu), không nhân đôi dòng cũ.
Future<bool> showManualTravelDialog(
  BuildContext context, {
  required ApiService api,
  required List<Map<String, dynamic>> employees,
  String? initialEmployeeId,
  DateTime? initialDay,
  TimeOfDay? initialStart,
  TimeOfDay? initialArrive,
  String? title,
  String? existingStartRecordId,
  String? existingArriveRecordId,
}) async {
  if (employees.isEmpty) {
    appNotification.showError(
      title: 'Thiếu dữ liệu',
      message: tr('Không có danh sách nhân viên để bổ sung đi đường'),
    );
    return false;
  }

  final sorted = List<Map<String, dynamic>>.from(employees)
    ..sort((a, b) {
      final na = _empLabel(a);
      final nb = _empLabel(b);
      return na.compareTo(nb);
    });

  String? selectedEmpId = initialEmployeeId;
  if (selectedEmpId != null &&
      !sorted.any((e) => e['id']?.toString() == selectedEmpId)) {
    // Thử khớp applicationUserId / employeeCode
    for (final e in sorted) {
      if (e['applicationUserId']?.toString() == initialEmployeeId ||
          e['employeeCode']?.toString() == initialEmployeeId ||
          e['pin']?.toString() == initialEmployeeId) {
        selectedEmpId = e['id']?.toString();
        break;
      }
    }
  }
  selectedEmpId ??= sorted.first['id']?.toString();

  final now = DateTime.now();
  DateTime day = initialDay ?? DateTime(now.year, now.month, now.day);
  TimeOfDay startTod = initialStart ?? const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay arriveTod = initialArrive ?? const TimeOfDay(hour: 8, minute: 0);
  final noteCtrl = TextEditingController();
  final dateFmt = DateFormat('dd/MM/yyyy');
  final timeFmt = DateFormat('HH:mm');
  var saving = false;
  var saved = false;
  final isSupplement = (existingStartRecordId != null &&
          existingStartRecordId.isNotEmpty) ||
      (existingArriveRecordId != null && existingArriveRecordId.isNotEmpty);

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> pickDay() async {
            final d = await showDatePicker(
              context: ctx,
              initialDate: day,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            );
            if (d != null) setLocal(() => day = d);
          }

          Future<void> pickTime({required bool isStart}) async {
            final t = await showTimePicker(
              context: ctx,
              initialTime: isStart ? startTod : arriveTod,
            );
            if (t == null) return;
            setLocal(() {
              if (isStart) {
                startTod = t;
              } else {
                arriveTod = t;
              }
            });
          }

          Future<void> submit() async {
            if (selectedEmpId == null || selectedEmpId!.isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(tr('Chọn nhân viên'))),
              );
              return;
            }
            final start = DateTime(
                day.year, day.month, day.day, startTod.hour, startTod.minute);
            final arrive = DateTime(day.year, day.month, day.day,
                arriveTod.hour, arriveTod.minute);
            if (!arrive.isAfter(start)) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                    content:
                        Text(tr('Giờ đến điểm phải sau giờ bắt đầu đi'))),
              );
              return;
            }
            setLocal(() => saving = true);
            final res = await api.createManualTravelAttendance(
              employeeId: selectedEmpId!,
              startTime: start,
              arriveTime: arrive,
              note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              existingStartRecordId: existingStartRecordId,
              existingArriveRecordId: existingArriveRecordId,
            );
            if (!ctx.mounted) return;
            setLocal(() => saving = false);
            if (res['isSuccess'] == true) {
              saved = true;
              Navigator.pop(ctx);
              appNotification.showSuccess(
                title: 'Thành công',
                message: tr(isSupplement
                    ? 'Đã bổ sung cặp đi đường'
                    : 'Đã lưu chấm đi đường'),
              );
            } else {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text(tr(res['message']?.toString() ??
                      'Không lưu được chấm đi đường')),
                ),
              );
            }
          }

          return AlertDialog(
            title: Text(tr(title ??
                (isSupplement ? 'Bổ sung cặp đi đường' : 'Thêm đi đường'))),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr(isSupplement
                          ? 'Bổ sung chấm còn thiếu trên phiếu hiện có (không tạo dòng mới).'
                          : 'Tạo cặp Bắt đầu đi → Đến điểm làm (đã duyệt).'),
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: selectedEmpId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: tr('Nhân viên'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: sorted.map((e) {
                        final id = e['id']?.toString() ?? '';
                        return DropdownMenuItem(
                          value: id,
                          child: Text(tr(_empLabel(e)),
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (saving || isSupplement)
                          ? null
                          : (v) => setLocal(() => selectedEmpId = v),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: saving ? null : pickDay,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(tr(dateFmt.format(day))),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                saving ? null : () => pickTime(isStart: true),
                            child: Text(tr(
                                'Bắt đầu ${timeFmt.format(DateTime(0, 1, 1, startTod.hour, startTod.minute))}')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving
                                ? null
                                : () => pickTime(isStart: false),
                            child: Text(tr(
                                'Đến ${timeFmt.format(DateTime(0, 1, 1, arriveTod.hour, arriveTod.minute))}')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      enabled: !saving,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: tr('Ghi chú (tuỳ chọn)'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: Text(tr('Huỷ')),
              ),
              FilledButton(
                onPressed: saving ? null : submit,
                style: FilledButton.styleFrom(backgroundColor: _theme),
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(tr('Lưu')),
              ),
            ],
          );
        },
      );
    },
  );
  noteCtrl.dispose();
  return saved;
}

String _empLabel(Map<String, dynamic> e) {
  final name = (e['fullName'] ??
          '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim())
      .toString()
      .trim();
  final code = e['employeeCode']?.toString() ?? '';
  if (code.isEmpty) return name.isEmpty ? '—' : name;
  return name.isEmpty ? code : '$name ($code)';
}
