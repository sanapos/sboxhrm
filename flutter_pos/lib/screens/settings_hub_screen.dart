import 'package:flutter/material.dart';

import 'pos/pos_printer_settings_hub_screen.dart';
import 'pos/pos_sell_industry_settings_hub_screen.dart';
import 'pos/pos_store_settings_hub_screen.dart';

/// Hub thiết lập POS (không gồm HRM).
class SettingsHubScreen extends StatelessWidget {
  const SettingsHubScreen({super.key});

  static final ValueNotifier<int?> pendingSubIndex = ValueNotifier<int?>(null);
  static bool isEmbeddedSubPage = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thiết lập POS')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Cửa hàng / ngành hàng'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PosSellIndustrySettingsHubScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Thiết lập cửa hàng'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PosStoreSettingsHubScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: const Text('Máy in'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PosPrinterSettingsHubScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
