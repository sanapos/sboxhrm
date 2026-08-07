import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../utils/permission_navigation.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import '../pos/pos_price_lists_screen.dart';
import '../pos_products_screen.dart';
import '../pos_reports_screen.dart';
import '../pos_sale_order_list_screen.dart';
import '../pos_sale_return_list_screen.dart';
import '../pos_sell_screen.dart';
import '../warehouse/wh_mobile_hub_screen.dart';
import '../warehouse/wh_mobile_nav.dart';
import 'pos_warranty_lookup_screen.dart';
import 'pos_appointment_day_screen.dart';
import 'pos_business_analysis_screen.dart';
import 'pos_customer_debt_report_screen.dart';
import 'pos_customers_screen.dart';
import 'pos_cancel_return_history_screen.dart';
import 'pos_end_of_day_screen.dart';
import 'pos_goods_report_screen.dart';
import 'pos_resource_floor_screen.dart';
import 'pos_sales_report_screen.dart';
import 'pos_customer_display_settings_screen.dart';
import 'pos_sell_industry_settings_hub_screen.dart';
import 'pos_store_settings_hub_screen.dart';
import 'pos_printer_settings_hub_screen.dart';
import 'pos_vouchers_screen.dart';
import '../settings_hub_screen.dart';

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
                PosMobileProfileCard(
                  name: user?.fullName ?? 'Cửa hàng',
                  subtitle: (user != null && user.email.isNotEmpty)
                      ? user.email
                      : (user?.position ??
                          user?.department ??
                          'Chi nhánh'),
                ),
                const SizedBox(height: 12),
                _section(
                  context,
                  perm,
                  title: 'Kho hàng',
                  items: [
                    _Item('Trung tâm Kho', Icons.warehouse_outlined, 'PosProducts',
                        const WhMobileHubScreen()),
                  ],
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
                    _Item('Lịch sử hủy / trả', Icons.history, 'PosSell',
                        const PosCancelReturnHistoryScreen(),
                        altModules: const ['PosSaleOrders', 'PosSaleReturns']),
                    _Item('Nhập hàng', Icons.move_to_inbox_outlined,
                        'PosPurchaseReceipts', const WhAdaptivePurchaseReceiptList()),
                    _Item('Trả hàng nhập', Icons.undo_outlined, 'PosPurchaseReturns',
                        const WhAdaptivePurchaseReturnList()),
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
                    _Item('Tra cứu BH', Icons.verified_outlined, 'PosWarranty',
                        const PosWarrantyLookupScreen(),
                        altModules: const ['PosSell', 'PosProducts']),
                    _Item('Kiểm kho', Icons.fact_check_outlined, 'PosStockCounts',
                        const WhAdaptiveStockCountList()),
                    _Item('Xuất hủy', Icons.delete_forever_outlined,
                        'PosDamageIssues', const WhAdaptiveDamageIssueList()),
                    _Item('Dùng nội bộ', Icons.build_outlined,
                        'PosInternalUseIssues', const WhAdaptiveInternalUseList()),
                  ],
                ),
                const SizedBox(height: 12),
                _section(
                  context,
                  perm,
                  title: 'Khách hàng',
                  items: [
                    _Item('Khách hàng', Icons.people_outline, 'PosCustomers',
                        const PosCustomersScreen(),
                        altModules: const ['PosSell', 'PosProducts']),
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
                  title: 'Thiết lập POS',
                  items: [
                    _Item(
                      'Thiết lập HRM / POS',
                      Icons.settings_outlined,
                      'SettingsHub',
                      const SettingsHubScreen(),
                      altModules: const ['PosSell', 'PosProducts'],
                    ),
                    _Item(
                      'Hồ sơ ngành',
                      Icons.storefront_outlined,
                      'PosSell',
                      const PosSellIndustrySettingsHubScreen(),
                      altModules: const ['PosProducts'],
                    ),
                    _Item(
                      'Màn hình phụ',
                      Icons.tv_outlined,
                      'PosCustomerDisplay',
                      const PosCustomerDisplaySettingsScreen(),
                      altModules: const ['PosSell'],
                    ),
                    _Item(
                      'Đặt bàn / lịch hẹn',
                      Icons.event_available_outlined,
                      'PosBooking',
                      const PosAppointmentDayScreen(),
                      altModules: const ['PosSell'],
                    ),
                    _Item(
                      'Thiết lập cửa hàng',
                      Icons.store_outlined,
                      'PosSell',
                      const PosStoreSettingsHubScreen(),
                      altModules: const ['PosProducts'],
                    ),
                    _Item(
                      'Máy in (thiết bị)',
                      Icons.print_outlined,
                      'PosSell',
                      const PosPrinterSettingsHubScreen(),
                      altModules: const ['PosProducts'],
                    ),
                    _Item(
                      'Quản lý bàn/phòng',
                      Icons.table_restaurant_outlined,
                      'PosSell',
                      const PosResourceFloorScreen(manageMode: true),
                      altModules: const ['PosProducts'],
                    ),
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

  Widget _section(
    BuildContext context,
    PermissionProvider perm, {
    required String title,
    required List<_Item> items,
  }) {
    final visible = items.where((i) => _canSeeItem(perm, i)).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return PosMobileHubSectionGrid(
      title: title,
      items: visible
          .map(
            (item) => PosMobileHubGridItem(
              label: item.label,
              icon: item.icon,
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
            ),
          )
          .toList(),
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
