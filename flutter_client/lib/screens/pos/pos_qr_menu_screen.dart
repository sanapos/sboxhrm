import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Menu riêng QR bàn / đặt online — chọn món từ catalog, giá tuỳ chỉnh.
class PosQrMenuScreen extends StatefulWidget {
  const PosQrMenuScreen({super.key});

  @override
  State<PosQrMenuScreen> createState() => _PosQrMenuScreenState();
}

class _QrMenuItem {
  _QrMenuItem({
    required this.productId,
    required this.name,
    required this.storePrice,
    this.qrPrice,
    this.showOnTable = true,
    this.showOnOnline = true,
    this.sortOrder = 0,
    this.categoryName,
  });

  final String productId;
  final String name;
  final double storePrice;
  double? qrPrice;
  bool showOnTable;
  bool showOnOnline;
  int sortOrder;
  final String? categoryName;

  factory _QrMenuItem.fromJson(Map<String, dynamic> j) {
    final store = _num(j['storePrice'] ?? j['StorePrice']);
    final custom = j['qrPrice'] ?? j['QrPrice'];
    return _QrMenuItem(
      productId: (j['productId'] ?? j['ProductId'] ?? '').toString(),
      name: (j['productName'] ?? j['ProductName'] ?? '').toString(),
      storePrice: store,
      qrPrice: custom == null ? null : _num(custom),
      showOnTable: j['showOnTable'] != false && j['ShowOnTable'] != false,
      showOnOnline: j['showOnOnline'] != false && j['ShowOnOnline'] != false,
      sortOrder: (j['sortOrder'] ?? j['SortOrder'] ?? 0) as int? ?? 0,
      categoryName: (j['categoryName'] ?? j['CategoryName'])?.toString(),
    );
  }

  Map<String, dynamic> toSaveJson(int index) => {
        'productId': productId,
        if (qrPrice != null && qrPrice! > 0) 'qrPrice': qrPrice!.round(),
        'showOnTable': showOnTable,
        'showOnOnline': showOnOnline,
        'sortOrder': index + 1,
      };
}

class _CatalogItem {
  _CatalogItem({
    required this.productId,
    required this.name,
    required this.storePrice,
    this.categoryName,
  });

  final String productId;
  final String name;
  final double storePrice;
  final String? categoryName;

  factory _CatalogItem.fromJson(Map<String, dynamic> j) => _CatalogItem(
        productId: (j['productId'] ?? j['ProductId'] ?? '').toString(),
        name: (j['productName'] ?? j['ProductName'] ?? '').toString(),
        storePrice: _num(j['storePrice'] ?? j['StorePrice']),
        categoryName: (j['categoryName'] ?? j['CategoryName'])?.toString(),
      );
}

