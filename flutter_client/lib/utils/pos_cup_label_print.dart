import 'pos_sell_store_settings.dart';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import 'pos_barcode_print.dart';
import 'pos_label_printer_service.dart';
import 'pos_label_renderer.dart';
import 'pos_local_printers_store.dart';
import 'pos_print_orchestrator.dart';
import 'pos_print_template_compiler.dart';
import 'pos_print_template_loader.dart';
import 'pos_print_template_runtime.dart';
import 'pos_print_template_v2_codec.dart';
import 'pos_print_template_v2_presets.dart';
import 'pos_printer_transport.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_thermal_printer_settings.dart';
import 'pos_topping_format.dart';
import '../l10n/app_tr.dart';

/// Má»™t tem dÃ¡n ly (1 pháº§n = 1 tem).
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

bool _isKitchenReceiptPrinter(PosStorePrinter p) {
  bool has(String t) =>
      p.documentTypes.any((x) => x.toLowerCase() == t.toLowerCase());
  return has(PosCloudDocumentTypes.kitchenSlip) ||
      has(PosCloudDocumentTypes.kitchenVoid) ||
      has(PosLocalPrinterRoles.kitchenSlip) ||
      has(PosLocalPrinterRoles.kitchenVoid);
}

bool _cloudLabelPrinterReady(PosStorePrinter p) {
  if (!p.isActive || !p.isLabelPrinter) return false;
  if (_isKitchenReceiptPrinter(p)) return false;
  return p.isDeviceLocal || p.isOnline;
}

/// MÃ¡y tem ná»™i bá»™ (USB/BT/LAN) hoáº·c mÃ¡y tem cá»­a hÃ ng Ä‘ang káº¿t ná»‘i (Agent online).
Future<bool> hasReadyCupLabelPrinter() async {
  if (!kIsWeb) {
    final all = await PosLocalPrintersStore.instance.loadAll();
    if (all.any((p) =>
        PosLocalPrintersStore.profileAllowsDirectLocal(p) && p.isLabel)) {
      return true;
    }
  }
  try {
    await PosPrintOrchestrator.instance.refreshConfig();
  } catch (_) {}
  return PosPrintOrchestrator.instance.printers.any(_cloudLabelPrinterReady);
}

