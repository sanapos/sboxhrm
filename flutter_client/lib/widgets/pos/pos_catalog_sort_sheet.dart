import 'package:flutter/material.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../utils/pos_category_tree.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';

/// Sheet kéo thả thứ tự nhóm hàng + sản phẩm (giống sắp nhóm bàn).
Future<bool> showPosCatalogSortSheet({
  required BuildContext context,
  required ApiService api,
  required List<PosCatalogItem> categories,
  required List<PosProduct> products,
  String? initialCategoryId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _PosCatalogSortSheet(
      api: api,
      categories: categories,
      products: products,
      initialCategoryId: initialCategoryId,
    ),
  );
  return result == true;
}

class _PosCatalogSortSheet extends StatefulWidget {
  const _PosCatalogSortSheet({
    required this.api,
    required this.categories,
    required this.products,
    this.initialCategoryId,
  });

  final ApiService api;
  final List<PosCatalogItem> categories;
  final List<PosProduct> products;
  final String? initialCategoryId;

  @override
  State<_PosCatalogSortSheet> createState() => _PosCatalogSortSheetState();
}

class _PosCatalogSortSheetState extends State<_PosCatalogSortSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late List<_CatRow> _catRows;
  late List<PosProduct> _productRows;
  String? _productCategoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _catRows = _flattenCategories(widget.categories);
    _productCategoryId = widget.initialCategoryId;
    _productRows = _productsForCategory(_productCategoryId);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<_CatRow> _flattenCategories(List<PosCatalogItem> flat) {
    final rows = <_CatRow>[];
    void walk(PosCategoryNode node) {
      rows.add(_CatRow(item: node.item, depth: node.depth));
      for (final c in node.children) {
        walk(c);
      }
    }

    for (final root in buildPosCategoryTree(flat)) {
      walk(root);
    }
    return rows;
  }

  List<PosProduct> _productsForCategory(String? categoryId) {
    var list = List<PosProduct>.from(widget.products);
    if (categoryId != null && categoryId.isNotEmpty) {
      final ids = collectCategorySubtreeIds(widget.categories, categoryId);
      list = list
          .where((p) => p.categoryId != null && ids.contains(p.categoryId))
          .toList();
    }
    list.sort((a, b) {
      final cs = a.sortOrder.compareTo(b.sortOrder);
      if (cs != 0) return cs;
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  Future<void> _saveCategories() async {
    setState(() => _saving = true);
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < _catRows.length; i++) {
      items.add({'id': _catRows[i].item.id, 'sortOrder': i});
    }
    final res = await widget.api.sortPosProductCategories(items);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã sắp nhóm hàng',
        message: '${items.length} nhóm',
      );
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không lưu được thứ tự nhóm',
      );
    }
  }

  Future<void> _saveProducts() async {
    if (_productRows.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Trống',
        message: 'Chọn nhóm có sản phẩm để sắp xếp',
      );
      return;
    }
    setState(() => _saving = true);
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < _productRows.length; i++) {
      items.add({'id': _productRows[i].id, 'sortOrder': i});
    }
    final res = await widget.api.sortPosProducts(items);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã sắp sản phẩm',
        message: '${items.length} SP',
      );
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không lưu được thứ tự SP',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: h,
      child: Column(
        children: [
          const ListTile(
            title: Text('Sắp xếp menu bán',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Kéo để đổi vị trí · Lưu để áp dụng'),
          ),
          TabBar(
            controller: _tabs,
            labelColor: PosTheme.kiotBlue,
            unselectedLabelColor: PosTheme.textSecondary,
            indicatorColor: PosTheme.kiotBlue,
            tabs: const [
              Tab(text: 'Nhóm hàng'),
              Tab(text: 'Sản phẩm'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildCategoryTab(),
                _buildProductTab(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.pop(context, false),
                  child: const Text('Đóng'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () {
                          if (_tabs.index == 0) {
                            _saveCategories();
                          } else {
                            _saveProducts();
                          }
                        },
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_tabs.index == 0
                          ? 'Lưu thứ tự nhóm'
                          : 'Lưu thứ tự SP'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTab() {
    if (_catRows.isEmpty) {
      return const Center(child: Text('Chưa có nhóm hàng'));
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _catRows.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = _catRows.removeAt(oldIndex);
          _catRows.insert(newIndex, item);
        });
      },
      itemBuilder: (context, i) {
        final row = _catRows[i];
        return ListTile(
          key: ValueKey(row.item.id),
          leading: const Icon(Icons.drag_handle),
          title: Padding(
            padding: EdgeInsets.only(left: row.depth * 16.0),
            child: Text(row.item.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          subtitle: row.depth > 0
              ? Padding(
                  padding: EdgeInsets.only(left: row.depth * 16.0),
                  child: const Text('Nhóm con',
                      style: TextStyle(fontSize: 11)),
                )
              : null,
        );
      },
    );
  }

  Widget _buildProductTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: DropdownButtonFormField<String?>(
            value: _productCategoryId,
            decoration: const InputDecoration(
              labelText: 'Lọc theo nhóm',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Tất cả'),
              ),
              for (final c in widget.categories)
                DropdownMenuItem<String?>(
                  value: c.id,
                  child: Text(c.name),
                ),
            ],
            onChanged: (v) {
              setState(() {
                _productCategoryId = v;
                _productRows = _productsForCategory(v);
              });
            },
          ),
        ),
        Expanded(
          child: _productRows.isEmpty
              ? const Center(child: Text('Không có sản phẩm trong nhóm này'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _productRows.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _productRows.removeAt(oldIndex);
                      _productRows.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, i) {
                    final p = _productRows[i];
                    return ListTile(
                      key: ValueKey(p.id),
                      leading: const Icon(Icons.drag_handle),
                      title: Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(p.productCode,
                          style: const TextStyle(fontSize: 11)),
                      trailing: p.isFavorite
                          ? const Icon(Icons.star,
                              size: 18, color: Color(0xFFF59E0B))
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CatRow {
  _CatRow({required this.item, required this.depth});
  final PosCatalogItem item;
  final int depth;
}
