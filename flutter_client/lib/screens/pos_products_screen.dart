import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_product.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart' as file_saver;
import '../utils/responsive_helper.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../utils/number_formatter.dart';
import '../utils/pos_kiot_time_range.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_barcode_label_dialog.dart';
import '../widgets/pos/pos_catalog_manage.dart';
import '../widgets/pos/pos_product_column_prefs.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_product_filter_sidebar.dart';
import '../widgets/pos/pos_product_data_table.dart';
import '../widgets/pos/pos_product_table_columns.dart';
import '../widgets/pos/pos_product_type_badge.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/pos/pos_product_expansion_panel.dart';
import '../widgets/pos/pos_product_unit_view.dart';
import '../widgets/pos/pos_unit_chip_selector.dart';
import '../widgets/pos/pos_hub_scope.dart';
import '../widgets/pos/pos_product_image.dart';
import '../utils/navigation_notifier.dart';
import '../widgets/pos_barcode_scanner.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;
import 'pos/pos_product_editor_page.dart';

/// Danh sách hàng hóa — giao diện kiểu KiotViet.
class PosProductsScreen extends StatefulWidget {
  const PosProductsScreen({super.key});

  @override
  State<PosProductsScreen> createState() => _PosProductsScreenState();
}

class _PosProductsScreenState extends State<PosProductsScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

  bool _loading = true;
  List<PosProduct> _items = [];
  int _total = 0;
  double _totalOnHand = 0;
  int _page = 1;
  static const _pageSize = 50;
  int _totalPages = 1;

  List<PosCatalogItem> _categories = [];
  List<PosCatalogItem> _brands = [];
  List<PosCatalogItem> _locations = [];
  List<PosCatalogItem> _suppliers = [];

  String? _categoryFilter;
  String? _brandFilter;
  String? _locationFilter;
  String? _supplierFilter;
  PosProductType? _typeFilter;
  PosStockFilter _stockFilter = PosStockFilter.all;
  PosStockoutFilter _stockoutFilter = PosStockoutFilter.all;
  bool? _directSaleFilter;
  PosProductSortBy _sortBy = PosProductSortBy.createdAt;
  bool _sortDesc = true;
  bool _includeInactive = false;
  PosKiotTimeFilterState _createdTimeFilter = PosKiotTimeFilterState.allTime();
  bool _useStockoutCustom = false;
  DateTime? _stockoutBefore;
  bool _isExporting = false;
  final Set<String> _selectedIds = {};
  Set<PosProductTableColumn> _visibleColumns = defaultPosProductVisibleColumns();
  String? _expandedProductId;
  String? _selectedVariantId;
  final Map<String, List<PosProductVariant>> _variantsByProductId = {};
  final Set<String> _variantsLoadingIds = {};
  final Map<String, String?> _unitViewVariantIdByProductId = {};

  @override
  void initState() {
    super.initState();
    ScreenRefreshNotifier.posProducts.addListener(_onExternalRefresh);
    NavigationNotifier.currentModuleCode.addListener(_onModuleVisible);
    _loadColumnPrefs();
    _loadAll();
  }

  void _onExternalRefresh() {
    if (!mounted) return;
    _reloadProducts();
  }

  void _onModuleVisible() {
    if (!mounted) return;
    if (NavigationNotifier.currentModuleCode.value == 'PosProducts') {
      _reloadProducts();
    }
  }

  Future<void> _loadColumnPrefs() async {
    final cols = await loadPosProductVisibleColumns();
    if (mounted) setState(() => _visibleColumns = cols);
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.posProducts.removeListener(_onExternalRefresh);
    NavigationNotifier.currentModuleCode.removeListener(_onModuleVisible);
    _searchCtrl.dispose();
    super.dispose();
  }

  PosProductType? get _typeFilterParam => _typeFilter;

  Future<void> _reloadProducts() async {
    await _loadProducts(page: 1);
    if (mounted) setState(() {});
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([_loadCatalogs(), _loadProducts()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCatalogs() async {
    final results = await Future.wait([
      _api.getPosProductCategories(),
      _api.getPosProductBrands(),
      _api.getPosStorageLocations(),
      _api.getPosSuppliers(),
    ]);
    if (!mounted) return;
    if (results[0]['isSuccess'] == true && results[0]['data'] is List) {
      _categories = (results[0]['data'] as List)
          .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (results[1]['isSuccess'] == true && results[1]['data'] is List) {
      _brands = (results[1]['data'] as List)
          .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (results[2]['isSuccess'] == true && results[2]['data'] is List) {
      _locations = (results[2]['data'] as List)
          .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (results[3]['isSuccess'] == true && results[3]['data'] is List) {
      _suppliers = (results[3]['data'] as List)
          .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  void _onCreatedTimeFilterChanged(PosKiotTimeFilterState s) {
    setState(() => _createdTimeFilter = s);
    _reloadProducts();
  }

  Future<void> _loadProducts({int? page}) async {
    if (page != null) _page = page;
    final res = await _api.getPosProducts(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      categoryId: _categoryFilter,
      brandId: _brandFilter,
      storageLocationId: _locationFilter,
      supplierId: _supplierFilter,
      productType: _typeFilterParam,
      isDirectSale: _directSaleFilter,
      stockFilter: _stockFilter,
      stockoutFilter: _useStockoutCustom
          ? PosStockoutFilter.all
          : _stockoutFilter,
      sortBy: _sortBy,
      sortDesc: _sortDesc,
      includeInactive: _includeInactive,
      createdFrom: _createdTimeFilter.from,
      createdTo: _createdTimeFilter.to,
      page: _page,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map<String, dynamic>;
      final list = data['items'] as List? ?? [];
      _items = list
          .map((e) => PosProduct.fromJson(e as Map<String, dynamic>))
          .toList();
      if (_useStockoutCustom && _stockoutBefore != null) {
        final before = _stockoutBefore!;
        _items = _items
            .where((p) =>
                p.estimatedStockoutDate != null &&
                !p.estimatedStockoutDate!.isAfter(before))
            .toList();
      }
      _total = (data['total'] as num?)?.toInt() ?? _items.length;
      _totalPages = (_total / _pageSize).ceil().clamp(1, 9999);
      final summary = data['summary'] as Map<String, dynamic>?;
      _totalOnHand = (summary?['totalOnHandQty'] as num?)?.toDouble() ??
          _items.fold(0.0, (a, b) => a + b.onHandQty);
      await _prefetchVariantsForPage();
    }
  }

  Future<void> _prefetchVariantsForPage() async {
    for (final p in _items) {
      if (p.variantCount > 0 &&
          !_variantsByProductId.containsKey(p.id) &&
          !_variantsLoadingIds.contains(p.id)) {
        await _loadVariantsForProduct(p);
      }
    }
  }

  void _setUnitView(PosProduct p, String? variantId) {
    setState(() {
      _unitViewVariantIdByProductId[p.id] = variantId;
      _selectedVariantId = variantId;
    });
  }

  Future<void> _openCreate(PosProductType type) async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!perm.canCreate('PosProducts')) return;
    final saved = await PosProductEditorPage.open(
      context,
      productType: type,
    );
    if (saved == true) {
      await _loadCatalogs();
      await _loadProducts(page: 1);
      if (mounted) setState(() {});
    }
  }

  void _toggleExpand(PosProduct p) {
    final next = _expandedProductId == p.id ? null : p.id;
    setState(() {
      _expandedProductId = next;
      if (next == null) _selectedVariantId = null;
    });
    if (next != null) {
      _variantsByProductId.remove(p.id);
      _loadVariantsForProduct(p);
    }
  }

  void _selectVariant(PosProduct p, PosProductVariant? v) {
    setState(() {
      if (v == null) {
        _selectedVariantId = null;
      } else {
        _expandedProductId = p.id;
        _selectedVariantId = v.id;
      }
    });
    if (v != null && !_variantsByProductId.containsKey(p.id)) {
      _loadVariantsForProduct(p);
    }
  }

  Future<void> _loadVariantsForProduct(PosProduct p, {bool force = false}) async {
    if (!force &&
        (_variantsByProductId.containsKey(p.id) ||
            _variantsLoadingIds.contains(p.id))) {
      return;
    }
    setState(() => _variantsLoadingIds.add(p.id));
    final res = await _api.getPosProductVariants(p.id);
    if (!mounted) return;
    setState(() {
      _variantsLoadingIds.remove(p.id);
      if (res['isSuccess'] == true && res['data'] is List) {
        _variantsByProductId[p.id] = (res['data'] as List)
            .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _variantsByProductId[p.id] = [];
      }
    });
  }

  Future<void> _addSameTypeProduct(PosProduct p) async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!perm.canEdit('PosProducts')) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: 'Bạn không có quyền sửa hàng hóa',
      );
      return;
    }
    final saved = await PosProductEditorPage.open(
      context,
      productType: p.productType,
      product: p,
      openUnitSetup: true,
      unitSetupAddMore: true,
    );
    if (!mounted) return;
    if (saved == true) {
      _variantsByProductId.remove(p.id);
      await _loadProducts();
      if (mounted) {
        setState(() {
          _expandedProductId = p.id;
        });
        await _loadVariantsForProduct(p);
      }
    }
  }

  Future<void> _copyProduct(PosProduct p) async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!perm.canCreate('PosProducts')) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: 'Bạn không có quyền thêm hàng hóa',
      );
      return;
    }

    PosProduct source = p;
    final detail = await _api.getPosProduct(p.id);
    if (detail['isSuccess'] == true && detail['data'] is Map) {
      source = PosProduct.fromJson(detail['data'] as Map<String, dynamic>);
    }

    final saved = await PosProductEditorPage.open(
      context,
      productType: source.productType,
      templateProduct: source,
    );
    if (!mounted) return;
    if (saved == true) {
      await _loadProducts(page: 1);
      setState(() {});
    }
  }

  Future<void> _deleteProduct(PosProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa hàng hóa'),
        content: Text('Xóa «${p.name}»?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.deletePosProduct(p.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      setState(() {
        _items.removeWhere((x) => x.id == p.id);
        _selectedIds.remove(p.id);
        if (_expandedProductId == p.id) _expandedProductId = null;
        if (_total > 0) _total -= 1;
      });
      NotificationOverlayManager().showSuccess(
        title: 'Thành công',
        message: 'Đã xóa hàng hóa',
      );
      await _loadProducts();
      if (mounted) setState(() {});
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không thể xóa',
      );
    }
  }

  Future<void> _printLabel(PosProduct p) async {
    await showPosBarcodeLabelDialog(context, [p]);
  }

  Future<void> _openEdit(PosProduct p) async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!perm.canEdit('PosProducts')) return;
    final saved = await PosProductEditorPage.open(
      context,
      productType: p.productType,
      product: p,
    );
    if (saved == true) {
      _variantsByProductId.remove(p.id);
      await _loadProducts();
      if (mounted) {
        setState(() {
          if (_expandedProductId == p.id) {
            _loadVariantsForProduct(p);
          }
        });
      }
    }
  }

  Future<void> _openEditVariant(PosProduct p, PosProductVariant v) async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!perm.canEdit('PosProducts')) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: 'Bạn không có quyền sửa hàng hóa',
      );
      return;
    }
    final saved = await PosProductEditorPage.openVariantUnitSetup(
      context,
      product: p,
      variant: v,
    );
    if (!mounted) return;
    if (saved == true) {
      _variantsByProductId.remove(p.id);
      await _loadProducts();
      if (mounted) {
        setState(() {
          _expandedProductId = p.id;
          _selectedVariantId = v.id;
        });
        await _loadVariantsForProduct(p);
      }
    }
  }

  Future<void> _toggleFavorite(PosProduct p, bool next) async {
    await _api.togglePosProductFavorite(p.id, next);
    await _loadProducts();
    if (mounted) setState(() {});
  }

  Future<void> _quickEditPrice(PosProduct p) async {
    final ctrl = TextEditingController(
        text: NumberFormat('#,###', 'vi_VN').format(p.basePrice.round()));
    final val = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sửa giá bán — ${p.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [ThousandSeparatorFormatter()],
          decoration: PosTheme.inputDecoration(label: 'Giá bán'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, parseFormattedNumber(ctrl.text)?.toDouble()),
            style: PosTheme.filledButtonStyle,
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (val == null) return;
    final res = await _api.patchPosProductQuick(p.id, basePrice: val);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _loadProducts();
      setState(() {});
    }
  }

  Future<void> _quickEditStock(PosProduct p) async {
    final ctrl =
        TextEditingController(text: p.onHandQty.toStringAsFixed(0));
    final val = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sửa tồn kho — ${p.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: PosTheme.inputDecoration(label: 'Tồn kho'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, double.tryParse(ctrl.text.replaceAll(',', ''))),
            style: PosTheme.filledButtonStyle,
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (val == null) return;
    final res = await _api.patchPosProductQuick(p.id, onHandQty: val);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _loadProducts();
      setState(() {});
    }
  }

  Future<void> _refreshExpandedVariants() async {
    final id = _expandedProductId;
    if (id == null) return;
    final p = _items.cast<PosProduct?>().firstWhere(
          (x) => x?.id == id,
          orElse: () => null,
        );
    if (p != null) {
      _variantsByProductId.remove(p.id);
      await _loadVariantsForProduct(p, force: true);
    }
  }

  Future<void> _quickEditVariantPrice(PosProduct p, PosProductVariant v) async {
    final ctrl = TextEditingController(
        text: NumberFormat('#,###', 'vi_VN').format(v.basePrice.round()));
    final val = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sửa giá bán — ${v.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [ThousandSeparatorFormatter()],
          decoration: PosTheme.inputDecoration(label: 'Giá bán'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, parseFormattedNumber(ctrl.text)?.toDouble()),
            style: PosTheme.filledButtonStyle,
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (val == null) return;
    final res = await _api.patchPosProductVariantQuick(p.id, v.id, basePrice: val);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _loadProducts();
      await _refreshExpandedVariants();
      if (mounted) setState(() {});
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không thể cập nhật giá',
      );
    }
  }

  Future<void> _quickEditVariantStock(PosProduct p, PosProductVariant v) async {
    final ctrl = TextEditingController(text: v.onHandQty.toStringAsFixed(0));
    final val = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sửa tồn kho — ${v.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: PosTheme.inputDecoration(label: 'Tồn kho'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, double.tryParse(ctrl.text.replaceAll(',', ''))),
            style: PosTheme.filledButtonStyle,
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (val == null) return;
    final res = await _api.patchPosProductVariantQuick(p.id, v.id, onHandQty: val);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _loadProducts();
      await _refreshExpandedVariants();
      if (mounted) setState(() {});
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không thể cập nhật tồn',
      );
    }
  }

  Future<void> _deleteVariant(PosProduct p, PosProductVariant v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa hàng cùng loại'),
        content: Text('Xóa «${v.name}» (${v.skuCode})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.deletePosProductVariant(p.id, v.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      if (_selectedVariantId == v.id) _selectedVariantId = null;
      setState(() {
        final list = _variantsByProductId[p.id];
        if (list != null) {
          _variantsByProductId[p.id] =
              list.where((x) => x.id != v.id).toList();
        }
      });
      await _loadProducts();
      _variantsByProductId.remove(p.id);
      await _loadVariantsForProduct(p, force: true);
      if (mounted) setState(() {});
      NotificationOverlayManager().showSuccess(
        title: 'Thành công',
        message: 'Đã xóa hàng cùng loại',
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không thể xóa',
      );
    }
  }

  Future<void> _exportExcel(PermissionProvider perm) async {
    if (!perm.canExport('PosProducts')) return;
    setState(() => _isExporting = true);
    try {
      final res = await _api.exportPosProductsExcel(
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        categoryId: _categoryFilter,
        supplierId: _supplierFilter,
      );
      if (res['isSuccess'] == true) {
        final bytes = Uint8List.fromList(List<int>.from(res['data']));
        await file_saver.saveFileBytes(
          bytes,
          'hang_hoa_pos_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        NotificationOverlayManager().showSuccess(
            title: 'Xuất file', message: 'Đã xuất Excel hàng hóa');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importExcel(PermissionProvider perm) async {
    if (!perm.canCreate('PosProducts')) return;
    final fileResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (fileResult == null || fileResult.files.isEmpty) return;
    final file = fileResult.files.first;
    if (file.bytes == null) return;
    final res = await _api.importPosProductsExcelFile(file.bytes!, file.name);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'] as Map<String, dynamic>?;
      NotificationOverlayManager().showSuccess(
        title: 'Import thành công',
        message:
            'Tạo mới: ${data?['created'] ?? 0}, Cập nhật: ${data?['updated'] ?? 0}',
      );
      await _loadAll();
      setState(() {});
    }
  }

  Future<void> _batchPrintLabels() async {
    if (_selectedIds.isEmpty) return;
    final products = _items.where((p) => _selectedIds.contains(p.id)).toList();
    await showPosBarcodeLabelDialog(context, products);
  }

  Future<void> _scanSearch() async {
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    _searchCtrl.text = code;
    await _loadProducts(page: 1);
    setState(() {});
  }

  Future<void> _addCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm nhóm hàng'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: PosTheme.inputDecoration(label: 'Tên nhóm'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: PosTheme.filledButtonStyle,
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    final res = await _api.createPosProductCategory(
      name,
      parentId: _categoryFilter,
    );
    if (res['isSuccess'] == true) {
      await _loadCatalogs();
      if (mounted) setState(() {});
    }
  }

  Future<void> _manageCatalog(PosCatalogKind kind) async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canEdit = perm.canEdit('PosProducts');
    final canDelete = perm.canDelete('PosProducts');
    if (!canEdit && !canDelete) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: 'Bạn không có quyền quản lý danh mục',
      );
      return;
    }

    List<PosCatalogItem> items;
    switch (kind) {
      case PosCatalogKind.category:
        items = _categories;
      case PosCatalogKind.brand:
        items = _brands;
      case PosCatalogKind.location:
        items = _locations;
      case PosCatalogKind.supplier:
        items = _suppliers;
    }

    await showPosCatalogManageDialog(
      context: context,
      api: _api,
      kind: kind,
      items: items,
      categoriesForParent: _categories,
      canEdit: canEdit,
      canDelete: canDelete,
      onRefresh: () async {
        final prevCategory = _categoryFilter;
        final prevBrand = _brandFilter;
        final prevLocation = _locationFilter;
        final prevSupplier = _supplierFilter;
        await _loadCatalogs();
        if (!mounted) return _categories;
        setState(() {
          if (prevCategory != null &&
              !_categories.any((c) => c.id == prevCategory)) {
            _categoryFilter = null;
          }
          if (prevBrand != null && !_brands.any((c) => c.id == prevBrand)) {
            _brandFilter = null;
          }
          if (prevLocation != null &&
              !_locations.any((c) => c.id == prevLocation)) {
            _locationFilter = null;
          }
          if (prevSupplier != null &&
              !_suppliers.any((c) => c.id == prevSupplier)) {
            _supplierFilter = null;
          }
        });
        await _reloadProducts();
        return switch (kind) {
          PosCatalogKind.category => _categories,
          PosCatalogKind.brand => _brands,
          PosCatalogKind.location => _locations,
          PosCatalogKind.supplier => _suppliers,
        };
      },
    );
  }


  void _onCreateType(String type) {
    switch (type) {
      case 'goods':
        _openCreate(PosProductType.goods);
      case 'service':
        _openCreate(PosProductType.service);
      case 'combo':
        _openCreate(PosProductType.combo);
    }
  }

  void _showColumnPicker() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Hiển thị cột'),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: PosProductTableColumn.values
                    .where((c) => c.canToggle)
                    .map((c) => CheckboxListTile(
                          dense: true,
                          activeColor: PosTheme.kiotBlue,
                          title: Text(c.label, style: const TextStyle(fontSize: 13)),
                          value: _visibleColumns.contains(c),
                          onChanged: (v) {
                            setDlg(() {
                              if (v == true) {
                                _visibleColumns.add(c);
                              } else {
                                _visibleColumns.remove(c);
                              }
                            });
                            setState(() {});
                            savePosProductVisibleColumns(_visibleColumns);
                          },
                        ))
                    .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _visibleColumns = defaultPosProductVisibleColumns());
                savePosProductVisibleColumns(_visibleColumns);
                Navigator.pop(ctx);
              },
              child: const Text('Mặc định'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
              child: const Text('Xong'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final wide = Responsive.preferTableListLayout(context) && Responsive.isDesktop(context);
    final mobile = posUseMobileList(context);
    final inHub = PosHubScope.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      floatingActionButton: mobile && perm.canCreate('PosProducts')
          ? PosMobileFab(onPressed: () => _onCreateType('goods'))
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!inHub) const PosModuleToolbar(activeModule: 'PosProducts'),
          if (mobile)
            PosMobileKiotHeader(
              title: 'Hàng hoá',
              onSearch: () => _focusSearch(),
              onFilter: () => _openMobileFilters(perm),
              onSort: _showSortSheet,
              onMore: () => _showMobileMoreMenu(perm),
              activeFilterCount: _activeMobileFilterCount,
              filterChips: _buildFilterChipsRow(),
            )
          else
            _buildMainToolbar(perm, wide),
          if (_selectedIds.isNotEmpty) _buildSelectionBar(),
          if (mobile) _buildMobileStockSummary(),
          Expanded(
            child: _loading
                ? const LoadingWidget(message: 'Đang tải hàng hóa…')
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wide)
                        SizedBox(
                          width: 280,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                right: BorderSide(color: PosTheme.border),
                              ),
                            ),
                            child: PosProductFilterSidebar(
                              categories: _categories,
                              brands: _brands,
                              locations: _locations,
                              suppliers: _suppliers,
                              categoryId: _categoryFilter,
                              brandId: _brandFilter,
                              locationId: _locationFilter,
                              supplierId: _supplierFilter,
                              productType: _typeFilter,
                              stockFilter: _stockFilter,
                              stockoutFilter: _stockoutFilter,
                              directSaleFilter: _directSaleFilter,
                              includeInactive: _includeInactive,
                              createdTimeFilter: _createdTimeFilter,
                              useStockoutCustom: _useStockoutCustom,
                              stockoutBefore: _stockoutBefore,
                              onCategoryChanged: (v) async {
                                setState(() => _categoryFilter = v);
                                await _reloadProducts();
                              },
                              onBrandChanged: (v) async {
                                setState(() => _brandFilter = v);
                                await _reloadProducts();
                              },
                              onLocationChanged: (v) async {
                                setState(() => _locationFilter = v);
                                await _reloadProducts();
                              },
                              onSupplierChanged: (v) async {
                                setState(() => _supplierFilter = v);
                                await _reloadProducts();
                              },
                              onProductTypeChanged: (v) async {
                                setState(() => _typeFilter = v);
                                await _reloadProducts();
                              },
                              onStockFilterChanged: (v) async {
                                setState(() => _stockFilter = v);
                                await _reloadProducts();
                              },
                              onStockoutFilterChanged: (v) async {
                                setState(() => _stockoutFilter = v);
                                await _reloadProducts();
                              },
                              onDirectSaleFilterChanged: (v) async {
                                setState(() => _directSaleFilter = v);
                                await _reloadProducts();
                              },
                              onIncludeInactiveChanged: (v) async {
                                setState(() => _includeInactive = v);
                                await _reloadProducts();
                              },
                              onCreatedTimeFilterChanged: _onCreatedTimeFilterChanged,
                              onStockoutCustomChanged: (v) async {
                                setState(() => _useStockoutCustom = v);
                                await _reloadProducts();
                              },
                              onStockoutBeforeChanged: (d) async {
                                setState(() => _stockoutBefore = d);
                                await _reloadProducts();
                              },
                              onCreateCategory: perm.canCreate('PosProducts')
                                  ? _addCategory
                                  : null,
                              onManageCategory: (perm.canEdit('PosProducts') ||
                                      perm.canDelete('PosProducts'))
                                  ? () => _manageCatalog(PosCatalogKind.category)
                                  : null,
                              onManageSupplier: (perm.canEdit('PosProducts') ||
                                      perm.canDelete('PosProducts'))
                                  ? () =>
                                      _manageCatalog(PosCatalogKind.supplier)
                                  : null,
                              onManageLocation: (perm.canEdit('PosProducts') ||
                                      perm.canDelete('PosProducts'))
                                  ? () =>
                                      _manageCatalog(PosCatalogKind.location)
                                  : null,
                              onManageBrand: (perm.canEdit('PosProducts') ||
                                      perm.canDelete('PosProducts'))
                                  ? () => _manageCatalog(PosCatalogKind.brand)
                                  : null,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Column(
                          children: [
                            if (!wide) _buildMobileFilterBar(perm),
                            Expanded(child: _buildContent(perm, wide)),
                            _buildPagination(),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainToolbar(PermissionProvider perm, bool wide) {
    final mobile = posUseMobileList(context);
    return Material(
      color: Colors.white,
      elevation: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(mobile ? 12 : 16, 12, mobile ? 12 : 16, 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PosTheme.border)),
        ),
        child: mobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Bộ lọc',
                        onPressed: () => _openMobileFilters(perm),
                        icon: const Icon(Icons.filter_list),
                      ),
                      const Expanded(
                        child: Text(
                          'Hàng hóa',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: PosTheme.textPrimary,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'refresh') {
                            _loadAll();
                          } else if (v == 'columns') {
                            _showColumnPicker();
                          } else if (v == 'scan') {
                            _scanSearch();
                          } else if (v == 'export' && perm.canExport('PosProducts')) {
                            _exportExcel(perm);
                          } else if (v == 'import' && perm.canCreate('PosProducts')) {
                            _importExcel(perm);
                          } else if (v.startsWith('create_') &&
                              perm.canCreate('PosProducts')) {
                            _onCreateType(v.replaceFirst('create_', ''));
                          }
                        },
                        itemBuilder: (_) => [
                          if (perm.canCreate('PosProducts')) ...[
                            const PopupMenuItem(
                                value: 'create_goods', child: Text('Tạo hàng hóa')),
                            const PopupMenuItem(
                                value: 'create_service', child: Text('Tạo dịch vụ')),
                            const PopupMenuItem(
                                value: 'create_combo', child: Text('Tạo combo')),
                          ],
                          const PopupMenuItem(
                              value: 'columns', child: Text('Hiển thị cột')),
                          const PopupMenuItem(
                              value: 'scan', child: Text('Quét mã vạch')),
                          if (perm.canExport('PosProducts'))
                            const PopupMenuItem(
                                value: 'export', child: Text('Xuất file')),
                          if (perm.canCreate('PosProducts'))
                            const PopupMenuItem(
                                value: 'import', child: Text('Import file')),
                          const PopupMenuItem(
                              value: 'refresh', child: Text('Làm mới')),
                        ],
                        icon: const Icon(Icons.more_vert),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Theo mã, tên hàng',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: const Color(0xFFF5F7FA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _reloadProducts(),
                  ),
                  if (perm.canCreate('PosProducts')) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => _onCreateType('goods'),
                      icon: const Icon(Icons.add, size: 18),
                      style: FilledButton.styleFrom(
                        backgroundColor: PosTheme.kiotBlue,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      label: const Text('Tạo mới'),
                    ),
                  ],
                ],
              )
            : Row(
          children: [
            if (!wide)
              IconButton(
                tooltip: 'Bộ lọc',
                onPressed: () => _openMobileFilters(perm),
                icon: const Icon(Icons.filter_list),
              ),
            const Text(
              'Hàng hóa',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: PosTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Theo mã, tên hàng',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF5F7FA),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: PosTheme.kiotBlue),
                    ),
                  ),
                  onSubmitted: (_) => _reloadProducts(),
                ),
              ),
            ),
            const Spacer(),
            if (perm.canCreate('PosProducts'))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PopupMenuButton<String>(
                  onSelected: _onCreateType,
                  offset: const Offset(0, 40),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: PosTheme.kiotBlue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text('Tạo mới',
                            style: TextStyle(color: Colors.white, fontSize: 14)),
                        Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
                      ],
                    ),
                  ),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'goods', child: Text('Hàng hóa')),
                    PopupMenuItem(value: 'service', child: Text('Dịch vụ')),
                    PopupMenuItem(value: 'combo', child: Text('Combo / Đóng gói')),
                  ],
                ),
              ),
            if (perm.canCreate('PosProducts'))
              OutlinedButton.icon(
                onPressed: () => _importExcel(perm),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Import file'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PosTheme.textPrimary,
                  side: const BorderSide(color: PosTheme.border),
                ),
              ),
            if (perm.canExport('PosProducts')) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _isExporting ? null : () => _exportExcel(perm),
                icon: const Icon(Icons.download, size: 18),
                label: Text(_isExporting ? 'Đang xuất…' : 'Xuất file'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PosTheme.textPrimary,
                  side: const BorderSide(color: PosTheme.border),
                ),
              ),
            ],
            IconButton(
              tooltip: 'Hiển thị cột',
              onPressed: _showColumnPicker,
              icon: const Icon(Icons.view_column_outlined),
            ),
            IconButton(
              tooltip: 'Quét mã vạch',
              onPressed: _scanSearch,
              icon: const Icon(Icons.qr_code_scanner),
            ),
            IconButton(
              tooltip: 'Làm mới',
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    return Material(
      color: PosTheme.kiotBlueLight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text('Đã chọn ${_selectedIds.length}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _selectedIds.clear()),
              child: const Text('Bỏ chọn'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _batchPrintLabels,
              icon: const Icon(Icons.qr_code, size: 18),
              label: const Text('In tem mã vạch'),
              style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
            ),
          ],
        ),
      ),
    );
  }

  int get _activeMobileFilterCount {
    var n = 0;
    if (_categoryFilter != null) n++;
    if (_typeFilter != null) n++;
    if (_stockFilter != PosStockFilter.all) n++;
    if (_stockoutFilter != PosStockoutFilter.all) n++;
    if (_brandFilter != null) n++;
    return n;
  }

  Widget? _buildFilterChipsRow() {
    final chips = <Widget>[];
    if (_typeFilter != null) {
      chips.add(_filterChip('Loại hàng', () => _openMobileFilters(
          Provider.of<PermissionProvider>(context, listen: false))));
    } else {
      chips.add(_filterChip('Tất cả loại hàng', () => _openMobileFilters(
          Provider.of<PermissionProvider>(context, listen: false))));
    }
    chips.add(_filterChip('Giá bán', _showSortSheet));
    if (chips.isEmpty) return null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: chips),
    );
  }

  Widget _filterChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  void _focusSearch() {
    // Mở dialog tìm nhanh
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tìm hàng hoá'),
        content: TextField(
          controller: _searchCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Mã, tên hàng…'),
          onSubmitted: (_) {
            Navigator.pop(ctx);
            _reloadProducts();
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _reloadProducts();
            },
            child: const Text('Tìm'),
          ),
        ],
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Giá bán'),
              trailing: _sortBy == PosProductSortBy.price
                  ? Icon(Icons.check, color: PosTheme.kiotBlue)
                  : null,
              onTap: () async {
                setState(() => _sortBy = PosProductSortBy.price);
                Navigator.pop(ctx);
                await _reloadProducts();
              },
            ),
            ListTile(
              title: const Text('Tên hàng'),
              trailing: _sortBy == PosProductSortBy.name
                  ? Icon(Icons.check, color: PosTheme.kiotBlue)
                  : null,
              onTap: () async {
                setState(() => _sortBy = PosProductSortBy.name);
                Navigator.pop(ctx);
                await _reloadProducts();
              },
            ),
            ListTile(
              title: const Text('Tồn kho'),
              trailing: _sortBy == PosProductSortBy.stock
                  ? Icon(Icons.check, color: PosTheme.kiotBlue)
                  : null,
              onTap: () async {
                setState(() => _sortBy = PosProductSortBy.stock);
                Navigator.pop(ctx);
                await _reloadProducts();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMobileMoreMenu(PermissionProvider perm) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (perm.canCreate('PosProducts'))
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Tạo hàng hoá'),
                onTap: () {
                  Navigator.pop(ctx);
                  _onCreateType('goods');
                },
              ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Quét mã vạch'),
              onTap: () {
                Navigator.pop(ctx);
                _scanSearch();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Làm mới'),
              onTap: () {
                Navigator.pop(ctx);
                _loadAll();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileStockSummary() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Row(
        children: [
          const Text('Tổng tồn',
              style: TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
          const Spacer(),
          Text(
            _moneyFmt.format(_totalOnHand),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _resetMobileFilters() async {
    setState(() {
      _categoryFilter = null;
      _brandFilter = null;
      _locationFilter = null;
      _supplierFilter = null;
      _typeFilter = null;
      _stockFilter = PosStockFilter.all;
      _stockoutFilter = PosStockoutFilter.all;
      _directSaleFilter = null;
      _includeInactive = false;
    });
    await _reloadProducts();
  }

  void _openMobileFilters(PermissionProvider perm) {
    showPosMobileFilterSheet(
      context,
      title: 'Bộ lọc',
      onReset: _resetMobileFilters,
      onApply: () => _reloadProducts(),
      child: PosProductFilterSidebar(
          categories: _categories,
          brands: _brands,
          locations: _locations,
          suppliers: _suppliers,
          categoryId: _categoryFilter,
          brandId: _brandFilter,
          locationId: _locationFilter,
          supplierId: _supplierFilter,
          productType: _typeFilter,
          stockFilter: _stockFilter,
          stockoutFilter: _stockoutFilter,
          directSaleFilter: _directSaleFilter,
          includeInactive: _includeInactive,
          createdTimeFilter: _createdTimeFilter,
          useStockoutCustom: _useStockoutCustom,
          stockoutBefore: _stockoutBefore,
          onCategoryChanged: (v) async {
            setState(() => _categoryFilter = v);
            await _reloadProducts();
          },
          onBrandChanged: (v) async {
            setState(() => _brandFilter = v);
            await _reloadProducts();
          },
          onLocationChanged: (v) async {
            setState(() => _locationFilter = v);
            await _reloadProducts();
          },
          onSupplierChanged: (v) async {
            setState(() => _supplierFilter = v);
            await _reloadProducts();
          },
          onProductTypeChanged: (v) async {
            setState(() => _typeFilter = v);
            await _reloadProducts();
          },
          onStockFilterChanged: (v) async {
            setState(() => _stockFilter = v);
            await _reloadProducts();
          },
          onStockoutFilterChanged: (v) async {
            setState(() => _stockoutFilter = v);
            await _reloadProducts();
          },
          onDirectSaleFilterChanged: (v) async {
            setState(() => _directSaleFilter = v);
            await _reloadProducts();
          },
          onIncludeInactiveChanged: (v) async {
            setState(() => _includeInactive = v);
            await _reloadProducts();
          },
          onCreatedTimeFilterChanged: _onCreatedTimeFilterChanged,
          onStockoutCustomChanged: (v) async {
            setState(() => _useStockoutCustom = v);
            await _reloadProducts();
          },
          onStockoutBeforeChanged: (d) async {
            setState(() => _stockoutBefore = d);
            await _reloadProducts();
          },
          onCreateCategory:
              perm.canCreate('PosProducts') ? _addCategory : null,
          onManageCategory: (perm.canEdit('PosProducts') ||
                  perm.canDelete('PosProducts'))
              ? () => _manageCatalog(PosCatalogKind.category)
              : null,
          onManageSupplier: (perm.canEdit('PosProducts') ||
                  perm.canDelete('PosProducts'))
              ? () => _manageCatalog(PosCatalogKind.supplier)
              : null,
          onManageLocation: (perm.canEdit('PosProducts') ||
                  perm.canDelete('PosProducts'))
              ? () => _manageCatalog(PosCatalogKind.location)
              : null,
          onManageBrand: (perm.canEdit('PosProducts') ||
                  perm.canDelete('PosProducts'))
              ? () => _manageCatalog(PosCatalogKind.brand)
              : null,
        ),
    );
  }

  Widget _buildMobileFilterBar(PermissionProvider perm) {
    final chips = <String>[];
    if (_categoryFilter != null) chips.add('Nhóm');
    if (_typeFilter != null) chips.add('Loại');
    if (_stockFilter != PosStockFilter.all) chips.add('Tồn kho');
    if (_stockoutFilter != PosStockoutFilter.all) chips.add('Hết hàng');
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 6,
        children: [
          ...chips.map((c) => Chip(
                label: Text(c, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              )),
          ActionChip(
            label: const Text('Đổi bộ lọc', style: TextStyle(fontSize: 12)),
            onPressed: () => _openMobileFilters(perm),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(PermissionProvider perm, bool wide) {
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Chưa có hàng hóa',
        description: perm.canCreate('PosProducts')
            ? 'Nhấn «Tạo mới» để thêm hàng hóa, dịch vụ hoặc combo'
            : null,
      );
    }

    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '$_total mặt hàng · Tồn kho: ${_moneyFmt.format(_totalOnHand)}',
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Material(
              color: Colors.white,
              child: PosProductDataTable(
                items: _items,
                moneyFmt: _moneyFmt,
                dateFmt: _dateFmt,
                sortBy: _sortBy,
                sortDesc: _sortDesc,
                visibleColumns: _visibleColumns,
                expandedProductId: _expandedProductId,
                selectedVariantId: _selectedVariantId,
                onSelectVariant: _selectVariant,
                onSort: (col, desc) async {
                  setState(() {
                    _sortBy = col;
                    _sortDesc = desc;
                  });
                  await _reloadProducts();
                },
                onToggleExpand: _toggleExpand,
                onEdit: _openEdit,
                onEditVariant: _openEditVariant,
                onCopy: _copyProduct,
                onDelete: _deleteProduct,
                onPrintLabel: _printLabel,
                onExpansionChanged: () async {
                  final id = _expandedProductId;
                  if (id != null) _variantsByProductId.remove(id);
                  await _loadProducts();
                  if (mounted) {
                    setState(() {});
                    if (id != null) {
                      final p = _items.cast<PosProduct?>().firstWhere(
                            (x) => x?.id == id,
                            orElse: () => null,
                          );
                      if (p != null) await _loadVariantsForProduct(p);
                    }
                  }
                },
                onToggleFavorite: _toggleFavorite,
                selectedIds: _selectedIds,
                onToggleSelect: (p, v) => setState(() {
                  if (v) {
                    _selectedIds.add(p.id);
                  } else {
                    _selectedIds.remove(p.id);
                  }
                }),
                onToggleSelectAll: (all) => setState(() {
                  if (all) {
                    _selectedIds.addAll(_items.map((p) => p.id));
                  } else {
                    _selectedIds.clear();
                  }
                }),
                canEdit: perm.canEdit('PosProducts'),
                onQuickPrice:
                    perm.canEdit('PosProducts') ? _quickEditPrice : null,
                onQuickStock:
                    perm.canEdit('PosProducts') ? _quickEditStock : null,
                onQuickVariantPrice: perm.canEdit('PosProducts')
                    ? _quickEditVariantPrice
                    : null,
                onQuickVariantStock: perm.canEdit('PosProducts')
                    ? _quickEditVariantStock
                    : null,
                onDeleteVariant:
                    perm.canEdit('PosProducts') ? _deleteVariant : null,
                variantsByProductId: _variantsByProductId,
                variantsLoadingIds: _variantsLoadingIds,
                unitViewVariantIdByProductId: _unitViewVariantIdByProductId,
                onUnitViewChanged: _setUnitView,
                onAddSameType: perm.canEdit('PosProducts')
                    ? _addSameTypeProduct
                    : null,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: Responsive.fabListInsets(
        context,
        base: const EdgeInsets.only(bottom: 8),
        enabled: perm.canCreate('PosProducts'),
      ),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
      itemBuilder: (context, i) => _buildKiotMobileProductRow(_items[i], perm),
    );
  }

  Widget _buildKiotMobileProductRow(PosProduct p, PermissionProvider perm) {
    final variants = _variantsByProductId[p.id] ?? [];
    final unitViews = buildPosProductUnitViews(p, variants);
    final unitViewId = _unitViewVariantIdByProductId[p.id];
    final activeView = resolveUnitView(p, variants, unitViewId);
    final stockUnit = activeView.label.isNotEmpty
        ? activeView.label
        : p.baseUnitName;

    return PosMobileProductRow(
      name: p.name,
      code: activeView.displayCode,
      priceText: _moneyFmt.format(activeView.basePrice),
      stockText: p.productType == PosProductType.service
          ? 'Dịch vụ'
          : 'Tồn: ${_moneyFmt.format(activeView.onHandQty)} $stockUnit',
      image: PosProductImage(
        productId: p.id,
        imageUrl: p.imageUrl,
        size: 48,
        borderRadius: 8,
      ),
      onTap: () => _toggleExpand(p),
      onLongPress: () => _openEdit(p),
    );
  }

  Widget _buildMobileProductCard(PosProduct p, PermissionProvider perm) {
    final expanded = _expandedProductId == p.id;
    final variants = _variantsByProductId[p.id] ?? [];
    final displayCount =
        variants.isNotEmpty ? variants.length : p.variantCount;
    final hasVariants = displayCount > 0;
    final loadingVariants = _variantsLoadingIds.contains(p.id);
    final unitViewId = _unitViewVariantIdByProductId[p.id];
    final unitViews = buildPosProductUnitViews(p, variants);
    final activeView = resolveUnitView(p, variants, unitViewId);
    PosProductVariant? focusVariant;
    if (activeView.variantId != null) {
      focusVariant = variants.cast<PosProductVariant?>().firstWhere(
            (v) => v?.id == activeView.variantId,
            orElse: () => null,
          );
    }

    Future<void> onExpansionChanged() async {
      final id = _expandedProductId;
      if (id != null) _variantsByProductId.remove(id);
      await _loadProducts();
      if (!mounted) return;
      setState(() {});
      if (id != null) {
        final prod = _items.cast<PosProduct?>().firstWhere(
              (x) => x?.id == id,
              orElse: () => null,
            );
        if (prod != null) await _loadVariantsForProduct(prod);
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Checkbox(
              value: _selectedIds.contains(p.id),
              activeColor: PosTheme.kiotBlue,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selectedIds.add(p.id);
                } else {
                  _selectedIds.remove(p.id);
                }
              }),
            ),
            title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasVariants
                      ? '($displayCount) ${activeView.displayCode}'
                      : activeView.displayCode,
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    PosProductTypeBadge(type: p.productType, compact: true),
                    const SizedBox(width: 6),
                    PosSellingStatusBadge(
                      isActive: p.isActive,
                      isDirectSale: p.isDirectSale,
                    ),
                  ],
                ),
                if (p.productType == PosProductType.goods && unitViews.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: PosUnitChipSelector(
                      views: unitViews,
                      selectedVariantId: unitViewId,
                      compact: true,
                      onChanged: (vid) => _setUnitView(p, vid),
                    ),
                  ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                InkWell(
                  onTap: perm.canEdit('PosProducts')
                      ? () {
                          if (focusVariant != null) {
                            _quickEditVariantPrice(p, focusVariant);
                          } else {
                            _quickEditPrice(p);
                          }
                        }
                      : null,
                  child: Text(
                    _moneyFmt.format(activeView.basePrice),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (p.productType != PosProductType.service)
                  InkWell(
                    onTap: perm.canEdit('PosProducts')
                        ? () {
                            if (focusVariant != null) {
                              _quickEditVariantStock(p, focusVariant);
                            } else {
                              _quickEditStock(p);
                            }
                          }
                        : null,
                    child: Text(
                      'Tồn: ${_moneyFmt.format(activeView.onHandQty)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: activeView.onHandQty <= 0
                            ? Colors.red
                            : Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
            onTap: () => _toggleExpand(p),
            onLongPress: () => _openEdit(p),
          ),
          if (expanded) ...[
            if (hasVariants && loadingVariants)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PosTheme.kiotBlue,
                    ),
                  ),
                ),
              )
            else
              PosProductExpansionPanel(
                product: p,
                focusVariant: focusVariant,
                moneyFmt: _moneyFmt,
                dateFmt: _dateFmt,
                canEdit: perm.canEdit('PosProducts'),
                canCreate: perm.canCreate('PosProducts'),
                canDelete: perm.canDelete('PosProducts'),
                onEdit: () {
                  if (focusVariant != null) {
                    _openEditVariant(p, focusVariant);
                  } else {
                    _openEdit(p);
                  }
                },
                onCopy: () => _copyProduct(p),
                onDelete: () => _deleteProduct(p),
                onPrintLabel: () => _printLabel(p),
                onChanged: onExpansionChanged,
              ),
            if (perm.canEdit('PosProducts') && hasVariants)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _addSameTypeProduct(p),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Thêm hàng cùng loại'),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: PosTheme.border)),
      ),
      child: Row(
        children: [
          Text(
            'Tổng: $_total · Tồn: ${_moneyFmt.format(_totalOnHand)}',
            style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
          ),
          const Spacer(),
          if (_totalPages > 1) ...[
            IconButton(
              onPressed: _page > 1
                  ? () async {
                      await _loadProducts(page: _page - 1);
                      setState(() {});
                    }
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Trang $_page / $_totalPages'),
            IconButton(
              onPressed: _page < _totalPages
                  ? () async {
                      await _loadProducts(page: _page + 1);
                      setState(() {});
                    }
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ],
      ),
    );
  }
}
