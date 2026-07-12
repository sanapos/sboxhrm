import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mobile_bottom_nav_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/mobile_bottom_nav_prefs.dart';
import '../../utils/mobile_bottom_nav_catalog.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/permission_navigation.dart';
import '../../widgets/mobile_bottom_nav_config_sheet.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_theme.dart';
import '../pos_products_screen.dart';
import '../pos_sale_order_list_screen.dart';
import '../pos_sell_screen.dart';
import 'pos_more_screen.dart';
import 'pos_overview_screen.dart';

/// Shell POS mobile 5-tab kiểu KiotViet — 5 ô cố định, tùy chỉnh được.
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
    MobileBottomNavPrefs.revision.addListener(_onNavPrefsChanged);
    NavigationNotifier.reportScreen(
      _labelForTab(_tab),
      moduleCode: _moduleForTab(_tab),
    );
  }

  @override
  void didUpdateWidget(PosMobileHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stable hub key: sync tab when MainLayout navigates between POS modules.
    if (oldWidget.initialTab != widget.initialTab) {
      final t = widget.initialTab.clamp(0, 4);
      if (_tab != t) {
        setState(() => _tab = t);
        NavigationNotifier.reportScreen(
          _labelForTab(t),
          moduleCode: _moduleForTab(t),
        );
      }
    }
  }

  @override
  void dispose() {
    MobileBottomNavPrefs.revision.removeListener(_onNavPrefsChanged);
    NavigationNotifier.posHubTab.removeListener(_onExternalTab);
    super.dispose();
  }

  void _onNavPrefsChanged() {
    if (mounted) setState(() {});
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

  String _labelForTab(int tab) {
    final layout = _resolvedPosLayout();
    for (var i = 0; i < layout.slots.length; i++) {
      if (MobileBottomNavCatalog.posTabIndexFor(layout.slots[i]) == tab) {
        return MobileBottomNavCatalog.mapFor(MobileBottomNavCatalog.posItems)[
                layout.slots[i]]
            ?.label ??
            PosHubModules.tabLabels[tab];
      }
    }
    return PosHubModules.tabLabels[tab];
  }

  Set<String> _allowedPosSlotIds(PermissionProvider perm) {
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final allowedModules = authUser?.allowedModules;
    final role = authUser?.role;
    final ids = <String>{MobileBottomNavCatalog.posMoreId};
    for (final d in MobileBottomNavCatalog.posItems) {
      if (d.moduleCode == null) continue;
      if (d.moduleCode == 'PosSalesReport') {
        if (PermissionNavigation.canNavigate(perm, 'PosSalesReport') ||
            PermissionNavigation.canNavigate(perm, 'PosSell')) {
          ids.add(d.id);
        }
        continue;
      }
      if (PermissionNavigation.canAccessModule(
        d.moduleCode!,
        allowedModules: allowedModules,
        perm: perm,
        role: role,
      )) {
        ids.add(d.id);
      }
    }
    return ids;
  }

  MobileBottomNavLayout _resolvedPosLayout() {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    return MobileBottomNavPrefs.posLayout.normalized(
      defaultSlots: MobileBottomNavLayout.defaultPosSlots,
      allowedIds: _allowedPosSlotIds(perm),
    );
  }

  bool _canUsePosSlot(String slotId, PermissionProvider perm) {
    if (slotId == MobileBottomNavCatalog.emptyId) return false;
    if (slotId == MobileBottomNavCatalog.posMoreId) return true;
    if (slotId == 'PosSalesReport') {
      return PermissionNavigation.canNavigate(perm, 'PosSalesReport') ||
          PermissionNavigation.canNavigate(perm, 'PosSell');
    }
    final def = MobileBottomNavCatalog.mapFor(MobileBottomNavCatalog.posItems)[slotId];
    if (def?.moduleCode == null) return false;
    return PermissionNavigation.canNavigate(perm, def!.moduleCode!);
  }

  void _switchTab(int index) {
    if (_tab == index) return;
    setState(() => _tab = index);
    NavigationNotifier.reportScreen(
      _labelForTab(index),
      moduleCode: _moduleForTab(index),
    );
  }

  void _onSlotTap(int slotIndex, String slotId, PermissionProvider perm) {
    if (!_canUsePosSlot(slotId, perm)) return;
    if (slotId == MobileBottomNavCatalog.posMoreId) {
      _switchTab(4);
      return;
    }
    _switchTab(MobileBottomNavCatalog.posTabIndexFor(slotId));
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final layout = _resolvedPosLayout();

    return Scaffold(
      backgroundColor: PosTheme.background,
      body: SafeArea(
        bottom: false,
        child: PosHubScope(
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
      ),
      bottomNavigationBar: Material(
        elevation: 8,
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: GestureDetector(
            onLongPress: () =>
                MobileBottomNavConfigSheet.show(context, initialPage: 1),
            child: SizedBox(
              height: PosTheme.mobileBottomNavHeight + 4,
              child: Row(
                children: List.generate(MobileBottomNavLayout.slotCount, (i) {
                  final slotId = layout.slots[i];
                  final def = MobileBottomNavCatalog
                      .mapFor(MobileBottomNavCatalog.posItems)[slotId];
                  final enabled = _canUsePosSlot(slotId, perm);
                  final tabForSlot =
                      MobileBottomNavCatalog.posTabIndexFor(slotId);
                  final active = _tab == tabForSlot && enabled;

                  if (!enabled || def == null) {
                    return Expanded(
                      child: Opacity(
                        opacity: 0.35,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.remove, size: 20, color: Colors.grey),
                            const SizedBox(height: 2),
                            Text(
                              def?.label ?? 'Trống',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: PosTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Expanded(
                    child: InkWell(
                      onTap: () => _onSlotTap(i, slotId, perm),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            active ? def.activeIcon : def.icon,
                            size: 22,
                            color: active
                                ? PosTheme.kiotBlue
                                : PosTheme.textSecondary,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            def.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w500,
                              color: active
                                  ? PosTheme.kiotBlue
                                  : PosTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void switchToTab(int index) => _switchTab(index.clamp(0, 4));
}
