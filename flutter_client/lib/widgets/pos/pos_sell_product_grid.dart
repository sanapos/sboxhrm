import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../services/pos_product_image_cache.dart';
import '../../services/pos_sell_catalog_cache.dart';
import '../../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../../utils/pos_category_tree.dart';
import '../../utils/pos_combo_stock.dart';
import '../../utils/pos_price_list_resolver.dart';
import '../../utils/pos_purchase_product_lookup.dart';
import '../../utils/pos_sell_stock_patch.dart';
import '../../utils/pos_sell_unit_views.dart';
import 'pos_catalog_sort_sheet.dart';
import 'pos_mobile_widgets.dart';
import '../pos_barcode_scanner.dart';
import 'pos_product_image.dart';
import 'pos_product_unit_view.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _blue = PosTheme.kiotBlue;

/// Lưới hàng hóa bán trực tiếp — chế độ Bán thường (nhóm trái + lưới phải).
class PosSellProductGrid extends StatefulWidget {
  const PosSellProductGrid({
    super.key,
    required this.api,
    required this.onPick,
    this.onDecrement,
    this.storeId,
    this.pageSize = 24,
    this.sellListLayout = false,
    this.cartQtyByProductId = const {},
    this.priceOverrides = const {},
    this.allowNegativeStock = false,
  });

  final ApiService api;
  final ValueChanged<PosPurchaseLookupPick> onPick;
  /// Giảm 1 SP trong giỏ (màn chọn hàng hóa — nút −).
  final ValueChanged<PosProduct>? onDecrement;
  /// Store hiện tại — dùng key cache catalog local.
  final String? storeId;
  final int pageSize;
  /// Mobile bán hàng: danh sách dọc kiểu KiotViet (không lưới).
  final bool sellListLayout;
  /// Số lượng đã chọn trong giỏ (theo productId) — dùng highlight + sắp xếp.
  final Map<String, double> cartQtyByProductId;
  /// Giá theo bảng giá đang chọn (khóa từ posPriceListItemKey).
  final Map<String, double> priceOverrides;
  /// Thiết lập ngành: cho phép bán khi hết hàng / tồn âm.
  final bool allowNegativeStock;

  @override
  State<PosSellProductGrid> createState() => PosSellProductGridState();
}

class PosSellProductGridState extends State<PosSellProductGrid> {
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final _categoryScroll = ScrollController();
  final _gridScroll = ScrollController();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<PosProduct> _allProducts = [];
  List<PosProduct> _products = [];
  List<PosCatalogItem> _categories = [];
  String? _categoryId;
  bool _loading = true;
  bool _syncing = false;
  bool _loadingCategories = true;
  String? _loadError;
  int _page = 0;
  final Map<String, List<PosProductUnitView>> _unitViewsCache = {};
  final Map<String, Future<List<PosProductUnitView>>> _unitViewsLoading = {};
  Map<String, double> _lastPriceOverrides = const {};
  Timer? _searchDebounce;

  Future<List<PosProductUnitView>> _viewsFor(PosProduct p) {
    if (!identical(_lastPriceOverrides, widget.priceOverrides)) {
      _unitViewsCache.clear();
      _lastPriceOverrides = widget.priceOverrides;
    }

    final cached = _unitViewsCache[p.id];
    if (cached != null) return Future.value(cached);

    return _unitViewsLoading.putIfAbsent(p.id, () async {
      var views = await loadPosSellUnitViews(widget.api, p);
      views = applyPosPriceListToViews(views, p, widget.priceOverrides);
      _unitViewsCache[p.id] = views;
      _unitViewsLoading.remove(p.id);
      return views;
    });
  }

  List<PosProductUnitView>? _viewsCachedSync(PosProduct p) {
    if (!identical(_lastPriceOverrides, widget.priceOverrides)) {
      _unitViewsCache.clear();
      _lastPriceOverrides = widget.priceOverrides;
    }
    return _unitViewsCache[p.id];
  }

  void _prefetchPageUnitViews() {
    for (final p in _pageItems) {
      _viewsFor(p);
    }
    _prefetchPageImages();
  }

