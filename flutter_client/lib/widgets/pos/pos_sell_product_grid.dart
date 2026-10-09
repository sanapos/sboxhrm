import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../services/pos_product_image_cache.dart';
import '../../services/pos_sell_catalog_cache.dart';
import '../../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../../utils/pos_category_tree.dart';
import '../../utils/pos_combo_stock.dart';
import '../../utils/pos_price_list_resolver.dart';
import '../../utils/pos_purchase_product_lookup.dart';
import '../../utils/pos_owner_password_gate.dart';
import '../../utils/pos_qty_rules.dart';
import '../../utils/pos_sell_stock_patch.dart';
import '../../utils/pos_sell_unit_views.dart';
import '../../utils/vn_search.dart';
import '../../utils/pos_floor_realtime.dart';
import '../../services/signalr_service.dart';
import 'pos_catalog_sort_sheet.dart';
import 'pos_form_keyboard.dart';
import 'pos_h_scroll_chip_row.dart';
import 'pos_mobile_widgets.dart';
import 'pos_qty_area_dialog.dart';
import '../pos_barcode_scanner.dart';
import 'pos_product_image.dart';
import 'pos_product_unit_view.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
const _blue = PosTheme.kiotBlue;

/// Lưới hàng hóa bán trực tiếp — chế độ Bán thường (nhóm trái + lưới phải).
class PosSellProductGrid extends StatefulWidget {
  const PosSellProductGrid({
    super.key,
    required this.api,
    required this.onPick,
    this.onDecrement,
    this.onSetQty,
    this.storeId,
    this.pageSize = 24,
    this.sellListLayout = false,
    this.cartQtyByProductId = const {},
    this.priceOverrides = const {},
    this.allowNegativeStock = false,
    this.stockWarnOnly = false,
  });

  final ApiService api;
  final ValueChanged<PosPurchaseLookupPick> onPick;
  /// Giảm 1 SP trong giỏ (màn chọn hàng hóa — nút −).
  final ValueChanged<PosProduct>? onDecrement;
  /// Đặt SL nháp (chạm vào số lượng trên hàng đã chọn).
  final void Function(PosProduct product, double qty, {String? areaNote})?
      onSetQty;
  /// Store hiện tại — dùng key cache catalog local.
  final String? storeId;
  final int pageSize;
  /// Mobile bán hàng: danh sách dọc kiểu KiotViet (không lưới).
  final bool sellListLayout;
  /// Số lượng đã chọn trong giỏ (theo productId) — dùng highlight + sắp xếp.
  final Map<String, double> cartQtyByProductId;
  /// Giá theo bảng giá đang chọn (khóa từ posPriceListItemKey).
  final Map<String, double> priceOverrides;
  /// Thiết lập ngành: cho phép bán khi hết hàng / tồn âm.
  final bool allowNegativeStock;

  /// Báo giá: hàng hết / tạm khóa chỉ cảnh báo, vẫn cho thêm (không trừ kho).
  final bool stockWarnOnly;

  @override
  State<PosSellProductGrid> createState() => PosSellProductGridState();
}

class PosSellProductGridState extends State<PosSellProductGrid> {
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final _categoryScroll = ScrollController();
  final _gridScroll = ScrollController();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<PosProduct> _allProducts = [];
  List<PosProduct> _products = [];
  List<PosCatalogItem> _categories = [];
  String? _categoryId;
  bool _loading = true;
  bool _loadingCategories = true;
  String? _loadError;
  static const _apiPageSize = 48;
  int _nextApiPage = 1;
  int _serverTotal = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  int _loadGen = 0;
  final Map<String, List<PosProductUnitView>> _unitViewsCache = {};
  final Map<String, Future<List<PosProductUnitView>>> _unitViewsLoading = {};
  final Set<String> _unitViewsFullyLoaded = {};
  /// ĐVT vừa chọn trên list mobile — tăng SL giữ đúng đơn vị, không về ĐVT mặc định.
  final Map<String, String> _listUnitKeyByProduct = {};
  Map<String, double> _lastPriceOverrides = const {};
  Timer? _searchDebounce;
  Timer? _imagePrefetchDebounce;
  bool _lockMode = false;
  final Set<String> _soldOutBusyIds = {};
  DateTime _soldOutDayStamp = _vnCalendarDate();

  static DateTime _vnCalendarDate() {
    final vn = DateTime.now().toUtc().add(const Duration(hours: 7));
    return DateTime(vn.year, vn.month, vn.day);
  }

