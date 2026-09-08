import 'api_service.dart';
import '../utils/pos_device_product_printers.dart';
import '../utils/pos_local_printers_store.dart';
import '../utils/pos_print_device_scope.dart';

/// Cache gán máy in theo sản phẩm (product → category fallback).
class PosProductPrinterService {
  PosProductPrinterService._();
  static final PosProductPrinterService instance = PosProductPrinterService._();

  final _api = ApiService();
  Map<String, _PrinterMapEntry>? _cache;
  DateTime? _cacheAt;
  static const _ttl = Duration(minutes: 5);

  Future<void> invalidate() async {
    _cache = null;
    _cacheAt = null;
  }

  Future<void> preload({bool force = false}) async {
    if (force) {
      _cache = null;
      _cacheAt = null;
    }
    await _load();
  }

  Future<Map<String, _PrinterMapEntry>> _load() async {
    if (_cache != null &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!) < _ttl) {
      return _cache!;
    }
    final res = await _api.getPosProductPrinterMap();
    final map = <String, _PrinterMapEntry>{};
    if (res['isSuccess'] == true && res['data'] is List) {
      for (final raw in res['data'] as List) {
        if (raw is! Map) continue;
        final id = raw['productId']?.toString() ?? '';
        if (id.isEmpty) continue;
        map[id] = _PrinterMapEntry(
          productPrinterId: raw['productPrinterId']?.toString(),
          categoryPrinterId: raw['categoryPrinterId']?.toString(),
        );
      }
    }
    _cache = map;
    _cacheAt = DateTime.now();
    return map;
  }

  /// Máy in cho [productId]: ưu tiên SP → nhóm hàng.
  Future<String?> resolvePrinterId(String productId) async {
    if (productId.isEmpty) return null;
    final map = await _load();
    final e = map[productId];
    if (e == null) return null;
    if (e.productPrinterId != null && e.productPrinterId!.isNotEmpty) {
      return e.productPrinterId;
    }
    if (e.categoryPrinterId != null && e.categoryPrinterId!.isNotEmpty) {
      return e.categoryPrinterId;
    }
    return null;
  }

  /// Local máy này trước; không in được thì Agent (bỏ gán máy gửi).
  Future<KitchenPrintRoute> resolveKitchenRoute(
    String productId, {
    required String documentRole,
  }) async {
    if (productId.isEmpty) return const KitchenPrintRoute.none();
    final deviceId = await PosDeviceProductPrinters.instance.printerIdForProduct(
      productId,
      label: documentRole == PosLocalPrinterRoles.kitchenLabel,
    );
    final storeId = await resolvePrinterId(productId);
    return PosPrintDeviceScope.resolveKitchenRoute(
      devicePrinterId: deviceId,
      storePrinterId: storeId,
      documentRole: documentRole,
    );
  }
}

class _PrinterMapEntry {
  const _PrinterMapEntry({this.productPrinterId, this.categoryPrinterId});
  final String? productPrinterId;
  final String? categoryPrinterId;
}
