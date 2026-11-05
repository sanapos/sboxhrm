import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/attendance_punch_slots.dart';
import '../app_responsive_dialog.dart';

/// Thiết lập từng ca nằm ở lần chấm nào. Trả về giá trị đã chọn, null nếu hủy.
Future<Map<String, List<int>>?> showShiftPunchSlotsDialog(
  BuildContext context, {
  required List<PunchSlotShift> shifts,
  required Map<String, List<int>> saved,
}) =>
    showDialog<Map<String, List<int>>>(
      context: context,
      builder: (_) => _ShiftPunchSlotsDialog(shifts: shifts, saved: saved),
    );

class _ShiftPunchSlotsDialog extends StatefulWidget {
  final List<PunchSlotShift> shifts;
  final Map<String, List<int>> saved;

  const _ShiftPunchSlotsDialog({required this.shifts, required this.saved});

  @override
  State<_ShiftPunchSlotsDialog> createState() => _ShiftPunchSlotsDialogState();
}

class _ShiftPunchSlotsDialogState extends State<_ShiftPunchSlotsDialog> {
  late Map<String, List<int>> _values = _copy(AttendancePunchSlots.withDefaults(widget.shifts, widget.saved));

  static Map<String, List<int>> _copy(Map<String, List<int>> v) => v.map((k, cols) => MapEntry(k, [...cols]));

  /// Tối thiểu Lần 1–8, luôn còn chỗ chọn lần cao hơn lần lớn nhất đang dùng.
  int get _maxLan {
    var n = 8;
    for (final v in _values.values) {
      if (v.last + 2 > n) n = v.last + 2;
    }
    return n;
  }

  bool get _allValid => _values.values.every(AttendancePunchSlots.isValid);

  /// Hai ca không trùng giờ (có thể cùng làm trong một ngày) mà dùng chung lần chấm.
  bool get _hasSharedLan {
    final list = widget.shifts;
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final a = list[i], b = list[j];
        final overlap = a.halves.first.start < b.halves.last.end && b.halves.first.start < a.halves.last.end;
        if (!overlap && _values[a.id]!.any(_values[b.id]!.contains)) return true;
      }
    }
    return false;
  }

  static String _hm(int minutes) {
    final m = minutes % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  Widget _lanPicker(String label, String shiftId, int index) {
    final cols = _values[shiftId]!;
    final isIn = index.isEven;
    return Expanded(
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: tr(label),
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: cols[index],
            isDense: true,
            isExpanded: true,
            items: [
              for (var lan = isIn ? 1 : 2; lan <= _maxLan; lan += 2)
                DropdownMenuItem(value: lan, child: Text(tr('Lần $lan'), style: const TextStyle(fontSize: 13))),
            ],
            onChanged: (v) {
              if (v != null) setState(() => cols[index] = v);
            },
          ),
        ),
      ),
    );
  }

  Widget _shiftBlock(PunchSlotShift s) {
    final valid = AttendancePunchSlots.isValid(_values[s.id]!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          for (var h = 0; h < s.halves.length; h++) ...[
            const SizedBox(height: 8),
            Text('${_hm(s.halves[h].start)} – ${_hm(s.halves[h].end)}',
                style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            const SizedBox(height: 6),
            Row(children: [
              _lanPicker('Chấm vào', s.id, h * 2),
              const SizedBox(width: 10),
              _lanPicker('Chấm ra', s.id, h * 2 + 1),
            ]),
          ],
          if (!valid) ...[
            const SizedBox(height: 6),
            Text(tr('Lần chấm sau phải lớn hơn lần chấm trước'),
                style: const TextStyle(fontSize: 12, color: Colors.red)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScrollableAlertDialog(
      title: Text(tr('Thiết lập lần chấm theo ca')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Áp dụng khi chọn «Giờ chấm theo ca» trên bảng và file xuất. Không ảnh hưởng cách tính công.'),
                style: const TextStyle(fontSize: 12, color: SboxColors.slate600),
              ),
              const SizedBox(height: 14),
              for (final s in widget.shifts) _shiftBlock(s),
              if (_hasSharedLan)
                Text(
                  tr('Có ca dùng chung một lần chấm: nếu nhân viên làm cả hai ca trong ngày, giờ của ca sau nằm ở các cột cuối.'),
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _values = _copy(AttendancePunchSlots.withDefaults(widget.shifts, const {}))),
          child: Text(tr('Tự xếp theo giờ ca')),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: _allValid ? () => Navigator.pop(context, _values) : null,
          child: Text(tr('Lưu')),
        ),
      ],
    );
  }
}
