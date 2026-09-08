import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/pos_store_printer.dart';
import '../services/pos_product_printer_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_lan_printer_scan_sheet.dart';
import 'package:sbox_pos/l10n/app_tr.dart';
import 'pos_local_printers_store.dart';
import 'pos_print_agent_settings.dart';
import 'pos_print_orchestrator.dart';
import 'pos_thermal_printer_settings.dart';
import 'pos_usb_labels.dart';
import 'pos_usb_printer.dart';

/// Kết nối máy in bếp USB/LAN nội bộ (không cần chia sẻ Agent).
class PosKitchenDirectConnect {
  PosKitchenDirectConnect._();

  static const _kitchenRoles = {
    PosLocalPrinterRoles.kitchenSlip,
    PosLocalPrinterRoles.kitchenVoid,
  };

  static String _newId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return 'kds-$t';
  }

  static bool _isKitchenPrinter(
    PosStorePrinter p, {
    required Set<String> kitchenRouteIds,
    required Set<String> localKitchenStoreIds,
  }) {
    final id = p.id.toLowerCase();
    if (kitchenRouteIds.contains(id) || localKitchenStoreIds.contains(id)) {
      return true;
    }
    return p.documentTypes.contains(PosCloudDocumentTypes.kitchenSlip) ||
        p.documentTypes.contains(PosCloudDocumentTypes.kitchenVoid);
  }

  static Future<List<PosStorePrinter>> reachableKitchenPrinters({
    required String deviceId,
  }) async {
    await PosPrintOrchestrator.instance.refreshConfig(force: true);
    final orch = PosPrintOrchestrator.instance;
    final mine = deviceId.trim().toLowerCase();

    final kitchenRouteIds = <String>{};
    for (final r in orch.routes) {
      if (r.documentType == PosCloudDocumentTypes.kitchenSlip ||
          r.documentType == PosCloudDocumentTypes.kitchenVoid) {
        final id = r.printerId.trim().toLowerCase();
        if (id.isNotEmpty) kitchenRouteIds.add(id);
      }
    }

    final locals = await PosLocalPrintersStore.instance.loadAll();
    final localKitchenStoreIds = <String>{};
    for (final loc in locals) {
      if (!loc.enabled) continue;
      if (!loc.roles.contains(PosLocalPrinterRoles.kitchenSlip) &&
          !loc.roles.contains(PosLocalPrinterRoles.kitchenVoid)) {
        continue;
      }
      final sid = (loc.storePrinterId ?? '').trim().toLowerCase();
      if (sid.isNotEmpty) localKitchenStoreIds.add(sid);
    }

    final agent = await PosPrintAgentSettings.load();
    final assigned =
        agent.assignedPrinterIds.map((e) => e.trim().toLowerCase()).toSet();

    var list = orch.printers.where((p) {
      if (!p.isActive || p.id.isEmpty) return false;
      if (!_isKitchenPrinter(p,
          kitchenRouteIds: kitchenRouteIds,
          localKitchenStoreIds: localKitchenStoreIds)) {
        return false;
      }
      if (p.isDeviceLocal) {
        final owner = (p.ownerDeviceId ?? '').trim().toLowerCase();
        return owner.isEmpty || mine.isEmpty || owner == mine;
      }
      return assigned.contains(p.id.toLowerCase()) ||
          localKitchenStoreIds.contains(p.id.toLowerCase());
    }).toList();

    final seen = {for (final p in list) p.id.trim().toLowerCase()};
    for (final loc in locals) {
      if (!loc.enabled || loc.isLabel) continue;
      if (!loc.roles.contains(PosLocalPrinterRoles.kitchenSlip) &&
          !loc.roles.contains(PosLocalPrinterRoles.kitchenVoid)) {
        continue;
      }
      if (!PosLocalPrintersStore.profileAllowsDirectLocal(loc)) continue;
      final sid = (loc.storePrinterId ?? loc.id).trim().toLowerCase();
      if (sid.isEmpty || seen.contains(sid)) continue;
      list.add(storePrinterFromLocal(loc, deviceId: deviceId));
      seen.add(sid);
    }

    list = PosPrintOrchestrator.uniquePrintersForPicker(
      list,
      deviceId: deviceId,
    );

    PosStorePrinter better(PosStorePrinter a, PosStorePrinter b) {
      if (a.isDeviceLocal && !b.isDeviceLocal) return a;
      if (b.isDeviceLocal && !a.isDeviceLocal) return b;
      return a;
    }

    final byName = <String, PosStorePrinter>{};
    for (final p in list) {
      final key = p.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      final prev = byName[key];
      byName[key] = prev == null ? p : better(prev, p);
    }
    final out = byName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static String _storeConn(PosThermalConnectionType t) {
    switch (t) {
      case PosThermalConnectionType.lan:
        return 'Lan';
      case PosThermalConnectionType.usb:
        return 'Usb';
      case PosThermalConnectionType.sunmi:
        return 'Sunmi';
      case PosThermalConnectionType.bluetooth:
        return 'Bluetooth';
    }
  }

  static PosStorePrinter storePrinterFromLocal(
    PosLocalPrinterProfile loc, {
    required String deviceId,
  }) {
    final id = (loc.storePrinterId ?? loc.id).trim();
    return PosStorePrinter(
      id: id.isEmpty ? loc.id : id,
      name: loc.name,
      connectionType: _storeConn(loc.connectionType),
      printerBrand: loc.printerBrand.key,
      paperSize: loc.paperSize,
      bluetoothAddress: loc.bluetoothAddress,
      bluetoothName: loc.bluetoothName,
      lanHost: loc.lanHost,
      lanPort: loc.lanPort,
      usbDeviceName: loc.usbDeviceName,
      feedBeforeCut: loc.feedBeforeCut,
      partialCut: loc.partialCut,
      cutPerItem: loc.cutPerItem,
      isDeviceLocal: true,
      ownerDeviceId: deviceId,
      isActive: loc.enabled,
      requiresAgent: false,
      documentTypes: const [
        PosCloudDocumentTypes.kitchenSlip,
        PosCloudDocumentTypes.kitchenVoid,
      ],
    );
  }

  /// Máy in phiếu «Làm xong»: chọn sẵn → trạm KDS → máy bếp nội bộ → USB/LAN đã cắm.
  static Future<PosStorePrinter?> resolvePrintTarget({
    required String deviceId,
    String? preferredId,
    String? stationId,
  }) async {
    final list = await reachableKitchenPrinters(deviceId: deviceId);
    PosStorePrinter? byId(Iterable<PosStorePrinter> src, String? id) {
      final want = (id ?? '').trim().toLowerCase();
      if (want.isEmpty) return null;
      for (final p in src) {
        if (p.id.trim().toLowerCase() == want) return p;
      }
      return null;
    }

    final preferred = byId(list, preferredId);
    if (preferred != null) return preferred;
    final station = byId(list, stationId);
    if (station != null) return station;

    final orch = PosPrintOrchestrator.instance;
    for (final id in [preferredId, stationId]) {
      final p = byId(orch.printers, id);
      if (p == null) continue;
      if (await PosPrintOrchestrator.instance.canProbeLocalPortForTest(p)) {
        return p;
      }
      if (p.hasKitchenDocumentRole) return p;
    }

    if (list.isNotEmpty) return list.first;

    final locals = await PosLocalPrintersStore.instance.loadAll();
    PosLocalPrinterProfile? pick;
    for (final loc in locals) {
      if (!loc.enabled || loc.isLabel) continue;
      if (!PosLocalPrintersStore.profileAllowsDirectLocal(loc)) continue;
      if (loc.roles.contains(PosLocalPrinterRoles.kitchenSlip) ||
          loc.roles.contains(PosLocalPrinterRoles.kitchenVoid)) {
        pick = loc;
        break;
      }
    }
    if (pick == null) {
      for (final loc in locals) {
        if (!loc.enabled || loc.isLabel) continue;
        if (!PosLocalPrintersStore.profileAllowsDirectLocal(loc)) continue;
        pick = loc;
        break;
      }
    }
    if (pick != null) return storePrinterFromLocal(pick, deviceId: deviceId);
    return byId(orch.printers, preferredId) ?? byId(orch.printers, stationId);
  }

  static Future<Set<String>> listedPrinterIds({
    required String deviceId,
  }) async {
    final ids = <String>{};
    final agent = await PosPrintAgentSettings.load();
    ids.addAll(agent.assignedPrinterIds.map((e) => e.toLowerCase()));
    final locals = await PosLocalPrintersStore.instance.loadAll();
    for (final loc in locals) {
      if (!loc.enabled) continue;
      if (!loc.roles.contains(PosLocalPrinterRoles.kitchenSlip) &&
          !loc.roles.contains(PosLocalPrinterRoles.kitchenVoid)) {
        continue;
      }
      final sid = (loc.storePrinterId ?? '').trim();
      if (sid.isNotEmpty) ids.add(sid.toLowerCase());
    }
    return ids;
  }

  static Future<PosLocalPrinterProfile?> connectUsb(BuildContext context) async {
    if (kIsWeb || !PosUsbPrinter.isSupported) {
      NotificationOverlayManager().showError(
        title: 'USB',
        message: tr('Kết nối USB nội bộ chỉ trên máy POS Android'),
      );
      return null;
    }
    var devices = await PosUsbPrinter.listDevices();
    if (!context.mounted) return null;
    if (devices.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Không thấy cổng USB',
        message: tr('Cắm máy in USB, bật nguồn, rồi thử lại'),
      );
      return null;
    }
    final picked = await showModalBottomSheet<PosUsbDevice>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.5,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(tr('Chọn máy in bếp USB'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final d in devices)
                      ListTile(
                        leading: const Icon(Icons.usb),
                        title: Text(PosUsbLabels.title(d)),
                        subtitle: Text(PosUsbLabels.subtitle(d)),
                        onTap: () => Navigator.pop(ctx, d),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return null;
    if (!picked.hasPermission) {
      await PosUsbPrinter.requestPermission(picked);
    }
    return _saveKitchenProfile(
      name: PosUsbLabels.title(picked),
      type: PosThermalConnectionType.usb,
      usbDeviceName: picked.savedRef,
      brand: PosUsbLabels.brandEnum(
            vendorId: picked.vendorId,
            manufacturer: picked.manufacturerName,
            product: picked.productName,
          ) ??
          PosThermalPrinterBrand.generic,
    );
  }

  static Future<PosLocalPrinterProfile?> connectLan(BuildContext context) async {
    if (kIsWeb) {
      NotificationOverlayManager().showError(
        title: 'LAN',
        message: tr('Quét LAN nội bộ chỉ trên máy POS Android'),
      );
      return null;
    }
    final hit = await showPosLanPrinterScanSheet(context);
    if (hit == null || !context.mounted) return null;
    return _saveKitchenProfile(
      name: hit.brand == PosThermalPrinterBrand.generic
          ? 'Bếp LAN ${hit.host}'
          : '${hit.brand.label} ${hit.host}',
      type: PosThermalConnectionType.lan,
      lanHost: hit.host,
      lanPort: hit.port,
      brand: hit.brand,
    );
  }

  static Future<PosLocalPrinterProfile?> _saveKitchenProfile({
    required String name,
    required PosThermalConnectionType type,
    String? usbDeviceName,
    String? lanHost,
    int lanPort = 9100,
    PosThermalPrinterBrand brand = PosThermalPrinterBrand.generic,
  }) async {
    final profile = PosLocalPrinterProfile(
      id: _newId(),
      name: name,
      enabled: true,
      kind: PosLocalPrinterKind.receipt,
      roles: _kitchenRoles,
      connectionType: type,
      printerBrand: brand,
      usbDeviceName: usbDeviceName,
      lanHost: lanHost,
      lanPort: lanPort,
      openCashDrawer: false,
    );
    final saved =
        await PosLocalPrintersStore.instance.upsert(profile, syncServer: true);
    await PosProductPrinterService.instance.invalidate();
    await PosPrintOrchestrator.instance.invalidateCache();
    NotificationOverlayManager().showSuccess(
      title: 'Đã kết nối máy bếp',
      message: tr('${saved.name} · ${saved.connectionType.label} nội bộ'),
    );
    return saved;
  }
}
