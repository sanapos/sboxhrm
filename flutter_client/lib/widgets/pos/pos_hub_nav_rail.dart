import 'package:flutter/material.dart';

import '../../models/mobile_bottom_nav_config.dart';
import '../../utils/mobile_bottom_nav_catalog.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Một ô trên thanh công cụ dọc hub POS (landscape).
class PosHubNavRailSlot {
  const PosHubNavRailSlot({
    required this.slotIndex,
    required this.slotId,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final int slotIndex;
  final String slotId;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final bool enabled;
  final VoidCallback? onTap;
}

/// Thanh dọc truy cập nhanh hub POS — thay bottom nav khi màn ngang rộng.
///
/// Không dùng trên tab Bán hàng (fullscreen).
class PosHubNavRail extends StatelessWidget {
  const PosHubNavRail({
    super.key,
    required this.slots,
    this.width = 76,
    this.onCustomize,
  });

  final List<PosHubNavRailSlot> slots;
  final double width;
  final VoidCallback? onCustomize;

  /// Landscape đủ rộng (Sunmi T1 / tablet ngang / C20Lite).
  static bool shouldShow(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width >= 720 && size.width > size.height;
  }

  static List<PosHubNavRailSlot> fromLayout({
    required MobileBottomNavLayout layout,
    required int currentTab,
    required bool Function(String slotId) canUse,
    required void Function(int slotIndex, String slotId) onSlotTap,
  }) {
    final map = MobileBottomNavCatalog.mapFor(MobileBottomNavCatalog.posItems);
    return [
      for (var i = 0; i < MobileBottomNavLayout.slotCount; i++)
        () {
          final slotId = layout.slots[i];
          final def = map[slotId];
          final enabled = canUse(slotId) && def != null;
          final tabForSlot = MobileBottomNavCatalog.posTabIndexFor(slotId);
          return PosHubNavRailSlot(
            slotIndex: i,
            slotId: slotId,
            label: def?.label ?? 'Trống',
            icon: def?.icon ?? Icons.remove,
            activeIcon: def?.activeIcon ?? Icons.remove,
            active: enabled && currentTab == tabForSlot,
            enabled: enabled,
            onTap: enabled ? () => onSlotTap(i, slotId) : null,
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: PosTheme.border)),
          ),
          child: SafeArea(
            right: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                  child: Text(
                    tr('Nhanh'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: PosTheme.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                    itemCount: slots.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, i) => _HubRailTile(slot: slots[i]),
                  ),
                ),
                if (onCustomize != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: IconButton(
                      tooltip: tr('Tùy chỉnh thanh công cụ'),
                      onPressed: onCustomize,
                      icon: const Icon(
                        Icons.tune_rounded,
                        size: 20,
                        color: PosTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HubRailTile extends StatelessWidget {
  const _HubRailTile({required this.slot});

  final PosHubNavRailSlot slot;

  @override
  Widget build(BuildContext context) {
    final color = !slot.enabled
        ? PosTheme.textSecondary
        : (slot.active ? PosTheme.kiotBlue : PosTheme.textSecondary);
    return Tooltip(
      message: tr(slot.label),
      child: Material(
        color: slot.active
            ? PosTheme.kiotBlue.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: slot.onTap,
          borderRadius: BorderRadius.circular(10),
          child: Opacity(
            opacity: slot.enabled ? 1 : 0.38,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    slot.active ? slot.activeIcon : slot.icon,
                    size: 24,
                    color: color,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(slot.label),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          slot.active ? FontWeight.w700 : FontWeight.w600,
                      height: 1.15,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
