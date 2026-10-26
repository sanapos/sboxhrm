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
import 'pos_label_printer_settings.dart';
import 'pos_label_renderer.dart';
import 'pos_local_printers_store.dart';
import '../services/pos_product_printer_service.dart';
import 'pos_device_product_printers.dart';
import 'pos_print_device_scope.dart';
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
    this.productId,
    this.toppings,
    this.note,
    this.qtyLabel,
    this.tableLabel,
    this.orderNo,
    this.unitLabel,
    this.price,
  });

  final String productName;
  /// Món của tem — để in ra máy tem đã gán món (lane tem). null = máy tem mặc định.
  final String? productId;
  final String? toppings;
  final String? note;
  final String? qtyLabel;
  final String? tableLabel;
  final String? orderNo;
  /// Size / đơn vị (M, L, Ly…) — trường «Đơn vị tính» của mẫu tem.
  final String? unitLabel;
  /// Giá 1 ly (gồm topping) — trường «Đơn giá» của mẫu tem.
  final double? price;
}

bool _isKitchenReceiptPrinter(PosStorePrinter p) {
  bool has(String t) =>
      p.documentTypes.any((x) => x.toLowerCase() == t.toLowerCase());
  return has(PosCloudDocumentTypes.kitchenSlip) ||
      has(PosCloudDocumentTypes.kitchenVoid) ||
      has(PosLocalPrinterRoles.kitchenSlip) ||
      has(PosLocalPrinterRoles.kitchenVoid);
}

/// Máy tem Agent (chip cloud). Không dùng IsDeviceLocal của máy khác —
/// A7 gửi ID nội bộ A6 thì Agent không claim (chip là bản twin).
Future<PosStorePrinter?> _agentFacingLabelPrinter(PosStorePrinter p) async {
  if (!p.isActive) return null;
  if (_isKitchenReceiptPrinter(p)) return null;
  final facing = await PosPrintDeviceScope.agentFacingPrinter(p.id);
  if (facing == null || !facing.isActive) return null;
  if (!facing.isLabelPrinter) return null;
  if (_isKitchenReceiptPrinter(facing)) return null;
  return facing;
}

/// Máy tem nội bộ trên máy này, hoặc máy tem Agent (A6) để A7/web in hộ.
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
  return await _resolveCupLabelCloudPrinter() != null;
}

/// In tem trà sữa / dán ly. True khi mọi tem đã gửi máy.
///
/// Ưu tiên **máy in tem** (KitchenLabel / mọi máy kind=label),
/// không đẩy sang máy hóa đơn Sunmi trừ khi không có máy tem.
Future<bool> printCupLabels({
  required List<CupLabelTicket> tickets,
  DateTime? printedAt,
  bool showFeedback = false,
  PosPrintTemplateV2? templateOverride,
}) async =>
    (await printCupLabelsRemaining(
      tickets: tickets,
      printedAt: printedAt,
      showFeedback: showFeedback,
      templateOverride: templateOverride,
    ))
        .isEmpty;

/// Lệnh tem ly gửi Agent đã nhận nhưng không ra giấy: [tickets] = đúng các tem của lệnh [jobId].
typedef CupLabelCloudHangCallback = void Function(
  List<CupLabelTicket> tickets, {
  required String jobId,
  required String printerName,
});

/// Như [printCupLabels] nhưng trả các tem CHƯA in được (theo thứ tự). Máy tem lỗi giữa chừng (vd hết giấy ở
/// tem thứ 3/5) → chỉ 2 tem cuối cần in lại; trước đây phiếu chờ in lại cả 5 → ra tem trùng.
///
/// [onCloudHang]: tem gửi qua Agent (coi là đã gửi) mà sau đó treo — trước đây chỉ hiện thông báo rồi mất tem,
/// giờ nơi gọi đưa vào «Phiếu chưa in» kèm mã lệnh để in lại / hủy đúng lệnh đó.
Future<List<CupLabelTicket>> printCupLabelsRemaining({
  required List<CupLabelTicket> tickets,
  DateTime? printedAt,
  bool showFeedback = false,
  PosPrintTemplateV2? templateOverride,
  CupLabelCloudHangCallback? onCloudHang,
}) async {
  if (tickets.isEmpty) return const [];
  Future<List<CupLabelTicket>> run(List<CupLabelTicket> part, String? target) =>
      _printCupLabelsOn(
        targetPrinterId: target,
        tickets: part,
        printedAt: printedAt,
        showFeedback: showFeedback,
        templateOverride: templateOverride,
      );
  // Món gán máy tem (lane tem) → in đúng máy đó; món chưa gán → máy tem mặc định như trước.
  // Trước: mọi tem dồn 1 máy tem, màn «Gán món in tem» không có tác dụng khi in.
  final routes = await _cupLabelRoutes(tickets);
  if (routes.every((r) => r == null)) return run(tickets, null);
  final groups = <String?, List<CupLabelTicket>>{};
  for (var i = 0; i < tickets.length; i++) {
    groups.putIfAbsent(routes[i], () => []).add(tickets[i]);
  }
  final left = Set<CupLabelTicket>.identity();
  for (final e in groups.entries) {
    left.addAll(await run(e.value, e.key));
  }
  return [for (final t in tickets) if (left.contains(t)) t];
}

