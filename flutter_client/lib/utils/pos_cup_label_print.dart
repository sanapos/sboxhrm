import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/pos_print_template.dart';
import 'pos_print_orchestrator.dart';
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

/// In tem trà sữa / dán ly — nhiệt K58/K80 (cùng máy báo bếp).
/// Mỗi phần (unit) = 1 tem; in 1 lần theo SL chưa in.
Future<bool> printCupLabels({
  required List<CupLabelTicket> tickets,
  DateTime? printedAt,
  bool showFeedback = false,
}) async {
  if (tickets.isEmpty) return false;
  final timeFmt = DateFormat('dd/MM HH:mm');
  final when = timeFmt.format(printedAt ?? DateTime.now());

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

  final settings = await loadSettings();
  final body = <String>[];
  for (var i = 0; i < tickets.length; i++) {
    final t = tickets[i];
    if (i > 0) body.add('');
    body.add('*** TEM LY ***');
    final table = (t.tableLabel ?? '').trim();
    if (table.isNotEmpty) body.add('Ban: $table');
    final order = (t.orderNo ?? '').trim();
    if (order.isNotEmpty) body.add('HD: $order');
    body.add(when);
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

  if (!kIsWeb) {
    final thermal = await PosThermalPrinterSettings.load();
    if (thermal.enabled) {
      final prepared = await PosPrinterTransport.prepareLocalSettings(thermal);
      final cupSettings = prepared.copyWith(feedBeforeCut: 10);
      if (cupSettings.connectionType == PosThermalConnectionType.sunmi ||
          await PosPrinterTransport.isSunmiDevice()) {
        try {
          // Sunmi: in từng tem ngắn qua ESC/POS text (không phụ thuộc API bếp).
          final bytes = await PosThermalPrinterService.buildTextEscPosBytes(
            settings: cupSettings.copyWith(
              connectionType: PosThermalConnectionType.sunmi,
              printerBrand: PosThermalPrinterBrand.sunmi,
            ),
            title: '',
            lines: body,
          );
          final ok = await PosPrintOrchestrator.instance.dispatchLocalEscPos(
            bytes: bytes,
            showFeedback: showFeedback,
            successTitle: 'Tem ly',
            settingsOverride: cupSettings.copyWith(
              connectionType: PosThermalConnectionType.sunmi,
              printerBrand: PosThermalPrinterBrand.sunmi,
            ),
            documentType: PosPrintDocumentTypes.stockIssue,
            skipDedup: true,
          );
          if (ok) return true;
        } catch (e) {
          debugPrint('Sunmi cup label failed: $e');
        }
      }
      try {
        final bytes = await PosThermalPrinterService.buildTextEscPosBytes(
          settings: cupSettings,
          title: '',
          lines: body,
        );
        return PosPrintOrchestrator.instance.dispatchLocalEscPos(
          bytes: bytes,
          showFeedback: showFeedback,
          successTitle: 'Tem ly',
          settingsOverride: cupSettings,
          documentType: PosPrintDocumentTypes.stockIssue,
          skipDedup: true,
        );
      } catch (e) {
        debugPrint('Local cup label failed: $e');
      }
    }
  }

  final printers = PosPrintOrchestrator.instance.printers;
  if (printers.isEmpty) return false;
  final cloudSettings = toThermalSettings(printers.first).copyWith(feedBeforeCut: 10);
  final bytes = await PosThermalPrinterService.buildTextEscPosBytes(
    settings: cloudSettings,
    title: '',
    lines: body,
  );
  return PosPrintOrchestrator.instance.dispatchLocalEscPos(
    bytes: bytes,
    showFeedback: showFeedback,
    successTitle: 'Tem ly',
    settingsOverride: cloudSettings,
    documentType: PosPrintDocumentTypes.stockIssue,
    skipDedup: true,
  );
}
