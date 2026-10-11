import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_tr.dart';
import '../models/pos_sale_order.dart';
import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import 'pos_label_printer_service.dart';
import 'pos_label_printer_settings.dart';
import 'pos_label_renderer.dart';
import 'pos_local_printers_store.dart';
import 'pos_print_device_scope.dart';
import 'pos_print_orchestrator.dart';
import 'pos_sell_store_settings.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_thermal_printer_settings.dart';

/// Thiết lập in tem vận đơn trên máy này.
class PosShippingLabelSettings {
  const PosShippingLabelSettings({this.autoPrint = false, this.size = '100x150'});

  /// Tạo vận đơn xong (bấm tay hoặc đơn online tự tạo) → tự in tem.
  final bool autoPrint;

  /// «100x150» (mặc định), «80x80» (GHN có khổ riêng), «browser» = chỉ mở link in của hãng như trước.
  final String size;

  static const sizes = <String, String>{
    '100x150': 'Tem 100×150 (máy tem vận đơn)',
    '80x80': 'Tem 80×80',
    'browser': 'Không in thẳng — mở link in của hãng',
  };

  bool get directPrint => size != 'browser';
  double get widthMm => size == '80x80' ? 80 : 100;
  double get heightMm => size == '80x80' ? 80 : 150;

  /// Khổ xin hãng (GHN có 80×80; còn lại hãng tự chọn, máy thu phóng vừa tem).
  String? get carrierSize => size == '80x80' ? '80x80' : null;

  static const _kAuto = 'pos_ship_label_auto';
  static const _kSize = 'pos_ship_label_size';
  static const _kPrinted = 'pos_ship_label_printed';

  static Future<PosShippingLabelSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final size = prefs.getString(_kSize) ?? '100x150';
    return PosShippingLabelSettings(
      autoPrint: prefs.getBool(_kAuto) ?? false,
      size: sizes.containsKey(size) ? size : '100x150',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAuto, autoPrint);
    await prefs.setString(_kSize, size);
  }

  PosShippingLabelSettings copyWith({bool? autoPrint, String? size}) =>
      PosShippingLabelSettings(autoPrint: autoPrint ?? this.autoPrint, size: size ?? this.size);

  /// Đơn đã tự in tem trên máy này (tránh in lại khi danh sách đơn online làm mới).
  static Future<bool> wasAutoPrinted(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_kPrinted) ?? const []).contains(orderId);
  }

  static Future<void> markAutoPrinted(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [...(prefs.getStringList(_kPrinted) ?? const <String>[])];
    if (list.contains(orderId)) return;
    list.add(orderId);
    if (list.length > 300) list.removeRange(0, list.length - 300);
    await prefs.setStringList(_kPrinted, list);
  }
}

enum ShippingLabelPrintResult { printed, openedLink, previewed, failed }

typedef _Raster = ({Uint8List raster, int widthPx, int heightPx});

/// Máy tem nhận tem vận đơn: nội bộ (USB / BT / LAN) hoặc máy tem Agent.
class _Target {
  _Target.local(this.settings, this.name) : cloud = null;
  _Target.cloud(PosStorePrinter p)
      : cloud = p,
        settings = toLabelSettings(p),
        name = p.name;

  final PosLabelPrinterSettings settings;
  final PosStorePrinter? cloud;
  final String name;
}

/// In tem vận đơn thẳng ra máy tem: nhãn của hãng (PDF / trang in HTML) hoặc tem tự vẽ
/// (đơn tự giao, hãng không trả nhãn như Ahamove).
class PosShippingLabelPrinter {
  PosShippingLabelPrinter._();

  static final _api = ApiService();

  static bool _isLargeLabel(PosLabelPrinterSettings s) => (s.template?.labelWidthMm ?? 0) >= 70;

  static Future<_Target?> _resolveTarget() async {
    if (!kIsWeb) {
      final all = await PosLocalPrintersStore.instance.loadAll();
      final labels = all.where((p) => PosLocalPrintersStore.profileAllowsDirectLocal(p) && p.isLabel).toList();
      final hit = labels.where((p) => p.hasRole(PosLocalPrinterRoles.shippingLabel)).firstOrNull ??
          labels.where((p) => _isLargeLabel(p.toLabelSettings())).firstOrNull;
      if (hit != null) {
        final s = hit.toLabelSettings().copyWith(enabled: true);
        if (s.connectionType != PosThermalConnectionType.sunmi) return _Target.local(s, hit.name);
      }
    }
    try {
      final orch = PosPrintOrchestrator.instance;
      await orch.refreshConfig();
      final candidates = [
        ...orch.resolvePrinters(PosCloudDocumentTypes.shippingLabel),
        ...orch.printers.where((p) => p.isLabelPrinter && _isLargeLabel(toLabelSettings(p))),
      ];
      for (final p in candidates) {
        if (!p.isActive || !p.isLabelPrinter) continue;
        final facing = await PosPrintDeviceScope.agentFacingPrinter(p.id);
        if (facing != null && facing.isActive && facing.isLabelPrinter) return _Target.cloud(facing);
      }
    } catch (e) {
      debugPrint('Shipping label: resolve cloud printer $e');
    }
    return null;
  }

