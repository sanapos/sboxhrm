import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  // Data
  List<Asset> _assets = [];
  List<AssetCategory> _categories = [];
  List<AssetTransfer> _transfers = [];
  List<AssetInventory> _inventories = [];
  List<Employee> _employees = [];
  AssetStatistics? _statistics;

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
          _transfers = (data['items'] as List?)?.map((e) => AssetTransfer.fromJson(e)).toList() ?? [];
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
          _inventories = (data['items'] as List?)?.map((e) => AssetInventory.fromJson(e)).toList() ?? [];
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

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: _isLoading ? const LoadingWidget() : _buildBody(),
    );
  }

  Widget _buildBody() {
    final isMobile = Responsive.isMobile(context);
    final hasPanel = _showTransfers || _showCategories || _showInventories;

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: isMobile && hasPanel
              ? _buildActivePanel()
              : Row(
                  children: [
                    // Main content
                    Expanded(
                      child: Column(
                        children: [
                          if (Responsive.isMobile(context)) ...[
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
                    if (!Responsive.isMobile(context) || _showMobileFilters) ...[                    _buildToolbar(),
                    if (_showFilters) _buildFilterBar(),
                    ],
                    Expanded(child: _buildAssetTable()),
                    if (!Responsive.isMobile(context)) _buildPagination(),
                  ],
                ),
              ),
              // Side panels
              if (_showTransfers) _buildTransfersPanel(),
              if (_showCategories) _buildCategoriesPanel(),
              if (_showInventories) _buildInventoriesPanel(),
            ],
          ),
        ),
      ],
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
    final statusColor = inventory.isInProgress ? const Color(0xFF1E3A5F) : inventory.isCompleted ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA);
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
              Expanded(child: Text(inventory.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  inventory.statusName.isNotEmpty ? inventory.statusName : (inventory.isInProgress ? 'Đang thực hiện' : inventory.isCompleted ? 'Hoàn thành' : 'Đã hủy'),
                  style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: inventory.progressPercent / 100,
              backgroundColor: const Color(0xFFE4E4E7),
              valueColor: AlwaysStoppedAnimation(statusColor),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('${inventory.checkedCount}/${inventory.totalAssets}', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
              const Spacer(),
              Text('${inventory.progressPercent.toStringAsFixed(0)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
            ],
          ),
          if (inventory.issueCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, size: 12, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 4),
                  Text('${inventory.issueCount} vấn đề', style: const TextStyle(fontSize: 11, color: Color(0xFFF59E0B))),
                ],
              ),
            ),
        ],
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

    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final formContent = SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Basic info
                        const Text('Thông tin cơ bản', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF52525B))),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: _dialogField('Mã tài sản *', codeCtrl)),
                          const SizedBox(width: 16),
                          Expanded(child: _dialogField('Số Serial', serialCtrl)),
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
                          price: priceCtrl.text, quantity: qtyCtrl.text, unit: unitCtrl.text,
                          supplier: supplierCtrl.text, invoice: invoiceCtrl.text,
                          warranty: warrantyCtrl.text, location: locationCtrl.text, notes: notesCtrl.text,
                          type: selectedType, status: selectedStatus, categoryId: selectedCategory,
                          purchaseDate: purchaseDate,
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
    required String price, required String quantity, required String unit,
    String? supplier, String? invoice, String? warranty, String? location, String? notes,
    required AssetType type, required AssetStatus status, String? categoryId,
    DateTime? purchaseDate,
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
                        _detailRow('Loại', getAssetTypeLabel(asset.assetType)),
                        if (asset.categoryName != null) _detailRow('Danh mục', asset.categoryName!),
                        if (asset.serialNumber != null) _detailRow('Số Serial', asset.serialNumber!),
                        if (asset.model != null) _detailRow('Model', asset.model!),
                        if (asset.brand != null) _detailRow('Thương hiệu', asset.brand!),
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
    DateTime startDate = DateTime.now();
    DateTime? endDate;
    String? responsibleUserId;

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
                  const Text('Tạo đợt kiểm kê mới', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                ],
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
          final actionButtons = Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (nameCtrl.text.isEmpty) {
                          NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập tên đợt kiểm kê');
                          return;
                        }
                        final result = await _apiService.createAssetInventory(
                          name: nameCtrl.text,
                          description: descCtrl.text.isNotEmpty ? descCtrl.text : null,
                          startDate: startDate, endDate: endDate,
                          responsibleUserId: responsibleUserId,
                          notes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null,
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        if (!mounted) return;
                        if (result['isSuccess'] == true) {
                          NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã tạo đợt kiểm kê mới');
                          _loadInventories();
                        } else {
                          NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Tạo'),
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
                    title: const Text('Tạo đợt kiểm kê mới'),
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
              width: math.min(500, MediaQuery.of(context).size.width - 32).toDouble(),
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
      nameCtrl.dispose();
      descCtrl.dispose();
      notesCtrl.dispose();
    });
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
