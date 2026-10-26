import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/notification_overlay.dart';
import 'pos_local_printers_store.dart';
import 'pos_printer_transport.dart';
import 'pos_thermal_printer_settings.dart';
import 'pos_usb_labels.dart';
import 'pos_usb_printer.dart';

/// Tự nhận máy in gắn trên thiết bị (không cần vào Thiết lập máy in):
/// - Máy Sunmi: máy in trong máy → máy in hóa đơn (K80 nếu có dao cắt, K58 máy cầm tay).
/// - Cắm USB máy in nhiệt → máy in hóa đơn K80; tên/model gợi ý máy tem → máy in tem 50×30.
/// - Rút ra cắm cổng khác: khớp lại theo VID/PID (xem [PosUsbPrinter.matchProfilesExclusive]),
///   không tạo máy trùng.
/// Máy người dùng đã xóa không tự thêm lại ([_kIgnored]).
class PosPrinterAutoDetect {
  PosPrinterAutoDetect._();
  static final PosPrinterAutoDetect instance = PosPrinterAutoDetect._();

  static const _kIgnored = 'pos_printer_autodetect_ignored_v1';
  static const sunmiIgnoreKey = 'sunmi';
  static const sunmiProfileId = 'auto_sunmi_builtin';

  StreamSubscription<Map<String, dynamic>>? _usbSub;
  Future<List<PosLocalPrinterProfile>>? _inflight;

