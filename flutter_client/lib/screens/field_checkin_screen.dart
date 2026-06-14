import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/field_checkin.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/store_role_helper.dart';
import '../widgets/hrm_page_chrome.dart';

Map<String, dynamic>? _findActiveFieldCheckin(List<dynamic>? checkins) {
  if (checkins == null) return null;
  for (final v in checkins) {
    if (v is Map && (v['status'] ?? '') == 'checked_in') {
      return Map<String, dynamic>.from(v);
    }
  }
  return null;
}

String _formatFieldElapsedMinutes(int mins) {
  if (mins < 1) return '<1 phút';
  if (mins < 60) return '$mins phút';
  final h = mins ~/ 60;
  final m = mins % 60;
  if (m > 0) return '${h}g ${m}p';
  return '${h}g';
}

String _liveFieldCheckinElapsed(Map<String, dynamic>? visit) {
  if (visit == null) return '';
  final raw = visit['checkInTime'];
  if (raw == null) return '';
  final checkIn = _parseApiUtc(raw);
  if (checkIn == null) return '';
  final mins = DateTime.now().toUtc().difference(checkIn.toUtc()).inMinutes;
  return _formatFieldElapsedMinutes(mins);
}

/// Server lưu UTC, JSON thường không có hậu tố Z → phải parse đúng múi giờ VN.
DateTime? _parseApiUtc(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  final dateStr =
      (raw.contains('Z') || raw.contains('+')) ? raw : '${raw}Z';
  return DateTime.tryParse(dateStr);
}

enum _StaffMapFilter { all, online, offline }

/// Bản đồ nhân sự — vị trí trực tuyến NV chấm ngoài CT (dành cho quản lý).
class FieldCheckInScreen extends StatefulWidget {
  const FieldCheckInScreen({super.key});

  @override
  State<FieldCheckInScreen> createState() => _FieldCheckInScreenState();
}

class _FieldCheckInScreenState extends State<FieldCheckInScreen> {
  static const _featureTitle = 'Bản đồ nhân sự';

  final ApiService _apiService = ApiService();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  bool _canTrack = false;
  bool _isLoading = true;
  bool _silentRefreshing = false;
  bool _mapFullscreen = false;
  String _searchQuery = '';
  _StaffMapFilter _statusFilter = _StaffMapFilter.all;
  List<Map<String, dynamic>> _employees = [];
  final Set<String> _selectedIds = {};
  final Map<String, List<JourneyTracking>> _journeysByEmployee = {};
  final Map<String, Color> _routeColorByEmployee = {};

  DateTime _rangeFrom = DateTime.now();
  DateTime _rangeTo = DateTime.now();
  DateTime? _lastRefreshedAt;

  Timer? _refreshTimer;
  Timer? _elapsedTimer;

  static const _routeColors = [
    HrmPageChrome.primaryNavy,
    Color(0xFFE53E3E),
    Color(0xFF38A169),
    Color(0xFFDD6B20),
    Color(0xFF805AD5),
    Color(0xFF2B6CB0),
    Color(0xFFD53F8C),
    Color(0xFF2C7A7B),
    Color(0xFFC05621),
    Color(0xFF6B46C1),
  ];

