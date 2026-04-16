import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/app_button.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import 'settings_hub_screen.dart';

// ===== LUNAR CALENDAR CONVERTER =====
class LunarDate {
  final int day, month, year;
  final bool isLeapMonth;
  LunarDate(this.day, this.month, this.year, {this.isLeapMonth = false});

  String toShortString() => '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}${isLeapMonth ? ' (nhuận)' : ''}';

  @override
  String toString() => '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year${isLeapMonth ? ' (nhuận)' : ''}';
}

class LunarConverter {
  // Standard verified Chinese/Vietnamese lunar calendar lookup table (1900-2049)
  // Encoding: bit 16 = leap month 30 days (1) or 29 days (0)
  //           bits 15-4 = month 1-12 big/small (1=30, 0=29)
  //           bits 3-0 = leap month number (0=no leap)
  static const List<int> _lunarMonthDays = [
    0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2, // 1900-1909
    0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977, // 1910-1919
    0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970, // 1920-1929
    0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950, // 1930-1939
    0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557, // 1940-1949
    0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0, // 1950-1959
    0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0, // 1960-1969
    0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6, // 1970-1979
    0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570, // 1980-1989
    0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x05ac0, 0x0ab60, 0x096d5, 0x092e0, // 1990-1999
    0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5, // 2000-2009
    0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930, // 2010-2019
    0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530, // 2020-2029
    0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d25f, 0x0d520, 0x0dd45, // 2030-2039
    0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0, // 2040-2049
  ];

  static const int _baseYear = 1900;
  static final DateTime _baseDate = DateTime(1900, 1, 31);

  static int _leapMonth(int year) {
    if (year - _baseYear < 0 || year - _baseYear >= _lunarMonthDays.length) return 0;
    return _lunarMonthDays[year - _baseYear] & 0xf;
  }

  static int _leapDays(int year) {
    if (_leapMonth(year) != 0) {
      return (_lunarMonthDays[year - _baseYear] & 0x10000) != 0 ? 30 : 29;
    }
    return 0;
  }

  static int _monthDays(int year, int month) {
    if (year - _baseYear < 0 || year - _baseYear >= _lunarMonthDays.length) return 29;
    return (_lunarMonthDays[year - _baseYear] & (0x10000 >> month)) != 0 ? 30 : 29;
  }

  /// Public method to get number of days in a lunar month (29 or 30)
  static int lunarMonthDays(int year, int month) => _monthDays(year, month);

  static int _yearDays(int year) {
    int sum = 348;
    if (year - _baseYear < 0 || year - _baseYear >= _lunarMonthDays.length) return sum;
    for (int i = 0x8000; i > 0x8; i >>= 1) {
      sum += (_lunarMonthDays[year - _baseYear] & i) != 0 ? 1 : 0;
    }
    return sum + _leapDays(year);
  }

  static LunarDate solarToLunar(DateTime solar) {
    int offset = solar.difference(_baseDate).inDays;
    if (offset < 0) return LunarDate(solar.day, solar.month, solar.year);

    int lunarYear = _baseYear;
    int temp = 0;
    for (lunarYear = _baseYear; lunarYear < 2050 && offset > 0; lunarYear++) {
      temp = _yearDays(lunarYear);
      offset -= temp;
    }
    if (offset < 0) {
      offset += _yearDays(--lunarYear);
    }

    int leapMon = _leapMonth(lunarYear);
    bool isLeap = false;
    int lunarMonth = 1;

    for (lunarMonth = 1; lunarMonth < 13 && offset > 0; lunarMonth++) {
      if (leapMon > 0 && lunarMonth == (leapMon + 1) && !isLeap) {
        --lunarMonth;
        isLeap = true;
        temp = _leapDays(lunarYear);
      } else {
        temp = _monthDays(lunarYear, lunarMonth);
      }
      if (isLeap && lunarMonth == (leapMon + 1)) isLeap = false;
      offset -= temp;
    }
    if (offset < 0) {
      offset += temp;
      --lunarMonth;
    }
    if (offset == 0 && leapMon > 0 && lunarMonth == leapMon + 1) {
      if (isLeap) {
        isLeap = false;
      } else {
        isLeap = true;
        --lunarMonth;
      }
    }

    int lunarDay = offset + 1;
    return LunarDate(lunarDay, lunarMonth, lunarYear, isLeapMonth: isLeap);
  }

