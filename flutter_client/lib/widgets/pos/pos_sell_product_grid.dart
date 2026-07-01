import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../../utils/pos_category_tree.dart';
import '../../utils/pos_purchase_product_lookup.dart';
import '../../utils/pos_sell_unit_views.dart';
import 'pos_product_image.dart';
import 'pos_product_unit_view.dart';
import 'pos_theme.dart';

const _blue = Color(0xFF2563EB);

/// Lưới hàng hóa bán trực tiếp — chế độ Bán thường (nhóm trái + lưới phải).
class PosSellProductGrid extends StatefulWidget {
  const PosSellProductGrid({
    super.key,
    required this.api,
    required this.onPick,
    this.pageSize = 24,
  });

  final ApiService api;
  final ValueChanged<PosPurchaseLookupPick> onPick;
  final int pageSize;

  @override
  State<PosSellProductGrid> createState() => PosSellProductGridState();
}

class PosSellProductGridState extends State<PosSellProductGrid> {
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final _categoryScroll = ScrollController();
  final _gridScroll = ScrollController();
  List<PosProduct> _products = [];
  List<PosCatalogItem> _categories = [];
  String? _categoryId;
  bool _loading = true;
  bool _loadingCategories = true;
  int _page = 0;
  final Map<String, List<PosProductUnitView>> _unitViewsCache = {};
  final Map<String, Future<List<PosProductUnitView>>> _unitViewsLoading = {};

  Future<List<PosProductUnitView>> _viewsFor(PosProduct p) {
    final cached = _unitViewsCache[p.id];
    if (cached != null) return Future.value(cached);

    return _unitViewsLoading.putIfAbsent(p.id, () async {
      final views = await loadPosSellUnitViews(widget.api, p);
      _unitViewsCache[p.id] = views;
      _unitViewsLoading.remove(p.id);
      return views;
    });
  }

  void _prefetchPageUnitViews() {
    for (final p in _pageItems) {
      _viewsFor(p);
    }
  }

  @override
  void initState() {
    super.initState();
    ScreenRefreshNotifier.posSellProductGrid.addListener(_onExternalRefresh);
    _loadCategories();
    _loadProducts();
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.posSellProductGrid.removeListener(_onExternalRefresh);
    _categoryScroll.dispose();
    _gridScroll.dispose();
    super.dispose();
  }

  void _onExternalRefresh() {
    if (!mounted) return;
    _loadProducts();
  }

  void reload() => _loadProducts();

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

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    final res = await widget.api.getPosProducts(
      categoryId: _categoryId,
      isDirectSale: true,
      pageSize: 200,
    );
    if (!mounted) return;
    final products = <PosProduct>[];
    if (res['isSuccess'] == true && res['data'] is Map) {
      final raw = (res['data'] as Map)['items'] as List? ?? [];
      products.addAll(
          raw.map((e) => PosProduct.fromJson(e as Map<String, dynamic>)));
    }
    setState(() {
      _products = products;
      _page = 0;
      _loading = false;
      _unitViewsCache.clear();
      _unitViewsLoading.clear();
    });
    _prefetchPageUnitViews();
  }

  void _selectCategory(String? id) {
    if (_categoryId == id) return;
    setState(() => _categoryId = id);
    _loadProducts();
  }

  int get _pageCount =>
      _products.isEmpty ? 1 : ((_products.length - 1) ~/ widget.pageSize) + 1;

  List<PosProduct> get _pageItems {
    if (_products.isEmpty) return const [];
    final start = _page * widget.pageSize;
    final end = (start + widget.pageSize).clamp(0, _products.length);
    return _products.sublist(start, end);
  }

  int _columnsForWidth(double w) {
    if (w >= 560) return 5;
    if (w >= 420) return 4;
    if (w >= 300) return 3;
    return 2;
  }

  double _aspectRatioForWidth(double w, int cols) {
    if (cols >= 5) return 0.88;
    if (cols == 4) return 0.82;
    if (cols == 3) return 0.78;
    return 0.74;
  }

  Future<void> _pickProduct(PosProduct p, {PosProductUnitView? view}) async {
    final views = await _viewsFor(p);
    if (!mounted || views.isEmpty) return;
    final v = view ?? views.first;
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
              label,
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
            label,
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

  Widget _productCard(PosProduct p, double imgSize) {
    final outOfStock = p.onHandQty <= 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: outOfStock ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
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
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Center(
                              child: PosProductImage(
                                productId: p.id,
                                imageUrl: p.imageUrl,
                                size: imgSize,
                                borderRadius: 6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                height: 1.25,
                                color: PosTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_moneyFmt.format(p.basePrice)} đ',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: _stockBadge(p),
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

  Widget _stockBadge(PosProduct p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: p.onHandQty <= 0
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: p.onHandQty <= 0
              ? const Color(0xFFFCA5A5)
              : const Color(0xFF93C5FD),
        ),
      ),
      child: Text(
        'Tồn ${_qtyFmt.format(p.onHandQty)}',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: p.onHandQty <= 0
              ? const Color(0xFFB91C1C)
              : const Color(0xFF1D4ED8),
          height: 1,
        ),
      ),
    );
  }

  Widget _buildGrid(double gridWidth) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_products.isEmpty) {
      return Center(
        child: Text(
          'Không có hàng bán trực tiếp',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      );
    }

    final cols = _columnsForWidth(gridWidth);
    final imgSize = cols >= 5 ? 40.0 : 44.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Scrollbar(
            controller: _gridScroll,
            thumbVisibility: true,
            child: GridView.builder(
              controller: _gridScroll,
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
                return _productCard(p, imgSize);
              },
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
                      ? () => setState(() {
                            _page--;
                            _prefetchPageUnitViews();
                          })
                      : null,
                ),
                Text(
                  '${_page + 1}/$_pageCount',
                  style: const TextStyle(fontSize: 12),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 22),
                  onPressed: _page < _pageCount - 1
                      ? () => setState(() {
                            _page++;
                            _prefetchPageUnitViews();
                          })
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  : Scrollbar(
                      controller: _categoryScroll,
                      thumbVisibility: true,
                      child: ListView(
                        controller: _categoryScroll,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: _categoryButtons(),
                      ),
                    ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => _buildGrid(box.maxWidth),
            ),
          ),
        ],
      ),
    );
  }
}
