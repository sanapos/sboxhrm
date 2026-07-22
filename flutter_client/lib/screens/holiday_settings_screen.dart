import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../widgets/app_scroll_safe.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../utils/lunar_converter.dart';
import '../widgets/app_button.dart';
import '../widgets/hrm/hrm_settings_mobile_kit.dart';
import '../widgets/hrm_mini_stat_chip.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
// ===== HOLIDAY SETTINGS SCREEN =====
class HolidaySettingsScreen extends StatefulWidget {
  const HolidaySettingsScreen({super.key});

  @override
  State<HolidaySettingsScreen> createState() => _HolidaySettingsScreenState();
}

class _HolidaySettingsScreenState extends State<HolidaySettingsScreen> {
  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _holidays = [];
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _categoryFilter = 'all';
  Map<String, dynamic>? _selectedHoliday;
  int _selectedYear = DateTime.now().year;

  // Pagination
  int _holidayPage = 1;
  int _holidayPageSize = 50;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  static const _primaryColor = HrmPageChrome.primaryNavy;
  static const _bgColor = Color(0xFFFAFAFA);
  static const _borderColor = Color(0xFFE4E4E7);
  static const _textDark = Color(0xFF18181B);
  static const _textMuted = Color(0xFF71717A);

  final List<Color> _badgeColors = [
    const Color(0xFFEF4444), const Color(0xFFF59E0B), HrmPageChrome.primaryNavy,
    HrmPageChrome.primaryNavy, HrmPageChrome.primaryNavy, const Color(0xFFEC4899),
    const Color(0xFF2D5F8B), HrmPageChrome.primaryNavy,
  ];

  static const List<String> _categories = [
    'Ngày nghỉ chính thức',
    'Ngày nghỉ bù',
    'Ngày nghỉ hàng tuần',
    'Ngày đặc biệt công ty',
  ];