/// In tem trÃ  sá»¯a / dÃ¡n ly.
///
/// Æ¯u tiÃªn **mÃ¡y in tem** (KitchenLabel / má»i mÃ¡y kind=label),
/// khÃ´ng Ä‘áº©y sang mÃ¡y hÃ³a Ä‘Æ¡n Sunmi trá»« khi khÃ´ng cÃ³ mÃ¡y tem.
Future<bool> printCupLabels({
  required List<CupLabelTicket> tickets,
  DateTime? printedAt,
  bool showFeedback = false,
  PosPrintTemplateV2? templateOverride,
}) async {
  if (tickets.isEmpty) return false;
  if (!await hasReadyCupLabelPrinter()) {
    if (showFeedback) {
      NotificationOverlayManager().showWarning(
        title: 'ChÆ°a cÃ³ mÃ¡y in tem',
        message: tr(
          'Káº¿t ná»‘i mÃ¡y tem trong cá»­a hÃ ng rá»“i in. KhÃ´ng táº¡o phiáº¿u chá» khi chÆ°a cÃ³ mÃ¡y.',
        ),
      );
    }
    debugPrint('Cup label: bá» qua â€” khÃ´ng cÃ³ mÃ¡y tem káº¿t ná»‘i');
    return false;
  }
  final timeFmt = DateFormat('dd/MM/yyyy');
  final hourFmt = DateFormat('HH:mm');
  final when = printedAt ?? DateTime.now();
  final storeNameForCup = (await PosSellStoreSettings.load()).storeName;

  if (!kIsWeb) {
    final all = await PosLocalPrintersStore.instance.loadAll();
    // 1) MÃ¡y tem ná»™i bá»™ Ä‘Ã£ cÃ i (USB/BT/Sunmi/LAN) + role KitchenLabel.
    // KhÃ´ng cÃ³ local â€” chá»‰ lanHost Agent â†’ cloud phÃ­a dÆ°á»›i.
    var labelTargets = all
        .where((p) =>
            PosLocalPrintersStore.profileAllowsDirectLocal(p) &&
            p.isLabel &&
            p.hasRole(PosLocalPrinterRoles.kitchenLabel))
        .toList();
    // 2) Má»i mÃ¡y tem ná»™i bá»™ Ä‘ang báº­t (ká»ƒ cáº£ chá»‰ BarcodeLabel)
    if (labelTargets.isEmpty) {
      labelTargets = all
          .where((p) =>
              PosLocalPrintersStore.profileAllowsDirectLocal(p) && p.isLabel)
          .toList();
    }

    if (labelTargets.isNotEmpty) {
      final v2 = templateOverride ?? await _loadKitchenLabelTemplate();
      // Khá»• váº­t lÃ½ = mÃ¡y tem (TSPL SIZE/GAP). Layout máº«u scale vÃ o canvas mÃ¡y â€” trÃ¡nh trÃ´i.
      var anyOk = false;
      for (final p in labelTargets) {
        final settings = p.toLabelSettings().copyWith(enabled: true);
        final machineTpl = settings.template ??
            posBarcodeLabelTemplateById('roll_1_50x30')!;
        final widthMm = machineTpl.labelWidthMm;
        final heightMm = machineTpl.labelHeightMm;
        final jobs =
            <({Uint8List raster, int widthPx, int heightPx})>[];
        final outputs = _compileCupOutputs(
          tickets: tickets,
          v2: v2.copyWith(paperSize: machineTpl.id),
          timeFmt: timeFmt,
          hourFmt: hourFmt,
          when: when,
          storeName: storeNameForCup,
        );
        for (var i = 0; i < outputs.length; i++) {
          final r = await PosLabelRenderer.renderCompiledLabel(
            output: outputs[i],
            widthMm: widthMm,
            heightMm: heightMm,
            dpi: settings.dpi,
            marginLeftMm: settings.marginLeftMm,
            marginRightMm: settings.marginRightMm,
            marginTopMm: settings.marginTopMm,
            marginBottomMm: settings.marginBottomMm,
            fontScale: settings.fontScale,
          );
          if (!PosLabelRenderer.hasEnoughInk(r.raster)) {
            // Fallback raster cá»©ng náº¿u máº«u trá»‘ng.
            final t = tickets[i];
            final fallback = await PosLabelRenderer.renderCupTicket(
              productName: t.productName,
              tableLabel: t.tableLabel,
              orderNo: t.orderNo,
              toppings: t.toppings,
              note: t.note,
              qtyLabel: t.qtyLabel,
              widthMm: widthMm,
              heightMm: heightMm,
              dpi: settings.dpi,
              marginLeftMm: settings.marginLeftMm,
              marginRightMm: settings.marginRightMm,
              marginTopMm: settings.marginTopMm,
              marginBottomMm: settings.marginBottomMm,
              fontScale: settings.fontScale,
              showHeader: settings.showHeader,
              showTable: settings.showTable,
              showOrderNo: settings.showOrderNo,
              showToppings: settings.showToppings,
              showNote: settings.showNote,
              showQty: settings.showQty,
            );
            if (PosLabelRenderer.hasEnoughInk(fallback.raster)) {
              jobs.add(fallback);
            }
            continue;
          }
          jobs.add(r);
        }
        if (jobs.isEmpty) {
          if (showFeedback) {
            NotificationOverlayManager().showError(
              title: 'Tem ly trá»‘ng',
              message: tr('KhÃ´ng render Ä‘Æ°á»£c chá»¯ tem. Thá»­ láº¡i hoáº·c kiá»ƒm tra font.'),
            );
          }
          continue;
        }
        final ok = await PosLabelPrinterService.printCupRasters(
          jobs,
          settings: settings,
          widthMm: widthMm,
          heightMm: heightMm,
        );
        if (ok) {
          // Chá»‰ 1 mÃ¡y tem â€” trÃ¡nh in Ä‘Ã´i khi cÃ³ 2 profile cÃ¹ng role.
          anyOk = true;
          break;
        }
      }
      if (anyOk) {
        if (showFeedback) {
          NotificationOverlayManager().showSuccess(
            title: 'Tem ly',
            message: tr('ÄÃ£ in lÃªn mÃ¡y tem'),
          );
        }
        return true;
      }
    }

    // 3) MÃ¡y nhiá»‡t ná»™i bá»™ cÃ³ role KitchenLabel â€” khÃ´ng dÃ¹ng mÃ¡y phiáº¿u cháº¿ biáº¿n.
    final thermalCup = all
        .where((p) =>
            PosLocalPrintersStore.profileAllowsDirectLocal(p) &&
            !p.isLabel &&
            p.hasRole(PosLocalPrinterRoles.kitchenLabel) &&
            !p.hasRole(PosLocalPrinterRoles.kitchenSlip) &&
            !p.hasRole(PosLocalPrinterRoles.kitchenVoid))
        .toList();
    if (thermalCup.isNotEmpty) {
      final v2 = templateOverride ?? await _loadKitchenLabelTemplate();
      final outputs = _compileCupOutputs(
        tickets: tickets,
        v2: v2,
        timeFmt: timeFmt,
        hourFmt: hourFmt,
        when: when,
          storeName: storeNameForCup,
      );
      var anyOk = false;
      for (final p in thermalCup) {
        final prepared =
            await PosPrinterTransport.prepareLocalSettings(p.toThermalSettings());
        final cupSettings = prepared.copyWith(
          feedBeforeCut: 8,
          openCashDrawer: false,
        );
        // KhÃ´ng Ã©p Sunmi khi connection khÃ´ng pháº£i sunmi.
        final ok = await _printCupOutputsLocal(
          outputs: outputs,
          cupSettings: cupSettings,
          showFeedback: false,
        );
        if (ok) {
          anyOk = true;
          break;
        }
      }
      if (anyOk) {
        if (showFeedback) {
          NotificationOverlayManager().showSuccess(
            title: 'Tem ly',
            message: tr('ÄÃ£ in tem ly'),
          );
        }
        return true;
      }
    }
  }

  // Cloud â†’ Print Agent.
  final v2 = templateOverride ?? await _loadKitchenLabelTemplate();
  final outputs = _compileCupOutputs(
    tickets: tickets,
    v2: v2,
    timeFmt: timeFmt,
    hourFmt: hourFmt,
    when: when,
          storeName: storeNameForCup,
  );

  await PosPrintOrchestrator.instance.refreshConfig();
  final cloudPrinter = _resolveCupLabelCloudPrinter();
  if (cloudPrinter != null && outputs.isNotEmpty) {
    try {
      // MÃ¡y tem (TSPL/Xprinter): pháº£i gá»­i bitmap TSPL â€” EscPos ghi USB Â«OKÂ»
      // nhÆ°ng Tem 350BM khÃ´ng in gÃ¬.
      if (cloudPrinter.isLabelPrinter) {
        final labelSettings = toLabelSettings(cloudPrinter);
        // Khá»• váº­t lÃ½ theo mÃ¡y tem â€” khÃ´ng dÃ¹ng mm máº«u thiáº¿t káº¿ (trÃ¡nh trÃ´i/cáº¯t).
        final machineTpl = labelSettings.template ??
            posBarcodeLabelTemplateById('roll_1_50x30')!;
        final widthMm = machineTpl.labelWidthMm;
        final heightMm = machineTpl.labelHeightMm;
        final rasters = <({Uint8List raster, int widthPx, int heightPx})>[];
        for (var i = 0; i < outputs.length; i++) {
          final r = await PosLabelRenderer.renderCompiledLabel(
            output: outputs[i],
            widthMm: widthMm,
            heightMm: heightMm,
            dpi: labelSettings.dpi,
            marginLeftMm: labelSettings.marginLeftMm,
            marginRightMm: labelSettings.marginRightMm,
            marginTopMm: labelSettings.marginTopMm,
            marginBottomMm: labelSettings.marginBottomMm,
            fontScale: labelSettings.fontScale,
          );
          if (!PosLabelRenderer.hasEnoughInk(r.raster)) {
            final t = tickets[i];
            final fallback = await PosLabelRenderer.renderCupTicket(
              productName: t.productName,
              tableLabel: t.tableLabel,
              orderNo: t.orderNo,
              toppings: t.toppings,
              note: t.note,
              qtyLabel: t.qtyLabel,
              widthMm: widthMm,
              heightMm: heightMm,
              dpi: labelSettings.dpi,
              marginLeftMm: labelSettings.marginLeftMm,
              marginRightMm: labelSettings.marginRightMm,
              marginTopMm: labelSettings.marginTopMm,
              marginBottomMm: labelSettings.marginBottomMm,
              fontScale: labelSettings.fontScale,
              showHeader: labelSettings.showHeader,
              showTable: labelSettings.showTable,
              showOrderNo: labelSettings.showOrderNo,
              showToppings: labelSettings.showToppings,
              showNote: labelSettings.showNote,
              showQty: labelSettings.showQty,
            );
            if (PosLabelRenderer.hasEnoughInk(fallback.raster)) {
              rasters.add(fallback);
            }
            continue;
          }
          rasters.add(r);
        }
        if (rasters.isNotEmpty) {
          final jobs = PosLabelPrinterService.buildCupRasterByteJobs(
            rasters,
            settings: labelSettings,
            widthMm: widthMm,
            heightMm: heightMm,
          );
          var allOk = true;
          for (var i = 0; i < jobs.length; i++) {
            final ok = await PosPrintOrchestrator.instance.dispatchEscPos(
              documentType: PosCloudDocumentTypes.kitchenLabel,
              bytes: jobs[i],
              printerId: cloudPrinter.id,
              showFeedback: showFeedback && i == jobs.length - 1,
              successTitle: 'Tem ly',
              skipDedup: true,
              // KhÃ´ng treo UI 90s chá» Completed â€” Agent Claimed = Ä‘ang in tem.
              waitForCompletion: false,
              acceptClaimedAsSuccess: true,
              hangAfter: const Duration(seconds: 90),
            );
            if (!ok) {
              allOk = false;
              break;
            }
          }
          if (allOk) return true;
        }
      } else if (!_isKitchenReceiptPrinter(cloudPrinter)) {
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
          acceptClaimedAsSuccess: true,
          hangAfter: const Duration(seconds: 90),
        );
        if (ok) return true;
      } else {
        debugPrint(
          'Cup label: bá» Agent ${cloudPrinter.name} â€” mÃ¡y phiáº¿u cháº¿ biáº¿n',
        );
      }
    } catch (e) {
      debugPrint('Cloud cup label (V2) failed: $e');
    }
  }

  // KhÃ´ng fallback EscPos Â«Ban: â€¦Â» lÃªn mÃ¡y phiáº¿u cháº¿ biáº¿n / mÃ¡y báº¥t ká»³.
  debugPrint(
    'Cup label: khÃ´ng in â€” cáº§n mÃ¡y tem (KitchenLabel), khÃ´ng Ä‘áº©y Agent lÃªn mÃ¡y báº¿p',
  );
  if (showFeedback) {
    NotificationOverlayManager().showError(
      title: 'ChÆ°a in tem ly',
      message: tr(
        'ChÆ°a cÃ³ mÃ¡y in tem. VÃ o MÃ¡y in ná»™i bá»™ â†’ thÃªm mÃ¡y Tem, gÃ¡n vai trÃ² Tem báº¿p.',
      ),
    );
  }
  return false;
}

