import 'pos_promotions_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/pos_sell_industry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/permission_navigation.dart';
import '../../utils/pos_lite_mode.dart';
import '../../utils/pos_icon_set.dart';
import '../../widgets/pos/pos_hub_nav_rail.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../utils/store_role_helper.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;
import '../../widgets/pos/pos_ai_assistant_sheet.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import '../pos/pos_price_lists_screen.dart';
import '../pos_products_screen.dart';
import '../pos_sale_order_list_screen.dart';
import '../pos_sale_return_list_screen.dart';
import '../pos_sell_screen.dart';
import '../pos_stock_transfer_screen.dart';
import '../warehouse/wh_mobile_hub_screen.dart';
import '../warehouse/wh_mobile_nav.dart';
import 'pos_warranty_lookup_screen.dart';
import 'pos_appointment_day_screen.dart';
import 'pos_customer_debt_report_screen.dart';
import 'pos_customers_screen.dart';
import 'pos_cancel_return_history_screen.dart';
import 'pos_cashier_shift_screen.dart';
import 'pos_qr_table_order_screen.dart';
import 'pos_qr_menu_screen.dart';
import 'pos_qr_online_orders_screen.dart';
import 'pos_kds_screen.dart';
import 'pos_end_of_day_screen.dart';
import 'pos_split_report_screens.dart';
import 'pos_einvoice_report_screen.dart';
import '../pos_print_templates_screen.dart';
import 'pos_transfer_confirm_screen.dart';
import 'pos_vouchers_screen.dart';
import '../settings_hub_screen.dart';
import 'pos_quote_list_screen.dart';
import 'pos_app_settings_screen.dart';
import 'pos_gym_checkin_screen.dart';
import '../../services/pos_app_update_service.dart';
import '../../widgets/pos_app_update_dialog.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
/// Hub «Nhiều hơn» — module POS phụ kiểu KiotViet.
class PosMoreScreen extends StatefulWidget {
  const PosMoreScreen({super.key});

  @override
  State<PosMoreScreen> createState() => _PosMoreScreenState();
}

class _PosMoreScreenState extends State<PosMoreScreen> {
  PosStoreSellSettingsDto? _sell;

  bool get _shiftOn => _sell?.enableCashierShift == true;
  bool get _qrOn => _sell?.enableQrTableOrder == true;
  bool get _gymOn => _sell?.enableSessionPacks == true;

  @override
  void initState() {
    super.initState();
    ScreenRefreshNotifier.posSellIndustry.addListener(_reloadSell);
    _reloadSell();
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.posSellIndustry.removeListener(_reloadSell);
    super.dispose();
  }

