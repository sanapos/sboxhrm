import 'package:flutter/material.dart';

import '../../utils/navigation_notifier.dart';
import 'pos_theme.dart';

/// Thanh công cụ POS phía trên (giống KiotViet).
class PosModuleToolbar extends StatelessWidget {
  const PosModuleToolbar({
    super.key,
    this.activeModule = 'PosProducts',
  });

  final String activeModule;

  static const _tabs = [
    _PosTab('PosProducts', 'Hàng hóa'),
    _PosTab('PosSell', 'Bán hàng'),
    _PosTab('PosSaleOrders', 'Đơn hàng'),
    _PosTab('PosPurchaseReceipts', 'Nhập hàng NCC'),
    _PosTab('PosPurchaseReturns', 'Trả hàng nhập'),
    _PosTab('PosStockCounts', 'Kiểm kho'),
    _PosTab('PosDamageIssues', 'Xuất hủy'),
    _PosTab('PosInternalUseIssues', 'Xuất dùng NB'),
    _PosTab('PosSalesReport', 'Báo cáo'),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A3A5C),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
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
              ..._tabs.map((t) {
                final active = t.module == activeModule;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TextButton(
                    onPressed: active
                        ? null
                        : () => NavigationNotifier.goToModule(t.module),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor:
                          active ? Colors.white.withValues(alpha: 0.15) : null,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                    child: Text(
                      t.label,
                      style: TextStyle(
                        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 13,
                        color: active ? Colors.white : Colors.white70,
                      ),
                    ),
                  ),
                );
              }),
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
        ),
      ),
    );
  }
}

class _PosTab {
  const _PosTab(this.module, this.label);
  final String module;
  final String label;
}
