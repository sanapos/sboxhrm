import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../utils/number_formatter.dart';
import '../widgets/hrm_mini_stat_chip.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
class AllowanceSettingsScreen extends StatefulWidget {
  const AllowanceSettingsScreen({super.key});

  @override
  State<AllowanceSettingsScreen> createState() =>
      _AllowanceSettingsScreenState();
}

class _AllowanceSettingsScreenState extends State<AllowanceSettingsScreen> {
  final ApiService _apiService = ApiService();
  final _currencyFormat = NumberFormat('#,###', 'vi_VN');
  List<Map<String, dynamic>> _allowances = [];
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedType = 'all';
  @override
  void initState() {
    super.initState();
    _loadAllowances();
  }

  Future<void> _loadAllowances() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getAllowanceSettings(),
        _apiService.getEmployees(pageSize: 500),
      ]);
      setState(() {
        _allowances = List<Map<String, dynamic>>.from(results[0]);
        _employees = List<Map<String, dynamic>>.from(results[1]);
      });
    } catch (e) {
      debugPrint('Error loading allowances: $e');
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: 'Không thể tải danh sách phụ cấp. Vui lòng thử lại.',
        );
      }
      setState(() {
        _allowances = [];
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredAllowances {
    return _allowances.where((allowance) {
      final matchesSearch = _searchQuery.isEmpty ||
          (allowance['name']
                  ?.toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ??
              false);

      bool matchesType = true;
      if (_selectedType != 'all') {
        final typeValue = _parseType(allowance['type']);
        if (_selectedType == '0') {
          matchesType = typeValue == 0;
        } else if (_selectedType == '1') {
          matchesType = typeValue == 1;
        } else if (_selectedType == '2') {
          matchesType = typeValue == 2;
        } else if (_selectedType == '3') {
          matchesType = typeValue == 3;
        }
      }

      return matchesSearch && matchesType;
    }).toList();
  }

  int get _totalAllowances => _allowances.length;
  int get _fixedAllowances =>
      _allowances.where((a) => _parseType(a['type']) == 0).length;
  int get _dailyAllowances =>
      _allowances.where((a) => _parseType(a['type']) == 1).length;

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _selectedType = 'all';
    });
  }

  List<String> _parseEmployeeIds(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

  /// API trả về enum `Type` dưới dạng String ("Fixed", "Daily", "Hourly",
  /// "PerEvent") vì server cấu hình `JsonStringEnumConverter`.
  /// Hand lại về int 0..3 để dùng cho dropdown / counters / icons.
  int _parseType(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'fixed':
        case '0':
          return 0;
        case 'daily':
        case '1':
          return 1;
        case 'hourly':
        case '2':
          return 2;
        case 'perevent':
        case 'per_event':
        case '3':
          return 3;
      }
    }
    return 0;
  }

  num _parseAmount(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  List<Widget> _allowanceToolbarActions(BuildContext context) {
    return Responsive.isMobile(context)
            ? [
                IconButton(
                  tooltip: 'Thêm phụ cấp',
                  icon: const Icon(Icons.add_circle_outline,
                      color: HrmPageChrome.primaryNavy),
                  onPressed: () => _showAllowanceDialog(),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Thêm thao tác',
                  icon: const Icon(Icons.more_vert, color: Color(0xFF71717A)),
                  onSelected: (value) {
                    if (value == 'export') {
                      appNotification.showInfo(
                          title: 'Xuất dữ liệu',
                          message: 'Tính năng đang phát triển');
                    } else if (value == 'refresh') {
                      _loadAllowances();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.refresh, size: 20),
                        title: Text('Làm mới'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.download,
                            size: 20, color: Color(0xFFEF4444)),
                        title: Text('Xuất dữ liệu'),
                      ),
                    ),
                  ],
                ),
              ]
            : [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _showAllowanceDialog(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Thêm PC'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HrmPageChrome.primaryNavy,
                      side: const BorderSide(color: HrmPageChrome.primaryNavy),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      appNotification.showInfo(
                          title: 'Xuất dữ liệu',
                          message: 'Tính năng đang phát triển');
                    },
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Xuất'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              ];
  }

  @override
  Widget build(BuildContext context) {
    final toolbarActions = _allowanceToolbarActions(context);

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: HrmPageChrome.appBar(
        title: 'Thiết lập Phụ cấp',
        actions: toolbarActions,
      ),
      body: _isLoading
          ? const LoadingWidget()
          : SingleChildScrollView(
              padding: EdgeInsets.all(Responsive.isMobile(context) ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (HrmPageChrome.isEmbedded) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: toolbarActions,
                    ),
                    const SizedBox(height: 12),
                  ],
                  HrmPageChrome.horizontalStatCards(
                    cards: [
                      _buildStatCard(Icons.receipt_long, '$_totalAllowances',
                          'Tổng phụ cấp', HrmPageChrome.primaryNavy),
                      _buildStatCard(Icons.lock, '$_fixedAllowances', 'Cố định',
                          HrmPageChrome.primaryNavy),
                      _buildStatCard(Icons.calendar_today, '$_dailyAllowances',
                          'Theo ngày', const Color(0xFFF59E0B)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Filter bar
                  
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth >= 600) {
                            return Row(
                              children: [
                                // Search input
                                Expanded(
                                  flex: 3,
                                  child: SizedBox(
                                    height: 44,
                                    child: TextField(
                                      style: const TextStyle(
                                          color: Color(0xFF18181B),
                                          fontSize: 14),
                                      decoration: InputDecoration(
                                        hintText: 'Tìm theo tên phụ cấp...',
                                        hintStyle: const TextStyle(
                                            color: Color(0xFFA1A1AA),
                                            fontSize: 14),
                                        prefixIcon: const Icon(Icons.search,
                                            color: Color(0xFFA1A1AA), size: 20),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 10),
                                        filled: true,
                                        fillColor: const Color(0xFFFAFAFA),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFE4E4E7)),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFE4E4E7)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                              color: HrmPageChrome.primaryNavy),
                                        ),
                                      ),
                                      onChanged: (value) =>
                                          setState(() => _searchQuery = value),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Type dropdown
                                Expanded(
                                  flex: 2,
                                  child: SizedBox(
                                    height: 44,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _selectedType,
                                      dropdownColor: Colors.white,
                                      icon:
                                          const Icon(Icons.keyboard_arrow_down),
                                      style: const TextStyle(
                                          color: Color(0xFF18181B),
                                          fontSize: 14),
                                      decoration: InputDecoration(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFE4E4E7)),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFE4E4E7)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                              color: HrmPageChrome.primaryNavy),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                        prefixIcon: Container(
                                          padding: const EdgeInsets.all(8),
                                          child: const Icon(Icons.circle,
                                              size: 10,
                                              color: Color(0xFFFBBF24)),
                                        ),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'all',
                                            child: Text('Tất cả loại')),
                                        DropdownMenuItem(
                                            value: '0',
                                            child:
                                                Text('Cố định (theo tháng)')),
                                        DropdownMenuItem(
                                            value: '1',
                                            child: Text('Theo ngày')),
                                      ],
                                      onChanged: (value) => setState(
                                          () => _selectedType = value ?? 'all'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Clear filter button
                                OutlinedButton.icon(
                                  onPressed: _clearFilters,
                                  icon: const Icon(Icons.filter_alt_off,
                                      size: 18),
                                  label: const Text('Xóa lọc'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF71717A),
                                    side: const BorderSide(
                                        color: Color(0xFFE4E4E7)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                SizedBox(
                                  height: 44,
                                  child: TextField(
                                    style: const TextStyle(
                                        color: Color(0xFF18181B), fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: 'Tìm theo tên phụ cấp...',
                                      hintStyle: const TextStyle(
                                          color: Color(0xFFA1A1AA),
                                          fontSize: 14),
                                      prefixIcon: const Icon(Icons.search,
                                          color: Color(0xFFA1A1AA), size: 20),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 10),
                                      filled: true,
                                      fillColor: const Color(0xFFFAFAFA),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE4E4E7)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE4E4E7)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: HrmPageChrome.primaryNavy),
                                      ),
                                    ),
                                    onChanged: (value) =>
                                        setState(() => _searchQuery = value),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 44,
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _selectedType,
                                          dropdownColor: Colors.white,
                                          icon: const Icon(
                                              Icons.keyboard_arrow_down),
                                          style: const TextStyle(
                                              color: Color(0xFF18181B),
                                              fontSize: 14),
                                          decoration: InputDecoration(
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                  color: Color(0xFFE4E4E7)),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                  color: Color(0xFFE4E4E7)),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                  color: HrmPageChrome.primaryNavy),
                                            ),
                                            filled: true,
                                            fillColor: Colors.white,
                                            prefixIcon: Container(
                                              padding: const EdgeInsets.all(8),
                                              child: const Icon(Icons.circle,
                                                  size: 10,
                                                  color: Color(0xFFFBBF24)),
                                            ),
                                          ),
                                          items: const [
                                            DropdownMenuItem(
                                                value: 'all',
                                                child: Text('Tất cả loại')),
                                            DropdownMenuItem(
                                                value: '0',
                                                child: Text(
                                                    'Cố định (theo tháng)')),
                                            DropdownMenuItem(
                                                value: '1',
                                                child: Text('Theo ngày')),
                                          ],
                                          onChanged: (value) => setState(() =>
                                              _selectedType = value ?? 'all'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    OutlinedButton.icon(
                                      onPressed: _clearFilters,
                                      icon: const Icon(Icons.filter_alt_off,
                                          size: 18),
                                      label: const Text('Xóa lọc'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF71717A),
                                        side: const BorderSide(
                                            color: Color(0xFFE4E4E7)),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Allowance cards grid
                  _filteredAllowances.isEmpty
                      ? const Center(
                          child: EmptyState(
                            icon: Icons.card_giftcard,
                            title: 'Không tìm thấy phụ cấp',
                            description:
                                'Thử thay đổi bộ lọc hoặc thêm phụ cấp mới',
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            // Web: một phụ cấp một dòng (bảng gọn).
                            if (kIsWeb) {
                              return _buildAllowanceWebList();
                            }

                            int crossAxisCount = 4;
                            if (constraints.maxWidth < 600) {
                              crossAxisCount = 1;
                            } else if (constraints.maxWidth < 900) {
                              crossAxisCount = 2;
                            } else if (constraints.maxWidth < 1200) {
                              crossAxisCount = 3;
                            }

                            if (crossAxisCount == 1) {
                              return Column(
                                children: List.generate(
                                  _filteredAllowances.length,
                                  (index) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _buildAllowanceDeckItem(
                                        _filteredAllowances[index]),
                                  ),
                                ),
                              );
                            }

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: 1.1,
                              ),
                              itemCount: _filteredAllowances.length,
                              itemBuilder: (context, index) {
                                return _buildAllowanceCard(
                                    _filteredAllowances[index]);
                              },
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard(
      IconData icon, String value, String label, Color color) {
    return HrmStatSummaryCard(
      icon: icon,
      value: value,
      label: label,
      color: color,
    );
  }

  ({String label, IconData icon, Color color}) _allowanceTypeMeta(
      Map<String, dynamic> allowance) {
    final typeValue = _parseType(allowance['type']);
    if (typeValue == 1) {
      return (
        label: 'Theo ngày',
        icon: Icons.calendar_today_outlined,
        color: const Color(0xFFF59E0B)
      );
    }
    if (typeValue == 2) {
      return (
        label: 'Theo giờ',
        icon: Icons.access_time,
        color: HrmPageChrome.primaryNavy
      );
    }
    if (typeValue == 3) {
      return (
        label: 'Theo sự kiện',
        icon: Icons.event,
        color: const Color(0xFF7C3AED)
      );
    }
    return (
      label: 'Cố định',
      icon: Icons.lock_outline,
      color: HrmPageChrome.primaryNavy
    );
  }

  Widget _buildAllowanceWebList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildAllowanceWebListHeader(),
          for (var i = 0; i < _filteredAllowances.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: Color(0xFFE4E4E7)),
            _buildAllowanceWebRow(_filteredAllowances[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildAllowanceWebListHeader() {
    TextStyle style = const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Color(0xFF71717A),
      letterSpacing: 0.2,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          const SizedBox(width: 48),
          Expanded(flex: 4, child: Text('Phụ cấp', style: style)),
          Expanded(flex: 2, child: Text('Loại', style: style)),
          Expanded(flex: 2, child: Text('Giá trị', style: style)),
          SizedBox(width: 88, child: Text('Trạng thái', style: style)),
          SizedBox(width: 88, child: Text('Thao tác', style: style)),
        ],
      ),
    );
  }

  Widget _buildAllowanceWebRow(Map<String, dynamic> allowance) {
    final meta = _allowanceTypeMeta(allowance);
    final isActive = allowance['isActive'] ?? true;
    final amount = _parseAmount(allowance['amount']);
    final empIds = _parseEmployeeIds(allowance['employeeIds']);
    final code = allowance['code']?.toString() ?? '';
    final empLabel = empIds.isEmpty
        ? 'Tất cả NV'
        : '${empIds.length} nhân viên';

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _showAllowanceDialog(allowance: allowance),
        hoverColor: const Color(0xFFF1F5F9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isActive
                      ? meta.color.withValues(alpha: 0.12)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  meta.icon,
                  size: 20,
                  color: isActive ? meta.color : const Color(0xFFA1A1AA),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allowance['name']?.toString() ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? const Color(0xFF18181B)
                            : const Color(0xFF71717A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      code.isNotEmpty ? '$code · $empLabel' : empLabel,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF71717A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(meta.icon, size: 14, color: meta.color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        meta.label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: meta.color),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${_currencyFormat.format(amount)}đ',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF18181B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 88,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isActive ? 'Bật' : 'Tắt',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF71717A),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 88,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Sửa',
                      onPressed: () =>
                          _showAllowanceDialog(allowance: allowance),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      color: HrmPageChrome.primaryNavy,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    IconButton(
                      tooltip: 'Xóa',
                      onPressed: () => _deleteAllowance(allowance),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: const Color(0xFFEF4444),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllowanceDeckItem(Map<String, dynamic> allowance) {
    final meta = _allowanceTypeMeta(allowance);
    final typeLabel = meta.label;
    final typeIcon = meta.icon;
    final typeColor = meta.color;
    final isActive = allowance['isActive'] ?? true;
    final amount = _parseAmount(allowance['amount']);
    final empIds = _parseEmployeeIds(allowance['employeeIds']);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          debugPrint('[Allowance] tap card id=${allowance['id']}');
          _showAllowanceDialog(allowance: allowance);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isActive
                      ? typeColor.withValues(alpha: 0.12)
                      : const Color(0xFFA1A1AA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  typeIcon,
                  color: isActive ? typeColor : const Color(0xFFA1A1AA),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            allowance['name'] ?? '',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF18181B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isActive ? 'Bật' : 'Tắt',
                            style: TextStyle(
                                color: isActive
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF71717A),
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(typeIcon, size: 12, color: typeColor),
                        const SizedBox(width: 4),
                        Text(
                          typeLabel,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: typeColor),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.payments_outlined,
                            size: 12, color: Color(0xFF71717A)),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            '${_currencyFormat.format(amount)}đ',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF18181B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.people_outline,
                            size: 11, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text(
                          empIds.isEmpty
                              ? 'Tất cả nhân viên'
                              : '${empIds.length} nhân viên',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                        if (allowance['code'] != null &&
                            allowance['code'].toString().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text('·', style: TextStyle(color: Colors.grey[400])),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              allowance['code'].toString(),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                  fontFamily: 'monospace'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Action buttons hiển thị rõ ràng — bảo đảm tap luôn có
                    // tác dụng dù sự kiện InkWell ngoài có chặn hay không.
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _showAllowanceDialog(allowance: allowance),
                            icon: const Icon(Icons.edit_outlined, size: 14),
                            label: const Text('Xem / Sửa',
                                style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: HrmPageChrome.primaryNavy,
                              side: const BorderSide(color: HrmPageChrome.primaryNavy),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 8),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _deleteAllowance(allowance),
                          icon: const Icon(Icons.delete_outline, size: 14),
                          label:
                              const Text('Xoá', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: const BorderSide(color: Color(0xFFEF4444)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 6, horizontal: 12),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
      ),
    );
  }

  Widget _buildAllowanceCard(Map<String, dynamic> allowance) {
    final typeValue = _parseType(allowance['type']);
    final isDaily = typeValue == 1;
    final isHourly = typeValue == 2;
    final isPerEvent = typeValue == 3;
    final amount = _parseAmount(allowance['amount']);
    final isActive = allowance['isActive'] ?? true;
    final empIds = _parseEmployeeIds(allowance['employeeIds']);

    String typeLabel = 'Cố định';
    IconData typeIcon = Icons.lock_outline;
    if (isDaily) {
      typeLabel = 'Theo ngày';
      typeIcon = Icons.calendar_today_outlined;
    } else if (isHourly) {
      typeLabel = 'Theo giờ';
      typeIcon = Icons.access_time;
    } else if (isPerEvent) {
      typeLabel = 'Theo sự kiện';
      typeIcon = Icons.event;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: !isActive
            ? Border.all(color: const Color(0xFFE4E4E7), width: 1)
            : null,
      ),
      child: Opacity(
        opacity: isActive ? 1.0 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with icon, name and status
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isActive
                          ? HrmPageChrome.primaryNavy.withValues(alpha: 0.1)
                          : const Color(0xFFA1A1AA).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.receipt_long,
                      color: isActive
                          ? HrmPageChrome.primaryNavy
                          : const Color(0xFFA1A1AA),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                allowance['name'] ?? '',
                                style: const TextStyle(
                                  color: Color(0xFF18181B),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isActive ? 'Đang bật' : 'Đã tắt',
                                style: TextStyle(
                                  color: isActive
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFF71717A),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (allowance['code'] != null &&
                            allowance['code'].toString().isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: HrmPageChrome.primaryNavy
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Mã: ${allowance['code']}',
                              style: const TextStyle(
                                color: HrmPageChrome.primaryNavy,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Type badge + Employee count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    typeIcon,
                    size: 14,
                    color: const Color(0xFF71717A),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    typeLabel,
                    style: const TextStyle(
                      color: Color(0xFF71717A),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.people, size: 13, color: Colors.grey[400]),
                  const SizedBox(width: 3),
                  Text(
                    empIds.isEmpty ? 'Tất cả' : '${empIds.length} NV',
                    style:
                        const TextStyle(color: Color(0xFF71717A), fontSize: 11),
                  ),
                ],
              ),
            ),

            // Amount
            Expanded(
              child: Center(
                child: Text(
                  '${_currencyFormat.format(amount)} đ',
                  style: TextStyle(
                    color: isActive
                        ? HrmPageChrome.primaryNavy
                        : const Color(0xFFA1A1AA),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Action buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFE4E4E7)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => _showAllowanceDialog(allowance: allowance),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    color: const Color(0xFF71717A),
                    tooltip: 'Sửa',
                  ),
                  IconButton(
                    onPressed: () => _deleteAllowance(allowance),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: const Color(0xFF71717A),
                    tooltip: 'Xóa',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAllowanceDialog({Map<String, dynamic>? allowance}) {
    final isEditing = allowance != null;
    final nameController =
        TextEditingController(text: allowance?['name'] ?? '');
    final codeController =
        TextEditingController(text: allowance?['code'] ?? '');
    final descriptionController =
        TextEditingController(text: allowance?['description'] ?? '');
    // Khởi tạo bằng chuỗi đã format hàng nghìn để khớp với
    // ThousandSeparatorFormatter; tránh double "50000.0" bị strip dấu chấm
    // thành "500000" khi user gõ phím đầu tiên.
    final amountController = TextEditingController(
      text: formatNumber(_parseAmount(allowance?['amount'])),
    );
    int type = _parseType(allowance?['type']);
    bool isActive = allowance?['isActive'] ?? true;
    bool isTaxable = allowance?['isTaxable'] ?? true;
    bool isInsuranceApplicable = allowance?['isInsuranceApplicable'] ?? false;
    DateTime? startDate = allowance?['startDate'] != null
        ? DateTime.tryParse(allowance!['startDate'])
        : null;
    DateTime? endDate = allowance?['endDate'] != null
        ? DateTime.tryParse(allowance!['endDate'])
        : null;
    List<String> selectedEmployeeIds =
        _parseEmployeeIds(allowance?['employeeIds']);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isMobile = Responsive.isMobile(context);

          Future<void> onSave() async {
            if (nameController.text.isEmpty || amountController.text.isEmpty) {
              appNotification.showWarning(
                  title: 'Thiếu thông tin',
                  message: 'Vui lòng điền tên và giá trị phụ cấp');
              return;
            }

            final data = {
              'name': nameController.text,
              'code':
                  codeController.text.isNotEmpty ? codeController.text : null,
              'description': descriptionController.text.isNotEmpty
                  ? descriptionController.text
                  : null,
              // Gửi tên enum (string) để chắc chắn server parse đúng.
              'type': const ['Fixed', 'Daily', 'Hourly', 'PerEvent'][type],
              'amount':
                  parseFormattedNumber(amountController.text)?.toDouble() ?? 0,
              'currency': 'VND',
              'isTaxable': isTaxable,
              'isInsuranceApplicable': isInsuranceApplicable,
              'isActive': isActive,
              if (startDate != null) 'startDate': startDate!.toIso8601String(),
              if (endDate != null) 'endDate': endDate!.toIso8601String(),
              if (selectedEmployeeIds.isNotEmpty)
                'employeeIds': selectedEmployeeIds,
            };

            Navigator.pop(context);

            try {
              dynamic response;
              if (isEditing) {
                response = await _apiService.updateAllowanceSetting(
                    allowance['id'].toString(), data);
              } else {
                response = await _apiService.createAllowanceSetting(data);
              }
              _loadAllowances();
              if (mounted) {
                if (response is Map && response['isSuccess'] == true) {
                  appNotification.showSuccess(
                    title: 'Thành công',
                    message:
                        isEditing ? 'Đã cập nhật phụ cấp' : 'Đã thêm phụ cấp',
                  );
                } else if (response is Map && response['isSuccess'] == false) {
                  appNotification.showError(
                    title: 'Lỗi',
                    message: response['message'] ?? 'Lỗi khi lưu phụ cấp',
                  );
                } else {
                  appNotification.showSuccess(
                    title: 'Thành công',
                    message:
                        isEditing ? 'Đã cập nhật phụ cấp' : 'Đã thêm phụ cấp',
                  );
                }
              }
            } catch (e) {
              if (mounted) {
                appNotification.showError(title: 'Lỗi', message: 'Lỗi: $e');
              }
            }
          }

          final activeSwitch = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isActive ? 'Đang bật' : 'Đã tắt',
                style: TextStyle(
                  color: isActive
                      ? HrmPageChrome.primaryNavy
                      : const Color(0xFFA1A1AA),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: isActive,
                onChanged: (value) => setDialogState(() => isActive = value),
                activeTrackColor: HrmPageChrome.primaryNavy,
              ),
            ],
          );

          final formContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Tên phụ cấp + Mã phụ cấp
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Text('Tên phụ cấp',
                                style: TextStyle(
                                    color: Color(0xFF71717A), fontSize: 13)),
                            Text(' *',
                                style: TextStyle(color: Color(0xFFEF4444))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: nameController,
                          style: const TextStyle(
                              color: Color(0xFF18181B), fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Vd: Phụ cấp ăn trưa',
                            hintStyle: const TextStyle(
                                color: Color(0xFFA1A1AA), fontSize: 13),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE4E4E7)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE4E4E7)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: HrmPageChrome.primaryNavy),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Mã phụ cấp',
                            style: TextStyle(
                                color: Color(0xFF71717A), fontSize: 13)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: codeController,
                          style: const TextStyle(
                              color: Color(0xFF18181B), fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Vd: PC_AT',
                            hintStyle: const TextStyle(
                                color: Color(0xFFA1A1AA), fontSize: 13),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE4E4E7)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE4E4E7)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: HrmPageChrome.primaryNavy),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Row 2: Loại phụ cấp + Giá trị
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Text('Loại phụ cấp',
                                style: TextStyle(
                                    color: Color(0xFF71717A), fontSize: 13)),
                            Text(' *',
                                style: TextStyle(color: Color(0xFFEF4444))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        InputDecorator(
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE4E4E7)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE4E4E7)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: HrmPageChrome.primaryNavy),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              isExpanded: true,
                              value: type,
                              dropdownColor: Colors.white,
                              style: const TextStyle(
                                  color: Color(0xFF18181B), fontSize: 14),
                              items: const [
                                DropdownMenuItem(
                                    value: 0,
                                    child: Text('Cố định (theo tháng)')),
                                DropdownMenuItem(
                                    value: 1, child: Text('Theo ngày công')),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(() => type = value);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Text('Giá trị (VNĐ)',
                                style: TextStyle(
                                    color: Color(0xFF71717A), fontSize: 13)),
                            Text(' *',
                                style: TextStyle(color: Color(0xFFEF4444))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [ThousandSeparatorFormatter()],
                          style: const TextStyle(
                              color: Color(0xFF18181B), fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Vd: 500000',
                            hintStyle: const TextStyle(
                                color: Color(0xFFA1A1AA), fontSize: 13),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE4E4E7)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE4E4E7)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: HrmPageChrome.primaryNavy),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Row 3: Thời gian áp dụng
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ngày bắt đầu',
                            style: TextStyle(
                                color: Color(0xFF71717A), fontSize: 13)),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: startDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              setDialogState(() => startDate = date);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: const Color(0xFFE4E4E7)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today,
                                    size: 16, color: Color(0xFF71717A)),
                                const SizedBox(width: 8),
                                Text(
                                  startDate != null
                                      ? DateFormat('dd/MM/yyyy')
                                          .format(startDate!)
                                      : 'Không giới hạn',
                                  style: TextStyle(
                                    color: startDate != null
                                        ? const Color(0xFF18181B)
                                        : const Color(0xFFA1A1AA),
                                    fontSize: 14,
                                  ),
                                ),
                                const Spacer(),
                                if (startDate != null)
                                  GestureDetector(
                                    onTap: () =>
                                        setDialogState(() => startDate = null),
                                    child: const Icon(Icons.close,
                                        size: 16, color: Color(0xFFA1A1AA)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ngày kết thúc',
                            style: TextStyle(
                                color: Color(0xFF71717A), fontSize: 13)),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: endDate ??
                                  DateTime.now().add(const Duration(days: 365)),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              setDialogState(() => endDate = date);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: const Color(0xFFE4E4E7)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today,
                                    size: 16, color: Color(0xFF71717A)),
                                const SizedBox(width: 8),
                                Text(
                                  endDate != null
                                      ? DateFormat('dd/MM/yyyy')
                                          .format(endDate!)
                                      : 'Không giới hạn',
                                  style: TextStyle(
                                    color: endDate != null
                                        ? const Color(0xFF18181B)
                                        : const Color(0xFFA1A1AA),
                                    fontSize: 14,
                                  ),
                                ),
                                const Spacer(),
                                if (endDate != null)
                                  GestureDetector(
                                    onTap: () =>
                                        setDialogState(() => endDate = null),
                                    child: const Icon(Icons.close,
                                        size: 16, color: Color(0xFFA1A1AA)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Mô tả
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Mô tả',
                      style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    style:
                        const TextStyle(color: Color(0xFF18181B), fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Ghi chú về phụ cấp này...',
                      hintStyle: const TextStyle(
                          color: Color(0xFFA1A1AA), fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
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
                        borderSide: const BorderSide(color: HrmPageChrome.primaryNavy),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Checkbox tính thuế
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: isTaxable,
                      onChanged: (value) =>
                          setDialogState(() => isTaxable = value ?? true),
                      activeColor: HrmPageChrome.primaryNavy,
                    ),
                    const Text('Tính thuế TNCN',
                        style:
                            TextStyle(color: Color(0xFF18181B), fontSize: 14)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isTaxable
                            ? const Color(0xFFFEF3C7)
                            : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isTaxable ? 'Có thuế' : 'Miễn thuế',
                        style: TextStyle(
                          color: isTaxable
                              ? const Color(0xFFD97706)
                              : const Color(0xFF16A34A),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Checkbox tính bảo hiểm
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: isInsuranceApplicable,
                      onChanged: (value) => setDialogState(
                          () => isInsuranceApplicable = value ?? false),
                      activeColor: HrmPageChrome.primaryNavy,
                    ),
                    const Text('Tính bảo hiểm',
                        style:
                            TextStyle(color: Color(0xFF18181B), fontSize: 14)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isInsuranceApplicable
                            ? const Color(0xFFFEF3C7)
                            : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isInsuranceApplicable ? 'Có BH' : 'Miễn BH',
                        style: TextStyle(
                          color: isInsuranceApplicable
                              ? const Color(0xFFD97706)
                              : const Color(0xFF16A34A),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Danh sách nhân viên áp dụng
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people,
                            size: 18, color: Color(0xFF71717A)),
                        const SizedBox(width: 8),
                        const Text('Áp dụng cho',
                            style: TextStyle(
                                color: Color(0xFF18181B),
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: selectedEmployeeIds.isEmpty
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFE0E7FF),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            selectedEmployeeIds.isEmpty
                                ? 'Tất cả nhân viên'
                                : '${selectedEmployeeIds.length} nhân viên',
                            style: TextStyle(
                              color: selectedEmployeeIds.isEmpty
                                  ? const Color(0xFF16A34A)
                                  : HrmPageChrome.primaryNavy,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedEmployeeIds.isEmpty
                          ? 'Phụ cấp này sẽ áp dụng cho tất cả nhân viên trong công ty'
                          : 'Đã chọn ${selectedEmployeeIds.length} nhân viên cụ thể',
                      style: const TextStyle(
                          color: Color(0xFF71717A), fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        _showEmployeeSelector(
                          selectedIds: selectedEmployeeIds,
                          onChanged: (ids) {
                            setDialogState(() {
                              selectedEmployeeIds = ids;
                            });
                          },
                        );
                      },
                      icon: const Icon(Icons.person_add, size: 16),
                      label: const Text('Chọn nhân viên'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HrmPageChrome.primaryNavy,
                        side: const BorderSide(color: HrmPageChrome.primaryNavy),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(isEditing ? 'Sửa phụ cấp' : 'Thêm phụ cấp'),
                  leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                  actions: [
                    activeSwitch,
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: onSave,
                      icon: const Icon(Icons.save, size: 18),
                      label: Text(isEditing ? 'Cập nhật' : 'Lưu'),
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

          return Dialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Container(
              width: 650,
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                    decoration: const BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
                    ),
                    child: Row(
                      children: [
                        Icon(isEditing ? Icons.edit : Icons.add_circle,
                            color: HrmPageChrome.primaryNavy, size: 22),
                        const SizedBox(width: 10),
                        Text(isEditing ? 'Sửa phụ cấp' : 'Thêm phụ cấp',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF18181B))),
                        const Spacer(),
                        activeSwitch,
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon:
                              const Icon(Icons.close, color: Color(0xFF71717A)),
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: formContent,
                    ),
                  ),
                  // Footer
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF71717A),
                            side: const BorderSide(color: Color(0xFFE4E4E7)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Hủy'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: onSave,
                          icon: const Icon(Icons.save, size: 18),
                          label: Text(isEditing ? 'Cập nhật' : 'Thêm phụ cấp'),
                          style: FilledButton.styleFrom(
                            backgroundColor: HrmPageChrome.primaryNavy,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEmployeeSelector({
    required List<String> selectedIds,
    required Function(List<String>) onChanged,
  }) {
    final tempIds = List<String>.from(selectedIds);
    String searchText = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = searchText.isEmpty
              ? _employees
              : _employees.where((e) {
                  final name = (e['fullName'] ?? e['name'] ?? '')
                      .toString()
                      .toLowerCase();
                  final code =
                      (e['employeeCode'] ?? '').toString().toLowerCase();
                  return name.contains(searchText.toLowerCase()) ||
                      code.contains(searchText.toLowerCase());
                }).toList();

          final isMobile = Responsive.isMobile(ctx);

          void onConfirm() {
            onChanged(tempIds);
            Navigator.pop(ctx);
          }

          final searchField = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              style: const TextStyle(fontSize: 13, color: Color(0xFF18181B)),
              decoration: InputDecoration(
                hintText: 'Tìm nhân viên...',
                hintStyle:
                    const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: Color(0xFFA1A1AA)),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: HrmPageChrome.primaryNavy)),
              ),
              onChanged: (v) => setDialogState(() => searchText = v),
            ),
          );

          final selectAll = InkWell(
            onTap: () {
              setDialogState(() {
                if (tempIds.length == _employees.length) {
                  tempIds.clear();
                } else {
                  tempIds.clear();
                  tempIds.addAll(_employees.map((e) => e['id'].toString()));
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFFAFAFA),
              child: Row(
                children: [
                  Icon(
                      tempIds.length == _employees.length
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                      color: HrmPageChrome.primaryNavy),
                  const SizedBox(width: 10),
                  Text('Chọn tất cả (${tempIds.length}/${_employees.length})',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          );

          final list = Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 24, color: Color(0xFFE4E4E7)),
              itemBuilder: (_, i) {
                final emp = filtered[i];
                final id = emp['id'].toString();
                final checked = tempIds.contains(id);
                final colors = [
                  HrmPageChrome.primaryNavy,
                  HrmPageChrome.primaryNavy,
                  const Color(0xFFF59E0B),
                  HrmPageChrome.primaryNavy,
                  const Color(0xFFEF4444)
                ];
                final color = colors[i % colors.length];
                return InkWell(
                  onTap: () {
                    setDialogState(() {
                      if (checked) {
                        tempIds.remove(id);
                      } else {
                        tempIds.add(id);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                            checked
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 20,
                            color: checked
                                ? HrmPageChrome.primaryNavy
                                : Colors.grey[400]),
                        const SizedBox(width: 10),
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: color.withValues(alpha: 0.15),
                          child: Text(
                              (emp['fullName'] ?? emp['name'] ?? '?')[0],
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: color)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(emp['fullName'] ?? emp['name'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF18181B))),
                              Text(emp['employeeCode'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF71717A))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );

          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Chọn nhân viên'),
                  leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                  actions: [
                    TextButton(
                      onPressed: onConfirm,
                      child: Text('Xác nhận (${tempIds.length})'),
                    ),
                  ],
                ),
                body: Column(
                  children: [
                    searchField,
                    selectAll,
                    const Divider(height: 24),
                    list
                  ],
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.white,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: math.min(450, MediaQuery.of(ctx).size.width - 32),
              height: 550,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                    decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                    child: Row(
                      children: [
                        const Icon(Icons.people,
                            color: HrmPageChrome.primaryNavy, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                            child: Text('Chọn nhân viên',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF18181B)))),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close,
                                color: Color(0xFF71717A), size: 20)),
                      ],
                    ),
                  ),
                  searchField,
                  selectAll,
                  const Divider(height: 24),
                  list,
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                        border:
                            Border(top: BorderSide(color: Color(0xFFE4E4E7)))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            onChanged([]);
                            Navigator.pop(ctx);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF71717A),
                            side: const BorderSide(color: Color(0xFFE4E4E7)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Tất cả NV'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF71717A),
                            side: const BorderSide(color: Color(0xFFE4E4E7)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Hủy'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: onConfirm,
                          style: FilledButton.styleFrom(
                            backgroundColor: HrmPageChrome.primaryNavy,
                          ),
                          child: Text('Xác nhận (${tempIds.length})'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _deleteAllowance(Map<String, dynamic> allowance) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận xóa',
            style: TextStyle(
                color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
        content: Text(
          'Bạn có chắc muốn xóa phụ cấp "${allowance['name']}"?',
          style: const TextStyle(color: Color(0xFF71717A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final response = await _apiService
                    .deleteAllowanceSetting(allowance['id'].toString());
                _loadAllowances();
                if (mounted) {
                  if (response['isSuccess'] == true) {
                    appNotification.showSuccess(
                        title: 'Thành công', message: 'Đã xóa phụ cấp');
                  } else if (response['isSuccess'] == false) {
                    appNotification.showError(
                        title: 'Lỗi',
                        message: response['message'] ?? 'Lỗi khi xóa phụ cấp');
                  } else {
                    appNotification.showSuccess(
                        title: 'Thành công', message: 'Đã xóa phụ cấp');
                  }
                }
              } catch (e) {
                if (mounted) {
                  appNotification.showError(title: 'Lỗi', message: 'Lỗi: $e');
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }
}
