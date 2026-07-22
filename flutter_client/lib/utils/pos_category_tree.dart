import '../models/pos_product.dart';

class PosCategoryNode {
  PosCategoryNode({
    required this.item,
    this.children = const [],
    this.depth = 0,
  });

  final PosCatalogItem item;
  final List<PosCategoryNode> children;
  final int depth;

  int get totalProducts =>
      item.productCount + children.fold(0, (a, c) => a + c.totalProducts);
}

List<PosCategoryNode> buildPosCategoryTree(List<PosCatalogItem> flat) {
  List<PosCategoryNode> build(String? parentId, int depth) {
    final siblings = flat
        .where((c) => (c.parentId ?? '') == (parentId ?? ''))
        .toList()
      ..sort((a, b) {
        final cs = a.sortOrder.compareTo(b.sortOrder);
        if (cs != 0) return cs;
        return a.name.compareTo(b.name);
      });
    return siblings
        .map((item) => PosCategoryNode(
              item: item,
              depth: depth,
              children: build(item.id, depth + 1),
            ))
        .toList();
  }

  return build(null, 0);
}

List<String> collectCategorySubtreeIds(
  List<PosCatalogItem> flat,
  String rootId,
) {
  final ids = <String>{rootId};
  void walk(String pid) {
    for (final c in flat.where((x) => x.parentId == pid)) {
      if (ids.add(c.id)) walk(c.id);
    }
  }

  walk(rootId);
  return ids.toList();
}