  static const _deptColors = _routeColors;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    _canTrack = StoreRoleHelper.isManagerOrAbove(user?.role);
    final now = DateTime.now();
    _rangeFrom = DateTime(now.year, now.month, now.day);
    _rangeTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
    if (_canTrack) {
      _loadEmployees();
      _startRefresh();
      _startElapsedRefresh();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _elapsedTimer?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _collapseEmployeeList() {
    Navigator.of(context).maybePop();
  }

  void _showEmployeeListPanel() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (_, scrollController) =>
            _buildEmployeeListSheet(scrollController),
      ),
    );
  }

  void _showEmployeesAtLocation(List<Map<String, dynamic>> group) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: (0.22 + group.length * 0.11).clamp(0.35, 0.75),
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                '${group.length} nhân viên cùng vị trí',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              ...group.map((e) => _buildEmployeeTile(e, compact: true)),
            ],
          ),
        ),
      ),
    );
  }

  void _startRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadEmployees(silent: true);
    });
  }

  void _startElapsedRefresh() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Set<String> _employeeKeys(Map<String, dynamic> emp) => {
        emp['employeeId']?.toString() ?? '',
        emp['employeeCode']?.toString() ?? '',
        emp['applicationUserId']?.toString() ?? '',
      }.where((s) => s.isNotEmpty).toSet();

  String _primaryKey(Map<String, dynamic> emp) =>
      emp['employeeId']?.toString() ??
      emp['employeeCode']?.toString() ??
      '';

  Color _deptColor(int idx) => _deptColors[idx % _deptColors.length];

  Color _routeColorFor(String empKey, int fallbackIdx) {
    return _routeColorByEmployee[empKey] ?? _routeColorForIndex(fallbackIdx);
  }

  Color _routeColorForIndex(int idx) => _routeColors[idx % _routeColors.length];

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    return s == 'true' || s == '1';
  }

  bool _isOnlineEmp(Map<String, dynamic> emp) {
    final api = emp['isOnline'];
    if (api != null) return _parseBool(api);

    // Fallback khi API thiếu cờ — đồng bộ với server (live GPS ≤10 phút).
    if (!_parseBool(emp['allowOutsideCheckIn'])) return false;
    if (emp['locationSource']?.toString() != 'live') return false;
    final last = _parseApiUtc(emp['lastUpdateTime']);
    if (last == null) return false;
    return DateTime.now().toUtc().difference(last.toUtc()).inMinutes <= 10;
  }

  List<Map<String, dynamic>> get _onlineEmployees =>
      _employees.where(_isOnlineEmp).toList();

  List<Map<String, dynamic>> get _offlineEmployees =>
      _employees.where((e) => !_isOnlineEmp(e)).toList();

  int get _onlineCount => _onlineEmployees.length;

  int get _offlineCount => _offlineEmployees.length;

  int get _onMapCount => _employees
      .where((e) => _isOnlineEmp(e) && _employeeLatLng(e) != null)
      .length;

  bool _matchesSearch(Map<String, dynamic> emp) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final name = emp['employeeName']?.toString().toLowerCase() ?? '';
    final code = emp['employeeCode']?.toString().toLowerCase() ?? '';
    final dept = emp['department']?.toString().toLowerCase() ?? '';
    return name.contains(q) || code.contains(q) || dept.contains(q);
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    return _employees.where((e) {
      if (!_matchesSearch(e)) return false;
      switch (_statusFilter) {
        case _StaffMapFilter.online:
          return _isOnlineEmp(e);
        case _StaffMapFilter.offline:
          return !_isOnlineEmp(e);
        case _StaffMapFilter.all:
          return true;
      }
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredOnline =>
      _filteredEmployees.where(_isOnlineEmp).toList();

  List<Map<String, dynamic>> get _filteredOffline =>
      _filteredEmployees.where((e) => !_isOnlineEmp(e)).toList();

  String _lastRefreshLabel() {
    if (_lastRefreshedAt == null) return 'Chưa làm mới';
    final diff = DateTime.now().difference(_lastRefreshedAt!);
    if (diff.inSeconds < 10) return 'Vừa cập nhật';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s trước';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    return DateFormat('HH:mm').format(_lastRefreshedAt!);
  }

  void _zoomToAllOnline() {
    final points = _filteredEmployees
        .where(_isOnlineEmp)
        .map(_employeeLatLng)
        .whereType<LatLng>()
        .toList();
    if (points.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (points.length == 1) {
          _mapController.move(points.first, 14);
          return;
        }
        final lats = points.map((p) => p.latitude);
        final lngs = points.map((p) => p.longitude);
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
            LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
          ),
          padding: EdgeInsets.all(_mapFullscreen ? 56 : 96),
        ));
      } catch (_) {}
    });
  }

  Widget _buildSummaryStrip() {
    Widget statChip(String label, String value, Color accent) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          statChip('Tổng', '${_employees.length}', HrmPageChrome.primaryNavy),
          const SizedBox(width: 6),
          statChip('Trực tuyến', '$_onlineCount', const Color(0xFF38A169)),
          const SizedBox(width: 6),
          statChip('Ngoại tuyến', '$_offlineCount', Colors.grey.shade600),
          const SizedBox(width: 6),
          statChip('Trên bản đồ', '$_onMapCount', const Color(0xFF2B6CB0)),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Tìm tên, mã NV, phòng ban…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text('Tất cả (${_employees.length})'),
                  selected: _statusFilter == _StaffMapFilter.all,
                  onSelected: (_) =>
                      setState(() => _statusFilter = _StaffMapFilter.all),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text('Trực tuyến ($_onlineCount)'),
                  selected: _statusFilter == _StaffMapFilter.online,
                  onSelected: (_) =>
                      setState(() => _statusFilter = _StaffMapFilter.online),
                  visualDensity: VisualDensity.compact,
                  selectedColor: const Color(0xFFE8F5E9),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text('Ngoại tuyến ($_offlineCount)'),
                  selected: _statusFilter == _StaffMapFilter.offline,
                  onSelected: (_) =>
                      setState(() => _statusFilter = _StaffMapFilter.offline),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _onlineStatusChip(Map<String, dynamic> emp) {
    final online = _isOnlineEmp(emp);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: online ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: online ? const Color(0xFF38A169) : Colors.grey.shade400,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: online ? const Color(0xFF38A169) : Colors.grey.shade500,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            online ? 'Trực tuyến' : 'Ngoại tuyến',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: online ? const Color(0xFF276749) : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleMapFullscreen({bool? value}) {
    setState(() => _mapFullscreen = value ?? !_mapFullscreen);
    if (_mapFullscreen) {
      _collapseEmployeeList();
      if (_selectedIds.length == 1) {
        final emp = _employees.firstWhere(
          (e) => _primaryKey(e) == _selectedIds.first,
          orElse: () => <String, dynamic>{},
        );
        if (emp.isNotEmpty) _zoomToEmployee(emp);
      }
    }
  }

  LatLng? _employeeLatLng(Map<String, dynamic> emp) {
    final lat = (emp['latitude'] as num?)?.toDouble();
    final lng = (emp['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null || lat == 0) return null;
    return LatLng(lat, lng);
  }

  List<LatLng> _pointsForEmployee(Map<String, dynamic> emp) {
    final empKey = _primaryKey(emp);
    final points = <LatLng>[];
    final current = _employeeLatLng(emp);
    if (current != null) points.add(current);
    for (final j in _journeysByEmployee[empKey] ?? []) {
      for (final p in j.routePoints) {
        if (p.lat != 0 || p.lng != 0) points.add(LatLng(p.lat, p.lng));
      }
    }
    return points;
  }

  void _zoomToEmployee(Map<String, dynamic> emp, {double singleZoom = 16.5}) {
    final points = _pointsForEmployee(emp);
    if (points.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (points.length == 1) {
          _mapController.move(points.first, singleZoom);
          return;
        }
        final lats = points.map((p) => p.latitude);
        final lngs = points.map((p) => p.longitude);
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
            LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
          ),
          padding: EdgeInsets.all(_mapFullscreen ? 56 : 96),
        ));
      } catch (_) {}
    });
  }

  Map<String, dynamic>? _selectedEmployee() {
    if (_selectedIds.length != 1) return null;
    final id = _selectedIds.first;
    for (final emp in _employees) {
      if (_primaryKey(emp) == id) return emp;
    }
    return null;
  }

  Future<void> _loadEmployees({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    if (silent) setState(() => _silentRefreshing = true);
    try {
      final resp = await _apiService.getEmployeeLocations(fieldStaffOnly: true);
      if (!mounted) return;
      if (resp['isSuccess'] == true && resp['data'] != null) {
        setState(() {
          _employees = (resp['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _lastRefreshedAt = DateTime.now();
          _isLoading = false;
          _silentRefreshing = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _silentRefreshing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _silentRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadJourneysForEmployee(Map<String, dynamic> emp) async {
    final empKey = _primaryKey(emp);
    if (empKey.isEmpty) return;

    final keys = _employeeKeys(emp).toList();
    final allJourneys = <JourneyTracking>[];

    for (final key in keys) {
      final resp = await _apiService.getJourneyReports(
        employeeId: key,
        fromDate: _rangeFrom,
        toDate: _rangeTo,
      );
      if (resp['isSuccess'] == true && resp['data'] != null) {
        allJourneys.addAll(
          (resp['data'] as List)
              .map((j) => JourneyTracking.fromJson(j as Map<String, dynamic>)),
        );
      }
    }

    // Dedupe by journey id
    final seen = <String>{};
    final unique = allJourneys.where((j) => seen.add(j.id)).toList()
      ..sort((a, b) => a.journeyDate.compareTo(b.journeyDate));

    if (!mounted) return;
    setState(() {
      _journeysByEmployee[empKey] = unique;
      if (!_routeColorByEmployee.containsKey(empKey)) {
        _routeColorByEmployee[empKey] =
            _routeColorForIndex(_routeColorByEmployee.length);
      }
    });

    _fitMapToSelection();
  }

  Future<void> _toggleEmployee(Map<String, dynamic> emp) async {
    final empKey = _primaryKey(emp);
    if (empKey.isEmpty) return;

    if (_selectedIds.contains(empKey)) {
      setState(() {
        _selectedIds.remove(empKey);
        _journeysByEmployee.remove(empKey);
        _routeColorByEmployee.remove(empKey);
        if (_selectedIds.isEmpty) _mapFullscreen = false;
      });
      _fitMapToSelection();
      return;
    }

    setState(() {
      _selectedIds.add(empKey);
      _mapFullscreen = true;
    });
    await _loadJourneysForEmployee(emp);
    _collapseEmployeeList();
    _zoomToEmployee(emp);
  }

  void _fitMapToSelection() {
    if (_selectedIds.length == 1) {
      final emp = _employees.firstWhere(
        (e) => _primaryKey(e) == _selectedIds.first,
        orElse: () => <String, dynamic>{},
      );
      if (emp.isNotEmpty) {
        _zoomToEmployee(emp);
        return;
      }
    }

    final points = <LatLng>[];
    for (final emp in _employees) {
      final key = _primaryKey(emp);
      if (!_selectedIds.contains(key)) continue;
      for (final j in _journeysByEmployee[key] ?? []) {
        for (final p in j.routePoints) {
          if (p.lat != 0 || p.lng != 0) points.add(LatLng(p.lat, p.lng));
        }
      }
      final current = _employeeLatLng(emp);
      if (current != null) points.add(current);
    }
    if (points.isEmpty) return;
    if (points.length == 1) {
      for (final emp in _employees) {
        if (_selectedIds.contains(_primaryKey(emp))) {
          _zoomToEmployee(emp);
          break;
        }
      }
      return;
    }
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
            LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
          ),
          padding: EdgeInsets.all(_mapFullscreen ? 56 : 96),
        ));
      } catch (_) {}
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _rangeFrom, end: _rangeTo),
    );
    if (picked == null) return;
    setState(() {
      _rangeFrom = DateTime(
          picked.start.year, picked.start.month, picked.start.day);
      _rangeTo = DateTime(picked.end.year, picked.end.month, picked.end.day,
          23, 59, 59);
      _journeysByEmployee.clear();
      _routeColorByEmployee.clear();
    });
    final selected = _selectedIds.toList();
    for (final key in selected) {
      final emp = _employees.firstWhere(
        (e) => _primaryKey(e) == key,
        orElse: () => <String, dynamic>{},
      );
      if (emp.isNotEmpty) await _loadJourneysForEmployee(emp);
    }
  }

  String _locationDurationLabel(Map<String, dynamic> emp) {
    final active = _findActiveFieldCheckin(emp['todayCheckins'] as List?);
    if (active != null) {
      final loc = active['locationName']?.toString() ?? 'điểm';
      final elapsed = _liveFieldCheckinElapsed(active);
      if (elapsed.isNotEmpty) return 'Đang ở $loc • $elapsed';
    }
    final lastUpdate = _parseApiUtc(emp['lastUpdateTime']);
    if (lastUpdate != null) {
      return 'Cập nhật ${DateFormat('HH:mm').format(lastUpdate.toLocal())}';
    }
    return 'Chưa có vị trí';
  }

  String _sourceLabel(String? source) {
    switch (source) {
      case 'journey':
        return 'Hành trình GPS';
      case 'live':
        return 'Trực tuyến';
      case 'punch':
        return 'Chấm công';
      case 'checkin':
        return 'Check-in';
      default:
        return '—';
    }
  }

  List<Widget> _buildRouteLayers() {
    final layers = <Widget>[];
    var colorIdx = 0;

    for (final empKey in _selectedIds) {
      final journeys = _journeysByEmployee[empKey] ?? [];
      final color = _routeColorFor(empKey, colorIdx++);
      for (final j in journeys) {
        final pts = j.routePoints
            .where((p) => p.lat != 0 || p.lng != 0)
            .map((p) => LatLng(p.lat, p.lng))
            .toList();
        if (pts.length < 2) continue;
        layers.add(PolylineLayer(polylines: [
          Polyline(
            points: pts,
            color: color,
            strokeWidth: 3.5,
          ),
        ]));
      }
    }
    return layers;
  }

  LatLng? _employeeLatLng(Map<String, dynamic> emp) {
    final lat = (emp['latitude'] as num?)?.toDouble();
    final lng = (emp['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null || lat == 0) return null;
    return LatLng(lat, lng);
  }

  String _locationGroupKey(double lat, double lng) =>
      '${lat.toStringAsFixed(5)}_${lng.toStringAsFixed(5)}';

  List<LatLng> _spreadMarkerPoints(LatLng center, int count) {
    if (count <= 1) return [center];
    final radiusDeg = 0.00012 + (0.00005 * count);
    final latRad = center.latitude * math.pi / 180;
    final lngScale = math.cos(latRad).abs().clamp(0.25, 1.0);
    return List.generate(count, (i) {
      final angle = (2 * math.pi * i / count) - (math.pi / 2);
      return LatLng(
        center.latitude + radiusDeg * math.sin(angle),
        center.longitude + (radiusDeg * math.cos(angle)) / lngScale,
      );
    });
  }

  Marker _buildLocationClusterMarker(
    LatLng center,
    List<Map<String, dynamic>> group,
  ) {
    return Marker(
      point: center,
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () => _showEmployeesAtLocation(group),
        child: Container(
          decoration: BoxDecoration(
            color: HrmPageChrome.primaryNavy,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '${group.length}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildEmployeeMapMarker(
    Map<String, dynamic> emp,
    LatLng point, {
    int stackCount = 1,
    List<Map<String, dynamic>>? locationGroup,
  }) {
    final empKey = _primaryKey(emp);
    final isSelected = _selectedIds.contains(empKey);
    final online = _isOnlineEmp(emp);
    final deptIdx = (emp['departmentColorIndex'] as num?)?.toInt() ?? 0;
    final baseColor = isSelected
        ? _routeColorFor(empKey, deptIdx)
        : _deptColor(deptIdx);
    final color = online ? baseColor : Colors.grey.shade600;
    final name = emp['employeeName']?.toString() ?? '?';
    final duration = online
        ? _locationDurationLabel(emp)
        : 'Ngoại tuyến • ${_locationDurationLabel(emp)}';
    final compact = stackCount > 1;
    final labelWidth = compact ? (isSelected ? 170 : 150) : (isSelected ? 230 : 200);
    final markerWidth = compact ? (isSelected ? 180 : 160) : (isSelected ? 240 : 210);
    final markerHeight = compact ? (isSelected ? 72 : 64) : (isSelected ? 84 : 72);

    return Marker(
      point: point,
      width: markerWidth.toDouble(),
      height: markerHeight.toDouble(),
      child: GestureDetector(
        onTap: () => _toggleEmployee(emp),
        onLongPress: locationGroup != null && locationGroup.length > 1
            ? () => _showEmployeesAtLocation(locationGroup)
            : null,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            constraints: BoxConstraints(maxWidth: labelWidth.toDouble()),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 4 : 6,
              vertical: compact ? 2 : 3,
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: online
                  ? Border.all(color: const Color(0xFF38A169), width: 1.5)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: online ? 0.2 : 0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (online)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 8 : 9,
                        fontWeight: FontWeight.bold,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                duration,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: compact ? 7 : 8,
                ),
              ),
            ]),
          ),
          Icon(Icons.person_pin_circle, color: color, size: compact ? 18 : 22),
        ]),
      ),
    );
  }

  List<Marker> _buildMapMarkers() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final emp in _filteredEmployees) {
      final point = _employeeLatLng(emp);
      if (point == null) continue;
      final key = _locationGroupKey(point.latitude, point.longitude);
      groups.putIfAbsent(key, () => []).add(emp);
    }

    final markers = <Marker>[];
    for (final group in groups.values) {
      if (group.length == 1) {
        markers.add(_buildEmployeeMapMarker(
          group.first,
          _employeeLatLng(group.first)!,
        ));
        continue;
      }

      final center = _employeeLatLng(group.first)!;
      markers.add(_buildLocationClusterMarker(center, group));
      final points = _spreadMarkerPoints(center, group.length);
      for (var i = 0; i < group.length; i++) {
        markers.add(_buildEmployeeMapMarker(
          group[i],
          points[i],
          stackCount: group.length,
          locationGroup: group,
        ));
      }
    }
    return markers;
  }

  Widget _buildEmployeeTile(Map<String, dynamic> emp, {bool compact = false}) {
    final empKey = _primaryKey(emp);
    final isSelected = _selectedIds.contains(empKey);
    final deptIdx = (emp['departmentColorIndex'] as num?)?.toInt() ?? 0;
    final color = isSelected ? _routeColorFor(empKey, deptIdx) : _deptColor(deptIdx);
    final name = emp['employeeName']?.toString() ?? '?';
    final dept = emp['department']?.toString() ?? '';
    final hasLocation = (emp['latitude'] as num?)?.toDouble() != null &&
        (emp['latitude'] as num?)?.toDouble() != 0;
    final online = _isOnlineEmp(emp);
    final journeys = _journeysByEmployee[empKey] ?? [];
    final totalKm = journeys.fold<double>(
        0, (s, j) => s + j.totalDistanceKm);
    final durationLabel = _locationDurationLabel(emp);

    if (compact) {
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            _onlineStatusChip(emp),
          ],
        ),
        subtitle: Text(
          [
            if (dept.isNotEmpty) dept,
            durationLabel,
            if (online && hasLocation)
              'Nguồn: ${_sourceLabel(emp['locationSource']?.toString())}',
          ].join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11,
              color: online
                  ? Colors.green.shade700
                  : (hasLocation ? Colors.grey.shade700 : Colors.grey)),
        ),
        trailing: isSelected
            ? Icon(Icons.route, color: color, size: 18)
            : Icon(Icons.chevron_right, color: Colors.grey[400], size: 18),
        selected: isSelected,
        selectedTileColor: color.withValues(alpha: 0.08),
        onTap: () => _toggleEmployee(emp),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: isSelected ? color.withValues(alpha: 0.06) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected
            ? BorderSide(color: color, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggleEmployee(emp),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
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
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        _onlineStatusChip(emp),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (dept.isNotEmpty)
                      Text(dept,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          hasLocation ? Icons.gps_fixed : Icons.location_off,
                          size: 13,
                          color: online
                              ? Colors.green
                              : (hasLocation ? Colors.grey : Colors.grey),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _locationDurationLabel(emp),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: online
                                  ? Colors.green.shade700
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hasLocation) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Nguồn: ${_sourceLabel(emp['locationSource']?.toString())}',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                    if (isSelected && journeys.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Hành trình: ${journeys.length} ngày • ${totalKm.toStringAsFixed(1)} km',
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.route : Icons.chevron_right,
                color: isSelected ? color : Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapStatsBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Tổng ${_employees.length} • Trực tuyến $_onlineCount • Ngoại tuyến $_offlineCount • $_onMapCount trên bản đồ',
        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
      ),
    );
  }

  Widget _buildMapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 22, color: color ?? HrmPageChrome.primaryNavy),
          ),
        ),
      ),
    );
  }

  void _mapZoomBy(double delta) {
    try {
      final cam = _mapController.camera;
      _mapController.move(cam.center, (cam.zoom + delta).clamp(3.0, 19.0));
    } catch (_) {}
  }

  Widget _buildSelectedEmployeeBanner() {
    final emp = _selectedEmployee();
    if (emp == null) return const SizedBox.shrink();

    final name = emp['employeeName']?.toString() ?? '?';
    final online = _isOnlineEmp(emp);
    final empKey = _primaryKey(emp);
    final deptIdx = (emp['departmentColorIndex'] as num?)?.toInt() ?? 0;
    final color = _routeColorFor(empKey, deptIdx);

    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: online ? const Color(0xFF38A169) : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    _locationDurationLabel(emp),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.route, color: color, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeListFab() {
    final count = _filteredEmployees.length;
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count', style: const TextStyle(fontSize: 10)),
      backgroundColor: const Color(0xFF38A169),
      child: _buildMapControlButton(
        icon: Icons.people_outline,
        tooltip: 'Danh sách nhân viên${count > 0 ? ' ($count)' : ''}',
        onPressed: _showEmployeeListPanel,
      ),
    );
  }

  Widget _buildSheetDragHandle() {
    return GestureDetector(
      onTap: _collapseEmployeeList,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bản đồ nhân sự (${_filteredEmployees.length}/${_employees.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Trực tuyến ${_filteredOnline.length} • Ngoại tuyến ${_filteredOffline.length} • ${_lastRefreshLabel()}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.grey[600],
                  ),
                  tooltip: 'Đóng danh sách',
                  onPressed: _collapseEmployeeList,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildEmployeeListSlivers() {
    if (_employees.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Chưa có nhân viên được bật chấm ngoài CT.\nNV bật chấm ngoài CT sẽ tự gửi vị trí khi mở app (trực tuyến ≤10 phút).',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ),
          ),
        ),
      ];
    }
    if (_filteredEmployees.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Không có nhân viên phù hợp bộ lọc.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ),
          ),
        ),
      ];
    }

    final slivers = <Widget>[];
    if (_filteredOnline.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _sectionHeader(
            'Trực tuyến (${_filteredOnline.length})',
            const Color(0xFF38A169),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _buildEmployeeTile(_filteredOnline[index], compact: true),
              childCount: _filteredOnline.length,
            ),
          ),
        ),
      );
    }
    if (_filteredOffline.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _sectionHeader(
            'Ngoại tuyến (${_filteredOffline.length})',
            Colors.grey.shade500,
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _buildEmployeeTile(_filteredOffline[index], compact: true),
              childCount: _filteredOffline.length,
            ),
          ),
        ),
      );
    }
    slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 16)));
    return slivers;
  }

  Widget _buildEmployeeListSheet(ScrollController scrollController) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: _loadEmployees,
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverToBoxAdapter(child: _buildSheetDragHandle()),
            SliverToBoxAdapter(child: _buildSearchAndFilters()),
            ..._buildEmployeeListSlivers(),
          ],
        ),
      ),
    );
  }

  Widget _buildMapStack({
    required LatLng center,
    required double zoom,
    required bool fullscreen,
  }) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.zktecoadms.app',
            ),
            ..._buildRouteLayers(),
            MarkerLayer(markers: _buildMapMarkers()),
          ],
        ),
        if (fullscreen && _selectedEmployee() != null)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: _buildSelectedEmployeeBanner(),
          ),
        if (!fullscreen)
          Positioned(
            top: 8,
            right: 8,
            child: _buildMapStatsBadge(),
          ),
        Positioned(
          top: fullscreen ? 72 : 8,
          left: 8,
          child: Column(
            children: [
              _buildMapControlButton(
                icon: fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                tooltip: fullscreen ? 'Thu nhỏ bản đồ' : 'Toàn màn hình',
                onPressed: _toggleMapFullscreen,
              ),
              if (_onMapCount > 0) ...[
                const SizedBox(height: 8),
                _buildMapControlButton(
                  icon: Icons.fit_screen,
                  tooltip: 'Hiển thị tất cả NV trực tuyến',
                  onPressed: _zoomToAllOnline,
                ),
              ],
              if (_selectedEmployee() != null) ...[
                const SizedBox(height: 8),
                _buildMapControlButton(
                  icon: Icons.my_location,
                  tooltip: 'Zoom vị trí NV đang chọn',
                  onPressed: () {
                    final emp = _selectedEmployee();
                    if (emp != null) _zoomToEmployee(emp);
                  },
                ),
              ],
            ],
          ),
        ),
        Positioned(
          bottom: 24,
          right: 8,
          child: Column(
            children: [
              _buildMapControlButton(
                icon: Icons.add,
                tooltip: 'Phóng to',
                onPressed: () => _mapZoomBy(1),
              ),
              const SizedBox(height: 8),
              _buildMapControlButton(
                icon: Icons.remove,
                tooltip: 'Thu nhỏ',
                onPressed: () => _mapZoomBy(-1),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 24,
          left: 8,
          child: _buildEmployeeListFab(),
        ),
      ],
    );
  }

  Widget _buildTrackerBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    LatLng center = const LatLng(16.0544, 108.2022);
    double zoom = 12;
    final located = _filteredEmployees
        .where((e) =>
            (e['latitude'] as num?)?.toDouble() != null &&
            (e['latitude'] as num?)?.toDouble() != 0)
        .toList();
    if (located.isNotEmpty) {
      if (located.length == 1) {
        center = LatLng(
          (located.first['latitude'] as num).toDouble(),
          (located.first['longitude'] as num).toDouble(),
        );
        zoom = 14;
      } else {
        center = LatLng(
          located
                  .map((e) => (e['latitude'] as num).toDouble())
                  .reduce((a, b) => a + b) /
              located.length,
          located
                  .map((e) => (e['longitude'] as num).toDouble())
                  .reduce((a, b) => a + b) /
              located.length,
        );
      }
    }

    if (_mapFullscreen) {
      return _buildMapStack(
        center: center,
        zoom: zoom,
        fullscreen: true,
      );
    }

    return Column(
      children: [
        _buildSummaryStrip(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickDateRange,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${DateFormat('dd/MM').format(_rangeFrom)} – ${DateFormat('dd/MM/yyyy').format(_rangeTo)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_selectedIds.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    _selectedIds.clear();
                    _journeysByEmployee.clear();
                    _routeColorByEmployee.clear();
                  }),
                  child: const Text('Bỏ chọn'),
                ),
            ],
          ),
        ),
        if (_selectedIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _selectedIds.map((id) {
                final emp = _employees.firstWhere(
                  (e) => _primaryKey(e) == id,
                  orElse: () => {'employeeName': id},
                );
                final color = _routeColorFor(id, 0);
                return Chip(
                  avatar: CircleAvatar(radius: 6, backgroundColor: color),
                  label: Text(
                    emp['employeeName']?.toString() ?? id,
                    style: const TextStyle(fontSize: 11),
                  ),
                  onDeleted: () {
                    final e = _employees.firstWhere(
                      (x) => _primaryKey(x) == id,
                      orElse: () => <String, dynamic>{},
                    );
                    if (e.isNotEmpty) _toggleEmployee(e);
                  },
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ),
        Expanded(
          child: _buildMapStack(
            center: center,
            zoom: zoom,
            fullscreen: false,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_mapFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _mapFullscreen) {
          _toggleMapFullscreen(value: false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _mapFullscreen
            ? null
            : AppBar(
                backgroundColor: HrmPageChrome.primaryNavy,
                foregroundColor: Colors.white,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _featureTitle,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    Text(
                      _silentRefreshing
                          ? 'Đang làm mới…'
                          : 'Cập nhật: ${_lastRefreshLabel()} • Tự động 30s',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                actions: [
                  if (_canTrack)
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Làm mới',
                      onPressed: () => _loadEmployees(),
                    ),
                ],
              ),
        body: _canTrack
            ? _buildTrackerBody()
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_outlined,
                          size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'Bản đồ nhân sự dành cho quản lý',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