/// Máy tem gán cho từng tem: gán trên thiết bị này trước, rồi gán cửa hàng (SP → nhóm).
/// Máy đã xóa / tắt coi như chưa gán.
Future<List<String?>> _cupLabelRoutes(List<CupLabelTicket> tickets) async {
  if (tickets.every((t) => (t.productId ?? '').trim().isEmpty)) {
    return List<String?>.filled(tickets.length, null);
  }
  final svc = PosProductPrinterService.instance;
  try {
    await PosPrintOrchestrator.instance.refreshConfig();
    await svc.preload();
  } catch (e) {
    debugPrint('Cup label: không tải gán máy tem — $e');
  }
  String? live(String? id) {
    final v = (id ?? '').trim();
    if (v.isEmpty) return null;
    final p = PosPrintOrchestrator.instance.printerByIdExact(v);
    return p != null && p.isActive ? v : null;
  }
  final byProduct = <String, String?>{};
  final out = <String?>[];
  for (final t in tickets) {
    final pid = (t.productId ?? '').trim();
    if (pid.isEmpty) {
      out.add(null);
      continue;
    }
    if (!byProduct.containsKey(pid)) {
      final device = kIsWeb
          ? null
          : live(await PosDeviceProductPrinters.instance
              .printerIdForProduct(pid, label: true));
      byProduct[pid] = device ?? live(await svc.resolveLabelPrinterId(pid));
    }
    out.add(byProduct[pid]);
  }
  return out;
}

bool _sameId(String? a, String b) =>
    (a ?? '').trim().toLowerCase() == b.trim().toLowerCase();

