import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Quản lý nhóm topping dùng chung (gắn vào nhiều hàng hóa).
class PosToppingGroupsScreen extends StatefulWidget {
  const PosToppingGroupsScreen({super.key});

  @override
  State<PosToppingGroupsScreen> createState() => _PosToppingGroupsScreenState();
}

class _PosToppingGroupsScreenState extends State<PosToppingGroupsScreen> {
  final _api = ApiService();
  final _money = NumberFormat('#,###', 'vi_VN');
  bool _loading = true;
  String? _error;
  List<PosProductToppingGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getPosToppingGroups();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      setState(() {
        _groups = (res['data'] as List)
            .whereType<Map>()
            .map((e) => PosProductToppingGroup.fromJson(
                Map<String, dynamic>.from(e)))
            .toList();
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['message']?.toString() ?? 'Không tải được nhóm topping';
        _loading = false;
      });
    }
  }

  Future<void> _editGroup([PosProductToppingGroup? existing]) async {
    final nameCtrl = TextEditingController(text: tr(existing?.name ?? ''));
    var items = List<PosProductToppingOption>.from(existing?.items ?? const []);

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return AlertDialog(
              title: Text(tr(existing == null ? 'Thêm nhóm topping' : 'Sửa nhóm topping')),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: tr('Tên nhóm'),
                          hintText: tr('VD: Topping trà sữa'),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(tr('Sản phẩm trong nhóm'),
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      ...items.asMap().entries.map((e) {
                        final i = e.key;
                        final t = e.value;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(tr(t.toppingProductName)),
                          subtitle: Text(tr('+${_money.format(t.extraPrice)} đ')),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setModal(() => items.removeAt(i)),
                          ),
                        );
                      }),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await _pickProduct(ctx);
                          if (picked == null) return;
                          if (items.any((x) => x.toppingProductId == picked.id)) {
                            return;
                          }
                          setModal(() {
                            items.add(PosProductToppingOption(
                              id: '',
                              toppingProductId: picked.id,
                              toppingProductName: picked.name,
                              extraPrice: picked.basePrice,
                              sortOrder: items.length,
                            ));
                          });
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(tr('Thêm sản phẩm topping')),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr('Hủy')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr('Lưu')),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu tên',
        message: tr('Nhập tên nhóm topping'),
      );
      return;
    }
    final body = {
      'name': name,
      'sortOrder': existing?.sortOrder ?? 0,
      'items': [
        for (var i = 0; i < items.length; i++)
          {
            'toppingProductId': items[i].toppingProductId,
            'extraPrice': items[i].extraPrice,
            'sortOrder': i,
          },
      ],
    };
    final res = existing == null
        ? await _api.createPosToppingGroup(body)
        : await _api.updatePosToppingGroup(existing.id, body);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã lưu',
        message: existing == null ? 'Đã tạo nhóm topping' : 'Đã cập nhật nhóm',
      );
      await _load();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không lưu được',
      );
    }
  }

  Future<PosProduct?> _pickProduct(BuildContext ctx) async {
    final qCtrl = TextEditingController();
    List<PosProduct> results = [];
    var loading = true;

    Future<void> search(StateSetter setModal, String q) async {
      setModal(() => loading = true);
      final res = await _api.getPosProducts(
        page: 1,
        pageSize: 40,
        search: q.trim().isEmpty ? null : q.trim(),
      );
      final items = <PosProduct>[];
      if (res['isSuccess'] == true && res['data'] is Map) {
        final raw = (res['data'] as Map)['items'] ?? (res['data'] as Map)['Items'];
        if (raw is List) {
          for (final e in raw) {
            if (e is Map) {
              items.add(PosProduct.fromJson(Map<String, dynamic>.from(e)));
            }
          }
        }
      }
      setModal(() {
        results = items;
        loading = false;
      });
    }

    return showDialog<PosProduct>(
      context: ctx,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (dCtx, setModal) {
            if (loading && results.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                search(setModal, '');
              });
            }
            return AlertDialog(
              title: Text(tr('Chọn hàng topping')),
              content: SizedBox(
                width: 400,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: qCtrl,
                      decoration: InputDecoration(
                        hintText: tr('Tìm hàng…'),
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => search(setModal, v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (_, i) {
                                final p = results[i];
                                return ListTile(
                                  title: Text(tr(p.name)),
                                  subtitle: Text(
                                    tr('${p.productCode} · ${_money.format(p.basePrice)} đ'
                                    '${p.isTopping ? ' · topping' : ''}'),
                                  ),
                                  onTap: () => Navigator.pop(dCtx, p),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: Text(tr('Đóng')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _delete(PosProductToppingGroup g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa nhóm topping')),
        content: Text(tr('Xóa «${g.name}»? Các hàng hóa đang gắn nhóm sẽ mất liên kết.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.deletePosToppingGroup(g.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: g.name);
      await _load();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không xóa được',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Nhóm topping')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editGroup(),
        icon: const Icon(Icons.add),
        label: Text(tr('Thêm nhóm')),
        backgroundColor: PosTheme.kiotBlue,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr(_error!), style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: Text(tr('Thử lại'))),
                    ],
                  ),
                )
              : _groups.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(tr('Chưa có nhóm topping'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr('Tạo nhóm (vd Topping trà sữa) gồm các SP + giá,\n'
                              'rồi gắn nhóm vào từng hàng hóa.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                      itemCount: _groups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final g = _groups[i];
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          child: ListTile(
                            title: Text(
                              tr(g.name),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              tr(g.items.isEmpty
                                  ? 'Chưa có sản phẩm'
                                  : g.items
                                      .map((t) =>
                                          '${t.toppingProductName} (+${_money.format(t.extraPrice)})')
                                      .join(' · ')),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') _editGroup(g);
                                if (v == 'delete') _delete(g);
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'edit', child: Text(tr('Sửa'))),
                                PopupMenuItem(value: 'delete', child: Text(tr('Xóa'))),
                              ],
                            ),
                            onTap: () => _editGroup(g),
                          ),
                        );
                      },
                    ),
    );
  }
}
