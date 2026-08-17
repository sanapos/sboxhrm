import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../utils/number_formatter.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';

class PosBarcodeHint {
  const PosBarcodeHint({
    this.barcode = '',
    this.name,
    this.unitName,
    this.brandName,
    this.categoryName,
    this.imageUrl,
    this.sampleCatalogId,
    this.defaultPrice,
    this.defaultCostPrice,
    this.description,
    this.productType,
    this.vatRate,
    this.vatExempt = false,
    this.fromCatalog = false,
  });

  final String barcode;
  final String? name;
  final String? unitName;
  final String? brandName;
  final String? categoryName;
  final String? imageUrl;
  final String? sampleCatalogId;
  final double? defaultPrice;
  final double? defaultCostPrice;
  final String? description;
  final PosProductType? productType;
  final double? vatRate;
  final bool vatExempt;
  final bool fromCatalog;

  factory PosBarcodeHint.fromLookup(Map<String, dynamic> data) {
    final catalog = data['catalog'];
    final barcode = (data['barcode'] ?? '').toString().trim();
    if (catalog is Map) {
      return PosBarcodeHint.fromSample(
        Map<String, dynamic>.from(catalog),
      )._copyWithBarcode(
        (catalog['barcode'] ?? barcode).toString().trim(),
      );
    }
    return PosBarcodeHint(barcode: barcode);
  }

  factory PosBarcodeHint.fromSample(Map<String, dynamic> sample) {
    final priceRaw = sample['defaultPrice'] ?? sample['DefaultPrice'];
    final costRaw =
        sample['defaultCostPrice'] ?? sample['DefaultCostPrice'];
    final vatRaw = sample['vatRate'] ?? sample['VatRate'];
    final exemptRaw = sample['vatExempt'] ?? sample['VatExempt'];
    final typeRaw =
        (sample['productType'] ?? sample['ProductType'])?.toString();
    return PosBarcodeHint(
      barcode: (sample['barcode'] ?? '').toString().trim(),
      name: sample['name']?.toString(),
      unitName: sample['unitName']?.toString(),
      brandName: sample['brandName']?.toString(),
      categoryName: sample['categoryName']?.toString(),
      imageUrl: sample['imageUrl']?.toString(),
      sampleCatalogId: (sample['id'] ?? sample['sampleCatalogId'])?.toString(),
      defaultPrice: priceRaw is num ? priceRaw.toDouble() : null,
      defaultCostPrice: costRaw is num ? costRaw.toDouble() : null,
      description: sample['description']?.toString(),
      productType: typeRaw == null || typeRaw.isEmpty
          ? null
          : posProductTypeFromString(typeRaw),
      vatRate: vatRaw is num ? vatRaw.toDouble() : null,
      vatExempt: exemptRaw == true,
      fromCatalog: true,
    );
  }

  PosBarcodeHint _copyWithBarcode(String barcode) => PosBarcodeHint(
        barcode: barcode,
        name: name,
        unitName: unitName,
        brandName: brandName,
        categoryName: categoryName,
        imageUrl: imageUrl,
        sampleCatalogId: sampleCatalogId,
        defaultPrice: defaultPrice,
        defaultCostPrice: defaultCostPrice,
        description: description,
        productType: productType,
        vatRate: vatRate,
        vatExempt: vatExempt,
        fromCatalog: fromCatalog,
      );
}

/// Form: loáº¡i HH/DV/CB/NVL/TP + giÃ¡ + nhÃ³m + ÄVT + TH + thuáº¿ â€” áº£nh máº«u dÃ¹ng chung.
Future<PosProduct?> showPosQuickAddByBarcode(
  BuildContext context,
  ApiService api,
  PosBarcodeHint hint, {
  List<PosCatalogItem>? categories,
}) {
  return showModalBottomSheet<PosProduct>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _QuickAddBarcodeSheet(
      api: api,
      hint: hint,
      categories: categories ?? const [],
    ),
  );
}

class _QuickAddBarcodeSheet extends StatefulWidget {
  const _QuickAddBarcodeSheet({
    required this.api,
    required this.hint,
    required this.categories,
  });
  final ApiService api;
  final PosBarcodeHint hint;
  final List<PosCatalogItem> categories;

