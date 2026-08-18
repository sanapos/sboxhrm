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
import '../widgets/pos/pos_product_type_filter_bar.dart';
import '../widgets/pos/pos_sample_catalog_picker.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/pos/pos_product_expansion_panel.dart';
import '../widgets/pos/pos_product_unit_view.dart';
import '../widgets/pos/pos_unit_chip_selector.dart';
import '../utils/pos_product_type_picker.dart';
import '../utils/pos_purchase_product_lookup.dart';
import '../widgets/pos/pos_hub_scope.dart';
import '../widgets/pos/pos_product_image.dart';
import '../utils/navigation_notifier.dart';
import 'pos/pos_product_detail_screen.dart';
import 'pos/pos_product_editor_page.dart';
import 'pos/pos_topping_groups_screen.dart';
import '../widgets/pos_barcode_scanner.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

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
  bool _loadingMore = false;
  final _listScroll = ScrollController();

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
    _listScroll.addListener(_onProductListScroll);
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
    _listScroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  PosProductType? get _typeFilterParam => _typeFilter;

  List<PosProduct>? _localCatalog;

  bool get _canFilterLocally =>
      _localCatalog != null &&
      _searchCtrl.text.trim().isEmpty &&
      !_includeInactive &&
      _stockoutFilter == PosStockoutFilter.all &&
      !_useStockoutCustom;

  void _captureLocalCatalogIfComplete() {
    if (_searchCtrl.text.trim().isNotEmpty) return;
    if (_typeFilter != null) return;
    if (_categoryFilter != null ||
        _brandFilter != null ||
        _locationFilter != null ||
        _supplierFilter != null) return;
    if (_stockFilter != PosStockFilter.all) return;
    if (_stockoutFilter != PosStockoutFilter.all || _useStockoutCustom) return;
    if (_directSaleFilter != null) return;
    if (_createdTimeFilter.preset != PosKiotTimePreset.allTime ||
        _createdTimeFilter.isCustom) return;
    if (_total > _pageSize) {
      _localCatalog = null;
      return;
    }
    _localCatalog = List<PosProduct>.of(_items);
  }

  List<PosProduct> _sortLocal(List<PosProduct> list) {
    int dir(int c) => _sortDesc ? -c : c;
    list.sort((a, b) {
      final primary = switch (_sortBy) {
        PosProductSortBy.code =>
          dir(a.productCode.toLowerCase().compareTo(b.productCode.toLowerCase())),
        PosProductSortBy.price => dir(a.basePrice.compareTo(b.basePrice)),
        PosProductSortBy.stock => dir(a.onHandQty.compareTo(b.onHandQty)),
        PosProductSortBy.name =>
          dir(a.name.toLowerCase().compareTo(b.name.toLowerCase())),
        _ => dir((a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))),
      };
      if (primary != 0) return primary;
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      return 0;
    });
    return list;
  }

  void _applyLocalFilters() {
    var list = List<PosProduct>.of(_localCatalog!);
    if (_typeFilter != null) {
      list = list.where((p) => p.productType == _typeFilter).toList();
    }
    if (_categoryFilter != null) {
      list = list.where((p) => p.categoryId == _categoryFilter).toList();
    }
    if (_brandFilter != null) {
      list = list.where((p) => p.brandId == _brandFilter).toList();
    }
    if (_locationFilter != null) {
      list = list.where((p) => p.storageLocationId == _locationFilter).toList();
    }
    if (_supplierFilter != null) {
      list = list.where((p) => p.supplierId == _supplierFilter).toList();
    }
    if (_directSaleFilter != null) {
      list = list.where((p) => p.isDirectSale == _directSaleFilter).toList();
    }
    if (!_includeInactive) {
      list = list.where((p) => p.isActive).toList();
    }
    final from = _createdTimeFilter.from;
    final to = _createdTimeFilter.to;
    if (from != null) {
      list = list
          .where((p) => p.createdAt != null && !p.createdAt!.isBefore(from))
          .toList();
    }
    if (to != null) {
      list = list
          .where((p) => p.createdAt != null && !p.createdAt!.isAfter(to))
          .toList();
    }
    switch (_stockFilter) {
      case PosStockFilter.outOfStock:
        list = list
            .where((p) => p.productType.tracksInventory && p.onHandQty <= 0)
            .toList();
      case PosStockFilter.belowMin:
        list = list
            .where((p) =>
                p.productType.tracksInventory &&
                p.minStockQty > 0 &&
                p.onHandQty > 0 &&
                p.onHandQty <= p.minStockQty)
            .toList();
      case PosStockFilter.aboveMax:
        list = list
            .where((p) =>
                p.productType.tracksInventory &&
                p.maxStockQty > 0 &&
                p.onHandQty > p.maxStockQty)
            .toList();
      case PosStockFilter.all:
        break;
    }
    _items = _sortLocal(list);
    _total = _items.length;
    _page = 1;
    _totalPages = 1;
    _totalOnHand = _items.fold(0.0, (a, b) => a + b.onHandQty);
  }

  Future<void> _reloadProducts({bool forceNetwork = false}) async {
    if (!forceNetwork && _canFilterLocally) {
      _applyLocalFilters();
      if (mounted) setState(() {});
      return;
    }
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

  Future<void> _loadProducts({int? page, bool append = false}) async {
    if (page != null) _page = page;
    if (append) {
      if (_loadingMore || _page > _totalPages) return;
      _loadingMore = true;
    }
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
      _localCatalog = null;
      final parsed = list
          .map((e) => PosProduct.fromJson(e as Map<String, dynamic>))
          .toList();
      if (_useStockoutCustom && _stockoutBefore != null) {
        final before = _stockoutBefore!;
        parsed.removeWhere((p) =>
            p.estimatedStockoutDate == null ||
            p.estimatedStockoutDate!.isAfter(before));
      }
      if (append) {
        final seen = {for (final p in _items) p.id};
        for (final p in parsed) {
          if (seen.add(p.id)) _items.add(p);
        }
      } else {
        _items = parsed;
      }
      _total = (data['total'] as num?)?.toInt() ?? _items.length;
      _totalPages = (_total / _pageSize).ceil().clamp(1, 9999);
      final summary = data['summary'] as Map<String, dynamic>?;
      _totalOnHand = (summary?['totalOnHandQty'] as num?)?.toDouble() ??
          _items.fold(0.0, (a, b) => a + b.onHandQty);
      _captureLocalCatalogIfComplete();
      _prefetchVariantsForPage();
    } else if (mounted) {
      NotificationOverlayManager().showError(
        title: 'Không tải được hàng hóa',
        message: res['message']?.toString() ?? 'Vui lòng thử lại sau',
      );
    }
    _loadingMore = false;
  }

  void _onProductListScroll() {
    if (!_listScroll.hasClients) return;
    final pos = _listScroll.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 280) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_loading || _loadingMore) return;
    if (_page >= _totalPages) return;
    await _loadProducts(page: _page + 1, append: true);
    if (mounted) setState(() {});
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
        message: tr('Bạn không có quyền sửa hàng hóa'),
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
        message: tr('Bạn không có quyền thêm hàng hóa'),
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
        title: Text(tr('Xóa hàng hóa')),
        content: Text(tr('Xóa «${p.name}»?')),
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
        message: tr('Đã xóa hàng hóa'),
      );
      ScreenRefreshNotifier.refreshPosAfterStockChange();
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
        message: tr('Bạn không có quyền sửa hàng hóa'),
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
        text: tr(NumberFormat('#,###', 'vi_VN').format(p.basePrice.round())));
    final val = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sửa giá bán — ${p.name}')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [ThousandSeparatorFormatter()],
          decoration: PosTheme.inputDecoration(label: 'Giá bán'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, parseFormattedNumber(ctrl.text)?.toDouble()),
            style: PosTheme.filledButtonStyle,
            child: Text(tr('Lưu')),
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
        TextEditingController(text: tr(p.onHandQty.toStringAsFixed(0)));
    final val = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sửa tồn kho — ${p.name}')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: PosTheme.inputDecoration(label: 'Tồn kho'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, double.tryParse(ctrl.text.replaceAll(',', ''))),
            style: PosTheme.filledButtonStyle,
            child: Text(tr('Lưu')),
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
      ScreenRefreshNotifier.refreshPosAfterStockChange();
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
        text: tr(NumberFormat('#,###', 'vi_VN').format(v.basePrice.round())));
    final val = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sửa giá bán — ${v.name}')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [ThousandSeparatorFormatter()],
          decoration: PosTheme.inputDecoration(label: 'Giá bán'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, parseFormattedNumber(ctrl.text)?.toDouble()),
            style: PosTheme.filledButtonStyle,
            child: Text(tr('Lưu')),
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
    final ctrl = TextEditingController(text: tr(v.onHandQty.toStringAsFixed(0)));
    final val = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sửa tồn kho — ${v.name}')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: PosTheme.inputDecoration(label: 'Tồn kho'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, double.tryParse(ctrl.text.replaceAll(',', ''))),
            style: PosTheme.filledButtonStyle,
            child: Text(tr('Lưu')),
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
      ScreenRefreshNotifier.refreshPosAfterStockChange();
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
        title: Text(tr('Xóa hàng cùng loại')),
        content: Text(tr('Xóa «${v.name}» (${v.skuCode})?')),
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
        message: tr('Đã xóa hàng cùng loại'),
      );
      ScreenRefreshNotifier.refreshPosAfterStockChange();
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
        productType: _typeFilter,
      );
      if (res['isSuccess'] == true) {
        final bytes = Uint8List.fromList(List<int>.from(res['data']));
        await file_saver.saveFileBytes(
          bytes,
          'hang_hoa_pos_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        NotificationOverlayManager().showSuccess(
            title: 'Xuất file', message: tr('Đã xuất Excel hàng hóa'));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importExcel(PermissionProvider perm,
      {PosProductType? forceProductType}) async {
    if (!perm.canCreate('PosProducts')) return;
    final fileResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (fileResult == null || fileResult.files.isEmpty) return;
    final file = fileResult.files.first;
    if (file.bytes == null) return;
    final res = await _api.importPosProductsExcelFile(
      file.bytes!,
      file.name,
      forceProductType: forceProductType,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'] as Map<String, dynamic>?;
      NotificationOverlayManager().showSuccess(
        title: 'Import thành công',
        message: 'Tạo mới: ${data?['created'] ?? 0}, Cập nhật: ${data?['updated'] ?? 0}',
      );
      await _loadAll();
      setState(() {});
    } else {
      NotificationOverlayManager().showError(
        title: 'Import lỗi',
        message: tr((res['message'] ?? 'Không nhập được file').toString()),
      );
    }
  }

  Future<void> _importBarcodeCatalog(PermissionProvider perm) async {
    if (!perm.canCreate('PosProducts')) return;
    final fileResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (fileResult == null || fileResult.files.isEmpty) return;
    final file = fileResult.files.first;
    if (file.bytes == null) return;
    final res = await _api.importPosBarcodeCatalogExcel(file.bytes!, file.name);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'] as Map<String, dynamic>?;
      NotificationOverlayManager().showSuccess(
        title: 'Đã nhập từ điển mã vạch',
        message: tr(
            'Thêm ${data?['created'] ?? 0}, cập nhật ${data?['updated'] ?? 0}. Quét mã chưa có hàng → gợi ý tên, chỉ nhập giá.'),
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Import từ điển lỗi',
        message: tr((res['message'] ?? 'Cần cột Mã vạch và Tên hàng').toString()),
      );
    }
  }

  Future<void> _downloadProductTemplate(PosProductType type) async {
    final res = await _api.exportPosProductsExcelTemplate(type);
    if (res['isSuccess'] != true || res['data'] == null) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: tr((res['message'] ?? 'Không tải được mẫu').toString()),
      );
      return;
    }
    final bytes = Uint8List.fromList(List<int>.from(res['data']));
    final slug = switch (type) {
      PosProductType.service => 'dich_vu',
      PosProductType.combo => 'combo',
      PosProductType.material => 'nvl',
      PosProductType.topping => 'topping',
      PosProductType.goods => 'hang_hoa',
    };
    await file_saver.saveFileBytes(
      bytes,
      'mau_${slug}_pos.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    NotificationOverlayManager().showSuccess(
      title: 'Mẫu Excel',
      message: tr('Đã tải mẫu ${posProductTypeLabel(type)}'),
    );
  }

  Future<void> _openTypeHub(
    PermissionProvider perm, {
    required String title,
    bool showCreate = true,
    bool showImport = true,
    bool showTemplate = true,
  }) async {
    final pick = await showPosProductTypeHub(
      context,
      title: title,
      showCreate: showCreate,
      showImport: showImport && perm.canCreate('PosProducts'),
      showTemplate: showTemplate && perm.canCreate('PosProducts'),
    );
    if (pick == null || !mounted) return;
    switch (pick.action) {
      case PosProductTypePickAction.create:
        await _openCreate(pick.type);
      case PosProductTypePickAction.importExcel:
        await _importExcel(perm, forceProductType: pick.type);
      case PosProductTypePickAction.downloadTemplate:
        await _downloadProductTemplate(pick.type);
    }
  }

  Future<void> _downloadBarcodeCatalogTemplate() async {
    final res = await _api.exportPosBarcodeCatalogTemplate();
    if (res['isSuccess'] != true || res['data'] == null) return;
    final bytes = Uint8List.fromList(List<int>.from(res['data']));
    await file_saver.saveFileBytes(
      bytes,
      'Mau_tu_dien_ma_vach.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    NotificationOverlayManager().showSuccess(
      title: 'Mẫu Excel',
      message: tr('Đã tải mẫu: Mã vạch + Tên hàng (+ ĐVT, nhóm, hãng)'),
    );
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
    if (!mounted) return;
    if (_items.isEmpty) {
      final pick = await lookupOrPickPosProduct(context, _api, code);
      if (pick != null && mounted) await _loadProducts(page: 1);
    }
    if (mounted) setState(() {});
  }

  Future<void> _addCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Thêm nhóm hàng')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: PosTheme.inputDecoration(label: 'Tên nhóm'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: PosTheme.filledButtonStyle,
            child: Text(tr('Lưu')),
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
        message: tr('Bạn không có quyền quản lý danh mục'),
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
    final t = switch (type) {
      'goods' => PosProductType.goods,
      'service' => PosProductType.service,
      'combo' => PosProductType.combo,
      'material' => PosProductType.material,
      'topping' => PosProductType.topping,
      _ => null,
    };
    if (t != null) _openCreate(t);
  }

  void _showColumnPicker() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr('Hiển thị cột')),
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
                          title: Text(tr(c.label), style: const TextStyle(fontSize: 13)),
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
              child: Text(tr('Mặc định')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
              child: Text(tr('Xong')),
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
          ? PosMobileFab(
              onPressed: () => _openTypeHub(
                perm,
                title: 'Tạo hoặc nhập theo loại',
              ),
            )
          : null,
      body: posMobileSafeBody(
        context,
        Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!inHub) const PosModuleToolbar(activeModule: 'PosProducts'),
          if (mobile)
            PosMobileKiotHeader(
              title: 'Hàng hoá',
              onSearch: () => _focusSearch(),
              onFilter: inHub ? null : () => _openMobileFilters(perm),
              onSort: inHub ? null : _showSortSheet,
              onMore: () => _showMobileMoreMenu(perm),
              onRefresh: inHub ? null : () => _reloadProducts(forceNetwork: true),
              activeFilterCount: _activeMobileFilterCount,
              filterChips: null,
            )
          else
            _buildMainToolbar(perm, wide),
          if (_selectedIds.isNotEmpty) _buildSelectionBar(),
          PosProductTypeFilterBar(
            value: _typeFilter,
            onChanged: (v) async {
              setState(() => _typeFilter = v);
              await _reloadProducts();
            },
          ),
          const Divider(height: 1, color: PosTheme.border),
          if (mobile && !inHub) _buildMobileStockSummary(),
          Expanded(
            child: _loading
                ? LoadingWidget(message: tr('Đang tải hàng hóa…'))
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
                        tooltip: tr('Bộ lọc'),
                        onPressed: () => _openMobileFilters(perm),
                        icon: const Icon(Icons.filter_list),
                      ),
                      Expanded(
                        child: Text(tr('Hàng hóa'),
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
                          } else if (v == 'import_typed' &&
                              perm.canCreate('PosProducts')) {
                            _openTypeHub(
                              perm,
                              title: 'Nhập Excel theo loại',
                              showCreate: false,
                            );
                          } else if (v == 'sample_menu' &&
                              perm.canCreate('PosProducts')) {
                            // ignore: discarded_futures
                            () async {
                              final created = await showPosSampleCatalogPicker(
                                context,
                                _api,
                                categories: _categories,
                              );
                              if (created != null && mounted) {
                                await _reloadProducts(forceNetwork: true);
                              }
                            }();
                          } else if (v == 'create_hub' &&
                              perm.canCreate('PosProducts')) {
                            _openTypeHub(perm, title: 'Tạo hoặc nhập theo loại');
                          } else if (v == 'import_catalog' &&
                              perm.canCreate('PosProducts')) {
                            _importBarcodeCatalog(perm);
                          } else if (v == 'catalog_template' &&
                              perm.canCreate('PosProducts')) {
                            _downloadBarcodeCatalogTemplate();
                          } else if (v == 'topping_groups') {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PosToppingGroupsScreen(),
                              ),
                            );
                          } else if (v.startsWith('create_') &&
                              perm.canCreate('PosProducts')) {
                            _onCreateType(v.replaceFirst('create_', ''));
                          }
                        },
                        itemBuilder: (_) => [
                          if (perm.canCreate('PosProducts')) ...[
                            PopupMenuItem(
                                value: 'sample_menu',
                                child: Text(tr('Thêm từ menu / catalog mẫu'))),
                            PopupMenuItem(
                                value: 'create_hub',
                                child: Text(tr('Tạo / nhập theo loại'))),
                          ],
                          PopupMenuItem(
                              value: 'topping_groups',
                              child: Text(tr('Nhóm topping'))),
                          PopupMenuItem(
                              value: 'columns', child: Text(tr('Hiển thị cột'))),
                          PopupMenuItem(
                              value: 'scan', child: Text(tr('Quét mã vạch'))),
                          if (perm.canExport('PosProducts'))
                            PopupMenuItem(
                                value: 'export', child: Text(tr('Xuất file'))),
                          if (perm.canCreate('PosProducts')) ...[
                            PopupMenuItem(
                                value: 'import_typed',
                                child: Text(tr('Nhập / tải mẫu theo loại'))),
                            PopupMenuItem(
                                value: 'import',
                                child: Text(tr('Import hỗn hợp (cột Loại hàng)'))),
                            PopupMenuItem(
                                value: 'import_catalog',
                                child: Text(tr('Import từ điển mã vạch'))),
                            PopupMenuItem(
                                value: 'catalog_template',
                                child: Text(tr('Tải mẫu từ điển mã vạch'))),
                          ],
                          PopupMenuItem(
                              value: 'refresh', child: Text(tr('Làm mới'))),
                        ],
                        icon: const Icon(Icons.more_vert),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: tr('Theo mã, tên hàng'),
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: PosBarcodeScanIcon(
                        controller: _searchCtrl,
                        iconSize: 20,
                        onScanned: (_) {
                          // ignore: discarded_futures
                          _reloadProducts();
                        },
                      ),
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
                      onPressed: () => _openTypeHub(
                        perm,
                        title: 'Tạo hoặc nhập theo loại',
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      style: FilledButton.styleFrom(
                        backgroundColor: PosTheme.kiotBlue,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      label: Text(tr('Tạo mới')),
                    ),
                  ],
                ],
              )
            : Row(
          children: [
            if (!wide)
              IconButton(
                tooltip: tr('Bộ lọc'),
                onPressed: () => _openMobileFilters(perm),
                icon: const Icon(Icons.filter_list),
              ),
            Text(tr('Hàng hóa'),
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
                    hintText: tr('Theo mã, tên hàng'),
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
                child: FilledButton.icon(
                  onPressed: () => _openTypeHub(
                    perm,
                    title: 'Tạo hoặc nhập theo loại',
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  style: FilledButton.styleFrom(
                    backgroundColor: PosTheme.kiotBlue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  label: Text(tr('Tạo mới')),
                ),
              ),
            if (perm.canCreate('PosProducts'))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final created = await showPosSampleCatalogPicker(
                      context,
                      _api,
                      categories: _categories,
                    );
                    if (created != null && mounted) {
                      await _reloadProducts(forceNetwork: true);
                    }
                  },
                  icon: const Icon(Icons.restaurant_menu, size: 18),
                  label: Text(tr('Catalog mẫu')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: PosTheme.textPrimary,
                    side: const BorderSide(color: PosTheme.border),
                  ),
                ),
              ),
            if (perm.canCreate('PosProducts'))
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'import') _importExcel(perm);
                  if (v == 'import_typed') {
                    _openTypeHub(
                      perm,
                      title: 'Nhập Excel theo loại',
                      showCreate: false,
                    );
                  }
                  if (v == 'import_catalog') _importBarcodeCatalog(perm);
                  if (v == 'catalog_template') {
                    _downloadBarcodeCatalogTemplate();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'import_typed',
                      child: Text(tr('Nhập / tải mẫu theo loại'))),
                  PopupMenuItem(
                      value: 'import',
                      child: Text(tr('Import hỗn hợp (cột Loại hàng)'))),
                  PopupMenuItem(
                      value: 'import_catalog',
                      child: Text(tr('Import từ điển mã vạch'))),
                  PopupMenuItem(
                      value: 'catalog_template',
                      child: Text(tr('Tải mẫu từ điển mã vạch'))),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: PosTheme.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.upload_file, size: 18),
                      const SizedBox(width: 6),
                      Text(tr('Import Excel')),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              ),
            if (perm.canExport('PosProducts')) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _isExporting ? null : () => _exportExcel(perm),
                icon: const Icon(Icons.download, size: 18),
                label: Text(tr(_isExporting ? 'Đang xuất…' : 'Xuất file')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PosTheme.textPrimary,
                  side: const BorderSide(color: PosTheme.border),
                ),
              ),
            ],
            IconButton(
              tooltip: tr('Hiển thị cột'),
              onPressed: _showColumnPicker,
              icon: const Icon(Icons.view_column_outlined),
            ),
            IconButton(
              tooltip: tr('Quét mã vạch'),
              onPressed: _scanSearch,
              icon: const Icon(Icons.qr_code_scanner),
            ),
            IconButton(
              tooltip: tr('Làm mới'),
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
            Text(tr('Đã chọn ${_selectedIds.length}'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _selectedIds.clear()),
              child: Text(tr('Bỏ chọn')),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _batchPrintLabels,
              icon: const Icon(Icons.qr_code, size: 18),
              label: Text(tr('In tem mã vạch')),
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
    if (_stockFilter != PosStockFilter.all) n++;
    if (_stockoutFilter != PosStockoutFilter.all) n++;
    if (_brandFilter != null) n++;
    return n;
  }

  void _focusSearch() {
    // Mở dialog tìm nhanh
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Tìm hàng hoá')),
        content: TextField(
          controller: _searchCtrl,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('Mã, tên hàng…')),
          onSubmitted: (_) {
            Navigator.pop(ctx);
            _reloadProducts();
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _reloadProducts();
            },
            child: Text(tr('Tìm')),
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
              title: Text(tr('Giá bán')),
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
              title: Text(tr('Tên hàng')),
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
              title: Text(tr('Tồn kho')),
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
    final inHub = PosHubScope.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (inHub) ...[
              ListTile(
                leading: const Icon(Icons.filter_list),
                title: Text(tr('${tr('Bộ lọc')}${_activeMobileFilterCount > 0 ? ' ($_activeMobileFilterCount)' : ''}')),
                onTap: () {
                  Navigator.pop(ctx);
                  _openMobileFilters(perm);
                },
              ),
              ListTile(
                leading: const Icon(Icons.import_export),
                title: Text(tr('Sắp xếp')),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSortSheet();
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(tr('Làm mới')),
                onTap: () {
                  Navigator.pop(ctx);
                  _reloadProducts();
                },
              ),
              const Divider(height: 1),
            ],
            if (perm.canCreate('PosProducts')) ...[
              ListTile(
                leading: const Icon(Icons.restaurant_menu),
                title: Text(tr('Thêm từ menu / catalog mẫu')),
                onTap: () {
                  Navigator.pop(ctx);
                  // ignore: discarded_futures
                  () async {
                    final created = await showPosSampleCatalogPicker(
                      context,
                      _api,
                      categories: _categories,
                    );
                    if (created != null && mounted) {
                      await _reloadProducts(forceNetwork: true);
                    }
                  }();
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(tr('Tạo / nhập theo loại')),
                onTap: () {
                  Navigator.pop(ctx);
                  _openTypeHub(perm, title: 'Tạo hoặc nhập theo loại');
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(tr('Quét mã vạch')),
              onTap: () {
                Navigator.pop(ctx);
                _scanSearch();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(tr('Làm mới')),
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
          Text(tr('Tổng tồn'),
              style: TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
          const Spacer(),
          Text(
            tr(_moneyFmt.format(_totalOnHand)),
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

  Widget _buildContent(PermissionProvider perm, bool wide) {
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Chưa có hàng hóa',
        description: perm.canCreate('PosProducts')
            ? 'Nhấn «Tạo mới» để thêm hàng hóa, dịch vụ, combo, NVL hoặc topping'
            : null,
      );
    }

    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(tr('$_total mặt hàng · Tồn kho: ${_moneyFmt.format(_totalOnHand)}'),
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
      controller: _listScroll,
      padding: Responsive.fabListInsets(
        context,
        base: const EdgeInsets.only(bottom: 8),
        enabled: perm.canCreate('PosProducts'),
      ),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _buildKiotMobileProductRow(_items[i], perm);
      },
    );
  }

  Future<void> _showMobileProductActions(PosProduct p, PermissionProvider perm) async {
    final variants = _variantsByProductId[p.id] ?? [];
    final unitViewId = _unitViewVariantIdByProductId[p.id];
    final activeView = resolveUnitView(p, variants, unitViewId);
    final canEdit = perm.canEdit('PosProducts');
    final canCreate = perm.canCreate('PosProducts');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.42,
          minChildSize: 0.28,
          maxChildSize: 0.72,
          builder: (_, scrollCtrl) => ListView(
            controller: scrollCtrl,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    PosProductImage(
                      productId: p.id,
                      imageUrl: p.imageUrl,
                      size: 44,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(p.name),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(tr('${activeView.displayCode} · ${_moneyFmt.format(activeView.basePrice)} đ'),
                            style: const TextStyle(
                              fontSize: 13,
                              color: PosTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(tr('Xem chi tiết')),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PosProductDetailScreen(product: p),
                    ),
                  );
                },
              ),
              if (canEdit)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(tr('Sửa hàng hóa')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openEdit(p);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(tr('In nhãn mã vạch')),
                onTap: () {
                  Navigator.pop(ctx);
                  _printLabel(p);
                },
              ),
              if (canCreate || canEdit)
                ListTile(
                  leading: const Icon(Icons.more_horiz),
                  title: Text(tr('Thao tác khác')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMobileProductMoreActions(p, perm);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMobileProductMoreActions(
      PosProduct p, PermissionProvider perm) async {
    final canEdit = perm.canEdit('PosProducts');
    final canCreate = perm.canCreate('PosProducts');
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canCreate)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text(tr('Sao chép hàng hóa')),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyProduct(p);
                },
              ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(tr('Xóa hàng hóa'), style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteProduct(p);
                },
              ),
          ],
        ),
      ),
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
          : p.productType == PosProductType.combo
              ? 'Có thể bán: ${_moneyFmt.format(p.sellableQty ?? activeView.onHandQty)}'
              : p.productType == PosProductType.material
                  ? 'NVL · Tồn: ${_moneyFmt.format(activeView.onHandQty)} $stockUnit'
                  : p.productType == PosProductType.topping
                      ? 'Topping · Tồn: ${_moneyFmt.format(activeView.onHandQty)} $stockUnit'
                      : 'Tồn: ${_moneyFmt.format(activeView.onHandQty)} $stockUnit',
      typeBadge: PosProductTypeBadge(type: p.productType, compact: true),
      image: PosProductImage(
        productId: p.id,
        imageUrl: p.imageUrl,
        size: 48,
        borderRadius: 8,
      ),
      onTap: () => _showMobileProductActions(p, perm),
      onLongPress: perm.canEdit('PosProducts') ? () => _openEdit(p) : null,
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
            title: Text(tr(p.name), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(hasVariants
                      ? '($displayCount) ${activeView.displayCode}'
                      : activeView.displayCode),
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
                    tr(_moneyFmt.format(activeView.basePrice)),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (p.productType == PosProductType.service)
                  Text(tr('Không trừ kho'),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  )
                else if (p.productType == PosProductType.combo)
                  Text(
                    tr('Có thể bán: ${_moneyFmt.format(p.sellableQty ?? activeView.onHandQty)}'),
                    style: TextStyle(
                      fontSize: 11,
                      color: (p.sellableQty ?? activeView.onHandQty) <= 0
                          ? Colors.red
                          : Colors.grey,
                    ),
                  )
                else
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
                    child: Text(tr('Tồn: ${_moneyFmt.format(activeView.onHandQty)}'),
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
                    label: Text(tr('Thêm hàng cùng loại')),
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
          Text(tr('Tổng: $_total · Tồn: ${_moneyFmt.format(_totalOnHand)}'),
            style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
          ),
          const Spacer(),
          if (_totalPages > 1 && !posUseMobileList(context)) ...[
            IconButton(
              onPressed: _page > 1
                  ? () async {
                      await _loadProducts(page: _page - 1);
                      setState(() {});
                    }
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text(tr('Trang $_page / $_totalPages')),
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
