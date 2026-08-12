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
import 'pos_thermal_printer_service.dart';
import 'pos_thermal_printer_settings.dart';
import '../l10n/app_tr.dart';

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

/// In tem trà sữa / dán ly.
///
/// Ưu tiên **máy in tem** (KitchenLabel / mọi máy kind=label),
/// không đẩy sang máy hóa đơn Sunmi trừ khi không có máy tem.
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

  if (!kIsWeb) {
    final all = await PosLocalPrintersStore.instance.loadAll();
    // 1) Máy tem nội bộ đã cài (USB/BT/Sunmi/LAN) + role KitchenLabel.
    // Không có local — chỉ lanHost Agent → cloud phía dưới.
    var labelTargets = all
        .where((p) =>
            PosLocalPrintersStore.profileAllowsDirectLocal(p) &&
            p.isLabel &&
            p.hasRole(PosLocalPrinterRoles.kitchenLabel))
        .toList();
    // 2) Mọi máy tem nội bộ đang bật (kể cả chỉ BarcodeLabel)
    if (labelTargets.isEmpty) {
      labelTargets = all
          .where((p) =>
              PosLocalPrintersStore.profileAllowsDirectLocal(p) && p.isLabel)
          .toList();
    }

    if (labelTargets.isNotEmpty) {
      final v2 = templateOverride ?? await _loadKitchenLabelTemplate();
      // Ưu tiên khổ giấy theo mẫu thiết kế; fallback khổ máy in tem.
      final designTplId =
          PosPrintPaperSizes.toLabelTemplateId(v2.paperSize);
      final designSize = posBarcodeLabelTemplateById(designTplId);
      var anyOk = false;
      for (final p in labelTargets) {
        final settings = p.toLabelSettings().copyWith(enabled: true);
        final machineTpl = settings.template ??
            posBarcodeLabelTemplateById('roll_1_50x30')!;
        final tpl = designSize ?? machineTpl;
        final widthMm = tpl.labelWidthMm;
        final heightMm = tpl.labelHeightMm;
        final jobs =
            <({Uint8List raster, int widthPx, int heightPx})>[];
        final outputs = _compileCupOutputs(
          tickets: tickets,
          v2: v2.copyWith(
            paperSize: designSize != null ? v2.paperSize : machineTpl.id,
          ),
          timeFmt: timeFmt,
          hourFmt: hourFmt,
          when: when,
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
            // Fallback raster cứng nếu mẫu trống.
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
              title: 'Tem ly trống',
              message: tr('Không render được chữ tem. Thử lại hoặc kiểm tra font.'),
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
          // Chỉ 1 máy tem — tránh in đôi khi có 2 profile cùng role.
          anyOk = true;
          break;
        }
      }
      if (anyOk) {
        if (showFeedback) {
          NotificationOverlayManager().showSuccess(
            title: 'Tem ly',
            message: tr('Đã in lên máy tem'),
          );
        }
        return true;
      }
    }

    // 3) Máy nhiệt nội bộ có role KitchenLabel (gồm LAN đã cài trên máy này).
    final thermalCup = all
        .where((p) =>
            PosLocalPrintersStore.profileAllowsDirectLocal(p) &&
            !p.isLabel &&
            p.hasRole(PosLocalPrinterRoles.kitchenLabel))
        .toList();
    if (thermalCup.isNotEmpty) {
      final v2 = templateOverride ?? await _loadKitchenLabelTemplate();
      final outputs = _compileCupOutputs(
        tickets: tickets,
        v2: v2,
        timeFmt: timeFmt,
        hourFmt: hourFmt,
        when: when,
      );
      var anyOk = false;
      for (final p in thermalCup) {
        final prepared =
            await PosPrinterTransport.prepareLocalSettings(p.toThermalSettings());
        final cupSettings = prepared.copyWith(
          feedBeforeCut: 8,
          openCashDrawer: false,
        );
        // Không ép Sunmi khi connection không phải sunmi.
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
            message: tr('Đã in tem ly'),
          );
        }
        return true;
      }
    }
  }

  // Cloud → Print Agent.
  final v2 = templateOverride ?? await _loadKitchenLabelTemplate();
  final outputs = _compileCupOutputs(
    tickets: tickets,
    v2: v2,
    timeFmt: timeFmt,
    hourFmt: hourFmt,
    when: when,
  );

  await PosPrintOrchestrator.instance.refreshConfig();
  final cloudPrinter = PosPrintOrchestrator.instance
          .resolvePrinter(PosCloudDocumentTypes.kitchenLabel) ??
      PosPrintOrchestrator.instance
          .resolvePrinter(PosCloudDocumentTypes.barcodeLabel);
  if (cloudPrinter != null && outputs.isNotEmpty) {
    try {
      // Máy tem (TSPL/Xprinter): phải gửi bitmap TSPL — EscPos ghi USB «OK»
      // nhưng Tem 350BM không in gì.
      if (cloudPrinter.isLabelPrinter) {
        final labelSettings = toLabelSettings(cloudPrinter);
        final designTplId =
            PosPrintPaperSizes.toLabelTemplateId(v2.paperSize);
        final designSize = posBarcodeLabelTemplateById(designTplId);
        final machineTpl = labelSettings.template ??
            posBarcodeLabelTemplateById('roll_1_50x30')!;
        final tpl = designSize ?? machineTpl;
        final widthMm = tpl.labelWidthMm;
        final heightMm = tpl.labelHeightMm;
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
              // Không treo UI 90s chờ Completed — Agent Claimed = đang in tem.
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
      } else {
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
      }
    } catch (e) {
      debugPrint('Cloud cup label (V2) failed: $e');
    }
  }

  // Fallback text cứng qua cloud — chỉ máy nhiệt (không đẩy EscPos text sang máy tem TSPL).
  if (cloudPrinter != null && cloudPrinter.isLabelPrinter) {
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: 'Chưa in tem ly',
        message: tr(
          'Không gửi được tem TSPL tới máy Agent. Kiểm tra USB tem (rút cáp ADB) và thử lại.',
        ),
      );
    }
    return false;
  }

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
  }

  if (cloudPrinter == null &&
      PosPrintOrchestrator.instance.printers.isEmpty) {
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: 'Chưa in tem ly',
        message: tr(
          'Chưa có máy in tem. Vào Máy in nội bộ → thêm máy Tem, gán vai trò Tem bếp.',
        ),
      );
    }
    return false;
  }
  final target =
      cloudPrinter ?? PosPrintOrchestrator.instance.printers.firstOrNull;
  if (target == null) return false;
  if (target.isLabelPrinter) return false;
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
    acceptClaimedAsSuccess: true,
    hangAfter: const Duration(seconds: 90),
  );
}

List<PosPrintCompiledOutput> _compileCupOutputs({
  required List<CupLabelTicket> tickets,
  required PosPrintTemplateV2 v2,
  required DateFormat timeFmt,
  required DateFormat hourFmt,
  required DateTime when,
}) {
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
      'Ten_Hang_Hoa':
          t.productName.trim().isEmpty ? 'Món' : t.productName.trim(),
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
    outputs.add(PosPrintTemplateCompiler.compile(
      template: v2,
      data: data,
      lineItems: const [],
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
