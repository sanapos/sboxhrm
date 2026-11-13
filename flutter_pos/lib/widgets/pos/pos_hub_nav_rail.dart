import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mobile_bottom_nav_config.dart';
import '../../providers/auth_provider.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/mobile_bottom_nav_catalog.dart';
import '../../utils/permission_role_options.dart';
import '../../utils/pos_icon_set.dart';
import 'pos_mobile_widgets.dart' show showPosLogoutDialog;
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

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

  /// Landscape đủ rộng (Sunmi T1 / tablet ngang).
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

  /// Màn đủ rộng (T1 ngang 1280dp): menu trái kiểu SBOX POS Android 7 thay thanh dọc hẹp.
  static bool useSidebar(BuildContext context) =>
      SboxColors.posApp && MediaQuery.sizeOf(context).width >= 1100;

  @override
  Widget build(BuildContext context) {
    if (useSidebar(context)) return _PosHubSidebar(slots: slots, onCustomize: onCustomize);
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
            ? PosTheme.kiotBlue.withOpacity(0.08)
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

/// Menu trái kiểu SBOX POS Android 7 (MainLayout): logo, nhóm «Truy cập nhanh», mục icon + chữ,
/// mục đang chọn nền nhạt viền trái màu thương hiệu, thẻ tài khoản ở cuối.
class _PosHubSidebar extends StatelessWidget {
  const _PosHubSidebar({required this.slots, this.onCustomize});

  final List<PosHubNavRailSlot> slots;
  final VoidCallback? onCustomize;

  static const width = 240.0;

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).user;
    final name = (user?.fullName ?? '').trim();
    return ColoredBox(
      color: SboxColors.chrome,
      child: SizedBox(
        width: width,
        child: SafeArea(
          right: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset('assets/sbox_pos_mark_gsm.png', width: 32, height: 32, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('SBOX POS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: SboxColors.brand600)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Text(tr('Truy cập nhanh').toUpperCase(),
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: SboxColors.slate400)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 2),
                children: [for (final s in slots) _SidebarTile(slot: s)],
              ),
            ),
            if (onCustomize != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: TextButton.icon(
                  onPressed: onCustomize,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(tr('Tùy chỉnh menu')),
                  style: TextButton.styleFrom(foregroundColor: SboxColors.slate600, alignment: Alignment.centerLeft),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Material(
                color: SboxColors.white,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: SboxColors.brand50,
                      child: Text(name.isEmpty ? 'S' : name.substring(0, 1).toUpperCase(),
                          style: TextStyle(fontWeight: FontWeight.w700, color: SboxColors.brand600)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(name.isEmpty ? tr('Cửa hàng') : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2B3437))),
                        Text(tr(PermissionRoleOptions.displayNameOf(user?.role ?? 'Employee')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: SboxColors.slate600)),
                      ]),
                    ),
                    IconButton(
                      tooltip: tr('Đăng xuất'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => showPosLogoutDialog(context),
                      icon: Icon(Icons.logout_rounded, size: 18, color: SboxColors.slate600.withOpacity(0.7)),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({required this.slot});

  final PosHubNavRailSlot slot;

  @override
  Widget build(BuildContext context) {
    final sel = slot.active;
    const accent = SboxColors.brand600;
    final icon = PosIconSet.ofNav(slot.label, sel ? slot.activeIcon : slot.icon);
    return Opacity(
      opacity: slot.enabled ? 1 : 0.38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Material(
          color: sel ? accent.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: slot.onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: sel
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: const Border(left: BorderSide(color: accent, width: 3)),
                    )
                  : null,
              child: Row(children: [
                Icon(icon, size: 21, color: sel ? accent : SboxColors.slate600),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tr(slot.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: sel ? const Color(0xFF2B3437) : SboxColors.slate600,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      )),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
