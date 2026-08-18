import 'package:flutter/material.dart';

import '../../models/pos_product.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

class _TypeChip {
  const _TypeChip(this.type, this.label, this.shortLabel, this.icon, this.color);
  final PosProductType? type;
  final String label;
  final String shortLabel;
  final IconData icon;
  final Color color;
}

const _kChips = <_TypeChip>[
  _TypeChip(null, 'Tất cả', 'Tất cả', Icons.grid_view_outlined, PosTheme.kiotBlue),
  _TypeChip(PosProductType.goods, 'Hàng hóa', 'Hàng hóa', Icons.inventory_2_outlined, PosTheme.goodsColor),
  _TypeChip(PosProductType.service, 'Dịch vụ', 'Dịch vụ', Icons.handyman_outlined, PosTheme.serviceColor),
  _TypeChip(PosProductType.combo, 'Combo', 'Combo', Icons.layers_outlined, PosTheme.comboColor),
  _TypeChip(PosProductType.material, 'Nguyên vật liệu', 'NVL', Icons.science_outlined, PosTheme.materialColor),
  _TypeChip(PosProductType.topping, 'Topping', 'Topping', Icons.icecream_outlined, PosTheme.toppingColor),
];

/// Bộ lọc 5 loại hàng — luôn hiện, không giấu trong dropdown.
class PosProductTypeFilterBar extends StatelessWidget {
  const PosProductTypeFilterBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.vertical = false,
  });

  final PosProductType? value;
  final ValueChanged<PosProductType?> onChanged;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in _kChips) _tile(c),
        ],
      );
    }
    return Material(
      color: Colors.white,
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          scrollDirection: Axis.horizontal,
          itemCount: _kChips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _pill(_kChips[i]),
        ),
      ),
    );
  }

  Widget _pill(_TypeChip c) {
    final selected = value == c.type;
    return Material(
      color: selected ? c.color : c.color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onChanged(c.type),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(c.icon, size: 16, color: selected ? Colors.white : c.color),
              const SizedBox(width: 6),
              Text(
                tr(c.shortLabel),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : c.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(_TypeChip c) {
    final selected = value == c.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? c.color.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onChanged(c.type),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Icon(c.icon, size: 18, color: c.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(c.label),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: PosTheme.textPrimary,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check, size: 18, color: c.color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
