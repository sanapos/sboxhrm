import 'pos_print_queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_basics.dart';
import 'pos_printer_settings_hub_screen.dart';
import 'pos_store_printers_screen.dart';

/// Thiết lập SBOX › Máy in: một mục, hai tab — máy in nối với máy này (Bluetooth / LAN / USB)
/// và máy in cloud dùng chung cả cửa hàng (Print Agent). Mỗi tab theo quyền riêng của nó.
class PosPrintersTabsScreen extends StatelessWidget {
  const PosPrintersTabsScreen({super.key, this.cloudFirst = false, this.debugTabs});

  /// Mở sẵn tab «Máy in cloud» (lối tắt cũ «Máy in cloud»).
  final bool cloudFirst;

  /// Test: bỏ qua quyền, chọn tab hiển thị (device, cloud).
  @visibleForTesting
  final ({bool device, bool cloud})? debugTabs;

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    final role = (context.watch<AuthProvider>().user?.role ?? '').toLowerCase();
    final all = role == 'superadmin';
    final device = debugTabs?.device ?? (all || perm.canViewExact('PosPrinters'));
    final cloud = debugTabs?.cloud ?? (all || perm.canViewExact('PosStorePrinters'));
    final tabs = <(String, IconData, Widget)>[
      if (device) ('Trên máy này', Icons.print_outlined, const PosPrinterSettingsHubScreen()),
      if (cloud) ('Máy in cloud', Icons.cloud_outlined, const PosStorePrintersScreen(embeddedInSettings: true)),
      // Lệnh in của mọi máy trong cửa hàng: chờ / treo / lỗi → In lại, chuyển máy in, hủy.
      if (device || cloud) ('Hàng đợi in', Icons.queue_outlined, const PosPrintQueueScreen(embedded: true)),
    ];
    if (tabs.isEmpty) {
      return const SboxEmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Không có quyền',
        message: 'Tài khoản chưa được cấp quyền máy in thiết bị hoặc máy in cloud.',
      );
    }
    if (tabs.length == 1) return tabs.first.$3;
    return DefaultTabController(
      length: tabs.length,
      initialIndex: cloudFirst && cloud ? tabs.length - 1 : 0,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          color: SboxColors.surface,
          child: TabBar(
            labelColor: SboxColors.brand700,
            unselectedLabelColor: SboxColors.slate500,
            indicatorColor: SboxColors.brand600,
            tabs: [for (final t in tabs) Tab(icon: Icon(t.$2, size: 20), text: tr(t.$1), iconMargin: const EdgeInsets.only(bottom: 2))],
          ),
        ),
        const Divider(height: 1, color: SboxColors.border),
        Expanded(child: TabBarView(children: [for (final t in tabs) t.$3])),
      ]),
    );
  }
}