  static Future<bool> hasPrinter() async => await _resolveTarget() != null;

  static Future<PosSaleOrder?> _loadOrder(String orderId) async {
    final res = await _api.getPosSale(orderId);
    if (res['isSuccess'] == true && res['data'] is Map) {
      return PosSaleOrder.fromJson(Map<String, dynamic>.from(res['data'] as Map));
    }
    return null;
  }

  static const _carrierNames = <String, String>{
    'ghn': 'GHN',
    'ghtk': 'GHTK',
    'viettelpost': 'Viettel Post',
    'spx': 'SPX Express',
    'ahamove': 'Ahamove',
    'internal': 'Giao nội bộ',
  };

  static String _carrierKey(PosSaleOrder o) =>
      (o.deliveryCarrierCode ?? o.deliveryPartner ?? '').trim().toLowerCase().replaceAll(' ', '');

  /// Hãng có nhãn riêng bắt buộc dùng (có mã phân loại của hãng) — lỗi lấy nhãn thì báo, không thay tem tự vẽ.
  static bool _carrierHasOwnLabel(String key) =>
      key.contains('ghn') || key.contains('ghtk') || key.contains('viettel') || key.contains('spx');

  /// Tem tự vẽ cho đơn.
  static Future<_Raster> _selfLabel(PosSaleOrder o, PosShippingLabelSettings s, int dpi) async {
    final store = await PosSellStoreSettings.load(peekServer: false);
    final key = _carrierKey(o);
    final address = [
      o.deliveryAddress,
      o.deliveryWard,
      o.deliveryDistrict,
      o.deliveryProvince,
    ].where((e) => (e ?? '').trim().isNotEmpty).map((e) => e!.trim()).join(', ');
    String qty(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
    return PosLabelRenderer.renderShippingSelfLabel(
      orderNo: o.orderNo,
      receiverName: o.customerName ?? '',
      receiverPhone: (o.deliveryPhone ?? '').trim().isNotEmpty ? o.deliveryPhone! : (o.customerPhone ?? ''),
      receiverAddress: address,
      codAmount: o.balanceDue > 0 ? o.balanceDue : 0,
      senderName: store.storeName,
      senderPhone: store.phone,
      carrierName: _carrierNames.entries.where((e) => key.contains(e.key)).map((e) => e.value).firstOrNull ??
          (o.deliveryPartner ?? '').trim(),
      trackingCode: o.deliveryTrackingCode,
      note: o.note,
      itemLines: [
        for (final l in o.lines)
          '${qty(l.qty)} × ${l.productName}${(l.unitName ?? '').trim().isEmpty ? '' : ' (${l.unitName})'}',
      ],
      itemCount: o.lines.length,
      date: o.saleDate ?? o.createdAt,
      widthMm: s.widthMm,
      heightMm: s.heightMm,
      dpi: dpi,
    );
  }

  /// Nhãn của hãng → raster. Trả (raster, link để mở trình duyệt khi không in thẳng được, lỗi).
  static Future<({_Raster? raster, String? url, String? error, bool selfLabel})> _carrierLabel(
    PosSaleOrder o,
    PosShippingLabelSettings s,
    int dpi,
  ) async {
    final res = await _api.getPosShipmentLabel(o.id, size: s.carrierSize);
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
    final ok = res['isSuccess'] == true && (data['success'] == true || data['Success'] == true);
    final url = (data['labelUrl'] ?? data['LabelUrl'] ?? '').toString();
    final format = (data['format'] ?? data['Format'] ?? '').toString().toLowerCase();
    final message = (data['message'] ?? data['Message'] ?? res['message'] ?? '').toString();
    if (!ok || url.isEmpty || format == 'link') {
      // Hãng không có nhãn (Ahamove…) → tem tự vẽ có mã vận đơn.
      if (!_carrierHasOwnLabel(_carrierKey(o))) return (raster: null, url: null, error: null, selfLabel: true);
      return (raster: null, url: url.isEmpty ? null : url, error: message.isEmpty ? 'Không lấy được nhãn' : message, selfLabel: false);
    }
    try {
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 40));
      if (resp.statusCode != 200) {
        return (raster: null, url: url, error: 'Hãng trả lỗi ${resp.statusCode}', selfLabel: false);
      }
      final bytes = resp.bodyBytes;
      Uint8List? pdf;
      if (bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
        pdf = bytes; // %PDF
      } else if (!kIsWeb) {
        // Trang in HTML (GHN / Viettel Post) → dựng PDF đúng khổ tem bằng WebView của máy.
        // ignore: deprecated_member_use — vẫn chạy trên Android / iOS; chưa có thay thế dựng HTML của hãng.
        pdf = await Printing.convertHtml(
          format: PdfPageFormat(s.widthMm * PdfPageFormat.mm, s.heightMm * PdfPageFormat.mm, marginAll: 0),
          html: resp.body,
          baseUrl: url,
        );
      }
      if (pdf == null) return (raster: null, url: url, error: 'Trình duyệt không dựng được trang in của hãng', selfLabel: false);
      ui.Image? page;
      await for (final r in Printing.raster(pdf, pages: const [0], dpi: 300)) {
        page = await r.toImage();
        break;
      }
      if (page == null) return (raster: null, url: url, error: 'Nhãn trống', selfLabel: false);
      final raster = await PosLabelRenderer.rasterFromImage(page, widthMm: s.widthMm, heightMm: s.heightMm, dpi: dpi);
      return (raster: raster, url: url, error: null, selfLabel: false);
    } catch (e) {
      // Web: trang của hãng chặn tải chéo (CORS) → mở link như trước.
      debugPrint('Shipping label: carrier content $e');
      return (raster: null, url: url, error: kIsWeb ? null : 'Không tải được nhãn: $e', selfLabel: false);
    }
  }

  static Future<bool> _send(_Target t, _Raster r, PosShippingLabelSettings s, {String? referenceNo}) async {
    final settings = t.settings;
    if (t.cloud == null) {
      return PosLabelPrinterService.printCupRasters([r], settings: settings, widthMm: s.widthMm, heightMm: s.heightMm);
    }
    final jobs = PosLabelPrinterService.buildCupRasterByteJobs(
      [r],
      settings: settings,
      widthMm: s.widthMm,
      heightMm: s.heightMm,
    );
    return PosPrintOrchestrator.instance.dispatchEscPos(
      documentType: PosCloudDocumentTypes.shippingLabel,
      bytes: jobs.first,
      printerId: t.cloud!.id,
      referenceNo: referenceNo,
      showFeedback: false,
      successTitle: 'Tem vận đơn',
      skipDedup: true,
      waitForCompletion: false,
      acceptClaimedAsSuccess: true,
    );
  }

  /// Raster 1-bit → PDF khổ tem (máy không có máy tem: in qua máy in thường / lưu file).
  static Future<Uint8List> _rasterPdf(_Raster r, PosShippingLabelSettings s) async {
    final rgba = Uint8List(r.widthPx * r.heightPx * 4);
    final bpr = (r.widthPx + 7) ~/ 8;
    for (var y = 0; y < r.heightPx; y++) {
      for (var x = 0; x < r.widthPx; x++) {
        final black = (r.raster[y * bpr + (x >> 3)] >> (7 - (x & 7))) & 1 == 1;
        final i = (y * r.widthPx + x) * 4;
        final v = black ? 0 : 255;
        rgba[i] = v;
        rgba[i + 1] = v;
        rgba[i + 2] = v;
        rgba[i + 3] = 255;
      }
    }
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(s.widthMm * PdfPageFormat.mm, s.heightMm * PdfPageFormat.mm, marginAll: 0),
      build: (_) => pw.Image(pw.RawImage(bytes: rgba, width: r.widthPx, height: r.heightPx), fit: pw.BoxFit.contain),
    ));
    return doc.save();
  }

  /// In tem vận đơn một đơn. [allowFallback]: không có máy tem → mở link hãng / xem PDF tem tự vẽ.
  static Future<ShippingLabelPrintResult> printForOrder(
    String orderId, {
    PosSaleOrder? order,
    bool showFeedback = true,
    bool allowFallback = true,
    PosShippingLabelSettings? settings,
  }) async {
    final s = settings ?? await PosShippingLabelSettings.load();
    final o = order ?? await _loadOrder(orderId);
    if (o == null) {
      if (showFeedback) NotificationOverlayManager().showError(title: 'In tem vận đơn', message: tr('Không tải được đơn'));
      return ShippingLabelPrintResult.failed;
    }
    final hasTracking = (o.deliveryTrackingCode ?? '').trim().isNotEmpty;
    final key = _carrierKey(o);

    // Chế độ cũ: chỉ mở link in của hãng.
    if (!s.directPrint && hasTracking && _carrierHasOwnLabel(key)) {
      return _openCarrierLink(o, s, showFeedback);
    }

    final target = s.directPrint ? await _resolveTarget() : null;
    final dpi = target?.settings.dpi ?? 203;
    _Raster? raster;
    String? fallbackUrl;
    if (!hasTracking || !_carrierHasOwnLabel(key)) {
      raster = await _selfLabel(o, s, dpi);
    } else {
      final c = await _carrierLabel(o, s, dpi);
      if (c.selfLabel) {
        raster = await _selfLabel(o, s, dpi);
      } else {
        raster = c.raster;
        fallbackUrl = c.url;
        if (raster == null && c.error != null && fallbackUrl == null) {
          if (showFeedback) NotificationOverlayManager().showError(title: 'Không lấy được nhãn', message: c.error!);
          return ShippingLabelPrintResult.failed;
        }
      }
    }

    if (raster != null && target != null) {
      final ok = await _send(target, raster, s, referenceNo: o.orderNo);
      if (showFeedback) {
        if (ok) {
          NotificationOverlayManager().showSuccess(
            title: 'Đã in tem vận đơn',
            message: tr('${o.orderNo} → ${target.name}'),
          );
        } else {
          NotificationOverlayManager().showError(
            title: 'In tem vận đơn thất bại',
            message: tr('Kiểm tra máy tem «${target.name}» (giấy 100×150, kết nối).'),
          );
        }
      }
      if (ok) return ShippingLabelPrintResult.printed;
      if (!allowFallback) return ShippingLabelPrintResult.failed;
    }

    if (!allowFallback) return ShippingLabelPrintResult.failed;
    // Không có máy tem (hoặc in lỗi): nhãn hãng → mở link; tem tự vẽ → xem / in PDF.
    if (fallbackUrl != null) return _openUrl(fallbackUrl, showFeedback);
    if (raster != null) {
      final pdf = await _rasterPdf(raster, s);
      await Printing.layoutPdf(onLayout: (_) async => pdf, name: 'TemVanDon_${o.orderNo}.pdf');
      return ShippingLabelPrintResult.previewed;
    }
    return ShippingLabelPrintResult.failed;
  }

  static Future<ShippingLabelPrintResult> _openCarrierLink(
    PosSaleOrder o,
    PosShippingLabelSettings s,
    bool showFeedback,
  ) async {
    final res = await _api.getPosShipmentLabel(o.id, size: s.carrierSize);
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
    final url = (data['labelUrl'] ?? data['LabelUrl'] ?? '').toString();
    if (url.isEmpty) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Không lấy được nhãn in',
          message: (data['message'] ?? data['Message'] ?? res['message'] ?? '').toString(),
        );
      }
      return ShippingLabelPrintResult.failed;
    }
    return _openUrl(url, showFeedback);
  }

  static Future<ShippingLabelPrintResult> _openUrl(String url, bool showFeedback) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ShippingLabelPrintResult.openedLink;
    }
    if (showFeedback) NotificationOverlayManager().showError(title: 'Không mở được link in', message: url);
    return ShippingLabelPrintResult.failed;
  }

  /// In nhiều đơn liền nhau (chỉ in thẳng ra máy tem — không mở hàng loạt trình duyệt).
  static Future<({int printed, int failed})> printMany(
    List<String> orderIds, {
    void Function(int done, int total)? onProgress,
  }) async {
    final s = await PosShippingLabelSettings.load();
    var printed = 0, failed = 0;
    for (var i = 0; i < orderIds.length; i++) {
      final r = await printForOrder(
        orderIds[i],
        showFeedback: false,
        allowFallback: false,
        settings: s.directPrint ? s : s.copyWith(size: '100x150'),
      );
      if (r == ShippingLabelPrintResult.printed) {
        printed++;
      } else {
        failed++;
      }
      onProgress?.call(i + 1, orderIds.length);
    }
    return (printed: printed, failed: failed);
  }

  /// Gọi sau khi tạo vận đơn thành công (bấm tay hoặc đơn online tự tạo): bật «Tự in» thì in một lần.
  static Future<void> autoPrintAfterCreate(String orderId, {PosSaleOrder? order}) async {
    final s = await PosShippingLabelSettings.load();
    if (!s.autoPrint || !s.directPrint) return;
    if (await PosShippingLabelSettings.wasAutoPrinted(orderId)) return;
    if (!await hasPrinter()) return;
    await PosShippingLabelSettings.markAutoPrinted(orderId);
    final r = await printForOrder(orderId, order: order, showFeedback: true, allowFallback: false, settings: s);
    if (r != ShippingLabelPrintResult.printed) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa tự in được tem vận đơn',
        message: tr('Mở đơn và bấm «In tem vận đơn» để in lại.'),
      );
    }
  }
}
