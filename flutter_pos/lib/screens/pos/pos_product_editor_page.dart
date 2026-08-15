import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/pos_product.dart';
import '../../models/pos_sell_industry.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/image_source_picker.dart';
import '../../utils/pos_product_editor_prefs.dart';
import '../../utils/pos_qty_rules.dart';
import '../../utils/pos_combo_stock.dart';
import '../../widgets/notification_overlay.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;
import '../../utils/number_formatter.dart';
import '../../widgets/pos/pos_catalog_manage.dart';
import '../../widgets/pos/pos_supplier_form_dialog.dart';
import '../../widgets/pos/pos_product_image.dart';
import '../../widgets/pos/pos_unit_attribute_setup_dialog.dart';
import '../../widgets/pos/pos_product_unit_view.dart';
import '../../widgets/pos/pos_combo_component_picker.dart';
import '../../widgets/pos/pos_sale_quick_notes_widgets.dart';
import '../../widgets/pos/pos_product_editor_sections_dialog.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos_barcode_scanner.dart';
import 'pos_topping_groups_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

class PosProductEditorPage extends StatefulWidget {
  const PosProductEditorPage({
    super.key,
    required this.productType,
    this.product,
    this.templateProduct,
    this.openUnitSetup = false,
    this.unitSetupAddMore = false,
    this.unitSetupFocusVariantId,
  });

  final PosProductType productType;
  final PosProduct? product;
  /// Sao chép: m? form thêm m?i, di?n s?n t? s?n ph?m ngu?n.
  final PosProduct? templateProduct;
  /// M? th?ng dialog thi?t l?p don v?/thu?c tính sau khi n?p xong.
  final bool openUnitSetup;
  /// Chu?n b? nh?p thêm giá tr? thu?c tính (hàng cùng lo?i).
  final bool unitSetupAddMore;
  /// M? dialog thi?t l?p và bôi d?m hàng cùng lo?i c?n s?a.
  final String? unitSetupFocusVariantId;

  /// M? editor: hàng hóa = dialog KiotViet; d?ch v?/combo = full page.
  static Future<bool?> open(
    BuildContext context, {
    required PosProductType productType,
    PosProduct? product,
    PosProduct? templateProduct,
    bool openUnitSetup = false,
    bool unitSetupAddMore = false,
    String? unitSetupFocusVariantId,
  }) {
    final page = PosProductEditorPage(
      productType: productType,
      product: product,
      templateProduct: templateProduct,
      openUnitSetup: openUnitSetup,
      unitSetupAddMore: unitSetupAddMore,
      unitSetupFocusVariantId: unitSetupFocusVariantId,
    );
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => page,
    );
  }

  /// M? th?ng dialog thi?t l?p don v?/thu?c tính d? s?a m?t hàng cùng lo?i (không m? form cha).
  static Future<bool?> openVariantUnitSetup(
    BuildContext context, {
    required PosProduct product,
    required PosProductVariant variant,
  }) async {
    final api = ApiService();
    final detailRes = await api.getPosProduct(product.id);
    if (detailRes['isSuccess'] != true || detailRes['data'] is! Map) {
      return false;
    }
    final full = PosProduct.fromJson(detailRes['data'] as Map<String, dynamic>);

    final variantsRes = await api.getPosProductVariants(product.id);
    final variants = variantsRes['isSuccess'] == true && variantsRes['data'] is List
        ? (variantsRes['data'] as List)
            .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
            .toList()
        : <PosProductVariant>[];

    final attrRows = _attributeRowsForUnitSetup(
      full.attributes ?? [],
      variants,
    );

    if (!context.mounted) return false;
    final result = await showUnitAttributeSetupDialog(
      context,
      input: UnitAttributeSetupInput(
        baseUnitName: full.baseUnitName.isEmpty ? 'Cái' : full.baseUnitName,
        basePrice: full.basePrice,
        costPrice: full.costPrice,
        baseDirectSale: full.isDirectSale,
        productCode: full.productCode.isEmpty ? null : full.productCode,
        barcode: full.barcode,
        extraUnits: (full.units ?? []).where((u) => !u.isBaseUnit).toList(),
        attributeRows: attrRows,
        variants: variants,
        productId: full.id,
        productPatch: {
          'name': full.name,
          'categoryId': full.categoryId,
          'brandId': full.brandId,
          'storageLocationId': full.storageLocationId,
          'supplierId': full.supplierId,
          'productType': 0,
          'description': full.description ?? '',
          'costPrice': full.costPrice,
          'basePrice': full.basePrice,
          'onHandQty': full.onHandQty,
          'reservedQty': full.reservedQty,
          'minStockQty': full.minStockQty,
          'maxStockQty': full.maxStockQty,
          if (full.weight != null) 'weight': full.weight,
          'weightUnit': full.weightUnit,
          'isDirectSale': full.isDirectSale,
          'isFavorite': full.isFavorite,
        },
        focusVariantId: variant.id,
      ),
    );
    return result != null;
  }

  static List<UnitAttributeRowInput> _attributeRowsForUnitSetup(
    List<PosProductAttribute> attributes,
    List<PosProductVariant> variants,
  ) {
    final fromVariants = <String, Set<String>>{};
    for (final v in variants) {
      final raw = v.attributeJson;
      if (raw == null || raw.isEmpty) continue;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in map.entries) {
          if (e.key.startsWith('_')) continue;
          final val = '${e.value}'.trim();
          if (val.isEmpty) continue;
          fromVariants.putIfAbsent(e.key, () => {}).add(val);
        }
      } catch (_) {}
    }
    if (fromVariants.isNotEmpty) {
      return fromVariants.entries
          .map((e) => UnitAttributeRowInput(
                attributeName: e.key,
                valuesText: e.value.join(', '),
              ))
          .toList();
    }
    final grouped = <String, UnitAttributeRowInput>{};
    for (final a in attributes) {
      final name = a.attributeName.trim();
      if (name.isEmpty) continue;
      final existing = grouped[name];
      if (existing != null) {
        grouped[name] = UnitAttributeRowInput(
          attributeId: a.attributeId,
          attributeName: name,
          valuesText: '${existing.valuesText}, ${a.value}',
        );
      } else {
        grouped[name] = UnitAttributeRowInput(
          attributeId: a.attributeId,
          attributeName: name,
          valuesText: a.value,
        );
      }
    }
    return grouped.values.toList();
  }

  @override
  State<PosProductEditorPage> createState() => _PosProductEditorPageState();
}

class _VariantAttrRow {
  String attributeId = '';
  String attributeName = '';
  String valuesText = '';

