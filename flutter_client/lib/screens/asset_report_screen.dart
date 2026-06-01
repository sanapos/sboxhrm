import 'package:flutter/material.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/excel_report_builder.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart' as file_saver;
import '../widgets/notification_overlay.dart';
import '../utils/report_screen_helpers.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm_responsive_list_layout.dart';
import 'package:excel/excel.dart' as excel_lib;

const _theme = Color(0xFF059669);
const _rowH = 52.0;
const _hdrH = 42.0;

class AssetReportScreen extends StatefulWidget {
  const AssetReportScreen({super.key});

  @override
  State<AssetReportScreen> createState() => _AssetReportScreenState();
}

class _AssetReportScreenState extends State<AssetReportScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  final _fmtDate = DateFormat('dd/MM/yyyy');
  final _fmtMoney = NumberFormat('#,##0', 'vi_VN');
  late TabController _tabs;

  int? _statusFilter;
  int? _typeFilter;
  String? _categoryId;
  String _search = '';
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'this_month';
  String _department = '';
  int? _stockTypeFilter;
  String? _inventoryId;
  bool _onlyVariance = true;
  int _warrantyDays = 30;
  bool _includeExpiredWarranty = false;

  bool _loading = false;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _register = [];
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _transfers = [];
  List<Map<String, dynamic>> _stockLedger = [];
  Map<String, dynamic> _stockSummary = {};
  List<Map<String, dynamic>> _inventoryVariance = [];
  Map<String, dynamic> _invVarianceSummary = {};
  List<Map<String, dynamic>> _warrantyItems = [];
  Map<String, dynamic> _warrantySummary = {};
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _inventories = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _loadTab(_tabs.index);
    });
    _loadCategories();
    _loadInventories();
    _loadTab(0);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final r = await _api.getAssetCategories();
      if (r['isSuccess'] == true && mounted) {
        final data = r['data'];
        final list = data is List ? data : (data is Map ? data['items'] : null);
        if (list is List) {
          setState(() {
            _categories = list
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadInventories() async {
    try {
      final r = await _api.getAssetInventories(pageSize: 100);
      if (r['isSuccess'] == true && mounted) {
        final data = r['data'];
        final items = data is Map ? data['items'] : (data is List ? data : null);
        if (items is List) {
          setState(() {
            _inventories = items
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadTab(int index) async {
    setState(() => _loading = true);
    try {
      switch (index) {
        case 0:
          final r = await _api.getAssetReportSummary(
            status: _statusFilter,
            assetType: _typeFilter,
            categoryId: _categoryId,
          );
          if (r['isSuccess'] == true && r['data'] is Map && mounted) {
            setState(() => _summary = Map<String, dynamic>.from(r['data'] as Map));
          }
          break;
        case 1:
          final r = await _api.getAssetReportRegister(
            status: _statusFilter,
            assetType: _typeFilter,
            categoryId: _categoryId,
            search: _search.isEmpty ? null : _search,
          );
          if (r['isSuccess'] == true && mounted) {
            final data = r['data'];
            final items = data is Map ? data['items'] : null;
            setState(() => _register = _parseList(items));
          }
          break;
        case 2:
          final r = await _api.getAssetReportAssignments(
            status: _statusFilter,
            department: _department.isEmpty ? null : _department,
          );
          if (r['isSuccess'] == true && mounted) {
            final data = r['data'];
            final items = data is Map ? data['assignments'] : null;
            setState(() => _assignments = _parseList(items));
          }
          break;
        case 3:
          final r = await _api.getAssetReportTransfers(
            from: _from,
            to: _to,
          );
          if (r['isSuccess'] == true && mounted) {
            final data = r['data'];
            final items = data is Map ? data['items'] : null;
            setState(() => _transfers = _parseList(items));
          }
          break;
        case 4:
          final r = await _api.getAssetReportStockLedger(
            from: _from,
            to: _to,
            transactionType: _stockTypeFilter,
          );
          if (r['isSuccess'] == true && r['data'] is Map && mounted) {
            final data = Map<String, dynamic>.from(r['data'] as Map);
            setState(() {
              _stockSummary = data;
              _stockLedger = _parseList(data['items']);
            });
          }
          break;
        case 5:
          final r = await _api.getAssetReportInventoryVariance(
            inventoryId: _inventoryId,
            onlyVariance: _onlyVariance,
            from: _from,
            to: _to,
          );
          if (r['isSuccess'] == true && r['data'] is Map && mounted) {
            final data = Map<String, dynamic>.from(r['data'] as Map);
            setState(() {
              _invVarianceSummary = data;
              _inventoryVariance = _parseList(data['items']);
            });
          }
          break;
        case 6:
          final r = await _api.getAssetReportWarrantyExpiring(
            days: _warrantyDays,
            includeExpired: _includeExpiredWarranty,
          );
          if (r['isSuccess'] == true && r['data'] is Map && mounted) {
            final data = Map<String, dynamic>.from(r['data'] as Map);
            setState(() {
              _warrantySummary = data;
              _warrantyItems = _parseList(data['items']);
            });
          }
          break;
      }
    } catch (e) {
      debugPrint('asset_report load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _parseList(dynamic items) {
    if (items is! List) return [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static double _money(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<void> _exportRegister() async {
    if (_register.isEmpty) {
      NotificationOverlayManager()
          .showError(title: 'Thông báo', message: 'Không có dữ liệu để xuất');
      return;
    }
    const headers = [
      'Mã TS',
      'Tên',
      'Loại',
      'Danh mục',
      'Trạng thái',
      'SL',
      'Giá mua',
      'Giá trị HT',
      'Người giữ',
      'Vị trí',
    ];
    final wb = ExcelReportBuilder.createWorkbook(sheetName: 'Danh muc tai san');
    final sh = wb['Danh muc tai san'];
    final auth = context.read<AuthProvider>();
    final exportCtx = ExcelReportContext.resolve(
      token: auth.token,
      email: auth.user?.email,
      fullName: auth.user?.fullName,
    );
    final layout = ExcelReportBuilder.applyMeta(
      sh,
      title: 'DANH MỤC TÀI SẢN',
      columnCount: headers.length,
      storeName: exportCtx.storeName,
      exportedBy: exportCtx.exportedBy,
      rowCount: _register.length,
    );
    ExcelReportBuilder.applyHeaderRow(sh, layout.headerRow, headers);
    var rowIdx = layout.dataStartRow;
    for (final r in _register) {
      ExcelReportBuilder.writeRow(sh, rowIdx++, [
        excel_lib.TextCellValue(r['assetCode']?.toString() ?? ''),
        excel_lib.TextCellValue(r['name']?.toString() ?? ''),
        excel_lib.TextCellValue(r['assetTypeName']?.toString() ?? ''),
        excel_lib.TextCellValue(r['categoryName']?.toString() ?? ''),
        excel_lib.TextCellValue(r['statusName']?.toString() ?? ''),
        excel_lib.TextCellValue('${r['quantity'] ?? 1}'),
        excel_lib.DoubleCellValue(_money(r['purchasePrice'])),
        excel_lib.DoubleCellValue(
            _money(r['currentValue'] ?? r['purchasePrice'])),
        excel_lib.TextCellValue(r['assigneeName']?.toString() ?? ''),
        excel_lib.TextCellValue(r['location']?.toString() ?? ''),
      ]);
    }
    final bytes = wb.encode();
    if (bytes == null) return;
    await file_saver.saveFileBytes(
      bytes,
      'bao-cao-tai-san-danh-muc.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  @override
  Widget build(BuildContext context) {
    final canExport = context.watch<PermissionProvider>().canExport('AssetReport') ||
        context.watch<PermissionProvider>().canExport('Asset');
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: Column(
        children: [
          _buildHeader(canExport),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _theme))
                : isMobile
                    ? HrmMobileNestedTabLayout(
                    headerSections: [_buildFilters()],
                    tabBar: TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      labelColor: _theme,
                      unselectedLabelColor: Colors.grey[600],
                      indicatorColor: _theme,
                      tabAlignment: TabAlignment.start,
                      tabs: const [
                        Tab(text: 'Tổng hợp'),
                        Tab(text: 'Danh mục'),
                        Tab(text: 'Cấp phát'),
                        Tab(text: 'Chuyển giao'),
                        Tab(text: 'Nhập/xuất kho'),
                        Tab(text: 'Kiểm kê CL'),
                        Tab(text: 'Bảo hành'),
                      ],
                    ),
                    tabBarView: TabBarView(
                      controller: _tabs,
                      children: [
                        _buildSummaryTab(),
                        _buildRegisterTab(),
                        _buildAssignmentsTab(),
                        _buildTransfersTab(),
                        _buildStockLedgerTab(),
                        _buildInventoryVarianceTab(),
                        _buildWarrantyTab(),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      _buildFilters(),
                      Material(
                        color: Colors.white,
                        child: TabBar(
                          controller: _tabs,
                          isScrollable: true,
                          labelColor: _theme,
                          unselectedLabelColor: Colors.grey[600],
                          indicatorColor: _theme,
                          tabAlignment: TabAlignment.start,
                          tabs: const [
                            Tab(text: 'Tổng hợp'),
                            Tab(text: 'Danh mục'),
                            Tab(text: 'Cấp phát'),
                            Tab(text: 'Chuyển giao'),
                            Tab(text: 'Nhập/xuất kho'),
                            Tab(text: 'Kiểm kê CL'),
                            Tab(text: 'Bảo hành'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                                controller: _tabs,
                                children: [
                                  _buildSummaryTab(),
                                  _buildRegisterTab(),
                                  _buildAssignmentsTab(),
                                  _buildTransfersTab(),
                                  _buildStockLedgerTab(),
                                  _buildInventoryVarianceTab(),
                                  _buildWarrantyTab(),
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

  Widget _buildHeader(bool canExport) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.inventory_2, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Báo cáo tài sản',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  Text('Kho, kiểm kê, bảo hành, cấp phát',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            if (canExport && _tabs.index == 1)
              IconButton(
                tooltip: 'Xuất Excel',
                onPressed: _exportRegister,
                icon: const Icon(Icons.download, color: Colors.white),
              ),
            IconButton(
              onPressed: () => _loadTab(_tabs.index),
              icon: const Icon(Icons.refresh, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final showDate =
        _tabs.index == 3 || _tabs.index == 4 || _tabs.index == 5;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showDate) ...[
            ReportDateRangeFilterBar(
              from: _from,
              to: _to,
              preset: _datePreset,
              onChanged: (f, t, p) {
                setState(() {
                  _from = f;
                  _to = t;
                  _datePreset = p;
                });
                _loadTab(_tabs.index);
              },
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<int?>(
              value: _statusFilter,
              decoration: const InputDecoration(
                labelText: 'Trạng thái',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Tất cả')),
                DropdownMenuItem(value: 0, child: Text('Đang dùng')),
                DropdownMenuItem(value: 5, child: Text('Trong kho')),
                DropdownMenuItem(value: 1, child: Text('Bảo trì')),
                DropdownMenuItem(value: 2, child: Text('Hỏng')),
              ],
              onChanged: (v) {
                setState(() => _statusFilter = v);
                _loadTab(_tabs.index);
              },
            ),
          ),
          if (_tabs.index <= 1)
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String?>(
                value: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Danh mục',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tất cả')),
                  ..._categories.map((c) => DropdownMenuItem(
                        value: c['id']?.toString(),
                        child: Text(c['name']?.toString() ?? '-',
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) {
                  setState(() => _categoryId = v);
                  _loadTab(_tabs.index);
                },
              ),
            ),
          if (_tabs.index == 1)
            SizedBox(
              width: 180,
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Tìm mã/tên/serial',
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onSubmitted: (v) {
                  setState(() => _search = v.trim());
                  _loadTab(1);
                },
              ),
            ),
          if (_tabs.index == 2)
            SizedBox(
              width: 160,
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Phòng ban',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) {
                  setState(() => _department = v.trim());
                  _loadTab(2);
                },
              ),
            ),
          if (_tabs.index == 4)
            SizedBox(
              width: 130,
              child: DropdownButtonFormField<int?>(
                value: _stockTypeFilter,
                decoration: const InputDecoration(
                  labelText: 'Loại GD',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Tất cả')),
                  DropdownMenuItem(value: 0, child: Text('Nhập kho')),
                  DropdownMenuItem(value: 1, child: Text('Xuất kho')),
                  DropdownMenuItem(value: 2, child: Text('Điều chỉnh')),
                ],
                onChanged: (v) {
                  setState(() => _stockTypeFilter = v);
                  _loadTab(4);
                },
              ),
            ),
          if (_tabs.index == 5) ...[
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                value: _inventoryId,
                decoration: const InputDecoration(
                  labelText: 'Đợt kiểm kê',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tất cả')),
                  ..._inventories.map((inv) => DropdownMenuItem(
                        value: inv['id']?.toString(),
                        child: Text(
                          '${inv['inventoryCode'] ?? ''} - ${inv['name'] ?? ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                ],
                onChanged: (v) {
                  setState(() => _inventoryId = v);
                  _loadTab(5);
                },
              ),
            ),
            FilterChip(
              label: const Text('Chỉ chênh lệch'),
              selected: _onlyVariance,
              onSelected: (v) {
                setState(() => _onlyVariance = v);
                _loadTab(5);
              },
            ),
          ],
          if (_tabs.index == 6) ...[
            SizedBox(
              width: 120,
              child: DropdownButtonFormField<int>(
                value: _warrantyDays,
                decoration: const InputDecoration(
                  labelText: 'Trong (ngày)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 7, child: Text('7 ngày')),
                  DropdownMenuItem(value: 30, child: Text('30 ngày')),
                  DropdownMenuItem(value: 60, child: Text('60 ngày')),
                  DropdownMenuItem(value: 90, child: Text('90 ngày')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _warrantyDays = v);
                    _loadTab(6);
                  }
                },
              ),
            ),
            FilterChip(
              label: const Text('Gồm đã hết hạn'),
              selected: _includeExpiredWarranty,
              onSelected: (v) {
                setState(() => _includeExpiredWarranty = v);
                _loadTab(6);
              },
            ),
          ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTab() {
    if (_summary.isEmpty) {
      return const Center(child: Text('Không có dữ liệu'));
    }
    final cards = [
      ('Tổng TS', '${_summary['totalAssets'] ?? 0}', Icons.inventory),
      ('Đang dùng', '${_summary['activeAssets'] ?? 0}', Icons.check_circle_outline),
      ('Trong kho', '${_summary['inStockAssets'] ?? 0}', Icons.warehouse_outlined),
      ('Đã cấp', '${_summary['assignedAssets'] ?? 0}', Icons.person_outline),
      ('BH sắp hết', '${_summary['warrantyExpiringSoon'] ?? 0}', Icons.warning_amber),
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map((c) => _statCard(c.$1, c.$2, c.$3))
              .toList(),
        ),
        const SizedBox(height: 12),
        _moneyCard('Tổng giá mua', _money(_summary['totalPurchaseValue'])),
        _moneyCard('Giá trị hiện tại', _money(_summary['totalCurrentValue'])),
        const SizedBox(height: 16),
        _groupSection('Theo trạng thái', _summary['byStatus']),
        _groupSection('Theo loại', _summary['byType']),
        _groupSection('Theo danh mục', _summary['byCategory']),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _theme, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: _theme)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _moneyCard(String label, double value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const Spacer(),
          Text('${_fmtMoney.format(value)} đ',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: _theme, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _groupSection(String title, dynamic groups) {
    if (groups is! List || groups.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const Divider(),
              ...groups.map((g) {
                final m = Map<String, dynamic>.from(g as Map);
                final name = m['statusName'] ??
                    m['assetTypeName'] ??
                    m['categoryName'] ??
                    '-';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(name.toString())),
                      Text('${m['count'] ?? 0}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterTab() => _dataTable(
        _register,
        ['Mã TS', 'Tên', 'Loại', 'Danh mục', 'Trạng thái', 'Người giữ', 'Giá trị'],
        (r) => [
          r['assetCode']?.toString() ?? '',
          r['name']?.toString() ?? '',
          r['assetTypeName']?.toString() ?? '',
          r['categoryName']?.toString() ?? '',
          r['statusName']?.toString() ?? '',
          r['assigneeName']?.toString() ?? '-',
          _fmtMoney.format(_money(r['currentValue'] ?? r['purchasePrice'])),
        ],
      );

  Widget _buildAssignmentsTab() => _dataTable(
        _assignments,
        ['Mã TS', 'Tên TS', 'NV', 'Phòng ban', 'Trạng thái', 'Giá trị'],
        (r) => [
          r['assetCode']?.toString() ?? '',
          r['assetName']?.toString() ?? '',
          r['employeeName']?.toString() ?? '',
          r['department']?.toString() ?? '',
          r['statusName']?.toString() ?? '',
          _fmtMoney.format(_money(r['value'])),
        ],
      );

  Widget _buildTransfersTab() => _dataTable(
        _transfers,
        ['Ngày', 'Loại', 'Mã TS', 'Tên', 'Từ', 'Đến', 'SL'],
        (r) {
          final d = r['transferDate']?.toString() ?? '';
          DateTime? dt;
          try {
            dt = DateTime.parse(d);
          } catch (_) {}
          return [
            dt != null ? _fmtDate.format(dt.toLocal()) : d,
            r['transferTypeName']?.toString() ?? '',
            r['assetCode']?.toString() ?? '',
            r['assetName']?.toString() ?? '',
            r['fromUserName']?.toString() ?? '-',
            r['toUserName']?.toString() ?? '-',
            '${r['quantity'] ?? 1}',
          ];
        },
      );

  Widget _buildStockLedgerTab() {
    return Column(
      children: [
        if (_stockSummary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _miniChip('Giao dịch', '${_stockSummary['totalCount'] ?? 0}'),
                _miniChip('Nhập', '${_stockSummary['totalStockIn'] ?? 0}'),
                _miniChip('Xuất', '${_stockSummary['totalStockOut'] ?? 0}'),
                _miniChip('Điều chỉnh', '${_stockSummary['totalAdjustments'] ?? 0}'),
              ],
            ),
          ),
        Expanded(
          child: _dataTable(
            _stockLedger,
            ['Ngày', 'Loại', 'Mã TS', 'Tên', 'SL', 'Tồn sau', 'Phiếu', 'Người TH'],
            (r) {
              final d = r['transactionDate']?.toString() ?? '';
              DateTime? dt;
              try {
                dt = DateTime.parse(d);
              } catch (_) {}
              return [
                dt != null ? _fmtDate.format(dt.toLocal()) : d,
                r['transactionTypeName']?.toString() ?? '',
                r['assetCode']?.toString() ?? '',
                r['assetName']?.toString() ?? '',
                '${r['quantity'] ?? 0}',
                '${r['balanceAfter'] ?? 0}',
                r['referenceCode']?.toString() ?? '',
                r['performedByName']?.toString() ?? '',
              ];
            },
          ),
        ),
      ],
    );
  }

  Widget _miniChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _theme.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label: $value',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildInventoryVarianceTab() {
    return Column(
      children: [
        if (_invVarianceSummary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                _miniChip('Dòng', '${_invVarianceSummary['totalCount'] ?? 0}'),
                _miniChip('SL lệch', '${_invVarianceSummary['varianceCount'] ?? 0}'),
                _miniChip('Có vấn đề', '${_invVarianceSummary['issueCount'] ?? 0}'),
              ],
            ),
          ),
        Expanded(
          child: _dataTable(
            _inventoryVariance,
            ['Đợt KK', 'Mã TS', 'Tên', 'Kỳ vọng', 'Thực tế', 'Chênh', 'TT', 'Vấn đề'],
            (r) => [
              r['inventoryCode']?.toString() ?? '',
              r['assetCode']?.toString() ?? '',
              r['assetName']?.toString() ?? '',
              '${r['expectedQuantity'] ?? 0}',
              '${r['actualQuantity'] ?? '-'}',
              '${r['variance'] ?? 0}',
              r['conditionName']?.toString() ?? '',
              r['hasIssue'] == true ? (r['issueDescription']?.toString() ?? 'Có') : '',
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWarrantyTab() {
    return Column(
      children: [
        if (_warrantySummary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                _miniChip('Tổng', '${_warrantySummary['totalCount'] ?? 0}'),
                _miniChip('Sắp hết', '${_warrantySummary['expiringSoonCount'] ?? 0}'),
                _miniChip('Đã hết', '${_warrantySummary['expiredCount'] ?? 0}'),
              ],
            ),
          ),
        Expanded(
          child: _dataTable(
            _warrantyItems,
            ['Mã TS', 'Tên', 'Danh mục', 'Hết BH', 'Còn (ngày)', 'Người giữ'],
            (r) {
              final d = r['warrantyExpiry']?.toString() ?? '';
              DateTime? dt;
              try {
                dt = DateTime.parse(d);
              } catch (_) {}
              final days = r['daysRemaining'];
              final daysStr = days is num
                  ? '${days.toInt()}'
                  : (r['isExpired'] == true ? 'Hết' : '-');
              return [
                r['assetCode']?.toString() ?? '',
                r['name']?.toString() ?? '',
                r['categoryName']?.toString() ?? '',
                dt != null ? _fmtDate.format(dt.toLocal()) : d,
                daysStr,
                r['assigneeName']?.toString() ?? '-',
              ];
            },
            rowColor: (r) {
              if (r['isExpired'] == true) {
                return Colors.red.withValues(alpha: 0.06);
              }
              final d = r['daysRemaining'];
              if (d is num && d <= 7) {
                return Colors.orange.withValues(alpha: 0.08);
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _dataTable(
    List<Map<String, dynamic>> rows,
    List<String> headers,
    List<String> Function(Map<String, dynamic>) rowBuilder, {
    Color? Function(Map<String, dynamic>)? rowColor,
  }) {
    if (rows.isEmpty) {
      return const Center(child: Text('Không có dữ liệu trong khoảng lọc'));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
          headingRowHeight: _hdrH,
          dataRowMinHeight: _rowH,
          dataRowMaxHeight: _rowH,
          headingRowColor: WidgetStateProperty.all(_theme.withValues(alpha: 0.08)),
          columns: headers
              .map((h) => DataColumn(
                  label: Text(h,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12))))
              .toList(),
          rows: rows
              .map((r) => DataRow(
                  color: rowColor != null
                      ? WidgetStateProperty.all(rowColor(r))
                      : null,
                  cells: rowBuilder(r)
                      .map((c) => DataCell(Text(c,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis)))
                      .toList()))
              .toList(),
      ),
    );
  }
}
