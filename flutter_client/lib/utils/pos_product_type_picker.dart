import 'package:flutter/material.dart';

import '../models/pos_product.dart';
import '../widgets/pos/pos_theme.dart';

/// Chọn loại hàng khi tạo mới (Hàng hóa / Dịch vụ / Combo).
Future<PosProductType?> showPosProductTypePicker(BuildContext context) {
  return showModalBottomSheet<PosProductType>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Loại hàng cần tạo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined, color: PosTheme.kiotBlue),
            title: const Text('Hàng hóa'),
            subtitle: const Text('Có tồn kho, biến thể'),
            onTap: () => Navigator.pop(ctx, PosProductType.goods),
          ),
          ListTile(
            leading: const Icon(Icons.handyman_outlined, color: PosTheme.kiotBlue),
            title: const Text('Dịch vụ'),
            subtitle: const Text('Không trừ tồn kho'),
            onTap: () => Navigator.pop(ctx, PosProductType.service),
          ),
          ListTile(
            leading: const Icon(Icons.layers_outlined, color: PosTheme.kiotBlue),
            title: const Text('Combo / Đóng gói'),
            subtitle: const Text('Gói nhiều hàng — trừ tồn thành phần'),
            onTap: () => Navigator.pop(ctx, PosProductType.combo),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void showPosProductCreateSheet(
  BuildContext context, {
  required void Function(PosProductType type) onPick,
}) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tạo mới',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Hàng hóa'),
            onTap: () {
              Navigator.pop(ctx);
              onPick(PosProductType.goods);
            },
          ),
          ListTile(
            leading: const Icon(Icons.handyman_outlined),
            title: const Text('Dịch vụ'),
            onTap: () {
              Navigator.pop(ctx);
              onPick(PosProductType.service);
            },
          ),
          ListTile(
            leading: const Icon(Icons.layers_outlined),
            title: const Text('Combo / Đóng gói'),
            onTap: () {
              Navigator.pop(ctx);
              onPick(PosProductType.combo);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