  /// Convert lunar date to solar date
  static DateTime lunarToSolar(int lunarYear, int lunarMonth, int lunarDay, {bool isLeapMonth = false}) {
    if (lunarYear < _baseYear || lunarYear - _baseYear >= _lunarMonthDays.length) {
      return DateTime(lunarYear, lunarMonth, lunarDay);
    }

    int offset = 0;
    // Add days of years from baseYear to lunarYear-1
    for (int y = _baseYear; y < lunarYear; y++) {
      offset += _yearDays(y);
    }

    // Add days of months in lunarYear before lunarMonth
    int leapMon = _leapMonth(lunarYear);
    bool afterLeap = false;
    for (int m = 1; m < lunarMonth; m++) {
      // If there's a leap month before current month, add its days
      if (leapMon > 0 && m == leapMon && !afterLeap) {
        offset += _leapDays(lunarYear);
        afterLeap = true;
      }
      offset += _monthDays(lunarYear, m);
    }

    // If this IS the leap month
    if (isLeapMonth && lunarMonth == leapMon) {
      offset += _monthDays(lunarYear, lunarMonth);
    }
    // If not leap month but leap month comes before/at same month, and we haven't added it yet
    if (!isLeapMonth && leapMon > 0 && leapMon < lunarMonth && !afterLeap) {
      offset += _leapDays(lunarYear);
    }

    offset += lunarDay - 1;

    return _baseDate.add(Duration(days: offset));
  }
}

// ===== HOLIDAY SETTINGS SCREEN =====
class HolidaySettingsScreen extends StatefulWidget {
  const HolidaySettingsScreen({super.key});

  @override
  State<HolidaySettingsScreen> createState() => _HolidaySettingsScreenState();
}

