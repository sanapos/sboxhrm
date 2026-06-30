import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../../utils/pos_category_tree.dart';
import '../../utils/pos_purchase_product_lookup.dart';
import '../../utils/pos_sell_unit_views.dart';
import 'pos_product_image.dart';
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
  final _categoryScroll = ScrollController();
  final _gridScroll = ScrollController();
  List<PosProduct> _products = [];
  List<PosCatalogItem> _categories = [];
  String? _categoryId;
  bool _loading = true;
  bool _loadingCategories = true;
  int _page = 0;

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
    });
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
    if (cols >= 5) return 2.8;
    if (cols == 4) return 2.6;
    if (cols == 3) return 2.4;
    return 2.2;
  }

  Future<void> _onTapProduct(PosProduct p) async {
    final views = await loadPosSellUnitViews(widget.api, p);
    if (!mounted || views.isEmpty) return;
    final view = views.first;
    widget.onPick(PosPurchaseLookupPick(
      product: p,
      variantId: view.variantId,
      unitId: view.unitId,
      unitLabel: view.label,
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
    final imgSize = cols >= 4 ? 36.0 : 40.0;
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
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _onTapProduct(p),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: PosTheme.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        children: [
                          PosProductImage(
                            productId: p.id,
                            imageUrl: p.imageUrl,
                            size: imgSize,
                            borderRadius: 4,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  p.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, height: 1.15),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _moneyFmt.format(p.basePrice),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _blue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
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
                  onPressed: _page > 0 ? () => setState(() => _page--) : null,
                ),
                Text(
                  '${_page + 1}/$_pageCount',
                  style: const TextStyle(fontSize: 12),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 22),
                  onPressed: _page < _pageCount - 1
                      ? () => setState(() => _page++)
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
