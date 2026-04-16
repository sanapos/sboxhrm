import 'package:flutter/material.dart';
import '../models/mobile_attendance.dart';
import '../services/api_service.dart';

class MobileAttendanceHistoryScreen extends StatefulWidget {
  const MobileAttendanceHistoryScreen({super.key});

  @override
  State<MobileAttendanceHistoryScreen> createState() =>
      _MobileAttendanceHistoryScreenState();
}

class _MobileAttendanceHistoryScreenState
    extends State<MobileAttendanceHistoryScreen> {
  final ApiService _apiService = ApiService();
  DateTime _selectedMonth = DateTime.now();
  DateTime? _selectedDate;

  List<MobileAttendanceRecord> _allRecords = [];
  List<MobileAttendanceRecord> _filteredRecords = [];
  int _currentPage = 1;
  final int _pageSize = 20;
  String? _statusFilter;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final fromDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final toDate = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);

      final response = await _apiService.getMobileAttendanceHistory(
        fromDate: fromDate,
        toDate: toDate,
      );

      if (!mounted) return;

      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is List) {
          _allRecords = data
              .map((e) => MobileAttendanceRecord.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } else {
        debugPrint('History API error: ${response['message']}');
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _filterRecords();
      }
    }
  }

  void _filterRecords() {
    setState(() {
      var records = _allRecords.toList();

      // Filter by selected date
      if (_selectedDate != null) {
        records = records.where((r) {
          return r.punchTime.year == _selectedDate!.year &&
              r.punchTime.month == _selectedDate!.month &&
              r.punchTime.day == _selectedDate!.day;
        }).toList();
      }

      // Filter by status
      if (_statusFilter != null) {
        records = records.where((r) => r.status == _statusFilter).toList();
      }

      records.sort((a, b) => b.punchTime.compareTo(a.punchTime));
      _filteredRecords = records;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
      _selectedDate = null;
      _currentPage = 1;
    });
    _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Lịch sử chấm công',
          style: TextStyle(
            color: Color(0xFF18181B),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Color(0xFF71717A)),
            onPressed: _showFilterBottomSheet,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecords,
        child: Column(
          children: [
            _buildMonthSelector(),
            _buildCalendarStrip(),
            _buildSummaryCard(),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF1E3A5F))),
              )
            else
              Expanded(child: _buildRecordsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    final months = [
      'Tháng 1', 'Tháng 2', 'Tháng 3', 'Tháng 4',
      'Tháng 5', 'Tháng 6', 'Tháng 7', 'Tháng 8',
      'Tháng 9', 'Tháng 10', 'Tháng 11', 'Tháng 12'
    ];
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left, color: Color(0xFF71717A)),
          ),
          GestureDetector(
            onTap: () => _showMonthPicker(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${months[_selectedMonth.month - 1]} ${_selectedMonth.year}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF18181B),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _changeMonth(1),
            icon: const Icon(Icons.chevron_right, color: Color(0xFF71717A)),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarStrip() {
    final daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final today = DateTime.now();
    
    return Container(
      height: 90,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: daysInMonth,
        itemBuilder: (context, index) {
          final date = DateTime(_selectedMonth.year, _selectedMonth.month, index + 1);
          final isSelected = _selectedDate?.day == date.day &&
              _selectedDate?.month == date.month &&
              _selectedDate?.year == date.year;
          final isToday = date.day == today.day &&
              date.month == today.month &&
              date.year == today.year;
          final isWeekend = date.weekday == 6 || date.weekday == 7;
          final hasRecords = _allRecords.any((r) =>
              r.punchTime.day == date.day &&
              r.punchTime.month == date.month &&
              r.punchTime.year == date.year);
          
          final weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
          
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedDate = isSelected ? null : date;
              });
              _filterRecords();
            },
            child: Container(
              width: 50,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF1E3A5F)
                    : isToday
                        ? const Color(0xFF1E3A5F).withValues(alpha: 0.1)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: isToday && !isSelected
                    ? Border.all(color: const Color(0xFF1E3A5F), width: 2)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    weekdays[date.weekday - 1],
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.8)
                          : isWeekend
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF71717A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Colors.white
                          : isWeekend
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF18181B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (hasRecords)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : const Color(0xFF1E3A5F),
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(width: 6, height: 6),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard() {
    final workDays = _filteredRecords.map((r) => '${r.punchTime.day}/${r.punchTime.month}').toSet().length;
    final checkIns = _filteredRecords.where((r) => r.punchType == 0).length;
    final checkOuts = _filteredRecords.where((r) => r.punchType == 1).length;
    final pendingCount = _filteredRecords.where((r) => r.status == 'pending').length;
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildSummaryItem(
            icon: Icons.calendar_today,
            value: '$workDays',
            label: 'Ngày làm',
            color: const Color(0xFF1E3A5F),
          ),
          _buildSummaryDivider(),
          _buildSummaryItem(
            icon: Icons.login,
            value: '$checkIns',
            label: 'Vào',
            color: const Color(0xFF1E3A5F),
          ),
          _buildSummaryDivider(),
          _buildSummaryItem(
            icon: Icons.logout,
            value: '$checkOuts',
            label: 'Ra',
            color: const Color(0xFFEF4444),
          ),
          _buildSummaryDivider(),
          _buildSummaryItem(
            icon: Icons.pending,
            value: '$pendingCount',
            label: 'Chờ duyệt',
            color: const Color(0xFFF59E0B),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF18181B),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF71717A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryDivider() {
    return Container(
      width: 1,
      height: 40,
      color: const Color(0xFFE4E4E7),
    );
  }

  Widget _buildRecordsList() {
    if (_filteredRecords.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'Không có dữ liệu chấm công',
              style: TextStyle(color: Color(0xFF71717A)),
            ),
          ],
        ),
      );
    }

    // Group by date
    final Map<String, List<MobileAttendanceRecord>> grouped = {};
    for (var record in _filteredRecords) {
      final key = '${record.punchTime.day}/${record.punchTime.month}/${record.punchTime.year}';
      grouped.putIfAbsent(key, () => []).add(record);
    }

    final groupKeys = grouped.keys.toList();
    final totalCount = groupKeys.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = (page - 1) * _pageSize;
    final endIndex = (page * _pageSize).clamp(0, totalCount);
    final paginatedKeys = groupKeys.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: paginatedKeys.length,
            itemBuilder: (context, index) {
              final dateKey = paginatedKeys[index];
              final records = grouped[dateKey]!;
              records.sort((a, b) => a.punchTime.compareTo(b.punchTime));
              
              return _buildDateGroup(dateKey, records);
            },
          ),
        ),
        if (totalPages > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Hiển thị ${startIndex + 1}-$endIndex / $totalCount ngày', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Row(children: [
                  IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: page > 1 ? () => setState(() => _currentPage--) : null, visualDensity: VisualDensity.compact),
                  Text('$page / $totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: page < totalPages ? () => setState(() => _currentPage++) : null, visualDensity: VisualDensity.compact),
                ]),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDateGroup(String dateKey, List<MobileAttendanceRecord> records) {
    final parts = dateKey.split('/');
    final date = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
    final weekdays = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ nhật'];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFAFA),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    color: Color(0xFF1E3A5F),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      weekdays[date.weekday - 1],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF18181B),
                      ),
                    ),
                    Text(
                      dateKey,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF71717A),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (records.length >= 2)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _calculateWorkHours(records),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E3A5F),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...records.map((record) => _buildRecordItem(record)),
        ],
      ),
    );
  }

  String _calculateWorkHours(List<MobileAttendanceRecord> records) {
    final checkIn = records.where((r) => r.punchType == 0).firstOrNull;
    final checkOut = records.where((r) => r.punchType == 1).lastOrNull;
    
    if (checkIn != null && checkOut != null) {
      final diff = checkOut.punchTime.difference(checkIn.punchTime);
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      return '${hours}h ${minutes}m';
    }
    return '--:--';
  }

  Widget _buildRecordItem(MobileAttendanceRecord record) {
    final isCheckIn = record.punchType == 0;
    final statusColor = record.status == 'auto_approved' || record.status == 'approved'
        ? const Color(0xFF1E3A5F)
        : const Color(0xFFF59E0B);
    final statusLabel = record.status == 'auto_approved'
        ? 'Tự động'
        : record.status == 'approved'
            ? 'Đã duyệt'
            : 'Chờ duyệt';
    
    return InkWell(
      onTap: () => _showRecordDetails(record),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: (isCheckIn ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444)).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(isCheckIn ? Icons.login : Icons.logout, size: 18, color: isCheckIn ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${record.punchTime.hour.toString().padLeft(2, '0')}:${record.punchTime.minute.toString().padLeft(2, '0')} · ${isCheckIn ? 'Vào' : 'Ra'}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF18181B)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${record.distanceFromLocation?.toInt() ?? 0}m · ${record.faceMatchScore?.toInt() ?? 0}%',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF71717A)),
          ],
        ),
      ),
    );
  }

  void _showRecordDetails(MobileAttendanceRecord record) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              record.punchType == 0 ? 'Chi tiết chấm công vào' : 'Chi tiết chấm công ra',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF18181B),
              ),
            ),
            const SizedBox(height: 20),
            _buildDetailRow(
              icon: Icons.access_time,
              label: 'Thời gian',
              value: '${record.punchTime.hour.toString().padLeft(2, '0')}:${record.punchTime.minute.toString().padLeft(2, '0')}:${record.punchTime.second.toString().padLeft(2, '0')}',
            ),
            _buildDetailRow(
              icon: Icons.calendar_today,
              label: 'Ngày',
              value: '${record.punchTime.day}/${record.punchTime.month}/${record.punchTime.year}',
            ),
            _buildDetailRow(
              icon: Icons.location_on,
              label: 'Khoảng cách',
              value: '${record.distanceFromLocation?.toInt() ?? 0}m từ văn phòng',
            ),
            _buildDetailRow(
              icon: Icons.face,
              label: 'Độ khớp khuôn mặt',
              value: '${record.faceMatchScore?.toStringAsFixed(1) ?? 0}%',
            ),
            _buildDetailRow(
              icon: Icons.verified,
              label: 'Phương thức',
              value: record.verifyMethod == 'face_gps' ? 'Face ID + GPS' : record.verifyMethod,
            ),
            _buildDetailRow(
              icon: Icons.check_circle,
              label: 'Trạng thái',
              value: record.status == 'auto_approved'
                  ? 'Tự động duyệt'
                  : record.status == 'approved'
                      ? 'Đã duyệt'
                      : 'Chờ duyệt',
            ),
            if (record.latitude != null && record.longitude != null)
              _buildDetailRow(
                icon: Icons.my_location,
                label: 'Tọa độ',
                value: '${record.latitude?.toStringAsFixed(6)}, ${record.longitude?.toStringAsFixed(6)}',
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF71717A)),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF71717A)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Color(0xFF18181B),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  void _showMonthPicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1E3A5F),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF18181B),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
        _selectedDate = null;
      });
      _loadRecords();
    }
  }

  void _showFilterBottomSheet() {
    String? tempFilter = _statusFilter;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Lọc theo trạng thái',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF18181B),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                _buildFilterChip('Tất cả', tempFilter == null, (selected) {
                  setSheetState(() => tempFilter = null);
                }),
                _buildFilterChip('Đã duyệt', tempFilter == 'approved', (selected) {
                  setSheetState(() => tempFilter = selected ? 'approved' : null);
                }),
                _buildFilterChip('Chờ duyệt', tempFilter == 'pending', (selected) {
                  setSheetState(() => tempFilter = selected ? 'pending' : null);
                }),
                _buildFilterChip('Tự động duyệt', tempFilter == 'auto_approved', (selected) {
                  setSheetState(() => tempFilter = selected ? 'auto_approved' : null);
                }),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _statusFilter = tempFilter;
                    _currentPage = 1;
                  });
                  _filterRecords();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Áp dụng', style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, ValueChanged<bool> onSelected) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
      checkmarkColor: const Color(0xFF1E3A5F),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF1E3A5F) : const Color(0xFF71717A),
      ),
    );
  }
}
