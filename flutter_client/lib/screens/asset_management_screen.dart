import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../utils/number_formatter.dart';
import '../models/asset.dart';
import '../models/employee.dart';
import '../utils/responsive_helper.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

class AssetManagementScreen extends StatefulWidget {
  const AssetManagementScreen({super.key});

  @override
  State<AssetManagementScreen> createState() => _AssetManagementScreenState();
}

class _AssetManagementScreenState extends State<AssetManagementScreen> {
  final ApiService _apiService = ApiService();
  final _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  final _searchController = TextEditingController();

  // Tab navigation
  int _currentTab = 0; // 0=Sản phẩm, 1=Kho, 2=Kiểm kê, 3=Lịch sử

  // Data
  List<Asset> _assets = [];
  List<AssetCategory> _categories = [];
  List<AssetTransfer> _transfers = [];
  List<AssetInventory> _inventories = [];
  List<Employee> _employees = [];
  AssetStatistics? _statistics;
  List<StockTransaction> _stockTransactions = [];
  StockSummary? _stockSummary;
  // ignore: unused_field
  int _stockTxTotal = 0;

  // Loading
  bool _isLoading = true;
  int _totalAssets = 0;
  int _currentPage = 1;
  int _pageSize = 20;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  // Filters
  String? _searchQuery;
  AssetStatus? _statusFilter;
  AssetType? _typeFilter;
  String? _categoryFilter;
  bool _showFilters = false;
  bool _showMobileFilters = false;
  bool _showMobileSummary = false;

  // Selection
  final Set<String> _selectedAssetIds = {};

