import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/pos_sell_print_settings.dart';
import '../../utils/pos_thermal_printer_settings.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/pos/pos_sell_mobile_print_settings_screen.dart';

/// Máy in / mẫu in runtime — Settings hub (HRM). Tái dùng UI mobile print settings.
class PosPrinterSettingsHubScreen extends StatefulWidget {
  const PosPrinterSettingsHubScreen({super.key});

  @override
  State<PosPrinterSettingsHubScreen> createState() =>
      _PosPrinterSettingsHubScreenState();
}

class _PosPrinterSettingsHubScreenState
    extends State<PosPrinterSettingsHubScreen> {
  PosSellPrintSettings? _print;
  PosThermalPrinterSettings? _thermal;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final print = await PosSellPrintSettings.load();
    final thermal = await PosThermalPrinterSettings.load();
    if (!mounted) return;
    setState(() {
      _print = print;
      _thermal = thermal;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _print == null || _thermal == null) {
      return const ColoredBox(
        color: HrmPageChrome.background,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return PosSellMobilePrintSettingsScreen(
      initialPrintSettings: _print!,
      initialThermalSettings: _thermal!,
    );
  }
}
