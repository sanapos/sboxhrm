import '../../l10n/app_tr.dart';
import '../../widgets/ai_assistant_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/permission_navigation.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;
import '../overview/business_overview_screen.dart';
import 'pos_qr_menu_screen.dart';
import 'pos_qr_online_orders_screen.dart';
import 'pos_kds_screen.dart';

/// Tổng quan POS — Truy cập nhanh + tổng quan bán hàng chuẩn SBOX (biểu đồ trên, bảng dưới).
class PosOverviewScreen extends StatefulWidget {
  const PosOverviewScreen({super.key});

  @override
  State<PosOverviewScreen> createState() => _PosOverviewScreenState();
}

class _PosOverviewScreenState extends State<PosOverviewScreen> {
  int _reloadKey = 0;

  @override
  void initState() {
    super.initState();
    ScreenRefreshNotifier.posOverview.addListener(_onExternalRefresh);
  }

  void _onExternalRefresh() {
    if (mounted) setState(() => _reloadKey++);
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.posOverview.removeListener(_onExternalRefresh);
    super.dispose();
  }

  void _goHubTab(int index) {
    NavigationNotifier.posHubTab.value = index;
  }

  void _pushPosPage(Widget child) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PosHubScope(
          embeddedInHub: false,
          pushedSubPage: true,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inHub = PosHubScope.of(context);
    final perm = Provider.of<PermissionProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final canReport = PermissionNavigation.canAccessModule('PosSalesReport',
        allowedModules: auth.user?.allowedModules, perm: perm, role: auth.userRole);
    final quick = _buildQuickAccessSection();
    return ColoredBox(
      color: PosTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inHub)
            PosMobileKiotHeader(
              title: 'Tổng quan',
              onRefresh: () async => setState(() => _reloadKey++),
              trailing: [
                if (canUseAiAssistant(context))
                IconButton(
                  icon: const Icon(Icons.auto_awesome, color: Color(0xFF7C3AED)),
                  tooltip: tr('Trợ lý ảo AI'),
                  onPressed: () => showAiAssistant(context),
                ),
              ],
            ),
          Expanded(
            child: canReport
                ? BusinessOverviewScreen(
                    key: ValueKey('pos_overview_$_reloadKey'),
                    mode: OverviewMode.pos,
                    leading: [quick],
                    showLegacyLink: false,
                  )
                : ListView(padding: const EdgeInsets.all(12), children: [quick]),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessSection() {
    // Tổng quan = điều hướng tab chính + QR hay dùng.
    // Module đầy đủ nằm ở tab «Nhiều hơn».
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    bool canMod(String code) => PermissionNavigation.canAccessModule(
          code,
          allowedModules: auth.user?.allowedModules,
          perm: perm,
          role: auth.user?.role,
        );
    final canQr = canMod('PosQrOrder');
    final canKds = canMod('PosKds');
    final items = <PosMobileHubGridItem>[
      if (canUseAiAssistant(context))
      PosMobileHubGridItem(
        label: 'Trợ lý AI',
        icon: Icons.auto_awesome_outlined,
        onTap: () => showAiAssistant(context),
      ),
      if (canMod('PosSell'))
        PosMobileHubGridItem(
          label: 'Bán hàng',
          icon: Icons.shopping_bag_outlined,
          onTap: () => _goHubTab(2),
        ),
      if (canMod('PosProducts'))
        PosMobileHubGridItem(
          label: 'Hàng hoá',
          icon: Icons.inventory_2_outlined,
          onTap: () => _goHubTab(1),
        ),
      if (canMod('PosSaleOrders'))
        PosMobileHubGridItem(
          label: 'Hoá đơn',
          icon: Icons.receipt_long_outlined,
          onTap: () => _goHubTab(3),
        ),
      if (canKds)
        PosMobileHubGridItem(
          label: 'Màn hình bếp',
          icon: Icons.kitchen_outlined,
          onTap: () => _pushPosPage(const PosKdsScreen()),
        ),
      if (canQr)
        PosMobileHubGridItem(
          label: 'Menu QR',
          icon: Icons.restaurant_menu,
          onTap: () => _pushPosPage(const PosQrMenuScreen()),
        ),
      if (canQr)
        PosMobileHubGridItem(
          label: 'Đơn online',
          icon: Icons.delivery_dining_outlined,
          onTap: () => _pushPosPage(const PosQrOnlineOrdersScreen()),
        ),
      PosMobileHubGridItem(
        label: 'Nhiều hơn',
        icon: Icons.apps_outlined,
        onTap: () => _goHubTab(4),
      ),
    ];
    return PosMobileHubSectionGrid(
      title: 'Truy cập nhanh',
      items: items,
    );
  }
}
