import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../../services/api_service.dart';
import '../../utils/number_formatter.dart';
import '../notification_overlay.dart';
import '../pos_barcode_scanner.dart';
import 'pos_theme.dart';

/// Dữ liệu mở dialog «Thiết lập đơn vị tính và thuộc tính» (kiểu KiotViet).
class UnitAttributeSetupInput {
  const UnitAttributeSetupInput({
    required this.baseUnitName,
    required this.basePrice,
    required this.costPrice,
    required this.baseDirectSale,
    this.productCode,
    this.barcode,
    this.extraUnits = const [],
    this.attributeRows = const [],
    this.variants = const [],
    this.productId,
    this.productPatch,
    this.startInAddMoreMode = false,
    this.focusVariantId,
  });

  final String baseUnitName;
  final double basePrice;
  final double costPrice;
  final bool baseDirectSale;
  final String? productCode;
  final String? barcode;
  final List<PosProductUnit> extraUnits;
  final List<UnitAttributeRowInput> attributeRows;
  final List<PosProductVariant> variants;
  final String? productId;
  final Map<String, dynamic>? productPatch;
  /// Mở dialog ở chế độ nhập thêm giá trị thuộc tính (hàng cùng loại).
  final bool startInAddMoreMode;
  /// Bôi đậm / cuộn tới hàng cùng loại cần sửa (từ danh sách hàng).
  final String? focusVariantId;
}

class UnitAttributeRowInput {
  const UnitAttributeRowInput({
    this.attributeId = '',
    this.attributeName = '',
    this.valuesText = '',
  });

  final String attributeId;
  final String attributeName;
  final String valuesText;
}

/// Kết quả sau khi bấm Lưu trong dialog.
class UnitAttributeSetupResult {
  const UnitAttributeSetupResult({
    required this.baseUnitName,
    required this.basePrice,
    required this.costPrice,
    required this.baseDirectSale,
    this.productCode,
    this.barcode,
    required this.extraUnits,
    required this.attributeRows,
    required this.variants,
    this.addAnotherSameType = false,
  });

  final String baseUnitName;
  final double basePrice;
  final double costPrice;
  final bool baseDirectSale;
  final String? productCode;
  final String? barcode;
  final List<PosProductUnit> extraUnits;
  final List<UnitAttributeRowInput> attributeRows;
  final List<PosProductVariant> variants;
  /// Bấm «Lưu & Thêm hàng hóa cùng loại» — mở lại để nhập thêm giá trị thuộc tính.
  final bool addAnotherSameType;
}

class _EditableUnit {
  _EditableUnit({
    this.id,
    required String name,
    required double rate,
    required double price,
    this.isDirectSale = true,
    this.isBase = false,
    bool autoPrice = false,
  })  : nameCtrl = TextEditingController(text: name),
        rateCtrl = TextEditingController(
            text: isBase ? '1' : _fmtRate(rate)),
        priceCtrl = TextEditingController(text: _fmtMoney(price)),
        priceAuto = autoPrice || (!isBase && price <= 0);

  String? id;
  final TextEditingController nameCtrl;
  final TextEditingController rateCtrl;
  final TextEditingController priceCtrl;
  bool isDirectSale;
  final bool isBase;

  static String _fmtMoney(double v) {
    if (v == 0) return '0';
    return NumberFormat('#,###', 'vi_VN').format(v.round());
  }

  static double _parseMoney(String text) {
    final n = parseFormattedNumber(text);
    return n?.toDouble() ?? 0;
  }

  static String _fmtRate(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void dispose() {
    nameCtrl.dispose();
    rateCtrl.dispose();
    priceCtrl.dispose();
  }

  double get rate {
    final t = rateCtrl.text.trim().replaceAll(',', '.');
    return (double.tryParse(t) ?? 1).clamp(0.0001, double.infinity);
  }
  double get price => _parseMoney(priceCtrl.text);
  bool priceAuto;

  /// Gợi ý giá bán = giá ĐVT cơ bản × quy đổi (KiotViet).
  void applySuggestedPrice(double basePrice) {
    if (!isBase && priceAuto) {
      priceCtrl.text = _fmtMoney(basePrice * rate);
    }
  }
}

class _EditableAttr {
  _EditableAttr({
    this.attributeId = '',
    String attributeName = '',
    String valuesText = '',
  })  : nameCtrl = TextEditingController(text: attributeName),
        valuesCtrl = TextEditingController(text: valuesText);

  String attributeId;
  final TextEditingController nameCtrl;
  final TextEditingController valuesCtrl;

  void dispose() {
    nameCtrl.dispose();
    valuesCtrl.dispose();
  }
}

class _RelatedRow {
  _RelatedRow({
    this.variantId,
    required this.attrLabel,
    required this.unitName,
    required this.conversion,
    required this.isBaseUnit,
    this.attrMap = const {},
    String skuCode = '',
    String barcode = '',
    double cost = 0,
    double price = 0,
    double onHandQty = 0,
  })  : codeCtrl = TextEditingController(text: skuCode),
        barcodeCtrl = TextEditingController(text: barcode),
        costCtrl = TextEditingController(
            text: _EditableUnit._fmtMoney(cost)),
        priceCtrl = TextEditingController(
            text: _EditableUnit._fmtMoney(price)),
        stockCtrl = TextEditingController(
            text: onHandQty == onHandQty.roundToDouble()
                ? onHandQty.toStringAsFixed(0)
                : onHandQty.toString());

  String? variantId;
  final String attrLabel;
  final String unitName;
  final double conversion;
  final bool isBaseUnit;
  final Map<String, String> attrMap;
  final TextEditingController codeCtrl;
  final TextEditingController barcodeCtrl;
  final TextEditingController costCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController stockCtrl;

  String get rowKey => '$attrLabel|$unitName|$conversion';

  void dispose() {
    codeCtrl.dispose();
    barcodeCtrl.dispose();
    costCtrl.dispose();
    priceCtrl.dispose();
    stockCtrl.dispose();
  }

  double get cost => _EditableUnit._parseMoney(costCtrl.text);
  double get price => _EditableUnit._parseMoney(priceCtrl.text);
  double get onHandQty => _EditableUnit._parseMoney(stockCtrl.text);

  void syncFromUnit(_EditableUnit unit, double baseCost) {
    priceCtrl.text = _EditableUnit._fmtMoney(unit.price);
    costCtrl.text = _EditableUnit._fmtMoney(baseCost * conversion);
  }
}

/// Mở dialog thiết lập đơn vị & thuộc tính kiểu KiotViet.
Future<UnitAttributeSetupResult?> showUnitAttributeSetupDialog(
  BuildContext context, {
  required UnitAttributeSetupInput input,
}) {
  return showDialog<UnitAttributeSetupResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UnitAttributeSetupDialog(input: input),
  );
}