/// MÃ¡y tem tháº­t (TSPL) Ä‘ang káº¿t ná»‘i â€” khÃ´ng gá»­i phiáº¿u cloud khi Agent offline.
PosStorePrinter? _resolveCupLabelCloudPrinter() {
  final orch = PosPrintOrchestrator.instance;
  for (final doc in [
    PosCloudDocumentTypes.kitchenLabel,
    PosCloudDocumentTypes.barcodeLabel,
  ]) {
    for (final p in orch.resolvePrinters(doc)) {
      if (_cloudLabelPrinterReady(p)) return p;
    }
  }
  for (final p in orch.printers) {
    if (_cloudLabelPrinterReady(p)) return p;
  }
  return null;
}

List<PosPrintCompiledOutput> _compileCupOutputs({
  required List<CupLabelTicket> tickets,
  required PosPrintTemplateV2 v2,
  required DateFormat timeFmt,
  required DateFormat hourFmt,
  required DateTime when,
  String? storeName,
}) {
  final outputs = <PosPrintCompiledOutput>[];
  for (final t in tickets) {
    final noteParts = <String>[];
    final tops = (t.toppings ?? '').trim();
    if (tops.isNotEmpty) noteParts.add(posToppingLabelText(tops));
    final note = (t.note ?? '').trim();
    if (note.isNotEmpty) noteParts.add(note);
    final data = <String, String>{
      'Ten_Cua_Hang': (storeName ?? '').trim(),
      'Ten_Ban': (t.tableLabel ?? '').trim(),
      'Ma_Don_Hang': (t.orderNo ?? '').trim(),
      'Ngay': timeFmt.format(when),
      'Gio': hourFmt.format(when),
      'Ten_Hang_Hoa':
          t.productName.trim().isEmpty ? 'MÃ³n' : t.productName.trim(),
      'Ghi_Chu': noteParts.join('\n'),
      'So_Luong': (t.qtyLabel ?? '1').trim().isEmpty
          ? '1'
          : (t.qtyLabel ?? '1').trim(),
      'Don_Vi_Tinh': '',
      'Ma_Hang': '',
      'Ma_Vach': '',
      'Don_Gia': '',
      'Tieu_De_In': 'TEM LY',
    };
    // Khá»‘iã€ŒTÃªn hÃ ngã€lÃ  lineItems â€” pháº£i cÃ³ 1 dÃ²ng, náº¿u khÃ´ng in tháº­t trá»‘ng dÃ¹ preview cÃ³ sample.
    final lineRow = <String, String>{
      'Ten_Hang_Hoa': data['Ten_Hang_Hoa'] ?? '',
      'So_Luong': data['So_Luong'] ?? '1',
      'Don_Vi_Tinh': data['Don_Vi_Tinh'] ?? '',
      'Ghi_Chu': data['Ghi_Chu'] ?? '',
      'Don_Gia': data['Don_Gia'] ?? '',
      'Ma_Hang': data['Ma_Hang'] ?? '',
      'Ma_Vach': data['Ma_Vach'] ?? '',
    };
    outputs.add(PosPrintTemplateCompiler.compile(
      template: v2,
      data: data,
      lineItems: [lineRow],
    ));
  }
  return outputs;
}

Future<bool> _printCupOutputsLocal({
  required List<PosPrintCompiledOutput> outputs,
  required PosThermalPrinterSettings cupSettings,
  required bool showFeedback,
}) async {
  if (cupSettings.connectionType == PosThermalConnectionType.sunmi) {
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
    return PosPrintOrchestrator.instance.dispatchLocalEscPos(
      bytes: merged,
      showFeedback: showFeedback,
      successTitle: 'Tem ly',
      settingsOverride: cupSettings,
      documentType: PosPrintDocumentTypes.kitchenLabel,
      skipDedup: true,
    );
  } catch (e) {
    debugPrint('Local cup label failed: $e');
    return false;
  }
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
