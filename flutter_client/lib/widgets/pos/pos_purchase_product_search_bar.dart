import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../utils/pos_category_tree.dart';
import '../../utils/pos_purchase_product_lookup.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos_barcode_scanner.dart';
import 'pos_product_image.dart';
import 'pos_product_unit_view.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _blue = Color(0xFF2563EB);

/// Một dòng gợi ý tìm hàng kiểu KiotViet (có thể là SP gốc hoặc từng ĐVT/biến thể).
class PosPurchaseSearchSuggestion {
  const PosPurchaseSearchSuggestion({
    required this.product,
    this.variantId,
    this.unitId,
    required this.unitLabel,
    required this.displayCode,
    required this.costPrice,
    required this.onHandQty,
  });

  final PosProduct product;
  final String? variantId;
  final String? unitId;
  final String unitLabel;
  final String displayCode;
  final double costPrice;
  final double onHandQty;

  PosPurchaseLookupPick get pick => PosPurchaseLookupPick(
        product: product,
        variantId: variantId,
        unitId: unitId,
        unitLabel: unitLabel,
      );
}

/// Thanh tìm hàng hóa phiếu nhập — dropdown gợi ý giống KiotViet.
class PosPurchaseProductSearchBar extends StatefulWidget {
  const PosPurchaseProductSearchBar({
    super.key,
    required this.api,
    required this.onPick,
    this.onBarcodePick,
    this.onAddProduct,
    this.readOnly = false,
    this.sellMode = false,
    this.hintText = 'Tìm hàng hóa theo mã hoặc tên (F3)',
    this.focusNode,
    this.autofocusOnMount = true,
    this.restoreFocusAfterPick = true,
    this.hideSuffix = false,
    this.compactSellMobile = false,
  });

  final ApiService api;
  final ValueChanged<PosPurchaseLookupPick> onPick;
  /// Quét mã / Enter sau khi gõ mã — mặc định dùng [onPick] nếu null.
  final ValueChanged<PosPurchaseLookupPick>? onBarcodePick;
  final VoidCallback? onAddProduct;
  final bool readOnly;
  /// Bán hàng: dùng giá bán + API sell products.
  final bool sellMode;
  final String hintText;
  final FocusNode? focusNode;
  final bool autofocusOnMount;
  final bool restoreFocusAfterPick;
  /// Bán hàng mobile: nút + / quét đặt ngoài thanh tìm.
  final bool hideSuffix;
  /// Bo góc nhỏ, không icon kính lúp — giống KiotViet.
  final bool compactSellMobile;

  @override
  State<PosPurchaseProductSearchBar> createState() =>
      PosPurchaseProductSearchBarState();
}

class PosPurchaseProductSearchBarState extends State<PosPurchaseProductSearchBar> {
  final _ctrl = TextEditingController();
  late final FocusNode _focus;
  late final bool _ownsFocus;
  final _layerLink = LayerLink();
  final _barKey = GlobalKey();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');

  OverlayEntry? _overlay;
  Timer? _debounce;
  List<PosPurchaseSearchSuggestion> _suggestions = [];
  bool _loading = false;
  int _searchGen = 0;