/// [targetPrinterId]: in lên đúng máy đã gán (nội bộ nếu có cổng trên máy này, không thì Agent);
/// null = chọn máy tem mặc định như trước.
Future<List<CupLabelTicket>> _printCupLabelsOn({
  String? targetPrinterId,
  required List<CupLabelTicket> tickets,
  DateTime? printedAt,
  bool showFeedback = false,
  PosPrintTemplateV2? templateOverride,
}) async {
  if (tickets.isEmpty) return const [];
  if (targetPrinterId == null && !await hasReadyCupLabelPrinter()) {
    if (showFeedback) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa có máy in tem',
        message: tr(
          'Kết nối máy tem trong cửa hàng rồi in. Không tạo phiếu chờ khi chưa có máy.',
        ),
      );
    }
    debugPrint('Cup label: bỏ qua — không có máy tem kết nối');
    return tickets;
  }
  final timeFmt = DateFormat('dd/MM/yyyy');
  final hourFmt = DateFormat('HH:mm');
  final when = printedAt ?? DateTime.now();
  final storeNameForCup = (await PosSellStoreSettings.load()).storeName;
  final total = tickets.length;
  // Số tem (tính từ đầu danh sách) đã gửi máy thành công hoặc bỏ qua vì trống.
  var done = 0;

  void feedbackOk(String message) {
    if (showFeedback) {
      NotificationOverlayManager().showSuccess(title: 'Tem ly', message: tr(message));
    }
  }

  /// Raster một tem cho khổ máy; null = mẫu và dự phòng đều trống (bỏ qua tem này).
  Future<({Uint8List raster, int widthPx, int heightPx})?> renderOne(
    CupLabelTicket t,
    PosPrintCompiledOutput output,
    PosLabelPrinterSettings settings,
    double widthMm,
    double heightMm,
  ) async {
    final r = await PosLabelRenderer.renderCompiledLabel(
      output: output,
      widthMm: widthMm,
      heightMm: heightMm,
      dpi: settings.dpi,
      marginLeftMm: settings.marginLeftMm,
      marginRightMm: settings.marginRightMm,
      marginTopMm: settings.marginTopMm,
      marginBottomMm: settings.marginBottomMm,
      fontScale: settings.fontScale,
    );
    if (PosLabelRenderer.hasEnoughInk(r.raster)) return r;
    // Fallback raster cứng nếu mẫu trống.
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
    return PosLabelRenderer.hasEnoughInk(fallback.raster) ? fallback : null;
  }

  if (!kIsWeb) {
    final all = await PosLocalPrintersStore.instance.loadAll();
    // 1) Máy tem nội bộ đã cài (USB/BT/Sunmi/LAN) + role KitchenLabel.
    // Không có local — chỉ lanHost Agent → cloud phía dưới.
    var labelTargets = all
        .where((p) =>
            PosLocalPrintersStore.profileAllowsDirectLocal(p) &&
            p.isLabel &&
            (targetPrinterId != null
                ? _sameId(p.storePrinterId, targetPrinterId)
                : p.hasRole(PosLocalPrinterRoles.kitchenLabel)))
        .toList();
    // 2) Mọi máy tem nội bộ đang bật (kể cả chỉ BarcodeLabel)
    if (labelTargets.isEmpty && targetPrinterId == null) {
      labelTargets = all
          .where((p) =>
              PosLocalPrintersStore.profileAllowsDirectLocal(p) && p.isLabel)
          .toList();
    }

    if (labelTargets.length > 1) {
      final want =
          ((await _resolveCupLabelCloudPrinter())?.id ?? '').trim().toLowerCase();
      if (want.isNotEmpty) {
        labelTargets.sort((a, b) {
          final aHit =
              (a.storePrinterId ?? '').trim().toLowerCase() == want;
          final bHit =
              (b.storePrinterId ?? '').trim().toLowerCase() == want;
          if (aHit != bHit) return aHit ? -1 : 1;
          return 0;
        });
      }
    }

    if (labelTargets.isNotEmpty) {
      final v2 = templateOverride ?? await _loadKitchenLabelTemplate();
      var anyInk = false;
      // Khổ vật lý = máy tem (TSPL SIZE/GAP). Layout mẫu scale vào canvas máy — tránh trôi.
      // Máy đầu lỗi giữa chừng → máy sau in tiếp từ tem chưa ra (không in lại tem đã ra).
      for (final p in labelTargets) {
        if (done >= total) break;
        final settings = p.toLabelSettings().copyWith(enabled: true);
        final machineTpl = settings.template ??
            posBarcodeLabelTemplateById('roll_1_50x30')!;
        final widthMm = machineTpl.labelWidthMm;
        final heightMm = machineTpl.labelHeightMm;
        final rest = tickets.sublist(done);
        final outputs = _compileCupOutputs(
          tickets: rest,
          v2: v2.copyWith(paperSize: machineTpl.id),
          timeFmt: timeFmt,
          hourFmt: hourFmt,
          when: when,
          storeName: storeNameForCup,
        );
        for (var i = 0; i < outputs.length; i++) {
          final r = await renderOne(rest[i], outputs[i], settings, widthMm, heightMm);
          if (r == null) {
            done++;
            continue;
          }
          anyInk = true;
          final ok = await PosLabelPrinterService.printCupRasters(
            [r],
            settings: settings,
            widthMm: widthMm,
            heightMm: heightMm,
          );
          if (!ok) break;
          done++;
        }
      }
      if (!anyInk && done >= total) {
        if (showFeedback) {
          NotificationOverlayManager().showError(
            title: 'Tem ly trống',
            message: tr('Không render được chữ tem. Thử lại hoặc kiểm tra font.'),
          );
        }
        return const [];
      }
      if (done >= total) {
        feedbackOk('Đã in lên máy tem');
        return const [];
      }
    }

    // 3) Máy nhiệt nội bộ có role KitchenLabel — không dùng máy phiếu chế biến.
    final thermalCup = all
        .where((p) =>
            PosLocalPrintersStore.profileAllowsDirectLocal(p) &&
            !p.isLabel &&
            (targetPrinterId != null
                // Món gán máy này (lane tem) → in đúng máy đó dù máy cũng in phiếu bếp.
                ? _sameId(p.storePrinterId, targetPrinterId)
                : p.hasRole(PosLocalPrinterRoles.kitchenLabel) &&
                    !p.hasRole(PosLocalPrinterRoles.kitchenSlip) &&
                    !p.hasRole(PosLocalPrinterRoles.kitchenVoid)))
        .toList();
    if (thermalCup.isNotEmpty && done < total) {
      final v2 = templateOverride ?? await _loadKitchenLabelTemplate();
      final outputs = _compileCupOutputs(
        tickets: tickets.sublist(done),
        v2: v2,
        timeFmt: timeFmt,
        hourFmt: hourFmt,
        when: when,
        storeName: storeNameForCup,
      );
      for (final p in thermalCup) {
        final prepared =
            await PosPrinterTransport.prepareLocalSettings(p.toThermalSettings());
        final cupSettings = prepared.copyWith(
          feedBeforeCut: 8,
          openCashDrawer: false,
        );
        // Không ép Sunmi khi connection không phải sunmi. Gửi gộp một lệnh (tất cả hoặc không).
        final ok = await _printCupOutputsLocal(
          outputs: outputs,
          cupSettings: cupSettings,
          showFeedback: false,
        );
        if (ok) {
          done = total;
          break;
        }
      }
      if (done >= total) {
        feedbackOk('Đã in tem ly');
        return const [];
      }
    }
  }

  // Cloud → Print Agent (các tem còn lại).
  final rest = tickets.sublist(done);
  final v2 = templateOverride ?? await _loadKitchenLabelTemplate();
  final outputs = _compileCupOutputs(
    tickets: rest,
    v2: v2,
    timeFmt: timeFmt,
    hourFmt: hourFmt,
    when: when,
    storeName: storeNameForCup,
  );

  await PosPrintOrchestrator.instance.refreshConfig();
  var cloudPrinter = targetPrinterId != null
      ? await PosPrintDeviceScope.agentFacingPrinter(targetPrinterId)
      : await _resolveCupLabelCloudPrinter();
  if (cloudPrinter != null &&
      PosPrintOrchestrator.instance.isServedBySelfAgent(cloudPrinter)) {
    // Agent chính máy này không nhận lệnh do mình gửi → tem treo; báo lỗi để thu ngân in lại.
    debugPrint('Cup label: bỏ cloud ${cloudPrinter.name} — Agent là chính máy này');
    cloudPrinter = null;
  }
  PosPrintHangCallback? hangFor(List<CupLabelTicket> part) => onCloudHang == null
      ? null
      : ({
          required String jobId,
          required String documentType,
          required String printerId,
          required String printerName,
          String? referenceNo,
        }) =>
          onCloudHang(List.of(part), jobId: jobId, printerName: printerName);
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
        for (var i = 0; i < outputs.length; i++) {
          final r = await renderOne(rest[i], outputs[i], labelSettings, widthMm, heightMm);
          if (r == null) {
            done++;
            continue;
          }
          final job = PosLabelPrinterService.buildCupRasterByteJobs(
            [r],
            settings: labelSettings,
            widthMm: widthMm,
            heightMm: heightMm,
          ).first;
          final ok = await PosPrintOrchestrator.instance.dispatchEscPos(
            documentType: PosCloudDocumentTypes.kitchenLabel,
            bytes: job,
            printerId: cloudPrinter.id,
            showFeedback: showFeedback && done == total - 1,
            successTitle: 'Tem ly',
            skipDedup: true,
            // Không treo UI 90s chờ Completed — Agent Claimed = đang in tem.
            waitForCompletion: false,
            acceptClaimedAsSuccess: true,
            hangAfter: const Duration(seconds: 90),
            referenceNo: tickets[done].orderNo,
            onHang: hangFor([tickets[done]]),
          );
          if (!ok) break;
          done++;
        }
        if (done >= total) return const [];
      } else if (targetPrinterId != null ||
          !_isKitchenReceiptPrinter(cloudPrinter)) {
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
          referenceNo: tickets[done].orderNo,
          onHang: hangFor(tickets.sublist(done)),
        );
        if (ok) return const [];
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
  debugPrint('Cup label: còn ${total - done}/$total tem chưa in');
  if (showFeedback) {
    NotificationOverlayManager().showError(
      title: done > 0 ? 'Mới in $done/$total tem ly' : 'Chưa in tem ly',
      message: tr(
        'Không gửi được tới máy tem. Kiểm tra máy tem trong Máy in nội bộ, hoặc bật in qua Agent trên máy có cắm máy tem.',
      ),
    );
  }
  return tickets.sublist(done);
}