  void _prefetchPageImages() {
    final items = _pageItems.take(24).toList();
    var i = 0;
    Future<void> pump() async {
      while (i < items.length) {
        final batch = <Future<void>>[];
        for (var n = 0; n < 4 && i < items.length; n++, i++) {
          final p = items[i];
          batch.add(PosProductImageCacheManager.instance.prefetchProduct(
            api: widget.api,
            productId: p.id,
            imageUrl: p.imageUrl,
            updatedAt: p.updatedAt,
          ));
        }
        await Future.wait(batch);
      }
    }

    // ignore: discarded_futures
    pump();
  }

  @override
  void initState() {
    super.initState();
    ScreenRefreshNotifier.posSellProductGrid.addListener(_onExternalRefresh);
    ScreenRefreshNotifier.posSellStockPatch.addListener(_onStockPatch);
    _loadCategories();
    _loadProducts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onStockPatch();
      if (ScreenRefreshNotifier.posSellProductGrid.value > 0) {
        _onExternalRefresh();
      }
    });
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.posSellProductGrid.removeListener(_onExternalRefresh);
    ScreenRefreshNotifier.posSellStockPatch.removeListener(_onStockPatch);
    _searchDebounce?.cancel();
    _categoryScroll.dispose();
    _gridScroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onExternalRefresh() {
    if (!mounted) return;
    final storeId = widget.storeId?.trim();
    if (storeId != null && storeId.isNotEmpty) {
      PosSellCatalogCache.instance.invalidate(storeId);
    }
    _loadProducts(forceNetwork: true);
  }

  void _onStockPatch() {
    final patch = ScreenRefreshNotifier.posSellStockPatch.value;
    if (patch == null || patch.isEmpty || !mounted) return;
    applyStockLinePatches(patch);
    ScreenRefreshNotifier.posSellStockPatch.value = null;
  }

  void reload({bool forceNetwork = true}) => _loadProducts(forceNetwork: forceNetwork);

  List<PosProduct> get catalogProducts => _allProducts;

  PosProduct? findCatalogProduct(String id) {
    for (final p in _allProducts) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Cập nhật tồn cục bộ theo dòng bán/trả — không reload lưới/ảnh.
  void applyStockLinePatches(List<PosSellStockLineDelta> lines) {
    if (lines.isEmpty) return;
    final merged = mergeStockLineDeltas(lines);
    setState(() {
      _allProducts = _allProducts.map((p) {
        return applyPosSellStockLines(p, merged);
      }).toList();
      _products = _filterByCategory(_allProducts);
      _unitViewsCache.clear();
      _unitViewsLoading.clear();
    });
    final storeId = widget.storeId?.trim();
    if (storeId != null && storeId.isNotEmpty) {
      PosSellCatalogCache.instance.write(storeId, items: _allProducts);
    }
  }

  /// Sau bán — trừ tồn SP đã bán, không reload lưới/ảnh.
  void applySoldQuantities(Map<String, double> soldByProductId) {
    if (soldByProductId.isEmpty) return;
    final lines = soldByProductId.entries
        .where((e) => e.value > 0)
        .map(
          (e) => PosSellStockLineDelta(
            productId: e.key,
            qty: e.value,
          ),
        )
        .toList();
    applyStockLinePatches(lines);
  }

  void applySoldLinePatches(List<PosSellStockLineDelta> lines) {
    applyStockLinePatches(lines);
  }

  List<PosProduct> _filterByCategory(List<PosProduct> source) {
    var list = source;
    if (_categoryId != null && _categoryId!.isNotEmpty) {
      final ids = collectCategorySubtreeIds(_categories, _categoryId!);
      list = list
          .where((p) => p.categoryId != null && ids.contains(p.categoryId))
          .toList();
    }
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((p) {
        final name = p.name.toLowerCase();
        final code = p.productCode.toLowerCase();
        final barcode = (p.barcode ?? '').toLowerCase();
        return name.contains(q) || code.contains(q) || barcode.contains(q);
      }).toList();
    }
    list = List<PosProduct>.from(list)
      ..sort((a, b) {
        final cs = a.sortOrder.compareTo(b.sortOrder);
        if (cs != 0) return cs;
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return list;
  }

  Future<void> _openCatalogSort() async {
    final ok = await showPosCatalogSortSheet(
      context: context,
      api: widget.api,
      categories: _categories,
      products: _allProducts,
      initialCategoryId: _categoryId,
    );
    if (!mounted || !ok) return;
    await _loadCategories();
    await _loadProducts(forceNetwork: true);
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final next = raw.trim();
      if (next == _searchQuery) return;
      setState(() {
        _searchQuery = next;
        _products = _filterByCategory(_allProducts);
        _page = 0;
      });
      _prefetchPageUnitViews();
    });
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: tr('Tìm tên, mã hàng, mã vạch…'),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          prefixIcon: const Icon(Icons.search, size: 20, color: PosTheme.textSecondary),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: PosTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: PosTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: PosTheme.kiotBlue, width: 1.4),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Future<void> _loadProducts({bool forceNetwork = false}) async {
    final storeId = widget.storeId?.trim() ?? '';

    if (!forceNetwork && storeId.isNotEmpty) {
      final cached = await PosSellCatalogCache.instance.read(storeId);
      if (cached != null && cached.items.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _allProducts = cached.items;
          _products = _filterByCategory(_allProducts);
          _page = 0;
          _loading = false;
        });
        _prefetchPageUnitViews();
        // Luôn sync nền — TTL chỉ để hiện cache tức thì, không chặn hàng mới (combo).
        _syncCatalogInBackground(storeId);
        return;
      }
    }

    if (mounted) setState(() => _loading = true);
    await _fetchCatalogFromNetwork(storeId);
  }

  Future<void> _syncCatalogInBackground(String storeId) async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _fetchCatalogFromNetwork(storeId, silent: true);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _fetchCatalogFromNetwork(String storeId, {bool silent = false}) async {
    final products = <PosProduct>[];
    DateTime? catalogVersion;
    String? error;
    const pageSize = 500;
    try {
      for (var page = 1; page <= 40; page++) {
        final res =
            await widget.api.getPosSellProducts(page: page, pageSize: pageSize);
        if (!mounted) return;
        if (res['isSuccess'] != true || res['data'] is! Map) {
          if (page == 1) {
            error = res['message']?.toString() ?? 'Không tải được danh mục hàng';
          }
          break;
        }
        final data = res['data'] as Map<String, dynamic>;
        final raw = data['items'] as List? ?? [];
        if (raw.isEmpty) break;
        for (final e in raw) {
          if (e is! Map) continue;
          try {
            products.add(
              applyComboSellableToProduct(
                PosProduct.fromJson(Map<String, dynamic>.from(e)),
              ),
            );
          } catch (_) {}
        }
        final verRaw = data['catalogVersion'];
        if (verRaw != null) {
          catalogVersion = DateTime.tryParse(verRaw.toString());
        }
        final total = (data['total'] as num?)?.toInt() ?? products.length;
        if (products.length >= total || raw.length < pageSize) break;
      }

      if (storeId.isNotEmpty && products.isNotEmpty) {
        // Cache lỗi không được chặn UI (đặc biệt web).
        try {
          await PosSellCatalogCache.instance.write(
            storeId,
            items: products,
            catalogVersion: catalogVersion,
          );
        } catch (_) {}
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (!mounted) return;
      setState(() {
        if (products.isNotEmpty || error == null) {
          _allProducts = products;
          _products = _filterByCategory(_allProducts);
          _page = 0;
          _unitViewsCache.clear();
          _unitViewsLoading.clear();
        }
        _loadError = products.isEmpty ? error : null;
        _loading = false;
      });
      if (products.isNotEmpty) _prefetchPageUnitViews();
      if (silent && error != null) {
        // Background sync — không toast.
      }
    }
  }

  Future<void> openCategoryFilter() async {
    if (_loadingCategories) return;
    String? draft = _categoryId;
    await showPosMobileFilterSheet(
      context,
      title: 'Nhóm hàng',
      onReset: () {
        draft = null;
        _selectCategory(null);
      },
      onApply: () => _selectCategory(draft),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _categoryFilterTile('Tất cả', null, draft, (id) => draft = id),
          for (final node in buildPosCategoryTree(_categories))
            ..._categoryFilterTilesForNode(node, draft, (id) => draft = id),
        ],
      ),
    );
  }

  Widget _categoryFilterTile(
    String label,
    String? id,
    String? selected,
    ValueChanged<String?> onSelect,
  ) {
    final isSelected = selected == id;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(tr(label)),
      trailing: isSelected
          ? const Icon(Icons.check, color: PosTheme.kiotBlue, size: 20)
          : null,
      onTap: () => onSelect(id),
    );
  }

  List<Widget> _categoryFilterTilesForNode(
    PosCategoryNode node,
    String? selected,
    ValueChanged<String?> onSelect,
  ) {
    final widgets = <Widget>[
      Padding(
        padding: EdgeInsets.only(left: node.depth * 12.0),
        child: _categoryFilterTile(node.item.name, node.item.id, selected, onSelect),
      ),
    ];
    for (final child in node.children) {
      widgets.addAll(_categoryFilterTilesForNode(child, selected, onSelect));
    }
    return widgets;
  }

  Future<void> _scanAndPick() async {
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    final pick = await lookupOrPickPosProduct(context, widget.api, code);
    if (pick != null && mounted) widget.onPick(pick);
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
    setState(() {
      _categoryId = id;
      _products = _filterByCategory(_allProducts);
      _page = 0;
    });
    if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
    _prefetchPageUnitViews();
  }

  int get _pageCount =>
      _products.isEmpty ? 1 : ((_products.length - 1) ~/ widget.pageSize) + 1;

  List<PosProduct> get _pageItems {
    if (_products.isEmpty) return const [];
    final start = _page * widget.pageSize;
    final end = (start + widget.pageSize).clamp(0, _products.length);
    return _products.sublist(start, end);
  }

  double _qtyInCart(String productId) =>
      widget.cartQtyByProductId[productId] ?? 0;

  List<PosProduct> get _sortedSellListProducts {
    // Giữ thứ tự menu (sortOrder); SP đã chọn trong giỏ nổi lên đầu.
    if (widget.cartQtyByProductId.isEmpty) return _products;
    final list = List<PosProduct>.from(_products);
    list.sort((a, b) {
      final qa = _qtyInCart(a.id);
      final qb = _qtyInCart(b.id);
      final aSelected = qa > 0;
      final bSelected = qb > 0;
      if (aSelected != bSelected) return aSelected ? -1 : 1;
      if (qa != qb) return qb.compareTo(qa);
      final cs = a.sortOrder.compareTo(b.sortOrder);
      if (cs != 0) return cs;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  int get _sellListPageCount => _sortedSellListProducts.isEmpty
      ? 1
      : ((_sortedSellListProducts.length - 1) ~/ widget.pageSize) + 1;

  List<PosProduct> get _sortedSellListPageItems {
    final sorted = _sortedSellListProducts;
    if (sorted.isEmpty) return const [];
    final start = _page * widget.pageSize;
    if (start >= sorted.length) return const [];
    final end = (start + widget.pageSize).clamp(0, sorted.length);
    return sorted.sublist(start, end);
  }

  int _columnsForWidth(double w) {
    if (w >= 560) return 5;
    if (w >= 420) return 4;
    if (w >= 300) return 3;
    return 2;
  }

  /// KiotViet: luôn dùng hàng pill danh mục (không rail trái).
  bool _useHorizontalCategories(double w) => true;

  double _aspectRatioForWidth(double w, int cols) {
    // KiotViet: ảnh lớn + tên ngắn — tỉ lệ rộng hơn một chút.
    if (cols >= 5) return 0.78;
    if (cols == 4) return 0.74;
    if (cols == 3) return 0.72;
    return 0.70;
  }

  Future<void> _pickProduct(PosProduct p, {PosProductUnitView? view}) async {
    final views = await _viewsFor(p);
    if (!mounted || views.isEmpty) return;
    if (!widget.allowNegativeStock && isPosSellOutOfStock(p, views)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('${p.name}: ${tr('hết hàng')}'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final v = view ?? pickDefaultSellUnitView(p, views) ?? views.first;
    widget.onPick(PosPurchaseLookupPick(
      product: p,
      variantId: v.variantId,
      unitId: v.unitId,
      unitLabel: v.label,
    ));
  }

  List<Widget> _categoryButtons() {
    final widgets = <Widget>[
      _categoryButton('Tất cả', null, depth: 0),
    ];
    for (final node in buildPosCategoryTree(_categories)) {
      widgets.addAll(_categoryNodeButtons(node));
    }
    return widgets;
  }

  List<Widget> _categoryNodeButtons(PosCategoryNode node) {
    final widgets = <Widget>[
      _categoryButton(node.item.name, node.item.id, depth: node.depth),
    ];
    for (final child in node.children) {
      widgets.addAll(_categoryNodeButtons(child));
    }
    return widgets;
  }

  Widget _categoryButton(String label, String? id, {required int depth}) {
    final selected = _categoryId == id;
    return Padding(
      padding: EdgeInsets.fromLTRB(6 + depth * 6.0, 2, 6, 2),
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

  Widget _unitBar(PosProduct p, List<PosProductUnitView> views) {
    if (views.isEmpty) {
      final fallback = p.baseUnitName.isNotEmpty ? p.baseUnitName : 'Cái';
      return _unitBarShell(
        children: [
          Expanded(
            child: _unitButton(
              label: fallback,
              isDefault: true,
              onTap: () => _pickProduct(p),
            ),
          ),
        ],
      );
    }

    return _unitBarShell(
      children: [
        for (var i = 0; i < views.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 22,
              color: const Color(0xFFE2E8F0),
            ),
          Expanded(
            child: _unitButton(
              label: views[i].label,
              isDefault: i == 0,
              onTap: () => _pickProduct(p, view: views[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _unitBarShell({required List<Widget> children}) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(children: children),
    );
  }

  Widget _unitButton({
    required String label,
    required bool isDefault,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
          child: Text(
            tr(label),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isDefault ? FontWeight.w700 : FontWeight.w600,
              color: isDefault ? _blue : const Color(0xFF475569),
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnitBar(PosProduct p) {
    final cached = _viewsCachedSync(p);
    if (cached != null) {
      return _unitBar(p, cached);
    }
    return FutureBuilder<List<PosProductUnitView>>(
      future: _viewsFor(p),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _unitBarShell(
            children: [
              Expanded(
                child: _unitButton(
                  label: p.baseUnitName.isNotEmpty ? p.baseUnitName : 'Cái',
                  isDefault: true,
                  onTap: () => _pickProduct(p),
                ),
              ),
            ],
          );
        }
        return _unitBar(p, snap.data ?? const []);
      },
    );
  }

  Widget _productCardContent(PosProduct p, List<PosProductUnitView>? views) {
        final view = views != null && views.isNotEmpty
            ? (pickDefaultSellUnitView(p, views) ?? views.first)
            : null;
        final qty = view != null
            ? resolvePosSellListStockQty(p, views!)
            : p.onHandQty;
        final unit = view?.label ?? p.baseUnitName;
        final trackStock = p.productType != PosProductType.service;
        final reserved = p.reservedQty;
        final outOfStock = trackStock &&
            isPosSellOutOfStock(p, views ?? const []);
        final price =
            applyPosPriceListToProductBase(p, widget.priceOverrides);
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: outOfStock
                  ? const Color(0xFFFECACA)
                  : const Color(0xFFE8E8E8),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _pickProduct(p),
                    hoverColor: _blue.withValues(alpha: 0.04),
                    splashColor: _blue.withValues(alpha: 0.08),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Ảnh + badge giá góc dưới trái (kiểu KiotViet).
                        Expanded(
                          flex: 5,
                          child: LayoutBuilder(
                            builder: (context, c) {
                              final side = (c.maxWidth < c.maxHeight
                                      ? c.maxWidth
                                      : c.maxHeight)
                                  .clamp(36.0, 160.0);
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  ColoredBox(
                                    color: const Color(0xFFF7F7F7),
                                    child: Center(
                                      child: PosProductImage(
                                        productId: p.id,
                                        imageUrl: p.imageUrl,
                                        updatedAt: p.updatedAt,
                                        size: side,
                                        borderRadius: 0,
                                      ),
                                    ),
                                  ),
                                  if (trackStock)
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: _stockBadge(qty: qty),
                                    ),
                                  Positioned(
                                    left: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 3),
                                      decoration: const BoxDecoration(
                                        color: PosTheme.kiotBlue,
                                        borderRadius: BorderRadius.only(
                                          topRight: Radius.circular(6),
                                        ),
                                      ),
                                      child: Text(
                                        tr(_moneyFmt.format(price)),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                          child: Text(
                            tr(p.name),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                              color: PosTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _buildUnitBar(p),
            ],
          ),
        );
  }

  Widget _productCard(PosProduct p) {
    final cached = _viewsCachedSync(p);
    if (cached != null) {
      return _productCardContent(p, cached);
    }
    return FutureBuilder<List<PosProductUnitView>>(
      future: _viewsFor(p),
      builder: (context, snap) => _productCardContent(p, snap.data),
    );
  }

  Widget _stockBadge({required double qty}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: qty <= 0
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: qty <= 0
              ? const Color(0xFFFCA5A5)
              : const Color(0xFF93C5FD),
        ),
      ),
      child: Text(
        tr('Tồn ${_qtyFmt.format(qty)}'),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: qty <= 0
              ? const Color(0xFFB91C1C)
              : const Color(0xFF1D4ED8),
          height: 1,
        ),
      ),
    );
  }

  Widget _buildSellList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_products.isEmpty) {
      return Center(
        child: Text(tr('Không có hàng bán trực tiếp'),
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      );
    }

    final pageItems = _sortedSellListPageItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RepaintBoundary(
            child: Scrollbar(
              controller: _gridScroll,
              thumbVisibility: true,
              child: ListView.separated(
                controller: _gridScroll,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: pageItems.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 70, color: PosTheme.border),
                itemBuilder: (_, i) => _sellListRow(pageItems[i]),
              ),
            ),
          ),
        ),
        if (_sellListPageCount > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left, size: 22),
                  onPressed: _page > 0
                      ? () => setState(() {
                            _page--;
                            _prefetchSellListPageUnitViews();
                          })
                      : null,
                ),
                Text(
                  tr('${_page + 1}/$_sellListPageCount · ${_sortedSellListProducts.length} SP'),
                  style: const TextStyle(fontSize: 11),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 22),
                  onPressed: _page < _sellListPageCount - 1
                      ? () => setState(() {
                            _page++;
                            _prefetchSellListPageUnitViews();
                          })
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _prefetchSellListPageUnitViews() {
    for (final p in _sortedSellListPageItems) {
      _viewsFor(p);
    }
  }

  Widget _sellListRowContent(PosProduct p, List<PosProductUnitView>? views) {
    final selectedQty = _qtyInCart(p.id);
    final isSelected = selectedQty > 0;
        final view = views != null && views.isNotEmpty
            ? (pickDefaultSellUnitView(p, views) ?? views.first)
            : null;
        final price = view != null
            ? (view.basePrice > 0
                ? view.basePrice
                : applyPosPriceListToProductBase(p, widget.priceOverrides))
            : applyPosPriceListToProductBase(p, widget.priceOverrides);
        final code = view?.displayCode ?? p.productCode;
        final unit = view?.label ?? p.baseUnitName;
        final qty = view != null
            ? resolvePosSellListStockQty(p, views!)
            : p.onHandQty;
        final lowStock = p.productType == PosProductType.goods &&
            qty > 0 &&
            p.minStockQty > 0 &&
            qty <= p.minStockQty;
        final outOfStock = p.productType != PosProductType.service &&
            isPosSellOutOfStock(p, views ?? const []);
        final name = view != null && views!.length > 1
            ? '${p.name} (${view.label})'
            : p.name;

        return PosMobileProductRow(
          kiotSellStyle: true,
          isSelected: isSelected,
          selectedQty: isSelected ? selectedQty : null,
          name: name,
          code: code,
          priceText: _moneyFmt.format(price),
          stockText: outOfStock
              ? 'Hết hàng'
              : lowStock
                  ? 'Sắp hết: ${_qtyFmt.format(qty)} $unit'
                  : '${_qtyFmt.format(qty)} $unit',
          orderReservedText: null,
          image: PosProductImage(
            productId: p.id,
            imageUrl: p.imageUrl,
            updatedAt: p.updatedAt,
            size: 48,
            borderRadius: 8,
          ),
          onTap: views == null
              ? null
              : () {
                  if (views.length == 1) {
                    _pickProduct(p, view: views.first);
                  } else {
                    _pickProduct(p);
                  }
                },
          onIncrement: !isSelected || views == null
              ? null
              : () {
                  if (views.length == 1) {
                    _pickProduct(p, view: views.first);
                  } else {
                    _pickProduct(p);
                  }
                },
          onDecrement: !isSelected || widget.onDecrement == null
              ? null
              : () => widget.onDecrement!(p),
        );
  }

  Widget _sellListRow(PosProduct p) {
    final cached = _viewsCachedSync(p);
    if (cached != null) {
      return _sellListRowContent(p, cached);
    }
    return FutureBuilder<List<PosProductUnitView>>(
      future: _viewsFor(p),
      builder: (context, snap) => _sellListRowContent(p, snap.data),
    );
  }

  Widget _buildGrid(double gridWidth) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(_loadError != null
                    ? 'Không tải được hàng hóa'
                    : 'Không có hàng bán trực tiếp'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              if (_loadError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _loadProducts(forceNetwork: true),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(tr('Thử lại')),
              ),
            ],
          ),
        ),
      );
    }

    final cols = _columnsForWidth(gridWidth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RepaintBoundary(
            child: Scrollbar(
              controller: _gridScroll,
              thumbVisibility: true,
              child: GridView.builder(
                controller: _gridScroll,
                cacheExtent: 480,
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  childAspectRatio: _aspectRatioForWidth(gridWidth, cols),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _pageItems.length,
                itemBuilder: (_, i) {
                  final p = _pageItems[i];
                  return _productCard(p);
                },
              ),
            ),
          ),
        ),
        if (_pageCount > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left, size: 22),
                  onPressed: _page > 0
                      ? () {
                          setState(() => _page--);
                          if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
                          _prefetchPageUnitViews();
                        }
                      : null,
                ),
                Text(
                  tr('${_page + 1}/$_pageCount'),
                  style: const TextStyle(fontSize: 12),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 22),
                  onPressed: _page < _pageCount - 1
                      ? () {
                          setState(() => _page++);
                          if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
                          _prefetchPageUnitViews();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _horizontalCategoryStrip() {
    return SizedBox(
      height: 46,
      child: _loadingCategories
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: false,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                      children: [
                        _horizontalCategoryChip('Tất cả', null),
                        for (final node in buildPosCategoryTree(_categories))
                          ..._horizontalCategoryChipsForNode(node),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr('Sắp xếp menu'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.swap_vert, size: 22, color: PosTheme.textSecondary),
                  onPressed: _openCatalogSort,
                ),
              ],
            ),
    );
  }

  List<Widget> _horizontalCategoryChipsForNode(PosCategoryNode node) {
    final widgets = <Widget>[
      _horizontalCategoryChip(node.item.name, node.item.id),
    ];
    for (final child in node.children) {
      widgets.addAll(_horizontalCategoryChipsForNode(child));
    }
    return widgets;
  }

  Widget _horizontalCategoryChip(String label, String? id) {
    final selected = _categoryId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? PosTheme.kiotBlue : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _selectCategory(id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? PosTheme.kiotBlue : const Color(0xFFD9D9D9),
              ),
            ),
            child: Text(
              tr(label),
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : PosTheme.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sellListLayout) {
      return Material(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchBar(),
            _horizontalCategoryStrip(),
            const Divider(height: 1, color: PosTheme.border),
            Expanded(child: _buildSellList()),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalCats = _useHorizontalCategories(constraints.maxWidth);
        if (horizontalCats) {
          return Material(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                _horizontalCategoryStrip(),
                const Divider(height: 1, color: PosTheme.border),
                Expanded(child: _buildGrid(constraints.maxWidth)),
              ],
            ),
          );
        }
        return Material(
          color: Colors.white,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 108,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border(right: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: _loadingCategories
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: Scrollbar(
                                controller: _categoryScroll,
                                thumbVisibility: true,
                                child: ListView(
                                  controller: _categoryScroll,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  children: _categoryButtons(),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: tr('Sắp xếp menu'),
                              icon: const Icon(Icons.swap_vert),
                              onPressed: _openCatalogSort,
                            ),
                          ],
                        ),
                ),
              ),
              Expanded(
                child: _buildGrid(constraints.maxWidth - 108),
              ),
            ],
          ),
        );
      },
    );
  }
}
