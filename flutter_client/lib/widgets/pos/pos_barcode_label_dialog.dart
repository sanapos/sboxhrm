import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/pos_label_design.dart';
import '../../models/pos_print_template.dart';
import '../../screens/pos/pos_label_templates_screen.dart';
import '../../utils/pos_label_design_painter.dart';
import '../../utils/pos_label_design_store.dart';
import '../../models/pos_product.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/pos_price_list.dart';
import '../../services/api_service.dart';
import '../../utils/pos_price_list_resolver.dart';
import '../../utils/pos_sell_unit_views.dart';
import '../../models/pos_store_printer.dart';
import '../../utils/pos_barcode_print.dart';
import '../../utils/pos_label_printer_service.dart';
import '../../utils/pos_label_printer_settings.dart';
import '../../utils/pos_local_printers_store.dart';
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../utils/pos_store_printer_mapper.dart';
import '../../utils/pos_thermal_printer_service.dart';
import '../../utils/pos_thermal_printer_settings.dart';
import '../../utils/responsive_helper.dart';
import '../notification_overlay.dart';
import 'pos_pdf_preview_dialog.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Dialog chọn loại giấy in tem mã — giao diện kiểu KiotViet.
/// [quantities] (song song với [products]): số tem riêng từng hàng, vd theo số lượng nhập hàng.
/// [documentType] = [PosPrintDocumentTypes.scaleLabel]: in tem cân — mẫu «Tem cân» (hoặc mẫu dựng sẵn),
/// giá trên tem cố định theo mã cân (không đổi theo bảng giá / biến thể).
Future<void> showPosBarcodeLabelDialog(
  BuildContext context,
  List<PosProduct> products, {
  List<int>? quantities,
  String documentType = PosPrintDocumentTypes.barcodeLabel,
}) async {
  if (products.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _PosBarcodeLabelDialog(
      products: products,
      quantities: quantities,
      documentType: documentType,
    ),
  );
}

class _PosBarcodeLabelDialog extends StatefulWidget {
  const _PosBarcodeLabelDialog({
    required this.products,
    this.quantities,
    this.documentType = PosPrintDocumentTypes.barcodeLabel,
  });

  final List<PosProduct> products;
  final List<int>? quantities;
  final String documentType;

  @override
  State<_PosBarcodeLabelDialog> createState() => _PosBarcodeLabelDialogState();
}

class _PosBarcodeLabelDialogState extends State<_PosBarcodeLabelDialog> {
  int _copies = 1;
  late final TextEditingController _copiesCtrl;
  late final TextEditingController _lanHostCtrl;
  late final TextEditingController _lanPortCtrl;
  // Hàng có sẵn mã vạch (EAN) in đúng mã vạch; chưa có thì in mã hàng.
  PosBarcodeCodeField _codeField = PosBarcodeCodeField.barcode;
  PosBarcodePriceMode _priceMode = PosBarcodePriceMode.withVnd;
  PosBarcodeUnitMode _unitMode = PosBarcodeUnitMode.withoutUnit;
  PosBarcodeStoreMode _storeMode = PosBarcodeStoreMode.withoutStore;
  PosBarcodeSpecMode _specMode = PosBarcodeSpecMode.withoutSpecs;
  /// Mỗi biến thể / đơn vị bán một tem (mã SKU / mã vạch biến thể, giá theo đơn vị).
  bool _expandViews = false;
  /// Bảng giá cho giá trên tem (null = giá bán).
  String? _priceListId;
  List<PosPriceList> _priceLists = const [];
  /// Mẫu tem cửa hàng (màn Mẫu in → Tem sản phẩm) đọc được; chọn '' = bố cục chuẩn SBOX.
  /// Mẫu trình soạn tem của cửa hàng (ưu tiên khi in); '' = không dùng (bố cục cũ).
  List<({String id, String name, PosLabelDesign d, bool isDefault})> _designs = const [];
  String _designId = '';
  /// Mẫu in: mẫu đang chọn → mẫu đầu tiên → mẫu dựng sẵn (không còn bố cục cố định cũ).
  PosLabelDesign get _design =>
      _designs.where((x) => x.id == _designId).map((x) => x.d).firstOrNull ??
      _designs.firstOrNull?.d ??
      posLabelDefaultDesign(widget.documentType);
  String get _kDesignPref => '${_kLayoutPref}_design';
  String get _kLayoutPref => switch (widget.documentType) {
        PosPrintDocumentTypes.scaleLabel => 'pos_scale_label_layout_id',
        PosPrintDocumentTypes.specLabel => 'pos_spec_label_layout_id',
        _ => 'pos_barcode_label_layout_id',
      };
  bool get _isScale => widget.documentType == PosPrintDocumentTypes.scaleLabel;
  bool get _isSpec => widget.documentType == PosPrintDocumentTypes.specLabel;