/// Tem ly từ lệnh in máy chủ (đơn QR / online — Agent): in thẳng lên đúng máy cửa hàng đã chọn cho
/// «Tem báo bếp», máy tem (TSPL / ZPL / ESC raster) hoặc máy nhiệt có vai trò tem.
Future<bool> printCupTicketsOnStorePrinter({
  required List<CupLabelTicket> tickets,
  required bool isLabelPrinter,
  required PosLabelPrinterSettings labelSettings,
  required PosThermalPrinterSettings thermalSettings,
}) async {
  if (tickets.isEmpty) return true;
  final v2 = await _loadKitchenLabelTemplate();
  final storeName = (await PosSellStoreSettings.load()).storeName;
  final when = DateTime.now();
  if (!isLabelPrinter) {
    final outputs = _compileCupOutputs(
      tickets: tickets,
      v2: v2,
      timeFmt: DateFormat('dd/MM/yyyy'),
      hourFmt: DateFormat('HH:mm'),
      when: when,
      storeName: storeName,
    );
    return _printCupOutputsLocal(
      outputs: outputs,
      cupSettings: thermalSettings.copyWith(feedBeforeCut: 8, openCashDrawer: false),
      showFeedback: false,
    );
  }
  final settings = labelSettings.copyWith(enabled: true);
  final machineTpl = settings.template ?? posBarcodeLabelTemplateById('roll_1_50x30')!;
  final outputs = _compileCupOutputs(
    tickets: tickets,
    v2: v2.copyWith(paperSize: machineTpl.id),
    timeFmt: DateFormat('dd/MM/yyyy'),
    hourFmt: DateFormat('HH:mm'),
    when: when,
    storeName: storeName,
  );
  final rasters = <({Uint8List raster, int widthPx, int heightPx})>[];
  for (var i = 0; i < outputs.length; i++) {
    final r = await PosLabelRenderer.renderCompiledLabel(
      output: outputs[i],
      widthMm: machineTpl.labelWidthMm,
      heightMm: machineTpl.labelHeightMm,
      dpi: settings.dpi,
      marginLeftMm: settings.marginLeftMm,
      marginRightMm: settings.marginRightMm,
      marginTopMm: settings.marginTopMm,
      marginBottomMm: settings.marginBottomMm,
      fontScale: settings.fontScale,
    );
    if (PosLabelRenderer.hasEnoughInk(r.raster)) {
      rasters.add(r);
      continue;
    }
    final t = tickets[i];
    final fb = await PosLabelRenderer.renderCupTicket(
      productName: t.productName,
      tableLabel: t.tableLabel,
      orderNo: t.orderNo,
      toppings: t.toppings,
      note: t.note,
      qtyLabel: t.qtyLabel,
      widthMm: machineTpl.labelWidthMm,
      heightMm: machineTpl.labelHeightMm,
      dpi: settings.dpi,
    );
    if (PosLabelRenderer.hasEnoughInk(fb.raster)) rasters.add(fb);
  }
  if (rasters.isEmpty) return false;
  return PosLabelPrinterService.printCupRasters(
    rasters,
    settings: settings,
    widthMm: machineTpl.labelWidthMm,
    heightMm: machineTpl.labelHeightMm,
  );
}

