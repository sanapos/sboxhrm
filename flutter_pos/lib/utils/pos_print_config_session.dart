import '../models/pos_print_template.dart';
import '../services/pos_product_printer_service.dart';
import 'pos_print_orchestrator.dart';
import 'pos_print_template_renderer.dart';

/// Cache mẫu in + cấu hình máy in trong phiên bán hàng.
class PosPrintConfigSession {
  PosPrintConfigSession._();
  static final PosPrintConfigSession instance = PosPrintConfigSession._();

  PosPrintTemplate? _warehouseTemplate;
  String? _warehouseTemplateKey;
  DateTime? _warehouseTemplateAt;
  PosPrintTemplate? _kitchenSlipTemplate;
  PosPrintTemplate? _kitchenVoidTemplate;
  DateTime? _kitchenTemplateAt;
  DateTime? _lastFullWarmAt;
  /// TTL đủ dài để mở lại màn bán / đổi tab không re-fetch mẫu + orchestrator.
  static const _templateTtl = Duration(minutes: 5);

  bool get isWarm {
    final at = _lastFullWarmAt ?? _kitchenTemplateAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < _templateTtl;
  }

  Future<void> warmUp({String? warehouseTemplateId}) async {
    await Future.wait([
      PosPrintOrchestrator.instance.refreshConfig(),
      PosProductPrinterService.instance.preload(),
    ]);
    await Future.wait([
      warehouseTemplate(warehouseTemplateId),
      kitchenTemplate(isCancel: false),
      kitchenTemplate(isCancel: true),
    ]);
    _lastFullWarmAt = DateTime.now();
  }

  /// Bỏ qua nếu phiên vẫn còn nóng — tránh invalidate + double refresh mỗi lần mở bán.
  Future<void> warmUpIfStale({String? warehouseTemplateId}) async {
    final key = warehouseTemplateId ?? '';
    if (isWarm &&
        _warehouseTemplate != null &&
        _warehouseTemplateKey == key &&
        _kitchenSlipTemplate != null) {
      return;
    }
    await warmUp(warehouseTemplateId: warehouseTemplateId);
  }

  Future<PosPrintTemplate?> warehouseTemplate(
    String? templateId, {
    bool force = false,
  }) async {
    final key = templateId ?? '';
    if (!force &&
        _warehouseTemplate != null &&
        _warehouseTemplateKey == key &&
        _warehouseTemplateAt != null &&
        DateTime.now().difference(_warehouseTemplateAt!) < _templateTtl) {
      return _warehouseTemplate;
    }
    _warehouseTemplate = await resolvePosPrintTemplate(
      documentType: PosPrintDocumentTypes.stockIssue,
      templateId: templateId,
    );
    _warehouseTemplateKey = key;
    _warehouseTemplateAt = DateTime.now();
    return _warehouseTemplate;
  }

  Future<PosPrintTemplate?> kitchenTemplate({
    required bool isCancel,
    bool force = false,
  }) async {
    if (!force &&
        _kitchenTemplateAt != null &&
        DateTime.now().difference(_kitchenTemplateAt!) < _templateTtl) {
      return isCancel ? _kitchenVoidTemplate : _kitchenSlipTemplate;
    }
    _kitchenSlipTemplate = await resolvePosPrintTemplate(
      documentType: PosPrintDocumentTypes.kitchenSlip,
    );
    _kitchenVoidTemplate = await resolvePosPrintTemplate(
      documentType: PosPrintDocumentTypes.kitchenVoid,
    );
    _kitchenTemplateAt = DateTime.now();
    return isCancel ? _kitchenVoidTemplate : _kitchenSlipTemplate;
  }

  void invalidate({bool warehouseTemplateOnly = false}) {
    _warehouseTemplate = null;
    _warehouseTemplateKey = null;
    _warehouseTemplateAt = null;
    _lastFullWarmAt = null;
    if (!warehouseTemplateOnly) {
      _kitchenSlipTemplate = null;
      _kitchenVoidTemplate = null;
      _kitchenTemplateAt = null;
      PosPrintOrchestrator.instance.invalidateCache();
      PosProductPrinterService.instance.invalidate();
    }
  }
}
