import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/pos_price_list.dart';
import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../utils/pos_price_list_resolver.dart';
import '../../utils/pos_purchase_product_lookup.dart';
import '../../utils/pos_sell_unit_views.dart';
import '../../utils/vnd_thousands_input_formatter.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/pos_purchase_product_search_bar.dart';
import '../main_layout.dart';

class _PriceRow {
  _PriceRow({
    required this.productId,
    required this.productName,
    required this.productCode,
    this.variantId,
    this.unitId,
    required this.unitLabel,
    required this.basePrice,
    required this.priceCtrl,
    this.selected = true,
  });

  final String productId;
  final String productName;
  final String productCode;
  final String? variantId;
  final String? unitId;
  final String unitLabel;
  final double basePrice;
  final TextEditingController priceCtrl;
  bool selected;

  String get key => posPriceListItemKey(
        productId: productId,
        variantId: variantId,
        unitId: unitId,
      );

  double get listPrice => VndThousandsInputFormatter.parse(priceCtrl.text);

  void setPrice(double v) {
    priceCtrl.text = VndThousandsInputFormatter.format(v);
  }

  void dispose() => priceCtrl.dispose();
}

/// Thiết lập giá theo bảng giá — nhiều SP + tính giá nhanh.
class PosPriceListDetailScreen extends StatefulWidget {
  const PosPriceListDetailScreen({super.key, required this.priceList});

  final PosPriceList priceList;

  @override
  State<PosPriceListDetailScreen> createState() =>
      _PosPriceListDetailScreenState();
}

