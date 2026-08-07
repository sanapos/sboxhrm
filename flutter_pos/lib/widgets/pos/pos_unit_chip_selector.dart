import 'package:flutter/material.dart';

import 'pos_product_unit_view.dart';
import 'pos_theme.dart';
import '../../l10n/app_tr.dart';

/// Chip chọn đơn vị / hàng cùng loại dưới tên SP (KiotViet).
class PosUnitChipSelector extends StatelessWidget {
  const PosUnitChipSelector({
    super.key,
    required this.views,
    required this.selectedVariantId,
    required this.onChanged,
    this.compact = false,
  });

  final List<PosProductUnitView> views;
  final String? selectedVariantId;
  final void Function(String? variantId) onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (views.length <= 1) {
      final v = views.first;
      return _chip(v.label, selected: true, onTap: null);
    }
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: views.map((v) {
        final selected = v.variantId == selectedVariantId ||
            (v.variantId == null && selectedVariantId == null);
        return _chip(
          v.label,
          selected: selected,
          onTap: () => onChanged(v.variantId),
        );
      }).toList(),
    );
  }

  Widget _chip(String label, {required bool selected, VoidCallback? onTap}) {
    return Material(
      color: selected
          ? PosTheme.kiotBlue.withOpacity(0.12)
          : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 8,
            vertical: compact ? 1 : 2,
          ),
          child: Text(
            tr(label),
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? PosTheme.kiotBlue : PosTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
