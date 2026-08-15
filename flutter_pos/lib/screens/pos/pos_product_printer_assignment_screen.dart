import 'package:flutter/material.dart';

import '../../models/pos_store_printer.dart';
import '../../services/api_service.dart';
import '../../services/pos_product_printer_service.dart';
import '../../utils/pos_local_printers_store.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Mục đích gán SP → máy in (phân biệt báo bếp / tem / kho).
enum PosAssignPrinterPurpose {
  kitchenSlip,
  kitchenLabel,
  stockIssue,
  mixed,
}

extension on PosAssignPrinterPurpose {
  String get titleVi => switch (this) {
        PosAssignPrinterPurpose.kitchenSlip => 'Báo bếp (phiếu nhiệt)',
        PosAssignPrinterPurpose.kitchenLabel => 'Tem bếp / tem ly',
        PosAssignPrinterPurpose.stockIssue => 'Báo kho / xuất kho',
        PosAssignPrinterPurpose.mixed => 'Gán máy in theo sản phẩm',
      };

  String get bannerVi => switch (this) {
        PosAssignPrinterPurpose.kitchenSlip =>
          'Gán phiếu bếp riêng — không đụng gán tem. '
              'Mỗi món chỉ thuộc 1 máy báo bếp.',
        PosAssignPrinterPurpose.kitchenLabel =>
          'Gán tem riêng — không đụng gán phiếu bếp/hóa đơn. '
              'Chỉ hiện món đã gán máy tem khác khi lọc «Tem máy khác».',
        PosAssignPrinterPurpose.stockIssue =>
          'Món gán máy này → phiếu xuất kho in đúng máy đó.',
        PosAssignPrinterPurpose.mixed =>
          'Mỗi món chỉ gán 1 máy. Món đã gán máy khác có thể chuyển sang máy này.',
      };

  Color get accent => switch (this) {
        PosAssignPrinterPurpose.kitchenSlip => const Color(0xFF1565C0),
        PosAssignPrinterPurpose.kitchenLabel => const Color(0xFF6A1B9A),
        PosAssignPrinterPurpose.stockIssue => const Color(0xFF2E7D32),
        PosAssignPrinterPurpose.mixed => PosTheme.kiotBlue,
      };

  IconData get icon => switch (this) {
        PosAssignPrinterPurpose.kitchenSlip => Icons.restaurant_menu,
        PosAssignPrinterPurpose.kitchenLabel => Icons.label_outline,
        PosAssignPrinterPurpose.stockIssue => Icons.inventory_2_outlined,
        PosAssignPrinterPurpose.mixed => Icons.link,
      };
}

PosAssignPrinterPurpose purposeFromRoles(Iterable<String> roles) {
  final set = roles.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  final hasSlip = set.contains(PosLocalPrinterRoles.kitchenSlip) ||
      set.contains(PosLocalPrinterRoles.kitchenVoid);
  final hasLabel = set.contains(PosLocalPrinterRoles.kitchenLabel);
  final hasStock = set.contains(PosLocalPrinterRoles.stockIssue);
  if (hasLabel && !hasSlip && !hasStock) {
    return PosAssignPrinterPurpose.kitchenLabel;
  }
  if (hasStock && !hasSlip && !hasLabel) {
    return PosAssignPrinterPurpose.stockIssue;
  }
  if (hasSlip && !hasLabel) return PosAssignPrinterPurpose.kitchenSlip;
  if (hasLabel && hasSlip) return PosAssignPrinterPurpose.mixed;
  if (hasStock) return PosAssignPrinterPurpose.stockIssue;
  if (hasLabel) return PosAssignPrinterPurpose.kitchenLabel;
  if (hasSlip) return PosAssignPrinterPurpose.kitchenSlip;
  return PosAssignPrinterPurpose.mixed;
}

PosAssignPrinterPurpose purposeFromFlags({
  required bool isLabel,
  List<String> documentTypes = const [],
}) {
  if (documentTypes.isNotEmpty) return purposeFromRoles(documentTypes);
  return isLabel
      ? PosAssignPrinterPurpose.kitchenLabel
      : PosAssignPrinterPurpose.kitchenSlip;
}

/// Danh sách máy in → chọn máy in → gán sản phẩm.
class PosProductPrinterAssignmentScreen extends StatefulWidget {
  const PosProductPrinterAssignmentScreen({super.key, this.printers});

  final List<PosStorePrinter>? printers;

  @override
  State<PosProductPrinterAssignmentScreen> createState() =>
      _PosProductPrinterAssignmentScreenState();
}

enum _PrinterKindFilter { all, kitchen, label }

