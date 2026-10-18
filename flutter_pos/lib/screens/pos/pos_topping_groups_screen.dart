import 'package:flutter/material.dart';
import '../../providers/permission_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
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
                          subtitle: Text(tr('+${_money.format(t.extraPrice)} đ · bấm để sửa giá')),
                          // Giá phụ thu riêng trong nhóm (vd trân châu 5k ở trà sữa, 7k ở sữa chua).
                          onTap: () async {
                            final price = await _editExtraPrice(ctx, t);
                            if (price == null) return;
                            setModal(() => items[i] = PosProductToppingOption(
                                  id: t.id,
                                  toppingProductId: t.toppingProductId,
                                  toppingProductName: t.toppingProductName,
                                  extraPrice: price,
                                  sortOrder: t.sortOrder,
                                ));
                          },
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

  Future<double?> _editExtraPrice(BuildContext ctx, PosProductToppingOption t) async {
    final ctrl = TextEditingController(text: t.extraPrice.toStringAsFixed(0));
    final v = await showDialog<double>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(tr('Giá thêm — ${t.toppingProductName}')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(suffixText: 'đ', border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () => Navigator.pop(
                dCtx, double.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), ''))),
            child: Text(tr('Lưu')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return v;
  }

  Future<PosProduct?> _pickProduct(BuildContext ctx) async {
    final qCtrl = TextEditingController();
    List<PosProduct> results = [];
    var loading = true;
    // Mặc định chỉ hiện hàng loại Topping; bỏ chọn để thêm hàng khác (vd «Thêm trứng» là hàng hóa).
    var onlyToppings = true;

    Future<void> search(StateSetter setModal, String q) async {
      setModal(() => loading = true);
      final res = await _api.getPosProducts(
        page: 1,
        pageSize: 40,
        search: q.trim().isEmpty ? null : q.trim(),
        productType: onlyToppings ? PosProductType.topping : null,
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
                    CheckboxListTile(
                      value: onlyToppings,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(tr('Chỉ hàng loại Topping')),
                      onChanged: (v) {
                        onlyToppings = v ?? true;
                        search(setModal, qCtrl.text);
                      },
                    ),
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

  /// Gắn nhóm vào nhiều món một lần: chọn cả nhóm hàng hoặc từng món (trước đây phải mở từng món).
  Future<void> _editLinks(PosProductToppingGroup g) async {
    final results = await Future.wait([
      _api.getPosToppingGroupLinks(g.id),
      _api.getPosProductCategories(),
    ]);
    final products = <PosProduct>[];
    for (var page = 1; page <= 5; page++) {
      final res = await _api.getPosProducts(page: page, pageSize: 200, isDirectSale: true);
      final raw = res['isSuccess'] == true && res['data'] is Map
          ? ((res['data'] as Map)['items'] ?? (res['data'] as Map)['Items'])
          : null;
      if (raw is! List) break;
      products.addAll(raw.whereType<Map>().map((e) => PosProduct.fromJson(Map<String, dynamic>.from(e))));
      if (raw.length < 200) break;
    }
    if (!mounted) return;
    // Món gắn được topping: hàng hóa / dịch vụ / combo (không phải chính topping / nguyên liệu).
    products.removeWhere((p) => p.productType == PosProductType.topping || p.productType == PosProductType.material);
    final linkRes = results[0];
    final selected = <String>{
      if (linkRes['isSuccess'] == true && linkRes['data'] is List)
        for (final e in (linkRes['data'] as List).whereType<Map>()) '${e['id'] ?? e['Id']}',
    };
    final catRaw = results[1]['data'];
    final catList = catRaw is List ? catRaw : (catRaw is Map ? (catRaw['items'] ?? const []) as List : const []);
    final categories = <(String, String)>[
      for (final c in catList.whereType<Map>())
        if (products.any((p) => p.categoryId == '${c['id'] ?? c['Id']}'))
          ('${c['id'] ?? c['Id']}', '${c['name'] ?? c['Name'] ?? ''}'),
    ];
    final qCtrl = TextEditingController();
    var query = '';
    final saved = await showDialog<Set<String>>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setD) {
          final shown = products
              .where((p) => query.isEmpty || p.name.toLowerCase().contains(query.toLowerCase()))
              .toList();
          bool catAll(String cid) {
            final inCat = products.where((p) => p.categoryId == cid);
            return inCat.isNotEmpty && inCat.every((p) => selected.contains(p.id));
          }

          return AlertDialog(
            title: Text(tr('Gắn «${g.name}» vào món')),
            content: SizedBox(
              width: 460,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr('Bấm nhóm hàng để chọn / bỏ cả nhóm, hoặc tick từng món. Món được gắn sẽ bật «cho chọn topping».'),
                    style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600),
                  ),
                  const SizedBox(height: 8),
                  if (categories.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (cid, name) in categories)
                          FilterChip(
                            label: Text(tr(name)),
                            selected: catAll(cid),
                            onSelected: (on) => setD(() {
                              for (final p in products.where((p) => p.categoryId == cid)) {
                                on ? selected.add(p.id) : selected.remove(p.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qCtrl,
                    decoration: InputDecoration(
                      hintText: tr('Tìm món…'),
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setD(() => query = v.trim()),
                  ),
                  const SizedBox(height: 4),
                  Text(tr('Đã chọn ${selected.length} món'),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  Expanded(
                    child: shown.isEmpty
                        ? Center(child: Text(tr('Không có món phù hợp')))
                        : ListView.builder(
                            itemCount: shown.length,
                            itemBuilder: (_, i) {
                              final p = shown[i];
                              return CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity: ListTileControlAffinity.leading,
                                value: selected.contains(p.id),
                                title: Text(tr(p.name)),
                                subtitle: Text(tr(p.categoryName ?? '')),
                                onChanged: (v) => setD(() => v == true ? selected.add(p.id) : selected.remove(p.id)),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(tr('Hủy'))),
              FilledButton(onPressed: () => Navigator.pop(dCtx, selected), child: Text(tr('Lưu'))),
            ],
          );
        },
      ),
    );
    qCtrl.dispose();
    if (saved == null || !mounted) return;
    final res = await _api.setPosToppingGroupLinks(g.id, productIds: saved.toList());
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final d = res['data'] as Map? ?? const {};
      NotificationOverlayManager().showSuccess(
        title: 'Đã gắn nhóm topping',
        message: tr('«${g.name}» gắn vào ${d['total'] ?? saved.length} món'
            ' (thêm ${d['added'] ?? 0}, gỡ ${d['removed'] ?? 0})'),
      );
      await _load();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không lưu được',
      );
    }
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
    final perm = context.watch<PermissionProvider>();
    final canCreate = perm.canCreate('PosProducts');
    final canEdit = perm.canEdit('PosProducts');
    final canDelete = perm.canDelete('PosProducts');
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Nhóm topping')),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        foregroundColor: SboxColors.text,
        actions: [
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _editGroup(),
              icon: const Icon(Icons.add),
              label: Text(tr('Thêm nhóm')),
              backgroundColor: PosTheme.kiotBlue,
            )
          : null,
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
                              style: TextStyle(color: SboxColors.slate600),
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
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(g.items.isEmpty
                                      ? 'Chưa có sản phẩm'
                                      : g.items
                                          .map((t) =>
                                              '${t.toppingProductName} (+${_money.format(t.extraPrice)})')
                                          .join(' · ')),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                InkWell(
                                  onTap: canEdit ? () => _editLinks(g) : null,
                                  child: Text(
                                  tr(g.linkedProductCount == 0
                                      ? 'Chưa gắn vào món nào — bấm để gắn'
                                      : 'Gắn vào ${g.linkedProductCount} món — bấm để sửa'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: g.linkedProductCount == 0
                                        ? const Color(0xFFD97706)
                                        : SboxColors.slate600,
                                    decoration: canEdit ? TextDecoration.underline : null,
                                  ),
                                ),
                                ),
                              ],
                            ),
                            trailing: canEdit || canDelete
                                ? PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'edit') _editGroup(g);
                                      if (v == 'links') _editLinks(g);
                                      if (v == 'delete') _delete(g);
                                    },
                                    itemBuilder: (_) => [
                                      if (canEdit)
                                        PopupMenuItem(value: 'links', child: Text(tr('Gắn vào món…'))),
                                      if (canEdit)
                                        PopupMenuItem(value: 'edit', child: Text(tr('Sửa'))),
                                      if (canDelete)
                                        PopupMenuItem(value: 'delete', child: Text(tr('Xóa'))),
                                    ],
                                  )
                                : null,
                            onTap: canEdit ? () => _editGroup(g) : null,
                          ),
                        );
                      },
                    ),
    );
  }
}
