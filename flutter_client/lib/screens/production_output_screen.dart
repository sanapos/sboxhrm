import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xl;
import '../utils/file_saver.dart' as file_saver;
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';
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
  String? _filterEmployeeId;
  String? _filterGroupId;
  String? _filterItemId;
  int _page = 1;
  final int _pageSize = 50;

  // Mobile UI state
  bool _showMobileFilters = false;

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
    try {
      final empRes = await _apiService.getEmployees();
      _employees = (empRes as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? [];

      final results = await Future.wait([
        _apiService.getProductGroups(),
        _apiService.getProductItems(),
      ]);
      if (results[0]['isSuccess'] == true) {
        _groups = List<Map<String, dynamic>>.from(results[0]['data'] ?? []);
      }
      if (results[1]['isSuccess'] == true) {
        _items = List<Map<String, dynamic>>.from(results[1]['data'] ?? []);
      }
    } catch (e) {
      debugPrint('Load base data error: $e');
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Không thể tải dữ liệu cơ bản');
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
        _entries = List<Map<String, dynamic>>.from(data['items'] ?? []);
        _total = data['total'] ?? 0;
      }
    } catch (e) {
      debugPrint('Load entries error: $e');
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Không thể tải dữ liệu sản lượng');
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
        _summaries = List<Map<String, dynamic>>.from(res['data'] ?? []);
      }
    } catch (e) {
      debugPrint('Load summary error: $e');
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Không thể tải tổng hợp sản lượng');
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    const primary = Color(0xFF059669);
    return Scaffold(
      floatingActionButton: isMobile && Provider.of<PermissionProvider>(context, listen: false).canCreate('Production')
          ? FloatingActionButton.extended(
              onPressed: _items.isEmpty ? null : _showAddEntryDialog,
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
            padding: EdgeInsets.fromLTRB(
                isMobile ? 14 : 24,
                isMobile ? 12 : 18,
                isMobile ? 14 : 24,
                isMobile ? 12 : 14),
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
                                  color:
                                      Colors.white.withValues(alpha: 0.8)),
                            ),
                        ],
                      ),
                    ),
                    // Filter toggle (mobile)
                    if (isMobile) ...[
                      GestureDetector(
                        onTap: () => setState(
                            () => _showMobileFilters = !_showMobileFilters),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                                alpha: _showMobileFilters ? 0.25 : 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Stack(
                            children: [
                              Icon(
                                _showMobileFilters
                                    ? Icons.filter_alt
                                    : Icons.filter_alt_outlined,
                                size: 18,
                                color: Colors.white,
                              ),
                              if (_hasActiveFilters)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                        color: Colors.orangeAccent,
                                        shape: BoxShape.circle),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          _showMobileImportMenu(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.file_upload_outlined,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ],
                    // Desktop buttons
                    if (!isMobile) ...[
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.file_upload_outlined,
                            color: Colors.white70),
                        tooltip: 'Import dữ liệu',
                        onSelected: (v) {
                          if (v == 'excel') _showExcelImportDialog();
                          if (v == 'gsheet') _showGSheetSyncDialog();
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                              value: 'excel',
                              child: Row(children: [
                                Icon(Icons.table_chart,
                                    size: 18, color: Color(0xFF059669)),
                                SizedBox(width: 8),
                                Text('Import từ Excel'),
                              ])),
                          const PopupMenuItem(
                              value: 'gsheet',
                              child: Row(children: [
                                Icon(Icons.cloud_download,
                                    size: 18, color: Color(0xFF1A73E8)),
                                SizedBox(width: 8),
                                Text('Đồng bộ Google Sheet'),
                              ])),
                        ],
                      ),
                      const SizedBox(width: 4),
                      if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Production'))
                      ElevatedButton.icon(
                        onPressed:
                            _items.isEmpty ? null : _showAddEntryDialog,
                        icon: const Icon(Icons.add,
                            size: 18, color: Colors.white),
                        label: const Text('Nhập sản lượng',
                            style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.2),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // ═══════ FILTERS (collapsible on mobile) ═══════
          if (!isMobile || _showMobileFilters)
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 24,
                  vertical: isMobile ? 10 : 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _buildDateFilter('Từ ngày', _fromDate, (d) {
                    setState(() => _fromDate = d);
                    _reloadCurrentTab();
                  }),
                  _buildDateFilter('Đến ngày', _toDate, (d) {
                    setState(() => _toDate = d);
                    _reloadCurrentTab();
                  }),
                  _buildDropdown(
                    'Nhân viên',
                    _filterEmployeeId,
                    _employees.map((e) {
                      final name =
                          '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'
                              .trim();
                      return DropdownMenuItem(
                          value: e['id']?.toString(), child: Text(name));
                    }).toList(),
                    (v) {
                      setState(() => _filterEmployeeId = v);
                      _reloadCurrentTab();
                    },
                  ),
                  _buildDropdown(
                    'Nhóm SP',
                    _filterGroupId,
                    _groups
                        .map((g) => DropdownMenuItem(
                            value: g['id']?.toString(),
                            child: Text(g['name'] ?? '')))
                        .toList(),
                    (v) {
                      setState(() => _filterGroupId = v);
                      _reloadCurrentTab();
                    },
                  ),
                ],
              ),
            ),

          // ═══════ TABS ═══════
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

          // ═══════ BODY ═══════
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabCtl,
                    children: [
                      _buildEntriesTab(),
                      _buildSummaryTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  bool get _hasActiveFilters =>
      _filterEmployeeId != null ||
      _filterGroupId != null ||
      _filterItemId != null;

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
    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Chưa có dữ liệu sản lượng',
                style: TextStyle(color: Colors.grey[500])),
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
          child: SingleChildScrollView(
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('STT', style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('Ngày', style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('Nhân viên', style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('Mã NV', style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('Nhóm SP', style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('Sản phẩm', style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('Số lượng', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                  DataColumn(label: Text('Đơn giá', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                  DataColumn(label: Text('Thành tiền', style: TextStyle(fontWeight: FontWeight.w600)), numeric: true),
                  DataColumn(label: Text('Ghi chú', style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.w600))),
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
                    DataCell(Text(_currencyFormat.format(
                        (entry['unitPrice'] ?? 0).toDouble()))),
                    DataCell(Text(_currencyFormat.format(
                        (entry['amount'] ?? 0).toDouble()))),
                    DataCell(Text(entry['note'] ?? '',
                        overflow: TextOverflow.ellipsis)),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (Provider.of<PermissionProvider>(context, listen: false).canEdit('Production'))
                        SizedBox(
                          width: 28, height: 28,
                          child: IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            color: const Color(0xFF64748B),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _showEditEntryDialog(entry),
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (Provider.of<PermissionProvider>(context, listen: false).canDelete('Production'))
                        SizedBox(
                          width: 28, height: 28,
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
        ),
        if (_total > _pageSize) _buildPagination(),
      ],
    );
  }

  Widget _buildEntryCard(Map<String, dynamic> entry, int index) {
    final workDate = DateTime.tryParse(entry['workDate'] ?? '');
    final amount = (entry['amount'] ?? 0).toDouble();
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
                      (entry['employeeName'] ?? '?')[0],
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
                    'ĐG: ${_currencyFormat.format((entry['unitPrice'] ?? 0).toDouble())}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B)),
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
                  if (Provider.of<PermissionProvider>(context, listen: false).canEdit('Production'))
                  _miniBtn(Icons.edit_outlined, const Color(0xFF3B82F6),
                      'Sửa', () => _showEditEntryDialog(entry)),
                  const SizedBox(width: 8),
                  if (Provider.of<PermissionProvider>(context, listen: false).canDelete('Production'))
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
    if (_summaries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.analytics_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Chưa có dữ liệu tổng hợp',
                style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _summaries.asMap().entries.map((e) {
          final summary = e.value;
          final items =
              List<Map<String, dynamic>>.from(summary['items'] ?? []);
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
                            '${_currencyFormat.format((summary['totalAmount'] ?? 0).toDouble())} đ',
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
                                '${_currencyFormat.format((item['amount'] ?? 0).toDouble())} đ',
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
    );
  }

  // ═══════════ HELPERS ═══════════

  Widget _buildDateFilter(
      String label, DateTime value, ValueChanged<DateTime> onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCBD5E1)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: ',
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
            Text(DateFormat('dd/MM/yyyy').format(value),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            const Icon(Icons.calendar_today, size: 14, color: Color(0xFF71717A)),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, String? value,
      List<DropdownMenuItem<String>> dropdownItems, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF71717A))),
          items: [
            DropdownMenuItem<String>(value: null, child: Text('Tất cả $label')),
            ...dropdownItems,
          ],
          onChanged: onChanged,
          isDense: true,
          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
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
                          child:
                              Text('$name (${e['employeeCode'] ?? ''})'));
                    }).toList(),
                    onChanged: (v) =>
                        setDlgState(() => selEmployeeId = v),
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
                      child: Text(
                          DateFormat('dd/MM/yyyy').format(workDate),
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
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
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
                                  item['groupName'] ?? '';
                              return DropdownMenuItem(
                                  value: item['id']?.toString(),
                                  child: Text('${item['name']} ($gn)',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13)));
                            }).toList(),
                            onChanged: (v) => setDlgState(
                                () => line.productItemId = v),
                          ),
                        ),
                        if (lines.length > 1)
                          IconButton(
                            icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 18,
                                color: Colors.red),
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
                        final gn = item['productGroupName'] ??
                            item['groupName'] ?? '';
                        return DropdownMenuItem(
                            value: item['id']?.toString(),
                            child: Text(
                                '${item['name']} ($gn)',
                                overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(fontSize: 13)));
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
                            icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 18,
                                color: Colors.red),
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
      final validLines = lines.where((l) =>
          l.productItemId != null && l.qtyCtl.text.trim().isNotEmpty);
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
        final res =
            await _apiService.createProductionEntryBatch(entries);
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
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
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
          return AlertDialog(
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
    final qtyCtl =
        TextEditingController(text: '${entry['quantity'] ?? ''}');
    final noteCtl = TextEditingController(text: entry['note'] ?? '');

    if (selEmployeeId != null && !_employees.any((e) => e['id']?.toString() == selEmployeeId)) {
      selEmployeeId = null;
    }
    if (selItemId != null && !_items.any((item) => item['id']?.toString() == selItemId)) {
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
      final res = await _apiService.updateProductionEntry(
          entry['id'].toString(), {
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
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
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
          return AlertDialog(
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
      final yesterday = DateFormat('dd/MM/yyyy').format(DateTime.now().subtract(const Duration(days: 1)));
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
        await file_saver.saveFileBytes(Uint8List.fromList(bytes), 'mau_san_luong.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
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
                  message: 'Đã tạo $created bản ghi${errors.isNotEmpty ? '\n${errors.length} lỗi' : ''}');
              _reloadCurrentTab();
            } else {
              appNotification.showError(title: 'Lỗi import', message: res['message'] ?? 'Lỗi');
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
                        Text('Định dạng Excel:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        SizedBox(height: 4),
                        Text('• Cột A: Ngày (dd/MM/yyyy) — nếu không có sẽ dùng ngày mặc định', style: TextStyle(fontSize: 12)),
                        Text('• Cột B: Mã nhân viên', style: TextStyle(fontSize: 12)),
                        Text('• Cột C: Mã sản phẩm', style: TextStyle(fontSize: 12)),
                        Text('• Cột D: Số lượng', style: TextStyle(fontSize: 12)),
                        Text('• Cột E: Ghi chú (tùy chọn)', style: TextStyle(fontSize: 12)),
                        Text('• Dòng 1 là tiêu đề (bỏ qua)', style: TextStyle(fontSize: 12)),
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
                        label: const Text('Tải file mẫu', style: TextStyle(fontSize: 13)),
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
                            if (picked != null) setDlgState(() => defaultDate = picked);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                                labelText: 'Ngày mặc định (khi cột Ngày trống)',
                                border: OutlineInputBorder(),
                                isDense: true),
                            child: Text(DateFormat('dd/MM/yyyy').format(defaultDate)),
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
                        if (result == null || result.files.single.bytes == null) return;
                        try {
                          final excel = xl.Excel.decodeBytes(result.files.single.bytes!);
                          final sheet = excel.tables.values.first;
                          final rows = <Map<String, dynamic>>[];
                          bool detectedDateCol = false;

                          // Detect if column A is a date column by checking header
                          if (sheet.maxRows > 0) {
                            final header = sheet.row(0);
                            final headerA = header.isNotEmpty ? header[0]?.value?.toString().trim().toLowerCase() ?? '' : '';
                            detectedDateCol = headerA.contains('ngày') || headerA.contains('date') || headerA.contains('ngay');
                          }

                          for (int i = 1; i < sheet.maxRows; i++) {
                            final row = sheet.row(i);
                            if (row.isEmpty) continue;

                            if (detectedDateCol) {
                              // Format: Date | EmpCode | ProdCode | Qty | Note
                              final dateStr = row.isNotEmpty ? row[0]?.value?.toString().trim() ?? '' : '';
                              final empCode = row.length > 1 ? row[1]?.value?.toString().trim() ?? '' : '';
                              final prodCode = row.length > 2 ? row[2]?.value?.toString().trim() ?? '' : '';
                              final qty = row.length > 3 ? double.tryParse(row[3]?.value?.toString() ?? '') ?? 0.0 : 0.0;
                              final note = row.length > 4 ? row[4]?.value?.toString().trim() ?? '' : '';
                              if (empCode.isNotEmpty && prodCode.isNotEmpty && qty > 0) {
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
                              final empCode = row.isNotEmpty ? row[0]?.value?.toString().trim() ?? '' : '';
                              final prodCode = row.length > 1 ? row[1]?.value?.toString().trim() ?? '' : '';
                              final qty = row.length > 2 ? double.tryParse(row[2]?.value?.toString() ?? '') ?? 0.0 : 0.0;
                              final note = row.length > 3 ? row[3]?.value?.toString().trim() ?? '' : '';
                              if (empCode.isNotEmpty && prodCode.isNotEmpty && qty > 0) {
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
                          appNotification.showError(title: 'Lỗi', message: 'Không đọc được file Excel: $e');
                        }
                      },
                      icon: const Icon(Icons.upload_file),
                      label: Text(isParsed ? 'Chọn file khác' : 'Chọn file Excel (.xlsx)'),
                    ),
                  ),
                  // Preview
                  if (isParsed) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Xem trước: ${previewRows.length} dòng hợp lệ',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        if (hasDateColumn) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Có cột Ngày', style: TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w500)),
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
                            dataRowMinHeight: 32, dataRowMaxHeight: 36,
                            columnSpacing: 16,
                            columns: [
                              if (hasDateColumn)
                                const DataColumn(label: Text('Ngày', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                              const DataColumn(label: Text('Mã NV', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                              const DataColumn(label: Text('Mã SP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                              const DataColumn(label: Text('SL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                              const DataColumn(label: Text('Ghi chú', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            ],
                            rows: previewRows.take(10).map((r) => DataRow(cells: [
                              if (hasDateColumn)
                                DataCell(Text('${r['workDate'] ?? ''}', style: const TextStyle(fontSize: 12))),
                              DataCell(Text('${r['employeeCode']}', style: const TextStyle(fontSize: 12))),
                              DataCell(Text('${r['productCode']}', style: const TextStyle(fontSize: 12))),
                              DataCell(Text('${r['quantity']}', style: const TextStyle(fontSize: 12))),
                              DataCell(Text('${r['note'] ?? ''}', style: const TextStyle(fontSize: 12))),
                            ])).toList(),
                          ),
                        ),
                      ),
                    ),
                    if (previewRows.length > 10)
                      Text('... và ${previewRows.length - 10} dòng nữa',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
                  ],
                ],
              );

          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Import từ Excel'),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  actions: [
                    TextButton(
                      onPressed: !isParsed || previewRows.isEmpty ? null : onImport,
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
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

          return AlertDialog(
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
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
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
      for (final fmt in ['dd-MM-yyyy', 'dd/MM/yyyy', 'yyyy-MM-dd', 'd-M-yyyy', 'd/M/yyyy', 'ddMMyyyy']) {
        try {
          return DateFormat(fmt).parseStrict(tabName.trim());
        } catch (_) {}
      }
      return DateTime.now();
    }

    bool looksLikeDate(String tabName) {
      for (final fmt in ['dd-MM-yyyy', 'dd/MM/yyyy', 'yyyy-MM-dd', 'd-M-yyyy', 'd/M/yyyy', 'ddMMyyyy']) {
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
            if (!isConnected || isSyncing || !tabConfig.values.any((c) => c['selected'] == true)) return;
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
                  message: 'Đã tạo $created bản ghi từ ${tabs.length} sheet${errors.isNotEmpty ? ' (${errors.length} lỗi)' : ''}');
              _reloadCurrentTab();
            } else {
              appNotification.showError(
                  title: 'Lỗi đồng bộ', message: res['message'] ?? 'Lỗi');
            }
          }

          final syncEnabled = isConnected && !isSyncing && tabConfig.values.any((c) => c['selected'] == true);

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
                        Text('Định dạng Google Sheet:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        SizedBox(height: 4),
                        Text('• Cột đầu tiên: Mã nhân viên', style: TextStyle(fontSize: 12)),
                        Text('• Các cột tiếp theo: Tên hoặc mã sản phẩm → giá trị = số lượng', style: TextStyle(fontSize: 12)),
                        Text('• Mỗi tab sheet = 1 ngày (đặt tên tab theo ngày dd-MM-yyyy để tự nhận)', style: TextStyle(fontSize: 12)),
                        Text('• Chọn nhiều tab để đồng bộ nhiều ngày cùng lúc', style: TextStyle(fontSize: 12)),
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
                          ? const SizedBox(width: 20, height: 20, child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2)))
                          : IconButton(
                              icon: const Icon(Icons.link, size: 20),
                              tooltip: 'Kiểm tra kết nối',
                              onPressed: () async {
                                if (urlCtl.text.trim().isEmpty) return;
                                setDlgState(() { isTesting = true; isConnected = false; });
                                final res = await _apiService.testProductionGSheetConnection({
                                  'spreadsheetUrl': urlCtl.text.trim(),
                                  'sheetName': '',
                                  'workDate': DateTime.now().toIso8601String(),
                                });
                                if (res['isSuccess'] == true && res['data']?['connected'] == true) {
                                  final names = List<String>.from(res['data']?['sheetNames'] ?? []);
                                  final config = <String, Map<String, dynamic>>{};
                                  for (final name in names) {
                                    config[name] = {
                                      'selected': names.length == 1, // auto-select if single sheet
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
                                  setDlgState(() { isTesting = false; });
                                  appNotification.showError(
                                      title: 'Lỗi kết nối',
                                      message: res['message'] ?? 'Không thể kết nối Google Sheet');
                                }
                              },
                            ),
                    ),
                  ),
                  if (isConnected) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF059669), size: 16),
                        const SizedBox(width: 4),
                        Text('Đã kết nối (${sheetNames.length} sheets)',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF059669))),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setDlgState(() {
                              for (final name in sheetNames) {
                                tabConfig[name]!['selected'] = true;
                              }
                            });
                          },
                          child: const Text('Chọn tất cả', style: TextStyle(fontSize: 12)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  activeColor: const Color(0xFF1A73E8),
                                  onChanged: (v) => setDlgState(() => cfg['selected'] = v ?? false),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                      )),
                                      if (isDateName)
                                        const Text('Tự nhận ngày từ tên tab',
                                            style: TextStyle(fontSize: 10, color: Color(0xFF059669))),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: InkWell(
                                    onTap: isSelected ? () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: date,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) setDlgState(() => cfg['date'] = picked);
                                    } : null,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: isSelected ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0)),
                                        borderRadius: BorderRadius.circular(6),
                                        color: isSelected ? Colors.white : const Color(0xFFF8FAFC),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.calendar_today, size: 12,
                                              color: isSelected ? const Color(0xFF64748B) : const Color(0xFFCBD5E1)),
                                          const SizedBox(width: 4),
                                          Text(
                                            DateFormat('dd/MM/yyyy').format(date),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
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
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  actions: [
                    TextButton(
                      onPressed: syncEnabled ? onSync : null,
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      child: isSyncing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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

          return AlertDialog(
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
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              FilledButton(
                onPressed: syncEnabled ? onSync : null,
                child: isSyncing
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
      builder: (ctx) => AlertDialog(
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
            title: 'Lỗi xóa', message: res['message'] ?? 'Không thể xóa bản ghi');
      }
    }
  }
}

class _BatchLine {
  String? productItemId;
  final TextEditingController qtyCtl = TextEditingController();
  final TextEditingController noteCtl = TextEditingController();
}