  // Side panels
  bool _showTransfers = false;
  bool _showCategories = false;
  bool _showInventories = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadEmployees(),
        _loadAssets(),
        _loadCategories(),
        _loadStatistics(),
      ]);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadEmployees() async {
    final employees = await _apiService.getEmployees();
    if (mounted) {
      setState(() {
        _employees = employees.map((e) => Employee.fromJson(e)).toList();
      });
    }
  }

  Future<void> _loadAssets() async {
    final result = await _apiService.getAssets(
      page: _currentPage,
      pageSize: _pageSize,
      search: _searchQuery,
      status: _statusFilter?.index,
      assetType: _typeFilter?.index,
      categoryId: _categoryFilter,
    );
    if (result['isSuccess'] == true && result['data'] != null) {
      final data = result['data'];
      if (mounted) {
        setState(() {
          _assets = (data['items'] as List?)?.map((e) => Asset.fromJson(e)).toList() ?? [];
          _totalAssets = data['totalCount'] ?? 0;
        });
      }
    }
  }

  Future<void> _loadCategories() async {
    final result = await _apiService.getAssetCategories(hierarchical: true);
    if (result['isSuccess'] == true && result['data'] != null) {
      if (mounted) {
        setState(() {
          _categories = (result['data'] as List?)?.map((e) => AssetCategory.fromJson(e)).toList() ?? [];
        });
      }
    }
  }

  Future<void> _loadTransfers() async {
    final result = await _apiService.getAssetTransfers(page: 1, pageSize: 50);
    if (result['isSuccess'] == true && result['data'] != null) {
      final data = result['data'];
      if (mounted) {
        setState(() {
          _transfers = (data is List ? data : (data['items'] as List?) ?? []).map((e) => AssetTransfer.fromJson(e)).toList();
        });
      }
    }
  }

  Future<void> _loadInventories() async {
    final result = await _apiService.getAssetInventories(page: 1, pageSize: 50);
    if (result['isSuccess'] == true && result['data'] != null) {
      final data = result['data'];
      if (mounted) {
        setState(() {
          _inventories = (data is List ? data : (data['items'] as List?) ?? []).map((e) => AssetInventory.fromJson(e)).toList();
        });
      }
    }
  }

  Future<void> _loadStatistics() async {
    final result = await _apiService.getAssetStatistics();
    if (result['isSuccess'] == true && result['data'] != null) {
      if (mounted) {
        setState(() {
          _statistics = AssetStatistics.fromJson(result['data']);
        });
      }
    }
  }

  Future<void> _loadStockTransactions({int? typeFilter, String? search}) async {
    final result = await _apiService.getStockTransactions(
      page: 1, pageSize: 100,
      transactionType: typeFilter,
      search: search,
    );
    if (result['isSuccess'] == true && result['data'] != null) {
      final data = result['data'];
      if (mounted) {
        setState(() {
          _stockTransactions = (data['items'] as List?)?.map((e) => StockTransaction.fromJson(e)).toList() ?? [];
          _stockTxTotal = data['total'] ?? 0;
        });
      }
    }
  }

  Future<void> _loadStockSummary() async {
    final result = await _apiService.getStockSummary();
    if (result['isSuccess'] == true && result['data'] != null) {
      if (mounted) {
        setState(() {
          _stockSummary = StockSummary.fromJson(result['data']);
        });
      }
    }
  }

  void _onSearch(String value) {
    setState(() {
      _searchQuery = value.isEmpty ? null : value;
      _currentPage = 1;
    });
    _loadAssets();
  }

  void _clearFilters() {
    setState(() {
      _statusFilter = null;
      _typeFilter = null;
      _categoryFilter = null;
      _searchQuery = null;
      _searchController.clear();
      _currentPage = 1;
    });
    _loadAssets();
  }

  bool get _hasActiveFilters => _statusFilter != null || _typeFilter != null || _categoryFilter != null;

  // ==================== QR SCAN ====================
  void _showQrScanDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AssetQrScanDialog(
        onAssetScanned: (code) async {
          Navigator.pop(ctx);
          await _lookupAssetByCode(code);
        },
      ),
    );
  }

  Future<void> _lookupAssetByCode(String code) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final result = await _apiService.lookupAssetByCode(code);
    if (mounted) Navigator.pop(context);

    if (result['isSuccess'] == true && result['data'] != null) {
      final asset = Asset.fromJson(result['data']);
      if (mounted) _showAssetDetail(asset);
    } else {
      if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Không tìm thấy',
          message: result['message'] ?? 'Không tìm thấy tài sản',
        );
      }
    }
  }

  void _handleInventoryAction(AssetInventory inventory, String action) async {
    if (action == 'detail') {
      _showInventoryDetailDialog(inventory);
      return;
    }

    final isDelete = action == 'delete';
    final title = isDelete ? 'Xóa đợt kiểm kê?' : 'Hủy đợt kiểm kê?';
    final message = isDelete
        ? 'Bạn có chắc muốn xóa "${inventory.name}"? Dữ liệu sẽ bị mất vĩnh viễn.'
        : 'Bạn có chắc muốn hủy "${inventory.name}"?';
    final confirmText = isDelete ? 'Xóa' : 'Hủy kiểm kê';
    final confirmColor = isDelete ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Đóng', style: TextStyle(color: Color(0xFF71717A)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final result = isDelete
        ? await _apiService.deleteInventory(inventory.id)
        : await _apiService.cancelInventory(inventory.id);

    if (result['isSuccess'] == true) {
      _loadInventories();
      if (mounted) {
        NotificationOverlayManager().showSuccess(
          title: 'Thành công',
          message: isDelete ? 'Đã xóa đợt kiểm kê' : 'Đã hủy đợt kiểm kê',
        );
      }
    } else {
      if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: result['message'] ?? 'Thao tác thất bại',
        );
      }
    }
  }

  void _showInventoryDetailDialog(AssetInventory inventory) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final result = await _apiService.getInventoryDetail(inventory.id);
    if (mounted) Navigator.pop(context);

    if (result['isSuccess'] == true && result['data'] != null) {
      final detail = AssetInventory.fromJson(result['data']);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => _InventoryDetailDialog(
            inventory: detail,
            apiService: _apiService,
            onRefresh: () {
              _loadInventories();
              _loadAssets();
              _loadStockSummary();
              _loadStockTransactions();
            },
          ),
        );
      }
    } else {
      if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: result['message'] ?? 'Không thể tải chi tiết kiểm kê',
        );
      }
    }
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: _isLoading ? const LoadingWidget() : _buildBody(),
    );
  }

  void _switchTab(int tab) {
    setState(() {
      _currentTab = tab;
      _showTransfers = false;
      _showCategories = false;
      _showInventories = false;
    });
    if (tab == 0) _loadAssets();
    if (tab == 1) { _loadStockSummary(); _loadAssets(); }
    if (tab == 2) _loadInventories();
    if (tab == 3) _loadStockTransactions();
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildHeader(),
        _buildTabBar(),
        Expanded(
          child: _currentTab == 0
              ? _buildProductTab()
              : _currentTab == 1
                  ? _buildStockTab()
                  : _currentTab == 2
                      ? _buildInventoryTab()
                      : _buildHistoryTab(),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    final isMobile = Responsive.isMobile(context);
    final tabs = [
      (Icons.inventory_2, 'Sản phẩm'),
      (Icons.warehouse, 'Kho'),
      (Icons.checklist, 'Kiểm kê'),
      (Icons.history, 'Lịch sử'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final i = entry.key;
          final tab = entry.value;
          final isActive = _currentTab == i;
          return Expanded(
            child: InkWell(
              onTap: () => _switchTab(i),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive ? const Color(0xFF1E3A5F) : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tab.$1, size: isMobile ? 16 : 18, color: isActive ? const Color(0xFF1E3A5F) : const Color(0xFF71717A)),
                    const SizedBox(width: 6),
                    Text(
                      tab.$2,
                      style: TextStyle(
                        fontSize: isMobile ? 12 : 14,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? const Color(0xFF1E3A5F) : const Color(0xFF71717A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProductTab() {
    final isMobile = Responsive.isMobile(context);
    final hasPanel = _showTransfers || _showCategories;

    return isMobile && hasPanel
        ? _buildActivePanel()
        : Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    if (isMobile) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: InkWell(
                          onTap: () => setState(() => _showMobileSummary = !_showMobileSummary),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.analytics_outlined, size: 16, color: Colors.blue.shade700),
                                const SizedBox(width: 6),
                                Text('Tổng quan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.blue.shade700)),
                                const Spacer(),
                                Icon(_showMobileSummary ? Icons.expand_less : Icons.expand_more, size: 20, color: Colors.blue.shade700),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_showMobileSummary) _buildStatCards(),
                    ] else ...[
                      _buildStatCards(),
                    ],
                    if (!isMobile || _showMobileFilters) ...[
                      _buildToolbar(),
                      if (_showFilters) _buildFilterBar(),
                    ],
                    Expanded(child: _buildAssetTable()),
                    if (!isMobile) _buildPagination(),
                  ],
                ),
              ),
              if (_showTransfers) _buildTransfersPanel(),
              if (_showCategories) _buildCategoriesPanel(),
            ],
          );
  }

  Widget _buildInventoryTab() {
    // Split inventories by status
    final inProgress = _inventories.where((i) => i.isInProgress).toList();
    final completed = _inventories.where((i) => i.isCompleted).toList();
    final cancelled = _inventories.where((i) => i.isCancelled).toList();

    // Stats
    final totalInventories = _inventories.length;
    final totalChecked = _inventories.fold<int>(0, (s, i) => s + i.checkedCount);
    final totalAssets = _inventories.fold<int>(0, (s, i) => s + i.totalAssets);
    final totalIssues = _inventories.fold<int>(0, (s, i) => s + i.issueCount);

    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.fact_check_outlined, size: 20, color: Color(0xFF1E3A5F)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Kiểm kê hàng hóa', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF18181B))),
                      if (totalInventories > 0)
                        Text('$totalInventories đợt · $totalChecked/$totalAssets đã kiểm', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showInventoryDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Tạo mới', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _inventories.isEmpty
                ? const Center(child: EmptyState(icon: Icons.fact_check_outlined, title: 'Chưa có đợt kiểm kê', description: 'Tạo đợt kiểm kê để kiểm soát hàng hóa'))
                : RefreshIndicator(
                    onRefresh: _loadInventories,
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        // Stats overview
                        if (totalInventories > 0) ...[
                          Row(
                            children: [
                              _inventoryStatChip(Icons.hourglass_top, '${inProgress.length}', 'Đang thực hiện', const Color(0xFF3B82F6)),
                              const SizedBox(width: 8),
                              _inventoryStatChip(Icons.check_circle, '${completed.length}', 'Hoàn thành', const Color(0xFF059669)),
                              const SizedBox(width: 8),
                              _inventoryStatChip(Icons.warning_amber, '$totalIssues', 'Vấn đề', const Color(0xFFF59E0B)),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        // In progress section
                        if (inProgress.isNotEmpty) ...[
                          _inventorySectionHeader('Đang thực hiện', Icons.hourglass_top, const Color(0xFF3B82F6), inProgress.length),
                          const SizedBox(height: 8),
                          ...inProgress.map((inv) => _buildInventoryItem(inv)),
                          const SizedBox(height: 16),
                        ],
                        // Completed section
                        if (completed.isNotEmpty) ...[
                          _inventorySectionHeader('Hoàn thành', Icons.check_circle, const Color(0xFF059669), completed.length),
                          const SizedBox(height: 8),
                          ...completed.map((inv) => _buildInventoryItem(inv)),
                          const SizedBox(height: 16),
                        ],
                        // Cancelled section
                        if (cancelled.isNotEmpty) ...[
                          _inventorySectionHeader('Đã hủy', Icons.cancel, const Color(0xFFEF4444), cancelled.length),
                          const SizedBox(height: 8),
                          ...cancelled.map((inv) => _buildInventoryItem(inv)),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _inventoryStatChip(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _inventorySectionHeader(String title, IconData icon, Color color, int count) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }

  // ==================== STOCK TAB ====================
  Widget _buildStockTab() {
    final isMobile = Responsive.isMobile(context);
    final summary = _stockSummary;

    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Summary cards
          if (summary != null)
            Container(
              padding: EdgeInsets.all(isMobile ? 12 : 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _stockSummaryCard('Tổng SP', '${summary.totalProducts}', Icons.inventory_2, const Color(0xFF1E3A5F)),
                  _stockSummaryCard('Tổng tồn kho', '${summary.totalStockQuantity}', Icons.warehouse, const Color(0xFF059669)),
                  _stockSummaryCard('Đã nhập', '+${summary.totalStockIn}', Icons.arrow_downward, const Color(0xFF2563EB)),
                  _stockSummaryCard('Đã xuất', '-${summary.totalStockOut}', Icons.arrow_upward, const Color(0xFFEF4444)),
                ],
              ),
            ),
          // Action buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showStockDialog(isStockIn: true),
                    icon: const Icon(Icons.add_box, size: 20),
                    label: const Text('Nhập kho'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showStockDialog(isStockIn: false),
                    icon: const Icon(Icons.outbox, size: 20),
                    label: const Text('Xuất kho'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Low stock warnings
          if (summary != null && summary.lowStockItems.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFCD34D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber, size: 18, color: Color(0xFFD97706)),
                      SizedBox(width: 6),
                      Text('Sản phẩm sắp hết', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFD97706))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...summary.lowStockItems.take(5).map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(item.assetName ?? item.assetCode ?? "SP", style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(4)),
                          child: Text('Còn ${item.quantity} ${item.unit ?? ""}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Product stock list
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E4E7)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                    child: const Row(
                      children: [
                        Expanded(flex: 3, child: Text('Sản phẩm', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)))),
                        Expanded(flex: 1, child: Text('Tồn', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)), textAlign: TextAlign.center)),
                        Expanded(flex: 1, child: Text('ĐVT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)), textAlign: TextAlign.center)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _assets.isEmpty
                        ? const Center(child: Text('Chưa có sản phẩm', style: TextStyle(color: Color(0xFFA1A1AA))))
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: _assets.length,
                            itemBuilder: (context, index) {
                              final asset = _assets[index];
                              return InkWell(
                                onTap: () => _showStockDetailDialog(asset),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(asset.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            Text(asset.assetCode, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: asset.quantity <= 5 ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '${asset.quantity}',
                                            style: TextStyle(
                                              fontSize: 13, fontWeight: FontWeight.bold,
                                              color: asset.quantity <= 5 ? const Color(0xFFEF4444) : const Color(0xFF059669),
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Text(asset.unit, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), textAlign: TextAlign.center),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _stockSummaryCard(String label, String value, IconData icon, Color color) {
    final isMobile = Responsive.isMobile(context);
    final width = isMobile ? (MediaQuery.of(context).size.width - 36) / 2 : 160.0;
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
                Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showStockDialog({required bool isStockIn}) {
    String? selectedAssetId;
    final qtyCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(isStockIn ? Icons.add_box : Icons.outbox, color: isStockIn ? const Color(0xFF059669) : const Color(0xFFEF4444)),
                const SizedBox(width: 8),
                Text(isStockIn ? 'Nhập kho' : 'Xuất kho'),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Select product
                    DropdownButtonFormField<String>(
                      initialValue: selectedAssetId,
                      decoration: InputDecoration(
                        labelText: 'Sản phẩm *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                      items: _assets.map((a) => DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.name} (Tồn: ${a.quantity})', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (v) => setDialogState(() => selectedAssetId = v),
                    ),
                    const SizedBox(height: 12),
                    // Quantity
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Số lượng *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Reason
                    TextField(
                      controller: reasonCtrl,
                      decoration: InputDecoration(
                        labelText: 'Lý do *',
                        hintText: isStockIn ? 'VD: Nhập hàng mới, bổ sung...' : 'VD: Bán hàng, hỏng, mất...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Reference code
                    TextField(
                      controller: refCtrl,
                      decoration: InputDecoration(
                        labelText: 'Mã phiếu (tuỳ chọn)',
                        hintText: 'VD: PN-001, PX-002...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Notes
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Ghi chú',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
              ElevatedButton(
                onPressed: isSubmitting ? null : () async {
                  if (selectedAssetId == null || qtyCtrl.text.isEmpty || reasonCtrl.text.isEmpty) {
                    NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng điền đầy đủ SP, SL và lý do');
                    return;
                  }
                  final qty = int.tryParse(qtyCtrl.text);
                  if (qty == null || qty <= 0) {
                    NotificationOverlayManager().showWarning(title: 'Lỗi', message: 'Số lượng phải là số > 0');
                    return;
                  }
                  setDialogState(() => isSubmitting = true);
                  final result = isStockIn
                      ? await _apiService.stockIn(assetId: selectedAssetId!, quantity: qty, reason: reasonCtrl.text, referenceCode: refCtrl.text.isNotEmpty ? refCtrl.text : null, notes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null)
                      : await _apiService.stockOut(assetId: selectedAssetId!, quantity: qty, reason: reasonCtrl.text, referenceCode: refCtrl.text.isNotEmpty ? refCtrl.text : null, notes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  if (result['isSuccess'] == true) {
                    NotificationOverlayManager().showSuccess(title: 'Thành công', message: isStockIn ? 'Đã nhập kho $qty SP' : 'Đã xuất kho $qty SP');
                    _loadAssets();
                    _loadStockSummary();
                    _loadStockTransactions();
                  } else {
                    NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isStockIn ? const Color(0xFF059669) : const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                ),
                child: isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(isStockIn ? 'Nhập kho' : 'Xuất kho'),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      qtyCtrl.dispose();
      reasonCtrl.dispose();
      refCtrl.dispose();
      notesCtrl.dispose();
    });
  }

  void _showStockDetailDialog(Asset asset) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.inventory_2, color: Color(0xFF1E3A5F), size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(asset.name, style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stockDetailRow('Mã SP', asset.assetCode),
              _stockDetailRow('Tồn kho', '${asset.quantity} ${asset.unit}'),
              _stockDetailRow('Giá', _currencyFormat.format(asset.purchasePrice)),
              _stockDetailRow('Giá trị tồn', _currencyFormat.format(asset.purchasePrice * asset.quantity)),
              if (asset.location != null) _stockDetailRow('Vị trí', asset.location!),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showStockDialog(isStockIn: true);
                      },
                      icon: const Icon(Icons.add_box, size: 18, color: Color(0xFF059669)),
                      label: const Text('Nhập', style: TextStyle(color: Color(0xFF059669))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showStockDialog(isStockIn: false);
                      },
                      icon: const Icon(Icons.outbox, size: 18, color: Color(0xFFEF4444)),
                      label: const Text('Xuất', style: TextStyle(color: Color(0xFFEF4444))),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng'))],
      ),
    );
  }

  Widget _stockDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF71717A)))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  // ==================== HISTORY TAB ====================
  Widget _buildHistoryTab() {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Filter bar
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Row(
              children: [
                const Icon(Icons.history, size: 20, color: Color(0xFF1E3A5F)),
                const SizedBox(width: 8),
                const Text('Lịch sử giao dịch', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const Spacer(),
                PopupMenuButton<int?>(
                  onSelected: (type) {
                    _loadStockTransactions(typeFilter: type);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: null, child: Text('Tất cả')),
                    const PopupMenuItem(value: 0, child: Text('Nhập kho')),
                    const PopupMenuItem(value: 1, child: Text('Xuất kho')),
                    const PopupMenuItem(value: 2, child: Text('Điều chỉnh')),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.filter_list, size: 16, color: Color(0xFF64748B)),
                        SizedBox(width: 4),
                        Text('Lọc', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Transaction list
          Expanded(
            child: _stockTransactions.isEmpty
                ? const Center(child: EmptyState(icon: Icons.history, title: 'Chưa có giao dịch', description: 'Nhập/xuất kho để thấy lịch sử'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _stockTransactions.length,
                    itemBuilder: (context, index) {
                      final tx = _stockTransactions[index];
                      final isIn = tx.isStockIn;
                      final isAdj = tx.isAdjustment;
                      final color = isIn ? const Color(0xFF059669) : isAdj ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
                      final icon = isIn ? Icons.arrow_downward : isAdj ? Icons.sync : Icons.arrow_upward;
                      final typeLabel = isIn ? 'Nhập kho' : isAdj ? 'Điều chỉnh' : 'Xuất kho';
                      final sign = isIn ? '+' : isAdj ? (tx.quantity >= 0 ? '+' : '') : '-';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                              child: Icon(icon, size: 20, color: color),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(tx.assetName ?? tx.assetCode ?? 'SP', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                        child: Text('$sign${tx.quantity.abs()}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
                                        child: Text(typeLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
                                      ),
                                      const SizedBox(width: 6),
                                      Text('Tồn: ${tx.balanceAfter}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                      const Spacer(),
                                      Text(DateFormat('dd/MM HH:mm').format(tx.transactionDate), style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                                    ],
                                  ),
                                  if (tx.reason != null && tx.reason!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(tx.reason!, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                  if (tx.performedByName != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text('Bởi: ${tx.performedByName}', style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePanel() {
    if (_showTransfers) return _buildTransfersPanel();
    if (_showCategories) return _buildCategoriesPanel();
    if (_showInventories) return _buildInventoriesPanel();
    return const SizedBox();
  }

  // ==================== HEADER ====================
  Widget _buildHeader() {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 12 : 24, isMobile ? 12 : 20, isMobile ? 12 : 24, isMobile ? 8 : 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2, color: Color(0xFF1E3A5F), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Quản lý Tài sản',
              style: TextStyle(fontSize: isMobile ? 16 : 22, fontWeight: FontWeight.bold, color: const Color(0xFF18181B)),
            ),
          ),
          if (isMobile) ...[
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Color(0xFF1E3A5F)),
              tooltip: 'Thêm',
              onSelected: (v) {
                if (v == 'transfers') {
                  setState(() { _showTransfers = true; _showCategories = false; _showInventories = false; });
                  if (_transfers.isEmpty) _loadTransfers();
                } else if (v == 'categories') {
                  setState(() { _showCategories = true; _showTransfers = false; _showInventories = false; });
                } else if (v == 'inventories') {
                  setState(() { _showInventories = true; _showTransfers = false; _showCategories = false; });
                  if (_inventories.isEmpty) _loadInventories();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'transfers', child: Row(children: [Icon(Icons.swap_horiz, size: 18), SizedBox(width: 8), Text('Chuyển giao')])),
                PopupMenuItem(value: 'categories', child: Row(children: [Icon(Icons.category, size: 18), SizedBox(width: 8), Text('Danh mục')])),
                PopupMenuItem(value: 'inventories', child: Row(children: [Icon(Icons.checklist, size: 18), SizedBox(width: 8), Text('Kiểm kê')])),
              ],
            ),
            IconButton(
              onPressed: _showQrScanDialog,
              icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF1E3A5F)),
              tooltip: 'Quét QR tài sản',
            ),
            IconButton(
              onPressed: () => setState(() => _showMobileFilters = !_showMobileFilters),
              icon: Stack(
                children: [
                  Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, color: const Color(0xFF1E3A5F)),
                  if (_hasActiveFilters || _searchQuery != null)
                    Positioned(right: 0, top: 0, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle))),
                ],
              ),
              tooltip: 'Bộ lọc',
            ),
            if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Asset'))
            IconButton(
              onPressed: () => _showAssetDialog(),
              icon: const Icon(Icons.add, color: Color(0xFF1E3A5F), size: 22),
              tooltip: 'Thêm tài sản',
            ),
          ] else ...[
          // Action buttons for less-used features
          _buildHeaderAction(Icons.swap_horiz, 'Chuyển giao', _showTransfers, () {
            setState(() {
              _showTransfers = !_showTransfers;
              _showCategories = false;
              _showInventories = false;
            });
            if (_showTransfers && _transfers.isEmpty) _loadTransfers();
          }),
          const SizedBox(width: 8),
          _buildHeaderAction(Icons.category, 'Danh mục', _showCategories, () {
            setState(() {
              _showCategories = !_showCategories;
              _showTransfers = false;
              _showInventories = false;
            });
          }),
          const SizedBox(width: 8),
          _buildHeaderAction(Icons.checklist, 'Kiểm kê', _showInventories, () {
            setState(() {
              _showInventories = !_showInventories;
              _showTransfers = false;
              _showCategories = false;
            });
            if (_showInventories && _inventories.isEmpty) _loadInventories();
          }),
          const SizedBox(width: 16),
          // QR Scan button
          ElevatedButton.icon(
            onPressed: _showQrScanDialog,
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: const Text('Quét QR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Asset'))
          ElevatedButton.icon(
            onPressed: () => _showAssetDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Thêm tài sản'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderAction(IconData icon, String label, bool isActive, VoidCallback onTap) {
    return Material(
      color: isActive ? const Color(0xFF1E3A5F).withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isActive ? const Color(0xFF1E3A5F) : const Color(0xFF71717A)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? const Color(0xFF1E3A5F) : const Color(0xFF71717A),
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== STAT CARDS ====================
  Widget _buildStatCards() {
    final stats = _statistics;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: LayoutBuilder(builder: (context, constraints) {
        final chips = [
          _buildStatChip('Tổng', stats?.totalAssets ?? 0, const Color(0xFF1E3A5F), Icons.inventory_2),
          _buildStatChip('Đang dùng', stats?.activeAssets ?? 0, const Color(0xFF1E3A5F), Icons.check_circle),
          _buildStatChip('Trong kho', stats?.inStockAssets ?? 0, const Color(0xFF1E3A5F), Icons.warehouse),
          _buildStatChip('Đã cấp', stats?.assignedAssets ?? 0, const Color(0xFFF59E0B), Icons.person),
          _buildStatChip('Bảo trì', stats?.maintenanceAssets ?? 0, const Color(0xFF0F2340), Icons.build),
          _buildStatChip('Hỏng', stats?.brokenAssets ?? 0, const Color(0xFFEF4444), Icons.error),
        ];

        if (constraints.maxWidth < 500) {
          return Column(children: [
            Wrap(spacing: 8, runSpacing: 8, children: chips),
            const SizedBox(height: 8),
            // Value summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE4E4E7)),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tổng giá trị', style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                      const SizedBox(height: 2),
                      Text(
                        _currencyFormat.format(stats?.totalPurchaseValue ?? 0),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF18181B)),
                      ),
                    ],
                  ),
                  if ((stats?.warrantyExpiringSoon ?? 0) > 0) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber, size: 14, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 4),
                          Text(
                            '${stats!.warrantyExpiringSoon} sắp hết BH',
                            style: const TextStyle(fontSize: 11, color: Color(0xFFB45309), fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ]);
        }
        return Row(
          children: [
            for (int i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              chips[i],
            ],
            const Spacer(),
            // Value summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE4E4E7)),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Tổng giá trị', style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                      const SizedBox(height: 2),
                      Text(
                        _currencyFormat.format(stats?.totalPurchaseValue ?? 0),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF18181B)),
                      ),
                    ],
                  ),
                  if ((stats?.warrantyExpiringSoon ?? 0) > 0) ...[
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, size: 14, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 4),
                          Text(
                            '${stats!.warrantyExpiringSoon} sắp hết BH',
                            style: const TextStyle(fontSize: 11, color: Color(0xFFB45309), fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildStatChip(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
              Text('$count', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== TOOLBAR ====================
  Widget _buildToolbar() {
    final isMobile = Responsive.isMobile(context);
    final searchField = SizedBox(
      width: isMobile ? double.infinity : 300,
      child: TextField(
        controller: _searchController,
        onSubmitted: _onSearch,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Tìm kiếm tài sản...',
          hintStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
          prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFFA1A1AA)),
          suffixIcon: _searchQuery != null
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () { _searchController.clear(); _onSearch(''); },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1E3A5F), width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
    final filterToggle = Material(
      color: _showFilters || _hasActiveFilters
          ? const Color(0xFF1E3A5F).withValues(alpha: 0.1)
          : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => setState(() => _showFilters = !_showFilters),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _hasActiveFilters ? const Color(0xFF1E3A5F) : const Color(0xFFE4E4E7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_list, size: 18, color: _hasActiveFilters ? const Color(0xFF1E3A5F) : const Color(0xFF71717A)),
              const SizedBox(width: 6),
              Text('Bộ lọc', style: TextStyle(
                fontSize: 13,
                color: _hasActiveFilters ? const Color(0xFF1E3A5F) : const Color(0xFF71717A),
              )),
              if (_hasActiveFilters) ...[
                const SizedBox(width: 6),
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: Color(0xFF1E3A5F), shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final clearBtn = _hasActiveFilters
        ? TextButton(
            onPressed: _clearFilters,
            child: const Text('Xóa lọc', style: TextStyle(fontSize: 13, color: Color(0xFFEF4444))),
          )
        : const SizedBox.shrink();
    final selectedInfo = _selectedAssetIds.isNotEmpty
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${_selectedAssetIds.length} đã chọn', style: const TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.w500, fontSize: 13)),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _selectedAssetIds.clear()),
                  child: const Icon(Icons.close, size: 16, color: Color(0xFF1E3A5F)),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [filterToggle, clearBtn, selectedInfo],
                ),
              ],
            )
          : Row(
              children: [
                Flexible(child: searchField),
                const SizedBox(width: 12),
                filterToggle,
                if (_hasActiveFilters) ...[
                  const SizedBox(width: 8),
                  clearBtn,
                ],
                const Spacer(),
                if (_selectedAssetIds.isNotEmpty) ...[
                  selectedInfo,
                  const SizedBox(width: 8),
                ],
              ],
            ),
    );
  }

  // ==================== FILTER BAR ====================
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          // Status filter
          _buildFilterDropdown<AssetStatus>(
            label: 'Trạng thái',
            value: _statusFilter,
            items: AssetStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(getAssetStatusLabel(s), style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) {
              setState(() { _statusFilter = v; _currentPage = 1; });
              _loadAssets();
            },
          ),
          // Type filter
          _buildFilterDropdown<AssetType>(
            label: 'Loại tài sản',
            value: _typeFilter,
            items: AssetType.values.map((t) => DropdownMenuItem(value: t, child: Text(getAssetTypeLabel(t), style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) {
              setState(() { _typeFilter = v; _currentPage = 1; });
              _loadAssets();
            },
          ),
          // Category filter
          _buildFilterDropdown<String>(
            label: 'Danh mục',
            value: _categoryFilter,
            items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) {
              setState(() { _categoryFilter = v; _currentPage = 1; });
              _loadAssets();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: value != null ? const Color(0xFF1E3A5F) : const Color(0xFFE4E4E7)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFFA1A1AA))),
          items: [
            DropdownMenuItem<T>(value: null, child: Text('Tất cả $label', style: const TextStyle(fontSize: 13))),
            ...items,
          ],
          onChanged: onChanged,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
        ),
      ),
    );
  }

  // ==================== ASSET TABLE ====================
  Widget _buildAssetTable() {
    if (_assets.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Chưa có tài sản',
        description: 'Nhấn "Thêm tài sản" để bắt đầu',
      );
    }

    if (Responsive.isMobile(context)) {
      return _buildMobileAssetList();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          child: _buildDataTable(),
        ),
      ),
    );
  }

  Widget _buildMobileAssetList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
      itemCount: _assets.length,
      itemBuilder: (context, index) {
        final asset = _assets[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _showAssetDetail(asset),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Name + Actions
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          asset.name,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF18181B)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _buildRowActions(asset),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Row 2: Code + Status
                  Row(
                    children: [
                      Icon(Icons.qr_code_2, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        asset.assetCode,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 10),
                      _buildStatusBadge(asset.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Row 3: Quantity + Price
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        _mobileInfoChip(Icons.inventory_2_outlined, 'SL: ${asset.quantity}${" ${asset.unit}"}'),
                        const SizedBox(width: 16),
                        _mobileInfoChip(Icons.payments_outlined, _currencyFormat.format(asset.purchasePrice)),
                        if (asset.currentAssigneeName != null) ...[
                          const Spacer(),
                          Icon(Icons.person_outline, size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              asset.currentAssigneeName!,
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Row 4: Type + Brand (if present)
                  if (asset.brand != null || asset.model != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E3A5F).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(getAssetTypeLabel(asset.assetType), style: const TextStyle(fontSize: 10, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w500)),
                          ),
                          if (asset.brand != null) ...[
                            const SizedBox(width: 6),
                            Text(asset.brand!, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          ],
                          if (asset.model != null) ...[
                            const SizedBox(width: 4),
                            Text('· ${asset.model}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _mobileInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey[800])),
      ],
    );
  }

  Widget _buildDataTable() {
    return DataTable(
      headingRowColor: WidgetStateProperty.all(const Color(0xFFFAFAFA)),
      headingTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF71717A)),
      dataTextStyle: const TextStyle(fontSize: 13, color: Color(0xFF18181B)),
      columnSpacing: 16,
      horizontalMargin: 16,
      showCheckboxColumn: true,
      columns: const [
        DataColumn(label: Expanded(child: Text('MÃ TÀI SẢN', textAlign: TextAlign.center))),
        DataColumn(label: Expanded(child: Text('TÊN TÀI SẢN', textAlign: TextAlign.center))),
        DataColumn(label: Expanded(child: Text('LOẠI', textAlign: TextAlign.center))),
        DataColumn(label: Expanded(child: Text('TRẠNG THÁI', textAlign: TextAlign.center))),
        DataColumn(label: Expanded(child: Text('NGƯỜI DÙNG', textAlign: TextAlign.center))),
        DataColumn(label: Expanded(child: Text('GIÁ TRỊ', textAlign: TextAlign.center))),
        DataColumn(label: Expanded(child: Text('SỐ LƯỢNG', textAlign: TextAlign.center))),
        DataColumn(label: Expanded(child: Text('', textAlign: TextAlign.center))),
      ],
      rows: _assets.map((asset) => _buildAssetRow(asset)).toList(),
    );
  }

  DataRow _buildAssetRow(Asset asset) {
    final isSelected = _selectedAssetIds.contains(asset.id);
    return DataRow(
      selected: isSelected,
      onSelectChanged: (selected) {
        setState(() {
          if (selected == true) {
            _selectedAssetIds.add(asset.id);
          } else {
            _selectedAssetIds.remove(asset.id);
          }
        });
      },
      cells: [
        // Asset code
        DataCell(Center(
          child: InkWell(
            onTap: () => _showAssetDetail(asset),
            child: Text(asset.assetCode, style: const TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        )),
        // Name + serial
        DataCell(Center(
          child: InkWell(
            onTap: () => _showAssetDetail(asset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(asset.name, style: const TextStyle(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                if (asset.serialNumber != null)
                  Text('S/N: ${asset.serialNumber}', style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
              ],
            ),
          ),
        )),
        // Type
        DataCell(Center(child: Text(getAssetTypeLabel(asset.assetType), style: const TextStyle(fontSize: 12)))),
        // Status
        DataCell(Center(child: _buildStatusBadge(asset.status))),
        // Assignee
        DataCell(Center(
          child: asset.currentAssigneeName != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.15),
                      child: Text(
                        asset.currentAssigneeName![0].toUpperCase(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E3A5F)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(child: Text(asset.currentAssigneeName!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                  ],
                )
              : const Text('—', style: TextStyle(color: Color(0xFFCBD5E1))),
        )),
        // Price
        DataCell(Center(child: Text(_currencyFormat.format(asset.purchasePrice), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)))),
        // Quantity
        DataCell(Center(child: Text('${asset.quantity}', style: const TextStyle(fontSize: 12)))),
        // Actions
        DataCell(Center(child: _buildRowActions(asset))),
      ],
    );
  }

  Widget _buildStatusBadge(AssetStatus status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        getAssetStatusLabel(status),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildRowActions(Asset asset) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (asset.warrantyExpiringSoon)
          Tooltip(
            message: 'Sắp hết bảo hành',
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.warning_amber, size: 14, color: Color(0xFFF59E0B)),
            ),
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz, size: 20, color: Color(0xFFA1A1AA)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          itemBuilder: (context) => [
            _buildPopupItem('view', Icons.visibility_outlined, 'Xem chi tiết'),
            if (Provider.of<PermissionProvider>(context, listen: false).canEdit('Asset'))
            _buildPopupItem('edit', Icons.edit_outlined, 'Chỉnh sửa'),
            const PopupMenuDivider(),
            if (asset.currentAssigneeId == null)
              _buildPopupItem('assign', Icons.person_add_outlined, 'Cấp phát'),
            if (asset.currentAssigneeId != null) ...[
              _buildPopupItem('transfer', Icons.swap_horiz, 'Chuyển giao'),
              _buildPopupItem('return', Icons.keyboard_return, 'Thu hồi'),
            ],
            const PopupMenuDivider(),
            if (Provider.of<PermissionProvider>(context, listen: false).canDelete('Asset'))
            _buildPopupItem('delete', Icons.delete_outline, 'Xóa', isDestructive: true),
          ],
          onSelected: (value) => _handleAssetAction(asset, value),
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, IconData icon, String label, {bool isDestructive = false}) {
    final color = isDestructive ? const Color(0xFFEF4444) : const Color(0xFF52525B);
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }

  // ==================== PAGINATION ====================
  Widget _buildPagination() {
    final totalPages = (_totalAssets / _pageSize).ceil();
    if (totalPages <= 1 && _totalAssets <= _pageSize) return const SizedBox(height: 8);

    final start = _totalAssets > 0 ? ((_currentPage - 1) * _pageSize) + 1 : 0;
    final end = (_currentPage * _pageSize).clamp(0, _totalAssets);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            'Hiển thị $start-$end / $_totalAssets',
            style: const TextStyle(fontSize: 12, color: Color(0xFFA1A1AA)),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Hiển thị:', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(width: 8),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _pageSize,
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    items: _pageSizeOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() { _pageSize = v; _currentPage = 1; });
                        _loadAssets();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPageButton(Icons.chevron_left, _currentPage > 1, () {
                setState(() => _currentPage--);
                _loadAssets();
              }),
              const SizedBox(width: 8),
              Text('$_currentPage / $totalPages', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              _buildPageButton(Icons.chevron_right, _currentPage < totalPages, () {
                setState(() => _currentPage++);
                _loadAssets();
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageButton(IconData icon, bool enabled, VoidCallback onTap) {
    return Material(
      color: enabled ? Colors.white : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE4E4E7)),
          ),
          child: Icon(icon, size: 18, color: enabled ? const Color(0xFF52525B) : const Color(0xFFCBD5E1)),
        ),
      ),
    );
  }

  // ==================== SIDE PANELS ====================
  Widget _buildTransfersPanel() {
    return Container(
      width: Responsive.isMobile(context) ? double.infinity : 380,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Column(
        children: [
          _buildPanelHeader('Lịch sử chuyển giao', Icons.swap_horiz, () => setState(() => _showTransfers = false)),
          Expanded(
            child: _transfers.isEmpty
                ? const Center(child: Text('Chưa có dữ liệu', style: TextStyle(color: Color(0xFFA1A1AA))))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _transfers.length,
                    itemBuilder: (context, index) => _buildTransferItem(_transfers[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesPanel() {
    return Container(
      width: Responsive.isMobile(context) ? double.infinity : 350,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Column(
        children: [
          _buildPanelHeader('Danh mục', Icons.category, () => setState(() => _showCategories = false),
            action: IconButton(
              icon: const Icon(Icons.add, size: 20, color: Color(0xFF1E3A5F)),
              onPressed: () => _showCategoryDialog(),
              tooltip: 'Thêm danh mục',
            ),
          ),
          Expanded(
            child: _categories.isEmpty
                ? const Center(child: Text('Chưa có danh mục', style: TextStyle(color: Color(0xFFA1A1AA))))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) => _buildCategoryItem(_categories[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoriesPanel() {
    return Container(
      width: Responsive.isMobile(context) ? double.infinity : 380,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Column(
        children: [
          _buildPanelHeader('Kiểm kê', Icons.checklist, () => setState(() => _showInventories = false),
            action: IconButton(
              icon: const Icon(Icons.add, size: 20, color: Color(0xFF1E3A5F)),
              onPressed: () => _showInventoryDialog(),
              tooltip: 'Tạo đợt kiểm kê',
            ),
          ),
          Expanded(
            child: _inventories.isEmpty
                ? const Center(child: Text('Chưa có đợt kiểm kê', style: TextStyle(color: Color(0xFFA1A1AA))))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _inventories.length,
                    itemBuilder: (context, index) => _buildInventoryItem(_inventories[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader(String title, IconData icon, VoidCallback onClose, {Widget? action}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF1E3A5F)),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF18181B))),
          const Spacer(),
          if (action != null) action,
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClose, color: const Color(0xFFA1A1AA)),
        ],
      ),
    );
  }

  Widget _buildTransferItem(AssetTransfer transfer) {
    final color = _getTransferTypeColor(transfer.transferType);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        color: const Color(0xFFFAFBFC),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Icon(_getTransferTypeIcon(transfer.transferType), size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(transfer.assetName ?? 'Tài sản', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
              ),
              if (!transfer.isConfirmed)
                InkWell(
                  onTap: () => _confirmTransfer(transfer),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Xác nhận', style: TextStyle(fontSize: 11, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600)),
                  ),
                )
              else
                const Icon(Icons.check_circle, size: 16, color: Color(0xFF1E3A5F)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(getTransferTypeLabel(transfer.transferType), style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(DateFormat('dd/MM/yyyy').format(transfer.transferDate), style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
            ],
          ),
          if (transfer.fromUserName != null || transfer.toUserName != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (transfer.fromUserName != null) Text(transfer.fromUserName!, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                  if (transfer.fromUserName != null && transfer.toUserName != null)
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.arrow_forward, size: 12, color: Color(0xFFCBD5E1))),
                  if (transfer.toUserName != null) Text(transfer.toUserName!, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(AssetCategory category, {int level = 0}) {
    return Column(
      children: [
        Container(
          margin: EdgeInsets.only(left: level * 16.0, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFFFAFBFC),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Row(
            children: [
              Icon(level > 0 ? Icons.subdirectory_arrow_right : Icons.folder, size: 16, color: const Color(0xFF1E3A5F)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    Text('${category.categoryCode} • ${category.assetCount} TS', style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                  ],
                ),
              ),
              if (!category.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                  child: const Text('Ẩn', style: TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 16, color: Color(0xFFA1A1AA)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                itemBuilder: (context) => [
                  if (Provider.of<PermissionProvider>(context, listen: false).canEdit('Asset'))
                  _buildPopupItem('edit', Icons.edit_outlined, 'Sửa'),
                  if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Asset'))
                  _buildPopupItem('add_sub', Icons.add, 'Thêm danh mục con'),
                  const PopupMenuDivider(),
                  if (Provider.of<PermissionProvider>(context, listen: false).canDelete('Asset'))
                  _buildPopupItem('delete', Icons.delete_outline, 'Xóa', isDestructive: true),
                ],
                onSelected: (value) => _handleCategoryAction(category, value),
              ),
            ],
          ),
        ),
        if (category.subCategories != null)
          ...category.subCategories!.map((sub) => _buildCategoryItem(sub, level: level + 1)),
      ],
    );
  }

  Widget _buildInventoryItem(AssetInventory inventory) {
    final isInProgress = inventory.isInProgress;
    final isCompleted = inventory.isCompleted;
    final statusColor = isInProgress ? const Color(0xFF3B82F6) : isCompleted ? const Color(0xFF059669) : const Color(0xFFEF4444);
    final statusIcon = isInProgress ? Icons.hourglass_top : isCompleted ? Icons.check_circle : Icons.cancel;
    final statusLabel = inventory.statusName.isNotEmpty ? inventory.statusName : (isInProgress ? 'Đang thực hiện' : isCompleted ? 'Hoàn thành' : 'Đã hủy');
    final progress = inventory.progressPercent / 100;
    final dateStr = DateFormat('dd/MM/yyyy').format(inventory.startDate);

    return InkWell(
      onTap: () => _showInventoryDetailDialog(inventory),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor.withValues(alpha: 0.15)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            // Top colored accent bar
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(statusIcon, size: 18, color: statusColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(inventory.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF18181B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.tag, size: 11, color: Colors.grey.shade400),
                                const SizedBox(width: 3),
                                Text(inventory.inventoryCode, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                                const SizedBox(width: 10),
                                Icon(Icons.calendar_today_outlined, size: 11, color: Colors.grey.shade400),
                                const SizedBox(width: 3),
                                Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade400),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'detail', child: Row(children: [Icon(Icons.open_in_new, size: 16, color: Color(0xFF3B82F6)), SizedBox(width: 8), Text('Xem chi tiết')])),
                          if (isInProgress)
                            const PopupMenuItem(value: 'cancel', child: Row(children: [Icon(Icons.block, size: 16, color: Color(0xFFF59E0B)), SizedBox(width: 8), Text('Hủy kiểm kê', style: TextStyle(color: Color(0xFFF59E0B)))])),
                          const PopupMenuDivider(),
                          const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)), SizedBox(width: 8), Text('Xóa', style: TextStyle(color: Color(0xFFEF4444)))])),
                        ],
                        onSelected: (value) => _handleInventoryAction(inventory, value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Progress bar
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: const Color(0xFFE4E4E7),
                            valueColor: AlwaysStoppedAnimation(statusColor),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('${inventory.progressPercent.toStringAsFixed(0)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: statusColor)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Bottom stats row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                        child: Text(statusLabel, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFF4F4F5), borderRadius: BorderRadius.circular(6)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check, size: 12, color: Color(0xFF64748B)),
                            const SizedBox(width: 3),
                            Text('${inventory.checkedCount}/${inventory.totalAssets}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                      if (inventory.issueCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber, size: 12, color: Color(0xFFF59E0B)),
                              const SizedBox(width: 3),
                              Text('${inventory.issueCount}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFF59E0B))),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (isInProgress)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3A5F),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow, size: 12, color: Colors.white),
                              SizedBox(width: 2),
                              Text('Tiếp tục', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Colors ====================
  Color _getStatusColor(AssetStatus status) {
    switch (status) {
      case AssetStatus.active: return const Color(0xFF1E3A5F);
      case AssetStatus.inMaintenance: return const Color(0xFFF59E0B);
      case AssetStatus.broken: return const Color(0xFFEF4444);
      case AssetStatus.disposed: return const Color(0xFFA1A1AA);
      case AssetStatus.lost: return const Color(0xFF0F2340);
      case AssetStatus.inStock: return const Color(0xFF1E3A5F);
    }
  }

  Color _getTransferTypeColor(AssetTransferType type) {
    switch (type) {
      case AssetTransferType.assignment: return const Color(0xFF1E3A5F);
      case AssetTransferType.transfer: return const Color(0xFFF59E0B);
      case AssetTransferType.returnAsset: return const Color(0xFF1E3A5F);
      case AssetTransferType.maintenance: return const Color(0xFF0F2340);
      case AssetTransferType.disposal: return const Color(0xFFEF4444);
    }
  }

  IconData _getTransferTypeIcon(AssetTransferType type) {
    switch (type) {
      case AssetTransferType.assignment: return Icons.person_add;
      case AssetTransferType.transfer: return Icons.swap_horiz;
      case AssetTransferType.returnAsset: return Icons.keyboard_return;
      case AssetTransferType.maintenance: return Icons.build;
      case AssetTransferType.disposal: return Icons.delete_forever;
    }
  }

  // ==================== DIALOGS ====================
  void _showAssetDialog({Asset? asset}) {
    final isEdit = asset != null;
    final codeCtrl = TextEditingController(text: asset?.assetCode ?? '');
    final nameCtrl = TextEditingController(text: asset?.name ?? '');
    final descCtrl = TextEditingController(text: asset?.description ?? '');
    final serialCtrl = TextEditingController(text: asset?.serialNumber ?? '');
    final modelCtrl = TextEditingController(text: asset?.model ?? '');
    final brandCtrl = TextEditingController(text: asset?.brand ?? '');
    final sizeCtrl = TextEditingController(text: asset?.size ?? '');
    final colorCtrl = TextEditingController(text: asset?.color ?? '');
    final priceCtrl = TextEditingController(text: formatNumber(asset?.purchasePrice));
    final qtyCtrl = TextEditingController(text: asset?.quantity.toString() ?? '1');
    final unitCtrl = TextEditingController(text: asset?.unit ?? 'Cái');
    final locationCtrl = TextEditingController(text: asset?.location ?? '');
    final notesCtrl = TextEditingController(text: asset?.notes ?? '');
    final supplierCtrl = TextEditingController(text: asset?.supplier ?? '');
    final invoiceCtrl = TextEditingController(text: asset?.invoiceNumber ?? '');
    final warrantyCtrl = TextEditingController(text: asset?.warrantyMonths?.toString() ?? '');

    AssetType selectedType = asset?.assetType ?? AssetType.electronics;
    AssetStatus selectedStatus = asset?.status ?? AssetStatus.inStock;
    String? selectedCategory = asset?.categoryId;
    DateTime? purchaseDate = asset?.purchaseDate;
    List<_PickedImage> pickedImages = [];

    void scanQrForField(TextEditingController ctrl, StateSetter setDialogState) {
      showDialog(
        context: context,
        builder: (_) => _AssetQrScanDialog(
          onAssetScanned: (code) {
            Navigator.pop(context);
            setDialogState(() => ctrl.text = code);
          },
        ),
      );
    }

    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget qrField(String label, TextEditingController ctrl) {
            return Row(children: [
              Expanded(child: _dialogField(label, ctrl)),
              const SizedBox(width: 6),
              Material(
                color: const Color(0xFF1E3A5F).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => scanQrForField(ctrl, setDialogState),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 44, height: 44,
                    alignment: Alignment.center,
                    child: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF1E3A5F), size: 22),
                  ),
                ),
              ),
            ]);
          }
          final formContent = SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Basic info
                        const Text('Thông tin cơ bản', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF52525B))),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: qrField('Mã tài sản *', codeCtrl)),
                          const SizedBox(width: 16),
                          Expanded(child: qrField('Số Serial', serialCtrl)),
                        ]),
                        const SizedBox(height: 12),
                        _dialogField('Tên tài sản *', nameCtrl),
                        const SizedBox(height: 12),
                        _dialogField('Mô tả', descCtrl, maxLines: 2),
                        const SizedBox(height: 20),

                        // Classification
                        const Text('Phân loại', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF52525B))),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: _dialogField('Model', modelCtrl)),
                          const SizedBox(width: 16),
                          Expanded(child: _dialogField('Thương hiệu', brandCtrl)),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: _dialogField('Size / Kích thước', sizeCtrl)),
                          const SizedBox(width: 16),
                          Expanded(child: _dialogField('Màu sắc', colorCtrl)),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: _dialogDropdown<AssetType>('Loại tài sản', selectedType,
                              AssetType.values.map((t) => DropdownMenuItem(value: t, child: Text(getAssetTypeLabel(t)))).toList(),
                              (v) => setDialogState(() => selectedType = v!),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _dialogDropdown<String?>('Danh mục', selectedCategory,
                              [const DropdownMenuItem(value: null, child: Text('Không')),
                               ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))],
                              (v) => setDialogState(() => selectedCategory = v),
                            ),
                          ),
                        ]),
                        if (isEdit) ...[
                          const SizedBox(height: 12),
                          _dialogDropdown<AssetStatus>('Trạng thái', selectedStatus,
                            AssetStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(getAssetStatusLabel(s)))).toList(),
                            (v) => setDialogState(() => selectedStatus = v!),
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Financial
                        const Text('Tài chính & Mua sắm', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF52525B))),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(flex: 2, child: _dialogField('Giá mua *', priceCtrl, inputType: TextInputType.number, suffix: 'VND')),
                          const SizedBox(width: 16),
                          Expanded(child: _dialogField('Số lượng', qtyCtrl, inputType: TextInputType.number)),
                          const SizedBox(width: 16),
                          Expanded(child: _dialogField('Đơn vị', unitCtrl)),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: _dialogField('Nhà cung cấp', supplierCtrl)),
                          const SizedBox(width: 16),
                          Expanded(child: _dialogField('Số hóa đơn', invoiceCtrl)),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: purchaseDate ?? DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime.now(),
                                );
                                if (date != null) setDialogState(() => purchaseDate = date);
                              },
                              child: InputDecorator(
                                decoration: _dialogDecoration('Ngày mua'),
                                child: Text(
                                  purchaseDate != null ? DateFormat('dd/MM/yyyy').format(purchaseDate!) : 'Chọn ngày',
                                  style: TextStyle(color: purchaseDate != null ? const Color(0xFF18181B) : const Color(0xFFA1A1AA)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: _dialogField('Bảo hành (tháng)', warrantyCtrl, inputType: TextInputType.number)),
                        ]),
                        const SizedBox(height: 12),
                        _dialogField('Vị trí', locationCtrl),
                        const SizedBox(height: 12),
                        _dialogField('Ghi chú', notesCtrl, maxLines: 2),
                        const SizedBox(height: 20),

                        // Images
                        const Text('Hình ảnh sản phẩm', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF52525B))),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            ...pickedImages.asMap().entries.map((entry) => Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(entry.value.bytes, width: 80, height: 80, fit: BoxFit.cover),
                                ),
                                Positioned(top: 2, right: 2, child: GestureDetector(
                                  onTap: () => setDialogState(() => pickedImages.removeAt(entry.key)),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                                  ),
                                )),
                              ],
                            )),
                            GestureDetector(
                              onTap: () async {
                                final source = await showModalBottomSheet<ImageSource>(
                                  context: context,
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                                  builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Chụp ảnh'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
                                    ListTile(leading: const Icon(Icons.photo_library), title: const Text('Chọn từ thư viện'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
                                  ])),
                                );
                                if (source == null) return;
                                final picker = ImagePicker();
                                final photo = await picker.pickImage(source: source, maxWidth: 1920, maxHeight: 1920, imageQuality: 80);
                                if (photo != null) {
                                  final bytes = await photo.readAsBytes();
                                  setDialogState(() => pickedImages.add(_PickedImage(Uint8List.fromList(bytes), photo.name)));
                                }
                              },
                              child: Container(
                                width: 80, height: 80,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFD4D4D8), style: BorderStyle.solid),
                                  color: const Color(0xFFF4F4F5),
                                ),
                                child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(Icons.add_photo_alternate, color: Color(0xFF71717A), size: 24),
                                  SizedBox(height: 4),
                                  Text('Thêm ảnh', style: TextStyle(fontSize: 10, color: Color(0xFF71717A))),
                                ]),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
          final actionButtons = Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => _saveAsset(
                          context, isEdit: isEdit, assetId: asset?.id,
                          code: codeCtrl.text, name: nameCtrl.text, description: descCtrl.text,
                          serial: serialCtrl.text, model: modelCtrl.text, brand: brandCtrl.text,
                          size: sizeCtrl.text, color: colorCtrl.text,
                          price: priceCtrl.text, quantity: qtyCtrl.text, unit: unitCtrl.text,
                          supplier: supplierCtrl.text, invoice: invoiceCtrl.text,
                          warranty: warrantyCtrl.text, location: locationCtrl.text, notes: notesCtrl.text,
                          type: selectedType, status: selectedStatus, categoryId: selectedCategory,
                          purchaseDate: purchaseDate, images: pickedImages,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A5F),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(isEdit ? 'Cập nhật' : 'Thêm mới'),
                      ),
                    ],
            ),
          );
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(isEdit ? 'Chỉnh sửa tài sản' : 'Thêm tài sản mới'),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ),
                  body: formContent,
                  bottomNavigationBar: actionButtons,
                ),
              ),
            );
          }
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.6,
              constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
                    ),
                    child: Row(
                      children: [
                        Icon(isEdit ? Icons.edit : Icons.add_circle, color: const Color(0xFF1E3A5F)),
                        const SizedBox(width: 10),
                        Text(isEdit ? 'Chỉnh sửa tài sản' : 'Thêm tài sản mới', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ),
                  Flexible(child: formContent),
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
                    ),
                    child: actionButtons,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      codeCtrl.dispose();
      nameCtrl.dispose();
      descCtrl.dispose();
      serialCtrl.dispose();
      modelCtrl.dispose();
      brandCtrl.dispose();
      priceCtrl.dispose();
      qtyCtrl.dispose();
      unitCtrl.dispose();
      locationCtrl.dispose();
      notesCtrl.dispose();
      supplierCtrl.dispose();
      invoiceCtrl.dispose();
      warrantyCtrl.dispose();
    });
  }

  Future<void> _saveAsset(BuildContext dialogContext, {
    required bool isEdit, String? assetId,
    required String code, required String name, String? description,
    String? serial, String? model, String? brand,
    String? size, String? color,
    required String price, required String quantity, required String unit,
    String? supplier, String? invoice, String? warranty, String? location, String? notes,
    required AssetType type, required AssetStatus status, String? categoryId,
    DateTime? purchaseDate, List<_PickedImage>? images,
  }) async {
    if (code.isEmpty || name.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập mã và tên tài sản');
      return;
    }

    Map<String, dynamic> result;
    if (isEdit && assetId != null) {
      result = await _apiService.updateAsset(
        assetId,
        assetCode: code, name: name,
        description: description?.isNotEmpty == true ? description : null,
        serialNumber: serial?.isNotEmpty == true ? serial : null,
        model: model?.isNotEmpty == true ? model : null,
        brand: brand?.isNotEmpty == true ? brand : null,
        size: size?.isNotEmpty == true ? size : null,
        color: color?.isNotEmpty == true ? color : null,
        assetType: type.index, categoryId: categoryId, status: status.index,
        quantity: int.tryParse(quantity) ?? 1, unit: unit,
        purchasePrice: parseFormattedNumber(price)?.toDouble() ?? 0, purchaseDate: purchaseDate,
        supplier: supplier?.isNotEmpty == true ? supplier : null,
        invoiceNumber: invoice?.isNotEmpty == true ? invoice : null,
        warrantyMonths: int.tryParse(warranty ?? ''),
        location: location?.isNotEmpty == true ? location : null,
        notes: notes?.isNotEmpty == true ? notes : null,
      );
    } else {
      result = await _apiService.createAsset(
        assetCode: code, name: name,
        description: description?.isNotEmpty == true ? description : null,
        serialNumber: serial?.isNotEmpty == true ? serial : null,
        model: model?.isNotEmpty == true ? model : null,
        brand: brand?.isNotEmpty == true ? brand : null,
        size: size?.isNotEmpty == true ? size : null,
        color: color?.isNotEmpty == true ? color : null,
        assetType: type.index, categoryId: categoryId,
        quantity: int.tryParse(quantity) ?? 1, unit: unit,
        purchasePrice: parseFormattedNumber(price)?.toDouble() ?? 0, purchaseDate: purchaseDate,
        supplier: supplier?.isNotEmpty == true ? supplier : null,
        invoiceNumber: invoice?.isNotEmpty == true ? invoice : null,
        warrantyMonths: int.tryParse(warranty ?? ''),
        location: location?.isNotEmpty == true ? location : null,
        notes: notes?.isNotEmpty == true ? notes : null,
      );
    }

    if (!mounted) return;
    if (dialogContext.mounted) Navigator.pop(dialogContext);
    if (result['isSuccess'] == true) {
      // Upload images if any
      final savedAssetId = assetId ?? result['data']?['id']?.toString();
      if (savedAssetId != null && images != null && images.isNotEmpty) {
        for (int i = 0; i < images.length; i++) {
          final img = images[i];
          final uploadResult = await _apiService.uploadFile(img.bytes.toList(), img.name, folder: 'assets');
          if (uploadResult['isSuccess'] == true && uploadResult['data'] != null) {
            final fileUrl = uploadResult['data']['fileUrl'];
            await _apiService.addAssetImage(
              assetId: savedAssetId,
              imageUrl: fileUrl,
              fileName: img.name,
              isPrimary: i == 0,
            );
          }
        }
      }
      NotificationOverlayManager().showSuccess(title: 'Thành công', message: isEdit ? 'Đã cập nhật tài sản' : 'Đã thêm tài sản mới');
      _loadAssets();
      _loadStatistics();
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
    }
  }

  void _showAssetDetail(Asset asset) {
    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (context) {
        final bodyContent = SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailSection('Thông tin chung', [
                        if (asset.qrCode != null && asset.qrCode != asset.assetCode) _detailRow('Mã QR', asset.qrCode!),
                        _detailRow('Loại', getAssetTypeLabel(asset.assetType)),
                        if (asset.categoryName != null) _detailRow('Danh mục', asset.categoryName!),
                        if (asset.serialNumber != null) _detailRow('Số Serial', asset.serialNumber!),
                        if (asset.model != null) _detailRow('Model', asset.model!),
                        if (asset.brand != null) _detailRow('Thương hiệu', asset.brand!),
                        if (asset.size != null) _detailRow('Size / Kích thước', asset.size!),
                        if (asset.color != null) _detailRow('Màu sắc', asset.color!),
                        _detailRow('Số lượng', '${asset.quantity} ${asset.unit}'),
                        if (asset.location != null) _detailRow('Vị trí', asset.location!),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection('Tài chính', [
                        _detailRow('Giá mua', _currencyFormat.format(asset.purchasePrice)),
                        if (asset.currentValue != null) _detailRow('Giá trị hiện tại', _currencyFormat.format(asset.currentValue)),
                        if (asset.purchaseDate != null) _detailRow('Ngày mua', DateFormat('dd/MM/yyyy').format(asset.purchaseDate!)),
                        if (asset.supplier != null) _detailRow('Nhà cung cấp', asset.supplier!),
                        if (asset.invoiceNumber != null) _detailRow('Số hóa đơn', asset.invoiceNumber!),
                      ]),
                      if (asset.warrantyMonths != null) ...[
                        const SizedBox(height: 16),
                        _detailSection('Bảo hành', [
                          _detailRow('Thời hạn', '${asset.warrantyMonths} tháng'),
                          if (asset.warrantyExpiry != null)
                            _detailRow(
                              'Hết hạn',
                              DateFormat('dd/MM/yyyy').format(asset.warrantyExpiry!),
                              valueColor: asset.isWarrantyExpired ? const Color(0xFFEF4444) : asset.warrantyExpiringSoon ? const Color(0xFFF59E0B) : null,
                            ),
                        ]),
                      ],
                      if (asset.currentAssigneeName != null) ...[
                        const SizedBox(height: 16),
                        _detailSection('Người sử dụng', [
                          _detailRow('Tên', asset.currentAssigneeName!),
                          if (asset.assignedDate != null) _detailRow('Từ ngày', DateFormat('dd/MM/yyyy').format(asset.assignedDate!)),
                        ]),
                      ],
                      if (asset.notes != null && asset.notes!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _detailSection('Ghi chú', [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(asset.notes!, style: const TextStyle(color: Color(0xFF52525B), fontSize: 13)),
                          ),
                        ]),
                      ],
                      const SizedBox(height: 16),
                      // Inventory history section
                      FutureBuilder<Map<String, dynamic>>(
                        future: _apiService.getAssetInventoryHistory(asset.id),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return _detailSection('Lịch sử kiểm kê', [
                              const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
                            ]);
                          }
                          final data = snapshot.data;
                          if (data == null || data['isSuccess'] != true) {
                            return const SizedBox.shrink();
                          }
                          final history = data['data'] as List? ?? [];
                          if (history.isEmpty) {
                            return _detailSection('Lịch sử kiểm kê', [
                              const Padding(padding: EdgeInsets.all(8), child: Text('Chưa có lần kiểm kê nào', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 13))),
                            ]);
                          }
                          return _detailSection('Lịch sử kiểm kê (${history.length})', history.map<Widget>((h) {
                            final date = h['inventoryDate'] != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(h['inventoryDate'])) : '';
                            final invStatus = h['inventoryStatus'] ?? 0;
                            final expected = h['expectedQuantity'] ?? 0;
                            final actual = h['actualQuantity'] ?? expected;
                            final diff = h['diff'] ?? (actual - expected);
                            final isChecked = h['isChecked'] ?? false;
                            final statusColor = invStatus == 1 ? const Color(0xFF22C55E) : invStatus == 2 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
                            final statusLabel = h['inventoryStatusName'] ?? (invStatus == 1 ? 'Hoàn thành' : invStatus == 2 ? 'Đã hủy' : 'Đang kiểm');
                            return InkWell(
                              onTap: () {
                                // Open inventory detail when tapped
                                final invId = h['inventoryId'];
                                if (invId != null) {
                                  Navigator.pop(context);
                                  _showInventoryDetailDialog(AssetInventory(
                                    id: invId,
                                    inventoryCode: h['inventoryCode'] ?? '',
                                    name: h['inventoryName'] ?? '',
                                    startDate: h['inventoryDate'] != null ? DateTime.parse(h['inventoryDate']) : DateTime.now(),
                                    createdAt: DateTime.now(),
                                    status: invStatus,
                                  ));
                                }
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE4E4E7))),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(child: Text(h['inventoryName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                      child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
                                    ),
                                  ]),
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    Text(date, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                                    if (!isChecked) ...[
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('Chưa kiểm', style: TextStyle(fontSize: 10, color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                    if (isChecked) ...[
                                      const Spacer(),
                                      Text('TK: $expected', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                      const SizedBox(width: 8),
                                      Text('TT: $actual', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 8),
                                      Text('CL: ${diff > 0 ? "+$diff" : "$diff"}',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: diff < 0 ? const Color(0xFFEF4444) : diff > 0 ? const Color(0xFF22C55E) : const Color(0xFF71717A))),
                                    ],
                                  ]),
                                  if (h['hasIssue'] == true && h['issueDescription'] != null && h['issueDescription'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text('Vấn đề: ${h['issueDescription']}', style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
                                  ],
                                ]),
                              ),
                            );
                          }).toList());
                        },
                      ),
                    ],
                  ),
        );
        final actionButtons = Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () { Navigator.pop(context); _showAssetDialog(asset: asset); },
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Sửa'),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF52525B)),
                    ),
                    const Spacer(),
                    if (asset.currentAssigneeId == null)
                      ElevatedButton.icon(
                        onPressed: () { Navigator.pop(context); _showAssignDialog(asset); },
                        icon: const Icon(Icons.person_add, size: 16),
                        label: const Text('Cấp phát'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white),
                      ),
                    if (asset.currentAssigneeId != null) ...[
                      OutlinedButton.icon(
                        onPressed: () { Navigator.pop(context); _showTransferDialog(asset); },
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: const Text('Chuyển giao'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () { Navigator.pop(context); _showReturnDialog(asset); },
                        icon: const Icon(Icons.keyboard_return, size: 16),
                        label: const Text('Thu hồi'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white),
                      ),
                    ],
                  ],
          ),
        );
        if (isMobile) {
          return Dialog(
            insetPadding: EdgeInsets.zero,
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Scaffold(
                appBar: AppBar(
                  title: Text(asset.name),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ),
                body: bodyContent,
                bottomNavigationBar: actionButtons,
              ),
            ),
          );
        }
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: math.min(600, MediaQuery.of(context).size.width - 32).toDouble(),
            constraints: const BoxConstraints(maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.inventory_2, color: Color(0xFF1E3A5F)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(asset.assetCode, style: const TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(width: 8),
                              _buildStatusBadge(asset.status),
                            ]),
                            const SizedBox(height: 4),
                            Text(asset.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF18181B))),
                          ],
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                Flexible(child: bodyContent),
                Container(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE4E4E7)))),
                  child: actionButtons,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF52525B))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13))),
          Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: valueColor ?? const Color(0xFF18181B)))),
        ],
      ),
    );
  }

  void _showCategoryDialog({AssetCategory? category, String? parentId}) {
    final isEdit = category != null;
    final codeCtrl = TextEditingController(text: category?.categoryCode ?? '');
    final nameCtrl = TextEditingController(text: category?.name ?? '');
    final descCtrl = TextEditingController(text: category?.description ?? '');

    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (context) {
        final formContent = SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMobile) ...[
                Text(isEdit ? 'Sửa danh mục' : 'Thêm danh mục mới', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
              ],
              _dialogField('Mã danh mục *', codeCtrl),
              const SizedBox(height: 12),
              _dialogField('Tên danh mục *', nameCtrl),
              const SizedBox(height: 12),
              _dialogField('Mô tả', descCtrl, maxLines: 2),
            ],
          ),
        );
        Future<Null> onSave() async {
                      if (codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) {
                        NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập mã và tên danh mục');
                        return;
                      }
                      Map<String, dynamic> result;
                      if (isEdit) {
                        result = await _apiService.updateAssetCategory(category.id, categoryCode: codeCtrl.text, name: nameCtrl.text, description: descCtrl.text.isNotEmpty ? descCtrl.text : null, parentCategoryId: category.parentCategoryId);
                      } else {
                        result = await _apiService.createAssetCategory(categoryCode: codeCtrl.text, name: nameCtrl.text, description: descCtrl.text.isNotEmpty ? descCtrl.text : null, parentCategoryId: parentId);
                      }
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      if (!mounted) return;
                      if (result['isSuccess'] == true) {
                        NotificationOverlayManager().showSuccess(title: 'Thành công', message: isEdit ? 'Đã cập nhật danh mục' : 'Đã thêm danh mục mới');
                        _loadCategories();
                      } else {
                        NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
                      }
        }
        final actionButtons = Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: onSave,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text(isEdit ? 'Cập nhật' : 'Thêm'),
                  ),
                ],
          ),
        );
        if (isMobile) {
          return Dialog(
            insetPadding: EdgeInsets.zero,
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Scaffold(
                appBar: AppBar(
                  title: Text(isEdit ? 'Sửa danh mục' : 'Thêm danh mục mới'),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ),
                body: formContent,
                bottomNavigationBar: actionButtons,
              ),
            ),
          );
        }
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: math.min(420, MediaQuery.of(context).size.width - 32).toDouble(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                formContent,
                actionButtons,
              ],
            ),
          ),
        );
      },
    ).then((_) {
      codeCtrl.dispose();
      nameCtrl.dispose();
      descCtrl.dispose();
    });
  }

  void _showInventoryDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    DateTime startDate = DateTime.now();
    DateTime? endDate;
    String? responsibleUserId;
    String searchText = '';
    // Track selected items with their expected quantities
    Map<String, int> itemQuantities = {}; // assetId -> expectedQty
    Map<String, int?> actualQuantities = {}; // assetId -> actual qty
    Map<String, String> itemNotes = {}; // assetId -> notes
    Map<String, Uint8List?> itemImages = {}; // assetId -> image bytes
    Map<String, String?> itemImageNames = {}; // assetId -> image filename
    Map<String, TextEditingController> actualQtyControllers = {};
    String? expandedItemId;
    int step = 0; // 0 = info, 1 = select items with qty
    bool isLoading = false;
    bool isCreating = false;
    List<Asset> allAssets = List.from(_assets);
    bool allLoaded = _assets.length >= _totalAssets;

    Future<void> loadAllAssets(StateSetter setDialogState) async {
      if (allLoaded || isLoading) return;
      setDialogState(() => isLoading = true);
      final result = await _apiService.getAssets(page: 1, pageSize: 9999);
      if (result['isSuccess'] == true && result['data'] != null) {
        final data = result['data'];
        final items = (data['items'] as List?)?.map((e) => Asset.fromJson(e)).toList() ?? [];
        allAssets = items;
        allLoaded = true;
      }
      setDialogState(() => isLoading = false);
    }

    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final displayAssets = allAssets.where((a) {
            if (searchText.isNotEmpty) {
              final q = searchText.toLowerCase();
              return (a.name.toLowerCase().contains(q)) ||
                  a.assetCode.toLowerCase().contains(q);
            }
            return true;
          }).toList();

          final selectedCount = itemQuantities.length;

          // Step 0: Basic info
          Widget buildInfoStep() {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dialogField('Tên đợt kiểm kê *', nameCtrl),
                  const SizedBox(height: 12),
                  _dialogField('Mô tả', descCtrl, maxLines: 2),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(context: context, initialDate: startDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                          if (date != null) setDialogState(() => startDate = date);
                        },
                        child: InputDecorator(
                          decoration: _dialogDecoration('Ngày bắt đầu *'),
                          child: Text(DateFormat('dd/MM/yyyy').format(startDate)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(context: context, initialDate: endDate ?? startDate.add(const Duration(days: 7)), firstDate: startDate, lastDate: DateTime.now().add(const Duration(days: 365)));
                          if (date != null) setDialogState(() => endDate = date);
                        },
                        child: InputDecorator(
                          decoration: _dialogDecoration('Ngày kết thúc'),
                          child: Text(endDate != null ? DateFormat('dd/MM/yyyy').format(endDate!) : 'Chọn ngày', style: TextStyle(color: endDate != null ? const Color(0xFF18181B) : const Color(0xFFA1A1AA))),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _dialogDropdown<String?>('Người phụ trách', responsibleUserId,
                    [const DropdownMenuItem(value: null, child: Text('Chọn người phụ trách')),
                     ..._employees.map((e) => DropdownMenuItem(value: e.id, child: Text(e.fullName)))],
                    (v) => setDialogState(() => responsibleUserId = v),
                  ),
                  const SizedBox(height: 12),
                  _dialogField('Ghi chú', notesCtrl, maxLines: 2),
                ],
              ),
            );
          }

          // Step 1: Select items with actual qty input
          Widget buildItemSelectStep() {
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Tìm hàng hóa...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: searchText.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { searchCtrl.clear(); setDialogState(() => searchText = ''); }) : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (v) => setDialogState(() => searchText = v),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => setDialogState(() {
                              if (itemQuantities.length == allAssets.length) {
                                itemQuantities.clear();
                                actualQuantities.clear();
                              } else {
                                for (final a in allAssets) {
                                  itemQuantities.putIfAbsent(a.id, () => a.quantity);
                                }
                              }
                            }),
                            child: Row(children: [
                              Icon(itemQuantities.length == allAssets.length ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: const Color(0xFF1E3A5F)),
                              const SizedBox(width: 6),
                              const Text('Chọn tất cả', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            ]),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: const Color(0xFF1E3A5F).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                            child: Text('Đã chọn: $selectedCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E3A5F))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                if (isLoading)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else
                  Expanded(
                    child: displayAssets.isEmpty
                        ? const Center(child: Text('Không tìm thấy hàng hóa', style: TextStyle(color: Color(0xFFA1A1AA))))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: displayAssets.length,
                            itemBuilder: (context, index) {
                              final asset = displayAssets[index];
                              final isSelected = itemQuantities.containsKey(asset.id);
                              final stockQty = asset.quantity;
                              final actualQty = actualQuantities[asset.id];
                              final hasActual = actualQty != null;
                              final diff = hasActual ? actualQty - stockQty : null;
                              final isExpanded = expandedItemId == asset.id;

                              if (!actualQtyControllers.containsKey(asset.id)) {
                                actualQtyControllers[asset.id] = TextEditingController(text: actualQty?.toString() ?? '');
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? (diff != null && diff < 0 ? const Color(0xFFFCA5A5) : const Color(0xFF93C5FD))
                                        : const Color(0xFFE4E4E7),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    // Main row: checkbox + info + stock badge
                                    Padding(
                                      padding: EdgeInsets.fromLTRB(10, 10, 10, isSelected ? 0 : 10),
                                      child: Row(
                                        children: [
                                          GestureDetector(
                                            onTap: () => setDialogState(() {
                                              if (isSelected) {
                                                itemQuantities.remove(asset.id);
                                                actualQuantities.remove(asset.id);
                                                actualQtyControllers[asset.id]?.clear();
                                                if (expandedItemId == asset.id) expandedItemId = null;
                                              } else {
                                                itemQuantities[asset.id] = asset.quantity;
                                              }
                                            }),
                                            child: Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: isSelected ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA)),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(asset.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                Text('Mã: ${asset.assetCode}', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(color: const Color(0xFFF4F4F5), borderRadius: BorderRadius.circular(6)),
                                            child: Text('Tồn: $stockQty', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Actual qty row (only when selected)
                                    if (isSelected) ...[
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(40, 6, 10, 8),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 100,
                                              height: 36,
                                              child: TextField(
                                                controller: actualQtyControllers[asset.id],
                                                keyboardType: TextInputType.number,
                                                decoration: InputDecoration(
                                                  labelText: 'SL thực tế',
                                                  labelStyle: const TextStyle(fontSize: 11),
                                                  isDense: true,
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                                                ),
                                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                                onChanged: (v) {
                                                  final parsed = int.tryParse(v);
                                                  setDialogState(() {
                                                    if (v.isEmpty) {
                                                      actualQuantities.remove(asset.id);
                                                    } else if (parsed != null) {
                                                      actualQuantities[asset.id] = parsed;
                                                    }
                                                  });
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (diff != null)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: diff < 0 ? const Color(0xFFFEE2E2) : diff > 0 ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      diff < 0 ? Icons.trending_down : diff > 0 ? Icons.trending_up : Icons.check_circle,
                                                      size: 14,
                                                      color: diff < 0 ? const Color(0xFFEF4444) : diff > 0 ? const Color(0xFFF59E0B) : const Color(0xFF059669),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      diff < 0 ? 'Hụt: ${diff.abs()}' : diff > 0 ? 'Thừa: +$diff' : 'Khớp',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                        color: diff < 0 ? const Color(0xFFEF4444) : diff > 0 ? const Color(0xFFF59E0B) : const Color(0xFF059669),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            const Spacer(),
                                            GestureDetector(
                                              onTap: () => setDialogState(() {
                                                expandedItemId = isExpanded ? null : asset.id;
                                              }),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: (itemNotes[asset.id]?.isNotEmpty == true || itemImages[asset.id] != null)
                                                      ? const Color(0xFFDCFCE7) : const Color(0xFFF4F4F5),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      itemImages[asset.id] != null ? Icons.image : Icons.note_add,
                                                      size: 14,
                                                      color: const Color(0xFF64748B),
                                                    ),
                                                    Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 16, color: const Color(0xFF64748B)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    // Expanded: notes + image
                                    if (isSelected && isExpanded) ...[
                                      const Divider(height: 1),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(40, 8, 10, 10),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            TextField(
                                              decoration: InputDecoration(
                                                hintText: 'Ghi chú cho sản phẩm này...',
                                                hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFA1A1AA)),
                                                isDense: true,
                                                contentPadding: const EdgeInsets.all(10),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              style: const TextStyle(fontSize: 12),
                                              maxLines: 2,
                                              controller: TextEditingController(text: itemNotes[asset.id] ?? ''),
                                              onChanged: (v) => itemNotes[asset.id] = v,
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                if (itemImages[asset.id] != null) ...[
                                                  Stack(
                                                    clipBehavior: Clip.none,
                                                    children: [
                                                      ClipRRect(
                                                        borderRadius: BorderRadius.circular(6),
                                                        child: Image.memory(itemImages[asset.id]!, width: 50, height: 50, fit: BoxFit.cover),
                                                      ),
                                                      Positioned(
                                                        top: -6, right: -6,
                                                        child: GestureDetector(
                                                          onTap: () => setDialogState(() {
                                                            itemImages.remove(asset.id);
                                                            itemImageNames.remove(asset.id);
                                                          }),
                                                          child: Container(
                                                            padding: const EdgeInsets.all(2),
                                                            decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                                                            child: const Icon(Icons.close, size: 12, color: Colors.white),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(width: 8),
                                                ],
                                                OutlinedButton.icon(
                                                  onPressed: () async {
                                                    final picker = ImagePicker();
                                                    final source = await showDialog<ImageSource>(
                                                      context: context,
                                                      builder: (ctx) => SimpleDialog(
                                                        title: const Text('Chọn nguồn ảnh'),
                                                        children: [
                                                          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ImageSource.camera), child: const ListTile(leading: Icon(Icons.camera_alt), title: Text('Chụp ảnh'))),
                                                          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ImageSource.gallery), child: const ListTile(leading: Icon(Icons.photo_library), title: Text('Thư viện'))),
                                                        ],
                                                      ),
                                                    );
                                                    if (source == null) return;
                                                    final file = await picker.pickImage(source: source, maxWidth: 1024, imageQuality: 80);
                                                    if (file == null) return;
                                                    final bytes = await file.readAsBytes();
                                                    setDialogState(() {
                                                      itemImages[asset.id] = bytes;
                                                      itemImageNames[asset.id] = file.name;
                                                    });
                                                  },
                                                  icon: const Icon(Icons.camera_alt, size: 16),
                                                  label: Text(itemImages[asset.id] != null ? 'Đổi ảnh' : 'Thêm ảnh', style: const TextStyle(fontSize: 12)),
                                                  style: OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    minimumSize: Size.zero,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
              ],
            );
          }

          Widget buildActions() {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE4E4E7)))),
              child: Row(
                children: [
                  if (step > 0)
                    TextButton.icon(
                      onPressed: () => setDialogState(() => step = 0),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Quay lại'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF71717A)),
                    ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
                  const SizedBox(width: 12),
                  if (step == 0)
                    ElevatedButton.icon(
                      onPressed: () {
                        if (nameCtrl.text.isEmpty) {
                          NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập tên đợt kiểm kê');
                          return;
                        }
                        setDialogState(() => step = 1);
                        if (!allLoaded) loadAllAssets(setDialogState);
                      },
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: const Text('Chọn hàng hóa'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                  if (step == 1)
                    ElevatedButton.icon(
                      onPressed: (selectedCount == 0 || isCreating) ? null : () async {
                        setDialogState(() => isCreating = true);
                        try {
                          // Upload images first
                          final Map<String, String?> imageUrls = {};
                          for (final entry in itemImages.entries) {
                            if (entry.value != null) {
                              final uploadResult = await _apiService.uploadFile(
                                entry.value!.toList(),
                                itemImageNames[entry.key] ?? 'inventory_check.jpg',
                                folder: 'inventory',
                              );
                              if (uploadResult['isSuccess'] == true && uploadResult['data'] != null) {
                                imageUrls[entry.key] = uploadResult['data']['fileUrl'];
                              }
                            }
                          }
                          // Build items list with quantities + actual qty + notes
                          final items = itemQuantities.entries.map((e) {
                            final item = <String, dynamic>{'assetId': e.key, 'expectedQuantity': e.value};
                            if (actualQuantities.containsKey(e.key)) {
                              item['actualQuantity'] = actualQuantities[e.key];
                            }
                            String? note = itemNotes[e.key];
                            final imgUrl = imageUrls[e.key];
                            if (imgUrl != null) {
                              note = '${note != null && note.isNotEmpty ? '$note\n' : ''}[IMG]$imgUrl[/IMG]';
                            }
                            if (note != null && note.isNotEmpty) item['notes'] = note;
                            return item;
                          }).toList();
                          final result = await _apiService.createAssetInventory(
                            name: nameCtrl.text,
                            description: descCtrl.text.isNotEmpty ? descCtrl.text : null,
                            startDate: startDate, endDate: endDate,
                            responsibleUserId: responsibleUserId,
                            notes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null,
                            items: items,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          if (!mounted) return;
                          if (result['isSuccess'] == true) {
                            NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã tạo đợt kiểm kê với $selectedCount hàng hóa');
                            _loadInventories();
                          } else {
                            NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
                          }
                        } finally {
                          if (context.mounted) setDialogState(() => isCreating = false);
                        }
                      },
                      icon: isCreating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check, size: 18),
                      label: Text('Tạo ($selectedCount)'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                ],
              ),
            );
          }

          Widget buildStepIndicator() {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7)))),
              child: Row(
                children: [
                  _stepDot(0, step, 'Thông tin'),
                  Expanded(child: Container(height: 1, color: step >= 1 ? const Color(0xFF1E3A5F) : const Color(0xFFE4E4E7))),
                  _stepDot(1, step, 'Chọn hàng hóa'),
                ],
              ),
            );
          }

          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(step == 0 ? 'Tạo đợt kiểm kê' : 'Chọn hàng hóa kiểm kê'),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ),
                  body: Column(
                    children: [
                      buildStepIndicator(),
                      Expanded(child: step == 0 ? buildInfoStep() : buildItemSelectStep()),
                    ],
                  ),
                  bottomNavigationBar: buildActions(),
                ),
              ),
            );
          }
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: math.min(520, MediaQuery.of(context).size.width - 32).toDouble(),
              height: step == 0 ? null : MediaQuery.of(context).size.height * 0.85,
              child: Column(
                mainAxisSize: step == 0 ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Row(children: [
                      const Icon(Icons.checklist, color: Color(0xFF1E3A5F), size: 22),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Tạo đợt kiểm kê mới', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                      IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                    ]),
                  ),
                  buildStepIndicator(),
                  if (step == 0) buildInfoStep() else Expanded(child: buildItemSelectStep()),
                  buildActions(),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      nameCtrl.dispose();
      descCtrl.dispose();
      notesCtrl.dispose();
      searchCtrl.dispose();
      for (final c in actualQtyControllers.values) {
        c.dispose();
      }
    });
  }

  Widget _stepDot(int index, int current, String label) {
    final isActive = current >= index;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1E3A5F) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: isActive ? const Color(0xFF1E3A5F) : const Color(0xFFD4D4D8), width: 2),
          ),
          child: Center(child: Text('${index + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isActive ? Colors.white : const Color(0xFFA1A1AA)))),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal, color: isActive ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA))),
      ],
    );
  }

  void _showAssignDialog(Asset asset) {
    String? selectedUserId;
    final reasonCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMobile) ...[
                  const Text('Cấp phát tài sản', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                ],
                Text('Tài sản: ${asset.name}', style: const TextStyle(color: Color(0xFF71717A))),
                const SizedBox(height: 20),
                _dialogDropdown<String?>('Cấp cho *', selectedUserId,
                  _employees.map((e) => DropdownMenuItem(value: e.id, child: Text(e.fullName))).toList(),
                  (v) => setDialogState(() => selectedUserId = v),
                ),
                const SizedBox(height: 12),
                _dialogField('Lý do', reasonCtrl),
                const SizedBox(height: 12),
                _dialogField('Ghi chú', notesCtrl, maxLines: 2),
              ],
            ),
          );
          final actionButtons = Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedUserId == null) {
                          NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng chọn người nhận');
                          return;
                        }
                        final result = await _apiService.assignAsset(assetId: asset.id, toUserId: selectedUserId!, reason: reasonCtrl.text.isNotEmpty ? reasonCtrl.text : null, notes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        if (!mounted) return;
                        if (result['isSuccess'] == true) {
                          NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã cấp phát tài sản');
                          _loadAssets(); _loadStatistics();
                        } else {
                          NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Cấp phát'),
                    ),
                  ],
            ),
          );
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Cấp phát tài sản'),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ),
                  body: formContent,
                  bottomNavigationBar: actionButtons,
                ),
              ),
            );
          }
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: math.min(450, MediaQuery.of(context).size.width - 32).toDouble(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  formContent,
                  actionButtons,
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      reasonCtrl.dispose();
      notesCtrl.dispose();
    });
  }

  void _showTransferDialog(Asset asset) {
    String? selectedUserId;
    final reasonCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMobile) ...[
                  const Text('Chuyển giao tài sản', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                ],
                Text('Tài sản: ${asset.name}', style: const TextStyle(color: Color(0xFF71717A))),
                Text('Đang sử dụng: ${asset.currentAssigneeName}', style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13)),
                const SizedBox(height: 20),
                _dialogDropdown<String?>('Chuyển cho *', selectedUserId,
                  _employees.where((e) => e.id != asset.currentAssigneeId).map((e) => DropdownMenuItem(value: e.id, child: Text(e.fullName))).toList(),
                  (v) => setDialogState(() => selectedUserId = v),
                ),
                const SizedBox(height: 12),
                _dialogField('Lý do', reasonCtrl),
                const SizedBox(height: 12),
                _dialogField('Ghi chú', notesCtrl, maxLines: 2),
              ],
            ),
          );
          final actionButtons = Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedUserId == null) {
                          NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng chọn người nhận');
                          return;
                        }
                        final result = await _apiService.transferAsset(assetId: asset.id, fromUserId: asset.currentAssigneeId!, toUserId: selectedUserId!, reason: reasonCtrl.text.isNotEmpty ? reasonCtrl.text : null, notes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        if (!mounted) return;
                        if (result['isSuccess'] == true) {
                          NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã chuyển giao tài sản');
                          _loadAssets(); _loadStatistics();
                        } else {
                          NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Chuyển giao'),
                    ),
                  ],
            ),
          );
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Chuyển giao tài sản'),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ),
                  body: formContent,
                  bottomNavigationBar: actionButtons,
                ),
              ),
            );
          }
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: math.min(450, MediaQuery.of(context).size.width - 32).toDouble(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  formContent,
                  actionButtons,
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      reasonCtrl.dispose();
      notesCtrl.dispose();
    });
  }

  void _showReturnDialog(Asset asset) {
    final reasonCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    InventoryCondition condition = InventoryCondition.good;
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMobile) ...[
                  const Text('Thu hồi tài sản', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                ],
                Text('Tài sản: ${asset.name}', style: const TextStyle(color: Color(0xFF71717A))),
                Text('Thu hồi từ: ${asset.currentAssigneeName}', style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13)),
                const SizedBox(height: 20),
                _dialogDropdown<InventoryCondition>('Tình trạng khi thu hồi', condition,
                  InventoryCondition.values.map((c) => DropdownMenuItem(value: c, child: Text(getConditionLabel(c)))).toList(),
                  (v) => setDialogState(() => condition = v!),
                ),
                const SizedBox(height: 12),
                _dialogField('Lý do thu hồi', reasonCtrl),
                const SizedBox(height: 12),
                _dialogField('Ghi chú', notesCtrl, maxLines: 2),
              ],
            ),
          );
          final actionButtons = Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        final result = await _apiService.returnAsset(assetId: asset.id, fromUserId: asset.currentAssigneeId!, reason: reasonCtrl.text.isNotEmpty ? reasonCtrl.text : null, notes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null, returnCondition: condition.index);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        if (!mounted) return;
                        if (result['isSuccess'] == true) {
                          NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã thu hồi tài sản');
                          _loadAssets(); _loadStatistics();
                        } else {
                          NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Thu hồi'),
                    ),
                  ],
            ),
          );
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Thu hồi tài sản'),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ),
                  body: formContent,
                  bottomNavigationBar: actionButtons,
                ),
              ),
            );
          }
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: math.min(450, MediaQuery.of(context).size.width - 32).toDouble(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  formContent,
                  actionButtons,
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      reasonCtrl.dispose();
      notesCtrl.dispose();
    });
  }

  // ==================== ACTIONS ====================
  void _handleAssetAction(Asset asset, String action) {
    switch (action) {
      case 'view': _showAssetDetail(asset); break;
      case 'edit': _showAssetDialog(asset: asset); break;
      case 'assign': _showAssignDialog(asset); break;
      case 'transfer': _showTransferDialog(asset); break;
      case 'return': _showReturnDialog(asset); break;
      case 'delete': _confirmDeleteAsset(asset); break;
    }
  }

  void _handleCategoryAction(AssetCategory category, String action) {
    switch (action) {
      case 'edit': _showCategoryDialog(category: category); break;
      case 'add_sub': _showCategoryDialog(parentId: category.id); break;
      case 'delete': _confirmDeleteCategory(category); break;
    }
  }

  Future<void> _confirmDeleteAsset(Asset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa tài sản "${asset.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await _apiService.deleteAsset(asset.id);
      if (!mounted) return;
      if (result['isSuccess'] == true) {
        NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã xóa tài sản');
        _loadAssets(); _loadStatistics();
      } else {
        NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
      }
    }
  }

  Future<void> _confirmDeleteCategory(AssetCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa danh mục "${category.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await _apiService.deleteAssetCategory(category.id);
      if (!mounted) return;
      if (result['isSuccess'] == true) {
        NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã xóa danh mục');
        _loadCategories();
      } else {
        NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
      }
    }
  }

  Future<void> _confirmTransfer(AssetTransfer transfer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận nhận tài sản'),
        content: Text('Bạn xác nhận đã nhận tài sản "${transfer.assetName ?? 'Tài sản'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _apiService.confirmAssetTransfer(transfer.id);
    if (!mounted) return;
    if (result['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã xác nhận chuyển giao');
      _loadTransfers();
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
    }
  }

  // ==================== FORM HELPERS ====================
  Widget _dialogField(String label, TextEditingController controller, {int maxLines = 1, TextInputType? inputType, String? suffix}) {
    final isMoney = suffix == 'VND' || suffix == 'VNĐ' || suffix == 'đ';
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: inputType,
      inputFormatters: isMoney ? [ThousandSeparatorFormatter()] : null,
      style: const TextStyle(fontSize: 14, color: Color(0xFF18181B)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFFA1A1AA)),
        suffixText: suffix,
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1E3A5F), width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  InputDecoration _dialogDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: Color(0xFFA1A1AA)),
      filled: true,
      fillColor: const Color(0xFFFAFAFA),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1E3A5F), width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _dialogDropdown<T>(String label, T? value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: _dialogDecoration(label),
      items: items,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: Color(0xFF18181B)),
    );
  }
}

