import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/permission_provider.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/permission_navigation.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_theme.dart';
import '../pos_products_screen.dart';
import '../pos_sale_order_list_screen.dart';
import '../pos_sell_screen.dart';
import 'pos_more_screen.dart';
import 'pos_overview_screen.dart';

/// Shell POS mobile 5-tab kiểu KiotViet.
class PosMobileHubScreen extends StatefulWidget {
  const PosMobileHubScreen({
    super.key,
    this.initialTab = 2,
  });

  final int initialTab;

  @override
  State<PosMobileHubScreen> createState() => PosMobileHubScreenState();
}

class PosMobileHubScreenState extends State<PosMobileHubScreen> {
  late int _tab = widget.initialTab.clamp(0, 4);

  @override
  void initState() {
    super.initState();
    NavigationNotifier.posHubTab.addListener(_onExternalTab);
    NavigationNotifier.reportScreen(
      PosHubModules.tabLabels[_tab],
      moduleCode: _moduleForTab(_tab),
    );
  }

  @override
  void dispose() {
    NavigationNotifier.posHubTab.removeListener(_onExternalTab);
    super.dispose();
  }

  void _onExternalTab() {
    final t = NavigationNotifier.posHubTab.value;
    if (t == null || !mounted) return;
    NavigationNotifier.posHubTab.value = null;
    setState(() => _tab = t.clamp(0, 4));
  }

  String _moduleForTab(int tab) => switch (tab) {
        0 => 'PosSalesReport',
        1 => 'PosProducts',
        2 => 'PosSell',
        3 => 'PosSaleOrders',
        _ => 'PosHub',
      };

  void _switchTab(int index) {
    if (_tab == index) return;
    setState(() => _tab = index);
    NavigationNotifier.reportScreen(
      PosHubModules.tabLabels[index],
      moduleCode: _moduleForTab(index),
    );
  }

  bool _canViewTab(int index, PermissionProvider perm) {
    return switch (index) {
      0 => PermissionNavigation.canNavigate(perm, 'PosSalesReport') ||
          PermissionNavigation.canNavigate(perm, 'PosSell'),
      1 => PermissionNavigation.canNavigate(perm, 'PosProducts'),
      2 => PermissionNavigation.canNavigate(perm, 'PosSell'),
      3 => PermissionNavigation.canNavigate(perm, 'PosSaleOrders'),
      4 => true,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);

    return Scaffold(
      backgroundColor: PosTheme.background,
      body: PosHubScope(
        embeddedInHub: true,
        child: IndexedStack(
          index: _tab,
          children: const [
            PosOverviewScreen(key: ValueKey('pos_overview')),
            PosProductsScreen(key: ValueKey('pos_products')),
            PosSellScreen(key: ValueKey('pos_sell')),
            PosSaleOrderListScreen(key: ValueKey('pos_orders')),
            PosMoreScreen(key: ValueKey('pos_more')),
          ],
        ),
      ),
      bottomNavigationBar: Material(
        elevation: 8,
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: PosTheme.mobileBottomNavHeight + 4,
            child: Row(
              children: List.generate(5, (i) {
                if (!_canViewTab(i, perm)) {
                  return const SizedBox.shrink();
                }
                return Expanded(
                  child: _navItem(
                    index: i,
                    icon: _iconFor(i, false),
                    activeIcon: _iconFor(i, true),
                    label: PosHubModules.tabLabels[i],
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(int tab, bool active) {
    return switch (tab) {
      0 => active ? Icons.insights : Icons.insights_outlined,
      1 => active ? Icons.inventory_2 : Icons.inventory_2_outlined,
      2 => active ? Icons.shopping_bag : Icons.shopping_bag_outlined,
      3 => active ? Icons.receipt_long : Icons.receipt_long_outlined,
      _ => active ? Icons.menu : Icons.menu_outlined,
    };
  }

  Widget _navItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final active = _tab == index;
    return InkWell(
      onTap: () => _switchTab(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            active ? activeIcon : icon,
            size: 22,
            color: active ? PosTheme.kiotBlue : PosTheme.textSecondary,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? PosTheme.kiotBlue : PosTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void switchToTab(int index) => _switchTab(index.clamp(0, 4));
}