  static final List<Map<String, dynamic>> _vietnamHolidayPresets = [
    // Solar holidays (isLunar: false) - month/day are solar dates
    {'name': 'Tết Dương lịch', 'month': 1, 'day': 1, 'isLunar': false, 'category': 'Ngày nghỉ chính thức', 'salaryRate': 3.0},
    {'name': 'Ngày Giải phóng miền Nam', 'month': 4, 'day': 30, 'isLunar': false, 'category': 'Ngày nghỉ chính thức', 'salaryRate': 3.0},
    {'name': 'Ngày Quốc tế Lao động', 'month': 5, 'day': 1, 'isLunar': false, 'category': 'Ngày nghỉ chính thức', 'salaryRate': 3.0},
    {'name': 'Ngày Quốc khánh', 'month': 9, 'day': 2, 'isLunar': false, 'category': 'Ngày nghỉ chính thức', 'salaryRate': 3.0},
    {'name': 'Ngày nghỉ bù Quốc khánh', 'month': 9, 'day': 3, 'isLunar': false, 'category': 'Ngày nghỉ bù', 'salaryRate': 2.0},
    // Lunar holidays (isLunar: true) - month/day are lunar dates
    {'name': 'Tết Nguyên Đán (30 Tết)', 'lunarMonth': 12, 'lunarDay': 30, 'isLunar': true, 'category': 'Ngày nghỉ chính thức', 'salaryRate': 3.0},
    {'name': 'Tết Nguyên Đán (Mùng 1)', 'lunarMonth': 1, 'lunarDay': 1, 'isLunar': true, 'category': 'Ngày nghỉ chính thức', 'salaryRate': 3.0},
    {'name': 'Tết Nguyên Đán (Mùng 2)', 'lunarMonth': 1, 'lunarDay': 2, 'isLunar': true, 'category': 'Ngày nghỉ chính thức', 'salaryRate': 3.0},
    {'name': 'Tết Nguyên Đán (Mùng 3)', 'lunarMonth': 1, 'lunarDay': 3, 'isLunar': true, 'category': 'Ngày nghỉ chính thức', 'salaryRate': 3.0},
    {'name': 'Tết Nguyên Đán (Mùng 4)', 'lunarMonth': 1, 'lunarDay': 4, 'isLunar': true, 'category': 'Ngày nghỉ chính thức', 'salaryRate': 3.0},
    {'name': 'Tết Nguyên Đán (Mùng 5)', 'lunarMonth': 1, 'lunarDay': 5, 'isLunar': true, 'category': 'Ngày nghỉ bù', 'salaryRate': 2.0},
    {'name': 'Giỗ Tổ Hùng Vương (10/3 ÂL)', 'lunarMonth': 3, 'lunarDay': 10, 'isLunar': true, 'category': 'Ngày nghỉ chính thức', 'salaryRate': 3.0},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getHolidaySettings(_selectedYear),
        _apiService.getEmployeesForSelect(),
      ]);
      final holidays = results[0];
      final employees = results[1];
      setState(() {
        _holidays = List<Map<String, dynamic>>.from(holidays);
        _employees = List<Map<String, dynamic>>.from(employees);
        if (_selectedHoliday != null) {
          final idx = _holidays.indexWhere((h) => h['id'] == _selectedHoliday!['id']);
          _selectedHoliday = idx >= 0 ? _holidays[idx] : null;
        }
      });
    } catch (e) {
      debugPrint('Error loading holidays: $e');
      setState(() {
        _holidays = _getDefaultHolidays(_selectedYear);
      });
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi tải dữ liệu',
          message: 'Không thể tải ngày lễ từ máy chủ. Đang hiển thị danh sách mặc định.',
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _getDefaultHolidays(int year) {
    return _vietnamHolidayPresets.map((p) {
      DateTime date;
      if (p['isLunar'] == true) {
        final lunarMonth = p['lunarMonth'] as int;
        var lunarDay = p['lunarDay'] as int;
        // For 30 Tết (lunar month 12), use previous solar year
        final lunarYear = lunarMonth == 12 ? year - 1 : year;
        // Clamp day to actual month length (month 12 may have only 29 days)
        final maxDay = LunarConverter.lunarMonthDays(lunarYear, lunarMonth);
        if (lunarDay > maxDay) lunarDay = maxDay;
        date = LunarConverter.lunarToSolar(lunarYear, lunarMonth, lunarDay);
      } else {
        date = DateTime(year, p['month'] as int, p['day'] as int);
      }
      return {
        'id': '${date.month}_${date.day}',
        'name': p['name'],
        'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'salaryRate': p['salaryRate'],
        'category': p['category'],
        'isActive': true,
      };
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredHolidays {
    var list = List<Map<String, dynamic>>.from(_holidays);
    if (_searchQuery.isNotEmpty) {
      list = list.where((h) => (h['name'] ?? '').toString().toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    if (_categoryFilter != 'all') {
      list = list.where((h) => (h['category'] ?? 'Ngày nghỉ chính thức') == _categoryFilter).toList();
    }
    return list;
  }

  String _getDayOfWeek(DateTime date) {
    const days = ['Chủ Nhật', 'Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy'];
    return days[date.weekday % 7];
  }

  String _getCategory(Map<String, dynamic> h) => h['category'] ?? 'Ngày nghỉ chính thức';

  Color _getCategoryColor(String cat) {
    switch (cat) {
      case 'Ngày nghỉ bù': return const Color(0xFFF59E0B);
      case 'Ngày nghỉ hàng tuần': return const Color(0xFF2D5F8B);
      case 'Ngày đặc biệt công ty': return HrmPageChrome.primaryNavy;
      default: return const Color(0xFFEF4444);
    }
  }

  List<String> _parseEmployeeIds(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat) {
      case 'Ngày nghỉ bù': return Icons.swap_horiz;
      case 'Ngày nghỉ hàng tuần': return Icons.weekend;
      case 'Ngày đặc biệt công ty': return Icons.business;
      default: return Icons.flag;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      backgroundColor: HrmPageChrome.scaffoldBackground(context),
      body: _isLoading
          ? const LoadingWidget()
          : isMobile
              ? _buildMainContent()
              : Row(
                  children: [
                    Expanded(
                      flex: _selectedHoliday != null ? 6 : 1,
                      child: _buildMainContent(),
                    ),
                    if (_selectedHoliday != null) ...[
                      Container(width: 1, color: _borderColor),
                      Expanded(flex: 4, child: _buildDetailPanel(_selectedHoliday!)),
                    ],
                  ],
                ),
    );
  }

  Widget _buildMainContent() {
    final isMobile = Responsive.isMobile(context);
    return Column(
      children: [
        _buildCompactToolbar(isMobile: isMobile),
        Expanded(child: _buildHolidayListBody(isMobile: isMobile)),
      ],
    );
  }

  String _shortCategory(String cat) {
    switch (cat) {
      case 'Ngày nghỉ chính thức': return 'Chính thức';
      case 'Ngày nghỉ bù': return 'Nghỉ bù';
      case 'Ngày nghỉ hàng tuần': return 'Hàng tuần';
      case 'Ngày đặc biệt công ty': return 'Đặc biệt';
      default: return cat;
    }
  }

  String _shortDayOfWeek(String full) {
    switch (full) {
      case 'Chủ Nhật':
        return 'CN';
      case 'Thứ Hai':
        return 'T2';
      case 'Thứ Ba':
        return 'T3';
      case 'Thứ Tư':
        return 'T4';
      case 'Thứ Năm':
        return 'T5';
      case 'Thứ Sáu':
        return 'T6';
      case 'Thứ Bảy':
        return 'T7';
      default:
        return full;
    }
  }

  ({List<Map<String, dynamic>> items, int safePage, int totalPages}) _pagedHolidays() {
    final all = _filteredHolidays;
    final totalPages = (all.length / _holidayPageSize).ceil().clamp(1, 9999);
    final safePage = _holidayPage.clamp(1, totalPages);
    final start = (safePage - 1) * _holidayPageSize;
    final end = (start + _holidayPageSize).clamp(0, all.length);
    return (
      items: all.sublist(start, end),
      safePage: safePage,
      totalPages: totalPages,
    );
  }

  Widget _ellipsisText(
    String text, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    TextAlign textAlign = TextAlign.start,
  }) {
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 400),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: fontSize ?? 12,
          fontWeight: fontWeight ?? FontWeight.w500,
          color: color ?? _textDark,
        ),
      ),
    );
  }

  Widget _buildYearSelector({bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
      decoration: BoxDecoration(
        border: Border.all(color: _borderColor),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              setState(() => _selectedYear--);
              _loadData();
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.chevron_left, size: 18, color: _textMuted),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$_selectedYear',
              style: TextStyle(
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.bold,
                color: _textDark,
              ),
            ),
          ),
          InkWell(
            onTap: () {
              setState(() => _selectedYear++);
              _loadData();
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.chevron_right, size: 18, color: _textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactToolbar({required bool isMobile}) {
    final embedded = HrmPageChrome.isEmbedded;
    final embeddedKit = HrmSettingsMobileKit.active(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 20,
        isMobile ? 10 : 16,
        isMobile ? 12 : 20,
        isMobile ? 10 : 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (!embedded && !isMobile) ...[
                const Icon(Icons.celebration, color: Color(0xFFF59E0B), size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Thiết lập ngày lễ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                ),
              ] else if (!embedded && isMobile)
                const Expanded(
                  child: Text(
                    'Thiết lập ngày lễ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                )
              else
                const Spacer(),
              _buildYearSelector(compact: isMobile),
              if (_perm.canCreate('Holiday')) ...[
                const SizedBox(width: 8),
                if (embeddedKit)
                  HrmSettingsAddButton(
                    label: 'Thêm ngày lễ',
                    compact: true,
                    onPressed: () => _showHolidayDialog(),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => _showHolidayDialog(),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(isMobile ? 'Thêm' : 'Thêm ngày lễ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: HrmPageChrome.primaryNavy,
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 16,
                        vertical: isMobile ? 8 : 12,
                      ),
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _buildHolidayStatsBar(),
          const SizedBox(height: 10),
          if (isMobile) ...[
            if (embeddedKit)
              HrmSettingsFilterChips(
                options: [
                  const HrmSettingsFilterChipOption(
                      value: 'all', label: 'Tất cả'),
                  ..._categories.map(
                    (c) => HrmSettingsFilterChipOption(
                      value: c,
                      label: _shortCategory(c),
                    ),
                  ),
                ],
                selected: _categoryFilter,
                onSelected: (v) => setState(() => _categoryFilter = v),
                onClear: _categoryFilter != 'all'
                    ? () => setState(() => _categoryFilter = 'all')
                    : null,
              )
            else
              _categoryDropdown(),
            const SizedBox(height: 8),
            _searchField(),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 200, child: _categoryDropdown()),
                const SizedBox(width: 12),
                Expanded(child: _searchField()),
              ],
            ),
        ],
      ),
    );
  }

  Widget _categoryDropdown() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _categoryFilter,
          isDense: true,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[400], size: 18),
          style: const TextStyle(fontSize: 12, color: _textDark),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('Tất cả danh mục')),
            ..._categories.map(
              (c) => DropdownMenuItem(
                value: c,
                child: Text(c, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (v) => setState(() => _categoryFilter = v ?? 'all'),
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Tìm ngày lễ...',
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => setState(() => _searchQuery = ''),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _borderColor),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        isDense: true,
        filled: true,
        fillColor: _bgColor,
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: (v) => setState(() => _searchQuery = v),
    );
  }

  Widget _buildListHeader() {
    TextStyle h = const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: _textMuted,
      letterSpacing: 0.2,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(flex: 4, child: Text('Tên ngày lễ', style: h)),
          SizedBox(width: 92, child: Text('Dương lịch', style: h)),
          SizedBox(width: 76, child: Text('Âm lịch', style: h)),
          SizedBox(width: 32, child: Text('Thứ', style: h)),
          SizedBox(width: 72, child: Text('Danh mục', style: h)),
          SizedBox(width: 44, child: Text('Hệ số', style: h, textAlign: TextAlign.center)),
          SizedBox(
              width: 48,
              child: Text('NV', style: h, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildHolidayListRow(
    Map<String, dynamic> holiday,
    int index, {
    required bool isSelected,
    required VoidCallback onTap,
    bool showChevron = false,
    bool useHorizontalScroll = false,
  }) {
    final date = DateTime.tryParse(holiday['date']?.toString() ?? '');
    final salaryRate = (holiday['salaryRate'] as num? ?? 3.0).toDouble();
    final dayOfWeek = date != null ? _getDayOfWeek(date) : '';
    final lunar = date != null ? LunarConverter.solarToLunar(date) : null;
    final category = _getCategory(holiday);
    final catColor = _getCategoryColor(category);
    final empIds = _parseEmployeeIds(holiday['employeeIds']);
    final color = _badgeColors[index % _badgeColors.length];
    final solar = date != null
        ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
        : '';
    final lunarStr = lunar?.toShortString() ?? '';
    final empLabel = empIds.isEmpty ? 'Tất cả' : '${empIds.length}';
    final name = holiday['name']?.toString() ?? '';

    final cells = <Widget>[
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(child: Icon(Icons.celebration, size: 16, color: color)),
      ),
      const SizedBox(width: 8),
      if (useHorizontalScroll)
        SizedBox(
          width: 128,
          child: _ellipsisText(name, fontSize: 13, fontWeight: FontWeight.w600),
        )
      else
        Expanded(
          flex: 4,
          child: _ellipsisText(name, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      SizedBox(
        width: 92,
        child: _ellipsisText(solar, fontSize: 12, color: _textMuted),
      ),
      SizedBox(
        width: 76,
        child: _ellipsisText(lunarStr, fontSize: 11, color: Colors.orange[800]),
      ),
      SizedBox(
        width: 32,
        child: _ellipsisText(
          _shortDayOfWeek(dayOfWeek),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: (dayOfWeek == 'Chủ Nhật' || dayOfWeek == 'Thứ Bảy')
              ? Colors.red
              : _textDark,
          textAlign: TextAlign.center,
        ),
      ),
      SizedBox(
        width: 72,
        child: _ellipsisText(
          _shortCategory(category),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: catColor,
        ),
      ),
      SizedBox(
        width: 44,
        child: _ellipsisText(
          '${salaryRate}x',
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: HrmPageChrome.primaryNavy,
          textAlign: TextAlign.center,
        ),
      ),
      SizedBox(
        width: 48,
        child: _ellipsisText(
          empLabel,
          fontSize: 11,
          color: _textMuted,
          textAlign: TextAlign.center,
        ),
      ),
      if (showChevron)
        const Icon(Icons.chevron_right, size: 18, color: _textMuted),
    ];

    Widget row = Row(children: cells);
    if (useHorizontalScroll) {
      row = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: row,
      );
    }

    return Material(
      color: isSelected ? _primaryColor.withValues(alpha: 0.06) : Colors.white,
      child: InkWell(
        onTap: onTap,
        hoverColor: const Color(0xFFF1F5F9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: const BorderSide(color: _borderColor, width: 0.5),
              left: isSelected
                  ? const BorderSide(color: _primaryColor, width: 3)
                  : BorderSide.none,
            ),
          ),
          child: row,
        ),
      ),
    );
  }

  Widget _buildPaginationBar() {
    final all = _filteredHolidays;
    final totalPages = (all.length / _holidayPageSize).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();
    final safePage = _holidayPage.clamp(1, totalPages);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Hiển thị:', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _holidayPageSize,
              isDense: true,
              style: TextStyle(fontSize: 12, color: Colors.grey[800]),
              items: _pageSizeOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text('$s')))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _holidayPageSize = v;
                    _holidayPage = 1;
                  });
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left),
            onPressed: safePage > 1 ? () => setState(() => _holidayPage--) : null,
          ),
          Text(
            'Trang $safePage/$totalPages · ${all.length} ngày',
            style: const TextStyle(fontSize: 12),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right),
            onPressed:
                safePage < totalPages ? () => setState(() => _holidayPage++) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildHolidayListBody({required bool isMobile}) {
    final page = _pagedHolidays();
    if (page.items.isEmpty) {
      return _buildEmptyState();
    }

    final embeddedKit = HrmSettingsMobileKit.active(context);

    if (embeddedKit && isMobile) {
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: HrmSettingsEntityGrid(
                itemCount: page.items.length,
                columns: 2,
                childAspectRatio: 0.92,
                itemBuilder: (ctx, i) {
                  final h = page.items[i];
                  final globalIndex =
                      (page.safePage - 1) * _holidayPageSize + i;
                  return _buildHolidayGridTile(h, globalIndex);
                },
              ),
            ),
          ),
          _buildPaginationBar(),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: Container(
            margin: EdgeInsets.fromLTRB(isMobile ? 10 : 16, isMobile ? 10 : 16, isMobile ? 10 : 16, 0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                if (!isMobile) _buildListHeader(),
                Expanded(
                  child: ListView.builder(
                    itemCount: page.items.length,
                    itemBuilder: (_, i) {
                      final h = page.items[i];
                      final globalIndex = (page.safePage - 1) * _holidayPageSize + i;
                      final isSelected = _selectedHoliday != null &&
                          _selectedHoliday!['id'] == h['id'];
                      return _buildHolidayListRow(
                        h,
                        globalIndex,
                        isSelected: isSelected,
                        showChevron: isMobile,
                        useHorizontalScroll: isMobile,
                        onTap: () {
                          if (isMobile) {
                            _showMobileHolidayDetailSheet(h);
                          } else {
                            setState(() => _selectedHoliday = h);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        _buildPaginationBar(),
      ],
    );
  }

  Widget _buildHolidayGridTile(Map<String, dynamic> holiday, int index) {
    final date = DateTime.tryParse(holiday['date']?.toString() ?? '');
    final category = _getCategory(holiday);
    final catColor = _getCategoryColor(category);
    final color = _badgeColors[index % _badgeColors.length];
    final solar = date != null
        ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
        : '';

    return HrmSettingsEntityTile(
      title: holiday['name']?.toString() ?? '',
      subtitle: solar,
      icon: Icons.celebration,
      iconColor: color,
      badge: _shortCategory(category),
      badgeColor: catColor,
      onTap: () => _showMobileHolidayDetailSheet(holiday),
    );
  }

  void _showMobileHolidayDetailSheet(Map<String, dynamic> holiday) {
    showAppSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(child: _buildDetailPanel(holiday, onClose: () => Navigator.pop(ctx))),
            ],
          ),
        ),
      ),
    );
  }

  // ===== DETAIL PANEL =====
  Widget _buildDetailPanel(Map<String, dynamic> holiday, {VoidCallback? onClose}) {
    final date = DateTime.tryParse(holiday['date'] ?? '');
    final salaryRate = (holiday['salaryRate'] as num? ?? 3.0).toDouble();
    final dayOfWeek = date != null ? _getDayOfWeek(date) : '';
    final lunar = date != null ? LunarConverter.solarToLunar(date) : null;
    final category = _getCategory(holiday);
    final catColor = _getCategoryColor(category);
    final empIds = _parseEmployeeIds(holiday['employeeIds']);

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Panel header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _borderColor))),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(child: Icon(Icons.celebration, color: Colors.white, size: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(holiday['name'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textDark)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: catColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(category, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: catColor)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose ?? () => setState(() => _selectedHoliday = null),
                  icon: const Icon(Icons.close, size: 20, color: _textMuted),
                ),
              ],
            ),
          ),

          // Panel content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: _borderColor)),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildDateBlock('Ngày Dương lịch', date != null ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}' : '', Icons.calendar_today, _primaryColor)),
                            Container(width: 1, height: 50, color: _borderColor),
                            Expanded(child: _buildDateBlock('Ngày Âm lịch', lunar?.toString() ?? '', Icons.auto_awesome, Colors.orange)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: (dayOfWeek == 'Chủ Nhật' || dayOfWeek == 'Thứ Bảy') ? Colors.red.withValues(alpha: 0.08) : Colors.blue.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.today, size: 16, color: (dayOfWeek == 'Chủ Nhật' || dayOfWeek == 'Thứ Bảy') ? Colors.red : _primaryColor),
                                    const SizedBox(width: 6),
                                    Text(dayOfWeek, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: (dayOfWeek == 'Chủ Nhật' || dayOfWeek == 'Thứ Bảy') ? Colors.red : _primaryColor)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.trending_up, size: 16, color: HrmPageChrome.primaryNavy),
                                  const SizedBox(width: 6),
                                  Text('Hệ số: ${salaryRate}x', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: HrmPageChrome.primaryNavy)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Category info
                  const Text('Thông tin', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _textDark)),
                  const SizedBox(height: 10),
                  _buildInfoRow(Icons.category, 'Danh mục', category, catColor),
                  _buildInfoRow(Icons.payments, 'Hệ số lương', '${salaryRate}x', HrmPageChrome.primaryNavy),
                  _buildInfoRow(Icons.people, 'Nhân viên', empIds.isEmpty ? 'Tất cả nhân viên' : '${empIds.length} nhân viên', HrmPageChrome.primaryNavy),
                  if (holiday['createdAt'] != null)
                    _buildInfoRow(Icons.access_time, 'Ngày tạo', _formatCreatedAt(holiday['createdAt']), Colors.grey),
                  const SizedBox(height: 16),

                  // Employee list (if specific)
                  if (empIds.isNotEmpty) ...[
                    const Text('Danh sách nhân viên', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _textDark)),
                    const SizedBox(height: 8),
                    ...empIds.take(5).map((id) {
                      final emp = _employees.firstWhere((e) => e['id'].toString() == id.toString(), orElse: () => {});
                      if (emp.isEmpty) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            CircleAvatar(radius: 12, backgroundColor: _primaryColor.withValues(alpha: 0.1), child: Text((emp['fullName'] ?? '?')[0], style: const TextStyle(fontSize: 10, color: _primaryColor))),
                            const SizedBox(width: 8),
                            Expanded(child: Text(emp['fullName'] ?? emp['name'] ?? '', style: const TextStyle(fontSize: 12, color: _textDark))),
                            Text(emp['employeeCode'] ?? '', style: const TextStyle(fontSize: 11, color: _textMuted)),
                          ],
                        ),
                      );
                    }),
                    if (empIds.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('... và ${empIds.length - 5} nhân viên khác', style: const TextStyle(fontSize: 11, color: _textMuted, fontStyle: FontStyle.italic)),
                      ),
                  ],
                ],
              ),
            ),
          ),

          // Action buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _borderColor))),
            child: Row(
              children: [
                if (_perm.canEdit('Holiday'))
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showHolidayDialog(holiday: holiday),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Sửa', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryColor,
                        side: const BorderSide(color: _primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                if (_perm.canEdit('Holiday') && _perm.canDelete('Holiday'))
                  const SizedBox(width: 12),
                if (_perm.canDelete('Holiday'))
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteHoliday(holiday),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Xóa', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateBlock(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color.withValues(alpha: 0.7), size: 20),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: _textMuted)),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: _textDark))),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCreatedAt(dynamic dateValue) {
    try {
      final dt = dateValue is DateTime ? dateValue : DateTime.parse(dateValue.toString());
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return dateValue.toString();
    }
  }

  Widget _buildHolidayStatsBar() {
    return HrmPageChrome.horizontalStatCards(
      cards: [
        _buildStatCard(Icons.celebration, '${_holidays.length}', 'Tổng',
            const Color(0xFFEF4444)),
        _buildStatCard(
            Icons.flag,
            '${_holidays.where((h) => _getCategory(h) == 'Ngày nghỉ chính thức').length}',
            'Chính thức',
            const Color(0xFFEF4444)),
        _buildStatCard(
            Icons.swap_horiz,
            '${_holidays.where((h) => _getCategory(h) == 'Ngày nghỉ bù').length}',
            'Nghỉ bù',
            const Color(0xFFF59E0B)),
      ],
      minCardWidth: 120,
      gap: 10,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.celebration, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Chưa có ngày lễ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('Nhấn "Thêm ngày lễ" để bắt đầu', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
          if (_perm.canCreate('Holiday')) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _showHolidayDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Thêm ngày lễ'),
              style: FilledButton.styleFrom(
                backgroundColor: HrmPageChrome.primaryNavy,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===== HOLIDAY DIALOG =====
  void _showHolidayDialog({Map<String, dynamic>? holiday}) {
    final isEditing = holiday != null;
    final nameCtrl = TextEditingController(text: holiday?['name'] ?? '');
    final salaryRateCtrl = TextEditingController(text: (holiday?['salaryRate'] ?? 3.0).toString());
    DateTime selectedDate = DateTime.tryParse(holiday?['date'] ?? '') ?? DateTime.now();
    String selectedCategory = _getCategory(holiday ?? {});
    List<String> selectedEmployeeIds = _parseEmployeeIds(holiday?['employeeIds']);
    bool isRecurring = holiday?['isRecurring'] ?? true;
    bool isSaving = false;
    String? selectedPreset;
    // Track lunar date separately for lunar-based holidays
    int lunarDay = 0;
    int lunarMonth = 0;
    int lunarYear = 0;
    bool isLunarBased = false; // ignore: unused_local_variable
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final dayOfWeek = _getDayOfWeek(selectedDate);
          final lunar = LunarConverter.solarToLunar(selectedDate);

          final isMobile = Responsive.isMobile(context);

          Future<void> onSave() async {
            if (nameCtrl.text.isEmpty) {
              appNotification.showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập tên ngày lễ');
              return;
            }
            setDialogState(() => isSaving = true);

            final data = {
              'name': nameCtrl.text,
              'date': '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
              'salaryRate': double.tryParse(salaryRateCtrl.text) ?? 3.0,
              'isActive': true,
              'isRecurring': isRecurring,
              'category': selectedCategory,
              'employeeIds': selectedEmployeeIds,
            };

            try {
              dynamic response;
              if (isEditing) {
                response = await _apiService.updateHolidaySetting(holiday['id'].toString(), data);
              } else {
                response = await _apiService.createHolidaySetting(data);
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _loadData();
              if (response is Map && response['isSuccess'] == false) {
                appNotification.showError(title: 'Lỗi', message: response['message'] ?? 'Lỗi khi lưu');
              } else {
                appNotification.showSuccess(title: 'Thành công', message: isEditing ? 'Đã cập nhật ngày lễ' : 'Đã thêm ngày lễ');
              }
            } catch (e) {
              setDialogState(() => isSaving = false);
              appNotification.showError(title: 'Lỗi', message: '$e');
            }
          }

          final formContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                          // Preset selector (only in add mode)
                          if (!isEditing) ...[
                            _dialogField('Chọn từ danh sách ngày lễ Việt Nam', Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFF59E0B)), borderRadius: BorderRadius.circular(8)),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedPreset,
                                  isExpanded: true,
                                  hint: const Text('-- Chọn ngày lễ có sẵn hoặc nhập thủ công --', style: TextStyle(fontSize: 13, color: _textMuted)),
                                  icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[400]),
                                  items: _vietnamHolidayPresets.map((p) => DropdownMenuItem(
                                    value: p['name'] as String,
                                    child: Text(p['name'] as String, style: const TextStyle(fontSize: 13)),
                                  )).toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      final preset = _vietnamHolidayPresets.firstWhere((p) => p['name'] == v);
                                      final year = DateTime.now().year;
                                      setDialogState(() {
                                        selectedPreset = v;
                                        nameCtrl.text = preset['name'] as String;
                                        salaryRateCtrl.text = (preset['salaryRate'] as num).toString();
                                        selectedCategory = preset['category'] as String;

                                        if (preset['isLunar'] == true) {
                                          // Lunar holiday: fill lunar date, compute solar
                                          isLunarBased = true;
                                          lunarMonth = preset['lunarMonth'] as int;
                                          lunarDay = preset['lunarDay'] as int;
                                          // For 30 Tết (lunar month 12), use previous solar year
                                          lunarYear = lunarMonth == 12 ? year - 1 : year;
                                          // Clamp day to actual month length (month 12 may only have 29 days)
                                          final maxDay = LunarConverter.lunarMonthDays(lunarYear, lunarMonth);
                                          if (lunarDay > maxDay) lunarDay = maxDay;
                                          selectedDate = LunarConverter.lunarToSolar(lunarYear, lunarMonth, lunarDay);
                                        } else {
                                          // Solar holiday: fill solar date, lunar auto-computes
                                          isLunarBased = false;
                                          selectedDate = DateTime(year, preset['month'] as int, preset['day'] as int);
                                          final lunar = LunarConverter.solarToLunar(selectedDate);
                                          lunarDay = lunar.day;
                                          lunarMonth = lunar.month;
                                          lunarYear = lunar.year;
                                        }
                                      });
                                    }
                                  },
                                ),
                              ),
                            )),
                            const SizedBox(height: 16),
                          ],

                          // Row 1: Name + Category
                          Row(
                            children: [
                              Expanded(flex: 3, child: _dialogField('Tên ngày lễ *', TextField(controller: nameCtrl, decoration: _inputDecor('VD: Tết Nguyên Đán'), style: const TextStyle(fontSize: 14)))),
                              const SizedBox(width: 16),
                              Expanded(flex: 2, child: _dialogField('Danh mục', Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(border: Border.all(color: _borderColor), borderRadius: BorderRadius.circular(8)),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _categories.contains(selectedCategory) ? selectedCategory : _categories[0],
                                    isExpanded: true,
                                    icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[400]),
                                    items: _categories.map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Row(
                                        children: [
                                          Icon(_getCategoryIcon(c), size: 14, color: _getCategoryColor(c)),
                                          const SizedBox(width: 6),
                                          Flexible(child: Text(c, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                                        ],
                                      ),
                                    )).toList(),
                                    onChanged: (v) => setDialogState(() => selectedCategory = v ?? _categories[0]),
                                  ),
                                ),
                              ))),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Row 2: Date + Lunar + Day of week
                          Row(
                            children: [
                              Expanded(child: _dialogField('Ngày dương lịch', InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: ctx,
                                    initialDate: selectedDate,
                                    firstDate: DateTime(DateTime.now().year - 2),
                                    lastDate: DateTime(DateTime.now().year + 5),
                                  );
                                  if (d != null) {
                                    setDialogState(() {
                                      selectedDate = d;
                                      isLunarBased = false;
                                      final lun = LunarConverter.solarToLunar(d);
                                      lunarDay = lun.day;
                                      lunarMonth = lun.month;
                                      lunarYear = lun.year;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(border: Border.all(color: _borderColor), borderRadius: BorderRadius.circular(8)),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_today, size: 16, color: _primaryColor),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text('${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}', style: const TextStyle(fontSize: 14))),
                                      Icon(Icons.edit_calendar, color: Colors.grey[400], size: 18),
                                    ],
                                  ),
                                ),
                              ))),
                              const SizedBox(width: 16),
                              Expanded(child: _dialogField('Ngày âm lịch (tự tính)', InkWell(
                                onTap: () async {
                                  // Allow editing lunar date via a simple dialog
                                  await _showLunarDatePicker(
                                    ctx,
                                    initialLunarDay: lunar.day,
                                    initialLunarMonth: lunar.month,
                                    initialLunarYear: lunar.year,
                                    onChanged: (lDay, lMonth, lYear) {
                                      setDialogState(() {
                                        lunarDay = lDay;
                                        lunarMonth = lMonth;
                                        lunarYear = lYear;
                                        isLunarBased = true;
                                        selectedDate = LunarConverter.lunarToSolar(lYear, lMonth, lDay);
                                      });
                                    },
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(color: const Color(0xFFFFF7ED), border: Border.all(color: const Color(0xFFFED7AA)), borderRadius: BorderRadius.circular(8)),
                                  child: Row(
                                    children: [
                                      Icon(Icons.auto_awesome, size: 16, color: Colors.orange[700]),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(lunar.toString(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.orange[800]))),
                                      Icon(Icons.edit_calendar, color: Colors.orange[300], size: 18),
                                    ],
                                  ),
                                ),
                              ))),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 120,
                                child: _dialogField('Thứ', Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: (dayOfWeek == 'Chủ Nhật' || dayOfWeek == 'Thứ Bảy') ? Colors.red.withValues(alpha: 0.05) : _bgColor,
                                    border: Border.all(color: _borderColor),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(dayOfWeek, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: (dayOfWeek == 'Chủ Nhật' || dayOfWeek == 'Thứ Bảy') ? Colors.red : _textDark)),
                                )),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Row 3: Salary rate + Employee count
                          Row(
                            children: [
                              Expanded(child: _dialogField('Hệ số lương', TextField(
                                controller: salaryRateCtrl,
                                decoration: _inputDecor('VD: 3.0'),
                                style: const TextStyle(fontSize: 14),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ))),
                              const SizedBox(width: 16),
                              Expanded(child: _dialogField('Nhân viên áp dụng', InkWell(
                                onTap: () => _showEmployeeSelector(
                                  selectedIds: selectedEmployeeIds,
                                  onChanged: (ids) => setDialogState(() => selectedEmployeeIds = ids),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(border: Border.all(color: _borderColor), borderRadius: BorderRadius.circular(8)),
                                  child: Row(
                                    children: [
                                      Icon(Icons.people, size: 16, color: Colors.grey[400]),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(
                                        selectedEmployeeIds.isEmpty ? 'Tất cả nhân viên' : '${selectedEmployeeIds.length} nhân viên đã chọn',
                                        style: TextStyle(fontSize: 13, color: selectedEmployeeIds.isEmpty ? _textMuted : _textDark),
                                      )),
                                      Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
                                    ],
                                  ),
                                ),
                              ))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Bỏ trống để áp dụng cho tất cả nhân viên', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                          const SizedBox(height: 12),
                          // Recurring toggle
                          InkWell(
                            onTap: () => setDialogState(() => isRecurring = !isRecurring),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: _borderColor),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(isRecurring ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: _primaryColor),
                                  const SizedBox(width: 10),
                                  const Expanded(child: Text('Lặp lại hàng năm', style: TextStyle(fontSize: 13, color: _textDark))),
                                  Text(isRecurring ? 'Có' : 'Không', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isRecurring ? _primaryColor : _textMuted)),
                                ],
                              ),
                            ),
                          ),
            ],
          );

          if (isMobile) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(isEditing ? 'Sửa ngày lễ' : 'Thêm ngày lễ'),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  actions: [
                    TextButton.icon(
                      onPressed: isSaving ? null : onSave,
                      icon: isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save, size: 18),
                      label: Text(isSaving ? 'Đang lưu...' : 'Lưu'),
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
              width: math.min(650, MediaQuery.of(context).size.width - 32),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _borderColor))),
                    child: Row(
                      children: [
                        Icon(isEditing ? Icons.edit : Icons.add_circle, color: const Color(0xFFF59E0B), size: 22),
                        const SizedBox(width: 10),
                        Text(isEditing ? 'Sửa ngày lễ' : 'Thêm ngày lễ', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textDark)),
                        const Spacer(),
                        IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: _textMuted), visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ),
                  // Form body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: formContent,
                    ),
                  ),
                  // Actions
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: _borderColor))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: isSaving ? null : () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _textMuted,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            side: const BorderSide(color: _borderColor),
                          ),
                          child: const Text('Hủy'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: isSaving ? null : onSave,
                          icon: isSaving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save, size: 18),
                          label: Text(isSaving ? 'Đang lưu...' : 'Lưu'),
                          style: FilledButton.styleFrom(
                            backgroundColor: HrmPageChrome.primaryNavy,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

  Widget _dialogField(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _textMuted)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  InputDecoration _inputDecor(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _borderColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primaryColor, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Future<void> _showLunarDatePicker(
    BuildContext parentCtx, {
    required int initialLunarDay,
    required int initialLunarMonth,
    required int initialLunarYear,
    required Function(int day, int month, int year) onChanged,
  }) async {
    int day = initialLunarDay;
    int month = initialLunarMonth;
    int year = initialLunarYear;

    await showDialog(
      context: parentCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: math.min(350, MediaQuery.of(context).size.width - 32).toDouble(),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.orange[700], size: 22),
                    const SizedBox(width: 10),
                    const Text('Chọn ngày Âm lịch', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textDark)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _dialogField('Ngày', Builder(builder: (_) {
                        final maxDay = LunarConverter.lunarMonthDays(year, month);
                        if (day > maxDay) day = maxDay;
                        return DropdownButtonFormField<int>(
                          initialValue: day.clamp(1, maxDay),
                          decoration: _inputDecor(''),
                          style: const TextStyle(fontSize: 14, color: _textDark),
                          items: List.generate(maxDay, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                          onChanged: (v) => setState(() => day = v ?? 1),
                        );
                      })),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _dialogField('Tháng', DropdownButtonFormField<int>(
                        initialValue: month.clamp(1, 12),
                        decoration: _inputDecor(''),
                        style: const TextStyle(fontSize: 14, color: _textDark),
                        items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text('Tháng ${i + 1}'))),
                        onChanged: (v) => setState(() {
                          month = v ?? 1;
                          final maxDay = LunarConverter.lunarMonthDays(year, month);
                          if (day > maxDay) day = maxDay;
                        }),
                      )),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _dialogField('Năm', DropdownButtonFormField<int>(
                        initialValue: year.clamp(2020, 2049),
                        decoration: _inputDecor(''),
                        style: const TextStyle(fontSize: 14, color: _textDark),
                        items: List.generate(30, (i) => DropdownMenuItem(value: 2020 + i, child: Text('${2020 + i}'))),
                        onChanged: (v) => setState(() {
                          year = v ?? DateTime.now().year;
                          final maxDay = LunarConverter.lunarMonthDays(year, month);
                          if (day > maxDay) day = maxDay;
                        }),
                      )),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Preview solar date
                Builder(builder: (_) {
                  final solarDate = LunarConverter.lunarToSolar(year, month, day);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 14, color: _primaryColor),
                        const SizedBox(width: 8),
                        Text('Dương lịch: ${solarDate.day.toString().padLeft(2, '0')}/${solarDate.month.toString().padLeft(2, '0')}/${solarDate.year}',
                          style: const TextStyle(fontSize: 13, color: _textDark)),
                        const SizedBox(width: 8),
                        Text('(${_getDayOfWeek(solarDate)})', style: const TextStyle(fontSize: 12, color: _textMuted)),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textMuted,
                        side: const BorderSide(color: _borderColor),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Hủy'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        onChanged(day, month, year);
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Xác nhận'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== EMPLOYEE SELECTOR =====
  void _showEmployeeSelector({
    required List<String> selectedIds,
    required Function(List<String>) onChanged,
  }) {
    final tempIds = List<String>.from(selectedIds);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isMobile = Responsive.isMobile(context);

          void onConfirm() {
            onChanged(tempIds);
            Navigator.pop(ctx);
          }

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
              color: _bgColor,
              child: Row(
                children: [
                  Icon(tempIds.length == _employees.length ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: _primaryColor),
                  const SizedBox(width: 10),
                  Text('Chọn tất cả (${tempIds.length}/${_employees.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          );

          final list = Expanded(
            child: ListView.separated(
              itemCount: _employees.length,
              separatorBuilder: (_, __) => const Divider(height: 24, color: _borderColor),
              itemBuilder: (_, i) {
                final emp = _employees[i];
                final id = emp['id'].toString();
                final checked = tempIds.contains(id);
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
                        Icon(checked ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: checked ? _primaryColor : Colors.grey[400]),
                        const SizedBox(width: 10),
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: _badgeColors[i % _badgeColors.length].withValues(alpha: 0.15),
                          child: Text((emp['fullName'] ?? emp['name'] ?? '?')[0], style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _badgeColors[i % _badgeColors.length])),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(emp['fullName'] ?? emp['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _textDark)),
                              Text(emp['employeeCode'] ?? '', style: const TextStyle(fontSize: 11, color: _textMuted)),
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
                  children: [selectAll, list],
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: math.min(450, MediaQuery.of(context).size.width - 32),
              height: 550,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _borderColor))),
                    child: Row(
                      children: [
                        const Icon(Icons.people, color: _primaryColor, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Chọn nhân viên', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textDark))),
                        IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: _textMuted, size: 20)),
                      ],
                    ),
                  ),
                  selectAll,
                  list,
                  // Footer
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: _borderColor))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _textMuted,
                            side: const BorderSide(color: _borderColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  void _deleteHoliday(Map<String, dynamic> holiday) {
    showDialog(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Xác nhận xóa', style: TextStyle(color: _textDark)),
        content: Text('Bạn có chắc muốn xóa ngày lễ "${holiday['name']}"?', style: const TextStyle(color: _textMuted)),
        actions: [AppDialogActions.delete(onConfirm: () async {
              Navigator.pop(context);
              try {
                final response = await _apiService.deleteHolidaySetting(holiday['id'].toString());
                if (_selectedHoliday?['id'] == holiday['id']) setState(() => _selectedHoliday = null);
                _loadData();
                if (response['isSuccess'] == true) {
                  appNotification.showSuccess(title: 'Thành công', message: 'Đã xóa ngày lễ');
                } else {
                  appNotification.showError(title: 'Lỗi', message: response['message'] ?? 'Lỗi khi xóa');
                }
              } catch (e) {
                appNotification.showError(title: 'Lỗi', message: '$e');
              }
            })],
      ),
    );
  }
}