// ==================== HELPER CLASSES ====================
class _PickedImage {
  final Uint8List bytes;
  final String name;
  const _PickedImage(this.bytes, this.name);
}

// ==================== QR SCAN DIALOG ====================
class _AssetQrScanDialog extends StatefulWidget {
  final Function(String code) onAssetScanned;
  const _AssetQrScanDialog({required this.onAssetScanned});

  @override
  State<_AssetQrScanDialog> createState() => _AssetQrScanDialogState();
}

class _AssetQrScanDialogState extends State<_AssetQrScanDialog> {
  MobileScannerController? _scannerController;
  bool _hasScanned = false;
  String? _cameraError;
  bool _showManualInput = false;
  final _manualController = TextEditingController();
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  void _initScanner() {
    try {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        formats: [BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.ean13],
      );
    } catch (e) {
      setState(() => _cameraError = 'Không thể khởi tạo camera: $e');
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: isMobile ? double.infinity : 420,
        height: _showManualInput ? 280 : 480,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E3A5F),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Quét QR / Barcode tài sản', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                ],
              ),
            ),
            Expanded(
              child: _showManualInput
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _manualController,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: 'Nhập mã tài sản',
                              hintText: 'VD: TS-20240101-0001',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.search),
                            ),
                            onSubmitted: (v) {
                              if (v.trim().isNotEmpty) widget.onAssetScanned(v.trim());
                            },
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                final v = _manualController.text.trim();
                                if (v.isNotEmpty) widget.onAssetScanned(v);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Tìm kiếm'),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        if (_scannerController != null)
                          ClipRRect(
                            child: MobileScanner(
                              controller: _scannerController!,
                              errorBuilder: (context, error) {
                                return Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.camera_alt, size: 48, color: Color(0xFFA1A1AA)),
                                      const SizedBox(height: 8),
                                      Text(error.errorDetails?.message ?? 'Không thể truy cập camera', style: const TextStyle(color: Color(0xFFA1A1AA))),
                                    ],
                                  ),
                                );
                              },
                              onDetect: (capture) {
                                if (_hasScanned) return;
                                final barcodes = capture.barcodes;
                                if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                                  final code = barcodes.first.rawValue!;
                                  setState(() => _hasScanned = true);
                                  widget.onAssetScanned(code);
                                }
                              },
                            ),
                          )
                        else
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.camera_alt, size: 48, color: Color(0xFFA1A1AA)),
                                const SizedBox(height: 8),
                                Text(_cameraError ?? 'Camera không khả dụng', style: const TextStyle(color: Color(0xFFA1A1AA))),
                              ],
                            ),
                          ),
                        if (_cameraError == null && _scannerController != null)
                          Center(
                            child: Container(
                              width: 220, height: 220,
                              decoration: BoxDecoration(
                                border: Border.all(color: _hasScanned ? const Color(0xFF059669) : Colors.white.withValues(alpha: 0.6), width: 2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: _hasScanned ? const Center(child: Icon(Icons.check_circle, color: Color(0xFF059669), size: 48)) : null,
                            ),
                          ),
                        if (_cameraError == null && _scannerController != null && !_hasScanned)
                          Positioned(
                            bottom: 12,
                            left: 0, right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: () { _scannerController!.toggleTorch(); setState(() => _torchOn = !_torchOn); },
                                  icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
                                  style: IconButton.styleFrom(backgroundColor: Colors.black38),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            // Bottom bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE4E4E7)))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _showManualInput = !_showManualInput),
                    icon: Icon(_showManualInput ? Icons.camera_alt : Icons.keyboard, size: 18),
                    label: Text(_showManualInput ? 'Quét mã' : 'Nhập thủ công'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== INVENTORY DETAIL DIALOG ====================
class _InventoryDetailDialog extends StatefulWidget {
  final AssetInventory inventory;
  final ApiService apiService;
  final VoidCallback onRefresh;

  const _InventoryDetailDialog({required this.inventory, required this.apiService, required this.onRefresh});

  @override
  State<_InventoryDetailDialog> createState() => _InventoryDetailDialogState();
}

class _InventoryDetailDialogState extends State<_InventoryDetailDialog> {
  late AssetInventory _inventory;
  bool _isScanning = false;
  bool _showReport = false;

  @override
  void initState() {
    super.initState();
    _inventory = widget.inventory;
    // Auto-show report for completed inventories
    if (_inventory.isCompleted) {
      _showReport = true;
    }
  }

  Future<void> _refreshInventory() async {
    final result = await widget.apiService.getInventoryDetail(_inventory.id);
    if (result['isSuccess'] == true && result['data'] != null) {
      setState(() => _inventory = AssetInventory.fromJson(result['data']));
    }
  }

  void _startQrScan() {
    showDialog(
      context: context,
      builder: (ctx) => _AssetQrScanDialog(
        onAssetScanned: (code) async {
          Navigator.pop(ctx);
          await _scanAndCheckItem(code);
        },
      ),
    );
  }

  Future<void> _scanAndCheckItem(String code) async {
    setState(() => _isScanning = true);

    // First find the matching item in inventory to get expectedQuantity
    final matchedItem = _inventory.items?.firstWhere(
      (i) => i.assetCode == code,
      orElse: () => AssetInventoryItem(id: '', inventoryId: '', assetId: '', expectedQuantity: 0, isChecked: false, hasIssue: false),
    );

    setState(() => _isScanning = false);

    if (matchedItem != null && matchedItem.id.isNotEmpty) {
      // Open manual check dialog so user enters actual quantity
      await _checkItemManually(matchedItem);
    } else {
      // Item not found locally, try scan API
      setState(() => _isScanning = true);
      final result = await widget.apiService.scanInventoryItem(
        inventoryId: _inventory.id,
        code: code,
      );
      if (!mounted) return;
      setState(() => _isScanning = false);

      if (result['isSuccess'] == true) {
        final data = result['data'];
        final assetName = data?['assetName'] ?? code;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ Đã quét: $assetName - Hãy nhập số lượng thực tế'),
          backgroundColor: const Color(0xFF059669),
          duration: const Duration(seconds: 2),
        ));
        await _refreshInventory();
        widget.onRefresh();
        // After refresh, find the item and open check dialog
        final refreshedItem = _inventory.items?.firstWhere(
          (i) => i.assetCode == code,
          orElse: () => AssetInventoryItem(id: '', inventoryId: '', assetId: '', expectedQuantity: 0, isChecked: false, hasIssue: false),
        );
        if (refreshedItem != null && refreshedItem.id.isNotEmpty) {
          await _checkItemManually(refreshedItem);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result['message'] ?? 'Không tìm thấy tài sản'),
            backgroundColor: const Color(0xFFEF4444),
          ));
        }
      }
    }
  }

  Future<void> _checkItemManually(AssetInventoryItem item) async {
    int condition = item.condition?.index ?? 0;
    // For unchecked items: default to empty (0) so user MUST enter real count
    // For re-checking: keep previously entered value
    int actualQty = item.isChecked ? (item.actualQuantity ?? 0) : 0;
    bool hasEnteredQty = item.isChecked;
    String? actualLocation = item.actualLocation;
    bool hasIssue = item.hasIssue;
    String? issueDesc = item.issueDescription;
    String? notes;
    Uint8List? imageBytes;
    String? imageName;

    // Extract existing notes without image tag
    if (item.notes != null) {
      notes = item.notes!.replaceAll(RegExp(r'\[IMG\].*?\[/IMG\]'), '').trim();
      if (notes.isEmpty) notes = null;
    }

    final qtyCtrl = TextEditingController(text: item.isChecked ? actualQty.toString() : '');
    final issueCtrl = TextEditingController(text: issueDesc ?? '');
    final notesCtrl = TextEditingController(text: notes ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final diff = hasEnteredQty ? actualQty - item.expectedQuantity : null;
          final diffColor = diff == null ? const Color(0xFF94A3B8) : diff < 0 ? const Color(0xFFEF4444) : diff > 0 ? const Color(0xFFF59E0B) : const Color(0xFF059669);
          final diffText = diff == null ? 'Chưa nhập' : diff < 0 ? 'Hao hụt: ${diff.abs()}' : diff > 0 ? 'Thừa: +$diff' : 'Khớp';

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: EdgeInsets.zero,
            title: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF1E3A5F),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.assetName ?? item.assetCode ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                  if (item.assetCode != null) Text(item.assetCode!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2, size: 16, color: Colors.white70),
                        const SizedBox(width: 6),
                        Text('Tồn kho: ${item.expectedQuantity}', style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: diffColor, borderRadius: BorderRadius.circular(4)),
                          child: Text(diffText, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Actual quantity - prominent
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Số lượng thực tế', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                        SizedBox(
                          width: 48, height: 36,
                          child: IconButton(
                            onPressed: () { if (actualQty > 0) { actualQty--; hasEnteredQty = true; qtyCtrl.text = actualQty.toString(); setDialogState(() {}); } },
                            icon: const Icon(Icons.remove_circle_outline, size: 22),
                            padding: EdgeInsets.zero,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: TextFormField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              border: const OutlineInputBorder(),
                              isDense: true,
                              hintText: '?',
                              hintStyle: TextStyle(color: Colors.red.shade300, fontSize: 18),
                            ),
                            onChanged: (v) {
                              final parsed = int.tryParse(v);
                              if (parsed != null) {
                                setDialogState(() { actualQty = parsed; hasEnteredQty = true; });
                              } else if (v.isEmpty) {
                                setDialogState(() { actualQty = 0; hasEnteredQty = false; });
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          width: 48, height: 36,
                          child: IconButton(
                            onPressed: () { actualQty++; hasEnteredQty = true; qtyCtrl.text = actualQty.toString(); setDialogState(() {}); },
                            icon: const Icon(Icons.add_circle_outline, size: 22),
                            padding: EdgeInsets.zero,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: condition,
                    decoration: const InputDecoration(labelText: 'Tình trạng', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Tốt')),
                      DropdownMenuItem(value: 1, child: Text('Bình thường')),
                      DropdownMenuItem(value: 2, child: Text('Kém')),
                      DropdownMenuItem(value: 3, child: Text('Hỏng')),
                      DropdownMenuItem(value: 4, child: Text('Không tìm thấy')),
                    ],
                    onChanged: (v) => setDialogState(() => condition = v ?? 0),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Có vấn đề?', style: TextStyle(fontSize: 14)),
                    value: hasIssue,
                    onChanged: (v) => setDialogState(() => hasIssue = v),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  if (hasIssue) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: issueCtrl,
                      decoration: const InputDecoration(labelText: 'Mô tả vấn đề', border: OutlineInputBorder(), isDense: true),
                      maxLines: 2,
                      onChanged: (v) => issueDesc = v.isEmpty ? null : v,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Ghi chú', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) => notes = v.isEmpty ? null : v,
                  ),
                  const SizedBox(height: 12),
                  const Align(alignment: Alignment.centerLeft, child: Text('Hình ảnh', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                  const SizedBox(height: 8),
                  if (imageBytes != null) ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(imageBytes!, height: 120, width: double.infinity, fit: BoxFit.cover),
                        ),
                        Positioned(top: 4, right: 4, child: GestureDetector(
                          onTap: () => setDialogState(() { imageBytes = null; imageName = null; }),
                          child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, size: 16, color: Colors.white)),
                        )),
                      ],
                    ),
                  ] else
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () async {
                          final picker = ImagePicker();
                          final photo = await picker.pickImage(source: ImageSource.camera, maxWidth: 1920, maxHeight: 1920, imageQuality: 80);
                          if (photo != null) { final bytes = await photo.readAsBytes(); setDialogState(() { imageBytes = bytes; imageName = photo.name; }); }
                        },
                        icon: const Icon(Icons.camera_alt, size: 18),
                        label: const Text('Chụp ảnh', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () async {
                          final picker = ImagePicker();
                          final photo = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1920, maxHeight: 1920, imageQuality: 80);
                          if (photo != null) { final bytes = await photo.readAsBytes(); setDialogState(() { imageBytes = bytes; imageName = photo.name; }); }
                        },
                        icon: const Icon(Icons.photo_library, size: 18),
                        label: const Text('Thư viện', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                      )),
                    ]),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
              ElevatedButton(
                onPressed: !hasEnteredQty ? null : () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white),
                child: Text(hasEnteredQty ? 'Xác nhận' : 'Nhập số lượng'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    // Upload image if selected
    String? imageUrl;
    if (imageBytes != null) {
      final uploadResult = await widget.apiService.uploadFile(imageBytes!.toList(), imageName ?? 'inventory_check.jpg', folder: 'inventory');
      if (uploadResult['isSuccess'] == true && uploadResult['data'] != null) {
        imageUrl = uploadResult['data']['fileUrl'];
      }
    }

    final result = await widget.apiService.checkInventoryItem(
      inventoryItemId: item.id,
      condition: condition,
      actualQuantity: actualQty,
      actualLocation: actualLocation,
      hasIssue: hasIssue,
      issueDescription: issueDesc,
      notes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null,
      imageUrl: imageUrl,
    );
    if (result['isSuccess'] == true) {
      await _refreshInventory();
      widget.onRefresh();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['message'] ?? 'Lỗi'),
          backgroundColor: const Color(0xFFEF4444),
        ));
      }
    }
  }

  Future<void> _completeInventory() async {
    final unchecked = _inventory.totalAssets - _inventory.checkedCount;
    if (unchecked > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Hoàn thành kiểm kê?'),
          content: Text('Còn $unchecked hàng hóa chưa kiểm. Bạn có chắc muốn hoàn thành?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white),
              child: const Text('Hoàn thành'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    final result = await widget.apiService.completeInventory(_inventory.id);
    if (result['isSuccess'] == true) {
      widget.onRefresh();
      // Reload inventory detail and show report
      final detailResult = await widget.apiService.getInventoryDetail(_inventory.id);
      if (detailResult['isSuccess'] == true && detailResult['data'] != null) {
        if (mounted) {
          setState(() {
            _inventory = AssetInventory.fromJson(detailResult['data']);
            _showReport = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✓ Đã hoàn thành kiểm kê - Xem báo cáo bên dưới'),
            backgroundColor: Color(0xFF059669),
            duration: Duration(seconds: 3),
          ));
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['message'] ?? 'Lỗi hoàn thành kiểm kê'),
          backgroundColor: const Color(0xFFEF4444),
        ));
      }
    }
  }

  // Compute shrinkage summary from checked items
  Map<String, dynamic> _computeSummary() {
    final items = _inventory.items ?? [];
    final checkedItems = items.where((i) => i.isChecked).toList();
    int totalExpected = 0;
    int totalActual = 0;
    int lossItems = 0;
    int surplusItems = 0;
    int matchItems = 0;
    int issueItems = 0;

    for (final item in checkedItems) {
      totalExpected += item.expectedQuantity;
      final actual = item.actualQuantity ?? 0;
      totalActual += actual;
      final diff = actual - item.expectedQuantity;
      if (diff < 0) {
        lossItems++;
      } else if (diff > 0) {
        surplusItems++;
      } else {
        matchItems++;
      }
      if (item.hasIssue) {
        issueItems++;
      }
    }

    return {
      'totalExpected': totalExpected,
      'totalActual': totalActual,
      'totalDiff': totalActual - totalExpected,
      'lossItems': lossItems,
      'surplusItems': surplusItems,
      'matchItems': matchItems,
      'issueItems': issueItems,
      'checkedCount': checkedItems.length,
    };
  }

  Widget _buildSummaryCard() {
    final s = _computeSummary();
    final diff = s['totalDiff'] as int;
    final diffColor = diff < 0 ? const Color(0xFFEF4444) : diff > 0 ? const Color(0xFFF59E0B) : const Color(0xFF059669);
    final diffLabel = diff < 0 ? 'Hao hụt' : diff > 0 ? 'Thừa' : 'Khớp';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1E3A5F).withValues(alpha: 0.05), const Color(0xFF1E3A5F).withValues(alpha: 0.02)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.assessment, size: 18, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 6),
              const Text('Báo cáo kiểm kê', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E3A5F))),
              const Spacer(),
              Text('${s['checkedCount']}/${_inventory.totalAssets} đã kiểm', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 10),
          // Main summary row
          Row(
            children: [
              Expanded(child: _summaryBox('Tồn kho', '${s['totalExpected']}', const Color(0xFF3B82F6))),
              const SizedBox(width: 8),
              Expanded(child: _summaryBox('Thực tế', '${s['totalActual']}', const Color(0xFF8B5CF6))),
              const SizedBox(width: 8),
              Expanded(child: _summaryBox(diffLabel, '${diff.abs()}', diffColor)),
            ],
          ),
          const SizedBox(height: 8),
          // Detail counts row
          Row(
            children: [
              _countChip(Icons.check_circle, '${s['matchItems']} khớp', const Color(0xFF059669)),
              const SizedBox(width: 6),
              _countChip(Icons.trending_down, '${s['lossItems']} hao hụt', const Color(0xFFEF4444)),
              const SizedBox(width: 6),
              _countChip(Icons.trending_up, '${s['surplusItems']} thừa', const Color(0xFFF59E0B)),
              if ((s['issueItems'] as int) > 0) ...[
                const SizedBox(width: 6),
                _countChip(Icons.warning_amber, '${s['issueItems']} vấn đề', const Color(0xFFEF4444)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _countChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final items = _inventory.items ?? [];
    final checkedItems = items.where((i) => i.isChecked).toList();
    final uncheckedItems = items.where((i) => !i.isChecked).toList();
    final progress = _inventory.totalAssets > 0 ? _inventory.checkedCount / _inventory.totalAssets : 0.0;
    final statusColor = _inventory.isInProgress ? const Color(0xFF3B82F6) : _inventory.isCompleted ? const Color(0xFF059669) : const Color(0xFFEF4444);

    // For report view, sort by shrinkage (most loss first)
    final reportItems = List<AssetInventoryItem>.from(checkedItems)
      ..sort((a, b) {
        final diffA = (a.actualQuantity ?? 0) - a.expectedQuantity;
        final diffB = (b.actualQuantity ?? 0) - b.expectedQuantity;
        return diffA.compareTo(diffB);
      });

    return Dialog(
      insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMobile ? 0 : 16)),
      child: SizedBox(
        width: isMobile ? double.infinity : 600,
        height: isMobile ? double.infinity : MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            // ===== HEADER =====
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3A5F), Color(0xFF2D5F8B)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(isMobile ? 0 : 16)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.fact_check_outlined, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_inventory.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(_inventory.inventoryCode, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4)),
                                      child: Text(
                                        _inventory.isInProgress ? 'Đang thực hiện' : _inventory.isCompleted ? 'Hoàn thành' : 'Đã hủy',
                                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Progress section
                      Row(
                        children: [
                          // Progress circle
                          SizedBox(
                            width: 48, height: 48,
                            child: Stack(
                              children: [
                                CircularProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                                  valueColor: const AlwaysStoppedAnimation(Color(0xFF34D399)),
                                  strokeWidth: 4,
                                ),
                                Center(
                                  child: Text('${_inventory.progressPercent.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Stats
                          Expanded(
                            child: Row(
                              children: [
                                _headerStat('Tổng SP', '${_inventory.totalAssets}', Colors.white),
                                Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.15), margin: const EdgeInsets.symmetric(horizontal: 10)),
                                _headerStat('Đã kiểm', '${_inventory.checkedCount}', const Color(0xFF34D399)),
                                Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.15), margin: const EdgeInsets.symmetric(horizontal: 10)),
                                _headerStat('Còn lại', '${_inventory.totalAssets - _inventory.checkedCount}', const Color(0xFFFBBF24)),
                                if (_inventory.issueCount > 0) ...[
                                  Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.15), margin: const EdgeInsets.symmetric(horizontal: 10)),
                                  _headerStat('Vấn đề', '${_inventory.issueCount}', const Color(0xFFF87171)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // ===== ACTION BAR =====
            if (_inventory.isInProgress)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isScanning ? null : _startQrScan,
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: const Text('Quét mã', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _actionIconBtn(
                      icon: _showReport ? Icons.list_alt : Icons.assessment_outlined,
                      tooltip: _showReport ? 'Danh sách' : 'Báo cáo',
                      onTap: () => setState(() => _showReport = !_showReport),
                      color: const Color(0xFF3B82F6),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      onPressed: _completeInventory,
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Hoàn thành', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF1E3A5F),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ),
            // Completed/Cancelled bar
            if (!_inventory.isInProgress)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _inventory.isCompleted ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                  border: Border(bottom: BorderSide(color: _inventory.isCompleted ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA))),
                ),
                child: Row(
                  children: [
                    Icon(_inventory.isCompleted ? Icons.check_circle : Icons.cancel, size: 16, color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      _inventory.isCompleted ? 'Đã hoàn thành' : 'Đã hủy',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                    ),
                    if (_inventory.endDate != null) ...[
                      const SizedBox(width: 8),
                      Text('· ${DateFormat('dd/MM/yyyy HH:mm').format(_inventory.endDate!)}', style: TextStyle(fontSize: 11, color: statusColor.withValues(alpha: 0.7))),
                    ],
                    const Spacer(),
                    _actionIconBtn(
                      icon: _showReport ? Icons.list_alt : Icons.assessment_outlined,
                      tooltip: _showReport ? 'Danh sách' : 'Báo cáo',
                      onTap: () => setState(() => _showReport = !_showReport),
                      color: const Color(0xFF3B82F6),
                    ),
                  ],
                ),
              ),
            if (_isScanning) const LinearProgressIndicator(),
            // Summary card
            if (checkedItems.isNotEmpty) _buildSummaryCard(),
            // ===== ITEM LIST =====
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFFD4D4D8)),
                      SizedBox(height: 8),
                      Text('Chưa có hàng hóa nào', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 14)),
                    ]))
                  : _showReport
                    ? _buildReportView(reportItems)
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          if (uncheckedItems.isNotEmpty) ...[
                            _sectionLabel('Chưa kiểm', uncheckedItems.length, const Color(0xFFF59E0B), Icons.radio_button_unchecked),
                            const SizedBox(height: 6),
                            ...uncheckedItems.map((item) => _buildInventoryItemCard(item, checked: false)),
                            const SizedBox(height: 16),
                          ],
                          if (checkedItems.isNotEmpty) ...[
                            _sectionLabel('Đã kiểm', checkedItems.length, const Color(0xFF059669), Icons.check_circle),
                            const SizedBox(height: 6),
                            ...checkedItems.map((item) => _buildInventoryItemCard(item, checked: true)),
                          ],
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _actionIconBtn({required IconData icon, required String tooltip, required VoidCallback onTap, required Color color}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _sectionLabel(String title, int count, Color color, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }

  Widget _buildReportView(List<AssetInventoryItem> reportItems) {
    if (reportItems.isEmpty) {
      return const Center(child: Text('Chưa có hàng hóa nào được kiểm', style: TextStyle(color: Color(0xFFA1A1AA))));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: reportItems.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // Table header
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Hàng hóa', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                SizedBox(width: 4),
                SizedBox(width: 45, child: Text('Tồn kho', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF64748B)), textAlign: TextAlign.center)),
                SizedBox(width: 4),
                SizedBox(width: 45, child: Text('Thực tế', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF64748B)), textAlign: TextAlign.center)),
                SizedBox(width: 4),
                SizedBox(width: 55, child: Text('Chênh lệch', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF64748B)), textAlign: TextAlign.center)),
              ],
            ),
          );
        }

        final item = reportItems[index - 1];
        final actual = item.actualQuantity ?? 0;
        final diff = actual - item.expectedQuantity;
        final diffColor = diff < 0 ? const Color(0xFFEF4444) : diff > 0 ? const Color(0xFFF59E0B) : const Color(0xFF059669);
        final diffText = diff < 0 ? '$diff' : diff > 0 ? '+$diff' : '0';

        String? imageUrl;
        if (item.notes != null && item.notes!.contains('[IMG]')) {
          final imgMatch = RegExp(r'\[IMG\](.*?)\[/IMG\]').firstMatch(item.notes!);
          if (imgMatch != null) imageUrl = imgMatch.group(1);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: diff < 0 ? const Color(0xFFFEF2F2) : diff > 0 ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: diff < 0 ? const Color(0xFFFECACA) : diff > 0 ? const Color(0xFFFED7AA) : const Color(0xFFBBF7D0), width: 0.5),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.assetName ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (item.assetCode != null) Text(item.assetCode!, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                    if (item.hasIssue)
                      Row(children: [
                        const Icon(Icons.warning_amber, size: 10, color: Color(0xFFEF4444)),
                        const SizedBox(width: 2),
                        Expanded(child: Text(item.issueDescription ?? 'Vấn đề', style: const TextStyle(fontSize: 10, color: Color(0xFFEF4444)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                    if (imageUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: GestureDetector(
                          onTap: () => showDialog(context: context, builder: (_) => Dialog(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              AppBar(title: Text(item.assetName ?? ''), leading: const CloseButton()),
                              Image.network(imageUrl!, fit: BoxFit.contain),
                            ]),
                          )),
                          child: const Row(children: [
                            Icon(Icons.image, size: 10, color: Color(0xFF3B82F6)),
                            SizedBox(width: 2),
                            Text('Xem ảnh', style: TextStyle(fontSize: 10, color: Color(0xFF3B82F6), decoration: TextDecoration.underline)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(width: 45, child: Text('${item.expectedQuantity}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
              const SizedBox(width: 4),
              SizedBox(width: 45, child: Text('$actual', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: diffColor), textAlign: TextAlign.center)),
              const SizedBox(width: 4),
              Container(
                width: 55,
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(color: diffColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                child: Text(diffText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: diffColor), textAlign: TextAlign.center),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInventoryItemCard(AssetInventoryItem item, {required bool checked}) {
    String? imageUrl;
    String? displayNotes = item.notes;
    if (item.notes != null && item.notes!.contains('[IMG]')) {
      final imgMatch = RegExp(r'\[IMG\](.*?)\[/IMG\]').firstMatch(item.notes!);
      if (imgMatch != null) {
        imageUrl = imgMatch.group(1);
        displayNotes = item.notes!.replaceAll(RegExp(r'\[IMG\].*?\[/IMG\]'), '').trim();
        if (displayNotes.isEmpty) displayNotes = null;
      }
    }

    final actual = item.actualQuantity ?? 0;
    final diff = checked ? actual - item.expectedQuantity : 0;
    final diffColor = diff < 0 ? const Color(0xFFEF4444) : diff > 0 ? const Color(0xFFF59E0B) : const Color(0xFF059669);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: checked
            ? (diff < 0 ? const Color(0xFFFEF2F2) : diff > 0 ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4))
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: checked
            ? (diff < 0 ? const Color(0xFFFECACA) : diff > 0 ? const Color(0xFFFED7AA) : const Color(0xFFBBF7D0))
            : const Color(0xFFE4E4E7)),
      ),
      child: Row(
        children: [
          Icon(
            checked ? Icons.check_circle : Icons.radio_button_unchecked,
            color: checked ? diffColor : const Color(0xFFA1A1AA),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.assetName ?? 'Hàng hóa', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                if (item.assetCode != null)
                  Text(item.assetCode!, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                if (!checked)
                  Text('Tồn kho: ${item.expectedQuantity}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                if (checked) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF3B82F6).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text('TK: ${item.expectedQuantity}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF3B82F6))),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text('TT: $actual', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF8B5CF6))),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: diffColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          diff < 0 ? '$diff' : diff > 0 ? '+$diff' : '±0',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: diffColor),
                        ),
                      ),
                    ],
                  ),
                  if (item.conditionName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('Tình trạng: ${item.conditionName}', style: TextStyle(fontSize: 11, color: diffColor)),
                    ),
                ],
                if (item.hasIssue)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber, size: 12, color: Color(0xFFEF4444)),
                        const SizedBox(width: 4),
                        Expanded(child: Text(item.issueDescription ?? 'Có vấn đề', style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)))),
                      ],
                    ),
                  ),
                if (displayNotes != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(displayNotes, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                if (imageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: GestureDetector(
                      onTap: () => showDialog(context: context, builder: (_) => Dialog(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          AppBar(title: Text(item.assetName ?? 'Ảnh kiểm kê'), leading: const CloseButton()),
                          Image.network(imageUrl!, fit: BoxFit.contain),
                        ]),
                      )),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(imageUrl, height: 60, width: 80, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(height: 60, width: 80, color: const Color(0xFFF4F4F5), child: const Icon(Icons.broken_image, size: 20, color: Color(0xFFA1A1AA)))),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!checked && _inventory.isInProgress)
            IconButton(
              onPressed: () => _checkItemManually(item),
              icon: const Icon(Icons.edit_note, size: 20, color: Color(0xFF1E3A5F)),
              tooltip: 'Kiểm kê',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          if (checked && _inventory.isInProgress)
            IconButton(
              onPressed: () => _checkItemManually(item),
              icon: const Icon(Icons.edit, size: 16, color: Color(0xFF94A3B8)),
              tooltip: 'Sửa',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
