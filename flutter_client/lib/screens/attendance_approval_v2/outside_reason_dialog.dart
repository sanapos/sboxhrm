import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../widgets/sbox/sbox_ui.dart';

const kOutsideReasonPresets = [
  'Gặp khách hàng',
  'Làm tại công trình',
  'Đi mua vật tư',
  'Giao hàng / lắp đặt',
  'Làm việc theo phân công của quản lý',
];

/// Hỏi lý do khi chấm công ngoài vị trí công ty. Trả về null nếu nhân viên hủy.
Future<String?> showOutsideReasonDialog(BuildContext context) {
  final ctrl = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: SboxRadius.lgAll),
        title: Row(children: [
          const Icon(Icons.wrong_location_outlined, color: SboxColors.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('Chấm công ngoài vị trí'), style: SboxType.titleStyle())),
        ]),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Bạn đang ở ngoài vị trí công ty. Vui lòng cho quản lý biết lý do để được duyệt nhanh.'),
                style: SboxType.smallStyle()),
            const SizedBox(height: SboxSpace.md),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in kOutsideReasonPresets)
                ChoiceChip(
                  label: Text(tr(p), style: SboxType.captionStyle(ctrl.text == p ? SboxColors.brand800 : SboxColors.textSecondary)),
                  selected: ctrl.text == p,
                  showCheckmark: false,
                  selectedColor: SboxColors.brand50,
                  onSelected: (_) => setS(() {
                    ctrl.text = p;
                    error = null;
                  }),
                ),
            ]),
            const SizedBox(height: SboxSpace.md),
            TextField(
              controller: ctrl,
              maxLines: 2,
              maxLength: 300,
              onChanged: (_) => setS(() => error = null),
              decoration: InputDecoration(
                labelText: tr('Lý do'),
                hintText: tr('VD: Gặp khách tại 12 Lê Lợi theo lịch hẹn'),
                errorText: error == null ? null : tr(error!),
                border: OutlineInputBorder(borderRadius: SboxRadius.mdAll),
                isDense: true,
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.length < 3) {
                setS(() => error = 'Nhập lý do (ít nhất 3 ký tự)');
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: Text(tr('Chấm công')),
          ),
        ],
      ),
    ),
  );
}
