import 'package:flutter/foundation.dart';

import '../models/pos_store_printer.dart';
import 'pos_device_identity.dart';
import 'pos_local_printers_store.dart';
import 'pos_print_orchestrator.dart';

/// Đích in bếp: máy này (local) hoặc Agent — không trộn hai lớp gán.
enum KitchenPrintLane { local, agent, none }

class KitchenPrintRoute {
  const KitchenPrintRoute._(this.lane, this.printerId);
  const KitchenPrintRoute.local(String id)
      : this._(KitchenPrintLane.local, id);
  const KitchenPrintRoute.agent(String id)
      : this._(KitchenPrintLane.agent, id);
  const KitchenPrintRoute.none() : this._(KitchenPrintLane.none, null);

  final KitchenPrintLane lane;
  final String? printerId;
}

/// Máy gửi vs Agent: gán local chỉ khi in trên máy này.
abstract final class PosPrintDeviceScope {
  static String? _myId;

  static Future<String> myDeviceId() async {
    if (kIsWeb) return '';
    _myId ??= (await PosDeviceIdentity.get()).id;
    return _myId ?? '';
  }

  /// Máy cửa hàng này đã cài trên thiết bị đang gửi lệnh.
  static Future<bool> isInstalledHere(String printerId) async {
    if (kIsWeb || printerId.trim().isEmpty) return false;
    final local = await PosLocalPrintersStore.instance
        .byStorePrinterId(printerId.trim());
    return local != null && PosLocalPrintersStore.profileAllowsDirectLocal(local);
  }

  static Future<bool> isOwnedDeviceLocal(PosStorePrinter printer) async {
    if (!printer.isDeviceLocal) return false;
    final me = await myDeviceId();
    final owner = (printer.ownerDeviceId ?? '').trim();
    if (me.isNotEmpty &&
        owner.isNotEmpty &&
        owner.toLowerCase() == me.toLowerCase()) {
      return true;
    }
    return isInstalledHere(printer.id);
  }

  static Future<bool> canExactLocal(
    String printerId, {
    required String documentRole,
  }) async {
    if (kIsWeb || printerId.trim().isEmpty) return false;
    final p = PosPrintOrchestrator.instance.printerByIdExact(printerId);
    if (p == null) return isInstalledHere(printerId);
    final on = await PosLocalPrintersStore.instance
        .resolveOnDeviceForStorePrinter(
      p,
      documentRole: documentRole,
      exactPort: true,
    );
    return on != null;
  }

  /// Máy Agent/cloud: bỏ máy nội bộ của máy gửi; twin cloud nếu có đúng 1.
  static Future<PosStorePrinter?> agentFacingPrinter(String? printerId) async {
    final id = (printerId ?? '').trim();
    if (id.isEmpty) return null;
    final raw = PosPrintOrchestrator.instance.printerByIdExact(id) ??
        PosPrintOrchestrator.instance.printerById(id);
    if (raw == null) return null;
    if (await isOwnedDeviceLocal(raw)) return null;
    if (!raw.isDeviceLocal) return raw;
    final twin = PosPrintOrchestrator.instance.preferCloudAgentPrinter(raw);
    if (!twin.isDeviceLocal) return twin;
    return null;
  }

  static Future<KitchenPrintRoute> resolveKitchenRoute({
    required String? devicePrinterId,
    required String? storePrinterId,
    required String documentRole,
  }) async {
    final device = (devicePrinterId ?? '').trim();
    final store = (storePrinterId ?? '').trim();
    // Gán máy nội bộ trên thiết bị này = nguồn sự thật.
    // Không fallback sang DefaultPrinterId cửa hàng (LAN Zywell máy/tài khoản khác).
    if (device.isNotEmpty) {
      return KitchenPrintRoute.local(device);
    }
    if (store.isNotEmpty &&
        await canExactLocal(store, documentRole: documentRole)) {
      return KitchenPrintRoute.local(store);
    }
    final agent = await agentFacingPrinter(store);
    if (agent != null && agent.id.trim().isNotEmpty) {
      return KitchenPrintRoute.agent(agent.id);
    }
    return const KitchenPrintRoute.none();
  }

  static Future<List<PosStorePrinter>> excludeSenderLocals(
    List<PosStorePrinter> printers,
  ) async {
    if (printers.isEmpty) return printers;
    final out = <PosStorePrinter>[];
    for (final p in printers) {
      if (await isOwnedDeviceLocal(p)) continue;
      out.add(p);
    }
    return out;
  }
}
