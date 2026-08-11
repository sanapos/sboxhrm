import 'package:flutter/material.dart';

import '../../models/pos_store_printer.dart';
import '../../services/api_service.dart';
import '../../services/pos_product_printer_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Danh sách máy in → chọn máy in → gán sản phẩm (tất cả / theo nhóm / từng SP).
class PosProductPrinterAssignmentScreen extends StatefulWidget {
  const PosProductPrinterAssignmentScreen({super.key, this.printers});

  final List<PosStorePrinter>? printers;

  @override
  State<PosProductPrinterAssignmentScreen> createState() =>
      _PosProductPrinterAssignmentScreenState();
}

class _PosProductPrinterAssignmentScreenState
    extends State<PosProductPrinterAssignmentScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<_PrinterSummary> _printers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final res = await _api.getPosPrinterProductSummary();
      if (res['isSuccess'] == true && res['data'] is List) {
        _printers = (res['data'] as List)
            .map((e) => _PrinterSummary.fromJson(e as Map<String, dynamic>))
            .where((p) => p.id.isNotEmpty)
            .toList();
      } else if (widget.printers != null && widget.printers!.isNotEmpty) {
        _printers = widget.printers!
            .where((p) => p.isActive)
            .map((p) => _PrinterSummary(
                  id: p.id,
                  name: p.isDeviceLocal ? '[Nội bộ] ${p.name}' : p.name,
                  productCount: 0,
                  isDeviceLocal: p.isDeviceLocal,
                ))
            .toList();
      } else if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Không tải được danh sách',
          message: res['message']?.toString() ??
              tr('API gán máy in lỗi — thử lại'),
        );
      }
    } catch (e) {
      debugPrint('PosProductPrinterAssignment load: $e');
      if (widget.printers != null && widget.printers!.isNotEmpty) {
        _printers = widget.printers!
            .where((p) => p.isActive)
            .map((p) => _PrinterSummary(
                  id: p.id,
                  name: p.isDeviceLocal ? '[Nội bộ] ${p.name}' : p.name,
                  productCount: 0,
                  isDeviceLocal: p.isDeviceLocal,
                ))
            .toList();
      } else if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Không tải được danh sách',
          message: tr('Lỗi mạng khi tải máy in / sản phẩm'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openPrinter(_PrinterSummary printer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PosPrinterManageProductsScreen(
          printerId: printer.id,
          printerName: printer.name,
        ),
      ),
    ).then((changed) {
      if (changed == true) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Gán sản phẩm cho máy in')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _printers.isEmpty
              ? Center(child: Text(tr('Chưa có máy in. Thêm máy in trước.')))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _printers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final p = _printers[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: PosTheme.kiotBlue.withOpacity(0.12),
                          child: Icon(
                            p.isDeviceLocal
                                ? Icons.phone_android
                                : Icons.print,
                            color: PosTheme.kiotBlue,
                            size: 22,
                          ),
                        ),
                        title: Text(tr(p.name), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          tr(p.isDeviceLocal
                              ? 'Máy nội bộ · ${p.productCount} sản phẩm'
                              : 'Agent / cloud · ${p.productCount} sản phẩm'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openPrinter(p),
                      ),
                    );
                  },
                ),
    );
  }
}

class PosPrinterManageProductsScreen extends StatefulWidget {
  const PosPrinterManageProductsScreen({
    super.key,
    required this.printerId,
    required this.printerName,
  });

  final String printerId;
  final String printerName;

  @override
  State<PosPrinterManageProductsScreen> createState() =>
      _PosPrinterManageProductsScreenState();
}