class _PosPriceListDetailScreenState extends State<PosPriceListDetailScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _searchKey = GlobalKey<PosPurchaseProductSearchBarState>();
  final _filterCtrl = TextEditingController();

  final List<_PriceRow> _rows = [];
  bool _loading = true;
  bool _saving = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  List<_PriceRow> get _visibleRows {
    final q = _filter.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows
        .where((r) =>
            r.productName.toLowerCase().contains(q) ||
            r.productCode.toLowerCase().contains(q) ||
            r.unitLabel.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final itemsRes = await _api.getPosPriceListItems(widget.priceList.id);
    if (!mounted) return;

    final items = <PosPriceListItem>[];
    if (itemsRes['isSuccess'] == true && itemsRes['data'] is List) {
      for (final e in itemsRes['data'] as List) {
        if (e is Map) {
          try {
            items.add(PosPriceListItem.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {
            // bỏ dòng lỗi parse
          }
        }
      }
    } else if (itemsRes['isSuccess'] != true) {
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: itemsRes['message']?.toString() ?? 'Không tải được dòng giá',
      );
      return;
    }

    // Tải catalog để lấy giá gốc (fallback / tính nhanh).
    final catalog = <String, PosProduct>{};
    final prodRes = await _api.getPosProducts(page: 1, pageSize: 2000);
    if (prodRes['isSuccess'] == true && prodRes['data'] is Map) {
      final raw = (prodRes['data'] as Map)['items'] ??
          (prodRes['data'] as Map)['Items'];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final p = PosProduct.fromJson(Map<String, dynamic>.from(e));
          catalog[p.id] = p;
        }
      }
    }
    if (!mounted) return;

    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();

    for (final it in items) {
      final p = catalog[it.productId];
      _rows.add(_PriceRow(
        productId: it.productId,
        productName: it.productName ?? p?.name ?? 'SP',
        productCode: p?.productCode ?? '',
        variantId: it.variantId,
        unitId: it.unitId,
        unitLabel: it.unitName ??
            it.variantName ??
            p?.baseUnitName ??
            'ĐVT cơ bản',
        basePrice: p?.basePrice ?? it.price,
        priceCtrl: TextEditingController(
          text: VndThousandsInputFormatter.format(it.price),
        ),
        selected: false,
      ));
    }

    setState(() => _loading = false);
  }

  bool _hasRow(String productId, String? variantId, String? unitId) {
    final k = posPriceListItemKey(
      productId: productId,
      variantId: variantId,
      unitId: unitId,
    );
    return _rows.any((r) => r.key == k);
  }

  /// Trả về số đơn vị vừa thêm. [silent]=true → không toast từng SP.
  Future<int> _addProduct(
    PosProduct p, {
    bool select = true,
    bool silent = false,
  }) async {
    final views = await loadPosSellUnitViews(_api, p);
    if (!mounted) return 0;
    var added = 0;
    for (final v in views) {
      if (_hasRow(p.id, v.variantId, v.unitId)) continue;
      _rows.add(_PriceRow(
        productId: p.id,
        productName: p.name,
        productCode: p.productCode,
        variantId: v.variantId,
        unitId: v.unitId,
        unitLabel: v.label,
        basePrice: v.basePrice,
        priceCtrl: TextEditingController(
          text: VndThousandsInputFormatter.format(v.basePrice),
        ),
        selected: select,
      ));
      added++;
    }
    if (added == 0) {
      if (!silent) {
        NotificationOverlayManager().showWarning(
          title: 'Đã có trong bảng',
          message: p.name,
        );
      }
      return 0;
    }
    setState(() {});
    if (!silent) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã thêm',
        message: '$added đơn vị · ${p.name}',
      );
    }
    return added;
  }

  Future<void> _onPickProduct(PosPurchaseLookupPick pick) async {
    await _addProduct(pick.product);
  }

  Future<void> _openBulkAdd() async {
    final picked = await showModalBottomSheet<List<PosProduct>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _BulkProductPickerSheet(api: _api),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    var totalUnits = 0;
    var productAdded = 0;
    for (final p in picked) {
      final n = await _addProduct(p, select: true, silent: true);
      if (n > 0) {
        productAdded++;
        totalUnits += n;
      }
    }
    if (!mounted) return;
    if (productAdded == 0) {
      NotificationOverlayManager().showWarning(
        title: 'Đã có trong bảng',
        message: '${picked.length} hàng hóa đã có sẵn',
      );
    } else {
      NotificationOverlayManager().showSuccess(
        title: 'Đã thêm',
        message: '$productAdded hàng hóa ($totalUnits mức giá)',
      );
    }
  }

  Future<void> _saveAll() async {
    if (_saving) return;
    setState(() => _saving = true);
    final items = _rows
        .map((r) => {
              'productId': r.productId,
              if (r.variantId != null && r.variantId!.isNotEmpty)
                'variantId': r.variantId,
              if (r.unitId != null && r.unitId!.isNotEmpty) 'unitId': r.unitId,
              'price': r.listPrice.clamp(0, double.infinity),
            })
        .toList();

    final res =
        await _api.upsertPosPriceListItems(widget.priceList.id, items);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      ScreenRefreshNotifier.refreshPosPriceLists();
      final data = res['data'];
      final saved = data is Map
          ? ((data['saved'] ?? data['Saved'] as num?)?.toInt() ?? items.length)
          : items.length;
      NotificationOverlayManager().showSuccess(
        title: 'Đã lưu',
        message: '$saved dòng giá · ${widget.priceList.name}',
      );
      await _loadAll();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không lưu được bảng giá',
      );
    }
  }

  void _selectAllVisible(bool v) {
    for (final r in _visibleRows) {
      r.selected = v;
    }
    setState(() {});
  }

  List<_PriceRow> get _targetRows {
    final selected = _rows.where((r) => r.selected).toList();
    if (selected.isNotEmpty) return selected;
    return _visibleRows;
  }

  void _applyPercentOff(double percent) {
    for (final r in _targetRows) {
      final next =
          (r.basePrice * (100 - percent) / 100).clamp(0, double.infinity);
      r.setPrice(next.roundToDouble());
    }
    setState(() {});
  }

  void _applyPercentUp(double percent) {
    for (final r in _targetRows) {
      final next =
          (r.basePrice * (100 + percent) / 100).clamp(0, double.infinity);
      r.setPrice(next.roundToDouble());
    }
    setState(() {});
  }

  void _applySubtract(double amount) {
    for (final r in _targetRows) {
      final next = (r.basePrice - amount).clamp(0, double.infinity);
      r.setPrice(next.roundToDouble());
    }
    setState(() {});
  }

  void _applyAdd(double amount) {
    for (final r in _targetRows) {
      final next = (r.basePrice + amount).clamp(0, double.infinity);
      r.setPrice(next.roundToDouble());
    }
    setState(() {});
  }

  void _applyBasePrice() {
    for (final r in _targetRows) {
      r.setPrice(r.basePrice);
    }
    setState(() {});
  }

  void _applyFixedPrice(double price) {
    for (final r in _targetRows) {
      r.setPrice(price.clamp(0, double.infinity));
    }
    setState(() {});
  }

  void _applyRoundThousand() {
    for (final r in _targetRows) {
      final p = r.listPrice;
      final rounded = (p / 1000).round() * 1000.0;
      r.setPrice(rounded);
    }
    setState(() {});
  }

  void _applyMultiply(double factor) {
    for (final r in _targetRows) {
      final next = (r.basePrice * factor).clamp(0, double.infinity);
      r.setPrice(next.roundToDouble());
    }
    setState(() {});
  }

  String get _targetHint => _rows.any((r) => r.selected)
      ? 'Áp dụng cho ${_rows.where((r) => r.selected).length} dòng đã chọn'
      : 'Áp dụng cho ${_visibleRows.length} dòng đang hiện';

  /// «Nhiều hơn» — chức năng khác hàng chip chính (chiết khấu nhanh).
  Future<void> _openMorePriceActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Nhiều hơn',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _targetHint,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.trending_up),
              title: const Text('Tăng giá theo %'),
              subtitle: const Text('Cộng % trên giá gốc'),
              onTap: () => Navigator.pop(ctx, 'pct_up'),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Cộng thêm số tiền'),
              subtitle: const Text('Giá gốc + số tiền'),
              onTap: () => Navigator.pop(ctx, 'add_money'),
            ),
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Đặt giá cố định'),
              subtitle: const Text('Mọi dòng cùng một mức giá'),
              onTap: () => Navigator.pop(ctx, 'fixed'),
            ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Nhân hệ số giá gốc'),
              subtitle: const Text('Ví dụ 0.9 = còn 90% giá gốc'),
              onTap: () => Navigator.pop(ctx, 'factor'),
            ),
            ListTile(
              leading: const Icon(Icons.rounded_corner),
              title: const Text('Làm tròn nghìn'),
              subtitle: const Text('Làm tròn giá đang nhập về hàng nghìn'),
              onTap: () => Navigator.pop(ctx, 'round'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    if (action == 'round') {
      _applyRoundThousand();
      return;
    }

    final ctrl = TextEditingController();
    String title;
    String label;
    String? suffix;
    switch (action) {
      case 'pct_up':
        title = 'Tăng giá theo %';
        label = 'Phần trăm tăng trên giá gốc';
        suffix = '%';
      case 'add_money':
        title = 'Cộng thêm số tiền';
        label = 'Số tiền cộng thêm';
        suffix = 'đ';
      case 'fixed':
        title = 'Đặt giá cố định';
        label = 'Giá bán mới';
        suffix = 'đ';
      case 'factor':
        title = 'Nhân hệ số';
        label = 'Hệ số (vd 0.85, 1.1)';
        suffix = null;
      default:
        ctrl.dispose();
        return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: action == 'factor' || action == 'pct_up'
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
                  : [VndThousandsInputFormatter()],
              decoration: InputDecoration(
                labelText: label,
                suffixText: suffix,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _targetHint,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
            child: const Text('Áp dụng'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) {
      ctrl.dispose();
      return;
    }

    if (action == 'pct_up') {
      final p = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
      if (p > 0) _applyPercentUp(p);
    } else if (action == 'add_money') {
      final m = VndThousandsInputFormatter.parse(ctrl.text);
      if (m > 0) _applyAdd(m);
    } else if (action == 'fixed') {
      final m = VndThousandsInputFormatter.parse(ctrl.text);
      if (m >= 0) _applyFixedPrice(m);
    } else if (action == 'factor') {
      final f = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
      if (f > 0) _applyMultiply(f);
    }
    ctrl.dispose();
  }

  void _removeSelected() {
    final toRemove = _rows.where((r) => r.selected).toList();
    if (toRemove.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa chọn',
        message: 'Chọn dòng cần xoá khỏi danh sách sửa',
      );
      return;
    }
    for (final r in toRemove) {
      r.dispose();
      _rows.remove(r);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _rows.where((r) => r.selected).length;
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(widget.priceList.name),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          if (selectedCount > 0)
            IconButton(
              tooltip: 'Xoá dòng đã chọn',
              onPressed: _removeSelected,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
            ),
          IconButton(
            tooltip: 'Tải lại',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Text(
                    'SP không có trong bảng giá vẫn bán theo giá quản lý hàng hóa.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: PosPurchaseProductSearchBar(
                    key: _searchKey,
                    api: _api,
                    onPick: _onPickProduct,
                    hintText: 'Tìm & thêm hàng hoá vào bảng giá…',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openBulkAdd,
                          icon: const Icon(Icons.playlist_add, size: 18),
                          label: const Text('Thêm nhiều SP'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _filterCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Lọc trong bảng…',
                            isDense: true,
                            prefixIcon: Icon(Icons.filter_list, size: 18),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _filter = v),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildQuickActions(selectedCount),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: Row(
                    children: [
                      Text(
                        '${_rows.length} dòng'
                        '${selectedCount > 0 ? ' · đã chọn $selectedCount' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _selectAllVisible(true),
                        child: const Text('Chọn hết'),
                      ),
                      TextButton(
                        onPressed: () => _selectAllVisible(false),
                        child: const Text('Bỏ chọn'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _visibleRows.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Chưa có hàng trong bảng giá.\n'
                              'Tìm SP hoặc «Thêm nhiều SP» để gắn giá.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: PosTheme.textSecondary),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                          itemCount: _visibleRows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) =>
                              _buildRowCard(_visibleRows[i]),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
              onPressed: _saving ? null : _saveAll,
              backgroundColor: PosTheme.kiotBlue,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Đang lưu…' : 'Lưu bảng giá'),
            ),
    );
  }

  Widget _buildQuickActions(int selectedCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Text(
            'Chiết khấu nhanh',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              _quickChip('-5%', () => _applyPercentOff(5)),
              _quickChip('-10%', () => _applyPercentOff(10)),
              _quickChip('-20%', () => _applyPercentOff(20)),
              _quickChip('-5.000đ', () => _applySubtract(5000)),
              _quickChip('-10.000đ', () => _applySubtract(10000)),
              _quickChip('= Giá gốc', _applyBasePrice),
              ActionChip(
                avatar: const Icon(Icons.more_horiz, size: 16),
                label: const Text('Nhiều hơn'),
                onPressed: _openMorePriceActions,
              ),
              if (selectedCount == 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    'Chưa chọn → áp dụng dòng đang hiện',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildRowCard(_PriceRow r) {
    return Container(
      decoration: PosTheme.mobileCardDecoration().copyWith(
        color: r.selected ? const Color(0xFFE8F0FE) : Colors.white,
      ),
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: r.selected,
            activeColor: PosTheme.kiotBlue,
            onChanged: (v) => setState(() => r.selected = v ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  [
                    if (r.productCode.isNotEmpty) r.productCode,
                    r.unitLabel,
                    'Gốc ${_moneyFmt.format(r.basePrice)}đ',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 11,
                    color: PosTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 128,
            child: TextField(
              controller: r.priceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                VndThousandsInputFormatter(),
              ],
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              decoration: const InputDecoration(
                labelText: 'Giá bán',
                suffixText: 'đ',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chọn nhiều SP từ catalog để thêm vào bảng giá.
class _BulkProductPickerSheet extends StatefulWidget {
  const _BulkProductPickerSheet({required this.api});

  final ApiService api;

  @override
  State<_BulkProductPickerSheet> createState() =>
      _BulkProductPickerSheetState();
}

class _BulkProductPickerSheetState extends State<_BulkProductPickerSheet> {
  final _searchCtrl = TextEditingController();
  final _selected = <String, PosProduct>{};
  List<PosProduct> _items = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await widget.api.getPosProducts(
      search: _query.isEmpty ? null : _query,
      page: 1,
      pageSize: 200,
      sortBy: PosProductSortBy.name,
      sortDesc: false,
    );
    if (!mounted) return;
    final list = <PosProduct>[];
    if (res['isSuccess'] == true && res['data'] is Map) {
      final raw =
          (res['data'] as Map)['items'] ?? (res['data'] as Map)['Items'];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            list.add(PosProduct.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
    }
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.85;
    return SizedBox(
      height: h,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Thêm nhiều hàng hoá',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                            context,
                            _selected.values.toList(),
                          ),
                  child: Text('Thêm (${_selected.length})'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Tìm tên / mã…',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    _query = _searchCtrl.text.trim();
                    _load();
                  },
                ),
              ),
              onSubmitted: (v) {
                _query = v.trim();
                _load();
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) {
                      final p = _items[i];
                      final on = _selected.containsKey(p.id);
                      return CheckboxListTile(
                        value: on,
                        activeColor: PosTheme.kiotBlue,
                        title: Text(p.name, maxLines: 2),
                        subtitle: Text(
                          '${p.productCode} · ${_moneyFmt(p.basePrice)}đ',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected[p.id] = p;
                            } else {
                              _selected.remove(p.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _moneyFmt(double v) =>
      NumberFormat('#,##0', 'vi_VN').format(v);
}
