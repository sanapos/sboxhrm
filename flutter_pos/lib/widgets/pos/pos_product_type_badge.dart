import 'package:flutter/material.dart';

import '../../models/pos_product.dart';
import 'pos_theme.dart';
import '../../l10n/app_tr.dart';

class PosProductTypeBadge extends StatelessWidget {
  const PosProductTypeBadge({super.key, required this.type, this.compact = false});

  final PosProductType type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (type) {
      PosProductType.service => (PosTheme.serviceColor, Icons.handyman_outlined),
      PosProductType.combo => (PosTheme.comboColor, Icons.layers_outlined),
      PosProductType.goods => (PosTheme.goodsColor, Icons.inventory_2_outlined),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: color),
          const SizedBox(width: 4),
          Text(
            tr(posProductTypeLabel(type)),
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class PosSellingStatusBadge extends StatelessWidget {
  const PosSellingStatusBadge({
    super.key,
    required this.isActive,
    required this.isDirectSale,
  });

  final bool isActive;
  final bool isDirectSale;

  @override
  Widget build(BuildContext context) {
    if (!isActive) {
      return _chip('Ngừng KD', Colors.red.shade700, Colors.red.shade50);
    }
    if (!isDirectSale) {
      return _chip('Ẩn POS', Colors.orange.shade800, Colors.orange.shade50);
    }
    return _chip('Đang bán', PosTheme.primaryDark, PosTheme.primaryLight);
  }

  Widget _chip(String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tr(label),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
