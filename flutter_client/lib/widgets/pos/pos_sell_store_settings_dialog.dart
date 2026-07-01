import 'package:flutter/material.dart';

import '../../utils/pos_sell_store_settings.dart';
import 'pos_theme.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Dialog thiết lập tên cửa hàng, địa chỉ, điện thoại.
Future<PosSellStoreSettings?> showPosSellStoreSettingsDialog(
  BuildContext context, {
  required PosSellStoreSettings initial,
}) async {
  final nameCtrl = TextEditingController(text: initial.storeName);
  final addressCtrl = TextEditingController(text: initial.address);
  final phoneCtrl = TextEditingController(text: initial.phone);

  final result = await showDialog<PosSellStoreSettings>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Thiết lập cửa hàng'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên cửa hàng',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Thông tin này hiển thị trên màn bán hàng và in trên hóa đơn.',
              style: TextStyle(fontSize: 11, color: PosTheme.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
          onPressed: () {
            Navigator.pop(
              ctx,
              PosSellStoreSettings(
                storeName: nameCtrl.text.trim(),
                address: addressCtrl.text.trim(),
                phone: phoneCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Lưu'),
        ),
      ],
    ),
  );

  nameCtrl.dispose();
  addressCtrl.dispose();
  phoneCtrl.dispose();
  return result;
}
