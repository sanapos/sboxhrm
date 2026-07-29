import 'package:flutter/material.dart';

import '../../models/pos_product.dart';
import '../../utils/pos_category_tree.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class PosCategoryTreePanel extends StatelessWidget {
  const PosCategoryTreePanel({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.onAddCategory,
  });

  final List<PosCatalogItem> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final VoidCallback? onAddCategory;

  @override
  Widget build(BuildContext context) {
    final tree = buildPosCategoryTree(categories);
    final totalAll = categories.fold<int>(0, (a, c) => a + c.productCount);

    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(tr('Nhóm hàng'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                if (onAddCategory != null)
                  IconButton(
                    tooltip: tr('Thêm nhóm'),
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: onAddCategory,
                    color: PosTheme.primary,
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                _tile(
                  label: 'Tất cả nhóm',
                  count: totalAll,
                  selected: selectedId == null,
                  depth: 0,
                  onTap: () => onSelected(null),
                ),
                ...tree.expand((n) => _flatten(n)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _flatten(PosCategoryNode node) {
    final widgets = <Widget>[
      _tile(
        label: node.item.name,
        count: node.totalProducts,
        selected: selectedId == node.item.id,
        depth: node.depth,
        onTap: () => onSelected(node.item.id),
      ),
    ];
    for (final child in node.children) {
      widgets.addAll(_flatten(child));
    }
    return widgets;
  }

  Widget _tile({
    required String label,
    required int count,
    required bool selected,
    required int depth,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? PosTheme.primaryLight : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12.0 + depth * 16, 8, 12, 8),
          child: Row(
            children: [
              Icon(
                depth == 0 ? Icons.folder_outlined : Icons.subdirectory_arrow_right,
                size: 16,
                color: selected ? PosTheme.primary : PosTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(label),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? PosTheme.primaryDark : PosTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                tr('$count'),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