double _num(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

class _PosQrMenuScreenState extends State<PosQrMenuScreen> {
  final _api = ApiService();
  final _money = NumberFormat('#,###', 'vi_VN');
  bool _loading = true;
  bool _saving = false;
  bool _useCustomMenu = false;
  List<_QrMenuItem> _items = [];
  List<_CatalogItem> _catalog = [];
  String? _error;
  String? _listCategory;
  Timer? _autoSaveTimer;
  String? _saveHint;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  List<String> _categoriesOf(Iterable<String?> names) {
    final set = <String>{};
    for (final n in names) {
      final t = (n ?? '').trim();
      if (t.isNotEmpty) set.add(t);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<_QrMenuItem> get _filteredItems {
    if (_listCategory == null) return _items;
    return _items
        .where((e) => (e.categoryName ?? '').trim() == _listCategory)
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getPosQrMenuConfig();
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được menu';
      });
      return;
    }
    final data = Map<String, dynamic>.from(res['data'] as Map);
    final items = <_QrMenuItem>[];
    final rawItems = data['items'] ?? data['Items'];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          items.add(_QrMenuItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    final catalog = <_CatalogItem>[];
    final rawCat = data['catalog'] ?? data['Catalog'];
    if (rawCat is List) {
      for (final e in rawCat) {
        if (e is Map) {
          catalog.add(_CatalogItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    setState(() {
      _useCustomMenu =
          data['useCustomMenu'] == true || data['UseCustomMenu'] == true;
      _items = items;
      _catalog = catalog;
      _loading = false;
      if (_listCategory != null &&
          !_categoriesOf(items.map((e) => e.categoryName))
              .contains(_listCategory)) {
        _listCategory = null;
      }
    });
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    setState(() => _saveHint = tr('Đang chờ lưu…'));
    _autoSaveTimer = Timer(const Duration(milliseconds: 650), _autoSave);
  }

  Future<void> _autoSave() async {
    if (!mounted || _loading) return;
    if (_useCustomMenu && _items.isEmpty) {
      setState(() => _saveHint = tr('Cần ít nhất 1 món khi bật menu riêng'));
      return;
    }
    setState(() {
      _saving = true;
      _saveHint = tr('Đang lưu…');
    });
    final body = {
      'useCustomMenu': _useCustomMenu,
      'items': [
        for (var i = 0; i < _items.length; i++) _items[i].toSaveJson(i),
      ],
    };
    final res = await _api.savePosQrMenuConfig(body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      setState(() => _saveHint = tr('Đã lưu'));
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _saveHint == tr('Đã lưu')) {
          setState(() => _saveHint = null);
        }
      });
    } else {
      setState(() => _saveHint = null);
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: '${res['message'] ?? res}',
      );
    }
  }

  void _mutate(VoidCallback fn) {
    setState(fn);
    _scheduleAutoSave();
  }

  void _addFromCatalog() {
    if (_error != null) {
      _load();
      return;
    }
    final existing = _items.map((e) => e.productId).toSet();
    final available =
        _catalog.where((c) => !existing.contains(c.productId)).toList();
    if (available.isEmpty) {
      NotificationOverlayManager().showInfo(
        title: tr(_catalog.isEmpty ? 'Chưa tải được menu' : 'Đã thêm hết'),
        message: tr(_catalog.isEmpty
            ? 'Bấm thử lại hoặc tải lại trang'
            : 'Tất cả món bán trực tiếp đã có trong menu'),
      );
      return;
    }
    final cats = _categoriesOf(available.map((e) => e.categoryName));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var q = '';
        String? cat;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = available.where((c) {
              if (cat != null && (c.categoryName ?? '').trim() != cat) {
                return false;
              }
              if (q.isEmpty) return true;
              final qq = q.toLowerCase();
              return c.name.toLowerCase().contains(qq) ||
                  (c.categoryName ?? '').toLowerCase().contains(qq);
            }).toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.8,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              builder: (_, scroll) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: tr('Tìm món…'),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onChanged: (v) => setLocal(() => q = v.trim()),
                    ),
                  ),
                  if (cats.isNotEmpty)
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(tr('Tất cả'),
                                  style: const TextStyle(fontSize: 12)),
                              selected: cat == null,
                              onSelected: (_) => setLocal(() => cat = null),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          for (final c in cats)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(c,
                                    style: const TextStyle(fontSize: 12)),
                                selected: cat == c,
                                onSelected: (_) => setLocal(() => cat = c),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(c.name,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${c.categoryName ?? '—'} · ${_money.format(c.storePrice)} đ',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.add_circle_outline,
                              size: 22, color: PosTheme.kiotBlue),
                          onTap: () {
                            _mutate(() {
                              _items.add(_QrMenuItem(
                                productId: c.productId,
                                name: c.name,
                                storePrice: c.storePrice,
                                categoryName: c.categoryName,
                                sortOrder: _items.length + 1,
                              ));
                              _useCustomMenu = true;
                            });
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editPrice(_QrMenuItem item) async {
    final ctrl = TextEditingController(
      text: item.qrPrice != null ? item.qrPrice!.round().toString() : '',
    );
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            16 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Giá bán QR / online'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 6),
              Text(item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                tr('Giá cửa hàng: ${_money.format(item.storePrice)} đ'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  labelText: tr('Giá bán QR'),
                  hintText: tr('Trống = dùng giá cửa hàng'),
                  suffixText: 'đ',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                ),
                onSubmitted: (_) => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(tr('Huỷ')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                          backgroundColor: PosTheme.kiotBlue),
                      child: Text(tr('Áp dụng')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
    _mutate(() {
      final raw = ctrl.text.trim();
      item.qrPrice = raw.isEmpty ? null : double.tryParse(raw);
    });
  }

  Widget _categoryFilterBar(List<String> cats) {
    if (cats.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(tr('Tất cả'), style: const TextStyle(fontSize: 12)),
              selected: _listCategory == null,
              onSelected: (_) => setState(() => _listCategory = null),
              visualDensity: VisualDensity.compact,
            ),
          ),
          for (final c in cats)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(c, style: const TextStyle(fontSize: 12)),
                selected: _listCategory == c,
                onSelected: (_) => setState(() => _listCategory = c),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Widget _compactItemRow(_QrMenuItem item) {
    final sell = item.qrPrice ?? item.storePrice;
    final diff = sell != item.storePrice;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _editPrice(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if ((item.categoryName ?? '').trim().isNotEmpty)
                          item.categoryName!.trim(),
                        if (item.showOnTable) 'QR bàn',
                        if (item.showOnOnline) 'Online',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _editPrice(item),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    '${_money.format(sell)}đ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color:
                          diff ? Colors.orange.shade800 : PosTheme.kiotBlue,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 32,
                child: ToggleButtons(
                  isSelected: [item.showOnTable, item.showOnOnline],
                  onPressed: (i) {
                    _mutate(() {
                      if (i == 0) {
                        item.showOnTable = !item.showOnTable;
                      } else {
                        item.showOnOnline = !item.showOnOnline;
                      }
                    });
                  },
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 28),
                  borderRadius: BorderRadius.circular(6),
                  selectedColor: Colors.white,
                  fillColor: PosTheme.kiotBlue,
                  children: [
                    Tooltip(
                      message: tr('QR bàn'),
                      child: const Text('Bàn',
                          style: TextStyle(fontSize: 10)),
                    ),
                    Tooltip(
                      message: tr('Online'),
                      child: const Text('OL',
                          style: TextStyle(fontSize: 10)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr('Xoá'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _mutate(() => _items.remove(item)),
                icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cats = _categoriesOf(_items.map((e) => e.categoryName));
    final visible = _filteredItems;

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: HrmPageChrome.appBar(
        title: 'Menu QR / Online',
        actions: [
          if (_saving || (_saveHint != null && _saveHint!.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  _saveHint ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: _saving
                        ? Colors.orange.shade800
                        : Colors.green.shade700,
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _error != null ? _load : _addFromCatalog,
              icon: Icon(_error != null ? Icons.refresh : Icons.add),
              label: Text(tr(_error != null ? 'Thử lại' : 'Thêm món')),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: Text(tr('Tải lại')),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(tr('Dùng menu riêng'),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        _useCustomMenu
                            ? tr('Chỉ món trong danh sách · tự lưu')
                            : tr('Hiện tất cả hàng bán trực tiếp · tự lưu'),
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: _useCustomMenu,
                      onChanged: (v) =>
                          _mutate(() => _useCustomMenu = v),
                    ),
                    const SizedBox(height: 4),
                    _categoryFilterBar(cats),
                    const SizedBox(height: 6),
                    if (_items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            tr('Chưa có món — bấm «Thêm món»'),
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      )
                    else if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            tr('Không có món trong nhóm này'),
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE7E5E4)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < visible.length; i++) ...[
                              if (i > 0)
                                Divider(
                                    height: 1, color: Colors.grey.shade200),
                              _compactItemRow(visible[i]),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}