class _UnitAttributeSetupDialog extends StatefulWidget {
  const _UnitAttributeSetupDialog({required this.input});

  final UnitAttributeSetupInput input;

  @override
  State<_UnitAttributeSetupDialog> createState() =>
      _UnitAttributeSetupDialogState();
}

class _UnitAttributeSetupDialogState extends State<_UnitAttributeSetupDialog> {
  final _api = ApiService();
  static final _moneyFmt = NumberFormat('#,###', 'vi_VN');

  late _EditableUnit _baseUnit;
  final List<_EditableUnit> _extraUnits = [];
  final List<_EditableAttr> _attrs = [];
  final List<_RelatedRow> _relatedRows = [];
  List<PosCatalogItem> _attrCatalog = [];
  bool _loading = true;
  bool _saving = false;
  double _baseCost = 0;
  final Set<String> _manualCostRows = {};
  /// Biến thể / dòng user đã xóa khỏi bảng — không khôi phục khi rebuild.
  final Set<String> _removedVariantIds = {};
  final Set<String> _removedRowKeys = {};

  bool get _usesSharedUnitStock {
    for (final a in _attrs) {
      if (_splitAttrValues(a.valuesCtrl.text).isNotEmpty) return false;
    }
    return true;
  }

  double get _baseSellPrice => _baseUnit.price;

  /// Chỉ dòng đơn vị cơ bản, không thuộc tính — đại diện SP cha (mã cha).
  bool _isParentOnlyRow(_RelatedRow row) =>
      row.isBaseUnit && row.attrLabel.isEmpty;

  /// Hàng cùng loại cần mã riêng và đồng bộ lên server.
  bool _isVariantRow(_RelatedRow row) => !_isParentOnlyRow(row);

  _EditableUnit? _findUnitByName(String name) {
    for (final u in _allUnits) {
      if (u.nameCtrl.text.trim() == name) return u;
    }
    return null;
  }

  /// Đồng bộ giá bán + giá vốn bảng «Hàng cùng loại» từ đơn vị tính (KiotViet).
  void _syncTableFromUnits({bool refreshCost = true}) {
    for (final row in _relatedRows) {
      final unit = _findUnitByName(row.unitName);
      if (unit != null) {
        row.priceCtrl.text = _EditableUnit._fmtMoney(unit.price);
      }
      if (refreshCost && !_manualCostRows.contains(row.rowKey)) {
        row.costCtrl.text =
            _EditableUnit._fmtMoney(_baseCost * row.conversion);
      }
    }
  }

  void _onRowCostEdited(_RelatedRow row, String text) {
    _manualCostRows.add(row.rowKey);
    if (row.isBaseUnit) {
      _baseCost = _EditableUnit._parseMoney(text);
    }
  }

  void _applyAutoCostFromBase() {
    for (final row in _relatedRows) {
      if (_manualCostRows.contains(row.rowKey)) continue;
      row.costCtrl.text =
          _EditableUnit._fmtMoney(_baseCost * row.conversion);
    }
  }

  void _onBasePriceChanged() {
    for (final u in _extraUnits) {
      u.applySuggestedPrice(_baseSellPrice);
    }
    setState(() => _rebuildRelatedRows());
  }

  void _onExtraUnitRateChanged(_EditableUnit u) {
    u.applySuggestedPrice(_baseSellPrice);
    setState(() => _rebuildRelatedRows(preserveMeta: true));
  }

  void _scheduleRebuild({bool preserveMeta = false}) {
    _rebuildRelatedRows(preserveMeta: preserveMeta);
  }