  void _autoResetSoldOutIfNewDay() {
    final today = _vnCalendarDate();
    if (today == _soldOutDayStamp) return;
    _soldOutDayStamp = today;
    if (!_allProducts.any((p) => p.isDailySoldOut)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _allProducts = [
          for (final p in _allProducts)
            p.isDailySoldOut ? p.copyWith(isDailySoldOut: false) : p,
        ];
        _products = [
          for (final p in _products)
            p.isDailySoldOut ? p.copyWith(isDailySoldOut: false) : p,
        ];
      });
    });
  }

  /// Chỉ dữ liệu nhúng — không gọi API khi vẽ lưới (A7/V2s).
  List<PosProductUnitView> _viewsForDisplay(PosProduct p) {
    if (!identical(_lastPriceOverrides, widget.priceOverrides)) {
      _unitViewsCache.clear();
      _unitViewsFullyLoaded.clear();
      _lastPriceOverrides = widget.priceOverrides;
    }

    final cached = _unitViewsCache[p.id];
    if (cached != null) return cached;

    var views = posProductHasEmbeddedSellViews(p)
        ? buildPosSellUnitViewsFromProduct(p)
        : buildPosProductUnitViews(p, const [], extraUnits: const []);
    views = applyPosPriceListToViews(views, p, widget.priceOverrides);
    if (views.length > 1) {
      _unitViewsCache[p.id] = views;
      _unitViewsFullyLoaded.add(p.id);
    }
    return views;
  }

  Future<List<PosProductUnitView>> _viewsFor(PosProduct p) {
    if (!identical(_lastPriceOverrides, widget.priceOverrides)) {
      _unitViewsCache.clear();
      _unitViewsFullyLoaded.clear();
      _lastPriceOverrides = widget.priceOverrides;
    }

    final cached = _unitViewsCache[p.id];
    if (cached != null && _unitViewsFullyLoaded.contains(p.id)) {
      return Future.value(cached);
    }

    return _unitViewsLoading.putIfAbsent(p.id, () async {
      var views = await loadPosSellUnitViews(widget.api, p);
      views = applyPosPriceListToViews(views, p, widget.priceOverrides);
      _unitViewsCache[p.id] = views;
      _unitViewsFullyLoaded.add(p.id);
      _unitViewsLoading.remove(p.id);
      return views;
    });
  }

  void _prefetchPageUnitViews() {
    for (final p in _pageItems) {
      _viewsForDisplay(p);
      unawaited(_viewsFor(p).then((views) {
        if (!mounted || views.length < 2) return;
        setState(() {});
      }));
    }
    _imagePrefetchDebounce?.cancel();
    _imagePrefetchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _prefetchPageImages();
    });
  }

  void _prefetchPageImages() {
    final items = _pageItems.take(12).toList();
    var i = 0;
    Future<void> pump() async {
      while (i < items.length) {
        final batch = <Future<void>>[];
        for (var n = 0; n < 2 && i < items.length; n++, i++) {
          final p = items[i];
          batch.add(PosProductImageCacheManager.instance.prefetchProduct(
            api: widget.api,
            productId: p.id,
            imageUrl: p.imageUrl,
            updatedAt: p.updatedAt,
          ));
        }
        await Future.wait(batch);
      }
    }

    // ignore: discarded_futures
    pump();
  }

  @override
  void initState() {
    super.initState();
    ScreenRefreshNotifier.posSellProductGrid.addListener(_onExternalRefresh);
    ScreenRefreshNotifier.posSellStockPatch.addListener(_onStockPatch);
    _loadCategories();
    _gridScroll.addListener(_onScrollNearEnd);
    _loadProducts();
    // Hàng / giá / tồn đổi ở máy khác → đồng bộ phần thay đổi (gom 1,5s), không đợi 2 phút.
    _catalogEventSub = SignalRService().onPosFloorChanged.listen((event) {
      if (PosSyncReasons.catalog.contains(PosSyncReasons.of(event))) _scheduleCatalogDelta();
    });
    _catalogConnSub = SignalRService().onConnectionStateChanged.listen((connected) {
      if (connected) _scheduleCatalogDelta();
    });
    _catalogLifecycle = AppLifecycleListener(onResume: _scheduleCatalogDelta);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onStockPatch();
      if (ScreenRefreshNotifier.posSellProductGrid.value > 0) {
        _onExternalRefresh();
      }
    });
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.posSellProductGrid.removeListener(_onExternalRefresh);
    ScreenRefreshNotifier.posSellStockPatch.removeListener(_onStockPatch);
    _searchDebounce?.cancel();
    _imagePrefetchDebounce?.cancel();
    _imageWarmupTimer?.cancel();
    _catalogDeltaTimer?.cancel();
    _catalogEventSub?.cancel();
    _catalogConnSub?.cancel();
    _catalogLifecycle?.dispose();
    _categoryScroll.dispose();
    _gridScroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onExternalRefresh() {
    if (!mounted) return;
    final storeId = widget.storeId?.trim();
    if (storeId != null && storeId.isNotEmpty) {
      PosSellCatalogCache.instance.invalidate(storeId);
    }
    _loadProducts(forceNetwork: true);
  }

  void _onStockPatch() {
    final patch = ScreenRefreshNotifier.posSellStockPatch.value;
    if (patch == null || patch.isEmpty || !mounted) return;
    applyStockLinePatches(patch);
    ScreenRefreshNotifier.posSellStockPatch.value = null;
  }

  void reload({bool forceNetwork = true}) => _loadProducts(forceNetwork: forceNetwork);

  List<PosProduct> get catalogProducts => _allProducts;

  PosProduct? findCatalogProduct(String id) {
    for (final p in _allProducts) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Cập nhật chip ghi chú nhanh trên catalog đang cache.
  void applySaleQuickNotes(String productId, List<String> notes) {
    if (productId.isEmpty) return;
    var changed = false;
    void patch(List<PosProduct> list) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id != productId) continue;
        list[i] = list[i].copyWith(saleQuickNotes: notes);
        changed = true;
      }
    }

    patch(_allProducts);
    patch(_products);
    if (changed && mounted) setState(() {});
  }

  /// Cập nhật tồn cục bộ theo dòng bán/trả — không reload lưới/ảnh.
  void applyStockLinePatches(List<PosSellStockLineDelta> lines) {
    if (lines.isEmpty) return;
    final merged = mergeStockLineDeltas(lines);
    final ids = {for (final l in merged) l.productId};
    var changed = false;
    final nextAll = List<PosProduct>.from(_allProducts);
    for (var i = 0; i < nextAll.length; i++) {
      final p = nextAll[i];
      if (!ids.contains(p.id)) continue;
      nextAll[i] = applyPosSellStockLines(p, merged);
      changed = true;
    }
    if (!changed) return;
    setState(() {
      _allProducts = nextAll;
      _products = List<PosProduct>.from(_allProducts);
      for (final id in ids) {
        _unitViewsCache.remove(id);
        _unitViewsLoading.remove(id);
      }
    });
    final storeId = widget.storeId?.trim();
    if (storeId != null && storeId.isNotEmpty) {
      PosSellCatalogCache.instance.patchMemoryProducts(
        storeId,
        ids,
        (p) => applyPosSellStockLines(p, merged),
      );
    }
  }

  /// Sau bán — trừ tồn SP đã bán, không reload lưới/ảnh.
  void applySoldQuantities(Map<String, double> soldByProductId) {
    if (soldByProductId.isEmpty) return;
    final lines = soldByProductId.entries
        .where((e) => e.value > 0)
        .map(
          (e) => PosSellStockLineDelta(
            productId: e.key,
            qty: e.value,
          ),
        )
        .toList();
    applyStockLinePatches(lines);
  }

  void applySoldLinePatches(List<PosSellStockLineDelta> lines) {
    applyStockLinePatches(lines);
  }

  bool get _hasActiveFilter =>
      _searchQuery.trim().isNotEmpty ||
      (_categoryId != null && _categoryId!.isNotEmpty);

  void _onScrollNearEnd() {
    if (!_gridScroll.hasClients) return;
    final pos = _gridScroll.position;
    // List ngắn (menu F&B trên iPhone): maxScrollExtent < 320 → pixels=0
    // vẫn thỏa "gần cuối" và gọi loadMore page 1, cache bị ghép trùng.
    if (pos.maxScrollExtent < 320) return;
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      unawaited(_loadMore());
    }
  }

  Future<void> _openCatalogSort() async {
    final ok = await showPosCatalogSortSheet(
      context: context,
      api: widget.api,
      categories: _categories,
      products: _allProducts,
      initialCategoryId: _categoryId,
    );
    if (!mounted || !ok) return;
    await _loadCategories();
    await _loadProducts(forceNetwork: true);
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final next = raw.trim();
      if (next == _searchQuery) return;
      _searchQuery = next;
      unawaited(_loadProducts());
    });
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        onTap: posShowSoftKeyboardOnFieldTap,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: tr('Tìm tên, mã hàng, mã vạch…'),
          isDense: true,
          filled: true,
          fillColor: SboxColors.slate50,
          prefixIcon: const Icon(Icons.search, size: 20, color: PosTheme.textSecondary),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchQuery.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Xóa'),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                  },
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('Quét QR / mã vạch liên tục'),
                icon: const Icon(Icons.qr_code_scanner, size: 22, color: PosTheme.kiotBlue),
                onPressed: () => unawaited(_scanContinuousAndPick()),
              ),
            ],
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: PosTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: PosTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: PosTheme.kiotBlue, width: 1.4),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Future<void> _loadProducts({bool forceNetwork = false}) async {
    final storeId = widget.storeId?.trim() ?? '';
    _loadGen++;
    final gen = _loadGen;
    _nextApiPage = 1;
    _hasMore = true;
    _loadingMore = false;

    // Đã có đủ danh mục trên máy → tìm / lọc nhóm ngay, không chờ mạng.
    if (!forceNetwork && _hasActiveFilter && storeId.isNotEmpty) {
      final snap = await PosSellCatalogCache.instance.read(storeId);
      if (gen != _loadGen || !mounted) return;
      if (snap != null && snap.complete && snap.items.isNotEmpty) {
        final filtered = _filterLocal(snap.items);
        setState(() {
          _allProducts = filtered;
          _products = List<PosProduct>.from(filtered);
          _serverTotal = filtered.length;
          _loading = false;
          _loadError = null;
          _hasMore = false;
        });
        _prefetchPageUnitViews();
        return;
      }
    }

    if (!forceNetwork && !_hasActiveFilter && storeId.isNotEmpty) {
      final cached = await PosSellCatalogCache.instance.read(storeId);
      if (cached != null && cached.items.isNotEmpty && gen == _loadGen) {
        if (!mounted) return;
        final unique = uniquePosProductsById(cached.items);
        setState(() {
          _allProducts = unique;
          _products = List<PosProduct>.from(unique);
          _serverTotal = unique.length;
          _loading = false;
          _loadError = null;
          // Snapshot cache = đủ catalog; không loadMore page 1 chồng lên.
          _hasMore = false;
        });
        _prefetchPageUnitViews();
        if (!cached.complete) {
          // Bản lưu cũ chỉ có trang đầu → tải đủ ở nền (vẫn hiện bản cũ).
          unawaited(_syncFullCatalog(storeId));
        } else if (!cached.isFresh) {
          unawaited(_revalidateCatalog(storeId, cached));
        }
        return;
      }
    }

    if (mounted && (_products.isEmpty || forceNetwork || _hasActiveFilter)) {
      setState(() => _loading = true);
    }
    await _fetchCatalogPage(storeId, reset: true, gen: gen);
    // Hiện trang đầu cho nhanh, đồng thời tải đủ danh mục ở nền để lần sau mở là có ngay.
    if (storeId.isNotEmpty && !_hasActiveFilter) {
      unawaited(_syncFullCatalog(storeId));
    }
  }

  /// Lọc giống server: tên / mã / mã vạch không dấu + nhóm hàng (kèm nhóm con).
  List<PosProduct> _filterLocal(List<PosProduct> items) {
    final q = vnFold(_searchQuery.trim());
    final cat = (_categoryId ?? '').trim();
    Set<String>? catIds;
    if (cat.isNotEmpty) {
      catIds = {cat.toLowerCase()};
      var grew = true;
      while (grew) {
        grew = false;
        for (final c in _categories) {
          final parent = (c.parentId ?? '').toLowerCase();
          if (parent.isNotEmpty && catIds.contains(parent) && catIds.add(c.id.toLowerCase())) {
            grew = true;
          }
        }
      }
    }
    return [
      for (final p in items)
        if ((catIds == null || catIds.contains((p.categoryId ?? '').toLowerCase())) &&
            (q.isEmpty ||
                vnFold(p.name).contains(q) ||
                vnFold(p.productCode).contains(q) ||
                vnFold(p.barcode ?? '').contains(q)))
          p,
    ];
  }

  bool _fullSyncRunning = false;
  StreamSubscription<Map<String, dynamic>>? _catalogEventSub;
  StreamSubscription<bool>? _catalogConnSub;
  AppLifecycleListener? _catalogLifecycle;
  Timer? _catalogDeltaTimer;

  void _scheduleCatalogDelta() {
    _catalogDeltaTimer?.cancel();
    _catalogDeltaTimer = Timer(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;
      final storeId = widget.storeId?.trim() ?? '';
      if (storeId.isEmpty) return;
      final snap = await PosSellCatalogCache.instance.read(storeId);
      if (!mounted) return;
      if (snap == null || !snap.complete) {
        await _syncFullCatalog(storeId);
      } else {
        await _revalidateCatalog(storeId, snap);
      }
    });
  }

  /// Tải ĐỦ danh mục (mọi trang) rồi mới ghi cache — trước đây ghi đè cache bằng trang 1
  /// (48 món) ⇒ lần mở sau chỉ còn 48 món, không tải thêm.
  Future<void> _syncFullCatalog(String storeId) async {
    if (_fullSyncRunning || storeId.isEmpty) return;
    _fullSyncRunning = true;
    try {
      const size = 100;
      final all = <PosProduct>[];
      DateTime? version;
      DateTime? serverTime;
      var total = 0;
      for (var page = 1; page <= 200; page++) {
        final res = await widget.api.getPosSellProducts(page: page, pageSize: size);
        if (res['isSuccess'] != true || res['data'] is! Map) return; // giữ bản cũ
        final data = res['data'] as Map<String, dynamic>;
        if (page == 1) {
          total = (data['total'] as num?)?.toInt() ?? 0;
          version = DateTime.tryParse('${data['catalogVersion'] ?? ''}');
          serverTime = DateTime.tryParse('${data['serverTime'] ?? ''}');
        }
        final raw = data['items'] as List? ?? const [];
        for (final e in raw) {
          if (e is! Map) continue;
          try {
            all.add(applyComboSellableToProduct(
              PosProduct.fromJson(Map<String, dynamic>.from(e)),
            ));
          } catch (_) {}
        }
        if (raw.length < size || all.length >= total) break;
      }
      final unique = uniquePosProductsById(all);
      await PosSellCatalogCache.instance.write(
        storeId,
        items: unique,
        catalogVersion: version,
        complete: true,
        syncedAt: serverTime,
        fullSyncedAt: DateTime.now(),
      );
      _applyFreshCatalog(unique);
    } catch (_) {
      // Lỗi mạng: giữ bản đang có, lần sau thử lại.
    } finally {
      _fullSyncRunning = false;
    }
  }

  /// Chỉ hỏi phần thay đổi từ lần đồng bộ trước (thường vài món): sửa / thêm / xóa.
  Future<void> _revalidateCatalog(String storeId, PosSellCatalogSnapshot snap) async {
    final since = snap.syncedAt;
    final full = snap.fullSyncedAt;
    if (since == null ||
        full == null ||
        DateTime.now().difference(full) > PosSellCatalogCache.fullSyncEvery) {
      await _syncFullCatalog(storeId);
      return;
    }
    if (_fullSyncRunning) return;
    try {
      final res = await widget.api.getPosSellProducts(
        page: 1,
        pageSize: 500,
        // Lùi 5 giây: tránh sót món ghi đúng lúc server chụp mốc.
        updatedSince: since.subtract(const Duration(seconds: 5)),
      );
      if (res['isSuccess'] != true || res['data'] is! Map) return;
      final data = res['data'] as Map<String, dynamic>;
      final raw = data['items'] as List? ?? const [];
      if (raw.length >= 500) {
        await _syncFullCatalog(storeId);
        return;
      }
      final removed = {
        for (final id in (data['removedIds'] as List? ?? const [])) '$id'.toLowerCase(),
      };
      final changed = <String, PosProduct>{};
      for (final e in raw) {
        if (e is! Map) continue;
        try {
          final p = applyComboSellableToProduct(
            PosProduct.fromJson(Map<String, dynamic>.from(e)),
          );
          changed[p.id.toLowerCase()] = p;
        } catch (_) {}
      }
      final current = (await PosSellCatalogCache.instance.read(storeId))?.items ?? snap.items;
      final merged = <PosProduct>[];
      for (final p in current) {
        final key = p.id.toLowerCase();
        if (removed.contains(key)) continue;
        merged.add(changed.remove(key) ?? p);
      }
      merged.addAll(changed.values); // món mới thêm
      final sellableTotal = (data['sellableTotal'] as num?)?.toInt();
      if (sellableTotal != null && sellableTotal != merged.length) {
        // Lệch số món (đổi nhóm bán / dữ liệu cũ) → tải lại đủ cho chắc.
        await _syncFullCatalog(storeId);
        return;
      }
      await PosSellCatalogCache.instance.write(
        storeId,
        items: merged,
        catalogVersion: DateTime.tryParse('${data['catalogVersion'] ?? ''}'),
        complete: true,
        syncedAt: DateTime.tryParse('${data['serverTime'] ?? ''}'),
      );
      if (raw.isNotEmpty || removed.isNotEmpty) _applyFreshCatalog(merged);
    } catch (_) {}
  }

  /// Đẩy danh mục mới lên lưới nếu đang xem toàn bộ (đang lọc thì lọc lại trên bản mới).
  void _applyFreshCatalog(List<PosProduct> items) {
    if (!mounted) return;
    final view = _hasActiveFilter ? _filterLocal(items) : items;
    setState(() {
      _allProducts = view;
      _products = List<PosProduct>.from(view);
      _serverTotal = view.length;
      _hasMore = false;
      _loading = false;
      _loadError = null;
    });
    _prefetchPageUnitViews();
    _scheduleCatalogImageWarmup(items);
  }

  Timer? _imageWarmupTimer;

  /// Tải trước ảnh toàn thực đơn ở nền (tuần tự, 2 luồng) — lần cuộn sau ảnh có ngay.
  void _scheduleCatalogImageWarmup(List<PosProduct> items) {
    _imageWarmupTimer?.cancel();
    _imageWarmupTimer = Timer(const Duration(seconds: 3), () async {
      final withImage = items.where((p) => (p.imageUrl ?? '').trim().isNotEmpty).toList();
      for (var i = 0; i < withImage.length && mounted; i += 2) {
        await Future.wait([
          for (final p in withImage.skip(i).take(2))
            PosProductImageCacheManager.instance.prefetchProduct(
              api: widget.api,
              productId: p.id,
              imageUrl: p.imageUrl,
              updatedAt: p.updatedAt,
            ),
        ]);
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    _loadingMore = true;
    final storeId = widget.storeId?.trim() ?? '';
    await _fetchCatalogPage(storeId, reset: false, gen: _loadGen);
  }

  Future<void> _fetchCatalogPage(
    String storeId, {
    required bool reset,
    required int gen,
  }) async {
    if (!reset) _loadingMore = true;
    String? error;
    final page = reset ? 1 : _nextApiPage;
    final batch = <PosProduct>[];
    try {
      final res = await widget.api.getPosSellProducts(
        page: page,
        pageSize: _apiPageSize,
        search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        categoryId: _categoryId,
      );
      if (!mounted || gen != _loadGen) return;
      if (res['isSuccess'] != true || res['data'] is! Map) {
        error = res['message']?.toString() ?? 'Không tải được danh mục hàng';
      } else {
        final data = res['data'] as Map<String, dynamic>;
        final raw = data['items'] as List? ?? [];
        for (final e in raw) {
          if (e is! Map) continue;
          try {
            batch.add(
              applyComboSellableToProduct(
                PosProduct.fromJson(Map<String, dynamic>.from(e)),
              ),
            );
          } catch (_) {}
        }
        final uniqueBatch = uniquePosProductsById(batch);
        batch
          ..clear()
          ..addAll(uniqueBatch);
        _serverTotal = (data['total'] as num?)?.toInt() ??
            (reset ? batch.length : _allProducts.length + batch.length);
        _nextApiPage = page + 1;
        _hasMore = batch.length >= _apiPageSize &&
            (reset ? batch.length : _allProducts.length + batch.length) <
                _serverTotal;
      }
      // Không ghi cache từ trang lẻ — _syncFullCatalog ghi khi đã đủ danh mục.
    } catch (e) {
      error = e.toString();
    }
    if (!mounted || gen != _loadGen) {
      if (mounted && gen == _loadGen) {
        _loading = false;
        _loadingMore = false;
      }
      return;
    }
    setState(() {
      if (error == null) {
        if (reset) {
          _allProducts = uniquePosProductsById(batch);
          _products = List<PosProduct>.from(_allProducts);
          _unitViewsCache.clear();
          _unitViewsLoading.clear();
          _unitViewsFullyLoaded.clear();
        } else if (batch.isNotEmpty) {
          final seen = {for (final p in _allProducts) p.id.trim().toLowerCase()};
          for (final p in batch) {
            final id = p.id.trim().toLowerCase();
            if (id.isEmpty || !seen.add(id)) continue;
            _allProducts.add(p);
            _products.add(p);
          }
        }
      }
      _loadError = (_allProducts.isEmpty) ? error : null;
      _loading = false;
      _loadingMore = false;
    });
    if (_allProducts.isNotEmpty) _prefetchPageUnitViews();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _loadGen) return;
      if (_hasMore &&
          _gridScroll.hasClients &&
          _gridScroll.position.maxScrollExtent < 48) {
        unawaited(_loadMore());
      }
    });
  }

  Future<void> openCategoryFilter() async {
    if (_loadingCategories) return;
    String? draft = _categoryId;
    await showPosMobileFilterSheet(
      context,
      title: 'Nhóm hàng',
      onReset: () {
        draft = null;
        _selectCategory(null);
      },
      onApply: () => _selectCategory(draft),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _categoryFilterTile('Tất cả', null, draft, (id) => draft = id),
          for (final node in buildPosCategoryTree(_categories))
            ..._categoryFilterTilesForNode(node, draft, (id) => draft = id),
        ],
      ),
    );
  }

  Widget _categoryFilterTile(
    String label,
    String? id,
    String? selected,
    ValueChanged<String?> onSelect,
  ) {
    final isSelected = selected == id;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(tr(label)),
      trailing: isSelected
          ? const Icon(Icons.check, color: PosTheme.kiotBlue, size: 20)
          : null,
      onTap: () => onSelect(id),
    );
  }

  List<Widget> _categoryFilterTilesForNode(
    PosCategoryNode node,
    String? selected,
    ValueChanged<String?> onSelect,
  ) {
    final widgets = <Widget>[
      Padding(
        padding: EdgeInsets.only(left: node.depth * 12.0),
        child: _categoryFilterTile(node.item.name, node.item.id, selected, onSelect),
      ),
    ];
    for (final child in node.children) {
      widgets.addAll(_categoryFilterTilesForNode(child, selected, onSelect));
    }
    return widgets;
  }

  void _stockSnack(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _scanAndPick() async {
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    final pick = await lookupOrPickPosProduct(context, widget.api, code);
    if (pick == null || !mounted) return;
    if (pick.product.isDailySoldOut) {
      _stockSnack(tr('${pick.product.name}: đã hết / tạm khóa'));
      if (!widget.stockWarnOnly) return;
    }
    await _emitPick(pick);
  }

  /// Quét liên tục trên màn chọn hàng — mỗi mã hợp lệ cộng 1 SP vào bản nháp/giỏ.
  Future<void> _scanContinuousAndPick() async {
    await scanBarcodeContinuously(
      context,
      onScan: (code) async {
        if (!mounted) return;
        final pick = await lookupOrPickPosProduct(context, widget.api, code);
        if (pick != null && mounted) {
          if (pick.product.isDailySoldOut) {
            _stockSnack(tr('${pick.product.name}: đã hết / tạm khóa'));
            if (!widget.stockWarnOnly) return;
          }
          await _emitPick(pick);
        }
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _loadCategories() async {
    final res = await widget.api.getPosProductCategories();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      setState(() {
        _categories = (res['data'] as List)
            .map((e) => PosCatalogItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _loadingCategories = false;
      });
    } else {
      setState(() => _loadingCategories = false);
    }
  }

  void _selectCategory(String? id) {
    if (_categoryId == id) return;
    _categoryId = id;
    if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
    unawaited(_loadProducts());
  }

  List<PosProduct> _withSoldOutLast(List<PosProduct> source) {
    if (source.length < 2 || !source.any((p) => p.isDailySoldOut)) {
      return source;
    }
    return [
      ...source.where((p) => !p.isDailySoldOut),
      ...source.where((p) => p.isDailySoldOut),
    ];
  }

  List<PosProduct> get _pageItems => _withSoldOutLast(_products);

  double _qtyInCart(String productId) =>
      widget.cartQtyByProductId[productId] ?? 0;

  /// Thứ tự «món đã chọn lên đầu» chốt lúc danh sách được tải / tìm — bấm thêm món không làm cả danh sách
  /// nhảy chỗ (trước đây món vừa bấm bay lên đầu → lần bấm kế tiếp trúng món khác).
  List<PosProduct>? _pinSource;
  Map<String, int> _pinOrder = const {};

  List<PosProduct> get _sortedSellListProducts {
    // SP đã chọn nổi lên đầu theo thứ tự đặt (món chọn trước xếp trước).
    // Món tạm khóa luôn xuống cuối menu.
    if (!identical(_pinSource, _products)) {
      _pinSource = _products;
      final snap = <String, int>{};
      var i = 0;
      for (final e in widget.cartQtyByProductId.entries) {
        if (e.value > 0) snap[e.key] = i++;
      }
      _pinOrder = snap;
    }
    final order = _pinOrder;
    if (order.isEmpty) return _withSoldOutLast(_products);
    final list = List<PosProduct>.from(_products);
    list.sort((a, b) {
      final ia = order[a.id];
      final ib = order[b.id];
      if (ia != null && ib != null) return ia.compareTo(ib);
      if (ia != null) return -1;
      if (ib != null) return 1;
      final cs = a.sortOrder.compareTo(b.sortOrder);
      if (cs != 0) return cs;
      return a.name.compareTo(b.name);
    });
    return _withSoldOutLast(list);
  }

  Future<void> _promptSellListQty(PosProduct p) async {
    final onSet = widget.onSetQty;
    if (onSet == null) return;
    p = await PosQtyRules.withFreshQtyFlags(widget.api, p);
    if (!mounted) return;
    _replaceProduct(p);
    final storeId = widget.storeId?.trim() ?? '';
    if (storeId.isNotEmpty) {
      PosSellCatalogCache.instance.patchMemoryProducts(
        storeId,
        {p.id},
        (_) => p,
      );
    }
    final cur = _qtyInCart(p.id);
    final result = await showPosLineQtyDialog(
      context: context,
      productName: p.name,
      unitName: p.baseUnitName,
      initialQty: cur <= 0 ? 1 : cur,
      allowDecimal: PosQtyRules.allowsDecimal(p) && !p.allowAreaQty,
      enterByArea: p.allowAreaQty && !p.requiresSerial,
      askLength: p.showAreaLength,
      askWidth: p.showAreaWidth,
      askHeight: p.showAreaHeight,
      serialOnly: p.requiresSerial,
    );
    if (result == null || !mounted) return;
    var product = p;
    if (!p.requiresSerial && result.decimal != p.allowDecimalQty) {
      final saved = await PosQtyRules.persistAllowDecimal(
        widget.api,
        p,
        result.decimal,
      );
      if (!mounted) return;
      if (saved.product == null) {
        if (!PosQtyRules.isWhole(result.qty)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(saved.error ?? 'Không lưu được bán số lẻ'))),
          );
          return;
        }
      } else {
        product = saved.product!;
        _replaceProduct(product);
      }
    }
    onSet(product, result.qty, areaNote: result.areaNote);
  }

  void _replaceProduct(PosProduct next) {
    setState(() {
      _allProducts = [
        for (final item in _allProducts)
          if (item.id == next.id) next else item,
      ];
      _products = [
        for (final item in _products)
          if (item.id == next.id) next else item,
      ];
    });
  }

  List<PosProduct> get _sortedSellListPageItems => _sortedSellListProducts;

  int _columnsForWidth(double w) {
    if (w >= 560) return 5;
    if (w >= 420) return 4;
    if (w >= 300) return 3;
    return 2;
  }

  /// KiotViet: luôn dùng hàng pill danh mục (không rail trái).
  bool _useHorizontalCategories(double w) => true;

  double _aspectRatioForWidth(double w, int cols) {
    // KiotViet: ảnh lớn + tên ngắn — tỉ lệ rộng hơn một chút.
    if (cols >= 5) return 0.78;
    if (cols == 4) return 0.74;
    if (cols == 3) return 0.72;
    return 0.70;
  }

  Future<void> _setLockMode(bool enabled) async {
    if (enabled == _lockMode) return;
    if (enabled) {
      final ok = await confirmPosOwnerPassword(
        context,
        title: 'Bật chế độ khóa món',
        message:
            'Nhập mật khẩu tài khoản chủ cửa hàng hoặc quản lý để khóa / mở bán món.',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _lockMode = enabled);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(tr(enabled
            ? 'Chế độ khóa món: chạm món để báo hết hoặc bán lại. Ngày mai tự mở.'
            : 'Đã tắt chế độ khóa món')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onProductTap(PosProduct p, {PosProductUnitView? view}) async {
    if (_lockMode) {
      await _toggleDailySoldOut(p);
      return;
    }
    if (p.isDailySoldOut) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(tr(
              '${p.name}: đã hết / tạm khóa. Bật chế độ khóa món để bán lại.')),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    await _pickProduct(p, view: view);
  }

  Future<void> _toggleDailySoldOut(PosProduct p) async {
    if (!_lockMode) return;
    if (_soldOutBusyIds.contains(p.id)) return;
    _soldOutBusyIds.add(p.id);
    final next = !p.isDailySoldOut;
    try {
      final res = await widget.api.patchPosProductDailySoldOut(
        p.id,
        soldOut: next,
      );
      if (!mounted) return;
      if (res['isSuccess'] != true) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(tr(
                res['message']?.toString() ?? 'Không đổi được trạng thái món')),
          ),
        );
        return;
      }
      var locked = next;
      final data = res['data'];
      if (data is Map) {
        locked = data['isDailySoldOut'] == true ||
            data['IsDailySoldOut'] == true;
      }
      _applyDailySoldOut(p.id, locked);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(tr(locked
              ? '${p.name}: đã hết / tạm khóa'
              : '${p.name}: đã mở bán lại')),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      _soldOutBusyIds.remove(p.id);
    }
  }

  void _applyDailySoldOut(String id, bool locked) {
    PosProduct patch(PosProduct x) => x.copyWith(isDailySoldOut: locked);
    setState(() {
      _allProducts = [
        for (final x in _allProducts) x.id == id ? patch(x) : x,
      ];
      _products = [for (final x in _products) x.id == id ? patch(x) : x];
    });
    final storeId = widget.storeId?.trim() ?? '';
    if (storeId.isNotEmpty) {
      PosSellCatalogCache.instance.patchMemoryProducts(storeId, {id}, patch);
    }
  }

  Future<void> _pickProduct(PosProduct p, {PosProductUnitView? view}) async {
    if (p.isDailySoldOut) {
      _stockSnack(tr(widget.stockWarnOnly
          ? '${p.name}: đang hết / tạm khóa — vẫn thêm vào báo giá'
          : '${p.name}: đã hết / tạm khóa'));
      if (!widget.stockWarnOnly) return;
    }
    final views = await _viewsFor(p);
    if (!mounted || views.isEmpty) return;
    if (!p.isDailySoldOut && isPosSellOutOfStock(p, views)) {
      if (widget.stockWarnOnly) {
        _stockSnack(tr('${p.name}: hết hàng trong kho — vẫn thêm vào báo giá, nhớ kiểm tra thời gian giao'));
      } else if (!widget.allowNegativeStock) {
        _stockSnack('${p.name}: ${tr('hết hàng')}');
        return;
      }
    }
    final v = view ?? pickDefaultSellUnitView(p, views) ?? views.first;
    _listUnitKeyByProduct[p.id] = v.viewKey;
    await _emitPick(PosPurchaseLookupPick(
      product: p,
      variantId: v.variantId,
      unitId: v.unitId,
      unitLabel: v.label,
    ));
  }

  Future<void> _emitPick(PosPurchaseLookupPick pick) async {
    final p = pick.product;
    if (p.allowAreaQty && !p.requiresSerial && widget.onSetQty != null) {
      await _promptSellListQty(p);
      return;
    }
    widget.onPick(pick);
  }

  PosProductUnitView? _listUnitFor(
    PosProduct p,
    List<PosProductUnitView> views,
  ) {
    if (views.isEmpty) return null;
    final key = _listUnitKeyByProduct[p.id];
    if (key != null) {
      for (final v in views) {
        if (v.viewKey == key) return v;
      }
    }
    return pickDefaultSellUnitView(p, views) ?? views.first;
  }

  Future<void> _onListRowTap(PosProduct p, {bool increment = false}) async {
    final views = await _viewsFor(p);
    if (!mounted || views.isEmpty) return;
    setState(() {});
    if (views.length == 1) {
      await _onProductTap(p, view: views.first);
      return;
    }
    if (increment || _listUnitKeyByProduct.containsKey(p.id)) {
      await _onProductTap(p, view: _listUnitFor(p, views));
      return;
    }
    await _pickListUnitWithSheet(p, views);
  }

  Future<void> _pickListUnitWithSheet(
    PosProduct p,
    List<PosProductUnitView> views,
  ) async {
    final chosen = await _showUnitPickerSheet(p, views);
    if (chosen == null || !mounted) return;
    setState(() => _listUnitKeyByProduct[p.id] = chosen.viewKey);
    await _onProductTap(p, view: chosen);
  }

  Future<PosProductUnitView?> _showUnitPickerSheet(
    PosProduct p,
    List<PosProductUnitView> views,
  ) {
    final selectedKey = _listUnitKeyByProduct[p.id];
    return showModalBottomSheet<PosProductUnitView>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD0D5DD),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(p.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _compactUnitChoices(ctx, p, views, selectedKey),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _compactUnitChoices(
    BuildContext ctx,
    PosProduct p,
    List<PosProductUnitView> views,
    String? selectedKey,
  ) {
    final cards = [
      for (final v in views) _unitChoiceCard(ctx, p, v, selectedKey),
    ];
    if (views.length <= 3) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: cards,
    );
  }

  Widget _unitChoiceCard(
    BuildContext ctx,
    PosProduct p,
    PosProductUnitView v,
    String? selectedKey,
  ) {
    final selected = v.viewKey == selectedKey;
    final price = v.basePrice > 0
        ? v.basePrice
        : applyPosPriceListToProductBase(p, widget.priceOverrides);
    final qty = resolvePosSellAvailableQty(p, v);
    final stockHint = p.productType.tracksInventory &&
            qty.isFinite &&
            !qty.isNaN
        ? _qtyFmt.format(qty)
        : null;
    return Material(
      color: selected ? const Color(0xFFE8F0FE) : SboxColors.slate50,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.pop(ctx, v),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _blue : SboxColors.slate200,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                tr(v.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: selected ? _blue : SboxColors.slate900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _moneyFmt.format(price),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _blue,
                ),
              ),
              if (stockHint != null) ...[
                const SizedBox(height: 1),
                Text(
                  stockHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: SboxColors.slate500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _categoryButtons() {
    final widgets = <Widget>[
      _categoryButton('Tất cả', null, depth: 0),
    ];
    for (final node in buildPosCategoryTree(_categories)) {
      widgets.addAll(_categoryNodeButtons(node));
    }
    return widgets;
  }

  List<Widget> _categoryNodeButtons(PosCategoryNode node) {
    final widgets = <Widget>[
      _categoryButton(node.item.name, node.item.id, depth: node.depth),
    ];
    for (final child in node.children) {
      widgets.addAll(_categoryNodeButtons(child));
    }
    return widgets;
  }

  Widget _categoryButton(String label, String? id, {required int depth}) {
    final selected = _categoryId == id;
    return Padding(
      padding: EdgeInsets.fromLTRB(6 + depth * 6.0, 2, 6, 2),
      child: Material(
        color: selected ? _blue.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _selectCategory(id),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? _blue : SboxColors.slate200,
              ),
            ),
            child: Text(
              tr(label),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? _blue : PosTheme.textPrimary,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _unitBar(PosProduct p, List<PosProductUnitView> views) {
    if (views.isEmpty) {
      final fallback = p.baseUnitName.isNotEmpty ? p.baseUnitName : 'Cái';
      return _unitBarShell(
        children: [
          Expanded(
            child: _unitButton(
              label: fallback,
              isDefault: true,
              onTap: () => _onProductTap(p),
            ),
          ),
        ],
      );
    }

    return _unitBarShell(
      children: [
        for (var i = 0; i < views.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 22,
              color: SboxColors.slate200,
            ),
          Expanded(
            child: _unitButton(
              label: views[i].label,
              isDefault: i == 0,
              onTap: () => _onProductTap(p, view: views[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _unitBarShell({required List<Widget> children}) {
    return Container(
      decoration: const BoxDecoration(
        color: SboxColors.slate50,
        border: Border(top: BorderSide(color: SboxColors.slate200)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(children: children),
    );
  }

  Widget _unitButton({
    required String label,
    required bool isDefault,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Text(
          tr(label),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isDefault ? FontWeight.w700 : FontWeight.w600,
            color: isDefault ? _blue : SboxColors.slate600,
            height: 1.15,
          ),
        ),
      ),
    );
  }

  Widget _buildUnitBar(PosProduct p) {
    return _unitBar(p, _viewsForDisplay(p));
  }

  Widget _productCardContent(PosProduct p, List<PosProductUnitView>? views) {
        final view = views != null && views.isNotEmpty
            ? (pickDefaultSellUnitView(p, views) ?? views.first)
            : null;
        final qty = view != null
            ? resolvePosSellListStockQty(p, views!)
            : p.onHandQty;
        final trackStock = switch (p.productType) {
          PosProductType.service => p.hasRecipe,
          PosProductType.combo => p.comboTrackStock && qty.isFinite,
          _ => true,
        };
        final outOfStock = trackStock &&
            isPosSellOutOfStock(p, views ?? const []);
        final price =
            applyPosPriceListToProductBase(p, widget.priceOverrides);
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: p.isDailySoldOut
                  ? SboxColors.warning
                  : outOfStock
                      ? const Color(0xFFFECACA)
                      : const Color(0xFFE8E8E8),
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onProductTap(p),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(
                              color: const Color(0xFFF7F7F7),
                              child: PosProductImage(
                                productId: p.id,
                                imageUrl: p.imageUrl,
                                updatedAt: p.updatedAt,
                                size: 96,
                                fill: true,
                                borderRadius: 0,
                              ),
                            ),
                            if (trackStock)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: _stockBadge(qty: qty),
                              ),
                            Positioned(
                              left: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: const BoxDecoration(
                                  color: PosTheme.kiotBlue,
                                  borderRadius: BorderRadius.only(
                                    topRight: Radius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  tr(_moneyFmt.format(price)),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                            if (p.isDailySoldOut)
                              const Positioned.fill(
                                child: ColoredBox(
                                  color: Color(0xAAF8FAFC),
                                  child: Center(
                                    child: _DailySoldOutBadge(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                        child: Text(
                          tr(p.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: p.isDailySoldOut
                                ? SboxColors.slate400
                                : PosTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _buildUnitBar(p),
            ],
          ),
        );
  }

  Widget _productCard(PosProduct p) {
    return _productCardContent(p, _viewsForDisplay(p));
  }

  Widget _stockBadge({required double qty}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: qty <= 0
            ? SboxColors.dangerSoft
            : SboxColors.brand50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: qty <= 0
              ? const Color(0xFFFCA5A5)
              : SboxColors.brand200,
        ),
      ),
      child: Text(
        tr('Tồn ${_qtyFmt.format(qty)}'),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: qty <= 0
              ? SboxColors.dangerText
              : SboxColors.brand700,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _buildSellList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_products.isEmpty) {
      return Center(
        child: Text(tr('Không có hàng bán trực tiếp'),
          style: TextStyle(color: SboxColors.slate600, fontSize: 13),
        ),
      );
    }

    final pageItems = _sortedSellListPageItems;
    final extra = _loadingMore ? 1 : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RepaintBoundary(
            child: Scrollbar(
              controller: _gridScroll,
              thumbVisibility: true,
              child: ListView.separated(
                controller: _gridScroll,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: pageItems.length + extra,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 70, color: PosTheme.border),
                itemBuilder: (_, i) {
                  if (i >= pageItems.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  return _sellListRow(pageItems[i]);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sellListRowContent(PosProduct p, List<PosProductUnitView>? views) {
    final selectedQty = _qtyInCart(p.id);
    final isSelected = selectedQty > 0;
    final view = views != null && views.isNotEmpty
        ? _listUnitFor(p, views)
        : null;
    final price = view != null
        ? (view.basePrice > 0
            ? view.basePrice
            : applyPosPriceListToProductBase(p, widget.priceOverrides))
        : applyPosPriceListToProductBase(p, widget.priceOverrides);
    final code = view?.displayCode ?? p.productCode;
    final unit = view?.label ?? p.baseUnitName;
    final qty = view != null
        ? resolvePosSellAvailableQty(p, view)
        : p.onHandQty;
    final lowStock = p.productType.tracksInventory &&
        qty.isFinite &&
        qty > 0 &&
        p.minStockQty > 0 &&
        qty <= p.minStockQty;
    final outOfStock = switch (p.productType) {
          PosProductType.service => p.hasRecipe,
          PosProductType.combo => qty.isFinite,
          _ => true,
        } &&
        isPosSellOutOfStock(p, views ?? const []);
    final multi = views != null && views.length > 1;
    final stockQtyText = !qty.isFinite
        ? ''
        : lowStock
            ? 'Sắp hết: ${_qtyFmt.format(qty)}'
            : _qtyFmt.format(qty);
    final stockText = p.isDailySoldOut
        ? 'Đã hết / tạm khóa'
        : outOfStock
            ? 'Hết hàng'
            : stockQtyText.isEmpty
                ? ''
                : multi
                    ? stockQtyText
                    : '$stockQtyText $unit';

    return PosMobileProductRow(
      kiotSellStyle: true,
      isSelected: isSelected,
      selectedQty: isSelected ? selectedQty : null,
      name: p.name,
      code: code,
      unitLabel: multi ? unit : null,
      onUnitTap: multi
          ? () => unawaited(_pickListUnitWithSheet(p, views!))
          : null,
      priceText: _moneyFmt.format(price),
      stockText: stockText,
      orderReservedText: null,
      image: PosProductImage(
        productId: p.id,
        imageUrl: p.imageUrl,
        updatedAt: p.updatedAt,
        size: 48,
        borderRadius: 8,
      ),
      onTap: views == null ? null : () => unawaited(_onListRowTap(p)),
      onIncrement: !isSelected || views == null
          ? null
          : () => unawaited(_onListRowTap(p, increment: true)),
      onDecrement: !isSelected || widget.onDecrement == null
          ? null
          : () => widget.onDecrement!(p),
      onQtyTap: !isSelected || widget.onSetQty == null
          ? null
          : () => unawaited(_promptSellListQty(p)),
    );
  }

  Widget _sellListRow(PosProduct p) {
    return _sellListRowContent(p, _viewsForDisplay(p));
  }

  Widget _buildGrid(double gridWidth) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(_loadError != null
                    ? 'Không tải được hàng hóa'
                    : 'Không có hàng bán trực tiếp'),
                textAlign: TextAlign.center,
                style: TextStyle(color: SboxColors.slate700, fontSize: 13),
              ),
              if (_loadError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: SboxColors.slate500, fontSize: 11),
                ),
              ],
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _loadProducts(forceNetwork: true),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(tr('Thử lại')),
              ),
            ],
          ),
        ),
      );
    }

    final cols = _columnsForWidth(gridWidth);
    final extra = _loadingMore ? 1 : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RepaintBoundary(
            child: Scrollbar(
              controller: _gridScroll,
              thumbVisibility: true,
              child: GridView.builder(
                controller: _gridScroll,
                cacheExtent: 280,
                addAutomaticKeepAlives: false,
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  childAspectRatio: _aspectRatioForWidth(gridWidth, cols),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _pageItems.length + extra,
                itemBuilder: (_, i) {
                  if (i >= _pageItems.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  return _productCard(_pageItems[i]);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _horizontalCategoryStrip() {
    return _loadingCategories
        ? const SizedBox(
            height: 46,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        : PosHScrollChipRow(
            height: 48,
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: tr(_lockMode
                      ? 'Tắt chế độ khóa món'
                      : 'Chế độ khóa món — cần mật khẩu chủ cửa hàng'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _lockMode ? Icons.lock : Icons.lock_open_outlined,
                    size: 22,
                    color: _lockMode
                        ? SboxColors.warning
                        : PosTheme.textSecondary,
                  ),
                  onPressed: () => unawaited(_setLockMode(!_lockMode)),
                ),
                IconButton(
                  tooltip: tr('Sắp xếp menu'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.swap_vert,
                      size: 22, color: PosTheme.textSecondary),
                  onPressed: _openCatalogSort,
                ),
              ],
            ),
            children: [
              _horizontalCategoryChip('Tất cả', null),
              for (final node in buildPosCategoryTree(_categories))
                ..._horizontalCategoryChipsForNode(node),
            ],
          );
  }

  List<Widget> _horizontalCategoryChipsForNode(PosCategoryNode node) {
    final widgets = <Widget>[
      _horizontalCategoryChip(node.item.name, node.item.id),
    ];
    for (final child in node.children) {
      widgets.addAll(_horizontalCategoryChipsForNode(child));
    }
    return widgets;
  }

  Widget _horizontalCategoryChip(String label, String? id) {
    final selected = _categoryId == id;
    return Material(
      color: selected ? PosTheme.kiotBlue : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _selectCategory(id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? PosTheme.kiotBlue : const Color(0xFFD9D9D9),
            ),
          ),
          child: Text(
            tr(label),
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : PosTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _autoResetSoldOutIfNewDay();
    if (widget.sellListLayout) {
      return Material(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchBar(),
            _horizontalCategoryStrip(),
            if (_lockMode) const _LockModeBanner(),
            const Divider(height: 1, color: PosTheme.border),
            Expanded(child: _buildSellList()),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalCats = _useHorizontalCategories(constraints.maxWidth);
        if (horizontalCats) {
          return Material(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                _horizontalCategoryStrip(),
                if (_lockMode) const _LockModeBanner(),
                const Divider(height: 1, color: PosTheme.border),
                Expanded(child: _buildGrid(constraints.maxWidth)),
              ],
            ),
          );
        }
        return Material(
          color: Colors.white,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 108,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: SboxColors.slate50,
                    border: Border(right: BorderSide(color: SboxColors.slate200)),
                  ),
                  child: _loadingCategories
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: Scrollbar(
                                controller: _categoryScroll,
                                thumbVisibility: true,
                                child: ListView(
                                  controller: _categoryScroll,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  children: _categoryButtons(),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: tr(_lockMode
                                  ? 'Tắt chế độ khóa món'
                                  : 'Chế độ khóa món — cần mật khẩu chủ cửa hàng'),
                              icon: Icon(
                                _lockMode
                                    ? Icons.lock
                                    : Icons.lock_open_outlined,
                                color: _lockMode
                                    ? SboxColors.warning
                                    : null,
                              ),
                              onPressed: () =>
                                  unawaited(_setLockMode(!_lockMode)),
                            ),
                            IconButton(
                              tooltip: tr('Sắp xếp menu'),
                              icon: const Icon(Icons.swap_vert),
                              onPressed: _openCatalogSort,
                            ),
                          ],
                        ),
                ),
              ),
              Expanded(
                child: _buildGrid(constraints.maxWidth - 108),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DailySoldOutBadge extends StatelessWidget {
  const _DailySoldOutBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: SboxColors.warning,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tr('HẾT MÓN'),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _LockModeBanner extends StatelessWidget {
  const _LockModeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: SboxColors.warningSoft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Text(
        tr('Chế độ khóa món — chạm để báo hết / bán lại. Ngày mai tự mở bán.'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: SboxColors.warningText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
