import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../utils/number_formatter.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import 'settings_hub_screen.dart';

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
  bool _showMobileFilters = false;

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
        final typeValue = allowance['type'] is int ? allowance['type'] : 0;
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
      _allowances.where((a) => (a['type'] is int ? a['type'] : 0) == 0).length;
  int get _dailyAllowances =>
      _allowances.where((a) => (a['type'] is int ? a['type'] : 0) == 1).length;
  int get _hourlyAllowances =>
      _allowances.where((a) => (a['type'] is int ? a['type'] : 0) == 2).length;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Thiết lập Phụ cấp',
            style: TextStyle(
                color: Color(0xFF18181B),
                fontWeight: FontWeight.bold,
                fontSize: 18),
            overflow: TextOverflow.ellipsis,
            maxLines: 1),
        leading: Responsive.isMobile(context) ? null : IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
          onPressed: () => SettingsHubScreen.goBack(context),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: () => _showAllowanceDialog(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Thêm PC'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1E3A5F),
                side: const BorderSide(color: Color(0xFF1E3A5F)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
          if (Responsive.isMobile(context))
            IconButton(
              icon: Stack(
                children: [
                  Icon(
                    _showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                    color: _showMobileFilters ? Colors.orange : const Color(0xFF71717A),
                  ),
                  if (_searchQuery.isNotEmpty || _selectedType != 'all')
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
              onPressed: () => setState(() => _showMobileFilters = !_showMobileFilters),
            ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : SingleChildScrollView(
              padding: EdgeInsets.all(Responsive.isMobile(context) ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Statistics cards row
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 900) {
                        return Row(
                          children: [
                            Expanded(
                                child: _buildStatCard(
                                    Icons.receipt_long,
                                    '$_totalAllowances',
                                    'Tổng phụ cấp',
                                    const Color(0xFF1E3A5F))),
                            const SizedBox(width: 16),
                            Expanded(
                                child: _buildStatCard(
                                    Icons.lock,
                                    '$_fixedAllowances',
                                    'Cố định',
                                    const Color(0xFF1E3A5F))),
                            const SizedBox(width: 16),
                            Expanded(
                                child: _buildStatCard(
                                    Icons.calendar_today,
                                    '$_dailyAllowances',
                                    'Theo ngày',
                                    const Color(0xFFF59E0B))),
                            const SizedBox(width: 16),
                            Expanded(
                                child: _buildStatCard(
                                    Icons.access_time,
                                    '$_hourlyAllowances',
                                    'Theo giờ',
                                    const Color(0xFF0F2340))),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                    child: _buildStatCard(
                                        Icons.receipt_long,
                                        '$_totalAllowances',
                                        'Tổng phụ cấp',
                                        const Color(0xFF1E3A5F))),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: _buildStatCard(
                                        Icons.lock,
                                        '$_fixedAllowances',
                                        'Cố định',
                                        const Color(0xFF1E3A5F))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                    child: _buildStatCard(
                                        Icons.calendar_today,
                                        '$_dailyAllowances',
                                        'Theo ngày',
                                        const Color(0xFFF59E0B))),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: _buildStatCard(
                                        Icons.access_time,
                                        '$_hourlyAllowances',
                                        'Theo giờ',
                                        const Color(0xFF0F2340))),
                              ],
                            ),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 24),

                  // Filter bar
                  if (!Responsive.isMobile(context) || _showMobileFilters)
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
                                        color: Color(0xFF18181B), fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: 'Tìm theo tên phụ cấp...',
                                      hintStyle: const TextStyle(
                                          color: Color(0xFFA1A1AA), fontSize: 14),
                                      prefixIcon: const Icon(Icons.search,
                                          color: Color(0xFFA1A1AA), size: 20),
                                      contentPadding: const EdgeInsets.symmetric(
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
                                            color: Color(0xFF1E3A5F)),
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
                                    icon: const Icon(Icons.keyboard_arrow_down),
                                    style: const TextStyle(
                                        color: Color(0xFF18181B), fontSize: 14),
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
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
                                            color: Color(0xFF1E3A5F)),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      prefixIcon: Container(
                                        padding: const EdgeInsets.all(8),
                                        child: const Icon(Icons.circle,
                                            size: 10, color: Color(0xFFFBBF24)),
                                      ),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'all', child: Text('Tất cả loại')),
                                      DropdownMenuItem(
                                          value: '0',
                                          child: Text('Cố định (theo tháng)')),
                                      DropdownMenuItem(
                                          value: '1', child: Text('Theo ngày')),
                                      DropdownMenuItem(
                                          value: '2', child: Text('Theo giờ')),
                                      DropdownMenuItem(
                                          value: '3', child: Text('Theo sự kiện')),
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
                                icon: const Icon(Icons.filter_alt_off, size: 18),
                                label: const Text('Xóa lọc'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF71717A),
                                  side: const BorderSide(color: Color(0xFFE4E4E7)),
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
                                        color: Color(0xFFA1A1AA), fontSize: 14),
                                    prefixIcon: const Icon(Icons.search,
                                        color: Color(0xFFA1A1AA), size: 20),
                                    contentPadding: const EdgeInsets.symmetric(
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
                                          color: Color(0xFF1E3A5F)),
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
                                        icon: const Icon(Icons.keyboard_arrow_down),
                                        style: const TextStyle(
                                            color: Color(0xFF18181B), fontSize: 14),
                                        decoration: InputDecoration(
                                          contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
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
                                                color: Color(0xFF1E3A5F)),
                                          ),
                                          filled: true,
                                          fillColor: Colors.white,
                                          prefixIcon: Container(
                                            padding: const EdgeInsets.all(8),
                                            child: const Icon(Icons.circle,
                                                size: 10, color: Color(0xFFFBBF24)),
                                          ),
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'all', child: Text('Tất cả loại')),
                                          DropdownMenuItem(
                                              value: '0',
                                              child: Text('Cố định (theo tháng)')),
                                          DropdownMenuItem(
                                              value: '1', child: Text('Theo ngày')),
                                          DropdownMenuItem(
                                              value: '2', child: Text('Theo giờ')),
                                          DropdownMenuItem(
                                              value: '3', child: Text('Theo sự kiện')),
                                        ],
                                        onChanged: (value) => setState(
                                            () => _selectedType = value ?? 'all'),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton.icon(
                                    onPressed: _clearFilters,
                                    icon: const Icon(Icons.filter_alt_off, size: 18),
                                    label: const Text('Xóa lọc'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF71717A),
                                      side: const BorderSide(color: Color(0xFFE4E4E7)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8)),
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
                                children: List.generate(_filteredAllowances.length, (index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Container(
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
                                    child: _buildAllowanceDeckItem(_filteredAllowances[index]),
                                  ),
                                )),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF18181B),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style:
                      const TextStyle(color: Color(0xFF71717A), fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllowanceDeckItem(Map<String, dynamic> allowance) {
    final typeValue = allowance['type'] is int ? allowance['type'] : 0;
    final isActive = allowance['isActive'] ?? true;
    final amount = allowance['amount'] as num;
    String typeLabel = 'Cố định';
    if (typeValue == 1) {
      typeLabel = 'Theo ngày';
    } else if (typeValue == 2) {
      typeLabel = 'Theo giờ';
    } else if (typeValue == 3) {
      typeLabel = 'Theo sự kiện';
    }

    return InkWell(
      onTap: () => _showAllowanceDialog(allowance: allowance),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF1E3A5F).withValues(alpha: 0.1) : const Color(0xFFA1A1AA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.receipt_long, color: isActive ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(allowance['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (allowance['code'] != null && allowance['code'].toString().isNotEmpty) allowance['code'],
                      typeLabel,
                      '${_currencyFormat.format(amount)}đ',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(isActive ? 'Bật' : 'Tắt', style: TextStyle(color: isActive ? const Color(0xFF16A34A) : const Color(0xFF71717A), fontSize: 10, fontWeight: FontWeight.w500)),
            ),
            IconButton(
              onPressed: () => _deleteAllowance(allowance),
              icon: const Icon(Icons.delete_outline, size: 18),
              color: const Color(0xFF71717A),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllowanceCard(Map<String, dynamic> allowance) {
    final typeValue = allowance['type'] is int ? allowance['type'] : 0;
    final isDaily = typeValue == 1;
    final isHourly = typeValue == 2;
    final isPerEvent = typeValue == 3;
    final amount = allowance['amount'] as num;
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
                          ? const Color(0xFF1E3A5F).withValues(alpha: 0.1)
                          : const Color(0xFFA1A1AA).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.receipt_long,
                      color: isActive
                          ? const Color(0xFF1E3A5F)
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
                              color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Mã: ${allowance['code']}',
                              style: const TextStyle(
                                color: Color(0xFF1E3A5F),
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
                    style: const TextStyle(color: Color(0xFF71717A), fontSize: 11),
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
                        ? const Color(0xFF1E3A5F)
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
    final amountController =
        TextEditingController(text: allowance?['amount']?.toString() ?? '');
    int type = allowance?['type'] ?? 0; // 0 = Fixed, 1 = Daily, 2 = Hourly
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
            if (nameController.text.isEmpty ||
                amountController.text.isEmpty) {
              appNotification.showWarning(
                  title: 'Thiếu thông tin',
                  message:
                      'Vui lòng điền tên và giá trị phụ cấp');
              return;
            }

            final data = {
              'name': nameController.text,
              'code': codeController.text.isNotEmpty
                  ? codeController.text
                  : null,
              'description': descriptionController.text.isNotEmpty
                  ? descriptionController.text
                  : null,
              'type': type,
              'amount': parseFormattedNumber(amountController.text)?.toDouble() ??
                  0,
              'currency': 'VND',
              'isTaxable': isTaxable,
              'isInsuranceApplicable': isInsuranceApplicable,
              'isActive': isActive,
              if (startDate != null)
                'startDate': startDate!.toIso8601String(),
              if (endDate != null)
                'endDate': endDate!.toIso8601String(),
              if (selectedEmployeeIds.isNotEmpty)
                'employeeIds': selectedEmployeeIds,
            };

            Navigator.pop(context);

            try {
              dynamic response;
              if (isEditing) {
                response =
                    await _apiService.updateAllowanceSetting(
                        allowance['id'].toString(), data);
              } else {
                response = await _apiService
                    .createAllowanceSetting(data);
              }
              _loadAllowances();
              if (mounted) {
                if (response is Map &&
                    response['isSuccess'] == true) {
                  appNotification.showSuccess(
                    title: 'Thành công',
                    message: isEditing
                        ? 'Đã cập nhật phụ cấp'
                        : 'Đã thêm phụ cấp',
                  );
                } else if (response is Map &&
                    response['isSuccess'] == false) {
                  appNotification.showError(
                    title: 'Lỗi',
                    message: response['message'] ??
                        'Lỗi khi lưu phụ cấp',
                  );
                } else {
                  appNotification.showSuccess(
                    title: 'Thành công',
                    message: isEditing
                        ? 'Đã cập nhật phụ cấp'
                        : 'Đã thêm phụ cấp',
                  );
                }
              }
            } catch (e) {
              if (mounted) {
                appNotification.showError(
                    title: 'Lỗi', message: 'Lỗi: $e');
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
                      ? const Color(0xFF1E3A5F)
                      : const Color(0xFFA1A1AA),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: isActive,
                onChanged: (value) =>
                    setDialogState(() => isActive = value),
                activeTrackColor: const Color(0xFF1E3A5F),
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
                                              color: Color(0xFF71717A),
                                              fontSize: 13)),
                                      Text(' *',
                                          style: TextStyle(
                                              color: Color(0xFFEF4444))),
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
                                          color: Color(0xFFA1A1AA),
                                          fontSize: 13),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
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
                                            color: Color(0xFF1E3A5F)),
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
                                          color: Color(0xFF71717A),
                                          fontSize: 13)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: codeController,
                                    style: const TextStyle(
                                        color: Color(0xFF18181B), fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: 'Vd: PC_AT',
                                      hintStyle: const TextStyle(
                                          color: Color(0xFFA1A1AA),
                                          fontSize: 13),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
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
                                            color: Color(0xFF1E3A5F)),
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
                                              color: Color(0xFF71717A),
                                              fontSize: 13)),
                                      Text(' *',
                                          style: TextStyle(
                                              color: Color(0xFFEF4444))),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<int>(
                                    initialValue: type,
                                    dropdownColor: Colors.white,
                                    style: const TextStyle(
                                        color: Color(0xFF18181B), fontSize: 14),
                                    decoration: InputDecoration(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
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
                                            color: Color(0xFF1E3A5F)),
                                      ),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 0,
                                          child: Text('Cố định (theo tháng)')),
                                      DropdownMenuItem(
                                          value: 1,
                                          child: Text('Theo ngày công')),
                                      DropdownMenuItem(
                                          value: 2, child: Text('Theo giờ')),
                                      DropdownMenuItem(
                                          value: 3, child: Text('Theo sự kiện')),
                                    ],
                                    onChanged: (value) =>
                                        setDialogState(() => type = value!),
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
                                              color: Color(0xFF71717A),
                                              fontSize: 13)),
                                      Text(' *',
                                          style: TextStyle(
                                              color: Color(0xFFEF4444))),
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
                                          color: Color(0xFFA1A1AA),
                                          fontSize: 13),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
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
                                            color: Color(0xFF1E3A5F)),
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
                                          color: Color(0xFF71717A),
                                          fontSize: 13)),
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () async {
                                      final date = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            startDate ?? DateTime.now(),
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
                                        border: Border.all(
                                            color: const Color(0xFFE4E4E7)),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.calendar_today,
                                              size: 16,
                                              color: Color(0xFF71717A)),
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
                                              onTap: () => setDialogState(
                                                  () => startDate = null),
                                              child: const Icon(Icons.close,
                                                  size: 16,
                                                  color: Color(0xFFA1A1AA)),
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
                                          color: Color(0xFF71717A),
                                          fontSize: 13)),
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () async {
                                      final date = await showDatePicker(
                                        context: context,
                                        initialDate: endDate ??
                                            DateTime.now()
                                                .add(const Duration(days: 365)),
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
                                        border: Border.all(
                                            color: const Color(0xFFE4E4E7)),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.calendar_today,
                                              size: 16,
                                              color: Color(0xFF71717A)),
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
                                              onTap: () => setDialogState(
                                                  () => endDate = null),
                                              child: const Icon(Icons.close,
                                                  size: 16,
                                                  color: Color(0xFFA1A1AA)),
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
                                style: TextStyle(
                                    color: Color(0xFF71717A), fontSize: 13)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: descriptionController,
                              maxLines: 2,
                              style: const TextStyle(
                                  color: Color(0xFF18181B), fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Ghi chú về phụ cấp này...',
                                hintStyle: const TextStyle(
                                    color: Color(0xFFA1A1AA), fontSize: 13),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
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
                                      color: Color(0xFF1E3A5F)),
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
                                onChanged: (value) => setDialogState(
                                    () => isTaxable = value ?? true),
                                activeColor: const Color(0xFF1E3A5F),
                              ),
                              const Text('Tính thuế TNCN',
                                  style: TextStyle(
                                      color: Color(0xFF18181B), fontSize: 14)),
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
                                activeColor: const Color(0xFF1E3A5F),
                              ),
                              const Text('Tính bảo hiểm',
                                  style: TextStyle(
                                      color: Color(0xFF18181B), fontSize: 14)),
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
                                            : const Color(0xFF0F2340),
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
                                  foregroundColor: const Color(0xFF0F2340),
                                  side: const BorderSide(
                                      color: Color(0xFF0F2340)),
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
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Container(
              width: 650,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
                    ),
                    child: Row(
                      children: [
                        Icon(isEditing ? Icons.edit : Icons.add_circle, color: const Color(0xFF1E3A5F), size: 22),
                        const SizedBox(width: 10),
                        Text(isEditing ? 'Sửa phụ cấp' : 'Thêm phụ cấp', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF18181B))),
                        const Spacer(),
                        activeSwitch,
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Color(0xFF71717A)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Hủy'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: onSave,
                          icon: const Icon(Icons.save, size: 18),
                          label: Text(isEditing ? 'Cập nhật' : 'Thêm phụ cấp'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A5F),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                  final name = (e['fullName'] ?? e['name'] ?? '').toString().toLowerCase();
                  final code = (e['employeeCode'] ?? '').toString().toLowerCase();
                  return name.contains(searchText.toLowerCase()) || code.contains(searchText.toLowerCase());
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
                hintStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFFA1A1AA)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
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
                  Icon(tempIds.length == _employees.length ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: const Color(0xFF1E3A5F)),
                  const SizedBox(width: 10),
                  Text('Chọn tất cả (${tempIds.length}/${_employees.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          );

          final list = Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 24, color: Color(0xFFE4E4E7)),
              itemBuilder: (_, i) {
                final emp = filtered[i];
                final id = emp['id'].toString();
                final checked = tempIds.contains(id);
                final colors = [const Color(0xFF1E3A5F), const Color(0xFF1E3A5F), const Color(0xFFF59E0B), const Color(0xFF0F2340), const Color(0xFFEF4444)];
                final color = colors[i % colors.length];
                return InkWell(
                  onTap: () {
                    setDialogState(() {
                      if (checked) { tempIds.remove(id); } else { tempIds.add(id); }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(checked ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: checked ? const Color(0xFF1E3A5F) : Colors.grey[400]),
                        const SizedBox(width: 10),
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: color.withValues(alpha: 0.15),
                          child: Text((emp['fullName'] ?? emp['name'] ?? '?')[0], style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(emp['fullName'] ?? emp['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF18181B))),
                              Text(emp['employeeCode'] ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
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
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  actions: [
                    TextButton(
                      onPressed: onConfirm,
                      child: Text('Xác nhận (${tempIds.length})'),
                    ),
                  ],
                ),
                body: Column(
                  children: [searchField, selectAll, const Divider(height: 24), list],
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: math.min(450, MediaQuery.of(ctx).size.width - 32),
              height: 550,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                    child: Row(
                      children: [
                        const Icon(Icons.people, color: Color(0xFF1E3A5F), size: 20),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Chọn nhân viên', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF18181B)))),
                        IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Color(0xFF71717A), size: 20)),
                      ],
                    ),
                  ),
                  searchField,
                  selectAll,
                  const Divider(height: 24),
                  list,
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE4E4E7)))),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Tất cả NV'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF71717A),
                            side: const BorderSide(color: Color(0xFFE4E4E7)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Hủy'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: onConfirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A5F),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final response =
                    await _apiService.deleteAllowanceSetting(allowance['id'].toString());
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }
}
