import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Loại thao tác chấm công (thêm / sửa / xóa) — dùng cho gợi ý và mẫu ghi chú.
enum AttendanceCorrectionReasonKind { add, edit, delete }

/// Trường lý do: điền sẵn mẫu, chip gợi ý, hoặc tự nhập.
class AttendanceCorrectionReasonField extends StatefulWidget {
  final TextEditingController controller;
  final AttendanceCorrectionReasonKind kind;
  final String? employeeName;
  final String? employeeCode;
  final DateTime? date;
  /// Giờ mới hoặc giờ cần thêm (HH:mm).
  final String? timeText;
  /// Giờ cũ khi sửa/xóa (HH:mm).
  final String? originalTimeText;
  final String? punchLabel;
  final bool autoFillOnInit;
  final String? label;

  const AttendanceCorrectionReasonField({
    super.key,
    required this.controller,
    required this.kind,
    this.employeeName,
    this.employeeCode,
    this.date,
    this.timeText,
    this.originalTimeText,
    this.punchLabel,
    this.autoFillOnInit = true,
    this.label,
  });

  @override
  State<AttendanceCorrectionReasonField> createState() =>
      _AttendanceCorrectionReasonFieldState();
}

class _AttendanceCorrectionReasonFieldState
    extends State<AttendanceCorrectionReasonField> {
  @override
  void initState() {
    super.initState();
    if (widget.autoFillOnInit && widget.controller.text.trim().isEmpty) {
      widget.controller.text = buildDefaultAttendanceCorrectionReason(
        kind: widget.kind,
        employeeName: widget.employeeName,
        employeeCode: widget.employeeCode,
        date: widget.date,
        timeText: widget.timeText,
        originalTimeText: widget.originalTimeText,
        punchLabel: widget.punchLabel,
      );
    }
  }

  String get _fieldLabel {
    if (widget.label != null) return widget.label!;
    switch (widget.kind) {
      case AttendanceCorrectionReasonKind.add:
        return 'Lý do bổ sung';
      case AttendanceCorrectionReasonKind.edit:
        return 'Lý do chỉnh sửa';
      case AttendanceCorrectionReasonKind.delete:
        return 'Lý do xóa';
    }
  }

  void _applyTemplate() {
    setState(() {
      widget.controller.text = buildDefaultAttendanceCorrectionReason(
        kind: widget.kind,
        employeeName: widget.employeeName,
        employeeCode: widget.employeeCode,
        date: widget.date,
        timeText: widget.timeText,
        originalTimeText: widget.originalTimeText,
        punchLabel: widget.punchLabel,
      );
    });
  }

  void _applySuggestion(String text) {
    setState(() => widget.controller.text = text);
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = attendanceCorrectionReasonSuggestions(widget.kind);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$_fieldLabel *',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            TextButton.icon(
              onPressed: _applyTemplate,
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Điền mẫu'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Chọn gợi ý hoặc chỉnh sửa nội dung bên dưới',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: suggestions.map((s) {
            return ActionChip(
              label: Text(s, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              onPressed: () => _applySuggestion(s),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: widget.controller,
          autofocus: false,
          enableSuggestions: false,
          autocorrect: false,
          minLines: 2,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.done,
          scrollPadding: const EdgeInsets.only(bottom: 120),
          decoration: InputDecoration(
            hintText: 'Nhập lý do hoặc chọn gợi ý phía trên',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.note_alt_outlined),
            suffixIcon: widget.controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () => setState(() => widget.controller.clear()),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}

String buildDefaultAttendanceCorrectionReason({
  required AttendanceCorrectionReasonKind kind,
  String? employeeName,
  String? employeeCode,
  DateTime? date,
  String? timeText,
  String? originalTimeText,
  String? punchLabel,
}) {
  final dateStr =
      date != null ? DateFormat('dd/MM/yyyy').format(date) : '...';
  final nv = _employeeLabel(employeeName, employeeCode);
  final punch = punchLabel != null && punchLabel.isNotEmpty
      ? ' ($punchLabel)'
      : '';

  switch (kind) {
    case AttendanceCorrectionReasonKind.add:
      final t = timeText ?? '...';
      return 'Bổ sung chấm công$punch lúc $t ngày $dateStr — $nv.';
    case AttendanceCorrectionReasonKind.edit:
      final oldT = originalTimeText ?? '...';
      final newT = timeText ?? '...';
      return 'Điều chỉnh giờ chấm công$punch từ $oldT thành $newT ngày $dateStr — $nv.';
    case AttendanceCorrectionReasonKind.delete:
      final t = originalTimeText ?? timeText ?? '...';
      return 'Xóa chấm công$punch lúc $t ngày $dateStr — $nv.';
  }
}

List<String> attendanceCorrectionReasonSuggestions(
    AttendanceCorrectionReasonKind kind) {
  const common = [
    'Quên chấm công / máy không ghi nhận',
    'Sự cố thiết bị hoặc mất điện',
    'Công tác / họp ngoài — bổ sung theo xác nhận quản lý',
    'Điều chỉnh theo đơn tờ / giấy phép đã duyệt',
    'Ca qua đêm — điều chỉnh ngày hoặc giờ chấm',
    'Nhập sai giờ — sửa theo thực tế',
  ];
  switch (kind) {
    case AttendanceCorrectionReasonKind.add:
      return [
        'Quên chấm công — bổ sung giờ vào/ra',
        'Máy chấm công không ghi nhận',
        ...common.skip(2),
      ];
    case AttendanceCorrectionReasonKind.edit:
      return [
        'Nhập sai giờ — sửa theo thực tế',
        'Ca qua đêm — điều chỉnh giờ chấm',
        ...common,
      ];
    case AttendanceCorrectionReasonKind.delete:
      return [
        'Chấm công trùng / nhầm lần',
        'Ghi nhận sai người hoặc sai giờ',
        'Theo yêu cầu điều chỉnh sau khi duyệt',
        ...common.take(4),
      ];
  }
}

String _employeeLabel(String? name, String? code) {
  final n = (name ?? '').trim();
  final c = (code ?? '').trim();
  if (n.isNotEmpty && c.isNotEmpty) return 'NV $n ($c)';
  if (n.isNotEmpty) return 'NV $n';
  if (c.isNotEmpty) return 'Mã $c';
  return 'nhân viên';
}

/// Map loại yêu cầu trên màn hình điều chỉnh chấm công.
AttendanceCorrectionReasonKind reasonKindFromCorrectionAction(
    dynamic action) {
  final name = action.toString().split('.').last.toLowerCase();
  if (name.contains('add') || name == '0') {
    return AttendanceCorrectionReasonKind.add;
  }
  if (name.contains('delete') || name == '2') {
    return AttendanceCorrectionReasonKind.delete;
  }
  return AttendanceCorrectionReasonKind.edit;
}
