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
import 'pos_customer_sales_report_screen.dart';
import 'pos_customers_screen.dart';
import 'pos_cancel_return_history_screen.dart';
import 'pos_cashier_shift_screen.dart';
import 'pos_qr_table_order_screen.dart';
import 'pos_kds_screen.dart';
import 'pos_end_of_day_screen.dart';
import 'pos_goods_report_screen.dart';
import 'pos_einvoice_report_screen.dart';
import 'pos_profit_report_screen.dart';
import 'pos_reservation_report_screen.dart';
import 'pos_sales_report_screen.dart';
import 'pos_split_report_screens.dart';
import 'pos_stock_health_report_screen.dart';
import 'pos_supplier_report_screen.dart';
import 'pos_customer_display_settings_screen.dart';
import 'pos_sell_industry_settings_hub_screen.dart';
import 'pos_store_settings_hub_screen.dart';
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
                    _Item('Cuối ngày', Icons.nightlight_round, 'PosReportEndOfDay',
                        const PosEndOfDayScreen(),
                        altModules: const ['PosSalesReport']),
                    _Item('Ca thu ngân', Icons.account_balance_wallet_outlined, 'PosCashierShift',
                        const PosCashierShiftScreen(),
                        altModules: const ['PosSell']),
                    _Item('QR order bàn', Icons.qr_code_2, 'PosQrOrder',
                        const PosQrTableOrderScreen(),
                        altModules: const ['PosSell']),
                    _Item('Màn hình bếp (KDS)', Icons.kitchen_outlined, 'PosKds',
                        const PosKdsScreen(),
                        altModules: const ['PosSell']),
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
                        'PosReportDebt', const PosCustomerDebtReportScreen(),
                        altModules: const ['PosSalesReport']),
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
                      'Ngành hàng',
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
                      'Đặt bàn / đặt phòng / lịch hẹn',
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
                  ],
                ),
                const SizedBox(height: 12),
                _section(
                  context,
                  perm,
                  title: 'Báo cáo',
                  items: [
                    _Item('Doanh thu', Icons.trending_up,
                        'PosReportRevenue', const PosRevenueReportScreen()),
                    _Item('Hàng hóa bán ra', Icons.shopping_cart_outlined,
                        'PosReportSoldGoods', const PosSoldGoodsReportScreen()),
                    _Item('Tồn kho', Icons.warehouse_outlined, 'PosReportStock',
                        const PosReportsScreen(initialTab: 1, lockTab: true)),
                    _Item('Báo cáo nhập hàng', Icons.move_to_inbox_outlined,
                        'PosReportPurchases', const PosPurchaseReportScreen()),
                    _Item('Phương thức thanh toán', Icons.payments_outlined,
                        'PosReportPayment', const PosPaymentMethodReportScreen()),
                    _Item('Công nợ', Icons.account_balance_outlined,
                        'PosReportDebt', const PosDebtCombinedReportScreen()),
                    _Item('Hàng sắp hết hạn', Icons.event_busy_outlined,
                        'PosReportExpiry',
                        const PosReportsScreen(initialTab: 2, lockTab: true)),
                    _Item('Lợi nhuận', Icons.stacked_line_chart,
                        'PosReportProfit', const PosProfitOnlyReportScreen()),
                    _Item('Chi phí', Icons.money_off_outlined,
                        'PosReportExpense', const PosExpenseReportScreen()),
                    _Item('Tổng kết cuối ngày', Icons.nightlight_round,
                        'PosReportEndOfDay', const PosEndOfDayScreen()),
                    _Item('Doanh thu theo nhân viên', Icons.badge_outlined,
                        'PosReportStaffRevenue', const PosStaffRevenueReportScreen()),
                    _Item('Sổ quỹ', Icons.menu_book_outlined,
                        'PosReportCashbook', const PosCashbookReportScreen()),
                    _Item('Kết quả kinh doanh', Icons.account_balance,
                        'PosReportPnl', const PosPnlReportScreen()),
                    _Item('Voucher', Icons.confirmation_number_outlined,
                        'PosReportVoucher', const PosVoucherUsageReportScreen()),
                  ],
                ),
                const SizedBox(height: 12),
                _section(
                  context,
                  perm,
                  title: 'Báo cáo khác',
                  items: [
                    _Item('Báo cáo bán hàng (gộp)', Icons.bar_chart_outlined,
                        'PosSalesReport', const PosSalesReportScreen()),
                    _Item('Hóa đơn điện tử', Icons.request_quote_outlined,
                        'PosEInvoice', const PosEInvoiceReportScreen(),
                        altModules: const ['PosSell', 'PosSaleOrders']),
                    _Item('Báo cáo hàng hóa', Icons.inventory_outlined,
                        'PosSalesReport', const PosGoodsReportScreen()),
                    _Item('Phân tích kinh doanh', Icons.insights_outlined,
                        'PosSalesReport', const PosBusinessAnalysisScreen()),
                    _Item('Lợi nhuận theo chiều', Icons.stacked_line_chart,
                        'PosSalesReport', const PosProfitReportScreen()),
                    _Item('Tồn chậm / cháy hàng', Icons.warning_amber_outlined,
                        'PosSalesReport', const PosStockHealthReportScreen(),
                        altModules: const ['PosProducts']),
                    _Item('Bán theo khách', Icons.people_alt_outlined,
                        'PosSalesReport', const PosCustomerSalesReportScreen()),
                    _Item('Nhà cung cấp', Icons.local_shipping_outlined,
                        'PosSalesReport', const PosSupplierReportScreen(),
                        altModules: const ['PosPurchaseReceipts']),
                    _Item('Đặt chỗ / cọc', Icons.event_seat_outlined,
                        'PosSalesReport', const PosReservationReportScreen(),
                        altModules: const ['PosSell']),
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
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final visible = items.where((i) => _canSeeItem(perm, i, auth)).toList();
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

  static bool _canSeeItem(PermissionProvider perm, _Item item, AuthProvider auth) {
    bool ok(String code) => PermissionNavigation.canAccessModule(
          code,
          allowedModules: auth.user?.allowedModules,
          perm: perm,
          role: auth.user?.role,
        );
    if (ok(item.moduleCode)) return true;
    for (final alt in item.altModules) {
      if (ok(alt)) return true;
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