  @override
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _focus = widget.focusNode ?? FocusNode();
    _focus.addListener(_onFocusChange);
    _ctrl.addListener(_onTextChanged);
    if (widget.autofocusOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => requestSearchFocus());
    }
  }

  void requestSearchFocus() {
    if (!mounted || widget.readOnly) return;
    _focus.requestFocus();
  }

  /// Mở camera quét mã vạch / QR rồi thêm vào giỏ.
  Future<void> scanBarcode() => _scanBarcode();

  Future<void> _restoreSearchFocus() async {
    if (!widget.restoreFocusAfterPick) return;
    await Future.delayed(const Duration(milliseconds: 40));
    if (mounted) requestSearchFocus();
  }

  void _dispatchPick(PosPurchaseLookupPick pick, {required bool fromBarcode}) {
    if (fromBarcode) {
      (widget.onBarcodePick ?? widget.onPick).call(pick);
    } else {
      widget.onPick(pick);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _focus.removeListener(_onFocusChange);
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!_focus.hasFocus) _removeOverlay();
      });
    } else if (_ctrl.text.trim().isNotEmpty) {
      _scheduleSearch(_ctrl.text);
    }
  }

  void _onTextChanged() {
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      _debounce?.cancel();
      setState(() {
        _suggestions = [];
        _loading = false;
      });
      _removeOverlay();
      return;
    }
    _scheduleSearch(q);
  }

  void _scheduleSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final gen = ++_searchGen;
    setState(() => _loading = true);
    _showOverlay();

    final exact = await _tryExactSuggestions(q);
    if (gen != _searchGen || !mounted) return;
    if (exact.isNotEmpty) {
      setState(() {
        _loading = false;
        _suggestions = exact;
      });
      _overlay?.markNeedsBuild();
      return;
    }

    final res = widget.sellMode
        ? await widget.api.getPosSellProducts(search: q)
        : await widget.api.getPosProducts(search: q, pageSize: 20);
    if (gen != _searchGen || !mounted) return;

    final items = <PosProduct>[];
    if (widget.sellMode) {
      if (res['isSuccess'] == true && res['data'] is List) {
        final raw = res['data'] as List;
        items.addAll(
            raw.map((e) => PosProduct.fromJson(e as Map<String, dynamic>)));
      }
    } else if (res['isSuccess'] == true && res['data'] is Map) {
      final raw = (res['data'] as Map)['items'] as List? ?? [];
      items.addAll(
          raw.map((e) => PosProduct.fromJson(e as Map<String, dynamic>)));
    }

    final suggestions = await _expandSuggestions(items);
    if (gen != _searchGen || !mounted) return;

    setState(() {
      _loading = false;
      _suggestions = suggestions;
    });
    _overlay?.markNeedsBuild();
  }

  Future<List<PosPurchaseSearchSuggestion>> _tryExactSuggestions(String q) async {
    final lookup = await widget.api.lookupPosSellItem(q);
    if (lookup['isSuccess'] != true || lookup['data'] is! Map) return [];

    final data = lookup['data'] as Map<String, dynamic>;
    final matchType = data['matchType']?.toString();

    if (matchType == 'variant' && data['variant'] is Map) {
      final vm = data['variant'] as Map<String, dynamic>;
      final productId = data['productId']?.toString() ?? '';
      final variant = PosProductVariant.fromJson(vm);
      final p = PosProduct(
        id: productId,
        productCode: vm['productCode']?.toString() ?? variant.skuCode,
        name: vm['productName']?.toString() ?? variant.name,
        imageUrl: vm['productImageUrl'] as String?,
        costPrice: variant.costPrice,
        basePrice: variant.basePrice,
        onHandQty: variant.onHandQty,
        variantCount: 1,
        baseUnitName: parseVariantUnitName(variant.attributeJson) ?? variant.name,
      );
      return [
        PosPurchaseSearchSuggestion(
          product: p,
          variantId: variant.id,
          unitLabel: parseVariantUnitName(variant.attributeJson) ?? variant.name,
          displayCode: variant.skuCode,
          costPrice: widget.sellMode ? variant.basePrice : variant.costPrice,
          onHandQty: variant.onHandQty,
        ),
      ];
    }

    if (matchType == 'product' && data['product'] is Map) {
      final p = PosProduct.fromJson(data['product'] as Map<String, dynamic>);
      return _expandSuggestions([p]);
    }
    return [];
  }

  Future<List<PosPurchaseSearchSuggestion>> _expandSuggestions(
      List<PosProduct> products) async {
    final out = <PosPurchaseSearchSuggestion>[];
    for (final p in products) {
      if (p.variantCount > 0) {
        final vRes = await widget.api.getPosProductVariants(p.id);
        if (vRes['isSuccess'] == true && vRes['data'] is List) {
          final variants = (vRes['data'] as List)
              .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
              .toList();
          for (final view in buildPosProductUnitViews(p, variants)) {
            out.add(PosPurchaseSearchSuggestion(
              product: p,
              variantId: view.variantId,
              unitId: view.unitId,
              unitLabel: view.label,
              displayCode: view.displayCode,
              costPrice: widget.sellMode ? view.basePrice : view.costPrice,
              onHandQty: view.onHandQty,
            ));
          }
          continue;
        }
      }
      out.add(PosPurchaseSearchSuggestion(
        product: p,
        unitLabel: p.baseUnitName,
        displayCode: p.productCode,
        costPrice: widget.sellMode ? p.basePrice : p.costPrice,
        onHandQty: p.onHandQty,
      ));
    }
    return out;
  }

  void _showOverlay() {
    if (_overlay != null) {
      _overlay!.markNeedsBuild();
      return;
    }
    _overlay = OverlayEntry(builder: (ctx) => _buildOverlay());
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  Future<void> _pick(PosPurchaseSearchSuggestion s) async {
    _removeOverlay();
    _ctrl.clear();
    _focus.unfocus();
    setState(() => _suggestions = []);

    PosProduct full = s.product;
    final res = await widget.api.getPosProduct(s.product.id);
    if (res['isSuccess'] == true && res['data'] is Map) {
      full = PosProduct.fromJson(res['data'] as Map<String, dynamic>);
    }
    _dispatchPick(
      PosPurchaseLookupPick(
        product: full,
        variantId: s.variantId,
        unitId: s.unitId,
        unitLabel: s.unitLabel,
      ),
      fromBarcode: false,
    );
    await _restoreSearchFocus();
  }

  Future<void> _submitExact() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    final pick = await lookupOrPickPosProduct(context, widget.api, q);
    if (!mounted) return;
    if (pick == null) {
      NotificationOverlayManager().showWarning(
        title: 'Không tìm thấy sản phẩm',
        message: tr('Không có hàng hóa với mã "$q"'),
      );
      return;
    }
    _ctrl.clear();
    _removeOverlay();
    _focus.unfocus();
    _dispatchPick(pick, fromBarcode: true);
    await _restoreSearchFocus();
  }

  Future<void> _scanBarcode() async {
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    _ctrl.text = code;
    await _submitExact();
  }

  Future<void> _openBrowseSheet() async {
    _focus.unfocus();
    _removeOverlay();
    final pick = await showModalBottomSheet<PosPurchaseLookupPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BrowseProductsSheet(
        api: widget.api,
        sellMode: widget.sellMode,
      ),
    );
    if (pick != null && mounted) widget.onPick(pick);
  }

  Widget _buildOverlay() {
    final box = _barKey.currentContext?.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 480;

    return Positioned(
      width: width,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 44),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : _suggestions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          tr(_ctrl.text.trim().isEmpty
                              ? 'Nhập mã hoặc tên hàng hóa'
                              : 'Không tìm thấy hàng phù hợp'),
                          style: const TextStyle(
                              fontSize: 13, color: PosTheme.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (_, i) =>
                            _SuggestionTile(
                          suggestion: _suggestions[i],
                          moneyFmt: _moneyFmt,
                          sellMode: widget.sellMode,
                          onTap: () => _pick(_suggestions[i]),
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) return const SizedBox.shrink();

    return Shortcuts(
      shortcuts: const {SingleActivator(LogicalKeyboardKey.f3): _FocusSearchIntent()},
      child: Actions(
        actions: {
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) {
              _focus.requestFocus();
              return null;
            },
          ),
        },
        child: CompositedTransformTarget(
          link: _layerLink,
          key: _barKey,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            decoration: InputDecoration(
              hintText: tr(widget.hintText),
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              prefixIcon: widget.compactSellMobile
                  ? null
                  : const Icon(Icons.search, size: 20, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                    widget.compactSellMobile ? 8 : 24),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                    widget.compactSellMobile ? 8 : 24),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                    widget.compactSellMobile ? 8 : 24),
                borderSide: const BorderSide(color: _blue, width: 1.5),
              ),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.symmetric(
                horizontal: widget.compactSellMobile ? 12 : 8,
                vertical: widget.compactSellMobile ? 10 : 12,
              ),
              suffixIcon: widget.hideSuffix
                  ? PosBarcodeScanIcon(
                      iconSize: 20,
                      onScanned: (_) {
                        // ignore: discarded_futures
                        _scanBarcode();
                      },
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PosBarcodeScanIcon(
                          iconSize: 20,
                          onScanned: (_) {
                            // ignore: discarded_futures
                            _scanBarcode();
                          },
                        ),
                        IconButton(
                          tooltip: tr('Chọn từ danh sách'),
                          icon: Icon(Icons.grid_view_rounded,
                              size: 20, color: Colors.grey.shade600),
                          onPressed: _openBrowseSheet,
                        ),
                        if (widget.onAddProduct != null)
                          IconButton(
                            tooltip: tr('Thêm hàng hóa mới'),
                            icon: const Icon(Icons.add, color: _blue, size: 22),
                            onPressed: widget.onAddProduct,
                          ),
                        const SizedBox(width: 4),
                      ],
                    ),
            ),
            onSubmitted: (_) => _submitExact(),
          ),
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.moneyFmt,
    required this.onTap,
    this.sellMode = false,
  });

  final PosPurchaseSearchSuggestion suggestion;
  final NumberFormat moneyFmt;
  final VoidCallback onTap;
  final bool sellMode;

  @override
  Widget build(BuildContext context) {
    final p = suggestion.product;
    final price = suggestion.costPrice > 0
        ? suggestion.costPrice
        : (sellMode ? p.basePrice : p.costPrice);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PosProductImage(
              productId: p.id,
              imageUrl: p.imageUrl,
              size: 44,
              borderRadius: 6,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 14,
                        color: PosTheme.textPrimary,
                        height: 1.3,
                      ),
                      children: [
                        TextSpan(
                          text: tr(p.name),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (suggestion.unitLabel.isNotEmpty)
                          TextSpan(
                            text: tr(' ${suggestion.unitLabel}'),
                            style: const TextStyle(
                              color: _blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(suggestion.displayCode),
                              style: const TextStyle(
                                fontSize: 12,
                                color: PosTheme.textSecondary,
                              ),
                            ),
                            Text(tr('Tồn: ${moneyFmt.format(suggestion.onHandQty)}'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: PosTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(tr('Giá: ${moneyFmt.format(price)}'),
                            style: TextStyle(
                              fontSize: 12,
                              color: sellMode ? _blue : PosTheme.textSecondary,
                              fontWeight:
                                  sellMode ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          Text(tr('Khách đặt: 0'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowseProductsSheet extends StatefulWidget {
  const _BrowseProductsSheet({
    required this.api,
    this.sellMode = false,
  });

  final ApiService api;
  final bool sellMode;

  @override
  State<_BrowseProductsSheet> createState() => _BrowseProductsSheetState();
}

Future<List<PosPurchaseSearchSuggestion>> _expandProductSuggestions(
  ApiService api,
  List<PosProduct> products, {
  required bool sellMode,
}) async {
  final out = <PosPurchaseSearchSuggestion>[];
  for (final p in products) {
    if (p.variantCount > 0) {
      final vRes = await api.getPosProductVariants(p.id);
      if (vRes['isSuccess'] == true && vRes['data'] is List) {
        final variants = (vRes['data'] as List)
            .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
            .toList();
        for (final view in buildPosProductUnitViews(p, variants)) {
          out.add(PosPurchaseSearchSuggestion(
            product: p,
            variantId: view.variantId,
            unitId: view.unitId,
            unitLabel: view.label,
            displayCode: view.displayCode,
            costPrice: sellMode ? view.basePrice : view.costPrice,
            onHandQty: view.onHandQty,
          ));
        }
        continue;
      }
    }
    out.add(PosPurchaseSearchSuggestion(
      product: p,
      unitLabel: p.baseUnitName,
      displayCode: p.productCode,
      costPrice: sellMode ? p.basePrice : p.costPrice,
      onHandQty: p.onHandQty,
    ));
  }
  return out;
}

class _BrowseProductsSheetState extends State<_BrowseProductsSheet> {
  final _search = TextEditingController();
  final _productScroll = ScrollController();
  final _categoryScroll = ScrollController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  List<PosPurchaseSearchSuggestion> _items = [];
  List<PosCatalogItem> _categories = [];
  String? _categoryId;
  bool _loading = true;
  bool _loadingCategories = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _load('');
    _search.addListener(() => _load(_search.text.trim()));
  }

  @override
  void dispose() {
    _search.dispose();
    _productScroll.dispose();
    _categoryScroll.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final res = await widget.api.getPosProductCategories();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      setState(() {
        _categories = (res['data'] as List)
            .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _loadingCategories = false;
      });
    } else {
      setState(() => _loadingCategories = false);
    }
  }

  void _selectCategory(String? id) {
    if (_categoryId == id) return;
    setState(() => _categoryId = id);
    _load(_search.text.trim());
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    final res = await widget.api.getPosProducts(
      search: q.isEmpty ? null : q,
      categoryId: _categoryId,
      isDirectSale: widget.sellMode ? true : null,
      pageSize: 100,
    );
    final products = <PosProduct>[];
    if (res['isSuccess'] == true && res['data'] is Map) {
      final raw = (res['data'] as Map)['items'] as List? ?? [];
      products.addAll(
          raw.map((e) => PosProduct.fromJson(e as Map<String, dynamic>)));
    }
    final items = await _expandProductSuggestions(
      widget.api,
      products,
      sellMode: widget.sellMode,
    );
    if (mounted) {
      setState(() {
        _loading = false;
        _items = items;
      });
    }
  }

  List<Widget> _categoryButtons({bool horizontal = false}) {
    final widgets = <Widget>[
      _categoryButton('Tất cả', null, depth: 0, horizontal: horizontal),
    ];
    for (final node in buildPosCategoryTree(_categories)) {
      widgets.addAll(_categoryNodeButtons(node, horizontal: horizontal));
    }
    return widgets;
  }

  List<Widget> _categoryNodeButtons(PosCategoryNode node, {bool horizontal = false}) {
    final widgets = <Widget>[
      _categoryButton(node.item.name, node.item.id, depth: node.depth, horizontal: horizontal),
    ];
    for (final child in node.children) {
      widgets.addAll(_categoryNodeButtons(child, horizontal: horizontal));
    }
    return widgets;
  }

  Widget _categoryButton(String label, String? id, {required int depth, bool horizontal = false}) {
    final selected = _categoryId == id;
    if (horizontal) {
      return Padding(
        padding: EdgeInsets.only(right: 6, left: depth > 0 ? 2 : 0),
        child: Material(
          color: selected ? _blue.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _selectCategory(id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? _blue : Colors.grey.shade300,
                ),
              ),
              child: Text(
                tr(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? _blue : PosTheme.textPrimary,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(4 + depth * 6.0, 2, 4, 2),
      child: Material(
        color: selected ? _blue.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _selectCategory(id),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? _blue : Colors.grey.shade200,
              ),
            ),
            child: Text(
              tr(label),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? _blue : PosTheme.textPrimary,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, __) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(tr('Chọn hàng hóa'),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final searchField = TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: tr('Tìm mã, tên hàng hóa…'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: PosBarcodeScanIcon(
                        controller: _search,
                        iconSize: 20,
                        onScanned: (code) {
                          // ignore: discarded_futures
                          _load(code);
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                    ),
                  );
                  final categoryStrip = SizedBox(
                    height: 44,
                    child: _loadingCategories
                        ? const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Scrollbar(
                            controller: _categoryScroll,
                            thumbVisibility: true,
                            child: ListView(
                              controller: _categoryScroll,
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              children: _categoryButtons(horizontal: true),
                            ),
                          ),
                  );
                  if (constraints.maxWidth >= 420) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 3, child: searchField),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: categoryStrip),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchField,
                      const SizedBox(height: 8),
                      categoryStrip,
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(
                          child: Text(tr('Không có hàng hóa'),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        )
                      : Scrollbar(
                          controller: _productScroll,
                          thumbVisibility: true,
                          child: ListView.separated(
                            controller: _productScroll,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: Colors.grey.shade200,
                            ),
                            itemBuilder: (_, i) => _SuggestionTile(
                              suggestion: _items[i],
                              moneyFmt: _moneyFmt,
                              sellMode: widget.sellMode,
                              onTap: () =>
                                  Navigator.pop(context, _items[i].pick),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}