  Map<String, dynamic> toGenerateJson() => {
        'attributeId': attributeId.isEmpty ? null : attributeId,
        'attributeName': attributeName.trim(),
        'values': valuesText
            .split(RegExp(r'[,;]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      };
}

class _PosProductEditorPageState extends State<PosProductEditorPage>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  static final _inputMoneyFmt = NumberFormat('#,###', 'vi_VN');
  late TabController _tabs;
  bool _saving = false;
  bool _loading = true;
  String? _imageBase64;
  String? _imagePreviewUrl;
  Uint8List? _pendingImageBytes;
  String? _pendingImageName;

  late final TextEditingController _codeCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _minStockCtrl;
  late final TextEditingController _maxStockCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _descCtrl;
  List<String> _saleQuickNotes = [];
  bool _isTopping = false;
  bool _allowToppings = false;
  bool _autoOpenToppingPopup = true;
  List<PosProductToppingOption> _toppingOptions = [];
  List<String> _toppingGroupIds = [];
  List<PosProductToppingGroup> _availableToppingGroups = [];
  late final TextEditingController _unitCtrl;

  String? _categoryId;
  String? _brandId;
  String? _locationId;
  String? _supplierId;
  bool _directSale = true;
  String _weightUnit = 'g';
  double _vatRate = 8;
  bool _vatExempt = false;
  late final TextEditingController _warrantyMonthsCtrl;
  late final TextEditingController _expiryWarningDaysCtrl;
  bool _requiresSerial = false;
  bool _allowDecimalQty = false;
  bool _trackExpiry = false;
  PosServiceBillingMode _serviceBillingMode = PosServiceBillingMode.flat;
  late final TextEditingController _minBillMinutesCtrl;
  late final TextEditingController _billRoundMinutesCtrl;
  late final TextEditingController _graceMinutesCtrl;
  late final TextEditingController _roundAfterMinutesCtrl;
  late final TextEditingController _defaultDurationMinutesCtrl;
  late final TextEditingController _sessionPackCountCtrl;
  late final TextEditingController _openingFeeCtrl;
  late final TextEditingController _openingMinutesCtrl;
  late final TextEditingController _sessionPackValidDaysCtrl;

  List<PosCatalogItem> _categories = [];
  List<PosCatalogItem> _brands = [];
  List<PosCatalogItem> _locations = [];
  List<PosCatalogItem> _suppliers = [];
  List<PosProductUnit> _units = [];
  final List<PosProductAttribute> _attributeValues = [];
  List<PosComboLine> _comboLines = [];
  List<PosProductVariant> _variants = [];
  late PosProductType _productType;
  final List<_VariantAttrRow> _variantAttrs = [];
  bool _generatingVariants = false;
  Set<PosProductEditorSection> _editorSections = defaultPosProductEditorSections();
  bool _editorPrefsLoaded = false;

  PosProductType get _type => _productType;
  bool get _isGoods => _type == PosProductType.goods;
  bool get _isService => _type == PosProductType.service;
  bool get _isCombo => _type == PosProductType.combo;
  String get _autoCodeHint => _isService
      ? 'DV00001…'
      : (_isCombo ? 'CB00001…' : 'HH00001…');
  bool get _isEditing => widget.product != null;
  bool get _hasVariants => _variants.isNotEmpty;
  bool get _usesSharedUnitStock =>
      _variants.isEmpty || _variants.every(variantIsBaseUnitOnly);
  bool get _canEditMainStock => !_hasVariants || _usesSharedUnitStock;

  String get _stockFieldLabel {
    if (!_hasVariants) return 'T?n kho';
    if (_usesSharedUnitStock) {
      final unit = _unitCtrl.text.trim();
      return unit.isEmpty ? 'T?n kho (don v? co b?n)' : 'T?n kho ($unit)';
    }
    return 'T?n kho (t?ng các lo?i)';
  }

  String get _stockFieldHint => _canEditMainStock
      ? 'Nh?p theo don v? nh? nh?t; ÐVT khác t? quy d?i khi hi?n th?'
      : 'S?a t?n t?ng bi?n th? ? b?ng bên du?i ho?c dùng Nh?p kho';
  bool get _isCopyFromTemplate =>
      widget.templateProduct != null && widget.product == null;

  String get _pageTitle {
    if (_isCopyFromTemplate) {
      return switch (_type) {
        PosProductType.goods => 'Thêm hàng hóa (sao chép)',
        PosProductType.service => 'Thêm d?ch v? (sao chép)',
        PosProductType.combo => 'Thêm combo (sao chép)',
      };
    }
    if (!_isEditing) {
      return switch (_type) {
        PosProductType.goods => 'T?o hàng hóa',
        PosProductType.service => 'T?o d?ch v?',
        PosProductType.combo => 'T?o combo - dóng gói',
      };
    }
    return switch (_type) {
      PosProductType.goods => 'S?a hàng hóa',
      PosProductType.service => 'S?a d?ch v?',
      PosProductType.combo => 'S?a combo',
    };
  }

  List<String> get _tabLabels => _showSection(PosProductEditorSection.description)
      ? const ['Thông tin', 'Mô t?']
      : const ['Thông tin'];

  bool _showSection(PosProductEditorSection section) {
    if (_editorSections.contains(section)) return true;
    return _sectionForcedByProduct(section);
  }

  /// Khi s?a hàng dã có d? li?u nâng cao — v?n hi?n m?c dó dù prefs t?t.
  bool _sectionForcedByProduct(PosProductEditorSection section) {
    switch (section) {
      case PosProductEditorSection.codes:
        return _codeCtrl.text.trim().isNotEmpty ||
            _barcodeCtrl.text.trim().isNotEmpty;
      case PosProductEditorSection.brand:
        return _brandId != null && _brandId!.isNotEmpty;
      case PosProductEditorSection.supplier:
        return _supplierId != null && _supplierId!.isNotEmpty;
      case PosProductEditorSection.vat:
        return _vatExempt || (_vatRate > 0 && _vatRate != 8);
      case PosProductEditorSection.warranty:
        return _requiresSerial ||
            _allowDecimalQty ||
            _trackExpiry ||
            _warrantyMonthsCtrl.text.trim().isNotEmpty;
      case PosProductEditorSection.stockLimits:
        final min = double.tryParse(_minStockCtrl.text.trim()) ?? 0;
        final max = double.tryParse(_maxStockCtrl.text.trim()) ?? 0;
        return min > 0 || (max > 0 && max < 999999999);
      case PosProductEditorSection.locationWeight:
        return (_locationId != null && _locationId!.isNotEmpty) ||
            _weightCtrl.text.trim().isNotEmpty;
      case PosProductEditorSection.unitsVariants:
        return _units.any((u) => !u.isBaseUnit) ||
            _variants.isNotEmpty ||
            _attributeValues.isNotEmpty ||
            _variantAttrs.isNotEmpty;
      case PosProductEditorSection.serviceBilling:
        return _serviceBillingMode != PosServiceBillingMode.flat ||
            (int.tryParse(_sessionPackCountCtrl.text.trim()) ?? 0) > 0 ||
            _defaultDurationMinutesCtrl.text.trim().isNotEmpty ||
            _openingFeeCtrl.text.trim().isNotEmpty ||
            _openingMinutesCtrl.text.trim().isNotEmpty ||
            _sessionPackValidDaysCtrl.text.trim().isNotEmpty;
      case PosProductEditorSection.description:
        return _descCtrl.text.trim().isNotEmpty || _saleQuickNotes.isNotEmpty;
    }
  }

  Future<void> _loadEditorSectionPrefs() async {
    final sections = await loadPosProductEditorSections();
    if (!mounted) return;
    setState(() {
      _editorSections = sections;
      _editorPrefsLoaded = true;
      _syncTabController();
    });
  }

  void _syncTabController() {
    final labels = _tabLabels;
    final idx = _tabs.index.clamp(0, labels.length - 1);
    if (_tabs.length != labels.length) {
      _tabs.dispose();
      _tabs = TabController(length: labels.length, vsync: this, initialIndex: idx);
    }
  }

  Future<void> _openEditorSectionsSettings() async {
    final result = await showPosProductEditorSectionsDialog(
      context,
      initial: _editorSections,
    );
    if (result == null || !mounted) return;
    setState(() {
      _editorSections = result;
      _syncTabController();
    });
  }

  double get _comboComponentsSum => _comboLines.fold(
        0.0,
        (s, c) => s + c.componentBasePrice * c.qty,
      );

  @override
  void initState() {
    super.initState();
    _productType = widget.product?.productType ??
        widget.templateProduct?.productType ??
        widget.productType;
    final p = widget.product ?? widget.templateProduct;
    // Ph?i t?o tru?c TabController: _tabLabels ? _showSection(description)
    // d?c _descCtrl / _saleQuickNotes.
    _descCtrl = TextEditingController(text: tr(p?.description ?? ''));
    _saleQuickNotes = List<String>.from(p?.saleQuickNotes ?? const []);
    _isTopping = p?.isTopping ?? false;
    _allowToppings = p?.allowToppings ?? false;
    _autoOpenToppingPopup = p?.autoOpenToppingPopup ?? true;
    _toppingOptions = List<PosProductToppingOption>.from(p?.toppingOptions ?? const []);
    _toppingGroupIds = List<String>.from(p?.toppingGroupIds ?? const []);
    unawaited(_loadToppingGroups());
    _tabs = TabController(length: _tabLabels.length, vsync: this);
    final copyName = p != null && _isCopyFromTemplate
        ? (p.name.trim().endsWith('(b?n sao)')
            ? p.name.trim()
            : '${p.name.trim()} (b?n sao)')
        : (p?.name ?? '');
    _codeCtrl = TextEditingController(
        text: tr(_isCopyFromTemplate ? '' : (p?.productCode ?? '')));
    _barcodeCtrl = TextEditingController(
        text: tr(_isCopyFromTemplate ? '' : (p?.barcode ?? '')));
    _nameCtrl = TextEditingController(text: tr(copyName));
    _costCtrl = TextEditingController(
        text: tr(_fmtInputMoney(p?.costPrice ?? 0)));
    _priceCtrl = TextEditingController(
        text: tr(_fmtInputMoney(p?.basePrice ?? 0)));
    _stockCtrl = TextEditingController(
        text: tr(p != null ? p.onHandQty.toStringAsFixed(0) : '0'));
    _minStockCtrl = TextEditingController(
        text: tr(p != null ? p.minStockQty.toStringAsFixed(0) : '0'));
    _maxStockCtrl = TextEditingController(
        text: tr(p != null
            ? p.maxStockQty.toStringAsFixed(0)
            : (_isGoods ? '999999999' : '0')));
    _weightCtrl = TextEditingController(
        text: tr(p?.weight != null ? p!.weight!.toStringAsFixed(0) : ''));
    _unitCtrl = TextEditingController(text: tr(p?.baseUnitName ?? 'Cái'));
    _categoryId = p?.categoryId;
    _brandId = p?.brandId;
    _locationId = p?.storageLocationId;
    _supplierId = p?.supplierId;
    _directSale = p?.isDirectSale ?? true;
    _weightUnit = p?.weightUnit ?? 'g';
    _vatRate = p?.vatExempt == true ? 0 : (p?.vatRate ?? 8);
    _vatExempt = p?.vatExempt ?? false;
    _warrantyMonthsCtrl = TextEditingController(
      text: tr(p?.warrantyMonths != null && p!.warrantyMonths! > 0
          ? '${p.warrantyMonths}'
          : ''),
    );
    _requiresSerial = p?.requiresSerial ?? false;
    _allowDecimalQty = p?.allowDecimalQty ?? false;
    _trackExpiry = p?.trackExpiry ?? false;
    _expiryWarningDaysCtrl = TextEditingController(
      text: tr('${p?.expiryWarningDays ?? 30}'),
    );
    _serviceBillingMode = PosServiceBillingMode.parse(p?.serviceBillingMode);
    _minBillMinutesCtrl = TextEditingController(
      text: tr(p?.minBillMinutes != null ? '${p!.minBillMinutes}' : ''),
    );
    _billRoundMinutesCtrl = TextEditingController(
      text: tr(p?.billRoundMinutes != null ? '${p!.billRoundMinutes}' : ''),
    );
    _graceMinutesCtrl = TextEditingController(
      text: tr(p?.graceMinutes != null ? '${p!.graceMinutes}' : ''),
    );
    _roundAfterMinutesCtrl = TextEditingController(
      text: tr(p?.roundAfterMinutes != null ? '${p!.roundAfterMinutes}' : ''),
    );
    _defaultDurationMinutesCtrl = TextEditingController(
      text: tr(p?.defaultDurationMinutes != null
          ? '${p!.defaultDurationMinutes}'
          : ''),
    );
    _sessionPackCountCtrl = TextEditingController(
      text: tr((p?.sessionPackCount ?? 0) > 0 ? '${p!.sessionPackCount}' : ''),
    );
    _openingFeeCtrl = TextEditingController(
      text: tr((p?.openingFee ?? 0) > 0 ? _fmtInputMoney(p!.openingFee) : ''),
    );
    _openingMinutesCtrl = TextEditingController(
      text: tr((p?.openingMinutes ?? 0) > 0 ? '${p!.openingMinutes}' : ''),
    );
    _sessionPackValidDaysCtrl = TextEditingController(
      text: tr((p?.sessionPackValidDays ?? 0) > 0
          ? '${p!.sessionPackValidDays}'
          : ''),
    );
    _imagePreviewUrl = p?.imageUrl;
    if (p?.units != null) _units = List.from(p!.units!);
    if (p?.attributes != null) _attributeValues.addAll(p!.attributes!);
    unawaited(_loadEditorSectionPrefs());
    _initData();
  }

  Future<void> _initData() async {
    final templateId = widget.templateProduct?.id;
    await Future.wait([
      _loadCatalogs(),
      if (_isEditing) _loadProductDetail(widget.product!.id),
      if (_isCopyFromTemplate && templateId != null)
        _loadTemplateExtras(templateId),
    ]);
    if (mounted) {
      setState(() {
        _loading = false;
        _syncTabController();
      });
    }
    if (mounted && widget.openUnitSetup && _isGoods) {
      await _openUnitAttributeSetup(addMore: widget.unitSetupAddMore);
    }
  }

  /// N?p don v?, thu?c tính, thành ph?n combo t? s?n ph?m ngu?n khi sao chép.
  Future<void> _loadTemplateExtras(String sourceId) async {
    final res = await _api.getPosProduct(sourceId);
    if (!mounted || res['isSuccess'] != true) return;
    final data = PosProduct.fromJson(res['data'] as Map<String, dynamic>);
    setState(() {
      if (data.units != null) _units = List.from(data.units!);
      _attributeValues
        ..clear()
        ..addAll(data.attributes ?? []);
      _supplierId = data.supplierId ?? _supplierId;
      _imagePreviewUrl = data.imageUrl ?? _imagePreviewUrl;
    });
    if (_isCombo) {
      final comboRes = await _api.getPosComboLines(sourceId);
      if (mounted && comboRes['isSuccess'] == true && comboRes['data'] is List) {
        setState(() {
          _comboLines = (comboRes['data'] as List)
              .map((e) => PosComboLine.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    }
  }

  Future<void> _loadCatalogs() async {
    final results = await Future.wait([
      _api.getPosProductCategories(),
      _api.getPosProductBrands(),
      _api.getPosStorageLocations(),
      _api.getPosSuppliers(),
    ]);
    if (!mounted) return;
    if (results[0]['isSuccess'] == true && results[0]['data'] is List) {
      _categories = (results[0]['data'] as List)
          .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (results[1]['isSuccess'] == true && results[1]['data'] is List) {
      _brands = (results[1]['data'] as List)
          .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (results[2]['isSuccess'] == true && results[2]['data'] is List) {
      _locations = (results[2]['data'] as List)
          .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (results[3]['isSuccess'] == true && results[3]['data'] is List) {
      _suppliers = (results[3]['data'] as List)
          .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _loadProductDetail(String id) async {
    final res = await _api.getPosProduct(id);
    if (!mounted || res['isSuccess'] != true) return;
    final data = PosProduct.fromJson(res['data'] as Map<String, dynamic>);
    setState(() {
      _productType = data.productType;
      if (data.units != null) _units = List.from(data.units!);
      _attributeValues
        ..clear()
        ..addAll(data.attributes ?? []);
      _syncVariantAttrsFromProductAttributes();
      _supplierId = data.supplierId;
      _saleQuickNotes = List<String>.from(data.saleQuickNotes);
      _isTopping = data.isTopping;
      _allowToppings = data.allowToppings;
      _autoOpenToppingPopup = data.autoOpenToppingPopup;
      _toppingOptions =
          List<PosProductToppingOption>.from(data.toppingOptions);
      _toppingGroupIds = List<String>.from(data.toppingGroupIds);
      _vatRate = data.vatExempt ? 0 : data.vatRate;
      _vatExempt = data.vatExempt;
      _warrantyMonthsCtrl.text =
          data.warrantyMonths != null && data.warrantyMonths! > 0
              ? '${data.warrantyMonths}'
              : '';
      _requiresSerial = data.requiresSerial;
      _allowDecimalQty = data.allowDecimalQty;
      _trackExpiry = data.trackExpiry;
      _expiryWarningDaysCtrl.text = '${data.expiryWarningDays}';
      _serviceBillingMode =
          PosServiceBillingMode.parse(data.serviceBillingMode);
      _minBillMinutesCtrl.text =
          data.minBillMinutes != null ? '${data.minBillMinutes}' : '';
      _billRoundMinutesCtrl.text =
          data.billRoundMinutes != null ? '${data.billRoundMinutes}' : '';
      _graceMinutesCtrl.text =
          data.graceMinutes != null ? '${data.graceMinutes}' : '';
      _roundAfterMinutesCtrl.text =
          data.roundAfterMinutes != null ? '${data.roundAfterMinutes}' : '';
      _defaultDurationMinutesCtrl.text = data.defaultDurationMinutes != null
          ? '${data.defaultDurationMinutes}'
          : '';
      _sessionPackCountCtrl.text =
          data.sessionPackCount > 0 ? '${data.sessionPackCount}' : '';
      _openingFeeCtrl.text =
          data.openingFee > 0 ? _fmtInputMoney(data.openingFee) : '';
      _openingMinutesCtrl.text =
          (data.openingMinutes ?? 0) > 0 ? '${data.openingMinutes}' : '';
      _sessionPackValidDaysCtrl.text = data.sessionPackValidDays > 0
          ? '${data.sessionPackValidDays}'
          : '';
    });
    if (_isCombo) {
      final comboRes = await _api.getPosComboLines(id);
      if (mounted && comboRes['isSuccess'] == true && comboRes['data'] is List) {
        setState(() {
          _comboLines = (comboRes['data'] as List)
              .map((e) => PosComboLine.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    }
    if (_isGoods) {
      await _loadVariants(id);
    }
  }

  Future<void> _loadVariants(String productId, {bool rebuildAttrs = true}) async {
    final res = await _api.getPosProductVariants(productId);
    if (!mounted || res['isSuccess'] != true || res['data'] is! List) return;
    setState(() {
      _variants = (res['data'] as List)
          .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
          .toList();
      if (rebuildAttrs && _variantAttrs.isEmpty) {
        _rebuildVariantAttrsFromVariants();
      }
      if (_variants.isNotEmpty && !_usesSharedUnitStock) {
        final sum = _variants.fold(0.0, (s, v) => s + v.onHandQty);
        _stockCtrl.text = sum.toStringAsFixed(0);
      }
    });
  }

  /// N?p dòng thu?c tính t? schema dã luu (1 value = "a, b, c" trên API).
  void _syncVariantAttrsFromProductAttributes() {
    if (_attributeValues.isEmpty) return;
    final grouped = <String, _VariantAttrRow>{};
    for (final a in _attributeValues) {
      final name = a.attributeName.trim();
      if (name.isEmpty) continue;
      final row = grouped.putIfAbsent(name, () {
        final r = _VariantAttrRow();
        r.attributeId = a.attributeId;
        r.attributeName = name;
        return r;
      });
      final parts = a.value
          .split(RegExp(r'[,;]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);
      final existing = row.valuesText
          .split(RegExp(r'[,;]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      existing.addAll(parts);
      row.valuesText = existing.join(', ');
    }
    if (grouped.isEmpty) return;
    _variantAttrs
      ..clear()
      ..addAll(grouped.values);
  }

  bool _isValidGuid(String? id) {
    if (id == null || id.isEmpty) return false;
    return RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(id);
  }

  /// Khôi ph?c dòng thu?c tính t? attributeJson c?a bi?n th? (sau reload/F5).
  void _rebuildVariantAttrsFromVariants() {
    if (_variants.isEmpty) return;
    final grouped = <String, Set<String>>{};
    for (final v in _variants) {
      final raw = v.attributeJson;
      if (raw == null || raw.isEmpty) continue;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in map.entries) {
          if (e.key.startsWith('_')) continue;
          final val = '${e.value}'.trim();
          if (val.isEmpty) continue;
          grouped.putIfAbsent(e.key, () => {}).add(val);
        }
      } catch (_) {}
    }
    if (grouped.isEmpty) return;
    _variantAttrs
      ..clear()
      ..addAll(grouped.entries.map((e) {
        final row = _VariantAttrRow();
        row.attributeName = e.key;
        row.valuesText = e.value.join(', ');
        return row;
      }));
  }

  /// Ghi don v? quy d?i + bi?n th? lên server (dùng cho c? t?o m?i và s?a).
  Future<String?> _syncGoodsUnitsAndVariants(String productId) async {
    final existingRes = await _api.getPosProductUnits(productId);
    final existing = <String, PosProductUnit>{};
    if (existingRes['isSuccess'] == true && existingRes['data'] is List) {
      for (final e in existingRes['data'] as List) {
        final u = PosProductUnit.fromJson(e as Map<String, dynamic>);
        if (!u.isBaseUnit) existing[u.id] = u;
      }
    }

    final keepIds = <String>{};
    for (final u in _units.where((u) => !u.isBaseUnit)) {
      final body = u.toUpsertJson();
      if (u.id.isNotEmpty) {
        keepIds.add(u.id);
        final res = await _api.updatePosProductUnit(productId, u.id, body);
        if (res['isSuccess'] != true) {
          return res['message']?.toString() ?? 'Luu don v? quy d?i th?t b?i';
        }
      } else {
        final res = await _api.createPosProductUnit(productId, body);
        if (res['isSuccess'] != true) {
          return res['message']?.toString() ?? 'T?o don v? quy d?i th?t b?i';
        }
        final newId = (res['data'] as Map?)?['id']?.toString();
        if (newId != null && newId.isNotEmpty) keepIds.add(newId);
      }
    }
    for (final e in existing.entries) {
      if (!keepIds.contains(e.key)) {
        await _api.deletePosProductUnit(productId, e.key);
      }
    }

    final syncVariants = _variants
        .map((v) => {
              if (_isValidGuid(v.id)) 'id': v.id,
              ...v.toUpsertJson(),
              'onHandQty': v.onHandQty,
            })
        .toList();
    final syncRes =
        await _api.syncPosProductVariants(productId, syncVariants);
    if (syncRes['isSuccess'] != true) {
      return syncRes['message']?.toString() ?? 'Luu bi?n th? th?t b?i';
    }
    if (syncRes['data'] is List) {
      _variants = (syncRes['data'] as List)
          .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return null;
  }

  InputDecoration _barcodeInputDecoration({String hint = 'Nh?p mã v?ch'}) {
    return posBarcodeScanDecoration(
      PosTheme.inputDecoration(label: 'Mã v?ch', hint: hint),
      controller: _barcodeCtrl,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    _codeCtrl.dispose();
    _barcodeCtrl.dispose();
    _nameCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _minStockCtrl.dispose();
    _maxStockCtrl.dispose();
    _weightCtrl.dispose();
    _descCtrl.dispose();
    _unitCtrl.dispose();
    _warrantyMonthsCtrl.dispose();
    _expiryWarningDaysCtrl.dispose();
    _minBillMinutesCtrl.dispose();
    _billRoundMinutesCtrl.dispose();
    _graceMinutesCtrl.dispose();
    _roundAfterMinutesCtrl.dispose();
    _defaultDurationMinutesCtrl.dispose();
    _sessionPackCountCtrl.dispose();
    _openingFeeCtrl.dispose();
    _openingMinutesCtrl.dispose();
    _sessionPackValidDaysCtrl.dispose();
    super.dispose();
  }

  String _fmtInputMoney(num v) => _inputMoneyFmt.format(v);

  double _parseNum(String s) =>
      parseFormattedNumber(s)?.toDouble() ?? 0;

  Future<void> _pickImage() async {
    final picked = await pickSingleImageWithCamera(context);
    if (picked == null) return;
    if (picked.bytes.length > 2 * 1024 * 1024) {
      NotificationOverlayManager().showError(
        title: 'L?i',
        message: tr('?nh không du?c vu?t quá 2 MB'),
      );
      return;
    }
    var name = picked.name.trim();
    if (name.isEmpty) name = 'product.jpg';
    if (!name.contains('.')) name = '$name.jpg';
    setState(() {
      _pendingImageBytes = picked.bytes;
      _pendingImageName = name;
      _imageBase64 = base64Encode(picked.bytes);
      _imagePreviewUrl = null;
    });
  }

  List<Map<String, dynamic>> _attributeSchemaForSave() {
    if (_variantAttrs.isNotEmpty) {
      return _variantAttrs
          .where((a) =>
              a.attributeName.trim().isNotEmpty &&
              a.valuesText.trim().isNotEmpty)
          .map((a) => {
                if (a.attributeId.isNotEmpty) 'attributeId': a.attributeId,
                'attributeName': a.attributeName.trim(),
                'value': a.valuesText.trim(),
              })
          .toList();
    }
    return _attributeValues.map((a) => a.toInputJson()).toList();
  }

  Future<void> _save({bool createAnother = false}) async {
    if (_nameCtrl.text.trim().isEmpty) {
      NotificationOverlayManager().showError(
        title: 'L?i',
        message: _isService
            ? 'Vui lòng nh?p tên d?ch v?'
            : 'Vui lòng nh?p tên hàng',
      );
      return;
    }
    if (_categoryId == null || _categoryId!.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'L?i',
        message: tr('Vui lòng ch?n nhóm hàng'),
      );
      return;
    }
    if (_isCombo && _comboLines.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'L?i',
        message: tr('Combo c?n ít nh?t 1 hàng thành ph?n'),
      );
      return;
    }
    setState(() => _saving = true);

    final body = <String, dynamic>{
      'productCode':
          _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
      if (_isService || _isGoods || _isCombo)
        'barcode':
            _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
      'name': _nameCtrl.text.trim(),
      'categoryId': _categoryId,
      'brandId': _brandId,
      if (_isGoods) 'storageLocationId': _locationId,
      if (_isGoods || _isCombo) 'supplierId': _supplierId,
      'productType': _isService ? 1 : (_isCombo ? 2 : 0),
      'description': _descCtrl.text.trim(),
      'saleQuickNotes': _saleQuickNotes
          .map((n) => n.trim())
          .where((n) => n.isNotEmpty)
          .toList(),
      'isTopping': _isTopping,
      'allowToppings': _allowToppings && !_isTopping,
      'autoOpenToppingPopup': _autoOpenToppingPopup,
      'toppings': (_allowToppings && !_isTopping)
          ? _toppingOptions
              .map((t) => {
                    'toppingProductId': t.toppingProductId,
                    'extraPrice': t.extraPrice,
                    'sortOrder': t.sortOrder,
                  })
              .toList()
          : <Map<String, dynamic>>[],
      'toppingGroupIds': _isTopping ? <String>[] : _toppingGroupIds,
      if (!_isEditing &&
          widget.templateProduct?.imageUrl != null &&
          _pendingImageBytes == null)
        'imageUrl': widget.templateProduct!.imageUrl,
      'costPrice': _parseNum(_costCtrl.text),
      'basePrice': _parseNum(_priceCtrl.text),
      'vatRate': _vatExempt ? 0 : _vatRate,
      'vatExempt': _vatExempt,
      if (!_hasVariants || _usesSharedUnitStock)
        'onHandQty': _isCombo ? 0 : (_isService ? 0 : _parseNum(_stockCtrl.text)),
      'reservedQty': widget.product?.reservedQty ?? 0,
      if (_isGoods) ...{
        'minStockQty': _parseNum(_minStockCtrl.text),
        'maxStockQty': _parseNum(_maxStockCtrl.text),
        'weight':
            _weightCtrl.text.trim().isEmpty ? null : _parseNum(_weightCtrl.text),
        'weightUnit': _weightUnit,
        'baseUnitName':
            _unitCtrl.text.trim().isEmpty ? 'Cái' : _unitCtrl.text.trim(),
      },
      'isDirectSale': _directSale,
      'isFavorite': widget.product?.isFavorite ?? false,
      if (_isGoods) ...{
        'warrantyMonths': int.tryParse(_warrantyMonthsCtrl.text.trim()),
        'requiresSerial': _requiresSerial,
        'allowDecimalQty': _allowDecimalQty,
        'trackExpiry': _trackExpiry,
        'expiryWarningDays':
            int.tryParse(_expiryWarningDaysCtrl.text.trim()) ?? 30,
        'attributes': _attributeSchemaForSave(),
      },
      if (_isService) ...{
        'serviceBillingMode': _serviceBillingMode.apiValue,
        'minBillMinutes': int.tryParse(_minBillMinutesCtrl.text.trim()),
        'billRoundMinutes': int.tryParse(_billRoundMinutesCtrl.text.trim()),
        'graceMinutes': int.tryParse(_graceMinutesCtrl.text.trim()),
        'roundAfterMinutes': int.tryParse(_roundAfterMinutesCtrl.text.trim()),
        'defaultDurationMinutes':
            int.tryParse(_defaultDurationMinutesCtrl.text.trim()),
        'sessionPackCount':
            int.tryParse(_sessionPackCountCtrl.text.trim()) ?? 0,
        'openingFee': _parseNum(_openingFeeCtrl.text),
        'openingMinutes': int.tryParse(_openingMinutesCtrl.text.trim()),
        'sessionPackValidDays':
            int.tryParse(_sessionPackValidDaysCtrl.text.trim()) ?? 0,
      },
    };

    final res = _isEditing
        ? await _api.updatePosProduct(widget.product!.id, body)
        : await _api.createPosProduct(body);

    if (res['isSuccess'] == true && _pendingImageBytes != null) {
      final productId = _isEditing
          ? widget.product!.id
          : (res['data'] as Map<String, dynamic>?)?['id']?.toString();
      if (productId != null) {
        final imgRes = await _api.uploadPosProductImage(
          productId,
          _pendingImageBytes!,
          _pendingImageName ?? 'product.jpg',
        );
        if (imgRes['isSuccess'] != true) {
          if (!mounted) return;
          setState(() => _saving = false);
          NotificationOverlayManager().showError(
            title: 'Luu ?nh th?t b?i',
            message: imgRes['message']?.toString() ??
                'Hàng hóa dã luu nhung ?nh chua du?c g?n. Vui lòng th? l?i.',
          );
          return;
        }
        final imgData = imgRes['data'];
        if (imgData is Map) {
          final savedPath = imgData['imageUrl'] ?? imgData['ImageUrl'];
          if (savedPath != null) {
            _imagePreviewUrl = savedPath.toString();
          }
        }
        _pendingImageBytes = null;
        _pendingImageName = null;
        _imageBase64 = null;
      }
    }

    if (res['isSuccess'] == true && _isGoods) {
      final productId = _isEditing
          ? widget.product!.id
          : (res['data'] as Map<String, dynamic>?)?['id']?.toString();
      if (productId != null) {
        final syncErr = await _syncGoodsUnitsAndVariants(productId);
        if (syncErr != null) {
          if (!mounted) return;
          setState(() => _saving = false);
          NotificationOverlayManager().showError(
            title: 'Luu chua hoàn t?t',
            message: syncErr,
          );
          return;
        }
      }
    }

    if (res['isSuccess'] == true && _isCombo) {
      final productId = widget.product?.id ??
          (res['data'] as Map<String, dynamic>?)?['id']?.toString();
      if (productId != null) {
        final comboRes = await _api.savePosComboLines(
          productId,
          _comboLines
              .map((c) => {
                    'componentProductId': c.componentProductId,
                    'qty': c.qty,
                  })
              .toList(),
        );
        if (comboRes['isSuccess'] != true) {
          if (!mounted) return;
          setState(() => _saving = false);
          NotificationOverlayManager().showError(
            title: 'Luu thành ph?n combo th?t b?i',
            message: comboRes['message']?.toString() ??
                'Hàng hóa dã luu nhung thành ph?n combo chua du?c g?n. Vui lòng th? l?i.',
          );
          return;
        }
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      ScreenRefreshNotifier.refreshPosSellProductGrid();
      NotificationOverlayManager().showSuccess(
        title: 'Thành công',
        message: _isEditing ? 'Ðã luu hàng hóa' : 'Ðã t?o hàng hóa',
      );
      if (createAnother && !_isEditing) {
        _resetForAnother();
        setState(() {});
      } else {
        Navigator.pop(context, true);
      }
    } else {
      NotificationOverlayManager().showError(
        title: 'L?i',
        message: res['message']?.toString() ?? 'Luu th?t b?i',
      );
    }
  }

  Future<void> _quickCreateCategory() async {
    final nameCtrl = TextEditingController();
    String? parentId;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr('T?o m?i nhóm hàng')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: PosTheme.inputDecoration(label: 'Tên nhóm hàng'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: parentId,
                decoration: PosTheme.inputDecoration(
                  label: 'Nhóm cha (tu? ch?n)',
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('— Không —'))),
                  ..._categories.map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(tr(c.name))),
                  ),
                ],
                onChanged: (v) => setDlg(() => parentId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('H?y')),
            ),
            FilledButton(
              style: PosTheme.filledButtonStyle,
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
              child: Text(tr('Luu')),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    if (name == null || name.isEmpty) return;
    final res = await _api.createPosProductCategory(name, parentId: parentId);
    if (res['isSuccess'] == true && res['data'] != null && mounted) {
      final item =
          PosCatalogItem.fromJson(res['data'] as Map<String, dynamic>);
      setState(() {
        _categories.add(item);
        _categoryId = item.id;
      });
    }
  }

  Future<void> _manageCatalog(PosCatalogKind kind) async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canEdit = perm.canEdit('PosProducts');
    final canDelete = perm.canDelete('PosProducts');
    if (!canEdit && !canDelete) {
      NotificationOverlayManager().showError(
        title: 'L?i',
        message: tr('B?n không có quy?n qu?n lý danh m?c'),
      );
      return;
    }

    List<PosCatalogItem> items;
    switch (kind) {
      case PosCatalogKind.category:
        items = _categories;
      case PosCatalogKind.brand:
        items = _brands;
      case PosCatalogKind.location:
        items = _locations;
      case PosCatalogKind.supplier:
        items = _suppliers;
    }

    await showPosCatalogManageDialog(
      context: context,
      api: _api,
      kind: kind,
      items: items,
      categoriesForParent: _categories,
      canEdit: canEdit,
      canDelete: canDelete,
      onRefresh: () async {
        await _loadCatalogs();
        if (!mounted) return _categories;
        setState(() {});
        return switch (kind) {
          PosCatalogKind.category => _categories,
          PosCatalogKind.brand => _brands,
          PosCatalogKind.location => _locations,
          PosCatalogKind.supplier => _suppliers,
        };
      },
    );
  }

  Future<void> _quickCreate(
    String title,
    Future<Map<String, dynamic>> Function(String name) apiFn,
    void Function(PosCatalogItem) onPicked,
  ) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('T?o m?i $title')),
        content: TextField(
          controller: ctrl,
          decoration: PosTheme.inputDecoration(label: 'Tên $title'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('H?y')),
          ),
          FilledButton(
            style: PosTheme.filledButtonStyle,
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Luu')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    final res = await apiFn(name);
    if (res['isSuccess'] == true && res['data'] != null && mounted) {
      final item = PosCatalogItem.fromJson(res['data'] as Map<String, dynamic>);
      setState(() => onPicked(item));
    }
  }

  /// T?o NCC form d?y d? (cùng API phi?u nh?p) — không ch? tên.
  Future<void> _openCreateSupplierFull() async {
    final created = await PosSupplierFormDialog.open(context);
    if (created == null || !mounted) return;
    setState(() {
      if (!_suppliers.any((s) => s.id == created.id)) {
        _suppliers.add(PosCatalogItem(id: created.id, name: created.name));
      }
      _supplierId = created.id;
    });
  }

  Future<void> _generateVariants() async {
    if (!_isEditing) {
      NotificationOverlayManager().showError(
        title: 'L?i',
        message: tr('Luu s?n ph?m tru?c khi t?o bi?n th?'),
      );
      return;
    }
    final attrs = _variantAttrs
        .where((a) =>
            a.attributeName.trim().isNotEmpty && a.valuesText.trim().isNotEmpty)
        .map((a) => a.toGenerateJson())
        .where((m) => (m['values'] as List).isNotEmpty)
        .toList();
    if (attrs.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'L?i',
        message: tr('Nh?p ít nh?t m?t thu?c tính và giá tr?'),
      );
      return;
    }
    setState(() => _generatingVariants = true);
    final res = await _api.generatePosProductVariants(
      widget.product!.id,
      attributes: attrs,
      defaultBasePrice: _parseNum(_priceCtrl.text),
      defaultCostPrice: _parseNum(_costCtrl.text),
    );
    if (!mounted) return;
    setState(() => _generatingVariants = false);
    if (res['isSuccess'] == true) {
      await _loadVariants(widget.product!.id);
      NotificationOverlayManager().showSuccess(
        title: 'Thành công',
        message: tr('Ðã t?o bi?n th?'),
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'L?i',
        message: res['message']?.toString() ?? 'T?o bi?n th? th?t b?i',
      );
    }
  }

  Future<void> _updateVariant(PosProductVariant v) async {
    if (!_isEditing) return;
    final res = await _api.updatePosProductVariant(
      widget.product!.id,
      v.id,
      v.toUpsertJson(),
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Ðã luu',
        message: tr('C?p nh?t bi?n th?'),
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'L?i',
        message: res['message']?.toString() ?? 'C?p nh?t th?t b?i',
      );
    }
  }

  void _resetForAnother() {
    _codeCtrl.clear();
    _barcodeCtrl.clear();
    _nameCtrl.clear();
    _costCtrl.text = '0';
    _priceCtrl.text = '0';
    _stockCtrl.text = '0';
    _minStockCtrl.text = '0';
    _maxStockCtrl.text = '999999999';
    _weightCtrl.clear();
    _descCtrl.clear();
    _saleQuickNotes = [];
    _isTopping = false;
    _allowToppings = false;
    _autoOpenToppingPopup = true;
    _toppingOptions = [];
    _toppingGroupIds = [];
    _unitCtrl.text = 'Cái';
    _imageBase64 = null;
    _imagePreviewUrl = null;
    _pendingImageBytes = null;
    _pendingImageName = null;
    _categoryId = null;
    _brandId = null;
    _locationId = null;
    _supplierId = null;
    _directSale = true;
    _attributeValues.clear();
    if (_isCombo) _comboLines.clear();
    _tabs.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return _buildKiotVietDialog();
  }

  Widget _buildKiotVietDialog() {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final narrow = size.width < 600;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.fromLTRB(
        narrow ? 8 : (size.width > 960 ? (size.width - 920) / 2 : 16),
        pad.top + (narrow ? 4 : 16),
        narrow ? 8 : (size.width > 960 ? (size.width - 920) / 2 : 16),
        pad.bottom + (narrow ? 4 : 12),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: size.height - pad.top - pad.bottom - (narrow ? 16 : 40),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildKiotVietHeader(),
            Material(
              color: Colors.white,
              child: _tabLabels.length > 1
                  ? TabBar(
                      controller: _tabs,
                      labelColor: PosTheme.kiotBlue,
                      unselectedLabelColor: PosTheme.textSecondary,
                      indicatorColor: PosTheme.kiotBlue,
                      indicatorWeight: 3,
                      tabs: _tabLabels.map((t) => Tab(text: tr(t))).toList(),
                    )
                  : const SizedBox.shrink(),
            ),
            if (_tabLabels.length > 1) const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: PosTheme.kiotBlue))
                  : _tabLabels.length > 1
                      ? TabBarView(
                          controller: _tabs,
                          children: [
                            _buildTypeInfoTab(),
                            _buildDescTab(),
                          ],
                        )
                      : _buildTypeInfoTab(),
            ),
            const Divider(height: 1),
            _buildKiotVietFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildKiotVietHeader() {
    final advancedOn = _editorSections.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(_pageTitle),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: PosTheme.textPrimary,
                  ),
                ),
                if (_editorPrefsLoaded && !advancedOn)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(tr('Form g?n — b?t thêm m?c trong ? n?u c?n'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _saving ? null : _openEditorSectionsSettings,
            icon: Icon(
              advancedOn ? Icons.tune : Icons.tune_outlined,
              color: advancedOn ? PosTheme.kiotBlue : PosTheme.textSecondary,
            ),
            tooltip: tr('Tùy ch?n hi?n th? form'),
          ),
          IconButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            tooltip: tr('Ðóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildKiotVietFooter() {
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final actions = <Widget>[
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: Text(tr('B? qua')),
      ),
      if (!_isEditing) ...[
        const SizedBox(width: 6),
        OutlinedButton(
          onPressed: _saving ? null : () => _save(createAnother: true),
          style: OutlinedButton.styleFrom(
            foregroundColor: PosTheme.kiotBlue,
            side: const BorderSide(color: PosTheme.kiotBlue),
            visualDensity: VisualDensity.compact,
          ),
          child: Text(tr('Luu & t?o thêm')),
        ),
      ],
      const SizedBox(width: 6),
      FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(
          backgroundColor: PosTheme.kiotBlue,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
              horizontal: narrow ? 16 : 24, vertical: 12),
        ),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(tr('Luu')),
      ),
    ];

    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _directSale,
                          activeColor: PosTheme.kiotBlue,
                          visualDensity: VisualDensity.compact,
                          onChanged: (v) =>
                              setState(() => _directSale = v ?? true),
                        ),
                        Expanded(
                          child: Text(tr('Bán tr?c ti?p'),
                              style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 6,
                      children: actions,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Checkbox(
                      value: _directSale,
                      activeColor: PosTheme.kiotBlue,
                      onChanged: (v) =>
                          setState(() => _directSale = v ?? true),
                    ),
                    Text(tr('Bán tr?c ti?p'), style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: tr('Hi?n th? trên màn hình bán hàng POS'),
                      child: Icon(Icons.info_outline,
                          size: 16, color: Colors.grey.shade500),
                    ),
                    const Spacer(),
                    ...actions,
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildFullPageScaffold() {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr(_pageTitle)),
        backgroundColor: PosTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: _tabLabels.length > 4,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: _tabLabels.map((t) => Tab(text: tr(t))).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PosTheme.primary))
          : TabBarView(
              controller: _tabs,
              children: _buildTabViews(),
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  List<Widget> _buildTabViews() {
    if (_isGoods) {
      return [_buildGoodsInfoTab(), _buildDescTab()];
    }
    if (_isService) {
      return [_buildInfoTab(), _buildPriceTab(), _buildDescTab()];
    }
    return [
      _buildInfoTab(),
      _buildComboTab(),
      _buildPriceTab(),
      _buildDescTab(),
    ];
  }

  Widget _buildTypeInfoTab() {
    if (_isGoods) return _buildGoodsInfoTab();
    if (_isService) return _buildServiceInfoTab();
    return _buildComboInfoTab();
  }

  /// Tab Thông tin hàng hóa — layout gi?ng KiotViet (m?t trang cu?n, nhi?u section).
  Widget _buildGoodsInfoTab() {
    final w = MediaQuery.sizeOf(context).width;
    final wide = w > 640;
    final padH = w < 420 ? 12.0 : 20.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(padH, 12, padH, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _goodsBasicFields()),
                    const SizedBox(width: 20),
                    SizedBox(width: 200, child: _kiotImageBox()),
                  ],
                )
              : Column(
                  children: [
                    _kiotImageBox(compact: w < 420),
                    const SizedBox(height: 12),
                    _goodsBasicFields(),
                  ],
                ),
          _kvSection(
            title: 'Giá v?n, giá bán',
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandSeparatorFormatter()],
                    decoration: PosTheme.inputDecoration(label: 'Giá v?n'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandSeparatorFormatter()],
                    decoration: PosTheme.inputDecoration(label: 'Giá bán'),
                  ),
                ),
              ],
            ),
          ),
          _buildProductVatSection(),
          if (_isGoods && _showSection(PosProductEditorSection.warranty))
            _buildProductWarrantySection(),
          _kvSection(
            title: 'T?n kho',
            subtitle: _showSection(PosProductEditorSection.stockLimits)
                ? 'Qu?n lý s? lu?ng t?n kho và d?nh m?c t?n.'
                : null,
            child: Builder(builder: (context) {
              final narrow = MediaQuery.sizeOf(context).width < 520;
              final stockField = TextField(
                controller: _stockCtrl,
                enabled: _canEditMainStock,
                keyboardType: TextInputType.number,
                decoration: PosTheme.inputDecoration(
                  label: _stockFieldLabel,
                  hint: _stockFieldHint,
                ),
              );
              if (!_showSection(PosProductEditorSection.stockLimits)) {
                return stockField;
              }
              final minField = TextField(
                controller: _minStockCtrl,
                keyboardType: TextInputType.number,
                decoration: PosTheme.inputDecoration(
                    label: 'Ð?nh m?c t?n th?p nh?t'),
              );
              final maxField = TextField(
                controller: _maxStockCtrl,
                keyboardType: TextInputType.number,
                decoration: PosTheme.inputDecoration(
                    label: 'Ð?nh m?c t?n cao nh?t'),
              );
              if (narrow) {
                return Column(
                  children: [
                    stockField,
                    const SizedBox(height: 10),
                    minField,
                    const SizedBox(height: 10),
                    maxField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: stockField),
                  const SizedBox(width: 12),
                  Expanded(child: minField),
                  const SizedBox(width: 12),
                  Expanded(child: maxField),
                ],
              );
            }),
          ),
          if (_showSection(PosProductEditorSection.locationWeight))
            _kvSection(
              title: 'V? trí, tr?ng lu?ng',
              subtitle:
                  'Qu?n lý vi?c s?p x?p kho, v? trí bán hàng ho?c tr?ng lu?ng hàng hóa',
              child: Column(
                children: [
                  _masterDropdown(
                    label: 'V? trí',
                    value: _locationId,
                    items: _locations,
                    onChanged: (v) => setState(() => _locationId = v),
                    onCreate: () => _quickCreate(
                      'v? trí',
                      _api.createPosStorageLocation,
                      (item) {
                        _locations.add(item);
                        _locationId = item.id;
                      },
                    ),
                    manageKind: PosCatalogKind.location,
                  ),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _weightCtrl,
                          keyboardType: TextInputType.number,
                          decoration:
                              PosTheme.inputDecoration(label: 'Tr?ng lu?ng'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _weightUnit,
                          decoration: PosTheme.inputDecoration(label: 'ÐVT'),
                          items: [
                            DropdownMenuItem(value: 'g', child: Text(tr('g'))),
                            DropdownMenuItem(value: 'kg', child: Text(tr('kg'))),
                          ],
                          onChanged: (v) =>
                              setState(() => _weightUnit = v ?? 'g'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (_showSection(PosProductEditorSection.unitsVariants))
            _buildUnitsAttributesExpansion(),
        ],
      ),
    );
  }

  Widget _buildProductTypeSelector() {
    if (!_isEditing) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<PosProductType>(
            value: _productType,
            decoration: PosTheme.inputDecoration(label: 'Loại hàng'),
            items: [
              DropdownMenuItem(
                value: PosProductType.goods,
                child: Text(tr('Hàng hóa')),
              ),
              DropdownMenuItem(
                value: PosProductType.service,
                child: Text(tr('Dịch vụ')),
              ),
              DropdownMenuItem(
                value: PosProductType.combo,
                child: Text(tr('Combo / Đóng gói')),
              ),
            ],
            onChanged: (v) {
              if (v == null || v == _productType) return;
              setState(() {
                final wasCombo = _isCombo;
                _productType = v;
                if (v != PosProductType.combo) {
                  _comboLines.clear();
                } else if (!wasCombo) {
                  _comboLines.clear();
                }
                if (v == PosProductType.service || v == PosProductType.combo) {
                  _stockCtrl.text = '0';
                }
              });
            },
          ),
          const SizedBox(height: 8),
          _buildTypeUsageNote(),
        ],
      ),
    );
  }