  PosBarcodeLabelTemplate? _selectedTemplate;
  PosLabelPrinterSettings _labelPrinter = const PosLabelPrinterSettings();
  String? _storeName;
  List<Map<String, String>> _btDevices = [];
  bool _printing = false;
  bool _printerExpanded = false;

  @override
  void initState() {
    super.initState();
    _copiesCtrl = TextEditingController(text: tr('1'));
    _lanHostCtrl = TextEditingController();
    _lanPortCtrl = TextEditingController(text: tr('9100'));
    _selectedTemplate = posBarcodeLabelTemplateById(_labelPrinter.templateId) ??
        defaultBarcodeLabelTemplate;
    // Tem thông số: mặc định in dòng / trường thông số.
    if (_isSpec) _specMode = PosBarcodeSpecMode.withSpecs;
    _loadPrinterSettings();
    _loadPriceLists();
    _loadLayouts();
  }

  Future<void> _loadLayouts() async {
    var designs = <({String id, String name, PosLabelDesign d, bool isDefault})>[];
    try {
      final list = await ensurePosLabelDesignTemplates(ApiService(), widget.documentType);
      designs = [
        for (final t in list)
          if (PosLabelDesign.tryParse(t.htmlContent) case final d?) (id: t.id, name: t.name, d: d, isDefault: t.isDefault),
      ];
    } catch (_) {}
    String? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getString(_kDesignPref);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _designs = designs;
      // Mẫu chọn lần trước → mẫu đang dùng → mẫu đầu tiên (không có mẫu nào → mẫu dựng sẵn, xem _design).
      _designId = designs.any((x) => x.id == saved)
          ? saved!
          : (designs.where((x) => x.isDefault).firstOrNull ?? designs.firstOrNull)?.id ?? '';
      _selectedTemplate = posBarcodeLabelTemplateForDesign(_design);
    });
  }

  Future<void> _loadPrinterSettings() async {
    final locals = await PosLocalPrintersStore.instance.loadAll();
    final localLabel =
        locals.where((p) => p.enabled && p.isLabel).firstOrNull;
    final lp =
        localLabel?.toLabelSettings() ?? await PosLabelPrinterSettings.load();
    final store = await PosSellStoreSettings.load();
    if (!mounted) return;
    setState(() {
      _labelPrinter = lp;
      _storeName = store.storeName;
      _lanHostCtrl.text = lp.lanHost ?? '';
      _lanPortCtrl.text = '${lp.lanPort}';
      _selectedTemplate ??=
          posBarcodeLabelTemplateById(lp.templateId) ?? defaultBarcodeLabelTemplate;
    });
    _btDevices = await PosThermalPrinterService.listBluetoothDevices();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _copiesCtrl.dispose();
    _lanHostCtrl.dispose();
    _lanPortCtrl.dispose();
    super.dispose();
  }

  /// Danh sách tem thực in: theo biến thể / đơn vị bán (mỗi loại một tem, mã SKU / mã vạch biến thể, giá
  /// theo đơn vị) và / hoặc giá theo bảng giá. Không chọn gì → đúng danh sách truyền vào.
  Future<({List<PosProduct> products, List<int>? quantities})> _effectiveItems() async {
    // Tem cân: giá đã nằm trong mã cân — không đổi theo bảng giá / biến thể.
    if (_isScale || (!_expandViews && _priceListId == null)) {
      return (products: widget.products, quantities: widget.quantities);
    }
    final api = ApiService();
    var overrides = <String, double>{};
    if (_priceListId != null) {
      final res = await api.getPosPriceListResolvedPrices(_priceListId!);
      if (res['isSuccess'] == true && res['data'] is List) {
        overrides = buildPosPriceOverrideMap(res['data'] as List);
      }
    }
    final out = <PosProduct>[];
    final qty = <int>[];
    for (var i = 0; i < widget.products.length; i++) {
      final p = widget.products[i];
      final q = widget.quantities != null && i < widget.quantities!.length ? widget.quantities![i] : 1;
      void add(PosProduct x) {
        final d = posLabelDetail[p];
        if (d != null) posLabelDetail[x] = d;
        out.add(x);
        qty.add(q);
      }

      if (!_expandViews) {
        add(p.copyWith(basePrice: applyPosPriceListToProductBase(p, overrides)));
        continue;
      }
      var views = await loadPosSellUnitViews(api, p);
      views = applyPosPriceListToViews(views, p, overrides);
      if (views.length <= 1) {
        add(p.copyWith(
          basePrice: views.isEmpty ? applyPosPriceListToProductBase(p, overrides) : views.first.basePrice,
        ));
        continue;
      }
      final variantBarcodes = <String, String>{};
      final unitBarcodes = <String, String>{};
      if (views.any((v) => v.unitId != null)) {
        final ur = await api.getPosProductUnits(p.id);
        if (ur['isSuccess'] == true && ur['data'] is List) {
          for (final e in ur['data'] as List) {
            if (e is! Map) continue;
            final u = PosProductUnit.fromJson(Map<String, dynamic>.from(e));
            if ((u.barcode ?? '').isNotEmpty) unitBarcodes[u.id] = u.barcode!;
          }
        }
      }
      if (views.any((v) => v.variantId != null)) {
        final vr = await api.getPosProductVariants(p.id);
        if (vr['isSuccess'] == true && vr['data'] is List) {
          for (final e in vr['data'] as List) {
            if (e is! Map) continue;
            final v = PosProductVariant.fromJson(Map<String, dynamic>.from(e));
            if ((v.barcode ?? '').trim().isNotEmpty) variantBarcodes[v.id] = v.barcode!.trim();
          }
        }
      }
      for (final v in views) {
        add(p.copyWith(
          name: v.isBase ? p.name : '${p.name} · ${v.label}',
          productCode: v.displayCode.trim().isEmpty ? p.productCode : v.displayCode,
          // Biến thể / đơn vị lớn (Thùng): mã vạch riêng; đơn vị chưa có mã riêng → in mã hàng, không in EAN của lon.
          barcode: v.variantId != null
              ? (variantBarcodes[v.variantId] ?? '')
              : (v.unitId != null ? (unitBarcodes[v.unitId] ?? '') : p.barcode),
          basePrice: v.basePrice,
          baseUnitName: v.unitId != null ? v.label : p.baseUnitName,
        ));
      }
    }
    return (products: out, quantities: qty);
  }

  Future<void> _loadPriceLists() async {
    final res = await ApiService().getPosPriceLists();
    if (!mounted || res['isSuccess'] != true || res['data'] is! List) return;
    setState(() {
      _priceLists = [
        for (final e in res['data'] as List)
          if (e is Map) PosPriceList.fromJson(Map<String, dynamic>.from(e)),
      ].where((l) => l.isActive).toList();
    });
  }

  PosBarcodePrintOptions _options(PosBarcodeLabelTemplate template) =>
      PosBarcodePrintOptions(
        template: template,
        copiesPerProduct: _copies,
        codeField: _codeField,
        priceMode: _priceMode,
        unitMode: _unitMode,
        storeMode: _storeMode,
        storeName: _storeName,
        specMode: _specMode,
        design: _design,
      );

  /// Tổng số tem sẽ in (theo số lượng từng hàng × số bản).
  int get _totalLabels {
    final q = widget.quantities;
    final per = q == null
        ? widget.products.length
        : q.fold<int>(0, (a, b) => a + (b < 0 ? 0 : b));
    return per * _copies;
  }

  String get _countText => widget.quantities == null
      ? '${widget.products.length} mặt hàng × $_copies = $_totalLabels tem'
      : '${widget.products.length} mặt hàng · $_totalLabels tem';

  PosLabelPrinterSettings _draftPrinterSettings() {
    final port = int.tryParse(_lanPortCtrl.text.trim()) ?? 9100;
    return _labelPrinter.copyWith(
      enabled: true,
      templateId: _selectedTemplate?.id ?? _labelPrinter.templateId,
      lanHost: _lanHostCtrl.text.trim(),
      lanPort: port,
    );
  }

  Future<void> _savePrinterSettings() async {
    await _draftPrinterSettings().save();
    if (mounted) setState(() => _labelPrinter = _draftPrinterSettings());
  }

  Future<void> _preview(PosBarcodeLabelTemplate template) async {
    setState(() => _selectedTemplate = template);
    try {
      final eff = await _effectiveItems();
      final bytes = await buildPosBarcodeLabelPdfBytes(
        eff.products,
        options: _options(template),
        copiesPerItem: eff.quantities,
      );
      if (!mounted) return;
      await showPosPdfPreviewDialog(
        context,
        bytes: bytes,
        title: 'Xem bản in — ${template.name}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Không tạo được bản in: $e'))),
      );
    }
  }

  Future<void> _printToDevice() async {
    final template = _selectedTemplate;
    if (template == null) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa chọn khổ giấy',
        message: tr('Chọn mẫu tem và bấm «Xem bản in» hoặc chọn thẻ mẫu'),
      );
      return;
    }

    if (template.isSheet) {
      NotificationOverlayManager().showWarning(
        title: 'Mẫu tờ chỉ in qua PDF',
        message: tr('«${template.name}» là giấy tờ A4 cho máy in văn phòng — bấm «Xem bản in» rồi in. '
            'Máy tem cuộn chọn mẫu Tem …×…'),
      );
      return;
    }

    setState(() => _printing = true);
    await _savePrinterSettings();
    final eff = await _effectiveItems();

    // 1) Ưu tiên máy tem nội bộ trên thiết bị này.
    if (!kIsWeb) {
      final locals = await PosLocalPrintersStore.instance.loadAll();
      final labelPrinters = locals.where((p) => p.enabled && p.isLabel).toList();
      final labelLocal = labelPrinters
              .where((p) => p.hasRole(PosLocalPrinterRoles.barcodeLabel))
              .firstOrNull ??
          labelPrinters
              .where((p) => !p.hasRole(PosLocalPrinterRoles.kitchenLabel))
              .firstOrNull ??
          labelPrinters.firstOrNull;
      if (labelLocal != null) {
        final settings = labelLocal.toLabelSettings().copyWith(
              enabled: true,
              templateId: template.id,
            );
        // Không gửi TSPL lên Sunmi tích hợp.
        if (settings.connectionType == PosThermalConnectionType.sunmi) {
          if (!mounted) return;
          setState(() => _printing = false);
          NotificationOverlayManager().showError(
            title: 'Sai máy in tem',
            message: tr(
              'Máy tem đang chọn Sunmi (hóa đơn). Vào Máy in nội bộ → chọn USB/BT/LAN máy tem.',
            ),
          );
          return;
        }
        final ok = await printPosBarcodeLabelsToDevice(
          eff.products,
          options: _options(template),
          settings: settings,
          copiesPerItem: eff.quantities,
        );
        if (!mounted) return;
        setState(() => _printing = false);
        if (ok) {
          NotificationOverlayManager().showSuccess(
            title: 'Đã gửi in tem',
            message: tr(
              '$_countText → ${labelLocal.name}',
            ),
          );
        } else {
          NotificationOverlayManager().showError(
            title: 'In tem thất bại',
            message: tr('Kiểm tra kết nối máy tem «${labelLocal.name}»'),
          );
        }
        return;
      }
    }

    if (!kIsWeb) {
      await PosPrintOrchestrator.instance.refreshConfig();
      final cloudPrinter = PosPrintOrchestrator.instance
          .resolvePrinter(PosCloudDocumentTypes.barcodeLabel);
      if (cloudPrinter != null && cloudPrinter.isLabelPrinter) {
        final settings = toLabelSettings(cloudPrinter).copyWith(
          templateId: template.id,
        );
        final jobs = await PosLabelPrinterService.buildLabelByteJobs(
          eff.products,
          options: _options(template),
          settings: settings,
          copiesPerItem: eff.quantities,
        );
        final cloudOk = await PosPrintOrchestrator.instance.dispatchLabelJobs(
          jobs: jobs,
          referenceNo:
              'LABEL-${DateTime.now().millisecondsSinceEpoch}-${widget.products.length}',
          showFeedback: true,
          skipDedup: true,
        );
        if (!mounted) return;
        setState(() => _printing = false);
        if (cloudOk) {
          NotificationOverlayManager().showSuccess(
            title: 'Đã gửi in tem',
            message: tr('$_countText (cloud)'),
          );
          return;
        }
        NotificationOverlayManager().showWarning(
          title: 'Cloud tem lỗi',
          message: tr('Thử in trực tiếp máy nội bộ…'),
        );
      }
    }

    final draft = _draftPrinterSettings().copyWith(templateId: template.id);
    if (draft.connectionType == PosThermalConnectionType.sunmi) {
      if (!mounted) return;
      setState(() => _printing = false);
      NotificationOverlayManager().showError(
        title: 'Chưa cấu hình máy tem',
        message: tr('Thêm máy in Tem (USB/BT/LAN) trong Máy in nội bộ.'),
      );
      return;
    }
    if (draft.connectionType == PosThermalConnectionType.bluetooth &&
        (draft.bluetoothAddress == null || draft.bluetoothAddress!.isEmpty)) {
      if (!mounted) return;
      setState(() => _printing = false);
      NotificationOverlayManager().showError(
        title: 'Chưa chọn máy in',
        message: tr('Cấu hình máy in tem trong Máy in nội bộ'),
      );
      return;
    }
    if (draft.connectionType == PosThermalConnectionType.lan &&
        (draft.lanHost == null || draft.lanHost!.trim().isEmpty)) {
      if (!mounted) return;
      setState(() => _printing = false);
      NotificationOverlayManager().showError(
        title: 'Thiếu IP máy in',
        message: tr('Nhập địa chỉ IP máy in tem (LAN/WiFi)'),
      );
      return;
    }

    final ok = await printPosBarcodeLabelsToDevice(
      eff.products,
      options: _options(template),
      settings: draft.copyWith(enabled: true),
      copiesPerItem: eff.quantities,
    );
    if (!mounted) return;
    setState(() => _printing = false);
    if (ok) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã gửi in tem',
        message: tr(_countText),
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'In tem thất bại',
        message: tr('Kiểm tra kết nối, khổ giấy và giao thức TSPL/ESC/POS'),
      );
    }
  }

  Future<void> _testLabelPrinter() async {
    final draft = _draftPrinterSettings();
    setState(() => _printing = true);
    final ok = await PosLabelPrinterService.testPrint(draft);
    if (!mounted) return;
    setState(() => _printing = false);
    if (ok) {
      NotificationOverlayManager()
          .showSuccess(title: 'In thử', message: tr('Đã gửi tem mẫu'));
    } else {
      NotificationOverlayManager().showError(
        title: 'In thử thất bại',
        message: tr('Kiểm tra kết nối máy in tem'),
      );
    }
  }

  Future<void> _exportExcel() async {
    if (_selectedTemplate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Chọn mẫu giấy trước'))),
      );
      return;
    }
    final eff = await _effectiveItems();
    await exportPosBarcodeLabelsExcel(
      eff.products,
      options: _options(_selectedTemplate!),
      copiesPerItem: eff.quantities,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: mobile ? 8 : 24,
        vertical: mobile ? 8 : 32,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: mobile ? size.width : (size.width * 0.92).clamp(720, 1100),
          maxHeight: size.height * (mobile ? 0.95 : 0.88),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(mobile),
            Expanded(
              child: mobile
                  ? ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        _buildOptionsPanel(),
                        const SizedBox(height: 12),
                        _buildPrinterPanel(),
                        const SizedBox(height: 12),
                        _buildTemplateGrid(),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 280,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _buildOptionsPanel(),
                              const SizedBox(height: 12),
                              _buildPrinterPanel(),
                            ],
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: _buildTemplateGrid()),
                      ],
                    ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool mobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PosTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(tr(_isScale
                  ? 'In tem cân (${widget.products.length})'
                  : _isSpec
                      ? 'In tem thông số (${widget.products.length})'
                      : 'In tem mã hàng (${widget.products.length})'),
              style: TextStyle(
                fontSize: mobile ? 15 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _openLabelTemplates,
            icon: const Icon(Icons.design_services_outlined, size: 18),
            label: Text(tr('Mẫu tem')),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: PosTheme.border)),
        color: Color(0xFFFAFBFC),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _printing ? null : _exportExcel,
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: Text(tr('Excel')),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _printing ? null : _printToDevice,
            icon: _printing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.print, size: 18),
            label: Text(tr('IN TEM')),
            style: FilledButton.styleFrom(
              backgroundColor: PosTheme.kiotBlue,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLabelTemplates() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PosLabelTemplatesScreen(initialType: widget.documentType),
    ));
    if (mounted) await _loadLayouts();
  }

  Future<void> _selectDesign(String id) async {
    setState(() {
      _designId = id;
      _selectedTemplate = posBarcodeLabelTemplateForDesign(_design);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDesignPref, id);
    } catch (_) {}
  }

  /// Hộp in khi dùng mẫu trình soạn tem: mẫu quyết định khổ + nội dung → chỉ còn chọn mẫu, số tem, máy in.
  Widget _buildDesignOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('Mẫu tem'),
        if (_designs.isEmpty)
          Text(tr('Mẫu dựng sẵn · ${_design.sizeLabel}'), style: const TextStyle(fontWeight: FontWeight.w600))
        else
          _dropdown<String>(
            value: _designs.any((x) => x.id == _designId) ? _designId : _designs.first.id,
            items: [for (final x in _designs) x.id],
            label: (id) {
              final x = _designs.firstWhere((d) => d.id == id);
              return '${x.name} · ${x.d.sizeLabel}${x.isDefault ? ' ★' : ''}';
            },
            onChanged: (v) => _selectDesign(v ?? ''),
          ),
        const SizedBox(height: 10),
        _fieldLabel('Số lượng in / mặt hàng'),
        TextField(
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: PosTheme.inputDecoration(label: ''),
          controller: _copiesCtrl,
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null && n >= 1 && n <= 5000) setState(() => _copies = n);
          },
        ),
        if (!_isScale) ...[
          const SizedBox(height: 10),
          _fieldLabel('Mã in trên mã vạch'),
          _dropdown<PosBarcodeCodeField>(
            value: _codeField,
            items: PosBarcodeCodeField.values,
            label: (v) => v.label,
            onChanged: (v) => setState(() => _codeField = v!),
          ),
          const SizedBox(height: 8),
          _dropdown<bool>(
            value: _expandViews,
            items: const [false, true],
            label: (v) => v ? 'Mỗi biến thể / đơn vị bán một tem' : 'Một tem mỗi mặt hàng',
            onChanged: (v) => setState(() => _expandViews = v ?? false),
          ),
          const SizedBox(height: 8),
          _dropdown<String>(
            value: _priceListId ?? '',
            items: ['', for (final l in _priceLists) l.id],
            label: (id) => id.isEmpty
                ? 'Giá trên tem: giá bán'
                : 'Giá trên tem: ${_priceLists.where((l) => l.id == id).map((l) => l.name).firstOrNull ?? id}',
            onChanged: (v) => setState(() => _priceListId = (v ?? '').isEmpty ? null : v),
          ),
        ],
      ],
    );
  }

  /// Xem trước tem theo mẫu đang chọn với hàng đầu tiên (đúng bộ vẽ khi in).
  Widget _buildDesignPreview() {
    final d = _design;
    final t = posBarcodeLabelTemplateForDesign(d);
    final p = widget.products.first;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(tr('Xem trước: ${_designs.where((x) => x.id == _designId).firstOrNull?.name ?? 'Mẫu dựng sẵn'} · ${d.sizeLabel}'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: PosTheme.kiotBlue)),
          ),
          TextButton.icon(
            onPressed: _printing ? null : () => _preview(t),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: Text(tr('Xem bản in (PDF)')),
          ),
          TextButton.icon(
            onPressed: _openLabelTemplates,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(tr('Sửa mẫu')),
          ),
        ]),
        Text(tr('${p.name}${widget.products.length > 1 ? ' (và ${widget.products.length - 1} hàng khác)' : ''}'),
            style: const TextStyle(fontSize: 11.5, color: PosTheme.textSecondary)),
        const SizedBox(height: 12),
        FutureBuilder(
          key: ValueKey('$_designId|$_codeField|${p.id}'),
          future: PosLabelDesignPainter.renderPng(d, posBarcodeLabelData(p, _options(t)), pxPerMm: 10),
          builder: (context, snap) {
            final png = snap.data;
            return LayoutBuilder(builder: (context, c) {
              final scale = (c.maxWidth / d.widthMm).clamp(1.0, 9.0);
              return Container(
                width: d.widthMm * scale,
                height: d.heightMm * scale,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: PosTheme.border),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: png == null ? const SizedBox.shrink() : Image.memory(png, fit: BoxFit.fill),
              );
            });
          },
        ),
        const SizedBox(height: 10),
        Text(tr('Khổ in theo mẫu: ${d.sizeLabel}. Máy tem cần nạp đúng cuộn tem khổ này.'),
            style: const TextStyle(fontSize: 11.5, color: PosTheme.textSecondary)),
      ]),
    );
  }

  Widget _buildOptionsPanel() => _buildDesignOptions();

  Widget _buildPrinterPanel() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: ExpansionTile(
        initiallyExpanded: _printerExpanded || _labelPrinter.enabled,
        onExpansionChanged: (v) => setState(() => _printerExpanded = v),
        title: Text(tr('Máy in tem nhãn'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          tr(_labelPrinter.enabled
              ? '${_labelPrinter.connectionType.label} · ${_labelPrinter.protocol.label}'
              : 'Bluetooth, LAN, USB — TSPL / ESC/POS'),
          style: const TextStyle(fontSize: 11),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Dùng máy in tem'), style: TextStyle(fontSize: 13)),
                  value: _labelPrinter.enabled,
                  activeColor: PosTheme.kiotBlue,
                  onChanged: (v) =>
                      setState(() => _labelPrinter = _labelPrinter.copyWith(enabled: v)),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: PosThermalConnectionType.values.map((t) {
                    if (t == PosThermalConnectionType.sunmi && kIsWeb) {
                      return const SizedBox.shrink();
                    }
                    final selected = _labelPrinter.connectionType == t;
                    return ChoiceChip(
                      label: Text(tr(t.label), style: const TextStyle(fontSize: 11)),
                      selected: selected,
                      selectedColor: PosTheme.kiotBlueLight,
                      onSelected: (_) => setState(
                        () => _labelPrinter = _labelPrinter.copyWith(connectionType: t),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _labelPrinter.protocol.key,
                  decoration: InputDecoration(
                    labelText: tr('Giao thức'),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: PosLabelPrinterProtocol.values
                      .map((p) => DropdownMenuItem(value: p.key, child: Text(tr(p.label))))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _labelPrinter = _labelPrinter.copyWith(
                          protocol: PosLabelPrinterProtocol.fromKey(v),
                        ));
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(tr('Khe giấy (mm)'), style: TextStyle(fontSize: 12)),
                    const Spacer(),
                    DropdownButton<double>(
                      value: [2.0, 3.0, 4.0].contains(_labelPrinter.gapMm)
                          ? _labelPrinter.gapMm
                          : 2.0,
                      items: [
                        DropdownMenuItem(value: 2.0, child: Text(tr('2 mm'))),
                        DropdownMenuItem(value: 3.0, child: Text(tr('3 mm'))),
                        DropdownMenuItem(value: 4.0, child: Text(tr('4 mm'))),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _labelPrinter = _labelPrinter.copyWith(gapMm: v));
                      },
                    ),
                  ],
                ),
                if (_labelPrinter.connectionType ==
                    PosThermalConnectionType.bluetooth) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Máy Bluetooth'), style: TextStyle(fontSize: 12)),
                    subtitle: Text(
                      tr(_labelPrinter.bluetoothName?.isNotEmpty == true
                          ? '${_labelPrinter.bluetoothName}'
                          : 'Chưa chọn'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: _pickBluetoothPrinter,
                  ),
                ],
                if (_labelPrinter.connectionType == PosThermalConnectionType.lan) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _lanHostCtrl,
                    decoration: InputDecoration(
                      labelText: tr('IP máy in tem'),
                      hintText: tr('192.168.1.100'),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _lanPortCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr('Cổng (9100)'),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _printing ? null : _testLabelPrinter,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: Text(tr('In thử tem mẫu')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBluetoothPrinter() async {
    if (_btDevices.isEmpty) {
      _btDevices = await PosThermalPrinterService.listBluetoothDevices();
    }
    if (!mounted) return;
    if (_btDevices.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không có máy in',
        message: tr('Ghép máy in Bluetooth trong Cài đặt Android'),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(tr('Chọn máy in tem'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            ..._btDevices.map(
              (d) => ListTile(
                title: Text(tr(d['name'] ?? 'Máy in')),
                subtitle: Text(tr(d['address'] ?? '')),
                onTap: () {
                  setState(() {
                    _labelPrinter = _labelPrinter.copyWith(
                      bluetoothName: d['name'],
                      bluetoothAddress: d['address'],
                    );
                  });
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(tr(text), style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: PosTheme.inputDecoration(label: ''),
      items: items
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(tr(label(e)), style: const TextStyle(fontSize: 12)),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildTemplateGrid() => _buildDesignPreview();
}