  @override
  State<_QuickAddBarcodeSheet> createState() => _QuickAddBarcodeSheetState();
}

class _QuickAddBarcodeSheetState extends State<_QuickAddBarcodeSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _descCtrl;
  String? _categoryId;
  String? _brandId;
  List<PosCatalogItem> _categories = [];
  List<PosCatalogItem> _brands = [];
  late PosProductType _productType;
  double _vatRate = 8;
  bool _vatExempt = false;
  bool _saving = false;
  bool _loadingCats = false;

  static const _vatChoices = [0.0, 5.0, 8.0, 10.0];

  @override
  void initState() {
    super.initState();
    final h = widget.hint;
    _productType = h.productType ?? PosProductType.goods;
    _vatExempt = h.vatExempt;
    _vatRate = _vatExempt ? 0 : (h.vatRate ?? 8);
    _nameCtrl = TextEditingController(text: h.name ?? '');
    final def = h.defaultPrice;
    _priceCtrl = TextEditingController(
      text: def != null && def > 0
          ? NumberFormat('#,##0', 'vi_VN').format(def)
          : '',
    );
    final cost = h.defaultCostPrice;
    _costCtrl = TextEditingController(
      text: cost != null && cost > 0
          ? NumberFormat('#,##0', 'vi_VN').format(cost)
          : '',
    );
    _unitCtrl = TextEditingController(
      text: (h.unitName ?? '').trim().isEmpty ? 'CÃ¡i' : h.unitName!.trim(),
    );
    _categoryCtrl = TextEditingController(text: (h.categoryName ?? '').trim());
    _brandCtrl = TextEditingController(text: (h.brandName ?? '').trim());
    _descCtrl = TextEditingController(text: (h.description ?? '').trim());
    _categories = List.of(widget.categories);
    _loadCatalogs();
  }

  Future<void> _loadCatalogs() async {
    setState(() => _loadingCats = true);
    final futures = await Future.wait([
      if (_categories.isEmpty) widget.api.getPosProductCategories(),
      widget.api.getPosProductBrands(),
    ]);
    if (!mounted) return;
    var fi = 0;
    if (_categories.isEmpty) {
      final res = futures[fi++];
      if (res['isSuccess'] == true && res['data'] is List) {
        _categories = (res['data'] as List)
            .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _matchCategoryHint();
      }
    } else {
      _matchCategoryHint();
    }
    final brandRes = futures[fi];
    if (brandRes['isSuccess'] == true && brandRes['data'] is List) {
      _brands = (brandRes['data'] as List)
          .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
          .toList();
      _matchBrandHint();
    }
    setState(() => _loadingCats = false);
  }

  void _matchCategoryHint() {
    final hint = (widget.hint.categoryName ?? '').trim().toLowerCase();
    if (hint.isEmpty) return;
    for (final c in _categories) {
      if (c.name.toLowerCase() == hint) {
        _categoryId = c.id;
        _categoryCtrl.text = c.name;
        return;
      }
    }
  }

  void _matchBrandHint() {
    final hint = (widget.hint.brandName ?? '').trim().toLowerCase();
    if (hint.isEmpty) return;
    for (final b in _brands) {
      if (b.name.toLowerCase() == hint) {
        _brandId = b.id;
        _brandCtrl.text = b.name;
        return;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _unitCtrl.dispose();
    _categoryCtrl.dispose();
    _brandCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final price = parseFormattedNumber(_priceCtrl.text)?.toDouble() ?? -1;
    if (name.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Thiáº¿u tÃªn',
        message: tr('Nháº­p tÃªn hÃ ng hÃ³a'),
      );
      return;
    }
    if (price < 0) {
      NotificationOverlayManager().showError(
        title: 'Thiáº¿u giÃ¡ bÃ¡n',
        message: tr('Nháº­p giÃ¡ bÃ¡n Ä‘á»ƒ thÃªm vÃ o hÃ³a Ä‘Æ¡n'),
      );
      return;
    }
    final unit = _unitCtrl.text.trim();
    if (unit.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Thiáº¿u Ä‘Æ¡n vá»‹',
        message: tr('Chá»n hoáº·c nháº­p Ä‘Æ¡n vá»‹ tÃ­nh'),
      );
      return;
    }
    final catName = _categoryCtrl.text.trim();
    if (catName.isEmpty && _categoryId == null) {
      NotificationOverlayManager().showError(
        title: 'Thiáº¿u nhÃ³m hÃ ng',
        message: tr('Chá»n hoáº·c nháº­p nhÃ³m hÃ ng'),
      );
      return;
    }

    setState(() => _saving = true);
    final barcode = widget.hint.barcode.trim();
    final brandName = _brandCtrl.text.trim();
    final res = await widget.api.createPosProductQuick({
      if (barcode.isNotEmpty) 'barcode': barcode,
      'name': name,
      'basePrice': price,
      'costPrice': parseFormattedNumber(_costCtrl.text)?.toDouble() ?? 0,
      'baseUnitName': unit,
      'productType': _productType.apiValue,
      'vatRate': _vatExempt ? 0 : _vatRate,
      'vatExempt': _vatExempt,
      if (_categoryId != null) 'categoryId': _categoryId,
      if (catName.isNotEmpty) 'categoryName': catName,
      if (_brandId != null) 'brandId': _brandId,
      if (brandName.isNotEmpty) 'brandName': brandName,
      if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
      if ((widget.hint.imageUrl ?? '').trim().isNotEmpty)
        'imageUrl': widget.hint.imageUrl!.trim(),
      if ((widget.hint.sampleCatalogId ?? '').trim().isNotEmpty)
        'sampleCatalogId': widget.hint.sampleCatalogId!.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true && res['data'] is Map) {
      final p = PosProduct.fromJson(res['data'] as Map<String, dynamic>);
      Navigator.pop(context, p);
      return;
    }
    NotificationOverlayManager().showError(
      title: 'KhÃ´ng thÃªm Ä‘Æ°á»£c',
      message:
          tr((res['message'] ?? res['errors'] ?? 'Lá»—i lÆ°u hÃ ng hÃ³a').toString()),
    );
  }

  Widget _imagePreview() {
    final sampleId = widget.hint.sampleCatalogId?.trim();
    if (sampleId != null && sampleId.isNotEmpty) {
      return FutureBuilder<List<int>?>(
        future: widget.api.getPosSampleCatalogImageBytes(sampleId),
        builder: (ctx, snap) {
          if (snap.hasData && snap.data != null && snap.data!.isNotEmpty) {
            return Image.memory(
              Uint8List.fromList(snap.data!),
              height: 88,
              width: 88,
              fit: BoxFit.cover,
            );
          }
          final url = widget.hint.imageUrl?.trim();
          if (url != null &&
              url.isNotEmpty &&
              (url.startsWith('http://') || url.startsWith('https://'))) {
            return Image.network(
              url,
              height: 88,
              width: 88,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined),
            );
          }
          return const Icon(Icons.image_outlined, size: 40);
        },
      );
    }
    final url = widget.hint.imageUrl?.trim() ?? '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        height: 88,
        width: 88,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final hasBarcode = widget.hint.barcode.trim().isNotEmpty;
    final title = widget.hint.sampleCatalogId != null
        ? 'ThÃªm tá»« catalog máº«u'
        : (widget.hint.fromCatalog
            ? 'ThÃªm hÃ ng tá»« tá»« Ä‘iá»ƒn mÃ£ váº¡ch'
            : 'MÃ£ váº¡ch chÆ°a cÃ³ trong cá»­a hÃ ng');
    final subtitle = hasBarcode
        ? 'MÃ£ ${widget.hint.barcode} â€” chá»n loáº¡i hÃ ng, ÄVT, thuáº¿ rá»“i bÃ¡n'
        : 'Chá»n loáº¡i hÃ ng (HH/DV/CB/NVL/TP), ÄVT, thÆ°Æ¡ng hiá»‡u, thuáº¿ â€” áº£nh máº«u dÃ¹ng chung';

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: PosTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              tr(title),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              tr(subtitle),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 88,
                  width: 88,
                  child: ColoredBox(
                    color: const Color(0xFFF0F2F5),
                    child: _imagePreview(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PosProductType>(
              value: _productType,
              decoration: PosTheme.inputDecoration(label: 'Loáº¡i hÃ ng *'),
              items: [
                for (final t in PosProductType.values)
                  DropdownMenuItem(
                    value: t,
                    child: Text(tr(posProductTypeLabel(t))),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _productType = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: PosTheme.inputDecoration(label: 'TÃªn hÃ ng *'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandSeparatorFormatter()],
                    decoration: PosTheme.inputDecoration(label: 'GiÃ¡ bÃ¡n *'),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandSeparatorFormatter()],
                    decoration: PosTheme.inputDecoration(label: 'GiÃ¡ vá»‘n'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _unitCtrl,
                    decoration: PosTheme.inputDecoration(
                      label: 'ÄÆ¡n vá»‹ tÃ­nh *',
                      hint: 'CÃ¡i, Lon, Lyâ€¦',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _loadingCats
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<String?>(
                          value: _categoryId != null &&
                                  _categories.any((c) => c.id == _categoryId)
                              ? _categoryId
                              : null,
                          isExpanded: true,
                          decoration:
                              PosTheme.inputDecoration(label: 'NhÃ³m hÃ ng *'),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('â€” Nháº­p má»›i / chá»n â€”'),
                            ),
                            ..._categories.map(
                              (c) => DropdownMenuItem<String?>(
                                value: c.id,
                                child: Text(tr(c.name),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _categoryId = v;
                              if (v != null) {
                                final hit = _categories
                                    .cast<PosCatalogItem?>()
                                    .firstWhere(
                                      (c) => c?.id == v,
                                      orElse: () => null,
                                    );
                                if (hit != null) {
                                  _categoryCtrl.text = hit.name;
                                }
                              }
                            });
                          },
                        ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _categoryCtrl,
              decoration: PosTheme.inputDecoration(
                label: 'Hoáº·c gÃµ tÃªn nhÃ³m hÃ ng má»›i',
                hint: 'VD: TrÃ  sá»¯a, MÃ³n chÃ­nhâ€¦',
              ),
              onChanged: (_) {
                if (_categoryId != null) {
                  setState(() => _categoryId = null);
                }
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _loadingCats
                      ? const SizedBox.shrink()
                      : DropdownButtonFormField<String?>(
                          value: _brandId != null &&
                                  _brands.any((b) => b.id == _brandId)
                              ? _brandId
                              : null,
                          isExpanded: true,
                          decoration:
                              PosTheme.inputDecoration(label: 'ThÆ°Æ¡ng hiá»‡u'),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('â€” KhÃ´ng / nháº­p má»›i â€”'),
                            ),
                            ..._brands.map(
                              (b) => DropdownMenuItem<String?>(
                                value: b.id,
                                child: Text(tr(b.name),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _brandId = v;
                              if (v != null) {
                                final hit = _brands
                                    .cast<PosCatalogItem?>()
                                    .firstWhere(
                                      (b) => b?.id == v,
                                      orElse: () => null,
                                    );
                                if (hit != null) {
                                  _brandCtrl.text = hit.name;
                                }
                              }
                            });
                          },
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _brandCtrl,
                    decoration: PosTheme.inputDecoration(
                      label: 'Hoáº·c gÃµ TH',
                      hint: 'Coca-Colaâ€¦',
                    ),
                    onChanged: (_) {
                      if (_brandId != null) {
                        setState(() => _brandId = null);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(tr('Thuáº¿ GTGT'), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(tr('KCT')),
                  selected: _vatExempt,
                  onSelected: (_) => setState(() {
                    _vatExempt = true;
                    _vatRate = 0;
                  }),
                ),
                for (final r in _vatChoices)
                  ChoiceChip(
                    label: Text('${r.toInt()}%'),
                    selected: !_vatExempt && _vatRate == r,
                    onSelected: (_) => setState(() {
                      _vatExempt = false;
                      _vatRate = r;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: PosTheme.inputDecoration(
                label: 'MÃ´ táº£',
                hint: 'Ghi chÃº ngáº¯nâ€¦',
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: PosTheme.filledButtonStyle,
              child: Text(tr(_saving ? 'Äang lÆ°uâ€¦' : 'LÆ°u vÃ  bÃ¡n')),
            ),
          ],
        ),
      ),
    );
  }
}