/// Máy tem Agent (chip cloud). A7 không cài tem — không lấy IsDeviceLocal A6.
Future<PosStorePrinter?> _resolveCupLabelCloudPrinter() async {
  final orch = PosPrintOrchestrator.instance;

  Future<PosStorePrinter?> pick(Iterable<PosStorePrinter> list) async {
    PosStorePrinter? firstReady;
    final sorted = [...list]
      ..sort((a, b) {
        if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
        final ac = a.isDeviceLocal ? 1 : 0;
        final bc = b.isDeviceLocal ? 1 : 0;
        if (ac != bc) return ac.compareTo(bc);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    for (final p in sorted) {
      final facing = await _agentFacingLabelPrinter(p);
      if (facing == null) continue;
      if (facing.isDefault) return facing;
      firstReady ??= facing;
    }
    return firstReady;
  }

  for (final doc in [
    PosCloudDocumentTypes.kitchenLabel,
    PosCloudDocumentTypes.barcodeLabel,
  ]) {
    final hit = await pick(orch.resolvePrinters(doc));
    if (hit != null) {
      debugPrint(
        'Cup label: Agent ${hit.name} (${hit.id}) doc=$doc',
      );
      return hit;
    }
  }
  final fallback = await pick(orch.printers);
  if (fallback != null) {
    debugPrint(
      'Cup label: Agent fallback ${fallback.name} (${fallback.id})',
    );
  }
  return fallback;
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
      'Don_Vi_Tinh': (t.unitLabel ?? '').trim(),
      'Ma_Hang': '',
      'Ma_Vach': '',
      'Don_Gia': (t.price ?? 0) > 0 ? NumberFormat('#,##0', 'vi_VN').format(t.price) : '',
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
