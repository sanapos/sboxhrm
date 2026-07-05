import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/pos_product.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;
import '../../utils/number_formatter.dart';
import '../../widgets/pos/pos_catalog_manage.dart';
import '../../widgets/pos/pos_product_image.dart';
import '../../widgets/pos/pos_unit_attribute_setup_dialog.dart';
import '../../widgets/pos/pos_product_unit_view.dart';
import '../../widgets/pos/pos_sale_quick_notes_widgets.dart';
import '../../widgets/pos/pos_theme.dart';

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
  /// Sao chép: mở form thêm mới, điền sẵn từ sản phẩm nguồn.
  final PosProduct? templateProduct;
  /// Mở thẳng dialog thiết lập đơn vị/thuộc tính sau khi nạp xong.
  final bool openUnitSetup;
  /// Chuẩn bị nhập thêm giá trị thuộc tính (hàng cùng loại).
  final bool unitSetupAddMore;
  /// Mở dialog thiết lập và bôi đậm hàng cùng loại cần sửa.
  final String? unitSetupFocusVariantId;

  /// Mở editor: hàng hóa = dialog KiotViet; dịch vụ/combo = full page.
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

  /// Mở thẳng dialog thiết lập đơn vị/thuộc tính để sửa một hàng cùng loại (không mở form cha).
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
  bool _requiresSerial = false;

  List<PosCatalogItem> _categories = [];
  List<PosCatalogItem> _brands = [];
  List<PosCatalogItem> _locations = [];
  List<PosCatalogItem> _suppliers = [];
  List<PosProductUnit> _units = [];
  final List<PosProductAttribute> _attributeValues = [];
  List<PosComboLine> _comboLines = [];
  List<PosProduct> _allProductsForCombo = [];
  List<PosProductVariant> _variants = [];
  final List<_VariantAttrRow> _variantAttrs = [];
  bool _generatingVariants = false;

  PosProductType get _type => widget.productType;
  bool get _isGoods => _type == PosProductType.goods;
  bool get _isService => _type == PosProductType.service;
  bool get _isCombo => _type == PosProductType.combo;
  bool get _isEditing => widget.product != null;
  bool get _hasVariants => _variants.isNotEmpty;
  bool get _usesSharedUnitStock =>
      _variants.isEmpty || _variants.every(variantIsBaseUnitOnly);
  bool get _canEditMainStock => !_hasVariants || _usesSharedUnitStock;

  String get _stockFieldLabel {
    if (!_hasVariants) return 'Tồn kho';
    if (_usesSharedUnitStock) {
      final unit = _unitCtrl.text.trim();
      return unit.isEmpty ? 'Tồn kho (đơn vị cơ bản)' : 'Tồn kho ($unit)';
    }
    return 'Tồn kho (tổng các loại)';
  }

  String get _stockFieldHint => _canEditMainStock
      ? 'Nhập theo đơn vị nhỏ nhất; ĐVT khác tự quy đổi khi hiển thị'
      : 'Sửa tồn từng biến thể ở bảng bên dưới hoặc dùng Nhập kho';
  bool get _isCopyFromTemplate =>
      widget.templateProduct != null && widget.product == null;

  String get _pageTitle {
    if (_isCopyFromTemplate) {
      return switch (_type) {
        PosProductType.goods => 'Thêm hàng hóa (sao chép)',
        PosProductType.service => 'Thêm dịch vụ (sao chép)',
        PosProductType.combo => 'Thêm combo (sao chép)',
      };
    }
    if (!_isEditing) {
      return switch (_type) {
        PosProductType.goods => 'Tạo hàng hóa',
        PosProductType.service => 'Tạo dịch vụ',
        PosProductType.combo => 'Tạo combo - đóng gói',
      };
    }
    return switch (_type) {
      PosProductType.goods => 'Sửa hàng hóa',
      PosProductType.service => 'Sửa dịch vụ',
      PosProductType.combo => 'Sửa combo',
    };
  }

  List<String> get _tabLabels => const ['Thông tin', 'Mô tả'];

  double get _comboComponentsSum => _comboLines.fold(
        0.0,
        (s, c) => s + c.componentBasePrice * c.qty,
      );

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabLabels.length, vsync: this);
    final p = widget.product ?? widget.templateProduct;
    final copyName = p != null && _isCopyFromTemplate
        ? (p.name.trim().endsWith('(bản sao)')
            ? p.name.trim()
            : '${p.name.trim()} (bản sao)')
        : (p?.name ?? '');
    _codeCtrl = TextEditingController(
        text: _isCopyFromTemplate ? '' : (p?.productCode ?? ''));
    _barcodeCtrl = TextEditingController(
        text: _isCopyFromTemplate ? '' : (p?.barcode ?? ''));
    _nameCtrl = TextEditingController(text: copyName);
    _costCtrl = TextEditingController(
        text: _fmtInputMoney(p?.costPrice ?? 0));
    _priceCtrl = TextEditingController(
        text: _fmtInputMoney(p?.basePrice ?? 0));
    _stockCtrl = TextEditingController(
        text: p != null ? p.onHandQty.toStringAsFixed(0) : '0');
    _minStockCtrl = TextEditingController(
        text: p != null ? p.minStockQty.toStringAsFixed(0) : '0');
    _maxStockCtrl = TextEditingController(
        text: p != null
            ? p.maxStockQty.toStringAsFixed(0)
            : (_isGoods ? '999999999' : '0'));
    _weightCtrl = TextEditingController(
        text: p?.weight != null ? p!.weight!.toStringAsFixed(0) : '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _saleQuickNotes = List<String>.from(p?.saleQuickNotes ?? const []);
    _unitCtrl = TextEditingController(text: p?.baseUnitName ?? 'Cái');
    _categoryId = p?.categoryId;
    _brandId = p?.brandId;
    _locationId = p?.storageLocationId;
    _supplierId = p?.supplierId;
    _directSale = p?.isDirectSale ?? true;
    _weightUnit = p?.weightUnit ?? 'g';
    _vatRate = p?.vatExempt == true ? 0 : (p?.vatRate ?? 8);
    _vatExempt = p?.vatExempt ?? false;
    _warrantyMonthsCtrl = TextEditingController(
      text: p?.warrantyMonths != null && p!.warrantyMonths! > 0
          ? '${p.warrantyMonths}'
          : '',
    );
    _requiresSerial = p?.requiresSerial ?? false;
    _imagePreviewUrl = p?.imageUrl;
    if (p?.units != null) _units = List.from(p!.units!);
    if (p?.attributes != null) _attributeValues.addAll(p!.attributes!);
    _initData();
  }

  Future<void> _initData() async {
    final templateId = widget.templateProduct?.id;
    await Future.wait([
      _loadCatalogs(),
      if (_isCombo) _loadProductsForCombo(),
      if (_isEditing) _loadProductDetail(widget.product!.id),
      if (_isCopyFromTemplate && templateId != null)
        _loadTemplateExtras(templateId),
    ]);
    if (mounted) setState(() => _loading = false);
    if (mounted && widget.openUnitSetup && _isGoods) {
      await _openUnitAttributeSetup(addMore: widget.unitSetupAddMore);
    }
  }

  /// Nạp đơn vị, thuộc tính, thành phần combo từ sản phẩm nguồn khi sao chép.
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

  Future<void> _loadProductsForCombo() async {
    final res = await _api.getPosProducts(pageSize: 200);
    if (!mounted || res['isSuccess'] != true) return;
    final items = ((res['data'] as Map?)?['items'] as List? ?? [])
        .map((e) => PosProduct.fromJson(e as Map<String, dynamic>))
        .where((p) =>
            p.productType != PosProductType.combo &&
            p.productType != PosProductType.service)
        .toList();
    setState(() => _allProductsForCombo = items);
  }

  Future<void> _loadProductDetail(String id) async {
    final res = await _api.getPosProduct(id);
    if (!mounted || res['isSuccess'] != true) return;
    final data = PosProduct.fromJson(res['data'] as Map<String, dynamic>);
    setState(() {
      if (data.units != null) _units = List.from(data.units!);
      _attributeValues
        ..clear()
        ..addAll(data.attributes ?? []);
      _syncVariantAttrsFromProductAttributes();
      _supplierId = data.supplierId;
      _saleQuickNotes = List<String>.from(data.saleQuickNotes);
      _vatRate = data.vatExempt ? 0 : data.vatRate;
      _vatExempt = data.vatExempt;
      _warrantyMonthsCtrl.text =
          data.warrantyMonths != null && data.warrantyMonths! > 0
              ? '${data.warrantyMonths}'
              : '';
      _requiresSerial = data.requiresSerial;
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

  /// Nạp dòng thuộc tính từ schema đã lưu (1 value = "a, b, c" trên API).
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

  /// Khôi phục dòng thuộc tính từ attributeJson của biến thể (sau reload/F5).
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

  /// Ghi đơn vị quy đổi + biến thể lên server (dùng cho cả tạo mới và sửa).
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
          return res['message']?.toString() ?? 'Lưu đơn vị quy đổi thất bại';
        }
      } else {
        final res = await _api.createPosProductUnit(productId, body);
        if (res['isSuccess'] != true) {
          return res['message']?.toString() ?? 'Tạo đơn vị quy đổi thất bại';
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
      return syncRes['message']?.toString() ?? 'Lưu biến thể thất bại';
    }
    if (syncRes['data'] is List) {
      _variants = (syncRes['data'] as List)
          .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return null;
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
    super.dispose();
  }

  String _fmtInputMoney(num v) => _inputMoneyFmt.format(v);

  double _parseNum(String s) =>
      parseFormattedNumber(s)?.toDouble() ?? 0;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: 'Ảnh không được vượt quá 2 MB',
      );
      return;
    }
    var name = file.name.trim();
    if (name.isEmpty) name = 'product.jpg';
    if (!name.contains('.')) name = '$name.jpg';
    setState(() {
      _pendingImageBytes = bytes;
      _pendingImageName = name;
      _imageBase64 = base64Encode(bytes);
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
        title: 'Lỗi',
        message: _isService
            ? 'Vui lòng nhập tên dịch vụ'
            : 'Vui lòng nhập tên hàng',
      );
      return;
    }
    if (_categoryId == null || _categoryId!.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: 'Vui lòng chọn nhóm hàng',
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
        'attributes': _attributeSchemaForSave(),
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
            title: 'Lưu ảnh thất bại',
            message: imgRes['message']?.toString() ??
                'Hàng hóa đã lưu nhưng ảnh chưa được gắn. Vui lòng thử lại.',
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
            title: 'Lưu chưa hoàn tất',
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
        await _api.savePosComboLines(
          productId,
          _comboLines
              .map((c) => {
                    'componentProductId': c.componentProductId,
                    'qty': c.qty,
                  })
              .toList(),
        );
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      ScreenRefreshNotifier.refreshPosSellProductGrid();
      NotificationOverlayManager().showSuccess(
        title: 'Thành công',
        message: _isEditing ? 'Đã lưu hàng hóa' : 'Đã tạo hàng hóa',
      );
      if (createAnother && !_isEditing) {
        _resetForAnother();
        setState(() {});
      } else {
        Navigator.pop(context, true);
      }
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Lưu thất bại',
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
          title: const Text('Tạo mới nhóm hàng'),
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
                  label: 'Nhóm cha (tuỳ chọn)',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Không —')),
                  ..._categories.map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ),
                ],
                onChanged: (v) => setDlg(() => parentId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            FilledButton(
              style: PosTheme.filledButtonStyle,
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
              child: const Text('Lưu'),
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
        title: 'Lỗi',
        message: 'Bạn không có quyền quản lý danh mục',
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
        title: Text('Tạo mới $title'),
        content: TextField(
          controller: ctrl,
          decoration: PosTheme.inputDecoration(label: 'Tên $title'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: PosTheme.filledButtonStyle,
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Lưu'),
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

  Future<void> _generateVariants() async {
    if (!_isEditing) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: 'Lưu sản phẩm trước khi tạo biến thể',
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
        title: 'Lỗi',
        message: 'Nhập ít nhất một thuộc tính và giá trị',
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
        message: 'Đã tạo biến thể',
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Tạo biến thể thất bại',
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
        title: 'Đã lưu',
        message: 'Cập nhật biến thể',
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Cập nhật thất bại',
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
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width > 960 ? (size.width - 920) / 2 : 16,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: size.height * 0.92,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildKiotVietHeader(),
            Material(
              color: Colors.white,
              child: TabBar(
                controller: _tabs,
                labelColor: PosTheme.kiotBlue,
                unselectedLabelColor: PosTheme.textSecondary,
                indicatorColor: PosTheme.kiotBlue,
                indicatorWeight: 3,
                tabs: _tabLabels.map((t) => Tab(text: t)).toList(),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: PosTheme.kiotBlue))
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _buildTypeInfoTab(),
                        _buildDescTab(),
                      ],
                    ),
            ),
            const Divider(height: 1),
            _buildKiotVietFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildKiotVietHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _pageTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: PosTheme.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            tooltip: 'Đóng',
          ),
        ],
      ),
    );
  }

  Widget _buildKiotVietFooter() {
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Checkbox(
                value: _directSale,
                activeColor: PosTheme.kiotBlue,
                onChanged: (v) => setState(() => _directSale = v ?? true),
              ),
              const Text('Bán trực tiếp', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Hiển thị trên màn hình bán hàng POS',
                child: Icon(Icons.info_outline,
                    size: 16, color: Colors.grey.shade500),
              ),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Bỏ qua'),
              ),
              const SizedBox(width: 8),
              if (!_isEditing)
                OutlinedButton(
                  onPressed: _saving ? null : () => _save(createAnother: true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: PosTheme.kiotBlue,
                    side: const BorderSide(color: PosTheme.kiotBlue),
                  ),
                  child: const Text('Lưu & Tạo thêm hàng'),
                ),
              if (!_isEditing) const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: PosTheme.kiotBlue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                    : const Text('Lưu'),
              ),
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
        title: Text(_pageTitle),
        backgroundColor: PosTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: _tabLabels.length > 4,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: _tabLabels.map((t) => Tab(text: t)).toList(),
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

  /// Tab Thông tin hàng hóa — layout giống KiotViet (một trang cuộn, nhiều section).
  Widget _buildGoodsInfoTab() {
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
                    Expanded(child: _goodsBasicFields()),
                    const SizedBox(width: 20),
                    SizedBox(width: 200, child: _kiotImageBox()),
                  ],
                )
              : Column(
                  children: [
                    _kiotImageBox(),
                    const SizedBox(height: 16),
                    _goodsBasicFields(),
                  ],
                ),
          _kvSection(
            title: 'Giá vốn, giá bán',
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandSeparatorFormatter()],
                    decoration: PosTheme.inputDecoration(label: 'Giá vốn'),
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
          if (_isGoods) _buildProductWarrantySection(),
          _kvSection(
            title: 'Tồn kho',
            subtitle:
                'Quản lý số lượng tồn kho và định mức tồn. Khi tồn kho chạm đến định mức, bạn sẽ nhận được cảnh báo.',
            child: Row(
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
                    decoration: PosTheme.inputDecoration(
                        label: 'Định mức tồn thấp nhất'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maxStockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: PosTheme.inputDecoration(
                        label: 'Định mức tồn cao nhất'),
                  ),
                ),
              ],
            ),
          ),
          _kvSection(
            title: 'Vị trí, trọng lượng',
            subtitle:
                'Quản lý việc sắp xếp kho, vị trí bán hàng hoặc trọng lượng hàng hóa',
            child: Column(
              children: [
                _masterDropdown(
                  label: 'Vị trí',
                  value: _locationId,
                  items: _locations,
                  onChanged: (v) => setState(() => _locationId = v),
                  onCreate: () => _quickCreate(
                    'vị trí',
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
                            PosTheme.inputDecoration(label: 'Trọng lượng'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _weightUnit,
                        decoration: PosTheme.inputDecoration(label: 'ĐVT'),
                        items: const [
                          DropdownMenuItem(value: 'g', child: Text('g')),
                          DropdownMenuItem(value: 'kg', child: Text('kg')),
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
          _buildUnitsAttributesExpansion(),
        ],
      ),
    );
  }

  Widget _goodsBasicFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeCtrl,
                decoration: PosTheme.inputDecoration(
                  label: 'Mã hàng',
                  hint: 'Tự động',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _barcodeCtrl,
                decoration: PosTheme.inputDecoration(
                  label: 'Mã vạch',
                  hint: 'Nhập mã vạch',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
        if (!_isCombo)
          _masterDropdown(
            label: 'Thương hiệu',
            value: _brandId,
            items: _brands,
            onChanged: (v) => setState(() => _brandId = v),
            onCreate: () => _quickCreate(
              'thương hiệu',
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
            label: 'Nhà cung cấp',
            value: _supplierId,
            items: _suppliers,
            onChanged: (v) => setState(() => _supplierId = v),
            onCreate: () => _quickCreate(
              'nhà cung cấp',
              _api.createPosSupplier,
              (item) {
                _suppliers.add(item);
                _supplierId = item.id;
              },
            ),
            manageKind: PosCatalogKind.supplier,
          ),
      ],
    );
  }

  /// Dịch vụ — giống KiotViet: thông tin cơ bản + giá + đơn vị/thuộc tính.
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
            title: 'Giá vốn, giá bán',
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
                        decoration: PosTheme.inputDecoration(label: 'Giá vốn'),
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
          _buildUnitsAttributesExpansion(),
        ],
      ),
    );
  }

  Widget _serviceBasicFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeCtrl,
                decoration: PosTheme.inputDecoration(
                  label: 'Mã hàng',
                  hint: 'Tự động',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _barcodeCtrl,
                decoration: PosTheme.inputDecoration(
                  label: 'Mã vạch',
                  hint: 'Nhập mã vạch',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
        _masterDropdown(
          label: 'Thương hiệu',
          value: _brandId,
          items: _brands,
          onChanged: (v) => setState(() => _brandId = v),
          onCreate: () => _quickCreate(
            'thương hiệu',
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

  /// Combo — giống KiotViet: thành phần + giá + vị trí + đơn vị/thuộc tính.
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
            title: 'Hàng thành phần',
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
                    child: Text(
                      'Tổng GT thành phần: ${_moneyFmt.format(_comboComponentsSum)}',
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
          _kvExpansion(
            title: 'Vị trí, trọng lượng',
            subtitle:
                'Quản lý việc sắp xếp kho, vị trí bán hàng hoặc trọng lượng hàng hóa',
            child: Column(
              children: [
                _masterDropdown(
                  label: 'Vị trí',
                  value: _locationId,
                  items: _locations,
                  onChanged: (v) => setState(() => _locationId = v),
                  onCreate: () => _quickCreate(
                    'vị trí',
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
                            PosTheme.inputDecoration(label: 'Trọng lượng'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _weightUnit,
                        decoration: PosTheme.inputDecoration(label: 'ĐVT'),
                        items: const [
                          DropdownMenuItem(value: 'g', child: Text('g')),
                          DropdownMenuItem(value: 'kg', child: Text('kg')),
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
          _buildUnitsAttributesExpansion(),
        ],
      ),
    );
  }

  Widget _comboBasicFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeCtrl,
                decoration: PosTheme.inputDecoration(
                  label: 'Mã hàng',
                  hint: 'Tự động',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _barcodeCtrl,
                decoration: PosTheme.inputDecoration(
                  label: 'Mã vạch',
                  hint: 'Nhập mã vạch',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
        _masterDropdown(
          label: 'Thương hiệu',
          value: _brandId,
          items: _brands,
          onChanged: (v) => setState(() => _brandId = v),
          onCreate: () => _quickCreate(
            'thương hiệu',
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

  Widget _buildComboComponentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          readOnly: true,
          onTap: _addComboComponent,
          decoration: InputDecoration(
            hintText: 'Thêm hàng thành phần',
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
              'Chưa có hàng thành phần',
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
              columns: const [
                DataColumn(label: Text('STT', style: TextStyle(fontSize: 12))),
                DataColumn(label: Text('Mã hàng', style: TextStyle(fontSize: 12))),
                DataColumn(
                    label: Text('Tên hàng thành phần',
                        style: TextStyle(fontSize: 12))),
                DataColumn(
                    label: Text('SL', style: TextStyle(fontSize: 12)),
                    numeric: true),
                DataColumn(
                    label: Text('Giá vốn', style: TextStyle(fontSize: 12)),
                    numeric: true),
                DataColumn(
                    label: Text('Tổng GV', style: TextStyle(fontSize: 12)),
                    numeric: true),
                DataColumn(
                    label: Text('Giá bán', style: TextStyle(fontSize: 12)),
                    numeric: true),
                DataColumn(label: Text('', style: TextStyle(fontSize: 12))),
              ],
              rows: _comboLines.asMap().entries.map((e) {
                final i = e.key;
                final c = e.value;
                final lineCost = c.componentBasePrice * c.qty;
                return DataRow(
                  cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(c.componentProductCode)),
                    DataCell(Text(c.componentProductName)),
                    DataCell(Text(c.qty.toStringAsFixed(0))),
                    DataCell(Text(_moneyFmt.format(c.componentBasePrice))),
                    DataCell(Text(_moneyFmt.format(lineCost))),
                    DataCell(Text(_moneyFmt.format(c.componentBasePrice))),
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
      title: 'Bảo hành & seri máy',
      subtitle: 'Thời hạn BH tính từ ngày bán. Bật seri để bắt buộc nhập khi thanh toán.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _warrantyMonthsCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: PosTheme.inputDecoration(
              label: 'Thời hạn bảo hành (tháng)',
              hint: 'VD: 12 — để trống nếu không BH',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bắt buộc nhập seri máy khi bán'),
            subtitle: const Text(
              'Mỗi đơn vị bán phải có seri riêng (máy điện tử, thiết bị...)',
              style: TextStyle(fontSize: 12),
            ),
            value: _requiresSerial,
            onChanged: (v) => setState(() => _requiresSerial = v),
          ),
        ],
      ),
    );
  }

  Widget _buildProductVatSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Thuế VAT (%)',
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
              child: Text(
                'Không chịu thuế GTGT — áp dụng khi cửa hàng chọn thuế theo từng mặt hàng',
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
      label: Text(label, style: const TextStyle(fontSize: 12)),
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
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: subtitle != null
            ? Text(subtitle,
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

  Widget _kiotImageBox() {
    return Column(
      children: [
        InkWell(
          onTap: _pickImage,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: PosTheme.border),
              borderRadius: BorderRadius.circular(4),
              color: const Color(0xFFFAFAFA),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: _imageBase64 != null
                ? Image.memory(base64Decode(_imageBase64!), fit: BoxFit.cover,
                    width: double.infinity, height: 160)
                : (_imagePreviewUrl != null && _imagePreviewUrl!.isNotEmpty)
                    ? PosProductImage(
                        productId: widget.product?.id,
                        imageUrl: _imagePreviewUrl,
                        size: 160,
                        borderRadius: 4,
                      )
                    : _imagePlaceholder(),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Mỗi ảnh không quá 2 MB',
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
        Text('Thêm ảnh',
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
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 15)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle,
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
      // Đồng bộ _variants từ server — nguồn đúng cho số hàng cùng loại
      if (_variants.length != result.variants.length) {
        setState(() {});
      }
      if (_variants.isEmpty &&
          (result.extraUnits.isNotEmpty || result.variants.isNotEmpty)) {
        NotificationOverlayManager().showError(
          title: 'Dữ liệu chưa được lưu',
          message:
              'Thiết lập chưa ghi lên server. Vui lòng thử Lưu lại hoặc bấm Lưu hàng hóa.',
        );
      } else if (result.variants.isNotEmpty || result.extraUnits.isNotEmpty) {
        NotificationOverlayManager().showSuccess(
          title: 'Thành công',
          message: 'Đã lưu thiết lập đơn vị tính và thuộc tính.',
        );
      }
    } else {
      NotificationOverlayManager().showWarning(
        title: 'Chưa lưu lên server',
        message:
            'Bấm «Lưu» trên form hàng hóa để ghi đơn vị tính và biến thể vào hệ thống.',
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

  /// Sau khi nạp từ server, ưu tiên số lượng thực tế trên DB.
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: PosTheme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Đơn vị tính',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          _inlineUnitRow(
            label: baseName,
            conversion: '1',
            price: _parseNum(_priceCtrl.text),
            isBase: true,
          ),
          ...extraUnits.map((u) => _inlineUnitRow(
                label: u.unitName,
                conversion: '${u.conversionRate} $baseName',
                price: u.basePrice,
              )),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openUnitAttributeSetup,
              icon: const Icon(Icons.add, size: 16, color: PosTheme.kiotBlue),
              label: const Text('Thêm đơn vị',
                  style: TextStyle(color: PosTheme.kiotBlue)),
            ),
          ),
          const Divider(height: 24),
          Row(
            children: [
              const Text('Hàng cùng loại',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const Spacer(),
              TextButton(
                onPressed: _openUnitAttributeSetup,
                child: const Text('Thiết lập giá'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_variants.isEmpty && extraUnits.isEmpty)
            Text(
              'Thêm đơn vị hoặc thuộc tính để sinh mã riêng từng loại',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: PosTheme.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  Container(
                    color: Colors.grey.shade50,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: const Row(
                      children: [
                        Expanded(flex: 2, child: Text('Đơn vị', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                        Expanded(child: Text('Mã hàng', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                        Expanded(child: Text('Giá vốn', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                        Expanded(child: Text('Giá bán', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                        Expanded(child: Text('Tồn', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                      ],
                    ),
                  ),
                  if (_variants.isNotEmpty)
                    ..._variants.map((v) => _inlineVariantRow(v))
                  else
                    _inlineUnitPreviewRow(baseName, _codeCtrl.text.trim(),
                        _parseNum(_costCtrl.text), _parseNum(_priceCtrl.text),
                        _parseNum(_stockCtrl.text)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _openUnitAttributeSetup,
            icon: const Icon(Icons.tune, size: 18, color: PosTheme.kiotBlue),
            label: const Text(
              'Thiết lập đơn vị tính và thuộc tính',
              style: TextStyle(color: PosTheme.kiotBlue),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              side: const BorderSide(color: PosTheme.kiotBlue),
            ),
          ),
        ],
      ),
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
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Text(conversion, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(
              NumberFormat('#,##0', 'vi_VN').format(price.round()),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (!isBase)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              onPressed: _openUnitAttributeSetup,
              tooltip: 'Sửa trong thiết lập',
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
          Expanded(flex: 2, child: Text(v.name, style: const TextStyle(fontSize: 12))),
          Expanded(child: Text(v.skuCode, style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(NumberFormat('#,##0', 'vi_VN').format(v.costPrice.round()), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(NumberFormat('#,##0', 'vi_VN').format(v.basePrice.round()), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(v.onHandQty.toStringAsFixed(0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
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
          Expanded(flex: 2, child: Text(unit, style: const TextStyle(fontSize: 12))),
          Expanded(child: Text(code.isEmpty ? '—' : code, style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(NumberFormat('#,##0', 'vi_VN').format(cost.round()), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(NumberFormat('#,##0', 'vi_VN').format(price.round()), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
          Expanded(child: Text(stock.toStringAsFixed(0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
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
              const Expanded(
                child: Text('Bán trực tiếp (hiện trên POS)',
                    style: TextStyle(fontSize: 13)),
              ),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Bỏ qua'),
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
                    : const Text('Lưu'),
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
          label: const Text('Chọn ảnh', style: TextStyle(color: PosTheme.primary)),
        ),
      ],
    );
  }

  Widget _infoFields() {
    final nameLabel =
        _isService ? 'Tên dịch vụ *' : 'Tên hàng *';
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
                    hint: 'Tự sinh nếu để trống',
                  ),
                ),
              ),
              if (_isGoods) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _barcodeCtrl,
                    decoration: PosTheme.inputDecoration(label: 'Mã vạch'),
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
            label: 'Thương hiệu',
            value: _brandId,
            items: _brands,
            onChanged: (v) => setState(() => _brandId = v),
            onCreate: () => _quickCreate(
              'thương hiệu',
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
            label: 'Vị trí',
            value: _locationId,
            items: _locations,
            onChanged: (v) => setState(() => _locationId = v),
            onCreate: () => _quickCreate(
              'vị trí',
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
                  decoration: PosTheme.inputDecoration(label: 'Giá vốn'),
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
            label: 'Nhà cung cấp',
            value: _supplierId,
            items: _suppliers,
            onChanged: (v) => setState(() => _supplierId = v),
            onCreate: () => _quickCreate(
              'nhà cung cấp',
              _api.createPosSupplier,
              (item) {
                _suppliers.add(item);
                _supplierId = item.id;
              },
            ),
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
                  decoration: PosTheme.inputDecoration(label: 'Tồn thấp nhất'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxStockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: PosTheme.inputDecoration(label: 'Tồn cao nhất'),
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
                  decoration: PosTheme.inputDecoration(label: 'Trọng lượng'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _weightUnit,
                  decoration: PosTheme.inputDecoration(label: 'ĐVT'),
                  items: const [
                    DropdownMenuItem(value: 'g', child: Text('g')),
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
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
    final priceLabel = _isService ? 'Giá dịch vụ' : 'Giá bán';
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
                  decoration: PosTheme.inputDecoration(label: 'Giá vốn'),
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
                border: Border.all(color: PosTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Tổng giá thành phần: ${_moneyFmt.format(_comboComponentsSum)}',
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
            decoration: PosTheme.inputDecoration(label: 'Đơn vị cơ bản'),
          ),
          const SizedBox(height: 16),
          const Text('Đơn vị quy đổi',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (_units.isEmpty)
            Text('Chưa có đơn vị quy đổi',
                style: TextStyle(color: PosTheme.textSecondary))
          else
            ..._units.map((u) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text(u.unitName +
                        (u.isBaseUnit ? ' (cơ bản)' : ' = ${u.conversionRate}')),
                    subtitle: Text('Giá: ${_moneyFmt.format(u.basePrice)}'),
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
                label: const Text('Thêm đơn vị',
                    style: TextStyle(color: PosTheme.primary)),
              ),
            ),
          const Divider(height: 32),
          const Text('Thuộc tính',
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
                          PosTheme.inputDecoration(label: 'Tên thuộc tính'),
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
                      decoration: PosTheme.inputDecoration(label: 'Giá trị'),
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
            label: const Text('Thêm thuộc tính',
                style: TextStyle(color: PosTheme.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantsTab() {
    if (!_isEditing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Lưu sản phẩm trước để quản lý biến thể',
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
          const Text('Tạo biến thể từ thuộc tính',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            'Nhập tên thuộc tính và các giá trị cách nhau bởi dấu phẩy',
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
                          PosTheme.inputDecoration(label: 'Thuộc tính'),
                      onChanged: (v) => a.attributeName = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: a.valuesText,
                      decoration: PosTheme.inputDecoration(
                        label: 'Giá trị',
                        hint: 'Đỏ, Xanh, Vàng',
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
                label: const Text('Thêm thuộc tính',
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
                label: const Text('Tạo biến thể'),
              ),
            ],
          ),
          const Divider(height: 32),
          Text('Biến thể (${_variants.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (_variants.isEmpty)
            Text('Chưa có biến thể',
                style: TextStyle(color: PosTheme.textSecondary))
          else
            ..._variants.map((v) => _variantCard(v)),
        ],
      ),
    );
  }

  Widget _variantCard(PosProductVariant v) {
    final priceCtrl =
        TextEditingController(text: v.basePrice.toStringAsFixed(0));
    final costCtrl = TextEditingController(text: v.costPrice.toStringAsFixed(0));
    final unitOnly = variantIsBaseUnitOnly(v);
    final stockCtrl = TextEditingController(
        text: v.onHandQty.toStringAsFixed(0));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (v.skuCode.isNotEmpty)
              Text('SKU: ${v.skuCode}',
                  style: TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: costCtrl,
                    keyboardType: TextInputType.number,
                    decoration: PosTheme.inputDecoration(label: 'Giá vốn'),
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
                      label: unitOnly ? 'Tồn (quy đổi)' : 'Tồn',
                      hint: unitOnly ? 'Sửa ô Tồn kho chính theo đơn vị cơ bản' : null,
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
                child: const Text('Lưu biến thể',
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PosTheme.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Tổng giá thành phần: ${_moneyFmt.format(_comboComponentsSum)}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: PosTheme.primaryDark,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Thành phần combo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (_comboLines.isEmpty)
            Text('Chưa có thành phần',
                style: TextStyle(color: PosTheme.textSecondary))
          else
            ..._comboLines.asMap().entries.map((e) {
              final i = e.key;
              final c = e.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(c.componentProductName.isNotEmpty
                      ? c.componentProductName
                      : c.componentProductId),
                  subtitle: Text(
                    'SL: ${c.qty} · Giá: ${_moneyFmt.format(c.componentBasePrice)}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => setState(() => _comboLines.removeAt(i)),
                  ),
                ),
              );
            }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addComboComponent,
              icon: const Icon(Icons.add, color: PosTheme.primary),
              label: const Text('Thêm thành phần',
                  style: TextStyle(color: PosTheme.primary)),
            ),
          ),
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
          const Text('Mô tả',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
          const SizedBox(height: 8),
          _kiotDescToolbar(),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            maxLines: 10,
            minLines: 10,
            decoration: InputDecoration(
              hintText: 'Mô tả chi tiết sản phẩm…',
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
          const Text(
            'Ghi chú nhanh khi bán hàng',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          const SizedBox(height: 8),
          PosSaleQuickNotesListEditor(
            notes: _saleQuickNotes,
            onChanged: (v) => setState(() => _saleQuickNotes = v),
          ),
        ],
      ),
    );
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
          btn(Icons.format_bold, 'In đậm'),
          btn(Icons.format_italic, 'In nghiêng'),
          btn(Icons.format_underlined, 'Gạch chân'),
          const VerticalDivider(width: 16),
          btn(Icons.format_align_left, 'Căn trái'),
          btn(Icons.format_align_center, 'Căn giữa'),
          btn(Icons.format_align_right, 'Căn phải'),
          const VerticalDivider(width: 16),
          btn(Icons.format_list_bulleted, 'Danh sách'),
          btn(Icons.format_list_numbered, 'Danh sách số'),
          const Spacer(),
          btn(Icons.link, 'Liên kết'),
          btn(Icons.image_outlined, 'Ảnh'),
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
                      DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
          if (manageKind != null)
            TextButton(
              onPressed: () => _manageCatalog(manageKind),
              child: Text(
                'Quản lý',
                style: TextStyle(
                  color: _isGoods
                      ? PosTheme.textSecondary
                      : PosTheme.textSecondary,
                ),
              ),
            ),
          TextButton(
            onPressed: onCreate,
            child: Text(
              'Tạo mới',
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
    final rateCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm đơn vị quy đổi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: PosTheme.inputDecoration(label: 'Tên đơn vị'),
            ),
            TextField(
              controller: rateCtrl,
              decoration: PosTheme.inputDecoration(
                label: 'Quy đổi (× đơn vị cơ bản)',
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
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: PosTheme.filledButtonStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Thêm'),
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
    String? pickedId;
    final qtyCtrl = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm thành phần combo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              decoration: PosTheme.inputDecoration(label: 'Hàng hóa'),
              items: _allProductsForCombo
                  .where((p) => p.id != widget.product?.id)
                  .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text('${p.productCode} — ${p.name}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => pickedId = v,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: PosTheme.inputDecoration(label: 'Số lượng'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: PosTheme.filledButtonStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
    if (ok != true || pickedId == null) return;
    final prod = _allProductsForCombo.firstWhere((p) => p.id == pickedId);
    setState(() {
      _comboLines.add(PosComboLine(
        id: '',
        componentProductId: pickedId!,
        componentProductCode: prod.productCode,
        componentProductName: prod.name,
        qty: double.tryParse(qtyCtrl.text) ?? 1,
        componentBasePrice: prod.basePrice,
      ));
    });
  }
}
