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
    if (PosHubScope.of(context)) return const SizedBox.shrink();
    final mobile = Responsive.isMobile(context);

    return Material(
      color: const Color(0xFF1A3A5C),
      child: SafeArea(
        bottom: false,
        child: mobile ? _buildMobile(context) : _buildDesktop(context),
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

  Widget _buildMobile(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
          child: Row(
            children: [
              const Text(
                'SBOX POS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              if (activeModule != 'PosSell')
                TextButton.icon(
                  onPressed: () => NavigationNotifier.goToModule('PosSell'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: PosTheme.kiotBlue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.point_of_sale, size: 16),
                  label: const Text('Bán', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            children: _tabs.map((t) => _tabButton(t, compact: true)).toList(),
          ),
        ),
      ],
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
