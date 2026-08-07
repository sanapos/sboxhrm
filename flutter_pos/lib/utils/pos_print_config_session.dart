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
  static const _templateTtl = Duration(minutes: 10);

  Future<void> warmUp({String? warehouseTemplateId}) async {
    await Future.wait([
      PosPrintOrchestrator.instance.refreshConfig(),
      PosProductPrinterService.instance.preload(),
    ]);
    await warehouseTemplate(warehouseTemplateId);
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

  void invalidate({bool warehouseTemplateOnly = false}) {
    _warehouseTemplate = null;
    _warehouseTemplateKey = null;
    _warehouseTemplateAt = null;
    if (!warehouseTemplateOnly) {
      PosPrintOrchestrator.instance.invalidateCache();
      PosProductPrinterService.instance.invalidate();
    }
  }
}