  List<String> _splitAttrValues(String text) =>
      text
          .split(RegExp(r'[,;]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

  Future<void> _pickAttrFromCatalog(_EditableAttr a) async {
    if (_attrCatalog.isEmpty) {
      await _quickCreateAttribute(a);
      return;
    }
    const createNew = '__create_new__';
    final picked = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add, color: PosTheme.kiotBlue),
              title: const Text('Tạo thuộc tính mới',
                  style: TextStyle(color: PosTheme.kiotBlue)),
              onTap: () => Navigator.pop(ctx, createNew),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _attrCatalog
                    .map((c) => ListTile(
                          title: Text(c.name),
                          onTap: () => Navigator.pop(ctx, c),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == createNew) {
      await _quickCreateAttribute(a);
      return;
    }
    if (picked is! PosCatalogItem) return;
    setState(() {
      a.attributeId = picked.id;
      a.nameCtrl.text = picked.name;
      _scheduleRebuild(preserveMeta: true);
    });
  }

  Future<void> _quickCreateAttribute(_EditableAttr a) async {
    final ctrl = TextEditingController(text: a.nameCtrl.text.trim());
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo thuộc tính mới'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: PosTheme.inputDecoration(
            label: 'Tên thuộc tính',
            hint: 'HƯƠNG VỊ, Màu sắc...',
          ),
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
    final res = await _api.createPosProductAttribute(name);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] != null) {
      final item =
          PosCatalogItem.fromJson(res['data'] as Map<String, dynamic>);
      setState(() {
        _attrCatalog.add(item);
        a.attributeId = item.id;
        a.nameCtrl.text = item.name;
        _scheduleRebuild(preserveMeta: true);
      });
    } else {
      setState(() {
        a.nameCtrl.text = name;
        _scheduleRebuild(preserveMeta: true);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _baseCost = widget.input.costPrice;
    _baseUnit = _EditableUnit(
      name: widget.input.baseUnitName,
      rate: 1,
      price: widget.input.basePrice,
      isDirectSale: widget.input.baseDirectSale,
      isBase: true,
    );
    for (final u in widget.input.extraUnits) {
      final eu = _EditableUnit(
        id: u.id.isEmpty ? null : u.id,
        name: u.unitName,
        rate: u.conversionRate,
        price: u.basePrice,
        isDirectSale: u.isDirectSale,
        autoPrice: u.basePrice <= 0,
      );
      if (eu.priceAuto) {
        eu.applySuggestedPrice(widget.input.basePrice);
      }
      _extraUnits.add(eu);
    }
    for (final a in widget.input.attributeRows) {
      _attrs.add(_EditableAttr(
        attributeId: a.attributeId,
        attributeName: a.attributeName,
        valuesText: a.valuesText,
      ));
    }
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final res = await _api.getPosProductAttributes();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      _attrCatalog = (res['data'] as List)
          .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    _rebuildRelatedRows(preserveMeta: true);
    _ensureVariantSkus();
    if (widget.input.startInAddMoreMode) {
      _prepareAddMoreSameType();
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _baseUnit.dispose();
    for (final u in _extraUnits) {
      u.dispose();
    }
    for (final a in _attrs) {
      a.dispose();
    }
    for (final r in _relatedRows) {
      r.dispose();
    }
    super.dispose();
  }

  List<_EditableUnit> get _allUnits => [_baseUnit, ..._extraUnits];

  String? _parentProductCode() {
    for (final row in _relatedRows) {
      if (_isParentOnlyRow(row)) {
        final code = row.codeCtrl.text.trim();
        if (code.isNotEmpty) return code;
      }
    }
    final fromInput = widget.input.productCode?.trim();
    return (fromInput != null && fromInput.isNotEmpty) ? fromInput : null;
  }

  String? _parentBarcode() {
    for (final row in _relatedRows) {
      if (_isParentOnlyRow(row)) {
        final bc = row.barcodeCtrl.text.trim();
        if (bc.isNotEmpty) return bc;
      }
    }
    final fromInput = widget.input.barcode?.trim();
    return (fromInput != null && fromInput.isNotEmpty) ? fromInput : null;
  }

  String _slugPart(String raw) {
    final s = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
        .replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e')
        .replaceAll(RegExp(r'[ìíịỉĩ]'), 'i')
        .replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
        .replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u')
        .replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y')
        .replaceAll(RegExp(r'[đ]'), 'd')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return s.length > 16 ? s.substring(0, 16) : s;
  }

  /// Mã hàng riêng cho từng hàng cùng loại (KiotViet: không trùng mã cha).
  String _suggestVariantSku(String productCode, _RelatedRow row, int index) {
    final base = productCode.trim().isEmpty ? 'SP' : productCode.trim();
    final parts = <String>[];
    if (row.attrLabel.isNotEmpty) parts.add(_slugPart(row.attrLabel));
    if (!row.isBaseUnit && row.unitName.isNotEmpty) {
      parts.add(_slugPart(row.unitName));
    }
    if (parts.isEmpty) {
      return '$base-V${index.toString().padLeft(2, '0')}';
    }
    final sku = '$base-${parts.join('-')}';
    return sku.length > 50 ? sku.substring(0, 50) : sku;
  }

  void _ensureVariantSkus() {
    final parentCode = widget.input.productCode?.trim() ?? '';
    final used = <String>{
      if (parentCode.isNotEmpty) parentCode,
    };
    var seq = 0;
    for (final row in _relatedRows) {
      if (!_isVariantRow(row)) continue;
      seq++;
      var code = row.codeCtrl.text.trim();
      if (code.isEmpty ||
          (parentCode.isNotEmpty && code == parentCode) ||
          used.contains(code)) {
        var attempt = seq;
        code = _suggestVariantSku(parentCode, row, attempt);
        while (used.contains(code) && attempt < seq + 100) {
          attempt++;
          code = _suggestVariantSku(parentCode, row, attempt);
        }
        row.codeCtrl.text = code;
      }
      used.add(code);
    }
  }

  void _rebuildRelatedRows({bool preserveMeta = false}) {
    final oldMeta = <String,
        ({
          String? variantId,
          String code,
          String barcode,
          double? cost,
          double? price,
          double? onHandQty,
        })>{};
    if (preserveMeta) {
      for (final r in _relatedRows) {
        oldMeta[r.rowKey] = (
          variantId: r.variantId,
          code: r.codeCtrl.text,
          barcode: r.barcodeCtrl.text,
          cost: r.cost,
          price: r.price,
          onHandQty: r.onHandQty,
        );
      }
      for (final v in widget.input.variants) {
        if (_removedVariantIds.contains(v.id)) continue;
        final parsed = _parseVariantJson(v.attributeJson);
        final key =
            '${parsed.attrLabel}|${parsed.unitName}|${parsed.conversion}';
        if (_removedRowKeys.contains(key)) continue;
        if (!oldMeta.containsKey(key)) {
          oldMeta[key] = (
            variantId: v.id,
            code: v.skuCode,
            barcode: v.barcode ?? '',
            cost: v.costPrice,
            price: v.basePrice,
            onHandQty: v.onHandQty,
          );
        }
      }
    }

    for (final r in _relatedRows) {
      r.dispose();
    }
    _relatedRows.clear();

    final combos = _buildAttrCombos();
    for (final combo in combos) {
      for (final unit in _allUnits) {
        final unitName = unit.nameCtrl.text.trim();
        if (unitName.isEmpty) continue;
        final conv = unit.isBase ? 1.0 : unit.rate;
        final key = '${combo.label}|$unitName|$conv';
        if (_removedRowKeys.contains(key)) continue;
        final meta = preserveMeta ? oldMeta[key] : null;

        final isParentOnly = unit.isBase && combo.label.isEmpty;
        final sku = meta != null && meta.code.isNotEmpty
            ? meta.code
            : (isParentOnly ? (widget.input.productCode ?? '') : '');
        final barcode = meta != null && meta.barcode.isNotEmpty
            ? meta.barcode
            : (isParentOnly ? (widget.input.barcode ?? '') : '');

        _relatedRows.add(_RelatedRow(
          variantId: meta?.variantId,
          attrLabel: combo.label,
          unitName: unitName,
          conversion: conv,
          isBaseUnit: unit.isBase,
          attrMap: combo.map,
          skuCode: sku,
          barcode: barcode,
          cost: meta?.cost ?? (_baseCost * conv),
          price: unit.price,
          onHandQty: meta?.onHandQty ?? 0,
        ));
      }
    }
    _ensureVariantSkus();
    // Luôn đồng bộ giá từ đơn vị → bảng (giống KiotViet)
    _syncTableFromUnits(refreshCost: !preserveMeta);
  }

  ({String attrLabel, String unitName, double conversion, bool isBaseUnit})
      _parseVariantJson(String? json) {
    if (json == null || json.isEmpty) {
      return (
        attrLabel: '',
        unitName: widget.input.baseUnitName,
        conversion: 1,
        isBaseUnit: true,
      );
    }
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final unitName = (map['_unit'] ?? widget.input.baseUnitName).toString();
      final conv = double.tryParse('${map['_conversion']}') ?? 1;
      final parts = <String>[];
      for (final e in map.entries) {
        if (!e.key.startsWith('_') && '${e.value}'.trim().isNotEmpty) {
          parts.add('${e.value}');
        }
      }
      return (
        attrLabel: parts.join(' / '),
        unitName: unitName,
        conversion: conv,
        isBaseUnit: conv == 1 && parts.isEmpty,
      );
    } catch (_) {
      return (
        attrLabel: '',
        unitName: widget.input.baseUnitName,
        conversion: 1,
        isBaseUnit: true,
      );
    }
  }

  List<({String label, bool isDefault, Map<String, String> map})>
      _buildAttrCombos() {
    final active = <({String name, List<String> values})>[];
    for (final a in _attrs) {
      final values = _splitAttrValues(a.valuesCtrl.text);
      if (values.isEmpty) continue;
      final name = a.nameCtrl.text.trim();
      active.add((
        name: name.isEmpty ? 'Thuộc tính' : name,
        values: values,
      ));
    }

    if (active.isEmpty) {
      return [(label: '', isDefault: true, map: <String, String>{})];
    }

    var combos = <({String label, bool isDefault, Map<String, String> map})>[];

    for (final attr in active) {
      if (combos.isEmpty) {
        for (final val in attr.values) {
          combos.add((
            label: val,
            isDefault: false,
            map: {attr.name: val},
          ));
        }
      } else {
        final next = <({String label, bool isDefault, Map<String, String> map})>[];
        for (final partial in combos) {
          for (final val in attr.values) {
            final m = Map<String, String>.from(partial.map);
            m[attr.name] = val;
            next.add((
              label: m.values.join(' / '),
              isDefault: false,
              map: m,
            ));
          }
        }
        combos = next;
      }
    }

    return combos.isEmpty
        ? [(label: '', isDefault: true, map: <String, String>{})]
        : combos;
  }

  void _addUnit() {
    setState(() {
      final u = _EditableUnit(name: '', rate: 1, price: 0, autoPrice: true);
      u.applySuggestedPrice(_baseSellPrice);
      _extraUnits.add(u);
      _rebuildRelatedRows(preserveMeta: true);
    });
  }

  void _removeUnit(int i) {
    setState(() {
      _extraUnits[i].dispose();
      _extraUnits.removeAt(i);
      _rebuildRelatedRows(preserveMeta: true);
    });
  }

  void _addAttr() {
    setState(() {
      _attrs.add(_EditableAttr());
      _rebuildRelatedRows(preserveMeta: true);
    });
  }

  void _removeAttr(int i) {
    setState(() {
      _attrs[i].dispose();
      _attrs.removeAt(i);
      _rebuildRelatedRows(preserveMeta: true);
    });
  }

  void _removeRelatedRow(int index) {
    final row = _relatedRows[index];
    if (_isParentOnlyRow(row)) {
      NotificationOverlayManager().showError(
        title: 'Không thể xóa',
        message: 'Không thể xóa dòng đơn vị cơ bản của hàng hóa',
      );
      return;
    }
    setState(() {
      _removedRowKeys.add(row.rowKey);
      if (_isValidGuid(row.variantId)) {
        _removedVariantIds.add(row.variantId!);
      }
      row.dispose();
      _relatedRows.removeAt(index);
    });
  }

  Future<void> _openPriceSetup() async {
    var mode = 'unit_prices';
    final marginCtrl = TextEditingController(text: '30');
    final baseCost = widget.input.costPrice;
    final uniformCostCtrl = TextEditingController(
      text: _EditableUnit._fmtMoney(baseCost),
    );

    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.settings, size: 20, color: PosTheme.kiotBlue),
              SizedBox(width: 8),
              Text('Thiết lập giá'),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RadioListTile<String>(
                  value: 'unit_prices',
                  groupValue: mode,
                  onChanged: (v) => setDlg(() => mode = v!),
                  title: const Text('Lấy giá bán từ đơn vị tính'),
                  subtitle: const Text(
                    'Áp giá bán đã nhập ở phần đơn vị cho từng dòng hàng cùng loại',
                    style: TextStyle(fontSize: 12),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  value: 'cost_by_conversion',
                  groupValue: mode,
                  onChanged: (v) => setDlg(() => mode = v!),
                  title: const Text('Giá vốn theo quy đổi'),
                  subtitle: Text(
                    'Giá vốn = ${_moneyFmt.format(baseCost)} × hệ số quy đổi',
                    style: const TextStyle(fontSize: 12),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  value: 'uniform_cost',
                  groupValue: mode,
                  onChanged: (v) => setDlg(() => mode = v!),
                  title: const Text('Giá vốn đồng nhất cho tất cả dòng'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                if (mode == 'uniform_cost')
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 8),
                    child: TextField(
                      controller: uniformCostCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandSeparatorFormatter()],
                      decoration: PosTheme.inputDecoration(label: 'Giá vốn'),
                    ),
                  ),
                RadioListTile<String>(
                  value: 'margin',
                  groupValue: mode,
                  onChanged: (v) => setDlg(() => mode = v!),
                  title: const Text('Giá bán = giá vốn + % lợi nhuận'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                if (mode == 'margin')
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: TextField(
                      controller: marginCtrl,
                      keyboardType: TextInputType.number,
                      decoration: PosTheme.inputDecoration(label: '% lợi nhuận'),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bỏ qua'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
              child: const Text('Áp dụng'),
            ),
          ],
        ),
      ),
    );

    final uniformCost =
        _EditableUnit._parseMoney(uniformCostCtrl.text);
    final marginPct =
        double.tryParse(marginCtrl.text.trim()) ?? 0;
    marginCtrl.dispose();
    uniformCostCtrl.dispose();
    if (applied != true || !mounted) return;

    setState(() {
      for (final row in _relatedRows) {
        final unit = _findUnitByName(row.unitName);
        switch (mode) {
          case 'unit_prices':
            if (unit != null) {
              row.priceCtrl.text = _EditableUnit._fmtMoney(unit.price);
            }
            break;
          case 'cost_by_conversion':
            _manualCostRows.remove(row.rowKey);
            row.costCtrl.text =
                _EditableUnit._fmtMoney(_baseCost * row.conversion);
            break;
          case 'uniform_cost':
            _manualCostRows.remove(row.rowKey);
            row.costCtrl.text = _EditableUnit._fmtMoney(uniformCost);
            break;
          case 'margin':
            row.priceCtrl.text = _EditableUnit._fmtMoney(
                row.cost * (1 + marginPct / 100));
            if (unit != null && !unit.isBase) {
              unit.priceCtrl.text = row.priceCtrl.text;
              unit.priceAuto = false;
            } else if (unit != null && unit.isBase) {
              unit.priceCtrl.text = row.priceCtrl.text;
            }
            break;
        }
      }
      // Đồng bộ giá bán từ đơn vị; cập nhật giá vốn theo quy đổi nếu cần
      if (mode == 'unit_prices') {
        for (final row in _relatedRows) {
          final unit = _findUnitByName(row.unitName);
          if (unit != null) {
            row.priceCtrl.text = _EditableUnit._fmtMoney(unit.price);
          }
        }
      }
    });
  }