  Widget _buildTypeUsageNote() {
    final (color, icon, text) = switch (_type) {
      PosProductType.service => (
          const Color(0xFF0369A1),
          Icons.handyman_outlined,
          'Dịch vụ không quản lý tồn kho — bán không trừ kho. Dùng cho công, spa, tính giờ, gói buổi.',
        ),
      PosProductType.combo => (
          const Color(0xFFB45309),
          Icons.layers_outlined,
          'Combo không có tồn riêng. Khai định lượng thành phần (SL / 1 combo, được phép lẻ). Khi bán, kho trừ đúng SL từng hàng thành phần.',
        ),
      PosProductType.goods => (
          PosTheme.kiotBlue,
          Icons.inventory_2_outlined,
          'Hàng hóa quản lý tồn. Nhập kho rồi bán sẽ trừ đúng số lượng.',
        ),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(text),
              style: TextStyle(fontSize: 12.5, height: 1.35, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _goodsBasicFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProductTypeSelector(),
        if (_showSection(PosProductEditorSection.codes)) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  decoration: PosTheme.inputDecoration(
                    label: 'Mã hàng',
                    hint: _autoCodeHint,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _barcodeCtrl,
                  decoration: _barcodeInputDecoration(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _nameCtrl,
          decoration: PosTheme.inputDecoration(label: 'Tên hàng *'),
        ),
        const SizedBox(height: 12),
        _masterDropdown(
          label: 'Nhóm hàng *',
          value: _categoryId,
          items: _categories,
          onChanged: (v) => setState(() => _categoryId = v),
          onCreate: _quickCreateCategory,
          manageKind: PosCatalogKind.category,
        ),
        if (!_isCombo && _showSection(PosProductEditorSection.brand))
          _masterDropdown(
            label: 'Thuong hi?u',
            value: _brandId,
            items: _brands,
            onChanged: (v) => setState(() => _brandId = v),
            onCreate: () => _quickCreate(
              'thuong hi?u',
              _api.createPosProductBrand,
              (item) {
                _brands.add(item);
                _brandId = item.id;
              },
            ),
            manageKind: PosCatalogKind.brand,
          ),
        if (_isGoods && _showSection(PosProductEditorSection.supplier))
          _masterDropdown(
            label: 'Nhà cung c?p',
            value: _supplierId,
            items: _suppliers,
            onChanged: (v) => setState(() => _supplierId = v),
            onCreate: _openCreateSupplierFull,
            manageKind: PosCatalogKind.supplier,
          ),
      ],
    );
  }

  /// D?ch v? — gi?ng KiotViet: thông tin co b?n + giá + don v?/thu?c tính.
  Widget _buildServiceInfoTab() {
    final wide = MediaQuery.sizeOf(context).width > 640;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _serviceBasicFields()),
                    const SizedBox(width: 20),
                    SizedBox(width: 200, child: _kiotImageBox()),
                  ],
                )
              : Column(
                  children: [
                    _kiotImageBox(),
                    const SizedBox(height: 16),
                    _serviceBasicFields(),
                  ],
                ),
          _kvExpansion(
            title: 'Giá v?n, giá bán',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _costCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandSeparatorFormatter()],
                        decoration: PosTheme.inputDecoration(label: 'Giá v?n'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _priceCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandSeparatorFormatter()],
                        decoration: PosTheme.inputDecoration(label: 'Giá bán'),
                      ),
                    ),
                  ],
                ),
                _buildProductVatSection(),
              ],
            ),
          ),
          if (_showSection(PosProductEditorSection.serviceBilling))
            _kvExpansion(
              title: 'Tính giờ / gói buổi',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<PosServiceBillingMode>(
                    value: _serviceBillingMode,
                    decoration: PosTheme.inputDecoration(
                        label: 'Cách tính giá dịch vụ'),
                    items: PosServiceBillingMode.values
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(tr(m.label)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _serviceBillingMode = v;
                        if (v == PosServiceBillingMode.perBlock &&
                            _billRoundMinutesCtrl.text.trim().isEmpty) {
                          _billRoundMinutesCtrl.text = '5';
                        }
                        if (v == PosServiceBillingMode.perDay &&
                            _billRoundMinutesCtrl.text.trim().isEmpty) {
                          _billRoundMinutesCtrl.text = '1440';
                        }
                        if (v == PosServiceBillingMode.perDay &&
                            _minBillMinutesCtrl.text.trim().isEmpty) {
                          _minBillMinutesCtrl.text = '1440';
                        }
                      });
                    },
                  ),
                  if (_serviceBillingMode.isTimed) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _openingFeeCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: PosTheme.inputDecoration(
                              label: 'Phí mở phòng / bàn',
                              hint: 'VD 50.000',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _openingMinutesCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: PosTheme.inputDecoration(
                              label: 'Phút gồm trong phí mở',
                              hint: '0 = tính ngay',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minBillMinutesCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: PosTheme.inputDecoration(
                              label: 'Phút tối thiểu',
                              hint: 'VD 60',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _billRoundMinutesCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: PosTheme.inputDecoration(
                              label: _serviceBillingMode ==
                                      PosServiceBillingMode.perBlock
                                  ? 'Mỗi block (phút)'
                                  : _serviceBillingMode ==
                                          PosServiceBillingMode.perDay
                                      ? 'Làm tròn ngày (phút)'
                                      : 'Làm tròn (phút)',
                              hint: _serviceBillingMode ==
                                      PosServiceBillingMode.perBlock
                                  ? 'VD 5'
                                  : _serviceBillingMode ==
                                          PosServiceBillingMode.perDay
                                      ? '1440 = 1 ngày'
                                      : 'VD 15',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _graceMinutesCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: PosTheme.inputDecoration(
                              label: 'Phút miễn (grace)',
                              hint: 'VD 5–10',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _roundAfterMinutesCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: PosTheme.inputDecoration(
                              label: 'Làm tròn sau (phút)',
                              hint: '0 = luôn làm tròn',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTimedBillingPreview(),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _defaultDurationMinutesCtrl,
                          keyboardType: TextInputType.number,
                          decoration: PosTheme.inputDecoration(
                            label: 'Thời lượng mặc định (phút)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _sessionPackCountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: PosTheme.inputDecoration(
                            label: 'Số buổi trong gói',
                            hint: '0 = không phải gói',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sessionPackValidDaysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: PosTheme.inputDecoration(
                      label: 'Hạn gói (ngày)',
                      hint: '0 = không hạn — liệu trình / thẻ tập',
                    ),
                  ),
                ],
              ),
            ),
          if (_showSection(PosProductEditorSection.unitsVariants))
            _buildUnitsAttributesExpansion(),
        ],
      ),
    );
  }

  Widget _buildTimedBillingPreview() {
    final price = _parseNum(_priceCtrl.text);
    final openingFee = _parseNum(_openingFeeCtrl.text);
    final openingMinutes = int.tryParse(_openingMinutesCtrl.text.trim());
    final minBill = int.tryParse(_minBillMinutesCtrl.text.trim());
    final round = int.tryParse(_billRoundMinutesCtrl.text.trim());
    final grace = int.tryParse(_graceMinutesCtrl.text.trim());
    final roundAfter = int.tryParse(_roundAfterMinutesCtrl.text.trim());
    final rows = PosServiceBillingCalc.preview(
      mode: _serviceBillingMode,
      unitPrice: price,
      minBillMinutes: minBill,
      billRoundMinutes: round,
      graceMinutes: grace,
      roundAfterMinutes: roundAfter,
      openingFee: openingFee,
      openingMinutes: openingMinutes,
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Xem trước tiền giờ (karaoke / bi-a / KS)'),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Công thức: phí mở + số block vượt × đơn giá. VD mở 50k, mỗi 5 phút +10k.'),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Expanded(child: Text(tr('${r.elapsed} phút'))),
                  Expanded(child: Text(tr('tính ${r.billable}p'))),
                  Expanded(child: Text(tr('×${r.qty}'))),
                  Expanded(
                    child: Text(
                      tr(_moneyFmt.format(r.total.round())),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _serviceBasicFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProductTypeSelector(),
        if (_showSection(PosProductEditorSection.codes)) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  decoration: PosTheme.inputDecoration(
                    label: 'Mã hàng',
                    hint: _autoCodeHint,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _barcodeCtrl,
                  decoration: _barcodeInputDecoration(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _nameCtrl,
          decoration: PosTheme.inputDecoration(label: 'Tên hàng *'),
        ),
        const SizedBox(height: 12),
        _masterDropdown(
          label: 'Nhóm hàng *',
          value: _categoryId,
          items: _categories,
          onChanged: (v) => setState(() => _categoryId = v),
          onCreate: _quickCreateCategory,
          manageKind: PosCatalogKind.category,
        ),
        if (_showSection(PosProductEditorSection.brand))
          _masterDropdown(
            label: 'Thuong hi?u',
            value: _brandId,
            items: _brands,
            onChanged: (v) => setState(() => _brandId = v),
            onCreate: () => _quickCreate(
              'thuong hi?u',
              _api.createPosProductBrand,
              (item) {
                _brands.add(item);
                _brandId = item.id;
              },
            ),
            manageKind: PosCatalogKind.brand,
          ),
      ],
    );
  }

  /// Combo — gi?ng KiotViet: thành ph?n + giá + v? trí + don v?/thu?c tính.
  Widget _buildComboInfoTab() {
    final wide = MediaQuery.sizeOf(context).width > 640;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _comboBasicFields()),
                    const SizedBox(width: 20),
                    SizedBox(width: 200, child: _kiotImageBox()),
                  ],
                )
              : Column(
                  children: [
                    _kiotImageBox(),
                    const SizedBox(height: 16),
                    _comboBasicFields(),
                  ],
                ),
          _kvExpansion(
            title: 'Hàng thành phần — định lượng trừ kho',
            subtitle:
                'Mỗi dòng = SL trừ kho khi bán 1 combo. Bấm cột SL để sửa (được phép lẻ).',
            initiallyExpanded: true,
            child: _buildComboComponentsSection(),
          ),
          _kvExpansion(
            title: 'Giá bán',
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandSeparatorFormatter()],
                    decoration: PosTheme.inputDecoration(label: 'Giá bán'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: PosTheme.kiotBlueLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(tr('T?ng GT thành ph?n: ${_moneyFmt.format(_comboComponentsSum)}'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PosTheme.kiotBlue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildProductVatSection(),
          if (_showSection(PosProductEditorSection.locationWeight))
            _kvExpansion(
              title: 'V? trí, tr?ng lu?ng',
              subtitle:
                  'Qu?n lý vi?c s?p x?p kho, v? trí bán hàng ho?c tr?ng lu?ng hàng hóa',
              child: Column(
                children: [
                  _masterDropdown(
                    label: 'V? trí',
                    value: _locationId,
                    items: _locations,
                    onChanged: (v) => setState(() => _locationId = v),
                    onCreate: () => _quickCreate(
                      'v? trí',
                      _api.createPosStorageLocation,
                      (item) {
                        _locations.add(item);
                        _locationId = item.id;
                      },
                    ),
                    manageKind: PosCatalogKind.location,
                  ),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _weightCtrl,
                          keyboardType: TextInputType.number,
                          decoration:
                              PosTheme.inputDecoration(label: 'Tr?ng lu?ng'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _weightUnit,
                          decoration: PosTheme.inputDecoration(label: 'ÐVT'),
                          items: [
                            DropdownMenuItem(value: 'g', child: Text(tr('g'))),
                            DropdownMenuItem(value: 'kg', child: Text(tr('kg'))),
                          ],
                          onChanged: (v) =>
                              setState(() => _weightUnit = v ?? 'g'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (_showSection(PosProductEditorSection.unitsVariants))
            _buildUnitsAttributesExpansion(),
        ],
      ),
    );
  }

  Widget _comboBasicFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProductTypeSelector(),
        if (_showSection(PosProductEditorSection.codes)) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  decoration: PosTheme.inputDecoration(
                    label: 'Mã hàng',
                    hint: _autoCodeHint,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _barcodeCtrl,
                  decoration: _barcodeInputDecoration(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _nameCtrl,
          decoration: PosTheme.inputDecoration(label: 'Tên hàng *'),
        ),
        const SizedBox(height: 12),
        _masterDropdown(
          label: 'Nhóm hàng *',
          value: _categoryId,
          items: _categories,
          onChanged: (v) => setState(() => _categoryId = v),
          onCreate: _quickCreateCategory,
          manageKind: PosCatalogKind.category,
        ),
      ],
    );
  }

  Widget _buildComboComponentsSection() {
    final sellable = _comboLines.isEmpty ? 0.0 : computeComboSellableQty(_comboLines);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          readOnly: true,
          onTap: _addComboComponent,
          decoration: InputDecoration(
            hintText: tr('Thêm hàng thành phần'),
            prefixIcon: const Icon(Icons.search, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: PosTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: PosTheme.border),
            ),
          ),
        ),
        if (_comboLines.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            tr(sellable <= 0
                ? 'Hiện không đủ thành phần để bán combo.'
                : 'Có thể bán khoảng ${PosQtyRules.format(sellable, allowDecimal: false)} combo (theo thành phần ít nhất).'),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: sellable <= 0 ? Colors.red.shade700 : const Color(0xFFB45309),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_comboLines.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: PosTheme.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tr('Chưa có hàng thành phần — thêm để trừ kho theo định lượng'),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 44,
              columnSpacing: 16,
              columns: [
                DataColumn(label: Text(tr('STT'), style: TextStyle(fontSize: 12))),
                DataColumn(label: Text(tr('Mã hàng'), style: TextStyle(fontSize: 12))),
                DataColumn(
                    label: Text(tr('Tên hàng thành phần'),
                        style: TextStyle(fontSize: 12))),
                DataColumn(
                    label: Text(tr('Định lượng / 1 combo'),
                        style: TextStyle(fontSize: 12)),
                    numeric: true),
                DataColumn(
                    label: Text(tr('ĐVT'), style: TextStyle(fontSize: 12))),
                DataColumn(
                    label: Text(tr('Giá vốn'), style: TextStyle(fontSize: 12)),
                    numeric: true),
                DataColumn(
                    label: Text(tr('Tổng GV'), style: TextStyle(fontSize: 12)),
                    numeric: true),
                DataColumn(label: Text('', style: TextStyle(fontSize: 12))),
              ],
              rows: _comboLines.asMap().entries.map((e) {
                final i = e.key;
                final c = e.value;
                final lineCost = c.componentBasePrice * c.qty;
                final qtyText =
                    '${PosQtyRules.format(c.qty, allowDecimal: true)}${c.componentUnitName.isNotEmpty ? ' ${c.componentUnitName}' : ''}';
                return DataRow(
                  cells: [
                    DataCell(Text(tr('${i + 1}'))),
                    DataCell(Text(tr(c.componentProductCode))),
                    DataCell(Text(tr(c.componentProductName))),
                    DataCell(
                      Text(
                        qtyText,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationStyle: TextDecorationStyle.dotted,
                        ),
                      ),
                      showEditIcon: true,
                      onTap: () async {
                        final q = await showComboComponentQtyDialog(
                          context,
                          initialQty: c.qty,
                        );
                        if (q == null || !mounted) return;
                        setState(() => _comboLines[i] = c.copyWith(qty: q));
                      },
                    ),
                    DataCell(Text(tr(c.componentUnitName.isEmpty
                        ? '—'
                        : c.componentUnitName))),
                    DataCell(Text(tr(_moneyFmt.format(c.componentBasePrice)))),
                    DataCell(Text(tr(_moneyFmt.format(lineCost)))),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            setState(() => _comboLines.removeAt(i)),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildProductWarrantySection() {
    return _kvSection(
      title: 'B?o hành, seri & lô/HSD',
      subtitle: 'BH tính t? ngày bán. B?t theo dõi HSD d? nh?p lô khi nh?p hàng.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _warrantyMonthsCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: PosTheme.inputDecoration(
              label: 'Th?i h?n b?o hành (tháng)',
              hint: 'VD: 12 — d? tr?ng n?u không BH',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('B?t bu?c nh?p seri máy khi bán')),
            subtitle: Text(tr('M?i don v? bán ph?i có seri riêng (máy di?n t?, thi?t b?...)'),
              style: TextStyle(fontSize: 12),
            ),
            value: _requiresSerial,
            onChanged: (v) => setState(() {
              _requiresSerial = v;
              if (v) _allowDecimalQty = false;
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Cho phép s? lu?ng th?p phân')),
            subtitle: Text(
              tr('B?t d? bán/nh?p 0.5, 1.25… (vd kg, lít). T?t = ch? s? nguyên.'),
              style: TextStyle(fontSize: 12),
            ),
            value: _allowDecimalQty,
            onChanged: _requiresSerial
                ? null
                : (v) => setState(() => _allowDecimalQty = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Theo dõi lô / HSD')),
            subtitle: Text(tr('B?t bu?c nh?p HSD trên phi?u nh?p hàng'),
              style: TextStyle(fontSize: 12),
            ),
            value: _trackExpiry,
            onChanged: (v) => setState(() => _trackExpiry = v),
          ),
          if (_trackExpiry) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _expiryWarningDaysCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: PosTheme.inputDecoration(
                label: 'C?nh báo tru?c HSD (ngày)',
                hint: 'M?c d?nh 30',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductVatSection() {
    if (!_showSection(PosProductEditorSection.vat)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Thu? VAT (%)'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _productVatChip('KCT', exempt: true),
              _productVatChip('0%', rate: 0),
              _productVatChip('5%', rate: 5),
              _productVatChip('8%', rate: 8),
              _productVatChip('10%', rate: 10),
            ],
          ),
          if (_vatExempt)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('Không ch?u thu? GTGT — áp d?ng khi c?a hàng ch?n thu? theo t?ng m?t hàng'),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _productVatChip(String label, {double rate = 0, bool exempt = false}) {
    final selected =
        exempt ? _vatExempt : (!_vatExempt && _vatRate == rate);
    return ChoiceChip(
      label: Text(tr(label), style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) {
        setState(() {
          if (exempt) {
            _vatExempt = true;
            _vatRate = 0;
          } else {
            _vatExempt = false;
            _vatRate = rate;
          }
        });
      },
      selectedColor: PosTheme.kiotBlueLight,
      labelStyle: TextStyle(
        color: selected ? PosTheme.kiotBlue : PosTheme.textPrimary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _kvExpansion({
    required String title,
    String? subtitle,
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: initiallyExpanded,
        title: Text(tr(title),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: subtitle != null
            ? Text(tr(subtitle),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _kiotImageBox({bool compact = false}) {
    final boxH = compact ? 120.0 : 160.0;
    return Column(
      children: [
        InkWell(
          onTap: _pickImage,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: double.infinity,
            height: boxH,
            decoration: BoxDecoration(
              border: Border.all(color: PosTheme.border),
              borderRadius: BorderRadius.circular(4),
              color: const Color(0xFFFAFAFA),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: _imageBase64 != null
                ? Image.memory(base64Decode(_imageBase64!), fit: BoxFit.cover,
                    width: double.infinity, height: boxH)
                : (_imagePreviewUrl != null && _imagePreviewUrl!.isNotEmpty)
                    ? PosProductImage(
                        productId: widget.product?.id,
                        imageUrl: _imagePreviewUrl,
                        size: boxH,
                        borderRadius: 4,
                      )
                    : _imagePlaceholder(),
          ),
        ),
        const SizedBox(height: 6),
        Text(tr('M?i ?nh không quá 2 MB'),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _imagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined,
            size: 36, color: Colors.grey.shade500),
        const SizedBox(height: 8),
        Text(tr('Ch?p ho?c ch?n ?nh'),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
      ],
    );
  }

  Widget _kvSection({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Divider(height: 24),
        Text(tr(title),
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 15)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(tr(subtitle),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
        ] else
          const SizedBox(height: 12),
        child,
      ],
    );
  }

  Map<String, dynamic> _productPatchForSetup() => {
        'name': _nameCtrl.text.trim(),
        'categoryId': _categoryId,
        'brandId': _brandId,
        'storageLocationId': _locationId,
        'supplierId': _supplierId,
        'productType': _isService ? 1 : (_isCombo ? 2 : 0),
        'description': _descCtrl.text.trim(),
        'saleQuickNotes': _saleQuickNotes
            .map((n) => n.trim())
            .where((n) => n.isNotEmpty)
            .toList(),
        'isTopping': _isTopping,
        'allowToppings': _allowToppings && !_isTopping,
        'autoOpenToppingPopup': _autoOpenToppingPopup,
        'toppings': (_allowToppings && !_isTopping)
            ? _toppingOptions
                .map((t) => {
                      'toppingProductId': t.toppingProductId,
                      'extraPrice': t.extraPrice,
                      'sortOrder': t.sortOrder,
                    })
                .toList()
            : <Map<String, dynamic>>[],
        'toppingGroupIds': _isTopping ? <String>[] : _toppingGroupIds,
      'costPrice': _parseNum(_costCtrl.text),
      'basePrice': _parseNum(_priceCtrl.text),
      'vatRate': _vatExempt ? 0 : _vatRate,
      'vatExempt': _vatExempt,
      if (!_hasVariants || _usesSharedUnitStock)
        'onHandQty': _isCombo ? 0 : (_isService ? 0 : _parseNum(_stockCtrl.text)),
      'reservedQty': widget.product?.reservedQty ?? 0,
        if (_isGoods) ...{
          'minStockQty': _parseNum(_minStockCtrl.text),
          'maxStockQty': _parseNum(_maxStockCtrl.text),
          if (_weightCtrl.text.trim().isNotEmpty)
            'weight': _parseNum(_weightCtrl.text),
          'weightUnit': _weightUnit,
        },
        'isDirectSale': _directSale,
        'isFavorite': widget.product?.isFavorite ?? false,
      };

  List<UnitAttributeRowInput> _attributeRowsForSetup() {
    if (_variantAttrs.isNotEmpty) {
      return _variantAttrs
          .map((a) => UnitAttributeRowInput(
                attributeId: a.attributeId,
                attributeName: a.attributeName,
                valuesText: a.valuesText,
              ))
          .toList();
    }
    final grouped = <String, UnitAttributeRowInput>{};
    for (final a in _attributeValues) {
      final name = a.attributeName.trim();
      if (name.isEmpty) continue;
      final existing = grouped[name];
      if (existing != null) {
        grouped[name] = UnitAttributeRowInput(
          attributeId: a.attributeId,
          attributeName: name,
          valuesText: '${existing.valuesText}, ${a.value}',
        );
      } else {
        grouped[name] = UnitAttributeRowInput(
          attributeId: a.attributeId,
          attributeName: name,
          valuesText: a.value,
        );
      }
    }
    return grouped.values.toList();
  }

  Future<void> _openUnitAttributeSetup({bool addMore = false}) async {
    final result = await showUnitAttributeSetupDialog(
      context,
      input: UnitAttributeSetupInput(
        baseUnitName: _unitCtrl.text.trim().isEmpty
            ? 'Cái'
            : _unitCtrl.text.trim(),
        basePrice: _parseNum(_priceCtrl.text),
        costPrice: _parseNum(_costCtrl.text),
        baseDirectSale: _directSale,
        productCode:
            _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
        barcode:
            _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
        extraUnits: _units.where((u) => !u.isBaseUnit).toList(),
        attributeRows: _attributeRowsForSetup(),
        variants: _variants,
        productId: _isEditing ? widget.product!.id : null,
        productPatch: _isEditing ? _productPatchForSetup() : null,
        startInAddMoreMode: addMore,
        focusVariantId: widget.unitSetupFocusVariantId,
      ),
    );
    if (result == null || !mounted) return;

    _applyUnitAttributeSetupResult(result);

    if (_isEditing) {
      await _loadProductDetail(widget.product!.id);
      await _loadVariants(widget.product!.id, rebuildAttrs: false);
      setState(() {
        _variantAttrs
          ..clear()
          ..addAll(result.attributeRows.map((a) {
            final row = _VariantAttrRow();
            row.attributeId = a.attributeId;
            row.attributeName = a.attributeName;
            row.valuesText = a.valuesText;
            return row;
          }));
        _attributeValues
          ..clear()
          ..addAll(result.attributeRows.expand((a) {
            return a.valuesText
                .split(RegExp(r'[,;]'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .map((v) => PosProductAttribute(
                      attributeId: a.attributeId,
                      attributeName: a.attributeName,
                      value: v,
                    ));
          }));
      });
      // Ð?ng b? _variants t? server — ngu?n dúng cho s? hàng cùng lo?i
      if (_variants.length != result.variants.length) {
        setState(() {});
      }
      if (_variants.isEmpty &&
          (result.extraUnits.isNotEmpty || result.variants.isNotEmpty)) {
        NotificationOverlayManager().showError(
          title: 'D? li?u chua du?c luu',
          message: tr('Thi?t l?p chua ghi lên server. Vui lòng th? Luu l?i ho?c b?m Luu hàng hóa.'),
        );
      } else if (result.variants.isNotEmpty || result.extraUnits.isNotEmpty) {
        NotificationOverlayManager().showSuccess(
          title: 'Thành công',
          message: tr('Ðã luu thi?t l?p don v? tính và thu?c tính.'),
        );
      }
    } else {
      NotificationOverlayManager().showWarning(
        title: 'Chua luu lên server',
        message: tr('B?m «Luu» trên form hàng hóa d? ghi don v? tính và bi?n th? vào h? th?ng.'),
      );
    }

    if (result.addAnotherSameType && mounted) {
      await _openUnitAttributeSetup();
    }
  }

  void _applyUnitAttributeSetupResult(UnitAttributeSetupResult result) {
    setState(() {
      _unitCtrl.text = result.baseUnitName;
      _priceCtrl.text = _fmtInputMoney(result.basePrice);
      _costCtrl.text = _fmtInputMoney(result.costPrice);
      _directSale = result.baseDirectSale;
      if (result.productCode != null && result.productCode!.isNotEmpty) {
        _codeCtrl.text = result.productCode!;
      }
      if (result.barcode != null) {
        _barcodeCtrl.text = result.barcode!;
      }
      _units = result.extraUnits;
      _variantAttrs
        ..clear()
        ..addAll(result.attributeRows.map((a) {
          final row = _VariantAttrRow();
          row.attributeId = a.attributeId;
          row.attributeName = a.attributeName;
          row.valuesText = a.valuesText;
          return row;
        }));
      _attributeValues
        ..clear()
        ..addAll(result.attributeRows.expand((a) {
          return a.valuesText
              .split(RegExp(r'[,;]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .map((v) => PosProductAttribute(
                    attributeId: a.attributeId,
                    attributeName: a.attributeName,
                    value: v,
                  ));
        }));
      _variants = result.variants;
    });
  }

  /// Sau khi n?p t? server, uu tiên s? lu?ng th?c t? trên DB.
  int get _displayVariantCount =>
      _variants.isNotEmpty ? _variants.length : _expectedVariantCount();

  int _expectedVariantCount() {
    if (_variantAttrs.isEmpty) return _variants.length;
    var combos = 1;
    for (final a in _variantAttrs) {
      final values = a.valuesText
          .split(RegExp(r'[,;]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .length;
      if (values > 0) combos *= values;
    }
    final unitCount = _units.where((u) => !u.isBaseUnit).length;
    final multiplier = unitCount > 0 ? unitCount : 1;
    return combos * multiplier;
  }

  Widget _buildUnitsAttributesExpansion() {
    final baseName =
        _unitCtrl.text.trim().isEmpty ? 'Cái' : _unitCtrl.text.trim();
    final extraUnits = _units.where((u) => !u.isBaseUnit).toList();
    final narrow = MediaQuery.sizeOf(context).width < 520;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // —— Ðon v? co b?n (tách riêng) ——
        _kvSection(
          title: 'Ðon v? tính co b?n',
          subtitle: 'Ðon v? nh? nh?t dùng d? qu?n lý t?n kho (vd: Cái, Kg, Chai).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _unitCtrl,
                decoration: PosTheme.inputDecoration(
                  label: 'Tên don v? co b?n *',
                  hint: 'Cái',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: PosTheme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('1 $baseName'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(tr('Giá bán: ${_moneyFmt.format(_parseNum(_priceCtrl.text))}'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: PosTheme.kiotBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // —— Ðon v? quy d?i (tách riêng) ——
        _kvSection(
          title: 'Ðon v? quy d?i',
          subtitle:
              'Ðon v? bán l?n hon, có h? s? quy d?i v? don v? co b?n (vd: Thùng = 24 Cái).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (extraUnits.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(tr('Chua có don v? quy d?i. Thêm n?u bán theo l?c/thùng/h?p…'),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                )
              else
                ...extraUnits.map((u) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: PosTheme.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr(u.unitName),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr('1 ${u.unitName} = ${u.conversionRate} $baseName'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              Text(tr('Giá: ${_moneyFmt.format(u.basePrice)}'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: PosTheme.kiotBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: PosTheme.kiotBlue,
                          onPressed: _openUnitAttributeSetup,
                          tooltip: tr('S?a'),
                        ),
                      ],
                    ),
                  );
                }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _openUnitAttributeSetup,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('Thêm don v? quy d?i')),
                  style: TextButton.styleFrom(foregroundColor: PosTheme.kiotBlue),
                ),
              ),
            ],
          ),
        ),
        // —— Thu?c tính / hàng cùng lo?i ——
        if (_showSection(PosProductEditorSection.unitsVariants))
          _kvSection(
            title: 'Hàng cùng lo?i / thu?c tính',
            subtitle: 'Sinh mã riêng theo màu, size… (tu? ch?n).',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_variants.isEmpty && extraUnits.isEmpty)
                  Text(tr('Chua có thu?c tính. Dùng «Thi?t l?p» d? thêm màu, size…'),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: narrow ? 420 : 520,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: PosTheme.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Container(
                              color: const Color(0xFFF8FAFC),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                      width: 120,
                                      child: Text(tr('Ðon v?'),
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600))),
                                  SizedBox(
                                      width: 100,
                                      child: Text(tr('Mã hàng'),
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600))),
                                  SizedBox(
                                      width: 80,
                                      child: Text(tr('Giá v?n'),
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600))),
                                  SizedBox(
                                      width: 80,
                                      child: Text(tr('Giá bán'),
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600))),
                                  SizedBox(
                                      width: 60,
                                      child: Text(tr('T?n'),
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600))),
                                ],
                              ),
                            ),
                            if (_variants.isNotEmpty)
                              ..._variants.map((v) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                            width: 120,
                                            child: Text(tr(v.name),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 12))),
                                        SizedBox(
                                            width: 100,
                                            child: Text(tr(v.skuCode),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 11))),
                                        SizedBox(
                                            width: 80,
                                            child: Text(
                                                tr(_moneyFmt.format(
                                                    v.costPrice.round())),
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(
                                                    fontSize: 11))),
                                        SizedBox(
                                            width: 80,
                                            child: Text(
                                                tr(_moneyFmt.format(
                                                    v.basePrice.round())),
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(
                                                    fontSize: 11))),
                                        SizedBox(
                                            width: 60,
                                            child: Text(
                                                tr(v.onHandQty.toStringAsFixed(0)),
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(
                                                    fontSize: 11))),
                                      ],
                                    ),
                                  ))
                            else
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                child: Row(
                                  children: [
                                    SizedBox(
                                        width: 120,
                                        child: Text(tr(baseName),
                                            style: const TextStyle(
                                                fontSize: 12))),
                                    SizedBox(
                                        width: 100,
                                        child: Text(
                                            tr(_codeCtrl.text.trim().isEmpty
                                                ? '—'
                                                : _codeCtrl.text.trim()),
                                            style: const TextStyle(
                                                fontSize: 11))),
                                    SizedBox(
                                        width: 80,
                                        child: Text(
                                            tr(_moneyFmt.format(
                                                _parseNum(_costCtrl.text)
                                                    .round())),
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                                fontSize: 11))),
                                    SizedBox(
                                        width: 80,
                                        child: Text(
                                            tr(_moneyFmt.format(
                                                _parseNum(_priceCtrl.text)
                                                    .round())),
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                                fontSize: 11))),
                                    SizedBox(
                                        width: 60,
                                        child: Text(
                                            tr(_parseNum(_stockCtrl.text)
                                                .toStringAsFixed(0)),
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                                fontSize: 11))),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _openUnitAttributeSetup,
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text(tr('Thi?t l?p don v? & thu?c tính')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: PosTheme.kiotBlue,
                    side: const BorderSide(color: PosTheme.kiotBlue),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _inlineUnitRow({
    required String label,
    required String conversion,
    required double price,
    bool isBase = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(tr(label), style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Text(tr(conversion), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(
              tr(NumberFormat('#,##0', 'vi_VN').format(price.round())),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (!isBase)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              onPressed: _openUnitAttributeSetup,
              tooltip: tr('S?a trong thi?t l?p'),
            ),
        ],
      ),
    );
  }

  Widget _inlineVariantRow(PosProductVariant v) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(tr(v.name), style: const TextStyle(fontSize: 12))),
          Expanded(child: Text(tr(v.skuCode), style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(tr(NumberFormat('#,##0', 'vi_VN').format(v.costPrice.round())), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(tr(NumberFormat('#,##0', 'vi_VN').format(v.basePrice.round())), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(tr(v.onHandQty.toStringAsFixed(0)), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  Widget _inlineUnitPreviewRow(
    String unit,
    String code,
    double cost,
    double price,
    double stock,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(tr(unit), style: const TextStyle(fontSize: 12))),
          Expanded(child: Text(tr(code.isEmpty ? '—' : code), style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(tr(NumberFormat('#,##0', 'vi_VN').format(cost.round())), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(tr(NumberFormat('#,##0', 'vi_VN').format(price.round())), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(tr(stock.toStringAsFixed(0)), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Material(
      elevation: 4,
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Checkbox(
                value: _directSale,
                activeColor: PosTheme.primary,
                onChanged: (v) => setState(() => _directSale = v ?? true),
              ),
              Expanded(
                child: Text(tr('Bán tr?c ti?p (hi?n trên POS)'),
                    style: TextStyle(fontSize: 13)),
              ),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(tr('B? qua')),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: PosTheme.filledButtonStyle,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(tr('Luu')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTab() {
    final wide = MediaQuery.sizeOf(context).width > 720;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _infoFields()),
                const SizedBox(width: 16),
                SizedBox(width: 180, child: _imageBox()),
              ],
            )
          : Column(
              children: [
                _imageBox(),
                const SizedBox(height: 16),
                _infoFields(),
              ],
            ),
    );
  }

  Widget _imageBox() {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: PosTheme.border),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            clipBehavior: Clip.antiAlias,
            child: _imageBase64 != null
                ? Image.memory(base64Decode(_imageBase64!), fit: BoxFit.cover)
                : (_imagePreviewUrl != null && _imagePreviewUrl!.isNotEmpty)
                    ? PosProductImage(
                        productId: widget.product?.id,
                        imageUrl: _imagePreviewUrl,
                        size: 180,
                        borderRadius: 12,
                      )
                    : Icon(Icons.add_a_photo_outlined,
                        size: 48, color: PosTheme.textSecondary),
          ),
        ),
        TextButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.photo_camera_outlined, color: PosTheme.primary),
          label: Text(tr('Ch?p / ch?n ?nh'), style: TextStyle(color: PosTheme.primary)),
        ),
      ],
    );
  }

  Widget _infoFields() {
    final nameLabel =
        _isService ? 'Tên d?ch v? *' : 'Tên hàng *';
    return Column(
      children: [
        if (!_isService) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  decoration: PosTheme.inputDecoration(
                    label: 'Mã hàng',
                    hint: _autoCodeHint,
                  ),
                ),
              ),
              if (_isGoods) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _barcodeCtrl,
                    decoration: _barcodeInputDecoration(),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _nameCtrl,
          decoration: PosTheme.inputDecoration(label: nameLabel),
        ),
        const SizedBox(height: 12),
        _masterDropdown(
          label: 'Nhóm hàng',
          value: _categoryId,
          items: _categories,
          onChanged: (v) => setState(() => _categoryId = v),
          onCreate: _quickCreateCategory,
          manageKind: PosCatalogKind.category,
        ),
        if (!_isCombo)
          _masterDropdown(
            label: 'Thuong hi?u',
            value: _brandId,
            items: _brands,
            onChanged: (v) => setState(() => _brandId = v),
            onCreate: () => _quickCreate(
              'thuong hi?u',
              _api.createPosProductBrand,
              (item) {
                _brands.add(item);
                _brandId = item.id;
              },
            ),
            manageKind: PosCatalogKind.brand,
          ),
        if (_isGoods)
          _masterDropdown(
            label: 'V? trí',
            value: _locationId,
            items: _locations,
            onChanged: (v) => setState(() => _locationId = v),
            onCreate: () => _quickCreate(
              'v? trí',
              _api.createPosStorageLocation,
              (item) {
                _locations.add(item);
                _locationId = item.id;
              },
            ),
            manageKind: PosCatalogKind.location,
          ),
      ],
    );
  }

  Widget _buildPriceStockTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _costCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandSeparatorFormatter()],
                  decoration: PosTheme.inputDecoration(label: 'Giá v?n'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandSeparatorFormatter()],
                  decoration: PosTheme.inputDecoration(label: 'Giá bán'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _masterDropdown(
            label: 'Nhà cung c?p',
            value: _supplierId,
            items: _suppliers,
            onChanged: (v) => setState(() => _supplierId = v),
            onCreate: _openCreateSupplierFull,
            manageKind: PosCatalogKind.supplier,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _stockCtrl,
                  enabled: _canEditMainStock,
                  keyboardType: TextInputType.number,
                  decoration: PosTheme.inputDecoration(
                    label: _stockFieldLabel,
                    hint: _stockFieldHint,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _minStockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: PosTheme.inputDecoration(label: 'T?n th?p nh?t'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxStockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: PosTheme.inputDecoration(label: 'T?n cao nh?t'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _weightCtrl,
                  keyboardType: TextInputType.number,
                  decoration: PosTheme.inputDecoration(label: 'Tr?ng lu?ng'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _weightUnit,
                  decoration: PosTheme.inputDecoration(label: 'ÐVT'),
                  items: [
                    DropdownMenuItem(value: 'g', child: Text(tr('g'))),
                    DropdownMenuItem(value: 'kg', child: Text(tr('kg'))),
                  ],
                  onChanged: (v) => setState(() => _weightUnit = v ?? 'g'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceTab() {
    final priceLabel = _isService ? 'Giá d?ch v?' : 'Giá bán';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _costCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandSeparatorFormatter()],
                  decoration: PosTheme.inputDecoration(label: 'Giá v?n'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandSeparatorFormatter()],
                  decoration: PosTheme.inputDecoration(label: priceLabel),
                ),
              ),
            ],
          ),
          if (_isCombo) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PosTheme.primaryLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: PosTheme.primary.withOpacity(0.3)),
              ),
              child: Text(tr('T?ng giá thành ph?n: ${_moneyFmt.format(_comboComponentsSum)}'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: PosTheme.primaryDark,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnitsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _unitCtrl,
            decoration: PosTheme.inputDecoration(label: 'Ðon v? co b?n'),
          ),
          const SizedBox(height: 16),
          Text(tr('Ðon v? quy d?i'),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (_units.isEmpty)
            Text(tr('Chua có don v? quy d?i'),
                style: TextStyle(color: PosTheme.textSecondary))
          else
            ..._units.map((u) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text(tr(u.unitName +
                        (u.isBaseUnit ? ' (co b?n)' : ' = ${u.conversionRate}'))),
                    subtitle: Text(tr('Giá: ${_moneyFmt.format(u.basePrice)}')),
                    trailing: u.isBaseUnit || !_isEditing
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              final res = await _api.deletePosProductUnit(
                                  widget.product!.id, u.id);
                              if (res['isSuccess'] == true) {
                                setState(() => _units.remove(u));
                              }
                            },
                          ),
                  ),
                )),
          if (_isEditing)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addExtraUnit,
                icon: const Icon(Icons.add, color: PosTheme.primary),
                label: Text(tr('Thêm don v?'),
                    style: TextStyle(color: PosTheme.primary)),
              ),
            ),
          const Divider(height: 32),
          Text(tr('Thu?c tính'),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ..._attributeValues.asMap().entries.map((e) {
            final i = e.key;
            final a = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: a.attributeName,
                      decoration:
                          PosTheme.inputDecoration(label: 'Tên thu?c tính'),
                      onChanged: (v) => _attributeValues[i] =
                          PosProductAttribute(
                        attributeId: a.attributeId,
                        attributeName: v,
                        value: a.value,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: a.value,
                      decoration: PosTheme.inputDecoration(label: 'Giá tr?'),
                      onChanged: (v) => _attributeValues[i] =
                          PosProductAttribute(
                        attributeId: a.attributeId,
                        attributeName: a.attributeName,
                        value: v,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        setState(() => _attributeValues.removeAt(i)),
                  ),
                ],
              ),
            );
          }),
          TextButton.icon(
            onPressed: () => setState(() => _attributeValues.add(
                PosProductAttribute(
                    attributeId: '', attributeName: '', value: ''))),
            icon: const Icon(Icons.add, color: PosTheme.primary),
            label: Text(tr('Thêm thu?c tính'),
                style: TextStyle(color: PosTheme.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantsTab() {
    if (!_isEditing) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(tr('Luu s?n ph?m tru?c d? qu?n lý bi?n th?'),
            textAlign: TextAlign.center,
            style: TextStyle(color: PosTheme.textSecondary),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('T?o bi?n th? t? thu?c tính'),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text(tr('Nh?p tên thu?c tính và các giá tr? cách nhau b?i d?u ph?y'),
            style: TextStyle(fontSize: 12, color: PosTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          ..._variantAttrs.asMap().entries.map((e) {
            final i = e.key;
            final a = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: a.attributeName,
                      decoration:
                          PosTheme.inputDecoration(label: 'Thu?c tính'),
                      onChanged: (v) => a.attributeName = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: a.valuesText,
                      decoration: PosTheme.inputDecoration(
                        label: 'Giá tr?',
                        hint: 'Ð?, Xanh, Vàng',
                      ),
                      onChanged: (v) => a.valuesText = v,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _variantAttrs.removeAt(i)),
                  ),
                ],
              ),
            );
          }),
          Row(
            children: [
              TextButton.icon(
                onPressed: () =>
                    setState(() => _variantAttrs.add(_VariantAttrRow())),
                icon: const Icon(Icons.add, color: PosTheme.primary),
                label: Text(tr('Thêm thu?c tính'),
                    style: TextStyle(color: PosTheme.primary)),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _generatingVariants ? null : _generateVariants,
                style: PosTheme.filledButtonStyle,
                icon: _generatingVariants
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_fix_high, size: 18),
                label: Text(tr('T?o bi?n th?')),
              ),
            ],
          ),
          const Divider(height: 32),
          Text(tr('Bi?n th? (${_variants.length})'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (_variants.isEmpty)
            Text(tr('Chua có bi?n th?'),
                style: TextStyle(color: PosTheme.textSecondary))
          else
            ..._variants.map((v) => _variantCard(v)),
        ],
      ),
    );
  }

  Widget _variantCard(PosProductVariant v) {
    final priceCtrl =
        TextEditingController(text: tr(v.basePrice.toStringAsFixed(0)));
    final costCtrl = TextEditingController(text: tr(v.costPrice.toStringAsFixed(0)));
    final unitOnly = variantIsBaseUnitOnly(v);
    final stockCtrl = TextEditingController(
        text: tr(v.onHandQty.toStringAsFixed(0)));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(v.name),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (v.skuCode.isNotEmpty)
              Text(tr('SKU: ${v.skuCode}'),
                  style: TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: costCtrl,
                    keyboardType: TextInputType.number,
                    decoration: PosTheme.inputDecoration(label: 'Giá v?n'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: PosTheme.inputDecoration(label: 'Giá bán'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: stockCtrl,
                    enabled: !unitOnly,
                    keyboardType: TextInputType.number,
                    decoration: PosTheme.inputDecoration(
                      label: unitOnly ? 'T?n (quy d?i)' : 'T?n',
                      hint: unitOnly ? 'S?a ô T?n kho chính theo don v? co b?n' : null,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  final updated = PosProductVariant(
                    id: v.id,
                    skuCode: v.skuCode,
                    barcode: v.barcode,
                    name: v.name,
                    attributeJson: v.attributeJson,
                    costPrice: _parseNum(costCtrl.text),
                    basePrice: _parseNum(priceCtrl.text),
                    onHandQty: _parseNum(stockCtrl.text),
                    isActive: v.isActive,
                  );
                  _updateVariant(updated);
                },
                child: Text(tr('Luu bi?n th?'),
                    style: TextStyle(color: PosTheme.primary)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComboTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTypeUsageNote(),
          const SizedBox(height: 12),
          Text(
            tr('Tổng giá thành phần: ${_moneyFmt.format(_comboComponentsSum)}'),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: PosTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 16),
          _buildComboComponentsSection(),
        ],
      ),
    );
  }

  Widget _buildDescTab() {
    const padding = EdgeInsets.fromLTRB(20, 16, 20, 24);
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Mô t?'),
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
          const SizedBox(height: 8),
          _kiotDescToolbar(),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            maxLines: 10,
            minLines: 10,
            decoration: InputDecoration(
              hintText: tr('Mô t? chi ti?t s?n ph?m…'),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: PosTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: PosTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: PosTheme.kiotBlue, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 20),
          Text(tr('Ghi chú nhanh khi bán hàng'),
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          const SizedBox(height: 8),
          PosSaleQuickNotesListEditor(
            notes: _saleQuickNotes,
            onChanged: (v) => setState(() => _saleQuickNotes = v),
          ),
          const SizedBox(height: 20),
          Text(tr('Tùy ch?n thêm'),
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(tr('Gi?ng ghi chú nhanh: hi?n d?ng chip khi bán, nhung có giá ph? thu / tr? t?n SP.'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Ðây là hàng tùy ch?n thêm')),
            subtitle: Text(tr('Dùng làm tùy ch?n cho món khác (vd: trân châu, th?ch)'),
              style: TextStyle(fontSize: 12),
            ),
            value: _isTopping,
            onChanged: (v) => setState(() {
              _isTopping = v;
              if (v) {
                _allowToppings = false;
                _toppingOptions = [];
                _toppingGroupIds = [];
              }
            }),
          ),
          if (!_isTopping) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Cho phép tùy ch?n thêm khi bán')),
              subtitle: Text(tr('Hi?n chip ch?n trên dòng hóa don (gi?ng ghi chú nhanh)'),
                style: TextStyle(fontSize: 12),
              ),
              value: _allowToppings,
              onChanged: (v) => setState(() {
                _allowToppings = v;
                if (!v) _toppingOptions = [];
              }),
            ),
            if (_allowToppings) ...[
              const SizedBox(height: 8),
              ..._toppingOptions.asMap().entries.map((e) {
                final i = e.key;
                final t = e.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(tr(t.toppingProductName)),
                  subtitle: Text(tr('+${_fmtInputMoney(t.extraPrice)} d'),
                    style: const TextStyle(color: PosTheme.kiotBlue),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _toppingOptions.removeAt(i)),
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: _pickToppingProduct,
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('Thêm tùy ch?n cho món này')),
              ),
            ],
            const Divider(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(tr('Topping (nhóm dùng chung)'),
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PosToppingGroupsScreen(),
                      ),
                    );
                    await _loadToppingGroups();
                  },
                  child: Text(tr('Qu?n lý nhóm')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(tr('Ch?n nhóm topping dã t?o s?n — m?i món g?n cùng nhóm dùng chung danh sách.'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            if (_availableToppingGroups.isEmpty)
              Text(tr('Chua có nhóm — nh?n «Qu?n lý nhóm» d? t?o.'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableToppingGroups.map((g) {
                  final on = _toppingGroupIds.contains(g.id);
                  return FilterChip(
                    label: Text(
                      tr('${g.name} (${g.items.length})'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: on,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _toppingGroupIds = [..._toppingGroupIds, g.id];
                      } else {
                        _toppingGroupIds =
                            _toppingGroupIds.where((id) => id != g.id).toList();
                      }
                    }),
                  );
                }).toList(),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('T? m? popup topping khi thêm món')),
              subtitle: Text(tr('Khi món có nhóm topping — h?i ngay lúc thêm vào gi?'),
                style: TextStyle(fontSize: 12),
              ),
              value: _autoOpenToppingPopup,
              onChanged: (v) => setState(() => _autoOpenToppingPopup = v),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadToppingGroups() async {
    final res = await _api.getPosToppingGroups();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      setState(() {
        _availableToppingGroups = (res['data'] as List)
            .whereType<Map>()
            .map((e) => PosProductToppingGroup.fromJson(
                Map<String, dynamic>.from(e)))
            .toList();
      });
    }
  }

  Future<void> _pickToppingProduct() async {
    final qCtrl = TextEditingController();
    List<PosProduct> results = [];
    var loading = true;

    Future<void> search(StateSetter setModal, String q) async {
      setModal(() => loading = true);
      final res = await _api.getPosProducts(
        page: 1,
        pageSize: 40,
        search: q.trim().isEmpty ? null : q.trim(),
      );
      final items = <PosProduct>[];
      if (res['isSuccess'] == true) {
        final data = res['data'];
        final raw = data is Map
            ? (data['items'] ?? data['Items'])
            : null;
        if (raw is List) {
          for (final e in raw) {
            if (e is! Map) continue;
            final p = PosProduct.fromJson(Map<String, dynamic>.from(e));
            if (p.id == widget.product?.id) continue;
            items.add(p);
          }
        }
      }
      setModal(() {
        results = items;
        loading = false;
      });
    }

    final picked = await showDialog<PosProduct>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            if (loading && results.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                search(setModal, '');
              });
            }
            return AlertDialog(
              title: Text(tr('Ch?n hàng topping')),
              content: SizedBox(
                width: 420,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: qCtrl,
                      decoration: InputDecoration(
                        hintText: tr('Tìm theo tên / mã…'),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (v) => search(setModal, v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (_, i) {
                                final p = results[i];
                                final already = _toppingOptions
                                    .any((t) => t.toppingProductId == p.id);
                                return ListTile(
                                  enabled: !already,
                                  title: Text(tr(p.name)),
                                  subtitle: Text(tr('${p.productCode} · ${_fmtInputMoney(p.basePrice)} d'),
                                  ),
                                  onTap: already
                                      ? null
                                      : () => Navigator.pop(ctx, p),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Ðóng')),
                ),
                TextButton(
                  onPressed: () => search(setModal, qCtrl.text),
                  child: Text(tr('Tìm')),
                ),
              ],
            );
          },
        );
      },
    );
    qCtrl.dispose();
    if (picked == null || !mounted) return;
    setState(() {
      _toppingOptions = [
        ..._toppingOptions,
        PosProductToppingOption(
          id: '',
          toppingProductId: picked.id,
          toppingProductName: picked.name,
          extraPrice: picked.basePrice,
          sortOrder: _toppingOptions.length,
        ),
      ];
      // G?i ý dánh d?u hàng topping n?u chua.
    });
  }

  Widget _kiotDescToolbar() {
    Widget btn(IconData icon, String tip) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: 18, color: PosTheme.textSecondary),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: PosTheme.border),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        color: const Color(0xFFFAFAFA),
      ),
      child: Row(
        children: [
          btn(Icons.format_bold, 'In d?m'),
          btn(Icons.format_italic, 'In nghiêng'),
          btn(Icons.format_underlined, 'G?ch chân'),
          const VerticalDivider(width: 16),
          btn(Icons.format_align_left, 'Can trái'),
          btn(Icons.format_align_center, 'Can gi?a'),
          btn(Icons.format_align_right, 'Can ph?i'),
          const VerticalDivider(width: 16),
          btn(Icons.format_list_bulleted, 'Danh sách'),
          btn(Icons.format_list_numbered, 'Danh sách s?'),
          const Spacer(),
          btn(Icons.link, 'Liên k?t'),
          btn(Icons.image_outlined, '?nh'),
        ],
      ),
    );
  }

  Widget _masterDropdown({
    required String label,
    required String? value,
    required List<PosCatalogItem> items,
    required ValueChanged<String?> onChanged,
    required VoidCallback onCreate,
    PosCatalogKind? manageKind,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: items.any((c) => c.id == value) ? value : null,
              decoration: PosTheme.inputDecoration(label: label),
              items: items
                  .map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(tr(c.name))))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
          if (manageKind != null)
            TextButton(
              onPressed: () => _manageCatalog(manageKind),
              child: Text(tr('Qu?n lý'),
                style: TextStyle(
                  color: _isGoods
                      ? PosTheme.textSecondary
                      : PosTheme.textSecondary,
                ),
              ),
            ),
          TextButton(
            onPressed: onCreate,
            child: Text(tr('T?o m?i'),
              style: TextStyle(
                color: _isGoods ? PosTheme.kiotBlue : PosTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addExtraUnit() async {
    if (!_isEditing) return;
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController(text: tr('1'));
    final priceCtrl = TextEditingController(text: tr('0'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Thêm don v? quy d?i')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: PosTheme.inputDecoration(label: 'Tên don v?'),
            ),
            TextField(
              controller: rateCtrl,
              decoration: PosTheme.inputDecoration(
                label: 'Quy d?i (× don v? co b?n)',
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: priceCtrl,
              decoration: PosTheme.inputDecoration(label: 'Giá bán'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('H?y')),
          ),
          FilledButton(
            style: PosTheme.filledButtonStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Thêm')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.createPosProductUnit(widget.product!.id, {
      'unitName': nameCtrl.text.trim(),
      'conversionRate': double.tryParse(rateCtrl.text) ?? 1,
      'basePrice': double.tryParse(priceCtrl.text) ?? 0,
      'isDirectSale': true,
    });
    if (res['isSuccess'] == true && res['data'] != null) {
      setState(() => _units.add(
          PosProductUnit.fromJson(res['data'] as Map<String, dynamic>)));
    }
  }

  Future<void> _addComboComponent() async {
    final existingIds =
        _comboLines.map((c) => c.componentProductId).toSet();
    final prod = await PosComboComponentPicker.show(
      context,
      api: _api,
      excludeProductId: widget.product?.id,
      excludeComponentIds: existingIds,
    );
    if (prod == null || !mounted) return;

    final existingIdx =
        _comboLines.indexWhere((c) => c.componentProductId == prod.id);
    if (existingIdx >= 0) {
      NotificationOverlayManager().showError(
        title: 'Ðã có thành ph?n',
        message: tr('«${prod.name}» dã n?m trong combo'),
      );
      return;
    }

    final qty = await showComboComponentQtyDialog(context);
    if (qty == null || !mounted) return;

    setState(() {
      _comboLines.add(PosComboLine(
        id: '',
        componentProductId: prod.id,
        componentProductCode: prod.productCode,
        componentProductName: prod.name,
        qty: qty,
        componentOnHandQty: prod.onHandQty,
        componentBasePrice: prod.basePrice,
        componentUnitName: prod.baseUnitName,
      ));
    });
  }
}
