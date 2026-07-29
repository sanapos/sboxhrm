import 'package:flutter/material.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../utils/pos_category_tree.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

enum PosCatalogKind { category, brand, location, supplier }

String posCatalogKindTitle(PosCatalogKind kind) => switch (kind) {
      PosCatalogKind.category => 'nhóm hàng',
      PosCatalogKind.brand => 'thương hiệu',
      PosCatalogKind.location => 'vị trí',
      PosCatalogKind.supplier => 'nhà cung cấp',
    };

String posCatalogKindTitleCap(PosCatalogKind kind) {
  final t = posCatalogKindTitle(kind);
  if (t.isEmpty) return t;
  return '${t[0].toUpperCase()}${t.substring(1)}';
}

/// Dialog quản lý danh mục POS — sửa / xóa từng mục.
Future<void> showPosCatalogManageDialog({
  required BuildContext context,
  required ApiService api,
  required PosCatalogKind kind,
  required List<PosCatalogItem> items,
  required Future<List<PosCatalogItem>> Function() onRefresh,
  required bool canEdit,
  required bool canDelete,
  List<PosCatalogItem>? categoriesForParent,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _PosCatalogManageDialog(
      api: api,
      kind: kind,
      items: List.of(items),
      onRefresh: onRefresh,
      canEdit: canEdit,
      canDelete: canDelete,
      categoriesForParent: categoriesForParent ?? items,
    ),
  );
}

class _PosCatalogManageDialog extends StatefulWidget {
  const _PosCatalogManageDialog({
    required this.api,
    required this.kind,
    required this.items,
    required this.onRefresh,
    required this.canEdit,
    required this.canDelete,
    required this.categoriesForParent,
  });

  final ApiService api;
  final PosCatalogKind kind;
  final List<PosCatalogItem> items;
  final Future<List<PosCatalogItem>> Function() onRefresh;
  final bool canEdit;
  final bool canDelete;
  final List<PosCatalogItem> categoriesForParent;

  @override
  State<_PosCatalogManageDialog> createState() =>
      _PosCatalogManageDialogState();
}

