import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/permission_navigation.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import '../pos_damage_issue_list_screen.dart';
import '../pos_internal_use_list_screen.dart';
import '../pos/pos_price_lists_screen.dart';
import '../pos_products_screen.dart';
import '../pos_purchase_receipt_list_screen.dart';
import '../pos_purchase_return_list_screen.dart';
import '../pos_reports_screen.dart';
import 'pos_warranty_lookup_screen.dart';
import '../pos_sale_order_list_screen.dart';
import '../pos_sale_return_list_screen.dart';
import '../pos_sell_screen.dart';
import '../pos_stock_count_list_screen.dart';
import 'pos_business_analysis_screen.dart';
import 'pos_customer_debt_report_screen.dart';
import 'pos_customers_screen.dart';
import 'pos_end_of_day_screen.dart';
import 'pos_goods_report_screen.dart';
import 'pos_sales_report_screen.dart';
import 'pos_vouchers_screen.dart';

/// Hub «Nhiều hơn» — module POS phụ kiểu KiotViet.
class PosMoreScreen extends StatelessWidget {
  const PosMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final perm = Provider.of<PermissionProvider>(context);
    final user = auth.user;

    return ColoredBox(
      color: PosTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PosMobileKiotHeader(title: 'Nhiều hơn'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
          _profileCard(
            name: user?.fullName ?? 'Cửa hàng',
            subtitle: user?.position ?? user?.department ?? 'Chi nhánh',
          ),
          const SizedBox(height: 12),
          _section(
            context,
            perm,
            title: 'Giao dịch',
            items: [
              _Item('Bán hàng', Icons.shopping_bag_outlined, 'PosSell',
                  const PosSellScreen()),
              _Item('Hoá đơn', Icons.receipt_long_outlined, 'PosSaleOrders',
                  const PosSaleOrderListScreen()),
              _Item('Trả hàng bán', Icons.assignment_return_outlined, 'PosSaleReturns',
                  const PosSaleReturnListScreen()),
              _Item('Nhập hàng', Icons.move_to_inbox_outlined,
                  'PosPurchaseReceipts', const PosPurchaseReceiptListScreen()),
              _Item('Trả hàng nhập', Icons.undo_outlined, 'PosPurchaseReturns',
                  const PosPurchaseReturnListScreen()),
              _Item('Cuối ngày', Icons.nightlight_round, 'PosSalesReport',
                  const PosEndOfDayScreen()),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            context,
            perm,
            title: 'Hàng hoá',
            items: [
              _Item('Hàng hoá', Icons.inventory_2_outlined, 'PosProducts',
                  const PosProductsScreen()),
              _Item('Bảng giá', Icons.price_change_outlined, 'PosProducts',
                  const PosPriceListsScreen(),
                  altModules: const ['PosSell']),
              _Item('Tra cứu BH', Icons.verified_outlined, 'PosSell',
                  const PosWarrantyLookupScreen(),
                  altModules: const ['PosProducts']),
              _Item('Kiểm kho', Icons.fact_check_outlined, 'PosStockCounts',
                  const PosStockCountListScreen()),
              _Item('Xuất hủy', Icons.delete_forever_outlined,
                  'PosDamageIssues', const PosDamageIssueListScreen()),
              _Item('Dùng nội bộ', Icons.build_outlined,
                  'PosInternalUseIssues', const PosInternalUseListScreen()),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            context,
            perm,
            title: 'Khách hàng',
            items: [
              _Item('Khách hàng', Icons.people_outline, 'PosProducts',
                  const PosCustomersScreen()),
              _Item('Công nợ KH', Icons.account_balance_wallet_outlined,
                  'PosSalesReport', const PosCustomerDebtReportScreen()),
              _Item('Voucher', Icons.confirmation_number_outlined, 'PosProducts',
                  const PosVouchersScreen(),
                  altModules: const ['PosSell']),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            context,
            perm,
            title: 'Báo cáo',
            items: [
              _Item('Báo cáo bán hàng', Icons.bar_chart_outlined,
                  'PosSalesReport', const PosSalesReportScreen()),
              _Item('Báo cáo hàng hóa', Icons.inventory_outlined,
                  'PosSalesReport', const PosGoodsReportScreen()),
              _Item('Phân tích kinh doanh', Icons.insights_outlined,
                  'PosSalesReport', const PosBusinessAnalysisScreen()),
              _Item('Báo cáo chi tiết', Icons.table_chart_outlined,
                  'PosSalesReport', const PosReportsScreen()),
            ],
          ),
        ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard({required String name, required String subtitle}) {
    return Container(
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: PosTheme.kiotBlueLight,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'S',
              style: const TextStyle(
                color: PosTheme.kiotBlue,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: PosTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => NavigationNotifier.goToModule('SettingsHub'),
            icon: const Icon(Icons.settings_outlined, color: PosTheme.kiotBlue),
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    PermissionProvider perm, {
    required String title,
    required List<_Item> items,
  }) {
    final visible = items
        .where((i) => _canSeeItem(perm, i))
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.92,
            children: visible
                .map((item) => _gridTile(context, item))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _gridTile(BuildContext context, _Item item) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PosHubScope(
              embeddedInHub: false,
              pushedSubPage: true,
              child: item.screen,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: PosTheme.kiotBlue, size: 26),
            const SizedBox(height: 6),
            Text(
              item.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
  static bool _canSeeItem(PermissionProvider perm, _Item item) {
    if (PermissionNavigation.canNavigate(perm, item.moduleCode)) return true;
    for (final alt in item.altModules) {
      if (PermissionNavigation.canNavigate(perm, alt)) return true;
    }
    return false;
  }
}

class _Item {
  const _Item(this.label, this.icon, this.moduleCode, this.screen,
      {this.altModules = const []});
  final String label;
  final IconData icon;
  final String moduleCode;
  final Widget screen;
  final List<String> altModules;
}
