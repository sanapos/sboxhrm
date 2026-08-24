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

/// Máy tem nội bộ (USB/BT/LAN) hoặc máy tem cửa hàng đang kết nối (Agent online).
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
  if (!await hasReadyCupLabelPrinter()) {
    if (showFeedback) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa có máy in tem',
        message: tr(
          'Kết nối máy tem trong cửa hàng rồi in. Không tạo phiếu chờ khi chưa có máy.',
        ),
      );
    }
    debugPrint('Cup label: bỏ qua — không có máy tem kết nối');
    return false;
  }
  final timeFmt = DateFormat('dd/MM/yyyy');
  final hourFmt = DateFormat('HH:mm');
  final when = printedAt ?? DateTime.now();
  final storeNameForCup = (await PosSellStoreSettings.load()).storeName;

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
      // Khổ vật lý = máy tem (TSPL SIZE/GAP). Layout mẫu scale vào canvas máy — tránh trôi.
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

    // 3) Máy nhiệt nội bộ có role KitchenLabel — không dùng máy phiếu chế biến.
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
          storeName: storeNameForCup,
  );

  await PosPrintOrchestrator.instance.refreshConfig();
  final cloudPrinter = _resolveCupLabelCloudPrinter();
  if (cloudPrinter != null && outputs.isNotEmpty) {
    try {
      // Máy tem (TSPL/Xprinter): phải gửi bitmap TSPL — EscPos ghi USB «OK»
      // nhưng Tem 350BM không in gì.
      if (cloudPrinter.isLabelPrinter) {
        final labelSettings = toLabelSettings(cloudPrinter);
        // Khổ vật lý theo máy tem — không dùng mm mẫu thiết kế (tránh trôi/cắt).
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
          'Cup label: bỏ Agent ${cloudPrinter.name} — máy phiếu chế biến',
        );
      }
    } catch (e) {
      debugPrint('Cloud cup label (V2) failed: $e');
    }
  }

  // Không fallback EscPos «Ban: …» lên máy phiếu chế biến / máy bất kỳ.
  debugPrint(
    'Cup label: không in — cần máy tem (KitchenLabel), không đẩy Agent lên máy bếp',
  );
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

/// Máy tem thật (TSPL) đang kết nối — không gửi phiếu cloud khi Agent offline.
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
    // Khối「Tên hàng」là lineItems — phải có 1 dòng, nếu không in thật trống dù preview có sample.
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