class _PosProductPrinterAssignmentScreenState
    extends State<PosProductPrinterAssignmentScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<_PrinterSummary> _printers = [];
  _PrinterKindFilter _filter = _PrinterKindFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getPosPrinterProductSummary();
      if (res['isSuccess'] == true && res['data'] is List) {
        _printers = (res['data'] as List)
            .whereType<Map>()
            .map((e) => _PrinterSummary.fromJson(Map<String, dynamic>.from(e)))
            .where((p) => p.id.isNotEmpty && !p.isDeviceLocal)
            .toList();
      } else if (widget.printers != null && widget.printers!.isNotEmpty) {
        _printers = widget.printers!
            .where((p) => p.isActive && !p.isDeviceLocal)
            .map((p) => _PrinterSummary(
                  id: p.id,
                  name: p.name,
                  productCount: 0,
                  isDeviceLocal: p.isDeviceLocal,
                  isLabel: p.isLabelPrinter,
                  documentTypes: p.documentTypes,
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
            .where((p) => p.isActive && !p.isDeviceLocal)
            .map((p) => _PrinterSummary(
                  id: p.id,
                  name: p.name,
                  productCount: 0,
                  isDeviceLocal: p.isDeviceLocal,
                  isLabel: p.isLabelPrinter,
                  documentTypes: p.documentTypes,
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

  List<_PrinterSummary> get _visible {
    switch (_filter) {
      case _PrinterKindFilter.kitchen:
        return _printers.where((p) => !p.isLabel).toList();
      case _PrinterKindFilter.label:
        return _printers.where((p) => p.isLabel).toList();
      case _PrinterKindFilter.all:
        return _printers;
    }
  }

  void _openPrinter(_PrinterSummary printer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PosPrinterManageProductsScreen(
          printerId: printer.id,
          printerName: printer.name,
          purpose: printer.purpose,
          isLabel: printer.isLabel,
        ),
      ),
    ).then((changed) {
      if (changed == true) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final kitchenCount = _printers.where((p) => !p.isLabel).length;
    final labelCount = _printers.where((p) => p.isLabel).length;
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Gán sản phẩm cho máy in')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Material(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        tr(
                          'Phân biệt máy báo bếp (nhiệt) và máy tem. '
                          'Món đã gán máy khác: bấm «Chuyển» để đổi nhanh.',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade900,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(tr('Tất cả (${_printers.length})')),
                        selected: _filter == _PrinterKindFilter.all,
                        onSelected: (_) =>
                            setState(() => _filter = _PrinterKindFilter.all),
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.restaurant_menu, size: 16),
                        label: Text(tr('Báo bếp ($kitchenCount)')),
                        selected: _filter == _PrinterKindFilter.kitchen,
                        onSelected: (_) => setState(
                            () => _filter = _PrinterKindFilter.kitchen),
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.label_outline, size: 16),
                        label: Text(tr('Tem ($labelCount)')),
                        selected: _filter == _PrinterKindFilter.label,
                        onSelected: (_) =>
                            setState(() => _filter = _PrinterKindFilter.label),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            tr(_printers.isEmpty
                                ? 'Chưa có máy in. Thêm máy in trước.'
                                : 'Không có máy thuộc nhóm này.'),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final p = visible[i];
                            final purpose = p.purpose;
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      purpose.accent.withOpacity(0.12),
                                  child: Icon(
                                    p.isLabel
                                        ? Icons.label_outline
                                        : purpose.icon,
                                    color: purpose.accent,
                                    size: 22,
                                  ),
                                ),
                                title: Text(
                                  tr(p.name),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  tr(
                                    '${purpose.titleVi}\n'
                                    '${p.isDeviceLocal ? 'Máy nội bộ' : 'Agent / cloud'}'
                                    ' · ${p.productCount} sản phẩm'
                                    '${p.hasOnlineAgent ? '' : '\n⚠ Chưa Agent nào nhận lệnh — phiếu sẽ không ra giấy'}',
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.hasOnlineAgent
                                        ? null
                                        : Colors.orange.shade900,
                                  ),
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _openPrinter(p),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class PosPrinterManageProductsScreen extends StatefulWidget {
  const PosPrinterManageProductsScreen({
    super.key,
    required this.printerId,
    required this.printerName,
    this.purpose = PosAssignPrinterPurpose.mixed,
    this.isLabel = false,
  });

  final String printerId;
  final String printerName;
  final PosAssignPrinterPurpose purpose;
  final bool isLabel;

  @override
  State<PosPrinterManageProductsScreen> createState() =>
      _PosPrinterManageProductsScreenState();
}

class _PosPrinterManageProductsScreenState
    extends State<PosPrinterManageProductsScreen> {
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
        forLabel: widget.isLabel,
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
      builder: (_) => _AddProductsSheet(
        printerId: widget.printerId,
        printerName: widget.printerName,
        purpose: widget.purpose,
        isLabel: widget.isLabel,
      ),
    );
    if (changed == true) {
      _page = 1;
      _searchCtrl.clear();
      await PosProductPrinterService.instance.invalidate();
      await _loadAssigned();
      if (mounted) {
        NotificationOverlayManager().showSuccess(
          title: 'Đã cập nhật',
          message: tr('Danh sách gán máy «${widget.printerName}» đã đổi'),
        );
      }
    }
  }

  Future<void> _removeProduct(_ProductItem p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Bỏ khỏi máy in?')),
        content: Text(tr('${p.name}\n(${p.productCode})')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Bỏ'))),
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
        NotificationOverlayManager().showSuccess(
          title: 'Đã bỏ gán',
          message: tr(p.name),
        );
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
    final purpose = widget.purpose;
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr(widget.printerName), overflow: TextOverflow.ellipsis),
        backgroundColor: purpose.accent,
        foregroundColor: Colors.white,
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
                onPressed: _loadAssigned, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addProducts,
        backgroundColor: purpose.accent,
        icon: const Icon(Icons.add),
        label: Text(tr('Thêm / chuyển SP')),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: purpose.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: purpose.accent.withOpacity(0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(purpose.icon, color: purpose.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('${purpose.titleVi}\n${purpose.bannerVi}'),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: purpose.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
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
              child: Text(
                tr('$_total sản phẩm đang gán máy này'),
                style: const TextStyle(
                    fontSize: 12, color: PosTheme.textSecondary),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _assigned.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tr(
                                  'Chưa có sản phẩm trên máy này.\n'
                                  'Bấm «Thêm / chuyển SP» để gán hoặc chuyển từ máy khác.',
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _addProducts,
                                icon: const Icon(Icons.add),
                                label: Text(tr('Thêm / chuyển SP')),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                        itemCount: _assigned.length +
                            (_total > _pageSize ? 1 : 0),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          if (_total > _pageSize && i == 0) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    onPressed: _page <= 1
                                        ? null
                                        : () async {
                                            _page--;
                                            await _loadAssigned();
                                          },
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  Text(tr('$_page / $totalPages')),
                                  IconButton(
                                    onPressed: _page >= totalPages
                                        ? null
                                        : () async {
                                            _page++;
                                            await _loadAssigned();
                                          },
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                            );
                          }
                          final idx = _total > _pageSize ? i - 1 : i;
                          if (idx < 0 || idx >= _assigned.length) {
                            return const SizedBox.shrink();
                          }
                          final p = _assigned[idx];
                          return ListTile(
                            title: Text(tr(p.name)),
                            subtitle: Text(tr(p.productCode)),
                            trailing: IconButton(
                              tooltip: tr('Bỏ gán'),
                              onPressed: _busy ? null : () => _removeProduct(p),
                              icon: const Icon(Icons.link_off,
                                  color: Colors.redAccent),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

enum _ProductAssignFilter { all, unassigned, other, onThis }

class _AddProductsSheet extends StatefulWidget {
  const _AddProductsSheet({
    required this.printerId,
    required this.printerName,
    required this.purpose,
    required this.isLabel,
  });

  final String printerId;
  final String printerName;
  final PosAssignPrinterPurpose purpose;
  final bool isLabel;

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
  String? _lastProductsError;
  _ProductAssignFilter _filter = _ProductAssignFilter.all;
  /// Xác nhận chuyển máy ngay trong sheet (tránh dialog bị che).
  _ConflictPrompt? _conflictPrompt;
  String? _actionBanner;
  bool _actionBannerError = false;

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

  String _lanePrinterId(_ProductItem p) =>
      (widget.isLabel ? p.labelPrinterId : p.defaultPrinterId)?.trim() ?? '';

  String _lanePrinterName(_ProductItem p) =>
      (widget.isLabel ? p.labelPrinterName : p.defaultPrinterName)?.trim() ??
      (widget.isLabel ? 'máy tem khác' : 'máy khác');

  bool _isOnThis(_ProductItem p) {
    final id = _lanePrinterId(p);
    return id.isNotEmpty &&
        id.toLowerCase() == widget.printerId.toLowerCase();
  }

  bool _isOther(_ProductItem p) {
    final id = _lanePrinterId(p);
    return id.isNotEmpty &&
        id.toLowerCase() != widget.printerId.toLowerCase();
  }

  bool _isUnassigned(_ProductItem p) => _lanePrinterId(p).isEmpty;

  void _selectAllOnPage() {
    setState(() {
      _selectAll = false;
      for (final p in _filteredProducts) {
        _selectedProductIds.add(p.id);
      }
    });
  }

  void _selectCategory(_CategoryItem c, bool selected) {
    setState(() {
      _selectAll = false;
      if (selected) {
        // Chỉ đánh dấu nhóm — API gán cả nhóm; không tick trùng SP để tránh đếm 3+3=6.
        _selectedCategoryIds.add(c.id);
      } else {
        _selectedCategoryIds.remove(c.id);
      }
    });
  }

  bool _isChecked(_ProductItem p) {
    if (_selectAll) return true;
    if (_selectedProductIds.contains(p.id)) return true;
    final cid = (p.categoryId ?? '').trim();
    return cid.isNotEmpty && _selectedCategoryIds.contains(cid);
  }

  List<_ProductItem> get _filteredProducts {
    switch (_filter) {
      case _ProductAssignFilter.unassigned:
        return _products.where(_isUnassigned).toList();
      case _ProductAssignFilter.other:
        return _products.where(_isOther).toList();
      case _ProductAssignFilter.onThis:
        return _products.where(_isOnThis).toList();
      case _ProductAssignFilter.all:
        return _products;
    }
  }

  int get _selectedOtherCount => _selectedProductIds.where((id) {
        final p = _products.where((x) => x.id == id).firstOrNull;
        return p != null && _isOther(p);
      }).length;

  Future<void> _load() async {
    setState(() => _loading = true);
    String? err;
    try {
      final catRes = await _api.getPosProductPrinterCategories();
      if (catRes['isSuccess'] == true && catRes['data'] is List) {
        _categories = (catRes['data'] as List)
            .whereType<Map>()
            .map((e) => _CategoryItem.fromJson(Map<String, dynamic>.from(e)))
            .where((c) => c.id.isNotEmpty)
            .toList();
      } else if (catRes['isSuccess'] != true) {
        err = catRes['message']?.toString();
      }
      await _loadProducts();
      if (_products.isEmpty && _productTotal == 0 && err == null) {
        if (_lastProductsError != null) err = _lastProductsError;
      }
    } catch (e) {
      err = e.toString();
      debugPrint('AddProductsSheet._load: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (err != null && err.isNotEmpty) {
          NotificationOverlayManager().showError(
            title: 'Không tải được sản phẩm',
            message: err,
          );
        }
      }
    }
  }

  Future<void> _loadProducts() async {
    _lastProductsError = null;
    final res = await _api.getPosProductPrinterProducts(
      search: _searchCtrl.text,
      page: _page,
      pageSize: _pageSize,
      forLabel: widget.isLabel,
    );
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = Map<String, dynamic>.from(res['data'] as Map);
      _productTotal = _readInt(data, 'total') ?? 0;
      final items = data['items'] ?? data['Items'];
      if (items is List) {
        _products = items
            .whereType<Map>()
            .map((e) => _ProductItem.fromJson(Map<String, dynamic>.from(e)))
            .where((p) => p.id.isNotEmpty && p.id != 'null')
            .toList();
      } else {
        _products = [];
        _lastProductsError = 'API không trả danh sách sản phẩm (items)';
      }
    } else {
      _products = [];
      _productTotal = 0;
      _lastProductsError =
          res['message']?.toString() ?? 'Không tải được danh sách sản phẩm';
    }
  }

  int get _selectionEstimate {
    if (_selectAll) return _productTotal;
    var n = 0;
    // Đếm theo nhóm (cả nhóm trên server) — không cộng thêm SP đã tick trùng nhóm.
    final coveredCats = <String>{};
    for (final c in _categories.where((x) => _selectedCategoryIds.contains(x.id))) {
      n += c.productCount;
      coveredCats.add(c.id);
    }
    for (final id in _selectedProductIds) {
      final p = _products.where((x) => x.id == id).firstOrNull;
      final cid = (p?.categoryId ?? '').trim();
      if (cid.isNotEmpty && coveredCats.contains(cid)) continue;
      n++;
    }
    return n;
  }

  /// [warning] = cần người dùng xác nhận, không phải hỏng — đừng báo «Lỗi gán máy in».
  void _snack(String message, {bool error = false, bool warning = false}) {
    if (!mounted) return;
    setState(() {
      _actionBanner = message;
      _actionBannerError = error || warning;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(tr(message)),
        backgroundColor: warning
            ? Colors.orange.shade800
            : error
                ? Colors.red.shade700
                : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: error || warning ? 4 : 3),
      ),
    );
    // Overlay ngoài sheet thường bị modal che — vẫn gọi để hiện sau khi đóng.
    if (warning) {
      NotificationOverlayManager()
          .showWarning(title: 'Gán máy in', message: message);
    } else if (error) {
      NotificationOverlayManager()
          .showError(title: 'Lỗi gán máy in', message: message);
    } else {
      NotificationOverlayManager()
          .showSuccess(title: 'Gán máy in', message: message);
    }
  }

  void _toggleProduct(_ProductItem p, bool select) {
    setState(() {
      if (select) {
        _selectedProductIds.add(p.id);
      } else {
        _selectedProductIds.remove(p.id);
        final cid = (p.categoryId ?? '').trim();
        if (cid.isNotEmpty) _selectedCategoryIds.remove(cid);
      }
    });
  }

  /// Chọn xong → bấm 1 nút. Có món máy khác thì hỏi xác nhận rồi force chuyển.
  Future<void> _submit() async {
    if (_saving) return;
    if (!_selectAll &&
        _selectedProductIds.isEmpty &&
        _selectedCategoryIds.isEmpty) {
      _snack('Chọn sản phẩm (hoặc nhóm / Tất cả) rồi bấm Gán / Chuyển',
          error: true);
      return;
    }
    await _doAssign(forceReassign: false, openConfirmIfNeeded: true);
  }

  Future<void> _doAssign({
    required bool forceReassign,
    bool openConfirmIfNeeded = false,
  }) async {
    setState(() {
      _saving = true;
      if (forceReassign) _conflictPrompt = null;
    });
    try {
      final ids = _selectedProductIds
          .where((id) => id.isNotEmpty && id != 'null')
          .toList();
      debugPrint(
        'AssignProducts: printer=${widget.printerId} force=$forceReassign '
        'all=$_selectAll cats=${_selectedCategoryIds.length} ids=${ids.length}',
      );
      final res = await _api.assignProductsToPosPrinter(
        widget.printerId,
        allProducts: _selectAll,
        categoryIds: _selectedCategoryIds.toList(),
        productIds: ids,
        forceReassign: forceReassign,
        forLabel: widget.isLabel,
      );
      debugPrint('AssignProducts result: $res');

      if (res['isSuccess'] != true) {
        final msg = res['message']?.toString() ?? 'Không gán / chuyển được';
        if (msg.toLowerCase().contains('không hợp lệ')) {
          _snack(
            'Máy in chưa đồng bộ server (ID cũ/Agent). '
            'Đóng màn này → Máy in nội bộ → Gán sản phẩm lại '
            '(app sẽ tạo máy hợp lệ). Chi tiết: $msg',
            error: true,
          );
        } else {
          _snack(msg, error: true);
        }
        return;
      }

      final raw = res['data'];
      final data = raw is Map ? Map<String, dynamic>.from(raw) : null;
      final needsConfirm =
          data?['needsConfirm'] == true || data?['NeedsConfirm'] == true;

      if (needsConfirm && !forceReassign && openConfirmIfNeeded) {
        final conflictsRaw = data?['conflicts'] ?? data?['Conflicts'];
        final items = <_ProductItem>[];
        if (conflictsRaw is List) {
          for (final e in conflictsRaw) {
            if (e is! Map) continue;
            final m = Map<String, dynamic>.from(e);
            final curId =
                (m['currentPrinterId'] ?? m['CurrentPrinterId'])?.toString();
            final curName = (m['currentPrinterName'] ??
                    m['CurrentPrinterName'])
                ?.toString();
            items.add(_ProductItem(
              id: (m['productId'] ?? m['ProductId'] ?? '').toString(),
              productCode:
                  (m['productCode'] ?? m['ProductCode'] ?? '').toString(),
              name: (m['productName'] ?? m['ProductName'] ?? '').toString(),
              defaultPrinterId: widget.isLabel ? null : curId,
              defaultPrinterName: widget.isLabel ? null : curName,
              labelPrinterId: widget.isLabel ? curId : null,
              labelPrinterName: widget.isLabel ? curName : null,
            ));
          }
        }
        // Fallback: dùng selection local nếu API không trả chi tiết.
        if (items.isEmpty) {
          items.addAll(
            _products.where(
                (p) => _selectedProductIds.contains(p.id) && _isOther(p)),
          );
        }
        if (items.isEmpty && (_selectAll || _selectedCategoryIds.isNotEmpty)) {
          final n = data == null
              ? '?'
              : '${_readInt(data, 'conflictCount') ?? '?'}';
          items.add(_ProductItem(
            id: '_batch',
            productCode: '',
            name: data?['message']?.toString() ??
                '$n món đang ở máy khác',
          ));
        }
        setState(() => _conflictPrompt = _ConflictPrompt.batch(items));
        _snack(
          'Có ${items.where((e) => e.id != '_batch').length} món đang gán máy khác — xác nhận để chuyển',
          warning: true,
        );
        return;
      }

      final updated = data != null ? (_readInt(data, 'updated') ?? 0) : 0;
      final already =
          data != null ? (_readInt(data, 'alreadyAssigned') ?? 0) : 0;
      final total = data != null ? (_readInt(data, 'total') ?? 0) : 0;
      final serverMsg = data?['message']?.toString();

      if (updated == 0 && already == 0 && total == 0) {
        _snack(
          serverMsg ??
              res['message']?.toString() ??
              'Không có sản phẩm nào được cập nhật',
          error: true,
        );
        return;
      }

      await PosProductPrinterService.instance.invalidate();
      final msg = forceReassign && updated > 0
          ? 'Đã chuyển $updated sản phẩm sang «${widget.printerName}»'
          : updated > 0
              ? 'Đã gán $updated sản phẩm vào «${widget.printerName}»'
              : already > 0
                  ? '$already sản phẩm vốn đã gán máy này'
                  : 'Đã gán sản phẩm';
      _snack(msg);
      if (mounted) Navigator.pop(context, true);
    } catch (e, st) {
      debugPrint('AssignProducts error: $e\n$st');
      _snack('Lỗi: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resolveConflict(String choice) async {
    final prompt = _conflictPrompt;
    if (prompt == null) return;

    if (choice == 'cancel') {
      setState(() => _conflictPrompt = null);
      _snack('Đã hủy — chưa chuyển máy', warning: true);
      return;
    }
    if (choice == 'move') {
      // Chọn xong → chuyển một lần (force).
      await _doAssign(forceReassign: true, openConfirmIfNeeded: false);
      return;
    }
    if (choice == 'skip') {
      setState(() => _conflictPrompt = null);
      if (_selectAll || _selectedCategoryIds.isNotEmpty) {
        _snack(
          'Đang chọn nhóm/Tất cả — hãy bấm «Chuyển sang máy này» hoặc bỏ chọn nhóm',
          error: true,
        );
        return;
      }
      final freeIds = _selectedProductIds.where((id) {
        final p = _products.where((x) => x.id == id).firstOrNull;
        return p == null || !_isOther(p);
      }).toList();
      if (freeIds.isEmpty) {
        _snack('Các món đã chọn đều đang thuộc máy khác', error: true);
        return;
      }
      setState(() {
        _selectedProductIds
          ..clear()
          ..addAll(freeIds);
      });
      await _doAssign(forceReassign: false, openConfirmIfNeeded: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (_productTotal / _pageSize).ceil().clamp(1, 9999);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final purpose = widget.purpose;
    final filtered = _filteredProducts;
    final otherOnPage = _products.where(_isOther).length;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr('Gán SP → ${widget.printerName}'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
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
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: purpose.accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tr(
                        '${purpose.titleVi}: chọn nhanh (hết trang / cả nhóm) rồi bấm Gán hoặc Chuyển. '
                        '${purpose.bannerVi}',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: purpose.accent,
                      ),
                    ),
                  ),
                ),
                if (_actionBanner != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Material(
                      color: _actionBannerError
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          _actionBannerError
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          color: _actionBannerError
                              ? Colors.red.shade700
                              : Colors.green.shade700,
                        ),
                        title: Text(
                          tr(_actionBanner!),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _actionBannerError
                                ? Colors.red.shade900
                                : Colors.green.shade900,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _actionBanner = null),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: Text(tr(widget.isLabel
                            ? 'Gán tem cả cửa hàng'
                            : 'Gán bếp cả cửa hàng')),
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
                      ActionChip(
                        avatar: const Icon(Icons.done_all, size: 16),
                        label: Text(tr('Chọn hết trang')),
                        onPressed: _saving ? null : _selectAllOnPage,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.clear_all, size: 16),
                        label: Text(tr('Bỏ chọn')),
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                  _selectAll = false;
                                  _selectedProductIds.clear();
                                  _selectedCategoryIds.clear();
                                }),
                      ),
                      ChoiceChip(
                        label: Text(tr('Lọc: tất cả')),
                        selected: _filter == _ProductAssignFilter.all,
                        onSelected: (_) =>
                            setState(() => _filter = _ProductAssignFilter.all),
                      ),
                      ChoiceChip(
                        label: Text(tr(widget.isLabel
                            ? 'Chưa gán tem'
                            : 'Chưa gán bếp')),
                        selected: _filter == _ProductAssignFilter.unassigned,
                        onSelected: (_) => setState(
                            () => _filter = _ProductAssignFilter.unassigned),
                      ),
                      ChoiceChip(
                        label: Text(tr(widget.isLabel
                            ? 'Tem máy khác ($otherOnPage)'
                            : 'Bếp máy khác ($otherOnPage)')),
                        selected: _filter == _ProductAssignFilter.other,
                        onSelected: (_) => setState(
                            () => _filter = _ProductAssignFilter.other),
                      ),
                      ChoiceChip(
                        label: Text(tr('Máy này')),
                        selected: _filter == _ProductAssignFilter.onThis,
                        onSelected: (_) => setState(
                            () => _filter = _ProductAssignFilter.onThis),
                      ),
                    ],
                  ),
                ),
                if (_categories.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(tr('Nhóm hàng'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final c = _categories[i];
                        final sel = _selectedCategoryIds.contains(c.id);
                        return FilterChip(
                          label: Text(tr('Cả nhóm: ${c.name} (${c.productCount})')),
                          selected: sel,
                          onSelected: _saving || _selectAll
                              ? null
                              : (v) => _selectCategory(c, v),
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
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onSubmitted: (_) async {
                      _page = 1;
                      await _loadProducts();
                      setState(() {});
                    },
                  ),
                ),
                if (_selectedProductIds.isNotEmpty || _selectAll)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Material(
                      color: _selectedOtherCount > 0
                          ? Colors.orange.shade50
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          _selectedOtherCount > 0
                              ? Icons.swap_horiz
                              : Icons.check_circle_outline,
                          color: _selectedOtherCount > 0
                              ? Colors.orange.shade800
                              : Colors.blue.shade800,
                        ),
                        title: Text(
                          tr(
                            _selectAll
                                ? 'Đã chọn TẤT CẢ — bấm nút cam bên dưới để chuyển'
                                : 'Đã chọn ${_selectionEstimate} món'
                                    '${_selectedOtherCount > 0 ? ' · $_selectedOtherCount đang máy khác' : ''}'
                                    ' — bấm nút dưới một lần',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: _selectedOtherCount > 0
                                ? Colors.orange.shade900
                                : Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      tr(_lastProductsError ??
                                          (_products.isEmpty
                                              ? 'Không có sản phẩm trong cửa hàng.'
                                              : 'Không có sản phẩm trong bộ lọc này.')),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed: () async {
                                        _page = 1;
                                        await _load();
                                      },
                                      icon: const Icon(Icons.refresh),
                                      label: Text(tr('Thử lại')),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: filtered.length +
                                  (_productTotal > _pageSize ? 1 : 0),
                              itemBuilder: (_, i) {
                                final hasPager = _productTotal > _pageSize;
                                if (hasPager && i == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
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
                                        Text(tr(' / ')),
                                        IconButton(
                                          onPressed: _page >= totalPages
                                              ? null
                                              : () async {
                                                  _page++;
                                                  await _loadProducts();
                                                  setState(() {});
                                                },
                                          icon:
                                              const Icon(Icons.chevron_right),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                final idx = hasPager ? i - 1 : i;
                                if (idx < 0 || idx >= filtered.length) {
                                  return const SizedBox.shrink();
                                }
                                final p = filtered[idx];
                                final checked = _isChecked(p);
                                final other = _isOther(p);
                                final onThis = _isOnThis(p);
                                return CheckboxListTile(
                                  value: checked,
                                  onChanged: _saving || _selectAll
                                      ? null
                                      : (v) => _toggleProduct(p, v == true),
                                  title: Text(
                                    tr(p.name),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(tr(p.productCode),
                                          style: const TextStyle(fontSize: 11)),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          if (onThis)
                                            _StatusChip(
                                              label: 'Đã trên máy này',
                                              color: Colors.green.shade700,
                                            ),
                                          if (other)
                                            _StatusChip(
                                              label:
                                                  'Đã gán ${widget.isLabel ? 'tem' : 'bếp'}: ${_lanePrinterName(p)}',
                                              color: Colors.orange.shade800,
                                            ),
                                          if (!onThis && !other)
                                            _StatusChip(
                                              label: 'Chưa gán',
                                              color: Colors.blueGrey,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  dense: true,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                );
                              },
                            ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if ((_selectedOtherCount > 0 || _selectAll) &&
                            !_saving)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: FilledButton.icon(
                              onPressed: () => _doAssign(
                                forceReassign: true,
                                openConfirmIfNeeded: false,
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange.shade800,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.swap_horiz),
                              label: Text(
                                tr(_selectAll
                                    ? 'Chuyển tất cả sang máy này'
                                    : 'Chuyển ${_selectedOtherCount} món sang máy này'),
                              ),
                            ),
                          ),
                        FilledButton(
                          onPressed: _saving ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: purpose.accent,
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
                                      ? 'Gán tất cả (hỏi nếu trùng máy)'
                                      : 'Gán ${_selectionEstimate > 0 ? _selectionEstimate : ''} sản phẩm đã chọn'),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_conflictPrompt != null)
              Positioned.fill(
                child: Material(
                  color: Colors.black54,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Card(
                        margin: const EdgeInsets.all(24),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                tr('Có món đã gán máy khác'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                tr(
                                  'Xác nhận chuyển lựa chọn sang «${widget.printerName}».',
                                ),
                              ),
                              const SizedBox(height: 8),
                              ..._conflictPrompt!.items
                                  .where((p) => p.id != '_batch')
                                  .take(5)
                                  .map(
                                    (p) => Text(
                                      tr(
                                        '• ${p.name} → «${_lanePrinterName(p)}»',
                                      ),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _saving
                                    ? null
                                    : () => _resolveConflict('move'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: purpose.accent,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                ),
                                child: Text(tr('Chuyển sang máy này')),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: _saving
                                    ? null
                                    : () => _resolveConflict('skip'),
                                child: Text(tr('Chỉ gán món chưa gán')),
                              ),
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => _resolveConflict('cancel'),
                                child: Text(tr('Hủy')),
                              ),
                            ],
                          ),
                        ),
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


class _ConflictPrompt {
  _ConflictPrompt._(this.items, {required this.isSingle});
  factory _ConflictPrompt.single(_ProductItem p) =>
      _ConflictPrompt._([p], isSingle: true);
  factory _ConflictPrompt.batch(List<_ProductItem> items) =>
      _ConflictPrompt._(items, isSingle: false);

  final List<_ProductItem> items;
  final bool isSingle;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        tr(label),
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
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
    bool isLabel = false,
    this.documentTypes = const [],
    this.hasOnlineAgent = true,
  }) : isLabelFlag = isLabel;

  final String id;
  final String name;
  final int productCount;
  final bool isDeviceLocal;

  /// Máy in trùng tên (cắm lại USB sinh bản ghi mới) khiến món gán vào máy
  /// không Agent nào nhận lệnh: phiếu nằm hàng đợi rồi hết hạn, không ra giấy.
  final bool hasOnlineAgent;

  /// Cờ thô từ server (hãng / khổ giấy) — chỉ dùng khi máy chưa cấu hình chứng từ.
  final bool isLabelFlag;
  final List<String> documentTypes;

  PosAssignPrinterPurpose get purpose => purposeFromFlags(
        isLabel: isLabelFlag,
        documentTypes: documentTypes,
      );

  /// Nhãn hiển thị và lane gán phải cùng một gốc, nếu không máy hiện «Báo kho»
  /// lại ghi vào lane tem → gán xong SP biến mất khỏi danh sách.
  bool get isLabel => purpose == PosAssignPrinterPurpose.kitchenLabel;

  factory _PrinterSummary.fromJson(Map<String, dynamic> j) => _PrinterSummary(
        id: (j['printerId'] ?? j['PrinterId'] ?? j['id'] ?? j['Id'])
            .toString(),
        name:
            (j['printerName'] ?? j['PrinterName'] ?? j['name'] ?? j['Name'] ?? '')
                .toString(),
        productCount: (j['productCount'] as num?)?.toInt() ??
            (j['ProductCount'] as num?)?.toInt() ??
            0,
        isDeviceLocal:
            j['isDeviceLocal'] == true || j['IsDeviceLocal'] == true,
        isLabel: j['isLabel'] == true ||
            j['IsLabel'] == true ||
            (j['printerBrand'] ?? j['PrinterBrand'])
                    ?.toString()
                    .toLowerCase() ==
                'label',
        documentTypes: () {
          final raw = j['documentTypes'] ?? j['DocumentTypes'];
          if (raw is! List) return const <String>[];
          return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
        }(),
        // Server cũ không trả cờ này → coi như có Agent, tránh cảnh báo sai.
        hasOnlineAgent: (j['hasOnlineAgent'] ?? j['HasOnlineAgent']) == null
            ? true
            : (j['hasOnlineAgent'] == true || j['HasOnlineAgent'] == true),
      );
}

class _ProductItem {
  _ProductItem({
    required this.id,
    required this.productCode,
    required this.name,
    this.categoryId,
    this.categoryName,
    this.defaultPrinterId,
    this.defaultPrinterName,
    this.labelPrinterId,
    this.labelPrinterName,
  });

  final String id;
  final String productCode;
  final String name;
  final String? categoryId;
  final String? categoryName;
  final String? defaultPrinterId;
  final String? defaultPrinterName;
  final String? labelPrinterId;
  final String? labelPrinterName;

  factory _ProductItem.fromJson(Map<String, dynamic> j) => _ProductItem(
        id: (j['id'] ?? j['Id'] ?? j['productId'] ?? j['ProductId']).toString(),
        productCode: (j['productCode'] ?? j['ProductCode'] ?? '').toString(),
        name: (j['name'] ?? j['Name'] ?? '').toString(),
        categoryId: (j['categoryId'] ?? j['CategoryId'])?.toString(),
        categoryName:
            j['categoryName']?.toString() ?? j['CategoryName']?.toString(),
        // Lane phiếu bếp
        defaultPrinterId: (j['defaultPrinterId'] ??
                j['DefaultPrinterId'] ??
                j['printerId'] ??
                j['PrinterId'])
            ?.toString(),
        defaultPrinterName: (j['defaultPrinterName'] ??
                j['DefaultPrinterName'] ??
                j['printerName'] ??
                j['PrinterName'])
            ?.toString(),
        // Lane tem — tách riêng, không đè phiếu bếp
        labelPrinterId: (j['labelPrinterId'] ??
                j['LabelPrinterId'] ??
                j['defaultLabelPrinterId'] ??
                j['DefaultLabelPrinterId'])
            ?.toString(),
        labelPrinterName: (j['labelPrinterName'] ??
                j['LabelPrinterName'] ??
                j['defaultLabelPrinterName'] ??
                j['DefaultLabelPrinterName'])
            ?.toString(),
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