class _PosPrinterManageProductsScreenState extends State<PosPrinterManageProductsScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  List<_ProductItem> _assigned = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadAssigned();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAssigned() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getPosPrinterProducts(
        widget.printerId,
        assignedOnly: true,
        search: _searchCtrl.text,
        page: _page,
        pageSize: _pageSize,
      );
      if (res['isSuccess'] == true && res['data'] != null) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        _total = _readInt(data, 'total') ?? 0;
        final items = data['items'] ?? data['Items'];
        if (items is List) {
          _assigned = items
              .whereType<Map>()
              .map((e) => _ProductItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        } else {
          _assigned = [];
        }
      } else if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Không tải được danh sách',
          message: res['message']?.toString() ?? 'Vui lòng thử lại',
        );
      }
    } catch (e) {
      debugPrint('PosPrinterManageProducts load: $e');
      if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Không tải được danh sách',
          message: tr('Lỗi tải sản phẩm — kiểm tra mạng / thử lại'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addProducts() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _AddProductsSheet(printerId: widget.printerId),
    );
      if (changed == true) {
      _page = 1;
      _searchCtrl.clear();
      await PosProductPrinterService.instance.invalidate();
      await _loadAssigned();
    }
  }

  Future<void> _removeProduct(_ProductItem p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Bỏ khỏi máy in?')),
        content: Text(tr('${p.name}\n(${p.productCode})')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Bỏ'))),
        ],
      ),
    );
    if (yes != true) return;

    setState(() => _busy = true);
    try {
      final res = await _api.unassignProductsFromPosPrinter(
        widget.printerId,
        productIds: [p.id],
      );
      if (res['isSuccess'] == true) {
        await PosProductPrinterService.instance.invalidate();
        await _loadAssigned();
      } else {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không bỏ được',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (_total / _pageSize).ceil().clamp(1, 9999);
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr(widget.printerName), overflow: TextOverflow.ellipsis),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(onPressed: _loadAssigned, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addProducts,
        backgroundColor: PosTheme.kiotBlue,
        icon: const Icon(Icons.add),
        label: Text(tr('Thêm sản phẩm')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: tr('Tìm trong danh sách đã gán…'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onSubmitted: (_) async {
                      _page = 1;
                      await _loadAssigned();
                    },
                  ),
                ),
                IconButton(
                  onPressed: _loading
                      ? null
                      : () async {
                          _page = 1;
                          await _loadAssigned();
                        },
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('$_total sản phẩm đang in trên máy này'),
                style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _assigned.isEmpty
                    ? Center(child: Text(tr('Chưa có sản phẩm.\nBấm "Thêm sản phẩm".')))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                        itemCount: _assigned.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final p = _assigned[i];
                          return Card(
                            child: ListTile(
                              title: Text(tr(p.name), maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                tr('${p.productCode}${p.categoryName != null ? ' · ${p.categoryName}' : ''}'),
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.remove_circle_outline,
                                    color: Colors.red.shade400),
                                onPressed: _busy ? null : () => _removeProduct(p),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (_total > _pageSize)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _loading || _page <= 1
                        ? null
                        : () async {
                            _page--;
                            await _loadAssigned();
                          },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(tr('Trang $_page / $totalPages')),
                  IconButton(
                    onPressed: _loading || _page >= totalPages
                        ? null
                        : () async {
                            _page++;
                            await _loadAssigned();
                          },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AddProductsSheet extends StatefulWidget {
  const _AddProductsSheet({required this.printerId});

  final String printerId;

  @override
  State<_AddProductsSheet> createState() => _AddProductsSheetState();
}

class _AddProductsSheetState extends State<_AddProductsSheet> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  List<_CategoryItem> _categories = [];
  List<_ProductItem> _products = [];
  final _selectedProductIds = <String>{};
  final _selectedCategoryIds = <String>{};
  bool _selectAll = false;
  int _page = 1;
  int _productTotal = 0;
  static const _pageSize = 40;

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
    try {
      final catRes = await _api.getPosProductPrinterCategories();
      if (catRes['isSuccess'] == true && catRes['data'] is List) {
        _categories = (catRes['data'] as List)
            .map((e) => _CategoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      await _loadProducts();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProducts() async {
    final res = await _api.getPosPrinterProducts(
      widget.printerId,
      assignedOnly: false,
      search: _searchCtrl.text,
      page: _page,
      pageSize: _pageSize,
    );
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map<String, dynamic>;
      _productTotal = _readInt(data, 'total') ?? 0;
      final items = data['items'] ?? data['Items'];
      if (items is List) {
        _products = items
            .map((e) => _ProductItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
  }

  int get _selectionEstimate {
    if (_selectAll) return _productTotal;
    var n = _selectedProductIds.length;
    for (final c in _categories.where((x) => _selectedCategoryIds.contains(x.id))) {
      n += c.productCount;
    }
    return n;
  }

  Future<void> _save({bool forceReassign = false}) async {
    if (!_selectAll &&
        _selectedProductIds.isEmpty &&
        _selectedCategoryIds.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Chưa chọn',
        message: tr('Chọn sản phẩm, nhóm hàng hoặc "Tất cả"'),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await _api.assignProductsToPosPrinter(
        widget.printerId,
        allProducts: _selectAll,
        categoryIds: _selectedCategoryIds.toList(),
        productIds: _selectedProductIds.toList(),
        forceReassign: forceReassign,
      );
      if (res['isSuccess'] == true) {
        final raw = res['data'];
        final data = raw is Map ? Map<String, dynamic>.from(raw) : null;
        final needsConfirm = data?['needsConfirm'] == true ||
            data?['NeedsConfirm'] == true;
        if (needsConfirm && !forceReassign) {
          final conflicts = data?['conflicts'] ?? data?['Conflicts'];
          final n = _readInt(data!, 'conflictCount') ??
              (conflicts is List ? conflicts.length : 0);
          final names = <String>[];
          if (conflicts is List) {
            for (final e in conflicts.take(5)) {
              if (e is! Map) continue;
              final m = Map<String, dynamic>.from(e);
              final pn = (m['productName'] ?? m['ProductName'] ?? '').toString();
              final pr = (m['currentPrinterName'] ??
                      m['CurrentPrinterName'] ??
                      '')
                  .toString();
              if (pn.isEmpty) continue;
              names.add(pr.isEmpty ? pn : '$pn → đang ở «$pr»');
            }
          }
          if (!mounted) return;
          final choice = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr('Món đã gán máy khác')),
              content: SingleChildScrollView(
                child: Text(
                  tr(
                    'Mỗi món chỉ in 1 máy.\n'
                    '$n sản phẩm đã gán máy khác'
                    '${names.isEmpty ? '' : ':\n• ${names.join('\n• ')}'}'
                    '${n > 5 ? '\n…' : ''}\n\n'
                    'Chọn cách xử lý:',
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: Text(tr('Hủy')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'skip'),
                  child: Text(tr('Chỉ gán món chưa gán')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'move'),
                  child: Text(tr('Chuyển sang máy này')),
                ),
              ],
            ),
          );
          if (choice == 'move') {
            await _save(forceReassign: true);
            return;
          }
          if (choice == 'skip') {
            // Gán lại chỉ các SP đang chọn mà chưa thuộc máy khác.
            final freeIds = _selectedProductIds.where((id) {
              final p = _products.where((x) => x.id == id).firstOrNull;
              final pid = (p?.defaultPrinterId ?? '').trim();
              return pid.isEmpty ||
                  pid.toLowerCase() == widget.printerId.toLowerCase();
            }).toList();
            if (_selectAll || _selectedCategoryIds.isNotEmpty) {
              NotificationOverlayManager().showWarning(
                title: 'Không thể lọc tự động',
                message: tr(
                  'Khi chọn nhóm / Tất cả hãy bỏ chọn món đã gán, '
                  'hoặc bấm «Chuyển sang máy này».',
                ),
              );
              return;
            }
            if (freeIds.isEmpty) {
              NotificationOverlayManager().showWarning(
                title: 'Không có món để gán',
                message: tr('Các món đã chọn đều đang thuộc máy khác'),
              );
              return;
            }
            setState(() {
              _selectedProductIds
                ..clear()
                ..addAll(freeIds);
            });
            await _save(forceReassign: false);
            return;
          }
          return;
        }

        final updated = data != null ? (_readInt(data, 'updated') ?? 0) : 0;
        final already =
            data != null ? (_readInt(data, 'alreadyAssigned') ?? 0) : 0;
        final total = data != null ? (_readInt(data, 'total') ?? 0) : 0;
        if (updated == 0 && already == 0 && total == 0) {
          NotificationOverlayManager().showError(
            title: 'Không gán được',
            message: res['message']?.toString() ??
                data?['message']?.toString() ??
                'Không có sản phẩm nào được cập nhật',
          );
          return;
        }
        PosProductPrinterService.instance.invalidate();
        if (mounted) Navigator.pop(context, true);
        final msg = forceReassign && updated > 0
            ? 'Đã chuyển $updated sản phẩm sang máy này'
            : updated > 0
                ? 'Cập nhật $updated sản phẩm'
                : already > 0
                    ? '$already sản phẩm đã gán trước đó'
                    : 'Đã gán sản phẩm';
        NotificationOverlayManager().showSuccess(
          title: 'Đã gán',
          message: msg,
        );
      } else {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không gán được',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (_productTotal / _pageSize).ceil().clamp(1, 9999);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(tr('Thêm sản phẩm vào máy in'),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: Text(tr('Tất cả sản phẩm')),
                    selected: _selectAll,
                    onSelected: _saving
                        ? null
                        : (v) => setState(() {
                              _selectAll = v;
                              if (v) {
                                _selectedProductIds.clear();
                                _selectedCategoryIds.clear();
                              }
                            }),
                  ),
                ],
              ),
            ),
            if (_categories.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(tr('Theo nhóm hàng'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final c = _categories[i];
                    final sel = _selectedCategoryIds.contains(c.id);
                    return FilterChip(
                      label: Text(tr('${c.name} (${c.productCount})')),
                      selected: sel,
                      onSelected: _saving || _selectAll
                          ? null
                          : (v) => setState(() {
                                if (v) {
                                  _selectedCategoryIds.add(c.id);
                                } else {
                                  _selectedCategoryIds.remove(c.id);
                                }
                              }),
                    );
                  },
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('Tìm mã, tên hàng…'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onSubmitted: (_) async {
                  _page = 1;
                  await _loadProducts();
                  setState(() {});
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: _products.length + 1,
                      itemBuilder: (_, i) {
                        if (i == 0 && _productTotal > _pageSize) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: _page <= 1
                                      ? null
                                      : () async {
                                          _page--;
                                          await _loadProducts();
                                          setState(() {});
                                        },
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Text(tr('$_page / $totalPages')),
                                IconButton(
                                  onPressed: _page >= totalPages
                                      ? null
                                      : () async {
                                          _page++;
                                          await _loadProducts();
                                          setState(() {});
                                        },
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                          );
                        }
                        final idx = _productTotal > _pageSize ? i - 1 : i;
                        if (idx < 0 || idx >= _products.length) {
                          return const SizedBox.shrink();
                        }
                        final p = _products[idx];
                        final checked = _selectAll || _selectedProductIds.contains(p.id);
                        final otherPrinter = (p.defaultPrinterId ?? '').trim().isNotEmpty &&
                            p.defaultPrinterId!.toLowerCase() !=
                                widget.printerId.toLowerCase();
                        final onThis = (p.defaultPrinterId ?? '').trim().isNotEmpty &&
                            p.defaultPrinterId!.toLowerCase() ==
                                widget.printerId.toLowerCase();
                        final sub = [
                          p.productCode,
                          if (otherPrinter)
                            'Đã gán: ${p.defaultPrinterName ?? 'máy khác'}',
                          if (onThis) 'Đã trên máy này',
                        ].where((s) => s.trim().isNotEmpty).join(' · ');
                        return CheckboxListTile(
                          value: checked,
                          onChanged: _saving || _selectAll
                              ? null
                              : (v) => setState(() {
                                    if (v == true) {
                                      _selectedProductIds.add(p.id);
                                    } else {
                                      _selectedProductIds.remove(p.id);
                                    }
                                  }),
                          title: Text(tr(p.name), maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            tr(sub),
                            style: TextStyle(
                              fontSize: 11,
                              color: otherPrinter
                                  ? Colors.orange.shade800
                                  : null,
                            ),
                          ),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: PosTheme.kiotBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            tr(_selectAll
                                ? 'Gán tất cả ($_productTotal SP)'
                                : 'Gán ${_selectionEstimate > 0 ? _selectionEstimate : ''} sản phẩm'),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrinterSummary {
  _PrinterSummary({
    required this.id,
    required this.name,
    this.productCount = 0,
    this.isDeviceLocal = false,
  });

  final String id;
  final String name;
  final int productCount;
  final bool isDeviceLocal;

  factory _PrinterSummary.fromJson(Map<String, dynamic> j) => _PrinterSummary(
        id: (j['printerId'] ?? j['PrinterId'] ?? j['id'] ?? j['Id']).toString(),
        name: (j['printerName'] ?? j['PrinterName'] ?? j['name'] ?? j['Name'] ?? '')
            .toString(),
        productCount: (j['productCount'] as num?)?.toInt() ??
            (j['ProductCount'] as num?)?.toInt() ??
            0,
        isDeviceLocal: j['isDeviceLocal'] == true || j['IsDeviceLocal'] == true,
      );
}

class _ProductItem {
  _ProductItem({
    required this.id,
    required this.productCode,
    required this.name,
    this.categoryName,
    this.defaultPrinterId,
    this.defaultPrinterName,
  });

  final String id;
  final String productCode;
  final String name;
  final String? categoryName;
  final String? defaultPrinterId;
  final String? defaultPrinterName;

  factory _ProductItem.fromJson(Map<String, dynamic> j) => _ProductItem(
        id: (j['id'] ?? j['Id']).toString(),
        productCode: (j['productCode'] ?? j['ProductCode'] ?? '').toString(),
        name: (j['name'] ?? j['Name'] ?? '').toString(),
        categoryName: j['categoryName']?.toString() ?? j['CategoryName']?.toString(),
        defaultPrinterId: (j['defaultPrinterId'] ?? j['DefaultPrinterId'])?.toString(),
        defaultPrinterName:
            (j['defaultPrinterName'] ?? j['DefaultPrinterName'])?.toString(),
      );
}

class _CategoryItem {
  _CategoryItem({
    required this.id,
    required this.name,
    this.productCount = 0,
  });

  final String id;
  final String name;
  final int productCount;

  factory _CategoryItem.fromJson(Map<String, dynamic> j) => _CategoryItem(
        id: (j['id'] ?? j['Id']).toString(),
        name: (j['name'] ?? j['Name'] ?? '').toString(),
        productCount: (j['productCount'] as num?)?.toInt() ??
            (j['ProductCount'] as num?)?.toInt() ??
            0,
      );
}

int? _readInt(Map<String, dynamic> map, String key) {
  final camel = map[key];
  if (camel is num) return camel.toInt();
  final pascal = map[key[0].toUpperCase() + key.substring(1)];
  if (pascal is num) return pascal.toInt();
  return null;
}