  Future<void> _reloadSell() async {
    final r = await PosSellSettingsHelper(ApiService()).load();
    if (!mounted) return;
    setState(() => _sell = r.settings);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final perm = Provider.of<PermissionProvider>(context);
    final user = auth.user;
    bool canMod(String code) => PermissionNavigation.canAccessModule(
          code,
          allowedModules: user?.allowedModules,
          perm: perm,
          role: user?.role,
        );

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
                if (PosHubNavRail.useSidebar(context))
                  _greeting(user?.fullName ?? 'Cửa hàng')
                else
                PosMobileProfileCard(
                  name: user?.fullName ?? 'Cửa hàng',
                  subtitle: (user != null && user.email.isNotEmpty)
                      ? user.email
                      : (user?.position ??
                          user?.department ??
                          'Chi nhánh'),
                ),
                if (NavigationNotifier.mainLayoutReady.value) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: NavigationNotifier.leavePosHubToAppHome,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: PosTheme.kiotBlue.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.apps_outlined,
                                  color: PosTheme.kiotBlue),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr('Về SBOX HRM'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    tr('Thoát bán hàng · mở toàn bộ phần mềm'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: SboxColors.slate600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right,
                                color: SboxColors.slate400),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                // Nhóm và dòng phụ theo Trang chủ SBOX POS Android 7.
                const SizedBox(height: 24),
                _section(
                  context,
                  perm,
                  title: 'Bán hàng',
                  subtitle: 'Thu ngân, đơn hàng, bếp, đặt lịch',
                  items: [
                    _Item('Bán hàng', Icons.shopping_bag_outlined, 'PosSell',
                        const PosSellScreen(), subtitle: 'Thu ngân'),
                    _Item('Màn hình bếp (KDS)', Icons.kitchen_outlined, 'PosKds',
                        const PosKdsScreen(), subtitle: 'Báo bếp'),
                    _Item('Đơn hàng', Icons.receipt_long_outlined, 'PosSaleOrders',
                        const PosSaleOrderListScreen(), subtitle: 'Hóa đơn'),
                    _Item('Menu QR / Online', Icons.restaurant_menu, 'PosQrOrder',
                        const PosQrMenuScreen(), visible: _qrOn, subtitle: 'Menu QR'),
                    _Item('Đơn online', Icons.delivery_dining_outlined, 'PosQrOrder',
                        const PosQrOnlineOrdersScreen(), visible: _qrOn, subtitle: 'QR online'),
                    _Item('QR order bàn', Icons.qr_code_2, 'PosQrOrder',
                        const PosQrTableOrderScreen(), visible: _qrOn, subtitle: 'Gọi món tại bàn'),
                    _Item('Trả hàng bán', Icons.assignment_return_outlined, 'PosSaleReturns',
                        const PosSaleReturnListScreen(), subtitle: 'Trả hàng'),
                    _Item('Đặt lịch', Icons.event_available_outlined, 'PosBooking',
                        const PosAppointmentDayScreen()),
                    _Item('Check-in hội viên', Icons.fingerprint, 'PosSell',
                        const PosGymCheckInScreen(), visible: _gymOn, subtitle: 'Gym: quét máy chấm công'),
                    _Item('Ca thu ngân', Icons.account_balance_wallet_outlined, 'PosCashierShift',
                        const PosCashierShiftScreen(), visible: _shiftOn, subtitle: 'Mở / đóng ca'),
                    _Item('Cuối ngày', Icons.nightlight_round, 'PosReportEndOfDay',
                        const PosEndOfDayScreen(), subtitle: 'Tổng kết cuối ngày'),
                    _Item('Xác nhận CK', Icons.payments_outlined, 'PosSell',
                        const PosTransferConfirmScreen(), altModules: const ['PosSell'], subtitle: 'Chuyển khoản chờ xác nhận'),
                  ],
                ),
                const SizedBox(height: 24),
                _section(
                  context,
                  perm,
                  title: 'Thương mại',
                  subtitle: 'Báo giá, hợp đồng',
                  items: [
                    _Item('Báo giá', Icons.request_quote_outlined, 'PosQuotes',
                        const PosQuoteListScreen(), subtitle: 'Thương mại'),
                    _Item('Mẫu in báo giá', Icons.article_outlined, 'PosPrintTemplates',
                        const PosPrintTemplatesScreen(initialDocumentType: 'Quote'), visible: canMod('PosQuotes'), subtitle: 'A4 thương mại'),
                    _Item('Hợp đồng', Icons.handshake_outlined, 'PosContracts',
                        const PosQuoteListScreen(initialTab: 1), subtitle: 'Thu tiền theo đợt'),
                  ],
                ),
                const SizedBox(height: 24),
                _section(
                  context,
                  perm,
                  title: 'Khách hàng & khuyến mãi',
                  subtitle: 'Khách hàng, bảo hành, khuyến mãi, voucher',
                  items: [
                    _Item('Khách hàng POS', Icons.people_outline, 'PosCustomers',
                        const PosCustomersScreen(), subtitle: 'Khách hàng'),
                    _Item('Bảo hành POS', Icons.verified_outlined, 'PosWarranty',
                        const PosWarrantyLookupScreen(), subtitle: 'Bảo hành'),
                    _Item('Voucher', Icons.confirmation_number_outlined, 'PosProducts',
                        const PosVouchersScreen(), altModules: const ['PosSell'], subtitle: 'Mã giảm giá'),
                    _Item('Khuyến mãi', Icons.local_offer_outlined, 'PosPromotions',
                        const PosPromotionsScreen(), subtitle: 'Tự động áp khi bán'),
                  ],
                ),
                const SizedBox(height: 24),
                _section(
                  context,
                  perm,
                  title: 'Hàng hóa & kho',
                  subtitle: 'Hàng hóa, nhập hàng, kiểm kho',
                  items: [
                    _Item('Hàng hóa', Icons.inventory_2_outlined, 'PosProducts',
                        const PosProductsScreen(), subtitle: 'SP, tồn, giá'),
                    _Item('Trung tâm Kho', Icons.warehouse_outlined, 'PosProducts',
                        const WhMobileHubScreen(), subtitle: 'Nhập, xuất, kiểm kho'),
                    _Item('Chuyển kho', Icons.local_shipping_outlined, 'PosProducts',
                        const PosStockTransferScreen(), subtitle: 'Giữa chi nhánh'),
                    _Item('Nhập hàng NCC', Icons.move_to_inbox_outlined, 'PosPurchaseReceipts',
                        const WhAdaptivePurchaseReceiptList(), subtitle: 'Nhập hàng'),
                    _Item('Trả hàng nhập', Icons.undo_outlined, 'PosPurchaseReturns',
                        const WhAdaptivePurchaseReturnList(), subtitle: 'Trả NCC'),
                    _Item('Kiểm kho', Icons.fact_check_outlined, 'PosStockCounts',
                        const WhAdaptiveStockCountList(), subtitle: 'Kiểm kê'),
                    _Item('Xuất hủy', Icons.delete_forever_outlined, 'PosDamageIssues',
                        const WhAdaptiveDamageIssueList()),
                    _Item('Xuất dùng nội bộ', Icons.build_outlined, 'PosInternalUseIssues',
                        const WhAdaptiveInternalUseList(), subtitle: 'Xuất nội bộ'),
                    _Item('Bảng giá', Icons.price_change_outlined, 'PosProducts',
                        const PosPriceListsScreen(), altModules: const ['PosSell'], subtitle: 'Giá sỉ / VIP / theo kỳ'),
                  ],
                ),
                const SizedBox(height: 24),
                _section(
                  context,
                  perm,
                  title: 'Báo cáo kinh doanh',
                  subtitle: 'Doanh thu, hủy trả, thu chi',
                  items: [
                    _Item('Báo cáo hủy / trả', Icons.history, 'PosSell',
                        const PosCancelReturnHistoryScreen(), altModules: const ['PosSaleOrders', 'PosSaleReturns'], subtitle: 'Hủy / trả'),
                    _Item('Công nợ khách hàng', Icons.account_balance_wallet_outlined, 'PosReportDebt',
                        const PosCustomerDebtReportScreen(), subtitle: 'Công nợ'),
                    _Item('Hóa đơn điện tử', Icons.receipt_long_outlined, 'PosEInvoice',
                        const PosEInvoiceReportScreen(), subtitle: 'Xuất, gửi, thay thế, hủy'),
                  ],
                ),
                const SizedBox(height: 12),
                // Hai lối vào duy nhất: «Cài đặt» (của tôi) và «Thiết lập SBOX» (cấu hình cửa hàng).
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline, color: PosTheme.kiotBlue),
                      title: Text(tr('Cài đặt'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(tr('Ngôn ngữ, phiên bản, cập nhật, điều khoản, đăng xuất')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const PosAppSettingsScreen()),
                      ),
                    ),
                    if (_canOpenSetup(perm)) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.tune_rounded, color: PosTheme.kiotBlue),
                        title: Text(tr('Thiết lập SBOX'), style: const TextStyle(fontWeight: FontWeight.w700)),
                        // Máy Android 6 (chế độ gọn) không có tài khoản / phân quyền — làm trên web / SBOX HRM.
                        subtitle: Text(tr(PosLiteMode.enabled
                            ? 'Cửa hàng, bán hàng, thanh toán, máy in'
                            : 'Cửa hàng, bán hàng, thanh toán, máy in, người dùng')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const SettingsHubScreen()),
                        ),
                      ),
                    ],
                  ]),
                ),
                if (PermissionNavigation.canAccessModule(
                  'PosSalesReport',
                  allowedModules: auth.user?.allowedModules,
                  perm: perm,
                  role: auth.user?.role,
                )) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      leading: const Icon(Icons.bar_chart_outlined,
                          color: PosTheme.kiotBlue),
                      title: Text(
                        tr('Báo cáo POS'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(tr('Doanh thu, sổ quỹ, kho, lợi nhuận…')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PosHubScope(
                              embeddedInHub: false,
                              pushedSubPage: true,
                              child: PosReportsHubScreen(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (canUsePosAiAssistant(context)) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      leading: const Icon(Icons.auto_awesome, color: Color(0xFF7C3AED)),
                      title: Text(tr('Trợ lý ảo'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(tr('Hỏi số liệu, ra lệnh bằng chữ hoặc giọng nói')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showPosAiAssistant(context),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: Column(
                    children: [
                      FutureBuilder(
                        future: PosAppUpdateService.currentPackage(),
                        builder: (context, snap) {
                          final info = snap.data;
                          final ver = info == null
                              ? '…'
                              : 'v${info.version} (${info.buildNumber})';
                          return ListTile(
                            leading: const Icon(Icons.system_update_alt,
                                color: PosTheme.kiotBlue),
                            title: Text(
                              tr('Cập nhật ứng dụng'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              tr('Đang dùng $ver — tải APK mới (Android 6+)'),
                            ),
                            onTap: () async {
                              final release =
                                  await PosAppUpdateService.checkForUpdate();
                              if (!context.mounted) return;
                              if (release == null) {
                                final cur =
                                    await PosAppUpdateService.currentPackage();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      tr(
                                        'Đang dùng bản mới nhất ${cur.version} (${cur.buildNumber}).',
                                      ),
                                    ),
                                  ),
                                );
                                return;
                              }
                              final cur =
                                  await PosAppUpdateService.currentPackage();
                              if (!context.mounted) return;
                              await showPosAppUpdateDialog(
                                context,
                                release: release,
                                currentVersion:
                                    '${cur.version} (${cur.buildNumber})',
                              );
                            },
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading:
                            Icon(Icons.logout, color: Colors.red.shade600),
                        title: Text(
                          tr('Đăng xuất'),
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(tr('Thoát tài khoản cửa hàng')),
                        onTap: () => showPosLogoutDialog(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder(
                  future: PosAppUpdateService.currentPackage(),
                  builder: (context, snap) {
                    final info = snap.data;
                    final label = info == null
                        ? '…'
                        : 'v${info.version} (${info.buildNumber})';
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Text(
                        'SBOX POS $label',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: SboxColors.slate600,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Lời chào + ngày như Trang chủ SBOX POS Android 7 (màn rộng có menu trái, thẻ tài khoản ở menu).
  Widget _greeting(String name) {
    final now = DateTime.now();
    final h = now.hour;
    final hello = h < 11 ? 'Chào buổi sáng,' : (h < 18 ? 'Chào buổi chiều,' : 'Chào buổi tối,');
    const wd = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ nhật'];
    final date = '${wd[now.weekday - 1]}, ${now.day} Th${now.month} ${now.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(hello), style: SboxType.bodyStyle(SboxColors.textMuted)),
            const SizedBox(height: 2),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF2B3437))),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: SboxColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: SboxColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_today_outlined, size: 15, color: SboxColors.slate600),
            const SizedBox(width: 8),
            Text(tr(date), style: SboxType.smallStyle(SboxColors.slate600)),
          ]),
        ),
      ]),
    );
  }

  Widget _section(
    BuildContext context,
    PermissionProvider perm, {
    required String title,
    String? subtitle,
    required List<_Item> items,
  }) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final visible = items.where((i) => _canSeeItem(perm, i, auth)).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return PosMobileHubSectionGrid(
      title: title,
      subtitle: subtitle,
      icon: PosIconSet.ofGroup(title, Icons.apps_rounded),
      items: visible
          .map(
            (item) => PosMobileHubGridItem(
              label: item.label,
              icon: PosIconSet.ofNav(item.label, item.icon),
              subtitle: item.subtitle,
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

  /// Thiết lập SBOX: thấy khi có quyền ít nhất một mục cấu hình.
  bool _canOpenSetup(PermissionProvider perm) => _canSeeItem(
        perm,
        const _Item('Thiết lập SBOX', Icons.tune_rounded, 'SettingsHub', SizedBox.shrink(), altModules: [
          'PosPrinters',
          'PosStorePrinters',
          'PosPrintTemplates',
          'PosEInvoice',
          'PosShipping',
          'PosCustomerDisplay',
          'UserManagement',
          'Role',
        ]),
        context.read<AuthProvider>(),
      );

  static bool _canSeeItem(PermissionProvider perm, _Item item, AuthProvider auth) {
    if (!item.visible || !PosLiteMode.showMore(item.label)) return false;
    bool inPackage(String code) => PermissionNavigation.isAllowedByPackageOrRole(
          code,
          allowedModules: auth.user?.allowedModules,
          perm: perm,
          bypassPackageFilter:
              StoreRoleHelper.bypassesPackageFilter(auth.user?.role),
        );
    bool exact(String code) => perm.canViewExact(code) && inPackage(code);
    bool ok(String code) => PermissionNavigation.canAccessModule(
          code,
          allowedModules: auth.user?.allowedModules,
          perm: perm,
          role: auth.user?.role,
        );
    const setupExact = {
      'SettingsHub',
      'PosPrinters',
      'PosStorePrinters',
      'PosPrintTemplates',
      'PosEInvoice',
      'PosShipping',
      'PosCustomerDisplay',
    };
    if (item.altModules.isNotEmpty) {
      if (ok(item.moduleCode)) return true;
      for (final alt in item.altModules) {
        if (exact(alt) || ok(alt)) return true;
      }
      return false;
    }
    if (setupExact.contains(item.moduleCode)) {
      return exact(item.moduleCode);
    }
    return ok(item.moduleCode);
  }
}

class _Item {
  const _Item(this.label, this.icon, this.moduleCode, this.screen,
      {this.altModules = const [], this.visible = true, this.subtitle});
  final String? subtitle;
  final String label;
  final IconData icon;
  final String moduleCode;
  final Widget screen;
  final List<String> altModules;
  final bool visible;
}
