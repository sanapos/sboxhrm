import 'package:flutter/material.dart';

import '../../utils/navigation_notifier.dart';
import '../../utils/responsive_helper.dart';
import 'pos_theme.dart';
import 'pos_hub_scope.dart';

/// Thanh công cụ POS phía trên (giống KiotViet).
class PosModuleToolbar extends StatelessWidget {
  const PosModuleToolbar({
    super.key,
    this.activeModule = 'PosProducts',
  });

  final String activeModule;

  static const _tabs = [
    _PosTab('PosProducts', 'Hàng hóa', Icons.inventory_2_outlined),
    _PosTab('PosSell', 'Bán hàng', Icons.point_of_sale),
    _PosTab('PosSaleOrders', 'Đơn hàng', Icons.receipt_long),
    _PosTab('PosPurchaseReceipts', 'Nhập hàng', Icons.shopping_cart),
    _PosTab('PosPurchaseReturns', 'Trả hàng', Icons.undo),
    _PosTab('PosStockCounts', 'Kiểm kho', Icons.fact_check),
    _PosTab('PosDamageIssues', 'Xuất hủy', Icons.delete_forever),
    _PosTab('PosInternalUseIssues', 'Dùng NB', Icons.build),
    _PosTab('PosSalesReport', 'Báo cáo', Icons.bar_chart),
  ];

  @override
  Widget build(BuildContext context) {
    if (PosHubScope.of(context) || PosHubScope.pushedSubPageOf(context)) {
      return const SizedBox.shrink();
    }
    if (Responsive.isMobile(context)) return const SizedBox.shrink();

    return Material(
      color: const Color(0xFF1A3A5C),
      child: SafeArea(
        bottom: false,
        child: _buildDesktop(context),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Text(
            'SBOX POS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 20),
          ..._tabs.map((t) => _tabButton(t, compact: false)),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => NavigationNotifier.goToModule('PosSell'),
            style: FilledButton.styleFrom(
              backgroundColor: PosTheme.kiotBlue,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            icon: const Icon(Icons.point_of_sale, size: 18),
            label: const Text('Bán hàng'),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _tabButton(_PosTab t, {required bool compact}) {
    final active = t.module == activeModule;
    return Padding(
      padding: EdgeInsets.only(right: compact ? 6 : 4),
      child: TextButton.icon(
        onPressed:
            active ? null : () => NavigationNotifier.goToModule(t.module),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor:
              active ? Colors.white.withValues(alpha: 0.18) : null,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 6 : 8,
          ),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(t.icon, size: compact ? 14 : 16),
        label: Text(
          t.label,
          style: TextStyle(
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            fontSize: compact ? 11 : 13,
            color: active ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _PosTab {
  const _PosTab(this.module, this.label, this.icon);
  final String module;
  final String label;
  final IconData icon;
}