  Future<void> _save({bool addMore = false}) async {
    final baseName = _baseUnit.nameCtrl.text.trim();
    if (baseName.isEmpty) {
      _showError('Nhập tên đơn vị cơ bản');
      return;
    }

    setState(() => _saving = true);

    try {
      final productId = widget.input.productId;
      if (productId == null || productId.isEmpty) {
        if (mounted) setState(() => _saving = false);
        if (addMore) {
          _showError(
            'Lưu hàng hóa trước khi thêm hàng cùng loại lên server.',
          );
          return;
        }
        if (!mounted) return;
        Navigator.pop(context, _buildSaveResult(addAnotherSameType: false));
        return;
      }

      if (productId.isNotEmpty) {
        final ok = await _persistToServer(productId);
        if (!ok) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        if (addMore) {
          await _reloadAfterSave(productId);
          if (!mounted) return;
          setState(() {
            _saving = false;
            _prepareAddMoreSameType();
            _rebuildRelatedRows(preserveMeta: true);
          });
          _showSuccess(
            'Đã lưu. Nhập thêm giá trị thuộc tính cho hàng cùng loại.',
          );
          return;
        }
      }

      if (!mounted) return;
      setState(() => _saving = false);

      ScreenRefreshNotifier.refreshPosProducts();
      ScreenRefreshNotifier.refreshPosSellProductGrid();
      final result = _buildSaveResult(addAnotherSameType: addMore);
      Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showError('Lưu thất bại: $e');
      }
    }
  }

  UnitAttributeSetupResult _buildSaveResult({bool addAnotherSameType = false}) {
    final baseName = _baseUnit.nameCtrl.text.trim();
    final baseRow = _relatedRows.cast<_RelatedRow?>().firstWhere(
          (r) => r!.isBaseUnit,
          orElse: () => null,
        );

    final extraUnitModels = <PosProductUnit>[];
    for (final u in _extraUnits) {
      final name = u.nameCtrl.text.trim();
      if (name.isEmpty) continue;
      extraUnitModels.add(PosProductUnit(
        id: u.id ?? '',
        unitName: name,
        conversionRate: u.rate,
        basePrice: u.price,
        isDirectSale: u.isDirectSale,
      ));
    }

    final attrRows = _attrs
        .map((a) => UnitAttributeRowInput(
              attributeId: a.attributeId,
              attributeName: a.nameCtrl.text.trim(),
              valuesText: a.valuesCtrl.text.trim(),
            ))
        .where((a) =>
            a.attributeName.isNotEmpty && a.valuesText.isNotEmpty)
        .toList();

    final variantModels = <PosProductVariant>[];
    for (final row in _relatedRows) {
      if (!_isVariantRow(row)) continue;
      variantModels.add(PosProductVariant(
        id: row.variantId ?? '',
        skuCode: row.codeCtrl.text.trim(),
        barcode: row.barcodeCtrl.text.trim().isEmpty
            ? null
            : row.barcodeCtrl.text.trim(),
        name: row.attrLabel.isEmpty
            ? row.unitName
            : '${row.attrLabel} · ${row.unitName}',
        attributeJson: _buildAttrJson(row),
        costPrice: row.cost,
        basePrice: row.price,
        onHandQty: row.onHandQty,
      ));
    }

    return UnitAttributeSetupResult(
      baseUnitName: baseName,
      basePrice: _baseUnit.price,
      costPrice: baseRow?.cost ?? _baseCost,
      baseDirectSale: _baseUnit.isDirectSale,
      productCode: _parentProductCode(),
      barcode: _parentBarcode(),
      extraUnits: extraUnitModels,
      attributeRows: attrRows,
      variants: variantModels,
      addAnotherSameType: addAnotherSameType,
    );
  }

  /// KiotViet: giữ nguyên danh sách thuộc tính, chỉ thêm ô nhập giá trị mới.
  void _prepareAddMoreSameType() {
    if (_attrs.isEmpty) {
      _attrs.add(_EditableAttr());
      return;
    }
    final target = _attrs.last;
    final current = target.valuesCtrl.text.trim();
    target.valuesCtrl.text =
        current.isEmpty ? '' : '$current, ';
    target.valuesCtrl.selection = TextSelection.collapsed(
      offset: target.valuesCtrl.text.length,
    );
  }

  Future<void> _reloadAfterSave(String productId) async {
    final unitsRes = await _api.getPosProductUnits(productId);
    if (unitsRes['isSuccess'] == true && unitsRes['data'] is List) {
      for (final e in unitsRes['data'] as List) {
        final u = PosProductUnit.fromJson(e as Map<String, dynamic>);
        if (u.isBaseUnit) continue;
        for (final eu in _extraUnits) {
          if (eu.nameCtrl.text.trim() == u.unitName) {
            eu.id = u.id;
          }
        }
      }
    }

    final varRes = await _api.getPosProductVariants(productId);
    if (varRes['isSuccess'] == true && varRes['data'] is List) {
      final variants = (varRes['data'] as List)
          .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
          .toList();
      for (final row in _relatedRows) {
        if (!_isVariantRow(row)) continue;
        for (final v in variants) {
          if (_variantMatchesRow(v, row)) {
            row.variantId = v.id;
            if (row.codeCtrl.text.trim().isEmpty) {
              row.codeCtrl.text = v.skuCode;
            }
            break;
          }
        }
      }
    }
  }

  bool _variantMatchesRow(PosProductVariant v, _RelatedRow row) {
    if (row.variantId != null &&
        row.variantId!.isNotEmpty &&
        v.id == row.variantId) {
      return true;
    }
    final parsed = _parseVariantJson(v.attributeJson);
    return parsed.attrLabel == row.attrLabel &&
        parsed.unitName == row.unitName &&
        parsed.conversion == row.conversion;
  }

  String _buildAttrJson(_RelatedRow row) {
    final map = Map<String, String>.from(row.attrMap);
    map['_unit'] = row.unitName;
    map['_conversion'] = row.conversion.toString();
    return jsonEncode(map);
  }

  /// Xóa trên server mọi biến thể không còn trong bảng (kể cả orphan cũ).
  Future<bool> _purgeServerVariantsExcept(
    String productId,
    Set<String> keepIds,
  ) async {
    final existingRes = await _api.getPosProductVariants(productId);
    if (existingRes['isSuccess'] != true || existingRes['data'] is! List) {
      return true;
    }
    for (final e in existingRes['data'] as List) {
      final v = PosProductVariant.fromJson(e as Map<String, dynamic>);
      if (keepIds.contains(v.id)) continue;
      final delRes = await _api.deletePosProductVariant(productId, v.id);
      if (delRes['isSuccess'] != true) {
        _showApiError(delRes);
        return false;
      }
    }
    return true;
  }

  Future<bool> _persistToServer(String productId) async {
    final baseName = _baseUnit.nameCtrl.text.trim();

    // Đồng bộ đơn vị quy đổi
    final existingRes = await _api.getPosProductUnits(productId);
    final existing = <String, PosProductUnit>{};
    if (existingRes['isSuccess'] == true && existingRes['data'] is List) {
      for (final e in existingRes['data'] as List) {
        final u = PosProductUnit.fromJson(e as Map<String, dynamic>);
        if (!u.isBaseUnit) existing[u.id] = u;
      }
    }

    final keepUnitIds = <String>{};
    for (final u in _extraUnits) {
      final name = u.nameCtrl.text.trim();
      if (name.isEmpty) continue;
      final body = {
        'unitName': name,
        'conversionRate': u.rate,
        'basePrice': u.price,
        'isDirectSale': u.isDirectSale,
      };

      var unitId = u.id;
      if (unitId == null || unitId.isEmpty) {
        for (final e in existing.values) {
          if (e.unitName == name) {
            unitId = e.id;
            u.id = unitId;
            break;
          }
        }
      }

      if (unitId != null && unitId.isNotEmpty) {
        keepUnitIds.add(unitId);
        final res = await _api.updatePosProductUnit(productId, unitId, body);
        if (res['isSuccess'] != true) {
          _showApiError(res);
          return false;
        }
      } else {
        final res = await _api.createPosProductUnit(productId, body);
        if (res['isSuccess'] != true) {
          _showApiError(res);
          return false;
        }
        if (res['data'] is Map) {
          final newId = (res['data'] as Map)['id']?.toString();
          if (newId != null && newId.isNotEmpty) {
            u.id = newId;
            keepUnitIds.add(newId);
          }
        }
      }
    }
    for (final e in existing.entries) {
      if (!keepUnitIds.contains(e.key)) {
        await _api.deletePosProductUnit(productId, e.key);
      }
    }

    // Cập nhật đơn vị cơ bản + sản phẩm cha
    final unitsRes = await _api.getPosProductUnits(productId);
    if (unitsRes['isSuccess'] == true && unitsRes['data'] is List) {
      var baseUpdated = false;
      for (final e in unitsRes['data'] as List) {
        final u = PosProductUnit.fromJson(e as Map<String, dynamic>);
        if (u.isBaseUnit) {
          final baseRes = await _api.updatePosProductUnit(productId, u.id, {
            'unitName': baseName,
            'conversionRate': 1,
            'basePrice': _baseUnit.price,
            'isDirectSale': _baseUnit.isDirectSale,
          });
          if (baseRes['isSuccess'] != true) {
            _showApiError(baseRes);
            return false;
          }
          baseUpdated = true;
          break;
        }
      }
      if (!baseUpdated) {
        _showError('Không tìm thấy đơn vị cơ bản trên server');
        return false;
      }
    }

    final baseRow = _relatedRows.cast<_RelatedRow?>().firstWhere(
          (r) => _isParentOnlyRow(r!),
          orElse: () => _relatedRows.cast<_RelatedRow?>().firstWhere(
                (r) => r!.isBaseUnit,
                orElse: () => null,
              ),
        );

    final patch = Map<String, dynamic>.from(widget.input.productPatch ?? {});
    patch['baseUnitName'] = baseName;
    patch['basePrice'] = _baseUnit.price;
    patch['costPrice'] = baseRow?.cost ?? _baseCost;
    patch['isDirectSale'] = _baseUnit.isDirectSale;
    final parentCode = _parentProductCode();
    if (parentCode != null && parentCode.isNotEmpty) {
      patch['productCode'] = parentCode;
    }
    final parentBarcode = _parentBarcode();
    if (parentBarcode != null && parentBarcode.isNotEmpty) {
      patch['barcode'] = parentBarcode;
    }
    // Lưu schema thuộc tính (1 dòng/attr, value = danh sách giá trị) để reload đúng
    patch['attributes'] = _attrs
        .map((a) => (
              id: a.attributeId,
              name: a.nameCtrl.text.trim(),
              values: _splitAttrValues(a.valuesCtrl.text),
            ))
        .where((a) => a.name.isNotEmpty && a.values.isNotEmpty)
        .map((a) => {
              if (a.id.isNotEmpty) 'attributeId': a.id,
              'attributeName': a.name,
              'value': a.values.join(', '),
            })
        .toList();

    final prodRes = await _api.updatePosProduct(productId, patch);
    if (prodRes['isSuccess'] != true) {
      _showApiError(prodRes);
      return false;
    }

    // Xóa trên server các biến thể không còn trong bảng (orphan + dòng user đã xóa)
    _ensureVariantSkus();
    final syncVariants = <Map<String, dynamic>>[];
    final keepVariantIds = <String>{};
    for (final row in _relatedRows) {
      if (!_isVariantRow(row)) continue;
      if (_isValidGuid(row.variantId)) keepVariantIds.add(row.variantId!);
      syncVariants.add({
        if (_isValidGuid(row.variantId)) 'id': row.variantId,
        'skuCode': row.codeCtrl.text.trim(),
        'barcode': row.barcodeCtrl.text.trim().isEmpty
            ? null
            : row.barcodeCtrl.text.trim(),
        'name': row.attrLabel.isEmpty
            ? row.unitName
            : '${row.attrLabel} · ${row.unitName}',
        'attributeJson': _buildAttrJson(row),
        'costPrice': row.cost,
        'basePrice': row.price,
        'onHandQty': row.onHandQty,
      });
    }
    for (final v in syncVariants) {
      final id = v['id']?.toString();
      if (_isValidGuid(id)) keepVariantIds.add(id!);
    }
    if (!await _purgeServerVariantsExcept(productId, keepVariantIds)) {
      return false;
    }

    final syncRes = await _api.syncPosProductVariants(productId, syncVariants);
    if (syncRes['isSuccess'] != true) {
      _showApiError(syncRes);
      return false;
    }

    _removedVariantIds.clear();
    _removedRowKeys.clear();

    // Xác minh số biến thể khớp với dữ liệu gửi lên
    if (syncVariants.isNotEmpty) {
      final verifyRes = await _api.getPosProductVariants(productId);
      final savedCount = verifyRes['isSuccess'] == true && verifyRes['data'] is List
          ? (verifyRes['data'] as List).length
          : 0;
      if (savedCount != syncVariants.length) {
        _showError(
          'Lưu biến thể chưa khớp (gửi ${syncVariants.length}, server $savedCount). Vui lòng thử lại.',
        );
        return false;
      }
    } else {
      final verifyRes = await _api.getPosProductVariants(productId);
      final savedCount = verifyRes['isSuccess'] == true && verifyRes['data'] is List
          ? (verifyRes['data'] as List).length
          : 0;
      if (savedCount > 0) {
        _showError(
          'Vẫn còn $savedCount hàng cùng loại trên server. Vui lòng thử lưu lại.',
        );
        return false;
      }
    }

    // Cập nhật id/sku từ server để lần lưu sau không gửi id cũ/invalid
    if (syncRes['data'] is List) {
      final synced = (syncRes['data'] as List)
          .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
          .toList();
      for (final row in _relatedRows) {
        if (!_isVariantRow(row)) continue;
        for (final v in synced) {
          if (_variantMatchesRow(v, row)) {
            row.variantId = v.id;
            if (row.codeCtrl.text.trim().isEmpty) {
              row.codeCtrl.text = v.skuCode;
            }
            break;
          }
        }
      }
    }

    return true;
  }

  bool _isValidGuid(String? id) {
    if (id == null || id.isEmpty) return false;
    return RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(id);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: PosTheme.primary),
    );
  }

  void _showError(String message) {
    NotificationOverlayManager().showError(title: 'Lỗi', message: message);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lỗi'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showApiError(Map<String, dynamic> res) {
    final msg = res['message']?.toString() ??
        res['error']?.toString() ??
        'Lưu thất bại (${res['statusCode'] ?? ''})';
    _showError(msg.trim().isEmpty ? 'Lưu thất bại' : msg);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final narrow = size.width < 600;
    final dialogW = narrow
        ? size.width
        : (size.width * 0.98).clamp(720.0, 1400.0);

    return Dialog(
      insetPadding: EdgeInsets.fromLTRB(
        narrow ? 6 : 16,
        pad.top + (narrow ? 4 : 16),
        narrow ? 6 : 16,
        pad.bottom + (narrow ? 4 : 16),
      ),
      child: SizedBox(
        width: dialogW,
        height: size.height - pad.top - pad.bottom - (narrow ? 16 : 48),
        child: Column(
          children: [
            _header(),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: EdgeInsets.all(narrow ? 12 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _unitsSection(),
                          const SizedBox(height: 20),
                          _attributesSection(),
                          const SizedBox(height: 20),
                          _relatedTableSection(),
                        ],
                      ),
                    ),
            ),
            const Divider(height: 1),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Thiết lập đơn vị tính và thuộc tính',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _unitsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Đơn vị tính',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        _unitHeaderRow(),
        const SizedBox(height: 4),
        _unitRow(_baseUnit, onDelete: null),
        ..._extraUnits.asMap().entries.map(
              (e) => _unitRow(_extraUnits[e.key],
                  onDelete: () => _removeUnit(e.key)),
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addUnit,
            icon: const Icon(Icons.add, size: 18, color: PosTheme.kiotBlue),
            label: const Text('Thêm đơn vị',
                style: TextStyle(color: PosTheme.kiotBlue)),
          ),
        ),
      ],
    );
  }

  Widget _unitHeaderRow() {
    if (MediaQuery.sizeOf(context).width < 520) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          const Expanded(flex: 22, child: SizedBox()),
          const SizedBox(width: 8),
          const SizedBox(
            width: 168,
            child: Text('Quy đổi',
                style: TextStyle(fontSize: 11, color: PosTheme.textSecondary)),
          ),
          const SizedBox(width: 8),
          const Expanded(
            flex: 14,
            child: Text('Giá bán',
                style: TextStyle(fontSize: 11, color: PosTheme.textSecondary)),
          ),
          const SizedBox(width: 108),
        ],
      ),
    );
  }

  Widget _unitRow(_EditableUnit u, {VoidCallback? onDelete}) {
    final baseName = _baseUnit.nameCtrl.text.trim().isEmpty
        ? 'ĐVT cơ bản'
        : _baseUnit.nameCtrl.text.trim();
    final narrow = MediaQuery.sizeOf(context).width < 520;

    final nameField = TextField(
      controller: u.nameCtrl,
      decoration: PosTheme.inputDecoration(
        label: u.isBase ? 'Tên đơn vị cơ bản' : 'Tên đơn vị',
        hint: u.isBase ? 'gói' : '1 lốc',
      ),
      onChanged: (_) =>
          setState(() => _scheduleRebuild(preserveMeta: true)),
    );

    final rateField = !u.isBase
        ? Row(
            children: [
              Text('= ',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700)),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: u.rateCtrl,
                  keyboardType: TextInputType.number,
                  decoration: PosTheme.inputDecoration(label: 'Hệ số'),
                  onChanged: (_) {
                    if (!u.isBase) _onExtraUnitRateChanged(u);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  baseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ),
            ],
          )
        : null;

    final priceField = TextField(
      controller: u.priceCtrl,
      keyboardType: TextInputType.number,
      inputFormatters: [ThousandSeparatorFormatter()],
      decoration: PosTheme.inputDecoration(label: 'Giá bán'),
      onChanged: (_) {
        if (u.isBase) {
          setState(() => _onBasePriceChanged());
        } else {
          u.priceAuto = false;
          setState(() => _syncTableFromUnits(refreshCost: false));
        }
      },
    );

    if (narrow) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        decoration: BoxDecoration(
          border: Border.all(color: PosTheme.border),
          borderRadius: BorderRadius.circular(8),
          color: u.isBase ? const Color(0xFFF8FAFC) : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                u.isBase ? 'Đơn vị cơ bản' : 'Đơn vị quy đổi',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            nameField,
            if (rateField != null) ...[
              const SizedBox(height: 8),
              rateField,
            ],
            const SizedBox(height: 8),
            priceField,
            Row(
              children: [
                Checkbox(
                  value: u.isDirectSale,
                  activeColor: PosTheme.primary,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) =>
                      setState(() => u.isDirectSale = v ?? true),
                ),
                const Text('Bán trực tiếp', style: TextStyle(fontSize: 12)),
                const Spacer(),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: Colors.red.shade400,
                    onPressed: onDelete,
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 22, child: nameField),
          const SizedBox(width: 8),
          if (!u.isBase)
            SizedBox(
              width: 168,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text('=',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700)),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: u.rateCtrl,
                      keyboardType: TextInputType.number,
                      decoration: PosTheme.inputDecoration(label: 'SL'),
                      onChanged: (_) {
                        if (!u.isBase) _onExtraUnitRateChanged(u);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        baseName,
                        maxLines: 2,
                        overflow: TextOverflow.visible,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox(width: 168),
          const SizedBox(width: 8),
          Expanded(flex: 14, child: priceField),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Row(
              children: [
                Checkbox(
                  value: u.isDirectSale,
                  activeColor: PosTheme.primary,
                  onChanged: (v) =>
                      setState(() => u.isDirectSale = v ?? true),
                ),
                const Expanded(
                  child: Text('Bán trực tiếp',
                      style: TextStyle(fontSize: 11), maxLines: 2),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _attributesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Thuộc tính',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 10),
        ..._attrs.asMap().entries.map((e) => _attrRow(e.key)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addAttr,
            icon: const Icon(Icons.add, size: 18, color: PosTheme.kiotBlue),
            label: const Text('Thêm thuộc tính',
                style: TextStyle(color: PosTheme.kiotBlue)),
          ),
        ),
      ],
    );
  }

  Widget _attrRow(int i) {
    final a = _attrs[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: a.nameCtrl,
              decoration: PosTheme.inputDecoration(
                label: 'Thuộc tính',
                hint: 'HƯƠNG VỊ, Màu sắc...',
                suffix: IconButton(
                  icon: const Icon(Icons.arrow_drop_down, size: 22),
                  tooltip: 'Chọn từ danh mục',
                  onPressed: () => _pickAttrFromCatalog(a),
                ),
              ),
              onChanged: (_) =>
                  setState(() => _scheduleRebuild(preserveMeta: true)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: a.valuesCtrl,
              decoration: PosTheme.inputDecoration(
                label: 'Giá trị thuộc tính',
                hint: 'Nhập giá trị (nhiều giá trị cách nhau dấu phẩy)',
              ),
              onChanged: (_) =>
                  setState(() => _scheduleRebuild(preserveMeta: true)),
              onEditingComplete: () =>
                  setState(() => _scheduleRebuild(preserveMeta: true)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _removeAttr(i),
          ),
        ],
      ),
    );
  }

  Widget _relatedTableSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            const Text('Hàng cùng loại',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            TextButton.icon(
              onPressed: _openPriceSetup,
              icon: const Icon(Icons.settings, size: 16, color: PosTheme.kiotBlue),
              label: const Text('Thiết lập giá',
                  style: TextStyle(color: PosTheme.kiotBlue)),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _manualCostRows.clear();
                  for (final u in _extraUnits) {
                    u.priceAuto = true;
                    u.applySuggestedPrice(_baseSellPrice);
                  }
                  _rebuildRelatedRows();
                });
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Tính lại giá'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_relatedRows.isEmpty)
          Text('Thêm đơn vị hoặc thuộc tính để sinh dòng hàng',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 720),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: PosTheme.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _relatedTableHeader(),
                    const Divider(height: 1, thickness: 1),
                    ..._relatedRows.asMap().entries.map(
                          (e) => _relatedTableDataRow(e.key, e.value),
                        ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _relatedTableHeader() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: const Row(
        children: [
          Expanded(flex: 24, child: Text('Giá trị thuộc tính', style: _th)),
          Expanded(flex: 14, child: Text('Đơn vị', style: _th)),
          Expanded(flex: 10, child: Text('Quy đổi', style: _th)),
          Expanded(flex: 16, child: Text('Mã hàng', style: _th)),
          Expanded(flex: 16, child: Text('Mã vạch', style: _th)),
          Expanded(flex: 14, child: Text('Giá vốn', style: _th)),
          Expanded(flex: 14, child: Text('Giá bán', style: _th)),
          Expanded(flex: 10, child: Text('Tồn kho', style: _th)),
          SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _relatedTableDataRow(int index, _RelatedRow r) {
    final convText = r.conversion == r.conversion.roundToDouble()
        ? r.conversion.toStringAsFixed(0)
        : r.conversion.toString();
    final focused = _isVariantRow(r) &&
        widget.input.focusVariantId != null &&
        r.variantId == widget.input.focusVariantId;
    return Container(
      key: ValueKey('${r.rowKey}_$index'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: focused ? PosTheme.kiotBlueLight.withValues(alpha: 0.45) : null,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
          left: focused
              ? const BorderSide(color: PosTheme.kiotBlue, width: 3)
              : BorderSide.none,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 24,
            child: Text(
              r.attrLabel.isEmpty ? '—' : r.attrLabel,
              style: TextStyle(
                fontSize: 12,
                color: r.attrLabel.isEmpty
                    ? Colors.grey.shade500
                    : Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(r.unitName, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            flex: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(convText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
          Expanded(
            flex: 16,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: r.codeCtrl.text.trim().isEmpty
                    ? 'Mã tự sinh khi lưu'
                    : r.codeCtrl.text.trim(),
                waitDuration: const Duration(milliseconds: 400),
                child: TextField(
                  controller: r.codeCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: r.isBaseUnit ? null : 'Tự động',
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 16,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: r.barcodeCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  suffixIcon: PosBarcodeScanIcon(
                    controller: r.barcodeCtrl,
                    iconSize: 18,
                    outlined: true,
                  ),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          Expanded(
            flex: 14,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: r.costCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandSeparatorFormatter()],
                onChanged: (v) => _onRowCostEdited(r, v),
                onEditingComplete: () {
                  if (r.isBaseUnit) {
                    setState(_applyAutoCostFromBase);
                  }
                },
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          Expanded(
            flex: 14,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: r.priceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandSeparatorFormatter()],
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          Expanded(
            flex: 10,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: r.stockCtrl,
                enabled: _isVariantRow(r) && !_usesSharedUnitStock,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandSeparatorFormatter()],
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: _isVariantRow(r)
                ? IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: Colors.red.shade700),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _removeRelatedRow(index),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  static const _th = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

  Widget _footer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Bỏ qua'),
            ),
            OutlinedButton(
              onPressed: _saving ? null : () => _save(addMore: true),
              child: const Text('Lưu & thêm cùng loại'),
            ),
            FilledButton(
              onPressed: _saving ? null : () => _save(addMore: false),
              style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}