class _PosCatalogManageDialogState extends State<_PosCatalogManageDialog> {
  late List<PosCatalogItem> _items;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _items = widget.items;
  }

  List<_CatalogRow> get _rows {
    if (widget.kind != PosCatalogKind.category) {
      final sorted = List<PosCatalogItem>.from(_items)
        ..sort((a, b) => a.name.compareTo(b.name));
      return sorted
          .map((c) => _CatalogRow(item: c, depth: 0))
          .toList();
    }
    final tree = buildPosCategoryTree(_items);
    final rows = <_CatalogRow>[];
    void walk(PosCategoryNode node) {
      rows.add(_CatalogRow(item: node.item, depth: node.depth));
      for (final child in node.children) {
        walk(child);
      }
    }
    for (final n in tree) {
      walk(n);
    }
    return rows;
  }

  Future<Map<String, dynamic>> _update(
      PosCatalogItem item, String name, {String? parentId}) {
    switch (widget.kind) {
      case PosCatalogKind.category:
        return widget.api.updatePosProductCategory(
          item.id,
          name,
          parentId: parentId,
          sortOrder: item.sortOrder,
        );
      case PosCatalogKind.brand:
        return widget.api.updatePosProductBrand(item.id, name);
      case PosCatalogKind.location:
        return widget.api.updatePosStorageLocation(item.id, name);
      case PosCatalogKind.supplier:
        return widget.api.updatePosSupplier(item.id, name);
    }
  }

  Future<Map<String, dynamic>> _delete(PosCatalogItem item) {
    switch (widget.kind) {
      case PosCatalogKind.category:
        return widget.api.deletePosProductCategory(item.id);
      case PosCatalogKind.brand:
        return widget.api.deletePosProductBrand(item.id);
      case PosCatalogKind.location:
        return widget.api.deletePosStorageLocation(item.id);
      case PosCatalogKind.supplier:
        return widget.api.deletePosSupplier(item.id);
    }
  }

  Set<String> _categoryDescendantIds(String rootId) {
    final byParent = <String?, List<PosCatalogItem>>{};
    for (final c in _items) {
      byParent.putIfAbsent(c.parentId, () => []).add(c);
    }
    final result = <String>{};
    void walk(String id) {
      for (final child in byParent[id] ?? const []) {
        result.add(child.id);
        walk(child.id);
      }
    }
    walk(rootId);
    return result;
  }

  Future<void> _editItem(PosCatalogItem item) async {
    final nameCtrl = TextEditingController(text: tr(item.name));
    String? parentId = item.parentId;
    final title = posCatalogKindTitleCap(widget.kind);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlg) {
          final descendants = widget.kind == PosCatalogKind.category
              ? _categoryDescendantIds(item.id)
              : <String>{};
          final parentOptions = widget.kind == PosCatalogKind.category
              ? _items
                  .where((c) =>
                      c.id != item.id && !descendants.contains(c.id))
                  .toList()
              : const <PosCatalogItem>[];

          return AlertDialog(
            title: Text(tr('Sửa $title')),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: PosTheme.inputDecoration(label: 'Tên $title'),
                  ),
                  if (widget.kind == PosCatalogKind.category) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: parentId != null &&
                              parentOptions.any((c) => c.id == parentId)
                          ? parentId
                          : null,
                      decoration: PosTheme.inputDecoration(
                        label: 'Nhóm cha (tuỳ chọn)',
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(tr('— Không —')),
                        ),
                        ...parentOptions.map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(tr(c.name)),
                          ),
                        ),
                      ],
                      onChanged: (v) => setDlg(() => parentId = v),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, false),
                child: Text(tr('Hủy')),
              ),
              FilledButton(
                style: PosTheme.filledButtonStyle,
                onPressed: () => Navigator.pop(dlgCtx, true),
                child: Text(tr('Lưu')),
              ),
            ],
          );
        },
      ),
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true || !mounted) return;

    if (name.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: tr('Tên không được để trống'),
      );
      return;
    }

    setState(() => _busy = true);
    final res = await _update(
      item,
      name,
      parentId: widget.kind == PosCatalogKind.category ? parentId : null,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (res['isSuccess'] == true) {
      final refreshed = await widget.onRefresh();
      if (!mounted) return;
      setState(() => _items = refreshed);
      NotificationOverlayManager().showSuccess(
        title: 'Đã lưu',
        message: tr('Cập nhật $title thành công'),
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Cập nhật thất bại',
      );
    }
  }

  Future<void> _deleteItem(PosCatalogItem item) async {
    final title = posCatalogKindTitle(widget.kind);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text(tr('Xóa $title?')),
        content: Text(
          tr(item.productCount > 0
              ? '"${item.name}" đang có ${item.productCount} hàng hóa. Không thể xóa khi còn hàng đang dùng.'
              : 'Bạn có chắc muốn xóa "${item.name}"?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: Text(tr('Đóng')),
          ),
          if (item.productCount == 0 && widget.canDelete)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dlgCtx, true),
              child: Text(tr('Xóa')),
            ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    final res = await _delete(item);
    if (!mounted) return;
    setState(() => _busy = false);

    if (res['isSuccess'] == true) {
      final refreshed = await widget.onRefresh();
      if (!mounted) return;
      setState(() => _items = refreshed);
      NotificationOverlayManager().showSuccess(
        title: 'Đã xóa',
        message: tr('Xóa $title thành công'),
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Xóa thất bại',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = posCatalogKindTitleCap(widget.kind);
    final rows = _rows;

    return AlertDialog(
      title: Text(tr('Quản lý $title')),
      content: SizedBox(
        width: 420,
        height: 420,
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : rows.isEmpty
                ? Center(child: Text(tr('Chưa có dữ liệu')))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      final item = row.item;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.only(
                          left: 8.0 + row.depth * 16,
                          right: 4,
                        ),
                        title: Text(
                          tr(item.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: item.productCount > 0
                            ? Text(tr('${item.productCount} hàng hóa'),
                                style: const TextStyle(fontSize: 11),
                              )
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.canEdit)
                              IconButton(
                                tooltip: tr('Sửa'),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => _editItem(item),
                              ),
                            if (widget.canDelete)
                              IconButton(
                                tooltip: tr('Xóa'),
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                  color: item.productCount > 0
                                      ? Colors.grey
                                      : Colors.red.shade400,
                                ),
                                onPressed: item.productCount > 0
                                    ? () => _deleteItem(item)
                                    : () => _deleteItem(item),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Đóng')),
        ),
      ],
    );
  }
}

class _CatalogRow {
  final PosCatalogItem item;
  final int depth;
  const _CatalogRow({required this.item, required this.depth});
}
