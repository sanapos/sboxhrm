import 'pos_sell_store_settings.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/pos_label_design.dart';
import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import '../models/pos_store_printer.dart';
import '../widgets/notification_overlay.dart';
import 'pos_label_design_painter.dart';
import 'pos_label_design_store.dart';
import 'pos_label_printer_service.dart';
import 'pos_label_printer_settings.dart';
import 'pos_label_renderer.dart';
import 'pos_local_printers_store.dart';
import 'pos_print_device_scope.dart';
import 'pos_print_orchestrator.dart';
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
    this.unitLabel,
    this.price,
  });

  final String productName;
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

  // Mẫu tem ly (trình soạn tem) + dữ liệu từng tem — vẽ cùng bộ vẽ với màn soạn.
  final design = await _loadKitchenDesign();
  final datas = _cupDataList(
    tickets: tickets,
    timeFmt: timeFmt,
    hourFmt: hourFmt,
    when: when,
    storeName: storeNameForCup,
  );

  /// Raster một tem theo mẫu; null = tem trống (bỏ qua tem này).
  Future<({Uint8List raster, int widthPx, int heightPx})?> renderOne(
    Map<String, String> data,
    PosLabelPrinterSettings settings,
  ) async {
    final r = await PosLabelDesignPainter.renderRowRaster(
      design.copyWith(columns: 1),
      [data],
      dpi: settings.dpi,
      shiftRightMm: settings.shiftRightMm,
    );
    return PosLabelRenderer.hasEnoughInk(r.raster) ? r : null;
  }

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
      var anyInk = false;
      // Khổ in = khổ mẫu tem ly (soạn đúng cuộn tem đang dùng).
      // Máy đầu lỗi giữa chừng → máy sau in tiếp từ tem chưa ra (không in lại tem đã ra).
      final widthMm = design.widthMm;
      final heightMm = design.heightMm;
      for (final p in labelTargets) {
        if (done >= total) break;
        final settings = p.toLabelSettings().copyWith(enabled: true);
        final rest = datas.sublist(done);
        for (var i = 0; i < rest.length; i++) {
          final r = await renderOne(rest[i], settings);
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
            p.hasRole(PosLocalPrinterRoles.kitchenLabel) &&
            !p.hasRole(PosLocalPrinterRoles.kitchenSlip) &&
            !p.hasRole(PosLocalPrinterRoles.kitchenVoid))
        .toList();
    if (thermalCup.isNotEmpty && done < total) {
      for (final p in thermalCup) {
        final prepared =
            await PosPrinterTransport.prepareLocalSettings(p.toThermalSettings());
        final cupSettings = prepared.copyWith(
          feedBeforeCut: 8,
          openCashDrawer: false,
        );
        // Ảnh tem (ESC/POS, cả Sunmi) thu vừa khổ giấy. Gửi gộp một lệnh (tất cả hoặc không).
        final ok = await PosPrintOrchestrator.instance.dispatchLocalEscPos(
          bytes: await _cupReceiptBytes(design, datas.sublist(done), cupSettings.paperWidthMm),
          showFeedback: false,
          successTitle: 'Tem ly',
          settingsOverride: cupSettings,
          documentType: PosPrintDocumentTypes.kitchenLabel,
          skipDedup: true,
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
  final rest = datas.sublist(done);

  await PosPrintOrchestrator.instance.refreshConfig();
  var cloudPrinter = await _resolveCupLabelCloudPrinter();
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
  if (cloudPrinter != null && rest.isNotEmpty) {
    try {
      // Máy tem (TSPL/Xprinter): phải gửi bitmap TSPL — EscPos ghi USB «OK»
      // nhưng Tem 350BM không in gì.
      if (cloudPrinter.isLabelPrinter) {
        final labelSettings = toLabelSettings(cloudPrinter);
        // Khổ in = khổ mẫu tem ly.
        final widthMm = design.widthMm;
        final heightMm = design.heightMm;
        for (var i = 0; i < rest.length; i++) {
          final r = await renderOne(rest[i], labelSettings);
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
      } else if (!_isKitchenReceiptPrinter(cloudPrinter)) {
        final cupSettings = toThermalSettings(cloudPrinter).copyWith(
          feedBeforeCut: 8,
          openCashDrawer: false,
        );
        final merged = await _cupReceiptBytes(design, rest, cupSettings.paperWidthMm);
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
      debugPrint('Cloud cup label failed: $e');
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
  final design = await _loadKitchenDesign();
  final storeName = (await PosSellStoreSettings.load()).storeName;
  final datas = _cupDataList(
    tickets: tickets,
    timeFmt: DateFormat('dd/MM/yyyy'),
    hourFmt: DateFormat('HH:mm'),
    when: DateTime.now(),
    storeName: storeName,
  );
  if (!isLabelPrinter) {
    final cupSettings = thermalSettings.copyWith(feedBeforeCut: 8, openCashDrawer: false);
    return PosPrintOrchestrator.instance.dispatchLocalEscPos(
      bytes: await _cupReceiptBytes(design, datas, cupSettings.paperWidthMm),
      showFeedback: false,
      successTitle: 'Tem ly',
      settingsOverride: cupSettings,
      documentType: PosPrintDocumentTypes.kitchenLabel,
      skipDedup: true,
    );
  }
  final settings = labelSettings.copyWith(enabled: true);
  final rasters = <({Uint8List raster, int widthPx, int heightPx})>[];
  for (final data in datas) {
    final r = await PosLabelDesignPainter.renderRowRaster(
      design.copyWith(columns: 1),
      [data],
      dpi: settings.dpi,
      shiftRightMm: settings.shiftRightMm,
    );
    if (PosLabelRenderer.hasEnoughInk(r.raster)) rasters.add(r);
  }
  if (rasters.isEmpty) return false;
  return PosLabelPrinterService.printCupRasters(
    rasters,
    settings: settings,
    widthMm: design.widthMm,
    heightMm: design.heightMm,
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

/// Dữ liệu từng tem ly cho mẫu (trường giống màn soạn tem: Ten_Ban, So_Luong, Ghi_Chu…).
List<Map<String, String>> _cupDataList({
  required List<CupLabelTicket> tickets,
  required DateFormat timeFmt,
  required DateFormat hourFmt,
  required DateTime when,
  String? storeName,
}) {
  final out = <Map<String, String>>[];
  for (final t in tickets) {
    final noteParts = <String>[];
    final tops = (t.toppings ?? '').trim();
    if (tops.isNotEmpty) noteParts.add(posToppingLabelText(tops));
    final note = (t.note ?? '').trim();
    if (note.isNotEmpty) noteParts.add(note);
    out.add({
      'Ten_Cua_Hang': (storeName ?? '').trim(),
      'Ten_Ban': (t.tableLabel ?? '').trim(),
      'Ma_Don_Hang': (t.orderNo ?? '').trim(),
      'Ngay': timeFmt.format(when),
      'Gio': hourFmt.format(when),
      'Ten_Hang_Hoa': t.productName.trim().isEmpty ? 'Món' : t.productName.trim(),
      'Ghi_Chu': noteParts.join('\n'),
      'So_Luong': (t.qtyLabel ?? '1').trim().isEmpty ? '1' : (t.qtyLabel ?? '1').trim(),
      'Don_Vi_Tinh': (t.unitLabel ?? '').trim(),
      'Ma_Hang': '',
      'Ma_Vach': '',
      'Don_Gia': (t.price ?? 0) > 0 ? NumberFormat('#,##0', 'vi_VN').format(t.price) : '',
      'Tieu_De_In': 'TEM LY',
    });
  }
  return out;
}

/// Tem ly in trên máy hóa đơn (K58 / K80, Sunmi): ảnh tem theo mẫu, thu nhỏ vừa khổ in (384 / 576 điểm).
Future<List<int>> _cupReceiptBytes(PosLabelDesign design, List<Map<String, String>> datas, int paperWidthMm) async {
  final maxDots = paperWidthMm <= 58 ? 384 : 576;
  final dpi = math.min(203, (maxDots / design.widthMm * 25.4).floor());
  final out = <int>[];
  for (final data in datas) {
    final r = await PosLabelDesignPainter.renderRowRaster(design.copyWith(columns: 1), [data], dpi: dpi);
    if (PosLabelRenderer.hasEnoughInk(r.raster)) out.addAll(PosLabelPrinterService.escPosRasterBytes(r));
  }
  return out;
}

Future<PosLabelDesign> _loadKitchenDesign() => loadPosLabelDesignForPrint(PosPrintDocumentTypes.kitchenLabel);