  /// Gọi sau khi đăng nhập cửa hàng (máy Android). An toàn khi gọi nhiều lần.
  Future<void> start() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _usbSub ??= PosUsbPrinter.deviceEvents.listen((e) {
      if (e['action'] == 'attached') {
        // Đợi Android liệt kê xong thiết bị mới.
        Future<void>.delayed(const Duration(milliseconds: 800), scan);
      }
    });
    await scan();
  }

  /// Quét và thêm máy chưa có. Trả về các máy vừa thêm.
  Future<List<PosLocalPrinterProfile>> scan() {
    return _inflight ??= _scanOnce().whenComplete(() => _inflight = null);
  }

  Future<List<PosLocalPrinterProfile>> _scanOnce() async {
    try {
      final store = PosLocalPrintersStore.instance;
      final existing = await store.loadAll();
      final isSunmi = await PosPrinterTransport.isSunmiDevice();
      final hasCutter = isSunmi && await PosPrinterTransport.sunmiHasAutoCutter();
      final devices = await PosUsbPrinter.listDevices();
      final ignored = await ignoredKeys();
      var seq = 0;
      final plan = planNewProfiles(
        existing: existing,
        devices: devices,
        isSunmiDevice: isSunmi,
        sunmiHasCutter: hasCutter,
        ignored: ignored,
        newId: () => 'auto_${DateTime.now().microsecondsSinceEpoch}_${seq++}',
      );
      final added = <PosLocalPrinterProfile>[];
      for (final p in plan) {
        added.add(await store.upsert(p));
      }
      for (final p in added) {
        NotificationOverlayManager().showInfo(
          title: 'Đã nhận máy in',
          message: '${p.name} — ${p.isLabel ? 'máy in tem ${_labelSize(p)}' : 'máy in hóa đơn ${p.paperSize}'}. '
              'Đổi vai trò trong Thiết lập › Máy in.',
        );
      }
      return added;
    } catch (e) {
      debugPrint('PosPrinterAutoDetect.scan: $e');
      return const [];
    }
  }

  static String _labelSize(PosLocalPrinterProfile p) =>
      p.labelTemplateId == 'roll_1_50x30' ? '50×30' : p.labelTemplateId;

  /// Máy USB đã cài nhưng không thấy ở cổng cũ (rút ra cắm cổng khác, đường dẫn đổi; máy
  /// không có serial) → khớp lại theo VID/PID trên toàn bộ máy USB đã cài (mỗi cổng chỉ thuộc
  /// 1 máy) và lưu cổng mới.
  static Future<PosUsbDevice?> resolveMovedUsb(String? savedRaw) async {
    final raw = (savedRaw ?? '').trim();
    if (raw.isEmpty) return null;
    final list = (await PosUsbPrinter.listDevices()).where((d) => d.canPrint && !d.isHid).toList();
    if (list.isEmpty) return null;
    final store = PosLocalPrintersStore.instance;
    final usb = (await store.loadAll())
        .where((p) =>
            p.connectionType == PosThermalConnectionType.usb &&
            (p.usbDeviceName ?? '').trim().isNotEmpty)
        .toList();
    final identity = PosLocalPrintersStore.usbIdentity(raw);
    final target = usb.where((p) => p.usbDeviceName!.trim() == raw).firstOrNull ??
        usb.where((p) => PosLocalPrintersStore.usbIdentity(p.usbDeviceName) == identity).firstOrNull;
    const adHoc = '_target';
    final profiles = [
      for (final p in usb) (id: p.id, savedRaw: p.usbDeviceName),
      if (target == null) (id: adHoc, savedRaw: raw),
    ];
    final hit = PosUsbPrinter.matchProfilesExclusive(profiles, list)[target?.id ?? adHoc];
    if (hit == null) return null;
    if (target != null && target.usbDeviceName != hit.savedRef) {
      debugPrint('USB: ${target.name} đổi cổng → ${hit.deviceName}');
      unawaited(store.upsert(target.copyWith(usbDeviceName: hit.savedRef)));
    }
    return hit;
  }

  /// Khóa bỏ qua cho máy: `sunmi` hoặc `vid:pid` (máy USB không serial đổi cổng vẫn cùng khóa).
  static String usbIgnoreKey(int vendorId, int productId) => '$vendorId:$productId';

  static Future<Set<String>> ignoredKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kIgnored);
      if (raw == null) return {};
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Người dùng xóa máy tự nhận → ghi nhớ để không thêm lại.
  static Future<void> rememberRemoved(PosLocalPrinterProfile p) async {
    String? key;
    if (p.connectionType == PosThermalConnectionType.sunmi) {
      key = sunmiIgnoreKey;
    } else if (p.connectionType == PosThermalConnectionType.usb) {
      final ref = PosUsbSavedRef.parse(p.usbDeviceName);
      final parts = (ref.stableId ?? '').split(':');
      final vid = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
      final pid = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (vid != null && pid != null) key = usbIgnoreKey(vid, pid);
    }
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final set = await ignoredKeys()..add(key);
    await prefs.setString(_kIgnored, jsonEncode(set.toList()));
  }

  /// Tên / model gợi ý máy in tem (TSPL): Xprinter XP-3xxB/4xxB/DT…, TSC, Zebra, Godex, «label».
  static bool looksLikeLabelPrinter(PosUsbDevice d) {
    final blob = '${d.manufacturerName ?? ''} ${d.productName ?? ''}'.toLowerCase();
    if (RegExp(r'\b(label|tspl|tsc|zebra|godex|barcode printer)\b').hasMatch(blob)) return true;
    // Xprinter tem: XP-365B, XP-420B, XP-460B, XP-470B, XP-DT108B, XP-D4601B.
    if (RegExp(r'xp-?(3\d\d|4\d\d|dt\d+|d\d{3,})b').hasMatch(blob)) return true;
    // Gprinter tem: GP-1324D, GP-3120TU, GP-9034T…
    if (RegExp(r'gp-?(1\d{3}d|3\d{3}tu?|9\d{3}t)').hasMatch(blob)) return true;
    return false;
  }

  /// Máy cần thêm mới — hàm thuần để test.
  static List<PosLocalPrinterProfile> planNewProfiles({
    required List<PosLocalPrinterProfile> existing,
    required List<PosUsbDevice> devices,
    required bool isSunmiDevice,
    required bool sunmiHasCutter,
    required Set<String> ignored,
    required String Function() newId,
  }) {
    final out = <PosLocalPrinterProfile>[];
    bool hasInvoice(Iterable<PosLocalPrinterProfile> list) => list.any((p) =>
        p.enabled && !p.isLabel && p.hasRole(PosLocalPrinterRoles.saleInvoice));

    if (isSunmiDevice &&
        !ignored.contains(sunmiIgnoreKey) &&
        !existing.any((p) => p.connectionType == PosThermalConnectionType.sunmi) &&
        // Đã cài máy hóa đơn khác (USB/LAN/BT) → không giành vai trò.
        !hasInvoice(existing)) {
      out.add(PosLocalPrinterProfile(
        id: sunmiProfileId,
        name: 'Máy in Sunmi (máy này)',
        connectionType: PosThermalConnectionType.sunmi,
        printerBrand: PosThermalPrinterBrand.sunmi,
        paperSize: sunmiHasCutter ? 'K80' : 'K58',
        roles: const {PosLocalPrinterRoles.saleInvoice},
      ));
    }

    final printable = devices.where((d) => d.canPrint && !d.isHid && d.vendorId != 0).toList();
    if (printable.isEmpty) return out;
    final usbProfiles = [
      for (final p in existing)
        if (p.connectionType == PosThermalConnectionType.usb &&
            (p.usbDeviceName ?? '').trim().isNotEmpty)
          (id: p.id, savedRaw: p.usbDeviceName),
    ];
    final matched = PosUsbPrinter.matchProfilesExclusive(usbProfiles, printable);
    final used = {for (final d in matched.values) if (d != null) d.deviceName};
    // Máy đã cấu hình nhưng chưa khớp (đang rút / chờ khớp): giữ VID/PID của nó,
    // không tạo máy mới cùng model — tránh trùng khi cắm lại cổng khác.
    final pendingVp = <String>{};
    for (final p in usbProfiles) {
      if (matched[p.id] != null) continue;
      final parts = (PosUsbSavedRef.parse(p.savedRaw).stableId ?? '').split(':');
      if (parts.length >= 2) pendingVp.add('${parts[0]}:${parts[1]}');
    }

    // Máy nhiệt cắm USB = máy hóa đơn, trừ khi đã có máy hóa đơn USB đang cắm / Bluetooth trên
    // máy này. Máy LAN (thường là máy bếp) và máy USB cũ đã rút không giữ chỗ hóa đơn.
    var invoiceTaken = existing.any((p) =>
        p.enabled &&
        !p.isLabel &&
        p.hasRole(PosLocalPrinterRoles.saleInvoice) &&
        ((p.connectionType == PosThermalConnectionType.usb && matched[p.id] != null) ||
            p.connectionType == PosThermalConnectionType.bluetooth));
    for (final d in printable) {
      if (used.contains(d.deviceName)) continue;
      final vp = usbIgnoreKey(d.vendorId, d.productId);
      if (ignored.contains(vp) || pendingVp.contains(vp)) continue;
      final isLabel = looksLikeLabelPrinter(d);
      final brand = PosUsbLabels.brandLabel(
        vendorId: d.vendorId,
        productId: d.productId,
        manufacturer: d.manufacturerName,
        product: d.productName,
      );
      final brandEnum = PosUsbLabels.brandEnum(
            vendorId: d.vendorId,
            manufacturer: d.manufacturerName,
            product: d.productName,
          ) ??
          PosThermalPrinterBrand.generic;
      final Set<String> roles;
      if (isLabel) {
        roles = const {PosLocalPrinterRoles.barcodeLabel, PosLocalPrinterRoles.kitchenLabel};
      } else if (!invoiceTaken) {
        roles = const {PosLocalPrinterRoles.saleInvoice};
        invoiceTaken = true;
      } else {
        // Máy hóa đơn đã có → máy nhiệt thứ hai làm máy bếp.
        roles = const {PosLocalPrinterRoles.kitchenSlip, PosLocalPrinterRoles.kitchenVoid};
      }
      out.add(PosLocalPrinterProfile(
        id: newId(),
        name: '${isLabel ? 'Máy tem' : 'Máy in'} $brand (USB)',
        kind: isLabel ? PosLocalPrinterKind.label : PosLocalPrinterKind.receipt,
        connectionType: PosThermalConnectionType.usb,
        printerBrand: brandEnum,
        paperSize: 'K80',
        labelTemplateId: 'roll_1_50x30',
        usbDeviceName: d.savedRef,
        roles: roles,
      ));
      used.add(d.deviceName);
      pendingVp.add(vp);
    }
    return out;
  }
}
