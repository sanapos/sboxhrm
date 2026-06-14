import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/hrm_fab_clearance.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xl;
import '../utils/file_saver.dart' as file_saver;
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../utils/report_screen_helpers.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/app_scroll_safe.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

class ProductionOutputScreen extends StatefulWidget {
  const ProductionOutputScreen({super.key});
  @override
  State<ProductionOutputScreen> createState() => _ProductionOutputScreenState();
}

class _ProductionOutputScreenState extends State<ProductionOutputScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  static double _toDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.replaceAll(',', '').trim()) ?? fallback;
    }
    return fallback;
  }

  static List<Map<String, dynamic>> _parseMapList(dynamic raw) {
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  static String _avatarLetter(dynamic name) {
    final s = (name ?? '').toString().trim();
    return s.isEmpty ? '?' : s[0].toUpperCase();
  }

  late TabController _tabCtl;

  // Data
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _summaries = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  bool _isLoading = true;

  // Filters
  DateTime _fromDate = DateTime.now().copyWith(day: 1);
  DateTime _toDate = DateTime.now();
  String _datePreset = 'this_month';
  String? _filterEmployeeId;
  String? _filterGroupId;
  String? _filterItemId;
  String? _filterBranchId;
  List<Map<String, dynamic>> _branches = [];
  int _page = 1;
  final int _pageSize = 50;
  bool _isExporting = false;

  // Mobile UI state
  @override
  void initState() {
    super.initState();
    _tabCtl = TabController(length: 2, vsync: this);
    _tabCtl.addListener(() {
      if (!_tabCtl.indexIsChanging) {
        if (_tabCtl.index == 1) _loadSummary();
      }
    });
    _loadMasterData();
  }

  @override
  void dispose() {
    _tabCtl.dispose();
    super.dispose();
  }

  Future<void> _loadMasterData() async {
    // Load employees separately so failure doesn't block product loading
    try {
      final empRes = await _apiService.getEmployees(pageSize: 9999);
      _employees = (empRes as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
    } catch (e) {
      debugPrint('Load employees error: $e');
    }
    try {
      final br = await _apiService.getBranchesForSelect();
      final bd = br['data'];
      if (bd is List && mounted) {
        setState(() => _branches =
            bd.map((b) => Map<String, dynamic>.from(b as Map)).toList());
      }
    } catch (_) {}

    // Load product groups and items
    try {
      final results = await Future.wait([
        _apiService.getProductGroups(),
        _apiService.getProductItems(),
      ]);
      if (results[0]['isSuccess'] == true) {
        _groups = _parseMapList(results[0]['data']);
      }
      if (results[1]['isSuccess'] == true) {
        _items = _parseMapList(results[1]['data']);
      }
      debugPrint('Loaded ${_groups.length} groups, ${_items.length} items');
    } catch (e) {
      debugPrint('Load product data error: $e');
      if (mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: 'Không thể tải dữ liệu sản phẩm');
      }
    }
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getProductionEntries(
        fromDate: _fromDate,
        toDate: _toDate,
        employeeId: _filterEmployeeId,
        productGroupId: _filterGroupId,
        productItemId: _filterItemId,
        page: _page,
        pageSize: _pageSize,
      );
      if (res['isSuccess'] == true) {
        final data = res['data'];
        if (data is Map) {
          _entries = _parseMapList(data['items']);
          _total = (data['total'] as num?)?.toInt() ?? _entries.length;
        }
      }
    } catch (e) {
      debugPrint('Load entries error: $e');
      if (mounted) {
        NotificationOverlayManager().showError(
            title: 'Lỗi', message: 'Không thể tải dữ liệu sản lượng');
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getProductionSummary(
        fromDate: _fromDate,
        toDate: _toDate,
        employeeId: _filterEmployeeId,
        productGroupId: _filterGroupId,
      );
      if (res['isSuccess'] == true) {
        _summaries = _parseMapList(res['data']);
      }
    } catch (e) {
      debugPrint('Load summary error: $e');
      if (mounted) {
        NotificationOverlayManager().showError(
            title: 'Lỗi', message: 'Không thể tải tổng hợp sản lượng');
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    const primary = Color(0xFF059669);
    final canCreateProduction = isMobile &&
        Provider.of<PermissionProvider>(context, listen: false)
            .canCreate('Production');
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      floatingActionButton: canCreateProduction
          ? FloatingActionButton.extended(
              onPressed: () {
                if (_items.isEmpty) {
                  NotificationOverlayManager().showError(
                    title: 'Chưa có sản phẩm',
                    message: 'Vui lòng thêm sản phẩm trước khi nhập sản lượng',
                  );
                  return;
                }
                _showAddEntryDialog();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nhập SL'),
              backgroundColor: primary,
              foregroundColor: Colors.white,
              elevation: 4,
            )
          : null,
      body: Column(
        children: [
          // ═══════ GRADIENT HEADER ═══════
          Container(
            padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, isMobile ? 12 : 18,
                isMobile ? 14 : 24, isMobile ? 12 : 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primary, primary.withValues(alpha: 0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(isMobile ? 8 : 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.precision_manufacturing,
                          size: isMobile ? 18 : 22, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sản lượng',
                              style: TextStyle(
                                  fontSize: isMobile ? 16 : 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          if (!isMobile)
                            Text(
                              'Quản lý sản lượng nhân viên',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.8)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          _buildToolbarRow(),

          Expanded(
            child: HrmFabClearance(
              fabVisible: canCreateProduction,
              extendedFab: true,
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabCtl,
                      labelColor: primary,
                      unselectedLabelColor: const Color(0xFF71717A),
                      indicatorColor: primary,
                      tabs: const [
                        Tab(text: 'Chi tiết'),
                        Tab(text: 'Tổng hợp'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabCtl,
                      children: [
                        _buildEntriesTab(),
                        _buildSummaryTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasActiveFilters =>
      _filterEmployeeId != null ||
      _filterGroupId != null ||
      _filterItemId != null ||
      _filterBranchId != null;

  int get _activeFilterCount {
    var n = 0;
    if (_filterEmployeeId != null) n++;
    if (_filterGroupId != null) n++;
    if (_filterItemId != null) n++;
    if (_filterBranchId != null) n++;
    return n;
  }

  List<Map<String, dynamic>> get _filterableEmployees {
    var list = _employees;
    if (_filterBranchId != null) {
      list = list
          .where((e) => e['branchId']?.toString() == _filterBranchId)
          .toList();
    }
    return list
        .where((e) => (e['id']?.toString() ?? '').isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> get _filterableItems {
    if (_filterGroupId == null) return _items;
    return _items
        .where((i) => i['productGroupId']?.toString() == _filterGroupId)
        .toList();
  }

  String _employeeLabel(String id) {
    final e = _employees.firstWhere(
      (x) => x['id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
    if (e.isEmpty) return id;
    return '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim();
  }

  String _groupLabel(String id) =>
      _groups
          .firstWhere(
            (g) => g['id']?.toString() == id,
            orElse: () => <String, dynamic>{'name': id},
          )['name']
          ?.toString() ??
      id;

  String _itemLabel(String id) =>
      _items
          .firstWhere(
            (i) => i['id']?.toString() == id,
            orElse: () => <String, dynamic>{'name': id},
          )['name']
          ?.toString() ??
      id;

  String _branchLabel(String id) =>
      _branches
          .firstWhere(
            (b) => b['id']?.toString() == id,
            orElse: () => <String, dynamic>{'name': id},
          )['name']
          ?.toString() ??
      id;

  void _clearFilters() {
    setState(() {
      _filterEmployeeId = null;
      _filterGroupId = null;
      _filterItemId = null;
      _filterBranchId = null;
    });
    _reloadCurrentTab();
  }

  String? _validDropdownValue(String? value, Iterable<String?> options) {
    if (value == null || value.isEmpty) return null;
    for (final o in options) {
      if (o == value) return value;
    }
    return null;
  }

  void _showMobileImportMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Color(0xFF059669)),
              title: const Text('Import từ Excel'),
              onTap: () {
                Navigator.pop(ctx);
                _showExcelImportDialog();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.cloud_download, color: Color(0xFF1A73E8)),
              title: const Text('Đồng bộ Google Sheet'),
              onTap: () {
                Navigator.pop(ctx);
                _showGSheetSyncDialog();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarRow() {
    final isMobile = Responsive.isMobile(context);
    const primary = Color(0xFF059669);
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canCreate = perm.canCreate('Production');
    final canExport = perm.canExport('Production');

    Widget buildActions({bool compact = false}) {
      final importBtn = compact
          ? IconButton(
              tooltip: 'Import dữ liệu',
              onPressed: () => _showMobileImportMenu(context),
              icon: const Icon(Icons.file_upload_outlined, size: 20),
              style: IconButton.styleFrom(foregroundColor: primary),
            )
          : PopupMenuButton<String>(
              tooltip: 'Import dữ liệu',
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              padding: EdgeInsets.zero,
              onSelected: (v) {
                if (v == 'excel') _showExcelImportDialog();
                if (v == 'gsheet') _showGSheetSyncDialog();
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                    value: 'excel',
                    child: Row(children: [
                      Icon(Icons.table_chart,
                          size: 18, color: Color(0xFF059669)),
                      SizedBox(width: 8),
                      Text('Import từ Excel'),
                    ])),
                PopupMenuItem(
                    value: 'gsheet',
                    child: Row(children: [
                      Icon(Icons.cloud_download,
                          size: 18, color: Color(0xFF1A73E8)),
                      SizedBox(width: 8),
                      Text('Đồng bộ Google Sheet'),
                    ])),
              ],
            );

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canExport)
            compact
                ? IconButton(
                    tooltip: 'Xuất Excel',
                    onPressed: _isExporting ? null : _exportExcel,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.file_download_outlined, size: 20),
                    style: IconButton.styleFrom(foregroundColor: primary),
                  )
                : OutlinedButton.icon(
                    onPressed: _isExporting ? null : _exportExcel,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.file_download_outlined, size: 16),
                    label: Text(_isExporting ? 'Đang xuất...' : 'Xuất Excel',
                        style: const TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                    ),
                  ),
          importBtn,
          if (canCreate) ...[
            compact
                ? IconButton(
                    tooltip: 'Thêm sản phẩm',
                    onPressed: _showAddProductDialog,
                    icon: const Icon(Icons.inventory_2_outlined, size: 20),
                    style: IconButton.styleFrom(foregroundColor: primary),
                  )
                : OutlinedButton.icon(
                    onPressed: _showAddProductDialog,
                    icon: const Icon(Icons.inventory_2_outlined, size: 16),
                    label: const Text('Thêm SP',
                        style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                    ),
                  ),
            if (!compact)
              FilledButton.icon(
                onPressed: () {
                  if (_items.isEmpty) {
                    NotificationOverlayManager().showError(
                      title: 'Chưa có sản phẩm',
                      message:
                          'Vui lòng thêm sản phẩm trước khi nhập sản lượng',
                    );
                    return;
                  }
                  _showAddEntryDialog();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Nhập SL',
                    style: TextStyle(fontSize: 13)),
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
          ],
        ],
      );
    }

    final toolbarContent = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: isMobile ? 120 : 130, child: _buildPeriodDropdown()),
        const SizedBox(width: 8),
        _buildCompactDateRange(),
        const SizedBox(width: 8),
        if (isMobile) ...[
          OutlinedButton.icon(
            onPressed: _showFilterSheet,
            icon: Badge(
              isLabelVisible: _activeFilterCount > 0,
              label: Text('$_activeFilterCount',
                  style: const TextStyle(fontSize: 10)),
              child: const Icon(Icons.tune, size: 16),
            ),
            label: Text(
              _activeFilterCount > 0 ? 'Lọc ($_activeFilterCount)' : 'Lọc',
              style: const TextStyle(fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: primary,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
          ),
        ] else ...[
          SizedBox(
              width: 150,
              child: _buildFilterDropdownField(
                label: 'Nhân viên',
                value: _filterEmployeeId,
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Tất cả NV')),
                  ..._filterableEmployees.map((e) {
                    final name =
                        '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'
                            .trim();
                    return DropdownMenuItem<String?>(
                      value: e['id']?.toString(),
                      child:
                          Text(name, overflow: TextOverflow.ellipsis),
                    );
                  }),
                ],
                onChanged: (v) {
                  setState(() => _filterEmployeeId = v);
                  _reloadCurrentTab();
                },
              )),
          const SizedBox(width: 6),
          SizedBox(
              width: 120,
              child: _buildFilterDropdownField(
                label: 'Nhóm',
                value: _filterGroupId,
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Tất cả')),
                  ..._groups.map((g) => DropdownMenuItem<String?>(
                        value: g['id']?.toString(),
                        child: Text(g['name']?.toString() ?? '',
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) {
                  setState(() {
                    _filterGroupId = v;
                    if (_filterItemId != null &&
                        !_filterableItems.any((i) =>
                            i['id']?.toString() == _filterItemId)) {
                      _filterItemId = null;
                    }
                  });
                  _reloadCurrentTab();
                },
              )),
          const SizedBox(width: 6),
          SizedBox(
              width: 120,
              child: _buildFilterDropdownField(
                label: 'Sản phẩm',
                value: _filterItemId,
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Tất cả')),
                  ..._filterableItems.map((i) => DropdownMenuItem<String?>(
                        value: i['id']?.toString(),
                        child: Text(i['name']?.toString() ?? '',
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) {
                  setState(() => _filterItemId = v);
                  _reloadCurrentTab();
                },
              )),
          if (_branches.isNotEmpty) ...[
            const SizedBox(width: 6),
            SizedBox(
                width: 120,
                child: _buildFilterDropdownField(
                  label: 'Chi nhánh',
                  value: _filterBranchId,
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Tất cả')),
                    ..._branches.map((b) => DropdownMenuItem<String?>(
                          value: b['id']?.toString(),
                          child: Text(b['name']?.toString() ?? '',
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _filterBranchId = v;
                      if (v != null) _filterEmployeeId = null;
                    });
                    _reloadCurrentTab();
                  },
                )),
          ],
          if (_hasActiveFilters)
            IconButton(
              tooltip: 'Xóa bộ lọc',
              onPressed: _clearFilters,
              icon: const Icon(Icons.filter_alt_off, size: 18),
              visualDensity: VisualDensity.compact,
            ),
        ],
        const Spacer(),
        buildActions(compact: isMobile),
      ],
    );

    return Theme(
      data: Theme.of(context).copyWith(
        canvasColor: Colors.white,
        inputDecorationTheme: const InputDecorationTheme(
          fillColor: Colors.white,
          filled: true,
        ),
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
        ),
        padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 10 : 16, vertical: isMobile ? 6 : 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: toolbarContent,
        ),
      ),
    );
  }

  static const _toolbarFieldText = TextStyle(
    fontSize: 12,
    color: Color(0xFF111827),
  );

  InputDecoration _toolbarFieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
      floatingLabelStyle:
          const TextStyle(fontSize: 12, color: Color(0xFF059669)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF059669)),
      ),
    );
  }

  Widget _buildPeriodDropdown() {
    return DropdownButtonFormField<String>(
      key: ValueKey('period-$_datePreset'),
      initialValue: _datePreset,
      isExpanded: true,
      dropdownColor: Colors.white,
      icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6B7280)),
      decoration: _toolbarFieldDecoration('Kỳ'),
      style: _toolbarFieldText,
      items: const [
        DropdownMenuItem(
            value: 'today',
            child: Text('Hôm nay', style: _toolbarFieldText)),
        DropdownMenuItem(
            value: 'yesterday',
            child: Text('Hôm qua', style: _toolbarFieldText)),
        DropdownMenuItem(
            value: 'this_week',
            child: Text('Tuần này', style: _toolbarFieldText)),
        DropdownMenuItem(
            value: 'last_week',
            child: Text('Tuần trước', style: _toolbarFieldText)),
        DropdownMenuItem(
            value: 'this_month',
            child: Text('Tháng này', style: _toolbarFieldText)),
        DropdownMenuItem(
            value: 'last_month',
            child: Text('Tháng trước', style: _toolbarFieldText)),
        DropdownMenuItem(
            value: 'custom',
            child: Text('Tùy chọn', style: _toolbarFieldText)),
      ],
      onChanged: (v) async {
        if (v == null) return;
        if (v == 'custom') {
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
            locale: const Locale('vi'),
          );
          if (picked != null) {
            setState(() {
              _fromDate = picked.start;
              _toDate = picked.end;
              _datePreset = 'custom';
            });
            _reloadCurrentTab();
          }
        } else {
          final r = ReportDateRangePresets.resolve(v);
          setState(() {
            _fromDate = r.from;
            _toDate = r.to;
            _datePreset = v;
          });
          _reloadCurrentTab();
        }
      },
    );
  }

  Widget _buildCompactDateRange() {
    final fmt = DateFormat('dd/MM/yy');
    return InkWell(
      onTap: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
          locale: const Locale('vi'),
        );
        if (picked != null) {
          setState(() {
            _fromDate = picked.start;
            _toDate = picked.end;
            _datePreset = 'custom';
          });
          _reloadCurrentTab();
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE4E4E7)),
          borderRadius: BorderRadius.circular(8),
          color: const Color(0xFFF8FAFC),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 14, color: Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(
              '${fmt.format(_fromDate)} – ${fmt.format(_toDate)}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportExcel() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final res = await _apiService.getProductionExport(
        fromDate: _fromDate,
        toDate: _toDate,
        employeeId: _filterEmployeeId,
        productGroupId: _filterGroupId,
      );
      if (res['isSuccess'] != true) {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không thể xuất dữ liệu',
        );
        return;
      }
      final raw = res['data'];
      if (raw is! List || raw.isEmpty) {
        NotificationOverlayManager().showError(
            title: 'Thông báo', message: 'Không có dữ liệu để xuất');
        return;
      }
      final fmt = DateFormat('dd/MM/yyyy');
      final rows = <List<dynamic>>[];
      for (int i = 0; i < raw.length; i++) {
        final e = Map<String, dynamic>.from(raw[i] as Map);
        final workDate = DateTime.tryParse(e['workDate']?.toString() ?? '');
        rows.add([
          i + 1,
          workDate != null ? fmt.format(workDate) : '',
          e['employeeName'] ?? '',
          e['employeeCode'] ?? '',
          e['groupName'] ?? e['productGroupName'] ?? '',
          e['productName'] ?? e['productItemName'] ?? '',
          e['quantity'] ?? 0,
          _toDouble(e['unitPrice']),
          _toDouble(e['amount']),
          e['note'] ?? '',
        ]);
      }
      final filterParts = <String>[];
      if (_filterEmployeeId != null) {
        filterParts.add('NV: ${_employeeLabel(_filterEmployeeId!)}');
      }
      if (_filterGroupId != null) {
        filterParts.add('Nhóm: ${_groupLabel(_filterGroupId!)}');
      }
      if (_filterItemId != null) {
        filterParts.add('SP: ${_itemLabel(_filterItemId!)}');
      }
      await ClientExcelExport.export(
        context: context,
        title: 'Báo cáo sản lượng',
        sheetName: 'San luong',
        filePrefix: 'SanLuong',
        headers: const [
          'STT',
          'Ngày',
          'Nhân viên',
          'Mã NV',
          'Nhóm SP',
          'Sản phẩm',
          'Số lượng',
          'Đơn giá',
          'Thành tiền',
          'Ghi chú',
        ],
        rows: rows,
        periodLabel:
            '${fmt.format(_fromDate)} – ${fmt.format(_toDate)}',
        filterLabel:
            filterParts.isEmpty ? null : filterParts.join(' · '),
      );
    } catch (e) {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: 'Không thể xuất Excel: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _buildFilterDropdownField({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String?>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = _validDropdownValue(
      value,
      items.map((i) => i.value),
    );
    return DropdownButtonFormField<String?>(
      key: ValueKey('$label-$safeValue'),
      initialValue: safeValue,
      isExpanded: true,
      dropdownColor: Colors.white,
      icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6B7280)),
      decoration: _toolbarFieldDecoration(label),
      style: _toolbarFieldText,
      items: items,
      onChanged: onChanged,
    );
  }

  void _showFilterSheet() {
    var employeeId = _filterEmployeeId;
    var groupId = _filterGroupId;
    var itemId = _filterItemId;
    var branchId = _filterBranchId;

    showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final sheetEmployees = branchId == null
              ? _employees
              : _employees
                  .where((e) => e['branchId']?.toString() == branchId)
                  .toList();
          final sheetItems = groupId == null
              ? _items
              : _items
                  .where((i) => i['productGroupId']?.toString() == groupId)
                  .toList();

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              16 + MediaQuery.of(ctx).padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('Bộ lọc',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (employeeId != null ||
                        groupId != null ||
                        itemId != null ||
                        branchId != null)
                      TextButton(
                        onPressed: () => setSheet(() {
                          employeeId = null;
                          groupId = null;
                          itemId = null;
                          branchId = null;
                        }),
                        child: const Text('Xóa tất cả',
                            style: TextStyle(color: Color(0xFFEF4444))),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_branches.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    key: ValueKey('sheet-branch-$branchId'),
                    initialValue: branchId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Chi nhánh',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Tất cả chi nhánh')),
                      ..._branches.map((b) => DropdownMenuItem<String?>(
                            value: b['id']?.toString(),
                            child: Text(b['name']?.toString() ?? ''),
                          )),
                    ],
                    onChanged: (v) => setSheet(() {
                      branchId = v;
                      if (v != null) employeeId = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                DropdownButtonFormField<String?>(
                  key: ValueKey('sheet-emp-$employeeId'),
                  initialValue: employeeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Nhân viên',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Tất cả nhân viên')),
                    ...sheetEmployees.map((e) {
                      final name =
                          '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'
                              .trim();
                      return DropdownMenuItem<String?>(
                        value: e['id']?.toString(),
                        child: Text(name),
                      );
                    }),
                  ],
                  onChanged: (v) => setSheet(() => employeeId = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  key: ValueKey('sheet-group-$groupId'),
                  initialValue: groupId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Nhóm sản phẩm',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Tất cả nhóm')),
                    ..._groups.map((g) => DropdownMenuItem<String?>(
                          value: g['id']?.toString(),
                          child: Text(g['name']?.toString() ?? ''),
                        )),
                  ],
                  onChanged: (v) => setSheet(() {
                    groupId = v;
                    if (itemId != null) {
                      final valid = v == null
                          ? _items
                          : _items.where(
                              (i) => i['productGroupId']?.toString() == v);
                      if (!valid.any((i) => i['id']?.toString() == itemId)) {
                        itemId = null;
                      }
                    }
                  }),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  key: ValueKey('sheet-item-$itemId'),
                  initialValue: itemId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sản phẩm',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Tất cả sản phẩm')),
                    ...sheetItems.map((i) => DropdownMenuItem<String?>(
                          value: i['id']?.toString(),
                          child: Text(i['name']?.toString() ?? ''),
                        )),
                  ],
                  onChanged: (v) => setSheet(() => itemId = v),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _filterEmployeeId = employeeId;
                      _filterGroupId = groupId;
                      _filterItemId = itemId;
                      _filterBranchId = branchId;
                    });
                    Navigator.pop(ctx);
                    _reloadCurrentTab();
                  },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Áp dụng'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _reloadProductCatalog() async {
    try {
      final results = await Future.wait([
        _apiService.getProductGroups(),
        _apiService.getProductItems(),
      ]);
      if (results[0]['isSuccess'] == true) {
        _groups = _parseMapList(results[0]['data']);
      }
      if (results[1]['isSuccess'] == true) {
        _items = _parseMapList(results[1]['data']);
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Reload product catalog error: $e');
    }
  }

  void _showAddProductDialog() {
    if (_groups.isEmpty) {
      _showQuickAddGroupDialog(andThenAddProduct: true);
      return;
    }

    final codeCtl = TextEditingController();
    final nameCtl = TextEditingController();
    final unitCtl = TextEditingController(text: 'cái');
    final priceCtl = TextEditingController(text: '0');
    String? selectedGroupId = _filterGroupId ?? _groups.first['id']?.toString();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => ScrollableAlertDialog(
          title: const Row(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 22, color: Color(0xFF059669)),
              SizedBox(width: 8),
              Text('Thêm sản phẩm'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('add-prod-group-$selectedGroupId'),
                  initialValue: selectedGroupId,
                  decoration: const InputDecoration(
                    labelText: 'Nhóm sản phẩm *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _groups
                      .map((g) => DropdownMenuItem(
                            value: g['id']?.toString(),
                            child: Text(g['name']?.toString() ?? ''),
                          ))
                      .toList(),
                  onChanged: (v) => setDlg(() => selectedGroupId = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: codeCtl,
                        decoration: const InputDecoration(
                          labelText: 'Mã SP *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: nameCtl,
                        decoration: const InputDecoration(
                          labelText: 'Tên sản phẩm *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: unitCtl,
                        decoration: const InputDecoration(
                          labelText: 'Đơn vị',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: priceCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Đơn giá',
                          border: OutlineInputBorder(),
                          isDense: true,
                          suffixText: 'đ',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _showQuickAddGroupDialog(),
              child: const Text('Thêm nhóm mới'),
            ),
            const Spacer(),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                if (codeCtl.text.trim().isEmpty ||
                    nameCtl.text.trim().isEmpty ||
                    selectedGroupId == null) {
                  NotificationOverlayManager().showError(
                    title: 'Thiếu thông tin',
                    message: 'Vui lòng nhập mã, tên và chọn nhóm sản phẩm',
                  );
                  return;
                }
                Navigator.pop(ctx);
                final res = await _apiService.createProductItem({
                  'code': codeCtl.text.trim(),
                  'name': nameCtl.text.trim(),
                  'unit': unitCtl.text.trim(),
                  'productGroupId': selectedGroupId,
                  'priceTiers': [
                    {
                      'tierLevel': 1,
                      'minQuantity': 0,
                      'maxQuantity': null,
                      'unitPrice':
                          double.tryParse(priceCtl.text.replaceAll(',', '')) ??
                              0,
                    },
                  ],
                });
                if (res['isSuccess'] == true) {
                  NotificationOverlayManager().showSuccess(
                    title: 'Thành công',
                    message: 'Đã thêm sản phẩm "${nameCtl.text.trim()}"',
                  );
                  await _reloadProductCatalog();
                } else {
                  NotificationOverlayManager().showError(
                    title: 'Lỗi',
                    message: res['message']?.toString() ?? 'Không thể thêm SP',
                  );
                }
              },
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF059669)),
              child: const Text('Thêm'),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickAddGroupDialog({bool andThenAddProduct = false}) {
    final nameCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Thêm nhóm sản phẩm'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: nameCtl,
            decoration: const InputDecoration(
              labelText: 'Tên nhóm *',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              if (nameCtl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              final res = await _apiService.createProductGroup({
                'name': nameCtl.text.trim(),
                'sortOrder': _groups.length,
              });
              if (res['isSuccess'] == true) {
                NotificationOverlayManager().showSuccess(
                  title: 'Thành công',
                  message: 'Đã thêm nhóm "${nameCtl.text.trim()}"',
                );
                await _reloadProductCatalog();
                if (andThenAddProduct && mounted) _showAddProductDialog();
              } else {
                NotificationOverlayManager().showError(
                  title: 'Lỗi',
                  message: res['message']?.toString() ?? 'Không thể thêm nhóm',
                );
              }
            },
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _reloadCurrentTab() {
    if (_tabCtl.index == 0) {
      _page = 1;
      _loadEntries();
    } else {
      _loadSummary();
    }
  }

  // ═══════════ ENTRIES TAB ═══════════
  Widget _buildEntriesTab() {
    final isMobile = Responsive.isMobile(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => _reloadCurrentTab(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.35,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text('Chưa có dữ liệu sản lượng',
                        style: TextStyle(color: Colors.grey[500])),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isMobile) {
      return Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reloadCurrentTab(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: _entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _buildEntryCard(_entries[i], i),
              ),
            ),
          ),
          if (_total > _pageSize) _buildPagination(),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: AppTableScroll(
            minWidth: 1120,
            child: DataTable(
                headingRowColor:
                    WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                columnSpacing: 20,
                columns: const [
                  DataColumn(
                      label: Text('STT',
                          style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text('Ngày',
                          style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text('Nhân viên',
                          style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text('Mã NV',
                          style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text('Nhóm SP',
                          style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text('Sản phẩm',
                          style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text('Số lượng',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      numeric: true),
                  DataColumn(
                      label: Text('Đơn giá',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      numeric: true),
                  DataColumn(
                      label: Text('Thành tiền',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      numeric: true),
                  DataColumn(
                      label: Text('Ghi chú',
                          style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text('',
                          style: TextStyle(fontWeight: FontWeight.w600))),
                ],
                rows: _entries.asMap().entries.map((e) {
                  final i = e.key;
                  final entry = e.value;
                  final workDate = DateTime.tryParse(entry['workDate'] ?? '');
                  return DataRow(cells: [
                    DataCell(Text('${(_page - 1) * _pageSize + i + 1}')),
                    DataCell(Text(workDate != null
                        ? DateFormat('dd/MM/yyyy').format(workDate)
                        : '')),
                    DataCell(Text(entry['employeeName'] ?? '')),
                    DataCell(Text(entry['employeeCode'] ?? '')),
                    DataCell(Text(entry['productGroupName'] ?? '')),
                    DataCell(Text(entry['productItemName'] ?? '')),
                    DataCell(Text('${entry['quantity'] ?? 0}')),
                    DataCell(Text(_currencyFormat
                        .format(_toDouble(entry['unitPrice'])))),
                    DataCell(Text(_currencyFormat
                        .format(_toDouble(entry['amount'])))),
                    DataCell(Text(entry['note'] ?? '',
                        overflow: TextOverflow.ellipsis)),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (Provider.of<PermissionProvider>(context,
                                listen: false)
                            .canEdit('Production'))
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              color: const Color(0xFF64748B),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _showEditEntryDialog(entry),
                            ),
                          ),
                        const SizedBox(width: 4),
                        if (Provider.of<PermissionProvider>(context,
                                listen: false)
                            .canDelete('Production'))
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16),
                              color: const Color(0xFFEF4444),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _confirmDeleteEntry(entry),
                            ),
                          ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
          ),
        ),
        if (_total > _pageSize) _buildPagination(),
      ],
    );
  }

  Widget _buildEntryCard(Map<String, dynamic> entry, int index) {
    final workDate = DateTime.tryParse(entry['workDate'] ?? '');
    final amount = _toDouble(entry['amount']);
    const primary = Color(0xFF059669);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEditEntryDialog(entry),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: primary.withValues(alpha: 0.1),
                    child: Text(
                      _avatarLetter(entry['employeeName']),
                      style: const TextStyle(
                          color: primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry['employeeName'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${entry['employeeCode'] ?? ''} · ${workDate != null ? DateFormat('dd/MM/yyyy').format(workDate) : ''}',
                          style: const TextStyle(
                              color: Color(0xFF71717A), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_currencyFormat.format(amount)} đ',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: primary),
                      ),
                      Text(
                        'SL: ${entry['quantity'] ?? 0}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF71717A)),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry['productItemName'] ?? '',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (entry['productGroupName'] != null)
                          Text(
                            entry['productGroupName'],
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    'ĐG: ${_currencyFormat.format(_toDouble(entry['unitPrice']))}',
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              if (entry['note'] != null &&
                  entry['note'].toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  entry['note'],
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // Action buttons row
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canEdit('Production'))
                    _miniBtn(Icons.edit_outlined, const Color(0xFF3B82F6),
                        'Sửa', () => _showEditEntryDialog(entry)),
                  const SizedBox(width: 8),
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canDelete('Production'))
                    _miniBtn(Icons.delete_outline, const Color(0xFFEF4444),
                        'Xóa', () => _confirmDeleteEntry(entry)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniBtn(
      IconData icon, Color color, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _page > 1
                ? () {
                    _page--;
                    _loadEntries();
                  }
                : null,
          ),
          Text('Trang $_page / ${(_total / _pageSize).ceil()}',
              style: const TextStyle(fontSize: 13)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _page < (_total / _pageSize).ceil()
                ? () {
                    _page++;
                    _loadEntries();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  // ═══════════ SUMMARY TAB ═══════════
  Widget _buildSummaryTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_summaries.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => _loadSummary(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.35,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.analytics_outlined,
                        size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text('Chưa có dữ liệu tổng hợp',
                        style: TextStyle(color: Colors.grey[500])),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _loadSummary(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: _summaries.asMap().entries.map((e) {
          final summary = e.value;
          final items = _parseMapList(summary['items']);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE4E4E7)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            const Color(0xFF059669).withValues(alpha: 0.1),
                        child: Text(
                          '${e.key + 1}',
                          style: const TextStyle(
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(summary['employeeName'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15)),
                            Text(
                              'Mã: ${summary['employeeCode'] ?? ''}',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF71717A)),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_currencyFormat.format(_toDouble(summary['totalAmount']))} đ',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Color(0xFF059669)),
                          ),
                          Text(
                            'Tổng SL: ${summary['totalQuantity'] ?? 0}',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF71717A)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (items.isNotEmpty) ...[
                    const Divider(height: 24),
                    ...items.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(
                                      '${item['groupName'] ?? ''} > ${item['productName'] ?? ''}',
                                      style: const TextStyle(fontSize: 13))),
                              Text('SL: ${item['quantity'] ?? 0}',
                                  style: const TextStyle(
                                      fontSize: 13, color: Color(0xFF64748B))),
                              const SizedBox(width: 16),
                              Text(
                                '${_currencyFormat.format(_toDouble(item['amount']))} đ',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF059669)),
                              ),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
          );
          }).toList(),
        ),
      ),
    );
  }

  // ═══════════ ADD / EDIT / DELETE ═══════════

  void _showAddEntryDialog() {
    final isMobile = Responsive.isMobile(context);
    String? selEmployeeId;
    DateTime workDate = DateTime.now();

    // Each line: productItemId, quantity controller, note controller
    final lines = <_BatchLine>[_BatchLine()];

    Widget buildFormContent(StateSetter setDlgState) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Employee + Date row
          if (isMobile) ...[
            DropdownButtonFormField<String>(
              initialValue: selEmployeeId,
              decoration: const InputDecoration(
                  labelText: 'Nhân viên *',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: _employees.map((e) {
                final name =
                    '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim();
                return DropdownMenuItem(
                    value: e['id']?.toString(),
                    child: Text('$name (${e['employeeCode'] ?? ''})'));
              }).toList(),
              onChanged: (v) => setDlgState(() => selEmployeeId = v),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: workDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) setDlgState(() => workDate = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Ngày *',
                    border: OutlineInputBorder(),
                    isDense: true),
                child: Text(DateFormat('dd/MM/yyyy').format(workDate),
                    style: const TextStyle(fontSize: 14)),
              ),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: selEmployeeId,
                    decoration: const InputDecoration(
                        labelText: 'Nhân viên *',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: _employees.map((e) {
                      final name =
                          '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'
                              .trim();
                      return DropdownMenuItem(
                          value: e['id']?.toString(),
                          child: Text('$name (${e['employeeCode'] ?? ''})'));
                    }).toList(),
                    onChanged: (v) => setDlgState(() => selEmployeeId = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: workDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDlgState(() => workDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Ngày *',
                          border: OutlineInputBorder(),
                          isDense: true),
                      child: Text(DateFormat('dd/MM/yyyy').format(workDate),
                          style: const TextStyle(fontSize: 14)),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          // Header
          Row(
            children: [
              const Text('Danh sách sản phẩm',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setDlgState(() => lines.add(_BatchLine()));
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Thêm dòng'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Product lines
          ...lines.asMap().entries.map((entry) {
            final idx = entry.key;
            final line = entry.value;
            if (isMobile) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: line.productItemId,
                            decoration: const InputDecoration(
                                hintText: 'Chọn sản phẩm',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10)),
                            isExpanded: true,
                            items: _items.map((item) {
                              final gn = item['productGroupName'] ??
                                  item['groupName'] ??
                                  '';
                              return DropdownMenuItem(
                                  value: item['id']?.toString(),
                                  child: Text('${item['name']} ($gn)',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13)));
                            }).toList(),
                            onChanged: (v) =>
                                setDlgState(() => line.productItemId = v),
                          ),
                        ),
                        if (lines.length > 1)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 18, color: Colors.red),
                            padding: const EdgeInsets.only(left: 4),
                            constraints: const BoxConstraints(),
                            onPressed: () =>
                                setDlgState(() => lines.removeAt(idx)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: line.qtyCtl,
                            decoration: const InputDecoration(
                                hintText: 'Số lượng',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10)),
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: line.noteCtl,
                            decoration: const InputDecoration(
                                hintText: 'Ghi chú',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10)),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: DropdownButtonFormField<String>(
                      initialValue: line.productItemId,
                      decoration: const InputDecoration(
                          hintText: 'Chọn SP',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10)),
                      isExpanded: true,
                      items: _items.map((item) {
                        final gn =
                            item['productGroupName'] ?? item['groupName'] ?? '';
                        return DropdownMenuItem(
                            value: item['id']?.toString(),
                            child: Text('${item['name']} ($gn)',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)));
                      }).toList(),
                      onChanged: (v) =>
                          setDlgState(() => line.productItemId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: line.qtyCtl,
                      decoration: const InputDecoration(
                          hintText: 'SL',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10)),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: line.noteCtl,
                      decoration: const InputDecoration(
                          hintText: 'Ghi chú',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10)),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: lines.length > 1
                        ? IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 18, color: Colors.red),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () =>
                                setDlgState(() => lines.removeAt(idx)),
                          )
                        : const SizedBox(),
                  ),
                ],
              ),
            );
          }),
        ],
      );
    }

    Future<void> onSubmit() async {
      if (selEmployeeId == null) return;
      final validLines = lines.where(
          (l) => l.productItemId != null && l.qtyCtl.text.trim().isNotEmpty);
      if (validLines.isEmpty) return;
      Navigator.pop(context);

      if (validLines.length == 1) {
        final line = validLines.first;
        final res = await _apiService.createProductionEntry({
          'employeeId': selEmployeeId,
          'productItemId': line.productItemId,
          'workDate': workDate.toIso8601String(),
          'quantity': double.tryParse(line.qtyCtl.text.trim()) ?? 0,
          'note': line.noteCtl.text.trim(),
        });
        if (res['isSuccess'] == true) {
          appNotification.showSuccess(
              title: 'Thành công', message: 'Đã thêm sản lượng');
          _reloadCurrentTab();
        } else {
          appNotification.showError(
              title: 'Lỗi', message: res['message'] ?? 'Lỗi');
        }
      } else {
        final entries = validLines
            .map((l) => {
                  'employeeId': selEmployeeId,
                  'productItemId': l.productItemId,
                  'workDate': workDate.toIso8601String(),
                  'quantity': double.tryParse(l.qtyCtl.text.trim()) ?? 0,
                  'note': l.noteCtl.text.trim(),
                })
            .toList();
        final res = await _apiService.createProductionEntryBatch(entries);
        if (res['isSuccess'] == true) {
          appNotification.showSuccess(
              title: 'Thành công',
              message: 'Đã thêm ${entries.length} sản phẩm');
          _reloadCurrentTab();
        } else {
          appNotification.showError(
              title: 'Lỗi', message: res['message'] ?? 'Lỗi');
        }
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Nhập sản lượng'),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  actions: [
                    TextButton(
                      onPressed: onSubmit,
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white),
                      child: const Text('Lưu'),
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: buildFormContent(setDlgState),
                ),
              ),
            );
          }
          return ScrollableAlertDialog(
            title: const Text('Nhập sản lượng'),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: buildFormContent(setDlgState),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy')),
              FilledButton(
                onPressed: onSubmit,
                child: const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditEntryDialog(Map<String, dynamic> entry) {
    final isMobile = Responsive.isMobile(context);
    String? selEmployeeId = entry['employeeId']?.toString();
    String? selItemId = entry['productItemId']?.toString();
    DateTime workDate =
        DateTime.tryParse(entry['workDate'] ?? '') ?? DateTime.now();
    final qtyCtl = TextEditingController(text: '${entry['quantity'] ?? ''}');
    final noteCtl = TextEditingController(text: entry['note'] ?? '');

    if (selEmployeeId != null &&
        !_employees.any((e) => e['id']?.toString() == selEmployeeId)) {
      selEmployeeId = null;
    }
    if (selItemId != null &&
        !_items.any((item) => item['id']?.toString() == selItemId)) {
      selItemId = null;
    }

    Widget buildForm(StateSetter setDlgState) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: selEmployeeId,
            decoration: const InputDecoration(
                labelText: 'Nhân viên *', border: OutlineInputBorder()),
            items: _employees.map((e) {
              final name =
                  '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim();
              return DropdownMenuItem(
                  value: e['id']?.toString(),
                  child: Text('$name (${e['employeeCode'] ?? ''})'));
            }).toList(),
            onChanged: (v) => setDlgState(() => selEmployeeId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: selItemId,
            decoration: const InputDecoration(
                labelText: 'Sản phẩm *', border: OutlineInputBorder()),
            items: _items.map((item) {
              final groupName =
                  item['productGroupName'] ?? item['groupName'] ?? '';
              return DropdownMenuItem(
                  value: item['id']?.toString(),
                  child: Text('${item['name']} ($groupName)'));
            }).toList(),
            onChanged: (v) => setDlgState(() => selItemId = v),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: workDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) setDlgState(() => workDate = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Ngày làm việc *', border: OutlineInputBorder()),
              child: Text(DateFormat('dd/MM/yyyy').format(workDate)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: qtyCtl,
            decoration: const InputDecoration(
                labelText: 'Số lượng *', border: OutlineInputBorder()),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtl,
            decoration: const InputDecoration(
                labelText: 'Ghi chú', border: OutlineInputBorder()),
          ),
        ],
      );
    }

    Future<void> onSubmit() async {
      if (selEmployeeId == null ||
          selItemId == null ||
          qtyCtl.text.trim().isEmpty) {
        return;
      }
      Navigator.pop(context);
      final res =
          await _apiService.updateProductionEntry(entry['id'].toString(), {
        'employeeId': selEmployeeId,
        'productItemId': selItemId,
        'workDate': workDate.toIso8601String(),
        'quantity': double.tryParse(qtyCtl.text.trim()) ?? 0,
        'note': noteCtl.text.trim(),
      });
      if (res['isSuccess'] == true) {
        appNotification.showSuccess(
            title: 'Thành công', message: 'Đã cập nhật');
        _reloadCurrentTab();
      } else {
        appNotification.showError(
            title: 'Lỗi', message: res['message'] ?? 'Lỗi');
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Sửa sản lượng'),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  actions: [
                    TextButton(
                      onPressed: onSubmit,
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white),
                      child: const Text('Lưu'),
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: buildForm(setDlgState),
                ),
              ),
            );
          }
          return ScrollableAlertDialog(
            title: const Text('Sửa sản lượng'),
            content: SizedBox(
              width: 450,
              child: buildForm(setDlgState),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy')),
              FilledButton(
                onPressed: onSubmit,
                child: const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════ EXCEL IMPORT ═══════════

  void _downloadSampleExcel() async {
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['Mẫu sản lượng'];

      // Header row
      sheet.appendRow([
        xl.TextCellValue('Ngày (dd/MM/yyyy)'),
        xl.TextCellValue('Mã nhân viên'),
        xl.TextCellValue('Mã sản phẩm'),
        xl.TextCellValue('Số lượng'),
        xl.TextCellValue('Ghi chú'),
      ]);

      // Sample data rows
      final today = DateFormat('dd/MM/yyyy').format(DateTime.now());
      final yesterday = DateFormat('dd/MM/yyyy')
          .format(DateTime.now().subtract(const Duration(days: 1)));
      sheet.appendRow([
        xl.TextCellValue(today),
        xl.TextCellValue('NV001'),
        xl.TextCellValue('SP001'),
        const xl.DoubleCellValue(10),
        xl.TextCellValue('Sản phẩm A'),
      ]);
      sheet.appendRow([
        xl.TextCellValue(today),
        xl.TextCellValue('NV001'),
        xl.TextCellValue('SP002'),
        const xl.DoubleCellValue(5),
        xl.TextCellValue(''),
      ]);
      sheet.appendRow([
        xl.TextCellValue(yesterday),
        xl.TextCellValue('NV002'),
        xl.TextCellValue('SP001'),
        const xl.DoubleCellValue(8),
        xl.TextCellValue('Ca sáng'),
      ]);

      excel.delete('Sheet1');

      final bytes = excel.encode();
      if (bytes != null) {
        await file_saver.saveFileBytes(
            Uint8List.fromList(bytes),
            'mau_san_lương.xlsx',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        appNotification.showSuccess(
            title: 'Thành công', message: 'Đã tải file mẫu');
      }
    } catch (e) {
      appNotification.showError(
          title: 'Lỗi', message: 'Không thể tạo file mẫu: $e');
    }
  }

  void _showExcelImportDialog() {
    DateTime defaultDate = DateTime.now();
    List<Map<String, dynamic>> previewRows = [];
    bool isParsed = false;
    bool hasDateColumn = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isMobile = Responsive.isMobile(ctx);

          Future<void> onImport() async {
            if (!isParsed || previewRows.isEmpty) return;
            Navigator.pop(ctx);
            final res = await _apiService.importProductionFromExcel({
              'workDate': defaultDate.toIso8601String(),
              'rows': previewRows,
            });
            if (res['isSuccess'] == true) {
              final data = res['data'];
              final created = data?['created'] ?? 0;
              final errors = List<String>.from(data?['errors'] ?? []);
              appNotification.showSuccess(
                  title: 'Import thành công',
                  message:
                      'Đã tạo $created bản ghi${errors.isNotEmpty ? '\n${errors.length} lỗi' : ''}');
              _reloadCurrentTab();
            } else {
              appNotification.showError(
                  title: 'Lỗi import', message: res['message'] ?? 'Lỗi');
            }
          }

          final formContent = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Instructions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Định dạng Excel:',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    SizedBox(height: 4),
                    Text(
                        '• Cột A: Ngày (dd/MM/yyyy) — nếu không có sẽ dùng ngày mặc định',
                        style: TextStyle(fontSize: 12)),
                    Text('• Cột B: Mã nhân viên',
                        style: TextStyle(fontSize: 12)),
                    Text('• Cột C: Mã sản phẩm',
                        style: TextStyle(fontSize: 12)),
                    Text('• Cột D: Số lượng', style: TextStyle(fontSize: 12)),
                    Text('• Cột E: Ghi chú (tùy chọn)',
                        style: TextStyle(fontSize: 12)),
                    Text('• Dòng 1 là tiêu đề (bỏ qua)',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Download sample + Date picker row
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _downloadSampleExcel,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Tải file mẫu',
                        style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF059669),
                      side: const BorderSide(color: Color(0xFF059669)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: defaultDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setDlgState(() => defaultDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                            labelText: 'Ngày mặc định (khi cột Ngày trống)',
                            border: OutlineInputBorder(),
                            isDense: true),
                        child:
                            Text(DateFormat('dd/MM/yyyy').format(defaultDate)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Pick file button
              Center(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['xlsx', 'xls'],
                      withData: true,
                    );
                    if (result == null || result.files.single.bytes == null) {
                      return;
                    }
                    try {
                      final excel =
                          xl.Excel.decodeBytes(result.files.single.bytes!);
                      final sheet = excel.tables.values.first;
                      final rows = <Map<String, dynamic>>[];
                      bool detectedDateCol = false;

                      // Detect if column A is a date column by checking header
                      if (sheet.maxRows > 0) {
                        final header = sheet.row(0);
                        final headerA = header.isNotEmpty
                            ? header[0]
                                    ?.value
                                    ?.toString()
                                    .trim()
                                    .toLowerCase() ??
                                ''
                            : '';
                        detectedDateCol = headerA.contains('ngày') ||
                            headerA.contains('date') ||
                            headerA.contains('ngay');
                      }

                      for (int i = 1; i < sheet.maxRows; i++) {
                        final row = sheet.row(i);
                        if (row.isEmpty) continue;

                        if (detectedDateCol) {
                          // Format: Date | EmpCode | ProdCode | Qty | Note
                          final dateStr = row.isNotEmpty
                              ? row[0]?.value?.toString().trim() ?? ''
                              : '';
                          final empCode = row.length > 1
                              ? row[1]?.value?.toString().trim() ?? ''
                              : '';
                          final prodCode = row.length > 2
                              ? row[2]?.value?.toString().trim() ?? ''
                              : '';
                          final qty = row.length > 3
                              ? double.tryParse(
                                      row[3]?.value?.toString() ?? '') ??
                                  0.0
                              : 0.0;
                          final note = row.length > 4
                              ? row[4]?.value?.toString().trim() ?? ''
                              : '';
                          if (empCode.isNotEmpty &&
                              prodCode.isNotEmpty &&
                              qty > 0) {
                            rows.add({
                              'workDate': dateStr,
                              'employeeCode': empCode,
                              'productCode': prodCode,
                              'quantity': qty,
                              'note': note,
                            });
                          }
                        } else {
                          // Legacy format: EmpCode | ProdCode | Qty | Note
                          final empCode = row.isNotEmpty
                              ? row[0]?.value?.toString().trim() ?? ''
                              : '';
                          final prodCode = row.length > 1
                              ? row[1]?.value?.toString().trim() ?? ''
                              : '';
                          final qty = row.length > 2
                              ? double.tryParse(
                                      row[2]?.value?.toString() ?? '') ??
                                  0.0
                              : 0.0;
                          final note = row.length > 3
                              ? row[3]?.value?.toString().trim() ?? ''
                              : '';
                          if (empCode.isNotEmpty &&
                              prodCode.isNotEmpty &&
                              qty > 0) {
                            rows.add({
                              'employeeCode': empCode,
                              'productCode': prodCode,
                              'quantity': qty,
                              'note': note,
                            });
                          }
                        }
                      }
                      setDlgState(() {
                        previewRows = rows;
                        isParsed = true;
                        hasDateColumn = detectedDateCol;
                      });
                    } catch (e) {
                      appNotification.showError(
                          title: 'Lỗi',
                          message: 'Không đọc được file Excel: $e');
                    }
                  },
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                      isParsed ? 'Chọn file khác' : 'Chọn file Excel (.xlsx)'),
                ),
              ),
              // Preview
              if (isParsed) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Xem trước: ${previewRows.length} dòng hợp lệ',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    if (hasDateColumn) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Có cột Ngày',
                            style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF059669),
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowHeight: 36,
                        dataRowMinHeight: 32,
                        dataRowMaxHeight: 36,
                        columnSpacing: 16,
                        columns: [
                          if (hasDateColumn)
                            const DataColumn(
                                label: Text('Ngày',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600))),
                          const DataColumn(
                              label: Text('Mã NV',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600))),
                          const DataColumn(
                              label: Text('Mã SP',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600))),
                          const DataColumn(
                              label: Text('SL',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600))),
                          const DataColumn(
                              label: Text('Ghi chú',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600))),
                        ],
                        rows: previewRows
                            .take(10)
                            .map((r) => DataRow(cells: [
                                  if (hasDateColumn)
                                    DataCell(Text('${r['workDate'] ?? ''}',
                                        style: const TextStyle(fontSize: 12))),
                                  DataCell(Text('${r['employeeCode']}',
                                      style: const TextStyle(fontSize: 12))),
                                  DataCell(Text('${r['productCode']}',
                                      style: const TextStyle(fontSize: 12))),
                                  DataCell(Text('${r['quantity']}',
                                      style: const TextStyle(fontSize: 12))),
                                  DataCell(Text('${r['note'] ?? ''}',
                                      style: const TextStyle(fontSize: 12))),
                                ]))
                            .toList(),
                      ),
                    ),
                  ),
                ),
                if (previewRows.length > 10)
                  Text('... và ${previewRows.length - 10} dòng nữa',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF71717A))),
              ],
            ],
          );

          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Import từ Excel'),
                  leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  actions: [
                    TextButton(
                      onPressed:
                          !isParsed || previewRows.isEmpty ? null : onImport,
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white),
                      child: const Text('Import'),
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: formContent,
                ),
              ),
            );
          }

          return ScrollableAlertDialog(
            title: const Row(
              children: [
                Icon(Icons.table_chart, color: Color(0xFF059669), size: 24),
                SizedBox(width: 8),
                Text('Import từ Excel'),
              ],
            ),
            content: SizedBox(
              width: 650,
              child: SingleChildScrollView(child: formContent),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy')),
              FilledButton(
                onPressed: !isParsed || previewRows.isEmpty ? null : onImport,
                child: const Text('Import'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════ GOOGLE SHEET SYNC ═══════════

  void _showGSheetSyncDialog() {
    final urlCtl = TextEditingController();
    List<String> sheetNames = [];
    // Map: sheetName -> {selected: bool, date: DateTime}
    Map<String, Map<String, dynamic>> tabConfig = {};
    bool isTesting = false;
    bool isSyncing = false;
    bool isConnected = false;

    DateTime tryParseTabDate(String tabName) {
      // Try common date formats in tab names
      for (final fmt in [
        'dd-MM-yyyy',
        'dd/MM/yyyy',
        'yyyy-MM-dd',
        'd-M-yyyy',
        'd/M/yyyy',
        'ddMMyyyy'
      ]) {
        try {
          return DateFormat(fmt).parseStrict(tabName.trim());
        } catch (_) {}
      }
      return DateTime.now();
    }

    bool looksLikeDate(String tabName) {
      for (final fmt in [
        'dd-MM-yyyy',
        'dd/MM/yyyy',
        'yyyy-MM-dd',
        'd-M-yyyy',
        'd/M/yyyy',
        'ddMMyyyy'
      ]) {
        try {
          DateFormat(fmt).parseStrict(tabName.trim());
          return true;
        } catch (_) {}
      }
      return false;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isMobile = Responsive.isMobile(ctx);

          Future<void> onSync() async {
            if (!isConnected ||
                isSyncing ||
                !tabConfig.values.any((c) => c['selected'] == true)) {
              return;
            }
            setDlgState(() => isSyncing = true);

            final tabs = <Map<String, dynamic>>[];
            for (final name in sheetNames) {
              final cfg = tabConfig[name]!;
              if (cfg['selected'] == true) {
                tabs.add({
                  'sheetName': name,
                  'workDate': (cfg['date'] as DateTime).toIso8601String(),
                });
              }
            }

            final res = tabs.length == 1
                ? await _apiService.syncProductionFromGSheet({
                    'spreadsheetUrl': urlCtl.text.trim(),
                    'sheetName': tabs.first['sheetName'],
                    'workDate': tabs.first['workDate'],
                  })
                : await _apiService.syncProductionFromGSheetMulti({
                    'spreadsheetUrl': urlCtl.text.trim(),
                    'tabs': tabs,
                  });

            setDlgState(() => isSyncing = false);
            if (res['isSuccess'] == true) {
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              final data = res['data'];
              final created = data?['created'] ?? data?['totalCreated'] ?? 0;
              final errors = List<String>.from(data?['errors'] ?? []);
              appNotification.showSuccess(
                  title: 'Đồng bộ thành công',
                  message:
                      'Đã tạo $created bản ghi từ ${tabs.length} sheet${errors.isNotEmpty ? ' (${errors.length} lỗi)' : ''}');
              _reloadCurrentTab();
            } else {
              appNotification.showError(
                  title: 'Lỗi đồng bộ', message: res['message'] ?? 'Lỗi');
            }
          }

          final syncEnabled = isConnected &&
              !isSyncing &&
              tabConfig.values.any((c) => c['selected'] == true);

          final formContent = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Instructions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Định dạng Google Sheet:',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    SizedBox(height: 4),
                    Text('• Cột đầu tiên: Mã nhân viên',
                        style: TextStyle(fontSize: 12)),
                    Text(
                        '• Các cột tiếp theo: Tên hoặc mã sản phẩm → giá trị = số lượng',
                        style: TextStyle(fontSize: 12)),
                    Text(
                        '• Mỗi tab sheet = 1 ngày (đặt tên tab theo ngày dd-MM-yyyy để tự nhận)',
                        style: TextStyle(fontSize: 12)),
                    Text('• Chọn nhiều tab để đồng bộ nhiều ngày cùng lúc',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Spreadsheet URL
              TextField(
                controller: urlCtl,
                decoration: InputDecoration(
                  labelText: 'URL Google Sheet *',
                  hintText: 'https://docs.google.com/spreadsheets/d/...',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: isTesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(
                          icon: const Icon(Icons.link, size: 20),
                          tooltip: 'Kiểm tra kết nối',
                          onPressed: () async {
                            if (urlCtl.text.trim().isEmpty) return;
                            setDlgState(() {
                              isTesting = true;
                              isConnected = false;
                            });
                            final res = await _apiService
                                .testProductionGSheetConnection({
                              'spreadsheetUrl': urlCtl.text.trim(),
                              'sheetName': '',
                              'workDate': DateTime.now().toIso8601String(),
                            });
                            if (res['isSuccess'] == true &&
                                res['data']?['connected'] == true) {
                              final names = List<String>.from(
                                  res['data']?['sheetNames'] ?? []);
                              final config = <String, Map<String, dynamic>>{};
                              for (final name in names) {
                                config[name] = {
                                  'selected': names.length ==
                                      1, // auto-select if single sheet
                                  'date': tryParseTabDate(name),
                                  'isDateName': looksLikeDate(name),
                                };
                              }
                              setDlgState(() {
                                sheetNames = names;
                                tabConfig = config;
                                isConnected = true;
                                isTesting = false;
                              });
                            } else {
                              setDlgState(() {
                                isTesting = false;
                              });
                              appNotification.showError(
                                  title: 'Lỗi kết nối',
                                  message: res['message'] ??
                                      'Không thể kết nối Google Sheet');
                            }
                          },
                        ),
                ),
              ),
              if (isConnected) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Color(0xFF059669), size: 16),
                    const SizedBox(width: 4),
                    Text('Đã kết nối (${sheetNames.length} sheets)',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF059669))),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setDlgState(() {
                          for (final name in sheetNames) {
                            tabConfig[name]!['selected'] = true;
                          }
                        });
                      },
                      child: const Text('Chọn tất cả',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Sheet tabs list
                Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sheetNames.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, idx) {
                      final name = sheetNames[idx];
                      final cfg = tabConfig[name]!;
                      final isSelected = cfg['selected'] as bool;
                      final date = cfg['date'] as DateTime;
                      final isDateName = cfg['isDateName'] as bool;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            Checkbox(
                              value: isSelected,
                              activeColor: const Color(0xFF1A73E8),
                              onChanged: (v) => setDlgState(
                                  () => cfg['selected'] = v ?? false),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: isSelected
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFF94A3B8),
                                      )),
                                  if (isDateName)
                                    const Text('Tự nhận ngày từ tên tab',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF059669))),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: InkWell(
                                onTap: isSelected
                                    ? () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: date,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2030),
                                        );
                                        if (picked != null) {
                                          setDlgState(
                                              () => cfg['date'] = picked);
                                        }
                                      }
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFFCBD5E1)
                                            : const Color(0xFFE2E8F0)),
                                    borderRadius: BorderRadius.circular(6),
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFFF8FAFC),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today,
                                          size: 12,
                                          color: isSelected
                                              ? const Color(0xFF64748B)
                                              : const Color(0xFFCBD5E1)),
                                      const SizedBox(width: 4),
                                      Text(
                                        DateFormat('dd/MM/yyyy').format(date),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isSelected
                                              ? const Color(0xFF0F172A)
                                              : const Color(0xFFCBD5E1),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          );

          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Đồng bộ Google Sheet'),
                  leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  actions: [
                    TextButton(
                      onPressed: syncEnabled ? onSync : null,
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white),
                      child: isSyncing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Đồng bộ'),
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: formContent,
                ),
              ),
            );
          }

          return ScrollableAlertDialog(
            title: const Row(
              children: [
                Icon(Icons.cloud_download, color: Color(0xFF1A73E8), size: 24),
                SizedBox(width: 8),
                Text('Đồng bộ Google Sheet'),
              ],
            ),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(child: formContent),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy')),
              FilledButton(
                onPressed: syncEnabled ? onSync : null,
                child: isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Đồng bộ'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteEntry(Map<String, dynamic> entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Xác nhận xóa'),
        content: const Text('Xóa bản ghi sản lượng này?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Xóa')),
        ],
      ),
    );
    if (confirm == true) {
      final res =
          await _apiService.deleteProductionEntry(entry['id'].toString());
      if (res['isSuccess'] == true) {
        appNotification.showSuccess(title: 'Thành công', message: 'Đã xóa');
        _reloadCurrentTab();
      } else {
        appNotification.showError(
            title: 'Lỗi xóa',
            message: res['message'] ?? 'Không thể xóa bản ghi');
      }
    }
  }
}

class _BatchLine {
  String? productItemId;
  final TextEditingController qtyCtl = TextEditingController();
  final TextEditingController noteCtl = TextEditingController();
}