class _HolidaySettingsScreenState extends State<HolidaySettingsScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _holidays = [];
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _categoryFilter = 'all';
  Map<String, dynamic>? _selectedHoliday;
  int _selectedYear = DateTime.now().year;
  bool _showMobileFilters = false;

  // Pagination
  int _holidayPage = 1;
  int _holidayPageSize = 50;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  static const _primaryColor = Color(0xFF1E3A5F);
  static const _bgColor = Color(0xFFFAFAFA);
  static const _borderColor = Color(0xFFE4E4E7);
  static const _textDark = Color(0xFF18181B);
  static const _textMuted = Color(0xFF71717A);

  final List<Color> _badgeColors = [
    const Color(0xFFEF4444), const Color(0xFFF59E0B), const Color(0xFF1E3A5F),
    const Color(0xFF1E3A5F), const Color(0xFF0F2340), const Color(0xFFEC4899),
    const Color(0xFF2D5F8B), const Color(0xFF0F2340),
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
        _apiService.getEmployees(),
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
      case 'Ngày đặc biệt công ty': return const Color(0xFF0F2340);
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
      backgroundColor: _bgColor,
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
    if (isMobile) {
      return _buildMobileContent();
    }
    return Column(
      children: [
        // Header
        Container(
          padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, isMobile ? 12 : 20, isMobile ? 16 : 24, isMobile ? 12 : 16),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!isMobile) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
                      onPressed: () => SettingsHubScreen.goBack(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Icon(Icons.celebration, color: Color(0xFFF59E0B), size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Thiết lập Ngày Lễ', style: TextStyle(fontSize: isMobile ? 16 : 20, fontWeight: FontWeight.bold, color: _textDark)),
                  ),
                  // Year selector
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: _borderColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () { setState(() { _selectedYear--; }); _loadData(); },
                          child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.chevron_left, size: 18, color: _textMuted)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text('$_selectedYear', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _textDark)),
                        ),
                        InkWell(
                          onTap: () { setState(() { _selectedYear++; }); _loadData(); },
                          child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.chevron_right, size: 18, color: _textMuted)),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showHolidayDialog(),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(isMobile ? 'Thêm' : 'Thêm ngày lễ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A5F),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 8 : 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Stats + Search
              if (isMobile) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildMiniStat(Icons.celebration, '${_holidays.length}', 'Tổng', const Color(0xFFEF4444)),
                      const SizedBox(width: 8),
                      _buildMiniStat(Icons.flag, '${_holidays.where((h) => _getCategory(h) == 'Ngày nghỉ chính thức').length}', 'Chính thức', const Color(0xFFEF4444)),
                      const SizedBox(width: 8),
                      _buildMiniStat(Icons.swap_horiz, '${_holidays.where((h) => _getCategory(h) == 'Ngày nghỉ bù').length}', 'Nghỉ bù', const Color(0xFFF59E0B)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: _borderColor)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _categoryFilter,
                            isDense: true,
                            isExpanded: true,
                            icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[400], size: 18),
                            style: const TextStyle(fontSize: 12, color: _textDark),
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('Tất cả danh mục')),
                              ..._categories.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))),
                            ],
                            onChanged: (v) => setState(() => _categoryFilter = v ?? 'all'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Tìm ngày lễ...',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _searchQuery = ''))
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _borderColor)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                    filled: true,
                    fillColor: _bgColor,
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ] else ...[
              Row(
                children: [
                  _buildMiniStat(Icons.celebration, '${_holidays.length}', 'Tổng', const Color(0xFFEF4444)),
                  const SizedBox(width: 12),
                  _buildMiniStat(Icons.flag, '${_holidays.where((h) => _getCategory(h) == 'Ngày nghỉ chính thức').length}', 'Chính thức', const Color(0xFFEF4444)),
                  const SizedBox(width: 12),
                  _buildMiniStat(Icons.swap_horiz, '${_holidays.where((h) => _getCategory(h) == 'Ngày nghỉ bù').length}', 'Nghỉ bù', const Color(0xFFF59E0B)),
                  const SizedBox(width: 12),
                  // Category filter
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: _borderColor)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _categoryFilter,
                        isDense: true,
                        icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[400], size: 18),
                        style: const TextStyle(fontSize: 12, color: _textDark),
                        items: [
                          const DropdownMenuItem(value: 'all', child: Text('Tất cả danh mục')),
                          ..._categories.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (v) => setState(() => _categoryFilter = v ?? 'all'),
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Tìm ngày lễ...',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                        prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _searchQuery = ''))
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _borderColor)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        isDense: true,
                        filled: true,
                        fillColor: _bgColor,
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                ],
              ),
              ],
            ],
          ),
        ),

        // Content - Cards on mobile, Table on desktop
        Expanded(
          child: _filteredHolidays.isEmpty
              ? _buildEmptyState()
              : isMobile
                  ? _buildHolidayCardList()
                  : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _borderColor),
                    ),
                    child: Column(
                      children: [
                        // Table header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: const BoxDecoration(
                            color: _bgColor,
                            borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                          ),
                          child: Row(
                            children: [
                              _tableHeader('Tên ngày lễ', flex: 4),
                              _tableHeader('Danh mục', flex: 3),
                              _tableHeader('Ngày dương lịch', flex: 2),
                              _tableHeader('Ngày âm lịch', flex: 2),
                              _tableHeader('Thứ trong tuần', flex: 2),
                              _tableHeader('Hệ số', flex: 1),
                              _tableHeader('Nhân viên', flex: 1),
                            ],
                          ),
                        ),
                        const Divider(height: 24, color: _borderColor),
                        Builder(builder: (_) {
                          final allHolidays = _filteredHolidays;
                          final totalPages = (allHolidays.length / _holidayPageSize).ceil();
                          final safePage = _holidayPage.clamp(1, totalPages == 0 ? 1 : totalPages);
                          final startIdx = (safePage - 1) * _holidayPageSize;
                          final endIdx = (startIdx + _holidayPageSize).clamp(0, allHolidays.length);
                          return Column(children: [
                            ...List.generate(endIdx - startIdx, (idx) {
                              final i = startIdx + idx;
                              final h = allHolidays[i];
                              final isSelected = _selectedHoliday != null && _selectedHoliday!['id'] == h['id'];
                              return _buildTableRow(h, i, isSelected);
                            }),
                            if (totalPages > 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
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
                                          value: _holidayPageSize,
                                          isDense: true,
                                          style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                                          items: _pageSizeOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                                          onChanged: (v) {
                                            if (v != null) setState(() { _holidayPageSize = v; _holidayPage = 1; });
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    IconButton(icon: const Icon(Icons.first_page), onPressed: safePage > 1 ? () => setState(() => _holidayPage = 1) : null),
                                    IconButton(icon: const Icon(Icons.chevron_left), onPressed: safePage > 1 ? () => setState(() => _holidayPage--) : null),
                                    Text('Trang $safePage / $totalPages (${allHolidays.length} dòng)', style: const TextStyle(fontSize: 13)),
                                    IconButton(icon: const Icon(Icons.chevron_right), onPressed: safePage < totalPages ? () => setState(() => _holidayPage++) : null),
                                    IconButton(icon: const Icon(Icons.last_page), onPressed: safePage < totalPages ? () => setState(() => _holidayPage = totalPages) : null),
                                  ],
                                ),
                              ),
                          ]);
                        }),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _tableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _textMuted, letterSpacing: 0.5)),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> holiday, int index, bool isSelected) {
    final date = DateTime.tryParse(holiday['date'] ?? '');
    final salaryRate = (holiday['salaryRate'] as num? ?? 3.0).toDouble();
    final dayOfWeek = date != null ? _getDayOfWeek(date) : '';
    final lunar = date != null ? LunarConverter.solarToLunar(date) : null;
    final category = _getCategory(holiday);
    final catColor = _getCategoryColor(category);
    final empIds = _parseEmployeeIds(holiday['employeeIds']);
    final color = _badgeColors[index % _badgeColors.length];

    return InkWell(
      onTap: () => setState(() => _selectedHoliday = holiday),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? _primaryColor.withValues(alpha: 0.06) : Colors.white,
          border: Border(
            bottom: const BorderSide(color: _borderColor, width: 0.5),
            left: isSelected ? const BorderSide(color: _primaryColor, width: 3) : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            // Holiday name
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Icon(Icons.celebration, size: 18, color: color)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(holiday['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textDark), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            // Category
            Expanded(
              flex: 3,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_getCategoryIcon(category), size: 12, color: catColor),
                  const SizedBox(width: 4),
                  Flexible(child: Text(category, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: catColor), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            // Solar date
            Expanded(
              flex: 2,
              child: Text(
                date != null ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}' : '',
                style: const TextStyle(fontSize: 13, color: _textDark),
              ),
            ),
            // Lunar date
            Expanded(
              flex: 2,
              child: Text(lunar?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.orange[700])),
            ),
            // Day of week
            Expanded(
              flex: 2,
              child: Text(dayOfWeek, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: (dayOfWeek == 'Chủ Nhật' || dayOfWeek == 'Thứ Bảy') ? Colors.red : _textDark)),
            ),
            // Salary rate
            Expanded(
              flex: 1,
              child: Text('${salaryRate}x', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F2340))),
            ),
            // Employee count
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Icon(Icons.people, size: 13, color: Colors.grey[400]),
                  const SizedBox(width: 3),
                  Text(empIds.isEmpty ? 'Tất cả' : '${empIds.length}', style: const TextStyle(fontSize: 11, color: _textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== MOBILE CARD VIEW =====
  // ===== MOBILE FULL-SCROLL LAYOUT =====
  Widget _buildMobileContent() {
    final allHolidays = _filteredHolidays;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.celebration, color: Color(0xFFF59E0B), size: 26),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Thiết lập Ngày Lễ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textDark)),
                    ),
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: _borderColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () { setState(() { _selectedYear--; }); _loadData(); },
                            child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.chevron_left, size: 18, color: _textMuted)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text('$_selectedYear', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _textDark)),
                          ),
                          InkWell(
                            onTap: () { setState(() { _selectedYear++; }); _loadData(); },
                            child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.chevron_right, size: 18, color: _textMuted)),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showHolidayDialog(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Thêm'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _showMobileFilters = !_showMobileFilters),
                      icon: Stack(
                        children: [
                          Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, color: const Color(0xFF1E3A5F)),
                          if (_searchQuery.isNotEmpty || _categoryFilter != 'all')
                            Positioned(right: 0, top: 0, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle))),
                        ],
                      ),
                      tooltip: 'Bộ lọc',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildMiniStat(Icons.celebration, '${_holidays.length}', 'Tổng', const Color(0xFFEF4444)),
                      const SizedBox(width: 8),
                      _buildMiniStat(Icons.flag, '${_holidays.where((h) => _getCategory(h) == 'Ngày nghỉ chính thức').length}', 'Chính thức', const Color(0xFFEF4444)),
                      const SizedBox(width: 8),
                      _buildMiniStat(Icons.swap_horiz, '${_holidays.where((h) => _getCategory(h) == 'Ngày nghỉ bù').length}', 'Nghỉ bù', const Color(0xFFF59E0B)),
                    ],
                  ),
                ),
                if (_showMobileFilters) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: _borderColor)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _categoryFilter,
                            isDense: true,
                            isExpanded: true,
                            icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[400], size: 18),
                            style: const TextStyle(fontSize: 12, color: _textDark),
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('Tất cả danh mục')),
                              ..._categories.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))),
                            ],
                            onChanged: (v) => setState(() => _categoryFilter = v ?? 'all'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Tìm ngày lễ...',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _searchQuery = ''))
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _borderColor)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                    filled: true,
                    fillColor: _bgColor,
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
                ],
              ],
            ),
          ),
        ),
        if (allHolidays.isEmpty)
          SliverFillRemaining(child: _buildEmptyState())
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: List.generate(allHolidays.length, (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildHolidayDeckItem(allHolidays[i], i),
                  ),
                )),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHolidayCardList() {
    final allHolidays = _filteredHolidays;
    final totalPages = (allHolidays.length / _holidayPageSize).ceil();
    final safePage = _holidayPage.clamp(1, totalPages == 0 ? 1 : totalPages);
    final startIdx = (safePage - 1) * _holidayPageSize;
    final endIdx = (startIdx + _holidayPageSize).clamp(0, allHolidays.length);
    final pageHolidays = allHolidays.sublist(startIdx, endIdx);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Column(
                children: List.generate(pageHolidays.length, (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildHolidayDeckItem(pageHolidays[i], startIdx + i),
                  ),
                )),
              ),
            ],
          ),
        ),
        if (totalPages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
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
                        value: _holidayPageSize,
                        isDense: true,
                        style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                        items: _pageSizeOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                        onChanged: (v) {
                          if (v != null) setState(() { _holidayPageSize = v; _holidayPage = 1; });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: safePage > 1 ? () => setState(() => _holidayPage--) : null),
                  Text('$safePage / $totalPages', style: const TextStyle(fontSize: 13)),
                  IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: safePage < totalPages ? () => setState(() => _holidayPage++) : null),
                ],
              ),
            ]),
          ),
      ],
    );
  }

  Widget _buildHolidayDeckItem(Map<String, dynamic> holiday, int index) {
    final date = DateTime.tryParse(holiday['date'] ?? '');
    final salaryRate = (holiday['salaryRate'] as num? ?? 3.0).toDouble();
    final dayOfWeek = date != null ? _getDayOfWeek(date) : '';
    final lunar = date != null ? LunarConverter.solarToLunar(date) : null;
    final category = _getCategory(holiday);
    final catColor = _getCategoryColor(category);
    final empIds = _parseEmployeeIds(holiday['employeeIds']);
    final color = _badgeColors[index % _badgeColors.length];
    final dateStr = date != null ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}' : '';

    return InkWell(
      onTap: () => _showMobileHolidayDetailSheet(holiday),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Center(child: Icon(Icons.celebration, size: 18, color: color)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(holiday['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textDark), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(dateStr, style: const TextStyle(fontSize: 11, color: _textMuted)),
                      if (dayOfWeek.isNotEmpty) ...[
                        const Text(' · ', style: TextStyle(fontSize: 11, color: _textMuted)),
                        Text(dayOfWeek, style: TextStyle(fontSize: 11, color: (dayOfWeek == 'Chủ Nhật' || dayOfWeek == 'Thứ Bảy') ? Colors.red : _textMuted)),
                      ],
                      if (lunar != null) ...[
                        const Text(' · ', style: TextStyle(fontSize: 11, color: _textMuted)),
                        Flexible(child: Text(lunar.toShortString(), style: TextStyle(fontSize: 11, color: Colors.orange[700]), overflow: TextOverflow.ellipsis)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(color: catColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(_shortCategory(category), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: catColor)),
            ),
            const SizedBox(width: 6),
            Text('${salaryRate}x', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F2340))),
            if (empIds.isNotEmpty) ...[
              const SizedBox(width: 6),
              Icon(Icons.people, size: 12, color: Colors.grey[400]),
              Text('${empIds.length}', style: const TextStyle(fontSize: 10, color: _textMuted)),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
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

  void _showMobileHolidayDetailSheet(Map<String, dynamic> holiday) {
    showModalBottomSheet(
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
                                color: const Color(0xFF0F2340).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.trending_up, size: 16, color: Color(0xFF0F2340)),
                                  const SizedBox(width: 6),
                                  Text('Hệ số: ${salaryRate}x', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F2340))),
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
                  _buildInfoRow(Icons.payments, 'Hệ số lương', '${salaryRate}x', const Color(0xFF0F2340)),
                  _buildInfoRow(Icons.people, 'Nhân viên', empIds.isEmpty ? 'Tất cả nhân viên' : '${empIds.length} nhân viên', const Color(0xFF1E3A5F)),
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
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showHolidayDialog(holiday: holiday),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Sửa', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      side: const BorderSide(color: _primaryColor),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteHoliday(holiday),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Xóa', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _buildMiniStat(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8))),
        ],
      ),
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
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _showHolidayDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Thêm ngày lễ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
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
                        ElevatedButton.icon(
                          onPressed: isSaving ? null : onSave,
                          icon: isSaving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save, size: 18),
                          label: Text(isSaving ? 'Đang lưu...' : 'Lưu'),
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
                    ElevatedButton(
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

  void _deleteHoliday(Map<String, dynamic> holiday) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
