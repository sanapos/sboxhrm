import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import 'pos_print_orchestrator.dart';
import 'pos_print_template_compiler.dart';
import 'pos_print_template_loader.dart';
import 'pos_print_template_runtime.dart';
import 'pos_print_template_v2_codec.dart';
import 'pos_print_template_v2_presets.dart';
import 'pos_printer_transport.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_thermal_printer_service.dart';
import 'pos_thermal_printer_settings.dart';

/// Một tem dán ly (1 phần = 1 tem).
class CupLabelTicket {
  const CupLabelTicket({
    required this.productName,
    this.toppings,
    this.note,
    this.qtyLabel,
    this.tableLabel,
    this.orderNo,
  });

  final String productName;
  final String? toppings;
  final String? note;
  final String? qtyLabel;
  final String? tableLabel;
  final String? orderNo;
}

/// In tem trà sữa / dán ly — dùng mẫu **Tem báo bếp** (KitchenLabel) nếu có.
/// Mỗi phần (unit) = 1 tem; in 1 lần theo SL chưa in.
Future<bool> printCupLabels({
  required List<CupLabelTicket> tickets,
  DateTime? printedAt,
  bool showFeedback = false,
  PosPrintTemplateV2? templateOverride,
}) async {
  if (tickets.isEmpty) return false;
  final timeFmt = DateFormat('dd/MM/yyyy');
  final hourFmt = DateFormat('HH:mm');
  final when = printedAt ?? DateTime.now();

  final v2 = templateOverride ?? await _loadKitchenLabelTemplate();

  Future<PosThermalPrinterSettings> loadSettings() async {
    if (!kIsWeb) {
      final thermal = await PosThermalPrinterSettings.load();
      if (thermal.enabled) {
        return PosPrinterTransport.prepareLocalSettings(thermal);
      }
    }
    final printers = PosPrintOrchestrator.instance.printers;
    if (printers.isNotEmpty) return toThermalSettings(printers.first);
    return const PosThermalPrinterSettings();
  }

  final settings = (await loadSettings()).copyWith(
    feedBeforeCut: 8,
    openCashDrawer: false,
  );

  // Biên dịch từng tem theo mẫu V2.
  final outputs = <PosPrintCompiledOutput>[];
  for (final t in tickets) {
    final noteParts = <String>[];
    final tops = (t.toppings ?? '').trim();
    if (tops.isNotEmpty) noteParts.add(tops);
    final note = (t.note ?? '').trim();
    if (note.isNotEmpty) noteParts.add(note);
    final data = <String, String>{
      'Ten_Cua_Hang': '',
      'Ten_Ban': (t.tableLabel ?? '').trim(),
      'Ma_Don_Hang': (t.orderNo ?? '').trim(),
      'Ngay': timeFmt.format(when),
      'Gio': hourFmt.format(when),
      'Ten_Hang_Hoa': t.productName.trim().isEmpty ? 'Món' : t.productName.trim(),
      'Ghi_Chu': noteParts.join('\n'),
      'So_Luong': (t.qtyLabel ?? '1').trim().isEmpty ? '1' : (t.qtyLabel ?? '1').trim(),
      'Don_Vi_Tinh': '',
      'Ma_Hang': '',
      'Ma_Vach': '',
      'Don_Gia': '',
      'Tieu_De_In': 'TEM LY',
    };
    outputs.add(PosPrintTemplateCompiler.compile(
      template: v2,
      data: data,
      lineItems: const [],
    ));
  }

  if (!kIsWeb) {
    final thermal = await PosThermalPrinterSettings.load();
    if (thermal.enabled) {
      final prepared = await PosPrinterTransport.prepareLocalSettings(thermal);
      final cupSettings = prepared.copyWith(
        feedBeforeCut: 8,
        openCashDrawer: false,
      );
      if (cupSettings.connectionType == PosThermalConnectionType.sunmi ||
          await PosPrinterTransport.isSunmiDevice()) {
        var allOk = true;
        for (final output in outputs) {
          final ok = await PosPrintTemplateRuntime.printCompiledSunmi(
            output: output,
            settings: cupSettings.copyWith(
              connectionType: PosThermalConnectionType.sunmi,
              printerBrand: PosThermalPrinterBrand.sunmi,
            ),
            kitchenFeed: true,
          );
          if (!ok) allOk = false;
        }
        if (allOk) return true;
      }
      try {
        final merged = <int>[];
        for (final output in outputs) {
          final bytes = await PosPrintTemplateRuntime.buildCompiledEscPosBytes(
            output: output,
            settings: cupSettings,
          );
          merged.addAll(bytes);
        }
        final localOk = await PosPrintOrchestrator.instance.dispatchLocalEscPos(
          bytes: merged,
          showFeedback: showFeedback,
          successTitle: 'Tem ly',
          settingsOverride: cupSettings,
          documentType: PosPrintDocumentTypes.kitchenLabel,
          skipDedup: true,
        );
        if (localOk) return true;
      } catch (e) {
        debugPrint('Local cup label failed: $e');
      }
    }
  }

  // Cloud → Print Agent (web + khi local lỗi).
  await PosPrintOrchestrator.instance.refreshConfig();
  final cloudPrinter = PosPrintOrchestrator.instance
          .resolvePrinter(PosCloudDocumentTypes.kitchenLabel) ??
      PosPrintOrchestrator.instance
          .resolvePrinter(PosCloudDocumentTypes.barcodeLabel);
  if (cloudPrinter != null && outputs.isNotEmpty) {
    try {
      final cupSettings = toThermalSettings(cloudPrinter).copyWith(
        feedBeforeCut: 8,
        openCashDrawer: false,
      );
      final merged = <int>[];
      for (final output in outputs) {
        merged.addAll(await PosPrintTemplateRuntime.buildCompiledEscPosBytes(
          output: output,
          settings: cupSettings,
        ));
      }
      final ok = await PosPrintOrchestrator.instance.dispatchEscPos(
        documentType: PosCloudDocumentTypes.kitchenLabel,
        bytes: merged,
        printerId: cloudPrinter.id,
        showFeedback: showFeedback,
        successTitle: 'Tem ly',
        skipDedup: true,
        waitForCompletion: false,
      );
      if (ok) return true;
    } catch (e) {
      debugPrint('Cloud cup label (V2) failed: $e');
    }
  }

  // Fallback text cứng qua cloud.
  final body = <String>[];
  for (var i = 0; i < tickets.length; i++) {
    final t = tickets[i];
    if (i > 0) body.add('');
    body.add('*** TEM LY ***');
    final table = (t.tableLabel ?? '').trim();
    if (table.isNotEmpty) body.add('Ban: $table');
    final order = (t.orderNo ?? '').trim();
    if (order.isNotEmpty) body.add('HD: $order');
    body.add(DateFormat('dd/MM HH:mm').format(when));
    body.add('--------------------');
    body.add(t.productName.trim().isEmpty ? 'Mon' : t.productName.trim());
    final tops = (t.toppings ?? '').trim();
    if (tops.isNotEmpty) {
      for (final part in tops.split(RegExp(r'[,;]'))) {
        final p = part.trim();
        if (p.isNotEmpty) body.add('+ $p');
      }
    }
    final note = (t.note ?? '').trim();
    if (note.isNotEmpty) body.add('GC: $note');
    final qty = (t.qtyLabel ?? '').trim();
    if (qty.isNotEmpty) body.add('SL: $qty');
    body.add('--------------------');
  }

  if (cloudPrinter == null &&
      PosPrintOrchestrator.instance.printers.isEmpty &&
      settings.enabled == false) {
    return false;
  }
  final target = cloudPrinter ??
      PosPrintOrchestrator.instance.printers.firstOrNull;
  if (target == null) return false;
  final cloudSettings = toThermalSettings(target)
      .copyWith(feedBeforeCut: 8, openCashDrawer: false);
  final bytes = await PosThermalPrinterService.buildTextEscPosBytes(
    settings: cloudSettings,
    title: '',
    lines: body,
  );
  return PosPrintOrchestrator.instance.dispatchEscPos(
    documentType: PosCloudDocumentTypes.kitchenLabel,
    bytes: bytes,
    printerId: target.id,
    showFeedback: showFeedback,
    successTitle: 'Tem ly',
    skipDedup: true,
    waitForCompletion: false,
  );
}

Future<PosPrintTemplateV2> _loadKitchenLabelTemplate() async {
  try {
    final list = await loadPosPrintTemplates(
      ApiService(),
      PosPrintDocumentTypes.kitchenLabel,
    ).timeout(const Duration(seconds: 8), onTimeout: () => <PosPrintTemplate>[]);
    final t = list.where((e) => e.isDefault).firstOrNull ?? list.firstOrNull;
    final parsed = PosPrintTemplateV2Codec.tryParse(t?.htmlContent);
    if (parsed != null) return parsed;
  } catch (e) {
    debugPrint('Load KitchenLabel template: $e');
  }
  return PosPrintTemplateV2Presets.build(
    documentType: PosPrintDocumentTypes.kitchenLabel,
    paperSize: PosPrintPaperSizes.label50x30,
    printerProfile: PosPrintPrinterProfiles.genericK58,
  );
}
