import 'package:flutter/material.dart';

import '../models/pos_product.dart';
import '../widgets/pos/pos_theme.dart';
import '../l10n/app_tr.dart';

enum PosProductTypePickAction { create, importExcel, downloadTemplate }

class PosProductTypePickResult {
  const PosProductTypePickResult(this.type, this.action);
  final PosProductType type;
  final PosProductTypePickAction action;
}

class _TypeMeta {
  const _TypeMeta({
    required this.type,
    required this.icon,
    required this.color,
    required this.subtitle,
  });
  final PosProductType type;
  final IconData icon;
  final Color color;
  final String subtitle;
}

const _kTypeMetas = <_TypeMeta>[
  _TypeMeta(
    type: PosProductType.goods,
    icon: Icons.inventory_2_outlined,
    color: PosTheme.goodsColor,
    subtitle: 'Có tồn kho, bán trên POS',
  ),
  _TypeMeta(
    type: PosProductType.service,
    icon: Icons.handyman_outlined,
    color: PosTheme.serviceColor,
    subtitle: 'Không trừ tồn thành phẩm',
  ),
  _TypeMeta(
    type: PosProductType.combo,
    icon: Icons.layers_outlined,
    color: PosTheme.comboColor,
    subtitle: 'Gói nhiều hàng — trừ thành phần',
  ),
  _TypeMeta(
    type: PosProductType.material,
    icon: Icons.science_outlined,
    color: PosTheme.materialColor,
    subtitle: 'NVL kho bếp — không hiện POS',
  ),
  _TypeMeta(
    type: PosProductType.topping,
    icon: Icons.icecream_outlined,
    color: PosTheme.toppingColor,
    subtitle: 'Bán kèm món — không hiện lưới chính',
  ),
];

/// Chọn loại hàng khi tạo mới.
Future<PosProductType?> showPosProductTypePicker(BuildContext context) {
  return showModalBottomSheet<PosProductType>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr('Loại hàng cần tạo'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          for (final m in _kTypeMetas)
            ListTile(
              leading: Icon(m.icon, color: m.color),
              title: Text(tr(posProductTypeLabel(m.type))),
              subtitle: Text(tr(m.subtitle)),
              onTap: () => Navigator.pop(ctx, m.type),
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
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr('Tạo mới'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          for (final m in _kTypeMetas)
            ListTile(
              leading: Icon(m.icon, color: m.color),
              title: Text(tr(posProductTypeLabel(m.type))),
              subtitle: Text(tr(m.subtitle)),
              onTap: () {
                Navigator.pop(ctx);
                onPick(m.type);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Hub tạo / tải mẫu / nhập Excel theo từng loại.
Future<PosProductTypePickResult?> showPosProductTypeHub(
  BuildContext context, {
  required String title,
  bool showCreate = true,
  bool showImport = true,
  bool showTemplate = true,
}) {
  return showModalBottomSheet<PosProductTypePickResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr(title),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr('Chọn loại, rồi tạo tay hoặc nhập Excel riêng loại đó.'),
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ),
            ),
            for (final m in _kTypeMetas)
              ListTile(
                leading: Icon(m.icon, color: m.color),
                title: Text(tr(posProductTypeLabel(m.type))),
                subtitle: Text(tr(m.subtitle)),
                onTap: showCreate
                    ? () => Navigator.pop(
                          ctx,
                          PosProductTypePickResult(
                            m.type,
                            PosProductTypePickAction.create,
                          ),
                        )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showTemplate)
                      IconButton(
                        tooltip: tr('Tải mẫu Excel'),
                        icon: Icon(Icons.download_outlined, color: m.color),
                        onPressed: () => Navigator.pop(
                          ctx,
                          PosProductTypePickResult(
                            m.type,
                            PosProductTypePickAction.downloadTemplate,
                          ),
                        ),
                      ),
                    if (showImport)
                      IconButton(
                        tooltip: tr('Nhập Excel'),
                        icon: Icon(Icons.upload_file_outlined, color: m.color),
                        onPressed: () => Navigator.pop(
                          ctx,
                          PosProductTypePickResult(
                            m.type,
                            PosProductTypePickAction.importExcel,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
