import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/field_checkin.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/platform_geolocation.dart';
import '../widgets/notification_overlay.dart';

class FieldCheckInScreen extends StatefulWidget {
  const FieldCheckInScreen({super.key});
  @override
  State<FieldCheckInScreen> createState() => _FieldCheckInScreenState();
}

class _FieldCheckInScreenState extends State<FieldCheckInScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabCtl;
  final MapController _mapController = MapController();

  // Auth
  String _employeeName = '';
  bool _isManager = false;

  // Data
  List<FieldLocationAssignment> _myAssignments = [];
  List<VisitReport> _todayVisits = [];
  JourneyTracking? _todayJourney;
  List<FieldLocation> _fieldLocations = [];
  bool _isLoadingMyData = true;

  // GPS tracking
  double? _currentLat;
  double? _currentLng;
  bool _isGettingLocation = false;
  Timer? _trackingTimer;
  Timer? _managerRefreshTimer;
  Timer? _locationReportTimer;
  final List<Map<String, dynamic>> _pendingTrackPoints = [];
  double? _lastTrackedLat;
  double? _lastTrackedLng;
  static const _kPendingPointsKey = 'field_checkin_pending_gps';

  // History tab
  List<VisitReport> _historyVisits = [];
  List<JourneyTracking> _journeyHistory = [];
  DateTime _historyFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _historyTo = DateTime.now();
  bool _isLoadingHistory = false;
  String _historySearchQuery = '';
  String? _historyEmployeeFilter;
  final TextEditingController _historySearchCtl = TextEditingController();

  // Manager tab
  List<FieldLocationAssignment> _allAssignments = [];
  List<VisitReport> _reports = [];
  List<JourneyTracking> _managerJourneys = [];
  bool _isLoadingManager = false;
  String _managerCustomerStatusFilter = 'Tất cả';
  DateTime _reportFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _reportTo = DateTime.now();
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _locations = [];

  // Manager map
  final MapController _managerMapController = MapController();
  // ignore: unused_field
  List<Map<String, dynamic>> _activeJourneys = [];
  List<Map<String, dynamic>> _employeeLocations = [];
  String? _selectedEmployeeId;
  bool _showManagerMap = true;
  // Journey overlay on manager map
  JourneyTracking? _selectedJourney;
  bool _isLoadingJourney = false;

  // Field location search
  final TextEditingController _locationSearchCtl = TextEditingController();
  List<FieldLocation> _searchResults = [];
  bool _isSearching = false;

  // Bottom sheet
  final DraggableScrollableController _sheetCtl = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user != null) {
      _employeeName = user.fullName;
      _isManager = user.role == 'Admin' || user.role == 'Manager' || user.role == 'Director';
    }
    _tabCtl = TabController(length: _isManager ? 3 : 2, vsync: this);
    _tabCtl.addListener(() {
      if (!_tabCtl.indexIsChanging) _onTabChanged();
    });
    _loadMyData();
    _restorePendingPoints();
    _startLocationReporting();
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _managerRefreshTimer?.cancel();
    _locationReportTimer?.cancel();
    _locationSearchCtl.dispose();
    _tabCtl.dispose();
    _sheetCtl.dispose();
    _mapController.dispose();
    _managerMapController.dispose();
    _historySearchCtl.dispose();
    super.dispose();
  }

  // ========== GPS Persistence ==========
  Future<void> _restorePendingPoints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kPendingPointsKey);
      if (saved != null && saved.isNotEmpty) {
        final list = (jsonDecode(saved) as List).cast<Map<String, dynamic>>();
        if (list.isNotEmpty) {
          _pendingTrackPoints.addAll(list);
          // Try to flush them if we have an active journey
          if (_pendingTrackPoints.length >= 2) {
            final pts = List<Map<String, dynamic>>.from(_pendingTrackPoints);
            _pendingTrackPoints.clear();
            await _apiService.trackJourneyPoints(pts);
            await prefs.remove(_kPendingPointsKey);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _savePendingPoints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pendingTrackPoints.isNotEmpty) {
        await prefs.setString(_kPendingPointsKey, jsonEncode(_pendingTrackPoints));
      } else {
        await prefs.remove(_kPendingPointsKey);
      }
    } catch (_) {}
  }

  void _onTabChanged() {
    if (_tabCtl.index == 1 && _historyVisits.isEmpty && _journeyHistory.isEmpty) {
      _loadHistory();
    } else if (_tabCtl.index == 2 && _isManager && _reports.isEmpty) {
      _loadManagerData();
    }
    // Start/stop manager auto-refresh
    if (_tabCtl.index == 2 && _isManager) {
      _startManagerRefresh();
    } else {
      _managerRefreshTimer?.cancel();
    }
  }

  void _startManagerRefresh() {
    _managerRefreshTimer?.cancel();
    _managerRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_tabCtl.index == 2 && _isManager && mounted) {
        _refreshEmployeeLocations();
      }
    });
  }

  bool _isBranchAttendanceLocation(FieldLocation loc) {
    final category = (loc.category ?? '').toLowerCase();
    final name = loc.name.toLowerCase();
    final address = (loc.address ?? '').toLowerCase();
    if (category == 'branch_attendance' || category == 'work_location' || category == 'office_branch') {
      return true;
    }
    final text = '$name $address';
    return text.contains('chi nhanh cham cong') ||
        text.contains('chi nhánh chấm công') ||
        text.contains('branch attendance') ||
        text.contains('work location');
  }

  /// Radius (in metres) used to filter "Điểm bán hôm nay" and "Điểm bán đã đăng ký"
  /// on the Journey tab. Only locations within this distance from the current GPS
  /// position are shown, so the list reflects what the user can realistically
  /// check in to right now.
  static const double _kNearbyRadiusMeters = 200.0;

  List<FieldLocationAssignment> get _sortedAssignments {
    final list = List<FieldLocationAssignment>.from(_myAssignments);
    if (_currentLat == null || _currentLng == null) return list;
    // Annotate each assignment with its distance, filter by 200m, then sort by nearest.
    final withDist = <MapEntry<FieldLocationAssignment, double>>[];
    for (final a in list) {
      final loc = a.location;
      if (loc == null) continue;
      final d = _calculateDistance(
          _currentLat!, _currentLng!, loc.latitude, loc.longitude);
      if (d <= _kNearbyRadiusMeters) {
        withDist.add(MapEntry(a, d));
      }
    }
    withDist.sort((a, b) => a.value.compareTo(b.value));
    return withDist.map((e) => e.key).toList();
  }

  List<FieldLocation> _sortLocationsByDistance(List<FieldLocation> input) {
    final list = List<FieldLocation>.from(input);
    if (_currentLat == null || _currentLng == null) return list;
    list.sort((a, b) {
      final aDist = _calculateDistance(_currentLat!, _currentLng!, a.latitude, a.longitude);
      final bDist = _calculateDistance(_currentLat!, _currentLng!, b.latitude, b.longitude);
      return aDist.compareTo(bDist);
    });
    return list;
  }

  List<FieldLocation> get _visibleRegisteredLocations {
    final assignedIds = _myAssignments.map((a) => a.locationId).toSet();
    final filtered = _fieldLocations.where((loc) {
      if (_isBranchAttendanceLocation(loc)) return false;
      if (assignedIds.contains(loc.id)) return false;
      // Only show registered locations within the nearby radius; if GPS is not
      // yet available we still show them sorted by distance (legacy behaviour).
      if (_currentLat == null || _currentLng == null) return true;
      final d = _calculateDistance(
          _currentLat!, _currentLng!, loc.latitude, loc.longitude);
      return d <= _kNearbyRadiusMeters;
    }).toList();
    return _sortLocationsByDistance(filtered);
  }

  String _extractCustomerStatus(VisitReport v) {
    return (v.reportData?['customerStatus'] ?? '').toString().trim();
  }

  String _extractNextAction(VisitReport v) {
    return (v.reportData?['nextAction'] ?? '').toString().trim();
  }

  List<String> get _managerCustomerStatusOptions {
    final statuses = _reports
        .map(_extractCustomerStatus)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['Tất cả', ...statuses];
  }

  List<VisitReport> get _filteredManagerReports {
    if (_managerCustomerStatusFilter == 'Tất cả') return _reports;
    final selected = _managerCustomerStatusFilter.toLowerCase();
    return _reports.where((v) => _extractCustomerStatus(v).toLowerCase() == selected).toList();
  }

  List<VisitReport> get _weeklyManagerReports {
    final from = DateTime.now().subtract(const Duration(days: 7));
    return _reports.where((v) => v.visitDate.isAfter(from)).toList();
  }

  Future<void> _refreshEmployeeLocations() async {
    try {
      final resp = await _apiService.getEmployeeLocations();
      if (mounted && resp['isSuccess'] == true && resp['data'] != null) {
        setState(() {
          _employeeLocations = (resp['data'] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
        });
      }
    } catch (_) {}
  }

  // ========== DATA LOADING ==========

  Future<void> _loadMyData() async {
    setState(() => _isLoadingMyData = true);
    try {
      final results = await Future.wait([
        _apiService.getMyFieldAssignments(),
        _apiService.getTodayFieldVisits(),
        _apiService.getTodayJourney(),
        _apiService.getFieldLocations(),
      ]);

      if (mounted) {
        setState(() {
          if (results[0]['isSuccess'] == true && results[0]['data'] != null) {
            _myAssignments = (results[0]['data'] as List)
                .map((e) => FieldLocationAssignment.fromJson(e as Map<String, dynamic>))
                .toList();
          }
          if (results[1]['isSuccess'] == true && results[1]['data'] != null) {
            _todayVisits = (results[1]['data'] as List)
                .map((e) => VisitReport.fromJson(e as Map<String, dynamic>))
                .toList();
          }
          if (results[2]['isSuccess'] == true && results[2]['data'] != null) {
            _todayJourney = JourneyTracking.fromJson(results[2]['data'] as Map<String, dynamic>);
          }
          if (results[3]['isSuccess'] == true && results[3]['data'] != null) {
            _fieldLocations = (results[3]['data'] as List)
                .map((e) => FieldLocation.fromJson(e as Map<String, dynamic>))
                .toList();
          }
          _isLoadingMyData = false;
        });
        // If journey is active, start tracking
        if (_todayJourney?.isActive == true) {
          _startGpsTracking();
        } else if (_todayJourney == null || _todayJourney!.isNotStarted) {
          // Auto-start journey when opening screen
          _autoStartJourney();
        }
        _initGps();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMyData = false);
    }
  }

  /// Tự động bắt đầu hành trình khi mở màn hình (không cần bấm nút)
  Future<void> _autoStartJourney() async {
    try {
      final resp = await _apiService.startJourney();
      if (mounted && resp['isSuccess'] == true && resp['data'] != null) {
        setState(() => _todayJourney = JourneyTracking.fromJson(resp['data'] as Map<String, dynamic>));
        _startGpsTracking();
      }
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final futures = <Future<Map<String, dynamic>>>[
        _isManager
            ? _apiService.getFieldReports(
                fromDate: _historyFrom,
                toDate: _historyTo,
                employeeId: _historyEmployeeFilter,
              )
            : _apiService.getMyFieldVisits(fromDate: _historyFrom, toDate: _historyTo),
        _apiService.getJourneyReports(
          fromDate: _historyFrom,
          toDate: _historyTo,
          employeeId: _historyEmployeeFilter,
        ),
      ];
      final results = await Future.wait(futures);
      if (mounted) {
        setState(() {
          if (results[0]['isSuccess'] == true && results[0]['data'] != null) {
            final data = results[0]['data'];
            final list = data is List ? data : (data['items'] as List?) ?? [];
            _historyVisits = list
                .map((e) => VisitReport.fromJson(e as Map<String, dynamic>))
                .toList();
          }
          if (results[1]['isSuccess'] == true && results[1]['data'] != null) {
            _journeyHistory = (results[1]['data'] as List)
                .map((e) => JourneyTracking.fromJson(e as Map<String, dynamic>))
                .toList();
          }
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _loadManagerData() async {
    setState(() => _isLoadingManager = true);
    try {
      final results = await Future.wait([
        _apiService.getFieldReports(fromDate: _reportFrom, toDate: _reportTo),
        _apiService.getFieldAssignments(),
        _apiService.getFieldLocations(),
        _apiService.getJourneyReports(fromDate: _reportFrom, toDate: _reportTo),
        _apiService.getActiveJourneys(),
        _apiService.getEmployeeLocations(),
      ]);

      if (mounted) {
        setState(() {
          if (results[0]['isSuccess'] == true && results[0]['data'] != null) {
            final data = results[0]['data'];
            final list = data is List ? data : (data['items'] as List?) ?? [];
            _reports = list
                .map((e) => VisitReport.fromJson(e as Map<String, dynamic>))
                .toList();
          }
          if (results[1]['isSuccess'] == true && results[1]['data'] != null) {
            _allAssignments = (results[1]['data'] as List)
                .map((e) => FieldLocationAssignment.fromJson(e as Map<String, dynamic>))
                .toList();
          }
          if (results[2]['isSuccess'] == true && results[2]['data'] != null) {
            _locations = (results[2]['data'] as List)
                .map((e) => e as Map<String, dynamic>)
                .toList();
          }
          if (results[3]['isSuccess'] == true && results[3]['data'] != null) {
            _managerJourneys = (results[3]['data'] as List)
                .map((e) => JourneyTracking.fromJson(e as Map<String, dynamic>))
                .toList();
          }
          if (results[4]['isSuccess'] == true && results[4]['data'] != null) {
            _activeJourneys = (results[4]['data'] as List)
                .map((e) => e as Map<String, dynamic>)
                .toList();
          }
          if (results[5]['isSuccess'] == true && results[5]['data'] != null) {
            _employeeLocations = (results[5]['data'] as List)
                .map((e) => e as Map<String, dynamic>)
                .toList();
          }
          _isLoadingManager = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingManager = false);
    }
  }

  // ========== GPS ==========

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  /// Compress image to max ~500KB JPEG for upload
  List<int> _compressImage(List<int> bytes) {
    try {
      // If already small enough, return as-is
      if (bytes.length <= 500 * 1024) return bytes;
      final decoded = img.decodeImage(bytes as dynamic);
      if (decoded == null) return bytes;
      // Resize if too large
      var image = decoded;
      if (image.width > 1280 || image.height > 1280) {
        image = img.copyResize(image, width: 1280);
      }
      // Encode as JPEG with quality reduction
      var quality = 70;
      var result = img.encodeJpg(image, quality: quality);
      while (result.length > 500 * 1024 && quality > 20) {
        quality -= 15;
        result = img.encodeJpg(image, quality: quality);
      }
      return result;
    } catch (_) {
      return bytes;
    }
  }

  Future<void> _initGps() async {
    try {
      if (!kIsWeb) await ensureLocationPermission();
      final pos = await getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLat = pos.latitude;
          _currentLng = pos.longitude;
        });
        _mapController.move(LatLng(pos.latitude, pos.longitude), 14);
      }
    } catch (_) {}
  }

  Future<bool> _getLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      if (!kIsWeb) await ensureLocationPermission();
      final pos = await getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLat = pos.latitude;
          _currentLng = pos.longitude;
        });
      }
      if (mounted) setState(() => _isGettingLocation = false);
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _isGettingLocation = false);
        NotificationOverlayManager().showWarning(
          title: 'Lỗi GPS',
          message: 'Không lấy được vị trí. Vui lòng bật GPS.',
        );
      }
      return false;
    }
  }

  void _startGpsTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_todayJourney?.isActive != true) {
        _trackingTimer?.cancel();
        return;
      }
      try {
        if (!kIsWeb) await ensureLocationPermission();
        final pos = await getCurrentPosition();
        if (mounted) {
          setState(() {
            _currentLat = pos.latitude;
            _currentLng = pos.longitude;
          });
          // Skip if within 50m of last tracked point
          if (_lastTrackedLat != null && _lastTrackedLng != null) {
            final dist = _calculateDistance(_lastTrackedLat!, _lastTrackedLng!, pos.latitude, pos.longitude);
            if (dist < 50) return;
          }
          _lastTrackedLat = pos.latitude;
          _lastTrackedLng = pos.longitude;
          _pendingTrackPoints.add({
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });
          // Persist pending points in case of crash
          _savePendingPoints();
          // Batch send every ~60s (2 points)
          if (_pendingTrackPoints.length >= 2) {
            final pts = List<Map<String, dynamic>>.from(_pendingTrackPoints);
            _pendingTrackPoints.clear();
            _savePendingPoints();
            final resp = await _apiService.trackJourneyPoints(pts);
            if (resp['isSuccess'] == true && resp['data'] != null) {
              setState(() {
                _todayJourney = JourneyTracking(
                  id: _todayJourney!.id,
                  journeyDate: _todayJourney!.journeyDate,
                  startTime: _todayJourney!.startTime,
                  endTime: _todayJourney!.endTime,
                  status: _todayJourney!.status,
                  totalDistanceKm: (resp['data']['totalDistanceKm'] as num?)?.toDouble() ?? _todayJourney!.totalDistanceKm,
                  totalTravelMinutes: resp['data']['totalTravelMinutes'] ?? _todayJourney!.totalTravelMinutes,
                  totalOnSiteMinutes: resp['data']['totalOnSiteMinutes'] ?? _todayJourney!.totalOnSiteMinutes,
                  checkedInCount: resp['data']['checkedInCount'] ?? _todayJourney!.checkedInCount,
                  assignedCount: _todayJourney!.assignedCount,
                  routePoints: _todayJourney!.routePoints,
                );
              });
            }
          }
        }
      } catch (_) {}
    });
  }

  void _stopGpsTracking() {
    _trackingTimer?.cancel();
  }

  /// Gửi vị trí GPS hiện tại lên server mỗi 60 giây (không phụ thuộc hành trình)
  void _startLocationReporting() {
    _locationReportTimer?.cancel();
    // Report immediately on open
    _reportCurrentLocation();
    _locationReportTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _reportCurrentLocation();
    });
  }

  Future<void> _reportCurrentLocation() async {
    try {
      if (!kIsWeb) await ensureLocationPermission();
      final pos = await getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLat = pos.latitude;
          _currentLng = pos.longitude;
        });
      }
      await _apiService.reportLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
      );
    } catch (_) {}
  }

  // ========== JOURNEY ACTIONS ==========

  // ignore: unused_element
  Future<void> _startJourney() async {
    final resp = await _apiService.startJourney();
    if (!mounted) return;
    if (resp['isSuccess'] == true && resp['data'] != null) {
      setState(() => _todayJourney = JourneyTracking.fromJson(resp['data'] as Map<String, dynamic>));
      _startGpsTracking();
      NotificationOverlayManager().showSuccess(
        title: 'Bắt đầu hành trình',
        message: 'Đang theo dõi lộ trình. Bắt đầu check-in tại các điểm.',
      );
    } else {
      NotificationOverlayManager().showWarning(title: 'Lỗi', message: resp['message'] ?? 'Lỗi');
    }
  }

  // ignore: unused_element
  Future<void> _endJourney() async {
    // Flush pending points
    if (_pendingTrackPoints.isNotEmpty) {
      await _apiService.trackJourneyPoints(List<Map<String, dynamic>>.from(_pendingTrackPoints));
      _pendingTrackPoints.clear();
      _savePendingPoints();
    }

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kết thúc hành trình?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_todayJourney != null) ...[
              Text('Đã di chuyển: ${_todayJourney!.distanceFormatted}'),
              Text('Đã check-in: ${_todayJourney!.checkedInCount}/${_todayJourney!.assignedCount} điểm'),
            ],
            const SizedBox(height: 8),
            const Text('Bạn có muốn kết thúc hành trình hôm nay?'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kết thúc')),
        ],
      ),
    );
    if (confirm != true) return;

    _stopGpsTracking();
    final resp = await _apiService.endJourney();
    if (!mounted) return;
    if (resp['isSuccess'] == true) {
      setState(() {
        if (resp['data'] != null) {
          _todayJourney = JourneyTracking.fromJson(resp['data'] as Map<String, dynamic>);
        }
      });
      NotificationOverlayManager().showSuccess(
        title: 'Kết thúc hành trình',
        message: 'Hành trình đã kết thúc. ${_todayJourney?.distanceFormatted ?? ""} • ${_todayJourney?.checkedInCount ?? 0} điểm.',
      );
    } else {
      NotificationOverlayManager().showWarning(
        title: 'Lỗi kết thúc',
        message: resp['message'] ?? 'Không thể kết thúc hành trình',
      );
    }
  }

  // ========== CHECK-IN / CHECK-OUT ==========

  Future<void> _doCheckIn(FieldLocationAssignment assignment) async {
    final gotGps = await _getLocation();
    if (!mounted || !gotGps || _currentLat == null) return;

    double? distanceMeters;
    bool isOutsideRadius = false;
    final loc = assignment.location;
    if (loc != null) {
      distanceMeters = _calculateDistance(_currentLat!, _currentLng!, loc.latitude, loc.longitude);
      isOutsideRadius = distanceMeters > loc.radius;
    }

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF1E3A5F).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.store, color: Color(0xFF1E3A5F), size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(loc?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    if (loc?.address != null)
                      Text(loc!.address!, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Distance
            if (distanceMeters != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isOutsideRadius ? const Color(0xFFFEE2E2) : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(
                    isOutsideRadius ? Icons.warning_amber_rounded : Icons.check_circle,
                    color: isOutsideRadius ? const Color(0xFFEF4444) : const Color(0xFF059669),
                  ),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      distanceMeters < 1000
                          ? '${distanceMeters.toStringAsFixed(0)}m'
                          : '${(distanceMeters / 1000).toStringAsFixed(2)}km',
                      style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18,
                        color: isOutsideRadius ? const Color(0xFFEF4444) : const Color(0xFF059669),
                      ),
                    ),
                    if (isOutsideRadius)
                      Text('Ngoài bán kính ${loc?.radius ?? 100}m', style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
                  ]),
                ]),
              ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.login),
                  label: const Text('Check-in'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ]),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    final resp = await _apiService.fieldCheckIn({
      'locationId': assignment.locationId,
      'employeeName': _employeeName,
      'latitude': _currentLat,
      'longitude': _currentLng,
    });

    if (!mounted) return;
    if (resp['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Check-in', message: 'Thành công tại ${assignment.location?.name}');
      _loadMyData();
    } else {
      NotificationOverlayManager().showWarning(title: 'Lỗi', message: resp['message'] ?? 'Lỗi check-in');
    }
  }

  Future<void> _doCheckInAtFieldLocation(FieldLocation loc) async {
    final gotGps = await _getLocation();
    if (!mounted || !gotGps || _currentLat == null) return;

    final distanceMeters = _calculateDistance(_currentLat!, _currentLng!, loc.latitude, loc.longitude);
    final isOutsideRadius = distanceMeters > loc.radius;

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.storefront, color: Color(0xFF6366F1), size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(loc.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    if (loc.address != null)
                      Text(loc.address!, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isOutsideRadius ? const Color(0xFFFEE2E2) : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(
                  isOutsideRadius ? Icons.warning_amber_rounded : Icons.check_circle,
                  color: isOutsideRadius ? const Color(0xFFEF4444) : const Color(0xFF059669),
                ),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    distanceMeters < 1000
                        ? '${distanceMeters.toStringAsFixed(0)}m'
                        : '${(distanceMeters / 1000).toStringAsFixed(2)}km',
                    style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18,
                      color: isOutsideRadius ? const Color(0xFFEF4444) : const Color(0xFF059669),
                    ),
                  ),
                  if (isOutsideRadius)
                    Text('Ngoài bán kính ${loc.radius}m', style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.login),
                  label: const Text('Check-in'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1), padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ]),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    final resp = await _apiService.fieldCheckIn({
      'locationId': loc.id,
      'employeeName': _employeeName,
      'latitude': _currentLat,
      'longitude': _currentLng,
    });

    if (!mounted) return;
    if (resp['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Check-in', message: 'Thành công tại ${loc.name}');
      _loadMyData();
    } else {
      NotificationOverlayManager().showWarning(title: 'Lỗi', message: resp['message'] ?? 'Lỗi check-in');
    }
  }

  Future<void> _doCheckOut(VisitReport visit) async {
    final gotGps = await _getLocation();
    if (!mounted || !gotGps || _currentLat == null) return;

    final noteCtl = TextEditingController(text: visit.reportNote);
    final meetingSummaryCtl = TextEditingController(text: (visit.reportData?['meetingSummary'] ?? '').toString());
    final customerStatusCtl = TextEditingController(text: (visit.reportData?['customerStatus'] ?? '').toString());
    final nextActionCtl = TextEditingController(text: (visit.reportData?['nextAction'] ?? '').toString());
    final List<XFile> selectedPhotos = [];
    final picker = ImagePicker();

    // Build suggestions from past visits (same location first, then any other past report by this user)
    List<String> collectSuggestions(String Function(VisitReport v) pick) {
      final pool = <VisitReport>[
        ..._historyVisits.where((v) => v.locationId == visit.locationId),
        ..._todayVisits.where((v) => v.id != visit.id && v.locationId == visit.locationId),
        ..._historyVisits.where((v) => v.locationId != visit.locationId),
      ];
      final seen = <String>{};
      final result = <String>[];
      for (final v in pool) {
        final s = pick(v).trim();
        if (s.isEmpty) continue;
        final key = s.toLowerCase();
        if (seen.add(key)) result.add(s);
        if (result.length >= 5) break;
      }
      return result;
    }

    final noteSuggestions = collectSuggestions((v) => v.reportNote ?? '');
    final meetingSuggestions = collectSuggestions((v) => (v.reportData?['meetingSummary'] ?? '').toString());
    final statusSuggestions = collectSuggestions((v) => (v.reportData?['customerStatus'] ?? '').toString());
    final nextSuggestions = collectSuggestions((v) => (v.reportData?['nextAction'] ?? '').toString());

    Widget suggestionChips(List<String> items, TextEditingController ctl, StateSetter setDialogState) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) => ActionChip(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.06),
              side: BorderSide(color: const Color(0xFF1E3A5F).withValues(alpha: 0.25)),
              avatar: Icon(Icons.history, size: 14, color: Colors.grey[700]),
              label: Text(
                items[i].length > 40 ? '${items[i].substring(0, 40)}…' : items[i],
                style: const TextStyle(fontSize: 11),
              ),
              onPressed: () {
                ctl.text = items[i];
                ctl.selection = TextSelection.fromPosition(TextPosition(offset: ctl.text.length));
                setDialogState(() {});
              },
            ),
          ),
        ),
      );
    }

    bool showMore = meetingSummaryCtl.text.isNotEmpty ||
        customerStatusCtl.text.isNotEmpty ||
        nextActionCtl.text.isNotEmpty;

    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.logout, color: Colors.orange, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(visit.locationName ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      if (visit.checkInTime != null)
                        Text('Check-in lúc: ${DateFormat('HH:mm').format(visit.checkInTime!.toLocal())}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    ])),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(Icons.tips_and_updates, size: 14, color: Colors.blue[700]),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      'Các trường đều không bắt buộc. Bấm gợi ý để điền nhanh từ lần trước.',
                      style: TextStyle(fontSize: 11, color: Colors.blue[800]),
                    )),
                  ]),
                ),
                const SizedBox(height: 12),
                // Primary field: short note
                TextField(
                  controller: noteCtl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú nhanh',
                    hintText: 'Tóm tắt 1 dòng...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                suggestionChips(noteSuggestions, noteCtl, setDialogState),
                const SizedBox(height: 10),
                // Photos (optional)
                Row(children: [
                  const Icon(Icons.photo_camera, size: 16, color: Color(0xFF1E3A5F)),
                  const SizedBox(width: 6),
                  Text('Ảnh (${selectedPhotos.length}/5) — tuỳ chọn', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  const Spacer(),
                  if (selectedPhotos.length < 5) ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.camera_alt), onPressed: () async {
                      final p = await picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1280);
                      if (p != null) setDialogState(() => selectedPhotos.add(p));
                    }),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.photo_library), onPressed: () async {
                      final ps = await picker.pickMultiImage(imageQuality: 70, maxWidth: 1280);
                      setDialogState(() => selectedPhotos.addAll(ps.take(5 - selectedPhotos.length)));
                    }),
                  ],
                ]),
                if (selectedPhotos.isNotEmpty)
                  SizedBox(
                    height: 72,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedPhotos.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: FutureBuilder<List<int>>(
                              future: selectedPhotos[i].readAsBytes(),
                              builder: (_, snap) => snap.hasData
                                  ? Image.memory(snap.data! as dynamic, width: 72, height: 72, fit: BoxFit.cover)
                                  : const SizedBox(width: 72, height: 72, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                            ),
                          ),
                          Positioned(top: 0, right: 0, child: GestureDetector(
                            onTap: () => setDialogState(() => selectedPhotos.removeAt(i)),
                            child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 12, color: Colors.white)),
                          )),
                        ]),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                // Collapsible "more fields" section
                InkWell(
                  onTap: () => setDialogState(() => showMore = !showMore),
                  child: Row(children: [
                    Icon(showMore ? Icons.expand_less : Icons.expand_more, size: 20, color: const Color(0xFF1E3A5F)),
                    const SizedBox(width: 4),
                    Text(
                      showMore ? 'Thu gọn báo cáo chi tiết' : 'Báo cáo chi tiết (tuỳ chọn)',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
                if (showMore) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: meetingSummaryCtl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Tình hình gặp khách',
                      hintText: 'VD: Khách quan tâm sản phẩm A',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  suggestionChips(meetingSuggestions, meetingSummaryCtl, setDialogState),
                  const SizedBox(height: 8),
                  TextField(
                    controller: customerStatusCtl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Kết quả chăm sóc',
                      hintText: 'VD: Đã demo, đồng ý test 7 ngày',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  suggestionChips(statusSuggestions, customerStatusCtl, setDialogState),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nextActionCtl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Hành động tiếp theo',
                      hintText: 'VD: Hẹn gặp thứ 5 để chốt đơn',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  suggestionChips(nextSuggestions, nextActionCtl, setDialogState),
                ],
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ'))),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx, {
                          'note': noteCtl.text.trim(),
                          'meetingSummary': meetingSummaryCtl.text.trim(),
                          'customerStatus': customerStatusCtl.text.trim(),
                          'nextAction': nextActionCtl.text.trim(),
                        });
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Check-out'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                ]),
              ],
            )),
          ),
        ),
      ),
    );

    if (result == null) return;

    final List<String> photoBase64 = [];
    for (final photo in selectedPhotos) {
      final bytes = await photo.readAsBytes();
      photoBase64.add(base64Encode(_compressImage(bytes)));
    }

    final resp = await _apiService.fieldCheckOut(visit.id, {
      'latitude': _currentLat,
      'longitude': _currentLng,
      'note': result['note'],
      'reportDataJson': jsonEncode({
        'meetingSummary': (result['meetingSummary'] ?? '').toString().trim(),
        'customerStatus': (result['customerStatus'] ?? '').toString().trim(),
        'nextAction': (result['nextAction'] ?? '').toString().trim(),
        'submittedAt': DateTime.now().toIso8601String(),
      }),
      if (photoBase64.isNotEmpty) 'photos': photoBase64,
    });

    if (!mounted) return;
    if (resp['isSuccess'] == true) {
      final mins = resp['data']?['timeSpentMinutes'];
      NotificationOverlayManager().showSuccess(title: 'Check-out',
          message: 'Thành công${mins != null ? " - $mins phút" : ""}');
      _loadMyData();
    } else {
      NotificationOverlayManager().showWarning(title: 'Lỗi', message: resp['message'] ?? 'Lỗi');
    }
  }

  Future<void> _showVisitDetailSheet(VisitReport visit) async {
    final meetingSummary = (visit.reportData?['meetingSummary'] ?? '').toString().trim();
    final customerStatus = (visit.reportData?['customerStatus'] ?? '').toString().trim();
    final nextAction = (visit.reportData?['nextAction'] ?? '').toString().trim();

    Widget reportField(IconData icon, String label, String value) {
      if (value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: const Color(0xFF1E3A5F)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ]),
      );
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Row(children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                child: const Icon(Icons.store, color: Color(0xFF1E3A5F)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(visit.locationName ?? 'Điểm bán', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                if (visit.employeeName != null)
                  Text(visit.employeeName!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ])),
              _buildStatusChip(visit.status),
            ]),
            const SizedBox(height: 12),
            // Times
            Wrap(spacing: 12, runSpacing: 6, children: [
              if (visit.checkInTime != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.login, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Text('Check-in: ${DateFormat('dd/MM HH:mm').format(visit.checkInTime!.toLocal())}', style: const TextStyle(fontSize: 12)),
                ]),
              if (visit.checkOutTime != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.logout, size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text('Check-out: ${DateFormat('dd/MM HH:mm').format(visit.checkOutTime!.toLocal())}', style: const TextStyle(fontSize: 12)),
                ]),
              if (visit.timeSpentMinutes != null && visit.timeSpentMinutes! > 0)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.timer, size: 14, color: Color(0xFF1E3A5F)),
                  const SizedBox(width: 4),
                  Text('Thời gian: ${visit.timeSpentFormatted}', style: const TextStyle(fontSize: 12)),
                ]),
            ]),
            const Divider(height: 22),
            if (meetingSummary.isEmpty && customerStatus.isEmpty && nextAction.isEmpty && (visit.reportNote == null || visit.reportNote!.isEmpty) && visit.photos.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Column(children: [
                  Icon(Icons.note_alt_outlined, size: 40, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text('Chưa có báo cáo cho lượt này', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ])),
              )
            else ...[
              if (visit.reportNote != null && visit.reportNote!.isNotEmpty)
                reportField(Icons.notes, 'Ghi chú', visit.reportNote!),
              reportField(Icons.handshake, 'Tình hình gặp khách', meetingSummary),
              reportField(Icons.task_alt, 'Kết quả chăm sóc', customerStatus),
              reportField(Icons.arrow_forward, 'Hành động tiếp theo', nextAction),
              if (visit.photos.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.photo_library, size: 14, color: Color(0xFF1E3A5F)),
                  const SizedBox(width: 6),
                  Text('Ảnh (${visit.photos.length})', style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 6),
                SizedBox(
                  height: 90,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: visit.photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final url = visit.photos[i];
                      return GestureDetector(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: Colors.black,
                            insetPadding: const EdgeInsets.all(12),
                            child: InteractiveViewer(
                              child: Image.network(url, fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white, size: 60)),
                            ),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(url, width: 90, height: 90, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 90, height: 90, color: Colors.grey[200],
                              child: Icon(Icons.broken_image, color: Colors.grey[400]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
            ),
          ],
        )),
      ),
    );
  }

  Future<void> _reviewVisit(VisitReport visit) async {
    final noteCtl = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duyệt báo cáo'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Colors.teal.shade50,
                child: Text((visit.employeeName ?? '?')[0].toUpperCase(),
                    style: TextStyle(color: Colors.teal[700], fontWeight: FontWeight.bold)),
              ),
              title: Text(visit.employeeName ?? ''),
              subtitle: Text('${visit.locationName ?? ""} • ${visit.timeSpentFormatted}'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Nhận xét', border: OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, noteCtl.text), child: const Text('Duyệt')),
        ],
      ),
    );
    if (result == null) return;

    final resp = await _apiService.reviewFieldVisit(visit.id, {'reviewNote': result});
    if (!mounted) return;
    if (resp['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Duyệt', message: 'Đã duyệt');
      _loadManagerData();
    }
  }

  // ========== BUILD ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Tab bar header
          Container(
            color: const Color(0xFF1E3A5F),
            child: SafeArea(
              bottom: false,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(children: [
                    const Icon(Icons.route, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    const Text('Check-in điểm bán', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                    const Spacer(),
                    if (_todayJourney?.isActive == true)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text('LIVE • ${_todayJourney?.distanceFormatted ?? ""}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                  ]),
                ),
                TabBar(
                  controller: _tabCtl,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  tabs: [
                    const Tab(text: 'Hành trình'),
                    const Tab(text: 'Lịch sử'),
                    if (_isManager) const Tab(text: 'Quản lý'),
                  ],
                ),
              ]),
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabCtl,
              children: [
                _buildJourneyTab(),
                _buildHistoryTab(),
                if (_isManager) _buildManagerTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 1: JOURNEY (MAP + BOTTOM SHEET) ====================

  Widget _buildJourneyTab() {
    if (_isLoadingMyData) return const Center(child: CircularProgressIndicator());

    return Stack(
      children: [
        // Map
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentLat != null
                ? LatLng(_currentLat!, _currentLng!)
                : const LatLng(16.0544, 108.2022), // Default Da Nang
            initialZoom: 14,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.zktecoadms.app',
            ),
            // Check-in route polyline (connects check-in points in chronological order)
            if (() {
              final pts = _todayVisits
                  .where((v) => v.checkInLatitude != null && v.checkInLongitude != null && v.checkInTime != null)
                  .length;
              return pts >= 2;
            }())
              PolylineLayer(polylines: [
                Polyline(
                  points: (_todayVisits
                      .where((v) => v.checkInLatitude != null && v.checkInLongitude != null && v.checkInTime != null)
                      .toList()
                        ..sort((a, b) => a.checkInTime!.compareTo(b.checkInTime!)))
                      .map((v) => LatLng(v.checkInLatitude!, v.checkInLongitude!))
                      .toList(),
                  color: const Color(0xFF1E3A5F),
                  strokeWidth: 4,
                ),
              ]),
            // Location markers
            MarkerLayer(markers: [
              // Check-in point markers (with name + time label, numbered by chronological order)
              ...() {
                final sorted = _todayVisits
                    .where((v) => v.checkInLatitude != null && v.checkInLongitude != null && v.checkInTime != null)
                    .toList()
                  ..sort((a, b) => a.checkInTime!.compareTo(b.checkInTime!));
                return sorted.asMap().entries.map((e) {
                  final idx = e.key;
                  final v = e.value;
                  final label = '${v.locationName ?? "Điểm"} · ${DateFormat('HH:mm').format(v.checkInTime!.toLocal())}';
                  return Marker(
                    point: LatLng(v.checkInLatitude!, v.checkInLongitude!),
                    width: 140,
                    height: 48,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF1E3A5F), width: 1),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 3)],
                          ),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF1E3A5F)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3A5F),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 3)],
                          ),
                          child: Center(
                            child: Text(
                              '${idx + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList();
              }(),
              // Current position
              if (_currentLat != null)
                Marker(
                  point: LatLng(_currentLat!, _currentLng!),
                  width: 36,
                  height: 36,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 4)],
                    ),
                    child: const Icon(Icons.navigation, color: Colors.white, size: 16),
                  ),
                ),
              // Assignment location pins
              ..._sortedAssignments.where((a) => a.location != null).map((a) {
                final activeVisit = _todayVisits.where((v) => v.locationId == a.locationId && v.isCheckedIn).firstOrNull;
                final visited = _todayVisits.any((v) => v.locationId == a.locationId && v.checkOutTime != null);
                return Marker(
                  point: LatLng(a.location!.latitude, a.location!.longitude),
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () {
                      if (activeVisit != null) {
                        _doCheckOut(activeVisit);
                      } else {
                        _doCheckIn(a);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: activeVisit != null
                            ? Colors.orange
                            : visited
                                ? const Color(0xFF22C55E)
                                : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: activeVisit != null
                              ? Colors.orange.shade700
                              : visited
                                  ? const Color(0xFF059669)
                                  : const Color(0xFF1E3A5F),
                          width: 2,
                        ),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
                      ),
                      child: Center(
                        child: Icon(
                          activeVisit != null
                              ? Icons.radio_button_checked
                              : visited
                                  ? Icons.check
                                  : Icons.store,
                          color: activeVisit != null || visited ? Colors.white : const Color(0xFF1E3A5F),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              // Field location pins (registered by employees) - hidden: only assigned locations shown on map
            ]),
          ],
        ),

        // Journey stats bar (top)
        if (_todayJourney != null && (_todayJourney!.isActive || _todayJourney!.isCompleted) && _todayJourney!.routePoints.isNotEmpty)
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildJourneyStat(Icons.route, _todayJourney!.distanceFormatted, 'Quãng đường'),
                  Container(width: 1, height: 30, color: Colors.grey[300]),
                  _buildJourneyStat(Icons.timer, _todayJourney!.durationFormatted, 'Thời gian'),
                  Container(width: 1, height: 30, color: Colors.grey[300]),
                  _buildJourneyStat(Icons.location_on, '${_todayJourney!.checkedInCount}/${_todayJourney!.assignedCount}', 'Điểm'),
                ],
              ),
            ),
          ),

        // My location button
        Positioned(
          right: 12,
          bottom: _myAssignments.isEmpty ? 100 : 320,
          child: FloatingActionButton.small(
            heroTag: 'my_loc',
            onPressed: () {
              if (_currentLat != null) {
                _mapController.move(LatLng(_currentLat!, _currentLng!), 15);
              }
            },
            backgroundColor: Colors.white,
            child: const Icon(Icons.my_location, color: Color(0xFF1E3A5F)),
          ),
        ),

        // Fit all markers button
        if (_myAssignments.isNotEmpty)
          Positioned(
            right: 12,
            bottom: _myAssignments.isEmpty ? 150 : 370,
            child: FloatingActionButton.small(
              heroTag: 'fit_all',
              onPressed: _fitAllMarkers,
              backgroundColor: Colors.white,
              child: const Icon(Icons.zoom_out_map, color: Color(0xFF1E3A5F)),
            ),
          ),

        // Bottom sheet with location list
        DraggableScrollableSheet(
          initialChildSize: 0.35,
          minChildSize: 0.12,
          maxChildSize: 0.75,
          controller: _sheetCtl,
          builder: (ctx, scrollController) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
            ),
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.zero,
              children: [
                // Handle
                Center(child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                )),

                // Journey control button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: _buildJourneyButton(),
                ),

                // Dwell summary (when route has dwell points)
                if (_todayJourney != null && _todayJourney!.routePoints.any((p) => p.isDwell))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.place, size: 16, color: Colors.orange),
                            SizedBox(width: 6),
                            Text('Các điểm dừng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange)),
                          ]),
                          const SizedBox(height: 8),
                          ..._todayJourney!.routePoints.where((p) => p.isDwell).map((p) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              Container(
                                width: 6, height: 6,
                                decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(
                                p.nearLocationName ?? 'Vị trí (${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)})',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              )),
                              Text(
                                p.dwellMinutes! >= 60
                                    ? '${p.dwellMinutes! ~/ 60}h${p.dwellMinutes! % 60}p'
                                    : '${p.dwellMinutes}p',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('HH:mm').format(p.time.toLocal()),
                                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                              ),
                            ]),
                          )),
                        ],
                      ),
                    ),
                  ),

                const Divider(height: 16),

                // Location cards
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Điểm bán hôm nay trong 200m (${_sortedAssignments.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF18181B)),
                  ),
                ),
                const SizedBox(height: 8),

                if (_sortedAssignments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(children: [
                      Icon(Icons.location_off, size: 40, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Text(
                        _currentLat == null
                            ? 'Đang xác định vị trí...'
                            : 'Không có điểm bán nào trong bán kính 200m',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ]),
                  )
                else
                  ..._sortedAssignments.map((a) => _buildLocationCard(a)),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Field Locations header + register button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(child: Text(
                      'Điểm bán đã đăng ký trong 200m (${_visibleRegisteredLocations.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF18181B)),
                    )),
                    SizedBox(
                      height: 32,
                      child: FilledButton.icon(
                        onPressed: _showRegisterLocationDialog,
                        icon: const Icon(Icons.add_location_alt, size: 16),
                        label: const Text('Đăng ký', style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A5F),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: Size.zero,
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),

                // Search bar for field locations
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _locationSearchCtl,
                    decoration: InputDecoration(
                      hintText: 'Tìm theo tên, địa chỉ, SĐT...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _locationSearchCtl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _locationSearchCtl.clear();
                                setState(() {
                                  _isSearching = false;
                                  _searchResults = [];
                                });
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: _onSearchFieldLocations,
                  ),
                ),
                const SizedBox(height: 8),

                if (_isSearching && _searchResults.isEmpty && _locationSearchCtl.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      Icon(Icons.search_off, size: 36, color: Colors.grey[300]),
                      const SizedBox(height: 6),
                      Text('Không tìm thấy điểm bán', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                    ]),
                  )
                else if (_visibleRegisteredLocations.isEmpty && !_isSearching)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      Icon(Icons.storefront, size: 36, color: Colors.grey[300]),
                      const SizedBox(height: 6),
                      Text('Chưa đăng ký điểm bán nào', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _showRegisterLocationDialog,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Đăng ký điểm bán mới'),
                      ),
                    ]),
                  )
                else
                  ...(_isSearching ? _sortLocationsByDistance(_searchResults.where((loc) => !_isBranchAttendanceLocation(loc)).toList()) : _visibleRegisteredLocations)
                      .map((loc) => _buildFieldLocationCard(loc)),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _onSearchFieldLocations(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }
    setState(() => _isSearching = true);
    try {
      final resp = await _apiService.getFieldLocations(search: query.trim());
      if (_locationSearchCtl.text.trim() == query.trim() && resp['isSuccess'] == true && resp['data'] != null) {
        final list = (resp['data'] as List)
            .map((e) => FieldLocation.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() => _searchResults = list);
      }
    } catch (_) {}
  }

  void _fitAllMarkers() {
    final points = <LatLng>[];
    if (_currentLat != null) points.add(LatLng(_currentLat!, _currentLng!));
    for (final a in _sortedAssignments) {
      if (a.location != null) points.add(LatLng(a.location!.latitude, a.location!.longitude));
    }
    for (final loc in _visibleRegisteredLocations) {
      points.add(LatLng(loc.latitude, loc.longitude));
    }
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 15);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)));
  }

  Widget _buildJourneyStat(IconData icon, String value, String label) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: const Color(0xFF1E3A5F)),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A5F))),
      ]),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
    ]);
  }

  Widget _buildJourneyButton() {
    if (_todayJourney == null || _todayJourney!.isNotStarted) {
      // Auto-starting, show loading indicator
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF22C55E))),
            SizedBox(width: 10),
            Text('Đang kết nối theo dõi...', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF22C55E))),
          ],
        ),
      );
    }

    // Active or completed — show tracking status (no end button)
    final isActive = _todayJourney!.isActive;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? const Color(0xFF22C55E).withValues(alpha: 0.3) : const Color(0xFF1E3A5F).withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF22C55E) : const Color(0xFF1E3A5F),
            shape: BoxShape.circle,
            boxShadow: isActive ? [BoxShadow(color: const Color(0xFF22C55E).withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 2)] : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isActive ? 'Hành trình đang hoạt động' : 'Hành trình đã hoàn thành',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isActive ? const Color(0xFF22C55E) : const Color(0xFF1E3A5F)),
            ),
          ],
        )),
        if (isActive)
          const Icon(Icons.gps_fixed, color: Color(0xFF22C55E), size: 20),
      ]),
    );
  }

  Widget _buildLocationCard(FieldLocationAssignment a) {
    final todayVisit = _todayVisits.where((v) => v.locationId == a.locationId).toList();
    final activeVisit = todayVisit.where((v) => v.isCheckedIn).firstOrNull;

    double? distance;
    if (_currentLat != null && a.location != null) {
      distance = _calculateDistance(_currentLat!, _currentLng!, a.location!.latitude, a.location!.longitude);
    }

    Color accentColor;
    IconData statusIcon;
    String statusLabel;
    if (activeVisit != null) {
      accentColor = Colors.orange;
      statusIcon = Icons.radio_button_checked;
      statusLabel = 'Đang ở điểm';
    } else {
      accentColor = const Color(0xFF71717A);
      statusIcon = Icons.radio_button_unchecked;
      statusLabel = distance != null
          ? (distance < 1000 ? '${distance.toStringAsFixed(0)}m' : '${(distance / 1000).toStringAsFixed(1)}km')
          : 'Chưa check-in';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: activeVisit != null ? 0.5 : 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.store, color: accentColor, size: 22),
        ),
        title: Text(a.location?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Row(children: [
          Icon(statusIcon, size: 12, color: accentColor),
          const SizedBox(width: 4),
          Text(statusLabel, style: TextStyle(fontSize: 12, color: accentColor, fontWeight: FontWeight.w500)),
          if (activeVisit?.checkInTime != null) ...[
            const SizedBox(width: 6),
            Text('• ${DateFormat('HH:mm').format(activeVisit!.checkInTime!.toLocal())}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ]),
        trailing: activeVisit != null
            ? _actionButton('Check-out', Icons.logout, Colors.orange, () => _doCheckOut(activeVisit))
          : _actionButton('Check-in', Icons.login, const Color(0xFF1E3A5F), () => _doCheckIn(a)),
        onTap: () {
          if (a.location != null) {
            _mapController.move(LatLng(a.location!.latitude, a.location!.longitude), 16);
            try { _sheetCtl.animateTo(0.12, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); } catch (_) {}
          }
        },
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      height: 34,
      child: FilledButton.icon(
        onPressed: _isGettingLocation ? null : onTap,
        icon: _isGettingLocation
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
        ),
      ),
    );
  }

  // ==================== FIELD LOCATION CARD & REGISTRATION ====================

  Widget _buildFieldLocationCard(FieldLocation loc) {
    double? distance;
    if (_currentLat != null) {
      distance = _calculateDistance(_currentLat!, _currentLng!, loc.latitude, loc.longitude);
    }

    // Check if already visited today
    final todayVisit = _todayVisits.where((v) => v.locationId == loc.id).toList();
    final activeVisit = todayVisit.where((v) => v.isCheckedIn).firstOrNull;

    Color accentColor;
    IconData statusIcon;
    String statusLabel;
    if (activeVisit != null) {
      accentColor = Colors.orange;
      statusIcon = Icons.radio_button_checked;
      statusLabel = 'Đang ở điểm';
    } else {
      accentColor = const Color(0xFF6366F1);
      statusIcon = Icons.storefront;
      statusLabel = distance != null
          ? (distance < 1000 ? '${distance.toStringAsFixed(0)}m' : '${(distance / 1000).toStringAsFixed(1)}km')
          : 'Chưa check-in';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: activeVisit != null ? 0.5 : 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            loc.category == 'pharmacy' ? Icons.local_pharmacy
                : loc.category == 'hospital' ? Icons.local_hospital
                : Icons.storefront,
            color: accentColor, size: 22,
          ),
        ),
        title: Text(loc.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (loc.address != null && loc.address!.isNotEmpty)
            Text(loc.address!, style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          Row(children: [
            Icon(statusIcon, size: 12, color: accentColor),
            const SizedBox(width: 4),
            Text(statusLabel, style: TextStyle(fontSize: 12, color: accentColor, fontWeight: FontWeight.w500)),
            if (loc.contactName != null && loc.contactName!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Icon(Icons.person, size: 11, color: Colors.grey[500]),
              const SizedBox(width: 2),
              Flexible(child: Text(loc.contactName!, style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis)),
            ],
          ]),
        ]),
        trailing: activeVisit != null
            ? _actionButton('Check-out', Icons.logout, Colors.orange, () => _doCheckOut(activeVisit))
          : _actionButton('Check-in', Icons.login, const Color(0xFF6366F1), () => _doCheckInAtFieldLocation(loc)),
        onTap: () {
          _mapController.move(LatLng(loc.latitude, loc.longitude), 16);
          try { _sheetCtl.animateTo(0.12, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); } catch (_) {}
        },
      ),
    );
  }

  void _showRegisterLocationDialog() {
    final nameCtl = TextEditingController();
    final addressCtl = TextEditingController();
    final contactNameCtl = TextEditingController();
    final contactPhoneCtl = TextEditingController();
    final contactEmailCtl = TextEditingController();
    final noteCtl = TextEditingController();
    String? selectedCategory;
    double? lat = _currentLat;
    double? lng = _currentLng;
    final photos = <String>[];
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.9,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(child: Container(
                      width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                    )),
                    const Text('Đăng ký điểm bán mới',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
                    const SizedBox(height: 16),

                    // Name
                    TextField(
                      controller: nameCtl,
                      decoration: const InputDecoration(
                        labelText: 'Tên cửa hàng *',
                        prefixIcon: Icon(Icons.store),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Address
                    TextField(
                      controller: addressCtl,
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ',
                        prefixIcon: Icon(Icons.location_on),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Category
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Loại cửa hàng',
                        prefixIcon: Icon(Icons.category),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'retail', child: Text('Bán lẻ')),
                        DropdownMenuItem(value: 'wholesale', child: Text('Bán sỉ')),
                        DropdownMenuItem(value: 'pharmacy', child: Text('Nhà thuốc')),
                        DropdownMenuItem(value: 'restaurant', child: Text('Quán ăn')),
                        DropdownMenuItem(value: 'supermarket', child: Text('Siêu thị')),
                        DropdownMenuItem(value: 'other', child: Text('Khác')),
                      ],
                      onChanged: (v) => setSheetState(() => selectedCategory = v),
                    ),
                    const SizedBox(height: 16),

                    // Contact info section
                    const Text('Thông tin liên hệ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),

                    TextField(
                      controller: contactNameCtl,
                      decoration: const InputDecoration(
                        labelText: 'Tên người liên hệ',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: contactPhoneCtl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: contactEmailCtl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Location
                    const Text('Vị trí GPS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.gps_fixed, color: Color(0xFF1E3A5F), size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          lat != null
                              ? 'Vị trí hiện tại: ${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}'
                              : 'Chưa xác định được vị trí GPS',
                          style: TextStyle(fontSize: 12, color: lat != null ? const Color(0xFF1E3A5F) : Colors.red),
                        )),
                        if (lat == null)
                          TextButton(
                            onPressed: () async {
                              await _getLocation();
                              setSheetState(() {
                                lat = _currentLat;
                                lng = _currentLng;
                              });
                            },
                            child: const Text('Lấy vị trí'),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // Note
                    TextField(
                      controller: noteCtl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú',
                        prefixIcon: Icon(Icons.note),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Photos
                    const Text('Ảnh cửa hàng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...photos.asMap().entries.map((entry) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                base64Decode(entry.value.contains(',') ? entry.value.split(',').last : entry.value),
                                width: 72, height: 72, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 72, height: 72,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0, right: 0,
                              child: GestureDetector(
                                onTap: () => setSheetState(() => photos.removeAt(entry.key)),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        )),
                        if (photos.length < 5)
                          InkWell(
                            onTap: () async {
                              try {
                                final picker = ImagePicker();
                                final picked = await picker.pickImage(
                                    source: ImageSource.camera, maxWidth: 1024, imageQuality: 80);
                                if (picked != null) {
                                  final bytes = await picked.readAsBytes();
                                  final b64 = base64Encode(_compressImage(bytes));
                                  setSheetState(() => photos.add(b64));
                                }
                              } catch (e) {
                                // camera not available on web, try gallery
                                try {
                                  final picker = ImagePicker();
                                  final picked = await picker.pickImage(
                                      source: ImageSource.gallery, maxWidth: 1024, imageQuality: 80);
                                  if (picked != null) {
                                    final bytes = await picked.readAsBytes();
                                    final b64 = base64Encode(_compressImage(bytes));
                                    setSheetState(() => photos.add(b64));
                                  }
                                } catch (_) {}
                              }
                            },
                            child: Container(
                              width: 72, height: 72,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.camera_alt, color: Colors.grey[500], size: 24),
                                Text('Chụp ảnh', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                              ]),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: saving ? null : () async {
                          if (nameCtl.text.trim().isEmpty) {
                            NotificationOverlayManager().showWarning(title: 'Lỗi', message: 'Vui lòng nhập tên cửa hàng');
                            return;
                          }
                          if (lat == null || lng == null) {
                            NotificationOverlayManager().showWarning(title: 'Lỗi', message: 'Chưa xác định được vị trí GPS');
                            return;
                          }
                          setSheetState(() => saving = true);
                          final result = await _apiService.registerFieldLocation({
                            'name': nameCtl.text.trim(),
                            'address': addressCtl.text.trim(),
                            'contactName': contactNameCtl.text.trim(),
                            'contactPhone': contactPhoneCtl.text.trim(),
                            'contactEmail': contactEmailCtl.text.trim(),
                            'note': noteCtl.text.trim(),
                            'latitude': lat,
                            'longitude': lng,
                            'radius': 200,
                            'category': selectedCategory ?? '',
                            if (photos.isNotEmpty) 'photos': photos,
                          });
                          setSheetState(() => saving = false);
                          if (result['isSuccess'] == true) {
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã đăng ký điểm bán thành công!');
                            _loadMyData();
                          } else {
                            NotificationOverlayManager().showWarning(title: 'Lỗi', message: result['message'] ?? 'Lỗi đăng ký');
                          }
                        },
                        icon: saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check),
                        label: Text(saving ? 'Đang lưu...' : 'Đăng ký điểm bán'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A5F),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ==================== TAB 2: HISTORY ====================

  List<VisitReport> get _filteredHistoryVisits {
    final q = _historySearchQuery.toLowerCase().trim();
    if (q.isEmpty) return _historyVisits;
    return _historyVisits.where((v) {
      return (v.locationName ?? '').toLowerCase().contains(q) ||
          (v.contactPhone ?? '').contains(q) ||
          (v.locationAddress ?? '').toLowerCase().contains(q) ||
          (v.contactName ?? '').toLowerCase().contains(q) ||
          (v.employeeName ?? '').toLowerCase().contains(q) ||
          (v.reportNote ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Widget _buildHistoryTab() {
    final filtered = _filteredHistoryVisits;
    // Summary stats
    final totalVisits = filtered.length;
    final uniqueLocations = filtered.map((v) => v.locationId).toSet().length;
    final checkedOut = filtered.where((v) => v.isCheckedOut || v.isReviewed).length;
    final totalMinutes = filtered.where((v) => v.timeSpentMinutes != null).fold<int>(0, (s, v) => s + v.timeSpentMinutes!);
    final uniqueEmployees = _isManager ? filtered.map((v) => v.employeeId).toSet().length : 0;

    return Column(
      children: [
        // === Filters section ===
        Container(
          color: Colors.grey.shade50,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Row 1: Date range + Employee filter (if manager)
            Row(children: [
              // Date range picker
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      initialDateRange: DateTimeRange(start: _historyFrom, end: _historyTo),
                    );
                    if (picked != null) {
                      setState(() { _historyFrom = picked.start; _historyTo = picked.end; });
                      _loadHistory();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.date_range, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text('${DateFormat('dd/MM').format(_historyFrom)} - ${DateFormat('dd/MM').format(_historyTo)}',
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
              ),
              // Quick date buttons
              const SizedBox(width: 6),
              _buildQuickDateBtn('Hôm nay', 0),
              const SizedBox(width: 4),
              _buildQuickDateBtn('7 ngày', 7),
              const SizedBox(width: 4),
              _buildQuickDateBtn('30 ngày', 30),
            ]),
            const SizedBox(height: 6),
            // Row 2: Employee filter (manager) + Search
            Row(children: [
              if (_isManager) ...[
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _historyEmployeeFilter,
                        hint: Row(children: [
                          Icon(Icons.person, size: 16, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          const Text('Tất cả NV', style: TextStyle(fontSize: 12)),
                        ]),
                        isExpanded: true,
                        isDense: true,
                        icon: Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[500]),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('Tất cả NV', style: TextStyle(fontSize: 12))),
                          ..._getUniqueEmployees().map((e) => DropdownMenuItem<String?>(
                            value: e['id'],
                            child: Text(e['name']!, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                          )),
                        ],
                        onChanged: (v) {
                          setState(() => _historyEmployeeFilter = v);
                          _loadHistory();
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              // Search box
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _historySearchCtl,
                    onChanged: (v) => setState(() => _historySearchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'SĐT, địa chỉ, tên điểm...',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
                      suffixIcon: _historySearchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () { _historySearchCtl.clear(); setState(() => _historySearchQuery = ''); },
                              child: Icon(Icons.close, size: 16, color: Colors.grey[400]),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ]),
          ]),
        ),
        // === Summary stats ===
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _buildHistoryStat(Icons.store, '$totalVisits', 'Lượt'),
              _buildHistoryStat(Icons.place, '$uniqueLocations', 'Điểm'),
              _buildHistoryStat(Icons.check_circle, '$checkedOut', 'Xong'),
              _buildHistoryStat(Icons.timer, _formatMinutes(totalMinutes), 'Thời gian'),
              if (_isManager) _buildHistoryStat(Icons.people, '$uniqueEmployees', 'NV'),
            ],
          ),
        ),
        const Divider(height: 1),
        // === Visit list ===
        Expanded(
          child: _isLoadingHistory
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.history, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        _historySearchQuery.isNotEmpty ? 'Không tìm thấy kết quả' : 'Chưa có lượt tiếp cận',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _loadHistory,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) => _buildHistoryVisitCard(filtered[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildQuickDateBtn(String label, int days) {
    final now = DateTime.now();
    final from = days == 0 ? DateTime(now.year, now.month, now.day) : now.subtract(Duration(days: days));
    final isActive = _historyFrom.day == from.day && _historyFrom.month == from.month && _historyFrom.year == from.year
        && _historyTo.day == now.day && _historyTo.month == now.month && _historyTo.year == now.year;
    return GestureDetector(
      onTap: () {
        setState(() { _historyFrom = from; _historyTo = now; });
        _loadHistory();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1E3A5F) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isActive ? const Color(0xFF1E3A5F) : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(fontSize: 10, color: isActive ? Colors.white : Colors.grey[600], fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildHistoryStat(IconData icon, String value, String label) {
    return Expanded(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: const Color(0xFF1E3A5F)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A5F))),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      ]),
    );
  }

  String _formatMinutes(int mins) {
    if (mins < 60) return '${mins}p';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m > 0 ? '${h}h${m}p' : '${h}h';
  }

  List<Map<String, String>> _getUniqueEmployees() {
    final seen = <String>{};
    final result = <Map<String, String>>[];
    for (final v in _historyVisits) {
      if (v.employeeId != null && seen.add(v.employeeId!)) {
        result.add({'id': v.employeeId!, 'name': v.employeeName ?? v.employeeId!});
      }
    }
    result.sort((a, b) => a['name']!.compareTo(b['name']!));
    return result;
  }

  // ignore: unused_element
  Widget _buildJourneyHistoryCard(JourneyTracking j) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF1E3A5F).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.route, color: Color(0xFF1E3A5F), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('EEEE dd/MM/yyyy', 'vi').format(j.journeyDate.toLocal()),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              if (j.startTime != null)
                Text(
                  '${DateFormat('HH:mm').format(j.startTime!.toLocal())}${j.endTime != null ? " → ${DateFormat('HH:mm').format(j.endTime!.toLocal())}" : " → đang đi"}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
            ])),
            _buildStatusChip(j.status),
          ]),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _miniStat(Icons.route, j.distanceFormatted, 'Đường đi'),
              _miniStat(Icons.timer, j.durationFormatted, 'Thời gian'),
              _miniStat(Icons.store, '${j.checkedInCount}/${j.assignedCount}', 'Điểm'),
              _miniStat(Icons.schedule, '${j.totalOnSiteMinutes}p', 'Tại điểm'),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _miniStat(IconData icon, String value, String label) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: const Color(0xFF71717A)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
    ]);
  }

  Widget _buildHistoryVisitCard(VisitReport v) {
    final hasContact = v.contactName != null || v.contactPhone != null;
    final meetingSummary = (v.reportData?['meetingSummary'] ?? '').toString().trim();
    final customerStatus = (v.reportData?['customerStatus'] ?? '').toString().trim();
    final nextAction = (v.reportData?['nextAction'] ?? '').toString().trim();
    final hasReport = meetingSummary.isNotEmpty ||
        customerStatus.isNotEmpty ||
        nextAction.isNotEmpty ||
        (v.reportNote != null && v.reportNote!.isNotEmpty) ||
        v.photos.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showVisitDetailSheet(v),
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header: location name + status
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: v.isCheckedOut || v.isReviewed ? Colors.green.shade50 : Colors.orange.shade50,
              child: Icon(Icons.store, size: 18, color: v.isCheckedOut || v.isReviewed ? Colors.green : Colors.orange),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.locationName ?? 'Không tên', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              if (v.locationAddress != null && v.locationAddress!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    Icon(Icons.place, size: 12, color: Colors.grey[400]),
                    const SizedBox(width: 3),
                    Expanded(child: Text(v.locationAddress!, style: TextStyle(fontSize: 11, color: Colors.grey[600]), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ])),
            const SizedBox(width: 6),
            _buildStatusChip(v.status),
          ]),
          // Contact info
          if (hasContact) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.person_outline, size: 14, color: Colors.blue[700]),
                const SizedBox(width: 6),
                if (v.contactName != null)
                  Text(v.contactName!, style: TextStyle(fontSize: 12, color: Colors.blue[800], fontWeight: FontWeight.w500)),
                if (v.contactPhone != null) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.phone, size: 12, color: Colors.blue[700]),
                  const SizedBox(width: 3),
                  Text(v.contactPhone!, style: TextStyle(fontSize: 12, color: Colors.blue[800])),
                ],
                if (v.contactEmail != null) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.email_outlined, size: 12, color: Colors.blue[700]),
                  const SizedBox(width: 3),
                  Expanded(child: Text(v.contactEmail!, style: TextStyle(fontSize: 11, color: Colors.blue[700]), overflow: TextOverflow.ellipsis)),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 8),
          // Time + employee info row
          Row(children: [
            Icon(Icons.access_time, size: 13, color: Colors.grey[500]),
            const SizedBox(width: 4),
            Text(
              v.checkInTime != null
                  ? DateFormat('dd/MM/yyyy HH:mm').format(v.checkInTime!.toLocal())
                  : DateFormat('dd/MM/yyyy').format(v.visitDate.toLocal()),
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            if (v.checkOutTime != null) ...[
              Text(' → ', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Text(DateFormat('HH:mm').format(v.checkOutTime!.toLocal()), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
            if (v.timeSpentMinutes != null && v.timeSpentMinutes! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFF1E3A5F).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(v.timeSpentFormatted, style: const TextStyle(fontSize: 10, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600)),
              ),
            ],
            const Spacer(),
            if (_isManager && v.employeeName != null) ...[
              Icon(Icons.person, size: 13, color: Colors.grey[500]),
              const SizedBox(width: 3),
              Text(v.employeeName!, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500)),
            ],
          ]),
          // Distance info
          if (v.checkInDistance != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.straighten, size: 12, color: Colors.grey[400]),
              const SizedBox(width: 4),
              Text('Khoảng cách: ${v.checkInDistance!.toStringAsFixed(0)}m', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              if (v.outsideRadius)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                  child: Text('Ngoài vùng', style: TextStyle(fontSize: 9, color: Colors.red[700], fontWeight: FontWeight.w500)),
                ),
            ]),
          ],
          // Report note
          if (v.reportNote != null && v.reportNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.notes, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Expanded(child: Text(v.reportNote!, style: TextStyle(fontSize: 12, color: Colors.grey[700]), maxLines: 3, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ],
          // Photos count
          if (v.photos.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.photo_camera, size: 12, color: Colors.grey[400]),
              const SizedBox(width: 4),
              Text('${v.photos.length} ảnh', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ]),
          ],
          // View report footer
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: (hasReport ? const Color(0xFF1E3A5F) : Colors.grey).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Icon(
                hasReport ? Icons.description : Icons.description_outlined,
                size: 13,
                color: hasReport ? const Color(0xFF1E3A5F) : Colors.grey[500],
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasReport ? 'Xem báo cáo chi tiết' : 'Chưa có báo cáo — bấm để xem',
                  style: TextStyle(
                    fontSize: 11,
                    color: hasReport ? const Color(0xFF1E3A5F) : Colors.grey[600],
                    fontWeight: hasReport ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 14, color: Colors.grey[500]),
            ]),
          ),
        ]),
      ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    String label;
    switch (status) {
      case 'checked_in': case 'in_progress': color = Colors.orange; label = status == 'in_progress' ? 'Đang đi' : 'Đang ở'; break;
      case 'checked_out': color = Colors.blue; label = 'Đã xong'; break;
      case 'completed': color = const Color(0xFF1E3A5F); label = 'Hoàn thành'; break;
      case 'reviewed': color = const Color(0xFF22C55E); label = 'Đã duyệt'; break;
      default: color = Colors.grey; label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }

  // ==================== TAB 3: MANAGER ====================

  // Color palette for employee routes
  static const _routeColors = [
    Color(0xFF1E3A5F), Color(0xFFE53E3E), Color(0xFF38A169),
    Color(0xFFDD6B20), Color(0xFF805AD5), Color(0xFF2B6CB0),
    Color(0xFFD53F8C), Color(0xFF2C7A7B), Color(0xFFC05621), Color(0xFF6B46C1),
  ];

  // ignore: unused_element
  Color _getEmployeeColor(int index) => _routeColors[index % _routeColors.length];

  // Department color palette
  static const _deptColors = [
    Color(0xFF1E3A5F), Color(0xFFE53E3E), Color(0xFF38A169),
    Color(0xFFDD6B20), Color(0xFF805AD5), Color(0xFF2B6CB0),
    Color(0xFFD53F8C), Color(0xFF2C7A7B), Color(0xFFC05621), Color(0xFF6B46C1),
  ];

  Color _getDeptColor(int deptIndex) => _deptColors[deptIndex % _deptColors.length];

  Widget _buildManagerTab() {
    if (_isLoadingManager) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _loadManagerData,
      child: Column(
        children: [
          // Header with toggle + assign
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      initialDateRange: DateTimeRange(start: _reportFrom, end: _reportTo),
                    );
                    if (picked != null) {
                      setState(() { _reportFrom = picked.start; _reportTo = picked.end; });
                      _loadManagerData();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.date_range, size: 18),
                      const SizedBox(width: 8),
                      Text('${DateFormat('dd/MM').format(_reportFrom)} - ${DateFormat('dd/MM/yyyy').format(_reportTo)}', style: const TextStyle(fontSize: 13)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => setState(() => _showManagerMap = !_showManagerMap),
                icon: Icon(_showManagerMap ? Icons.list : Icons.map, size: 22),
                tooltip: _showManagerMap ? 'Danh sách' : 'Bản đồ',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                ),
              ),
              const SizedBox(width: 4),
              if (Provider.of<PermissionProvider>(context, listen: false).canCreate('FieldCheckIn'))
                FilledButton.icon(
                  onPressed: _showAssignDialog,
                  icon: const Icon(Icons.add_location_alt, size: 18),
                  label: const Text('Giao'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                ),
            ]),
          ),
          const SizedBox(height: 8),

          // Map or List
          Expanded(
            child: _showManagerMap ? _buildEmployeeMapView() : _buildManagerListView(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeMapView() {
    final markers = <Marker>[];
    final circles = <CircleMarker>[];

    // Group employees by department for legend
    final deptGroups = <String, List<Map<String, dynamic>>>{};
    for (final emp in _employeeLocations) {
      final dept = emp['department'] ?? 'Khác';
      deptGroups.putIfAbsent(dept, () => []).add(emp);
    }

    // Build markers for each employee
    for (final emp in _employeeLocations) {
      final lat = (emp['latitude'] as num?)?.toDouble();
      final lng = (emp['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null || lat == 0) continue;

      final deptIdx = (emp['departmentColorIndex'] as num?)?.toInt() ?? 0;
      final color = _getDeptColor(deptIdx);
      final name = emp['employeeName'] ?? '?';
      final isSelected = emp['employeeId'] == _selectedEmployeeId;
      final checkinCount = (emp['checkinCount'] as num?)?.toInt() ?? 0;
      final source = emp['locationSource'] ?? '';

      // Location accuracy circle
      circles.add(CircleMarker(
        point: LatLng(lat, lng),
        radius: isSelected ? 24 : 16,
        color: color.withValues(alpha: isSelected ? 0.2 : 0.08),
        borderColor: color.withValues(alpha: 0.5),
        borderStrokeWidth: 1,
      ));

      // Employee marker with name
      markers.add(Marker(
        point: LatLng(lat, lng),
        width: isSelected ? 180 : 120,
        height: isSelected ? 68 : 52,
        child: GestureDetector(
          onTap: () => setState(() {
            _selectedEmployeeId = isSelected ? null : emp['employeeId'];
          }),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Name badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? color : color.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  name.length > 14 ? '${name.substring(0, 14)}…' : name,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
                if (checkinCount > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4)),
                    child: Text('$checkinCount', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
            ),
            // Pin icon
            Icon(
              source == 'journey' ? Icons.directions_walk :
              source == 'checkin' ? Icons.location_on :
              Icons.person_pin_circle,
              color: color,
              size: isSelected ? 26 : 20,
            ),
          ]),
        ),
      ));

      // If selected, show check-in location markers
      if (isSelected) {
        final visits = (emp['todayCheckins'] as List?) ?? [];
        for (final v in visits) {
          final vLat = (v['checkInLatitude'] as num?)?.toDouble();
          final vLng = (v['checkInLongitude'] as num?)?.toDouble();
          if (vLat == null || vLng == null || vLat == 0) continue;
          circles.add(CircleMarker(
            point: LatLng(vLat, vLng),
            radius: 14,
            color: Colors.orange.withValues(alpha: 0.2),
            borderColor: Colors.orange,
            borderStrokeWidth: 2,
          ));
          markers.add(Marker(
            point: LatLng(vLat, vLng),
            width: 120, height: 32,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 3)],
              ),
              child: Text(
                v['locationName'] ?? '',
                style: const TextStyle(fontSize: 9, color: Colors.deepOrange, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
          ));
        }
      }
    }

    // Determine center
    LatLng center = const LatLng(16.0544, 108.2022);
    double zoom = 12;
    final allPoints = _employeeLocations
        .where((e) => (e['latitude'] as num?)?.toDouble() != null && (e['latitude'] as num?)?.toDouble() != 0)
        .map((e) => LatLng((e['latitude'] as num).toDouble(), (e['longitude'] as num).toDouble()))
        .toList();
    if (allPoints.isNotEmpty) {
      if (allPoints.length == 1) {
        center = allPoints.first;
        zoom = 15;
      } else {
        center = LatLng(
          allPoints.map((p) => p.latitude).reduce((a, b) => a + b) / allPoints.length,
          allPoints.map((p) => p.longitude).reduce((a, b) => a + b) / allPoints.length,
        );
      }
    }

    final withLocation = _employeeLocations.where((e) => (e['latitude'] as num?)?.toDouble() != null && (e['latitude'] as num?)?.toDouble() != 0).length;

    return Column(children: [
      // Department legend
      if (deptGroups.length > 1)
        Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: deptGroups.entries.map((entry) {
              final deptIdx = (entry.value.first['departmentColorIndex'] as num?)?.toInt() ?? 0;
              final color = _getDeptColor(deptIdx);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: CircleAvatar(radius: 6, backgroundColor: color),
                  label: Text('${entry.key} (${entry.value.length})', style: const TextStyle(fontSize: 10)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList(),
          ),
        ),

      // Map
      Expanded(
        flex: 3,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _managerMapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                onTap: (_, __) => setState(() {
                  _selectedEmployeeId = null;
                  _selectedJourney = null;
                }),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.zktecoadms.app',
                ),
                if (circles.isNotEmpty) CircleLayer(circles: circles),
                if (markers.isNotEmpty) MarkerLayer(markers: markers),
                // Journey route overlay
                if (_selectedJourney != null) ..._buildJourneyOverlayLayers(),
              ],
            ),
            // Info badge
            Positioned(
              top: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.people, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text('$withLocation/${_employeeLocations.length} có vị trí',
                      style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  Icon(Icons.refresh, size: 14, color: Colors.grey[500]),
                  Text(' 60s', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                ]),
              ),
            ),
          ],
        ),
      ),

      // Bottom panel: Employee list with check-in history
      Expanded(
        flex: 2,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))],
          ),
          child: Column(children: [
            Center(child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            )),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Icon(Icons.people, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  'Nhân viên (${_employeeLocations.length}) • Check-in hôm nay',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _employeeLocations.isEmpty
                  ? Center(child: Text('Không có nhân viên', style: TextStyle(color: Colors.grey[500])))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _employeeLocations.length,
                      itemBuilder: (ctx, i) => _buildEmployeeLocationTile(i),
                    ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildEmployeeLocationTile(int index) {
    final emp = _employeeLocations[index];
    final deptIdx = (emp['departmentColorIndex'] as num?)?.toInt() ?? 0;
    final color = _getDeptColor(deptIdx);
    final isSelected = emp['employeeId'] == _selectedEmployeeId;
    final name = emp['employeeName'] ?? '?';
    final dept = emp['department'] ?? '';
    final position = emp['position'] ?? '';
    final checkins = (emp['todayCheckins'] as List?) ?? [];
    final hasLocation = (emp['latitude'] as num?)?.toDouble() != null && (emp['latitude'] as num?)?.toDouble() != 0;
    final source = emp['locationSource'] ?? '';
    final lastUpdate = emp['lastUpdateTime'] != null ? DateTime.tryParse(emp['lastUpdateTime']) : null;

    String sourceLabel;
    IconData sourceIcon;
    switch (source) {
      case 'journey': sourceLabel = 'Hành trình'; sourceIcon = Icons.directions_walk; break;
      case 'checkin': sourceLabel = 'Check-in'; sourceIcon = Icons.location_on; break;
      case 'punch': sourceLabel = 'Chấm công'; sourceIcon = Icons.fingerprint; break;
      case 'live': sourceLabel = 'Trực tuyến'; sourceIcon = Icons.gps_fixed; break;
      default: sourceLabel = 'Chưa có vị trí'; sourceIcon = Icons.location_off;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: isSelected ? color.withValues(alpha: 0.06) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected ? BorderSide(color: color, width: 1.5) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            _selectedEmployeeId = isSelected ? null : emp['employeeId'];
            if (!isSelected) _selectedJourney = null;
          });
          // Center map on employee location
          if (!isSelected && hasLocation) {
            final lat = (emp['latitude'] as num).toDouble();
            final lng = (emp['longitude'] as num).toDouble();
            try { _managerMapController.move(LatLng(lat, lng), 16); } catch (_) {}
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            CircleAvatar(
              radius: 18, backgroundColor: color.withValues(alpha: 0.15),
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                if (checkins.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text('${checkins.length} check-in', style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600)),
                  ),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Text(dept, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
                if (position.isNotEmpty) Text(' • $position', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Icon(sourceIcon, size: 12, color: hasLocation ? Colors.green : Colors.grey[400]),
                const SizedBox(width: 3),
                Text(sourceLabel, style: TextStyle(fontSize: 10, color: hasLocation ? Colors.green : Colors.grey[500])),
                if (lastUpdate != null) ...[
                  const SizedBox(width: 6),
                  Text(DateFormat('HH:mm').format(lastUpdate.toLocal()),
                      style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                ],
              ]),
              // Check-in history when selected
              if (isSelected && checkins.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Divider(height: 1),
                const SizedBox(height: 4),
                ...checkins.map((v) {
                  final locName = v['locationName'] ?? '';
                  final checkIn = v['checkInTime'] != null ? DateTime.tryParse(v['checkInTime']) : null;
                  final checkOut = v['checkOutTime'] != null ? DateTime.tryParse(v['checkOutTime']) : null;
                  final mins = v['timeSpentMinutes'] ?? 0;
                  final vStatus = v['status'] ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(children: [
                      Icon(
                        vStatus == 'checked_out' ? Icons.check_circle : Icons.radio_button_checked,
                        size: 14,
                        color: vStatus == 'checked_out' ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(locName, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (checkIn != null)
                        Text(DateFormat('HH:mm').format(checkIn.toLocal()), style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                      if (checkOut != null)
                        Text(' → ${DateFormat("HH:mm").format(checkOut.toLocal())}', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                      if (mins > 0)
                        Text(' (${mins}p)', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                    ]),
                  );
                }),
              ],
              // Journey action buttons when selected
              if (isSelected) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoadingJourney ? null : () => _loadEmployeeJourney(emp['employeeId'], name),
                      icon: _isLoadingJourney
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.route, size: 14),
                      label: Text(
                        _selectedJourney != null && _selectedJourney!.employeeId == emp['employeeId']
                            ? 'Ẩn hành trình'
                            : 'Xem hành trình hôm nay',
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E3A5F),
                        side: const BorderSide(color: Color(0xFF1E3A5F), width: 0.8),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ]),
              ],
            ])),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
          ]),
        ),
      ),
    );
  }

  /// Load today's journey for a specific employee and show on map
  Future<void> _loadEmployeeJourney(String employeeId, String employeeName) async {
    // Toggle off if already showing this employee's journey
    if (_selectedJourney != null && _selectedJourney!.employeeId == employeeId) {
      setState(() => _selectedJourney = null);
      return;
    }

    setState(() => _isLoadingJourney = true);
    try {
      final today = DateTime.now();
      final result = await _apiService.getJourneyReports(
        employeeId: employeeId,
        fromDate: DateTime(today.year, today.month, today.day),
        toDate: DateTime(today.year, today.month, today.day, 23, 59, 59),
      );
      if (!mounted) return;

      if (result['isSuccess'] == true && result['data'] != null) {
        final journeys = (result['data'] as List)
            .map((j) => JourneyTracking.fromJson(j))
            .toList();

        if (journeys.isEmpty) {
          setState(() { _selectedJourney = null; _isLoadingJourney = false; });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$employeeName chưa có hành trình hôm nay')),
          );
          return;
        }

        final journey = journeys.first;
        setState(() {
          _selectedJourney = journey;
          _isLoadingJourney = false;
        });

        // Fit map to journey route
        final points = journey.routePoints.where((p) => p.lat != 0 && p.lng != 0).toList();
        if (points.isNotEmpty) {
          if (points.length == 1) {
            try { _managerMapController.move(LatLng(points.first.lat, points.first.lng), 15); } catch (_) {}
          } else {
            final lats = points.map((p) => p.lat);
            final lngs = points.map((p) => p.lng);
            try {
              _managerMapController.fitCamera(CameraFit.bounds(
                bounds: LatLngBounds(
                  LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
                  LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
                ),
                padding: const EdgeInsets.all(60),
              ));
            } catch (_) {}
          }
        }
      } else {
        setState(() { _selectedJourney = null; _isLoadingJourney = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$employeeName chưa có hành trình hôm nay')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _selectedJourney = null; _isLoadingJourney = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi tải hành trình: $e')),
      );
    }
  }

  /// Build journey overlay layers for the manager map
  List<Widget> _buildJourneyOverlayLayers() {
    final j = _selectedJourney;
    if (j == null) return [];
    final points = j.routePoints.where((p) => p.lat != 0 && p.lng != 0).toList();
    if (points.isEmpty) return [];

    final dwellPoints = points.where((p) => p.isDwell).toList();
    final layers = <Widget>[];

    // Route polyline
    layers.add(PolylineLayer(polylines: [
      Polyline(
        points: points.map((p) => LatLng(p.lat, p.lng)).toList(),
        color: const Color(0xFF1E3A5F),
        strokeWidth: 3.5,
      ),
    ]));

    // Dwell circles
    if (dwellPoints.isNotEmpty) {
      layers.add(CircleLayer(circles: dwellPoints.map((p) => CircleMarker(
        point: LatLng(p.lat, p.lng),
        radius: 22,
        color: Colors.orange.withValues(alpha: 0.25),
        borderColor: Colors.orange,
        borderStrokeWidth: 2,
      )).toList()));
    }

    // Route point markers with time labels
    final routeMarkers = <Marker>[];

    // Start marker
    routeMarkers.add(Marker(
      point: LatLng(points.first.lat, points.first.lng),
      width: 80, height: 44,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.green.shade700,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            DateFormat('HH:mm').format(points.first.time.toLocal()),
            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
        const Icon(Icons.play_circle_filled, color: Colors.green, size: 22),
      ]),
    ));

    // End marker
    if (points.length > 1) {
      routeMarkers.add(Marker(
        point: LatLng(points.last.lat, points.last.lng),
        width: 80, height: 44,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: j.isCompleted ? Colors.red.shade700 : Colors.blue.shade700,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              DateFormat('HH:mm').format(points.last.time.toLocal()),
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ),
          Icon(
            j.isCompleted ? Icons.flag_circle : Icons.my_location,
            color: j.isCompleted ? Colors.red : Colors.blue,
            size: 22,
          ),
        ]),
      ));
    }

    // Dwell point markers with time & duration
    for (final p in dwellPoints) {
      routeMarkers.add(Marker(
        point: LatLng(p.lat, p.lng),
        width: 100, height: 38,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.orange, width: 0.5),
          ),
          child: Text(
            '${DateFormat("HH:mm").format(p.time.toLocal())} • ${p.dwellMinutes}p${p.nearLocationName != null ? "\n${p.nearLocationName}" : ""}',
            style: const TextStyle(fontSize: 9, color: Colors.deepOrange, fontWeight: FontWeight.w600),
            maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
          ),
        ),
      ));
    }

    // Intermediate time markers (every ~10 points)
    if (points.length > 5) {
      final step = (points.length / 6).ceil().clamp(3, 20);
      for (var i = step; i < points.length - step; i += step) {
        final p = points[i];
        if (p.isDwell) continue;
        routeMarkers.add(Marker(
          point: LatLng(p.lat, p.lng),
          width: 50, height: 22,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0xFF1E3A5F), width: 0.5),
            ),
            child: Text(
              DateFormat('HH:mm').format(p.time.toLocal()),
              style: const TextStyle(fontSize: 8, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ));
      }
    }

    layers.add(MarkerLayer(markers: routeMarkers));
    return layers;
  }

  Widget _buildManagerListView() {
    final weekly = _weeklyManagerReports;
    final filteredReports = _filteredManagerReports;
    final weeklyTotal = weekly.length;
    final weeklyWithPhotos = weekly.where((v) => v.photos.isNotEmpty).length;
    final weeklyWithStructured = weekly.where((v) {
      final rd = v.reportData ?? const <String, dynamic>{};
      return (rd['meetingSummary'] ?? '').toString().trim().isNotEmpty ||
          (rd['customerStatus'] ?? '').toString().trim().isNotEmpty ||
          (rd['nextAction'] ?? '').toString().trim().isNotEmpty;
    }).length;
    final weeklyWithNextAction = weekly.where((v) => _extractNextAction(v).isNotEmpty).length;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Weekly KPI for manager
        const Text('KPI 7 ngày gần nhất', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildStatCard('Lượt gặp', '$weeklyTotal', Icons.badge, const Color(0xFF1E3A5F)),
            const SizedBox(width: 6),
            _buildStatCard('Có ảnh', '$weeklyWithPhotos', Icons.photo_camera, const Color(0xFF16A34A)),
            const SizedBox(width: 6),
            _buildStatCard('Có báo cáo', '$weeklyWithStructured', Icons.summarize, const Color(0xFF9333EA)),
            const SizedBox(width: 6),
            _buildStatCard('Có follow-up', '$weeklyWithNextAction', Icons.next_plan, const Color(0xFFF59E0B)),
          ].map((w) => Expanded(child: w)).toList(),
        ),
        const SizedBox(height: 16),

        // Journey reports
        if (_managerJourneys.isNotEmpty) ...[
          Text('Hành trình nhân viên (${_managerJourneys.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          ..._managerJourneys.map(_buildManagerJourneyCard),
          const SizedBox(height: 16),
        ],

        // Assignments
        Text('Giao điểm (${_allAssignments.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        if (_allAssignments.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Chưa giao điểm', style: TextStyle(color: Colors.grey[500]))))
        else
          ..._allAssignments.map(_buildManagerAssignmentCard),

        const SizedBox(height: 16),

        // Reports
        Text('Báo cáo check-in (${filteredReports.length}/${_reports.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _managerCustomerStatusOptions.map((status) {
            final selected = status == _managerCustomerStatusFilter;
            return ChoiceChip(
              label: Text(status, style: const TextStyle(fontSize: 11)),
              selected: selected,
              onSelected: (_) => setState(() => _managerCustomerStatusFilter = status),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        if (filteredReports.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Không có báo cáo theo bộ lọc đã chọn', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ),
          )
        else
          ...filteredReports.map(_buildManagerReportCard),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildStatsRow() {
    final total = _reports.length;
    final checkedOut = _reports.where((r) => r.isCheckedOut || r.isReviewed).length;
    final totalMinutes = _reports.where((r) => r.timeSpentMinutes != null).fold<int>(0, (sum, r) => sum + r.timeSpentMinutes!);
    final journeyKm = _managerJourneys.fold<double>(0, (sum, j) => sum + j.totalDistanceKm);

    return Row(
      children: [
        _buildStatCard('Check-in', '$total', Icons.login, Colors.blue),
        const SizedBox(width: 6),
        _buildStatCard('Xong', '$checkedOut', Icons.check_circle, const Color(0xFF22C55E)),
        const SizedBox(width: 6),
        _buildStatCard('Giờ', '${(totalMinutes / 60).toStringAsFixed(1)}h', Icons.timer, Colors.orange),
        const SizedBox(width: 6),
        _buildStatCard('Km', journeyKm.toStringAsFixed(1), Icons.route, const Color(0xFF1E3A5F)),
      ].map((w) => Expanded(child: w)).toList(),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600]), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildManagerJourneyCard(JourneyTracking j) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showJourneyRouteDialog(j),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 16, backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                child: Text((j.employeeName ?? '?')[0].toUpperCase(),
                    style: const TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(j.employeeName ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('${DateFormat('dd/MM').format(j.journeyDate.toLocal())} • ${j.distanceFormatted} • ${j.checkedInCount}/${j.assignedCount} điểm',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ])),
              _buildStatusChip(j.status),
              const SizedBox(width: 4),
              Icon(Icons.map_outlined, size: 18, color: Colors.grey[400]),
            ]),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: j.completionRate,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation(j.completionRate >= 1 ? const Color(0xFF22C55E) : const Color(0xFF1E3A5F)),
            ),
          ]),
        ),
      ),
    );
  }

  void _showJourneyRouteDialog(JourneyTracking j) {
    final points = j.routePoints.where((p) => p.lat != 0 && p.lng != 0).toList();
    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa có dữ liệu tuyến đường')));
      return;
    }

    final center = LatLng(
      points.map((p) => p.lat).reduce((a, b) => a + b) / points.length,
      points.map((p) => p.lng).reduce((a, b) => a + b) / points.length,
    );

    final dwellPoints = points.where((p) => p.isDwell).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF1E3A5F),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(children: [
                const Icon(Icons.route, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(j.employeeName ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(
                    '${DateFormat('dd/MM/yyyy').format(j.journeyDate.toLocal())} • ${j.distanceFormatted} • ${j.durationFormatted}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                  ),
                ])),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ]),
            ),
            // Map
            Expanded(
              flex: 3,
              child: FlutterMap(
                options: MapOptions(initialCenter: center, initialZoom: 14),
                children: [
                  TileLayer(
                    urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.zktecoadms.app',
                  ),
                  PolylineLayer(polylines: [
                    Polyline(
                      points: points.map((p) => LatLng(p.lat, p.lng)).toList(),
                      color: const Color(0xFF1E3A5F),
                      strokeWidth: 3,
                    ),
                  ]),
                  // Dwell circles
                  CircleLayer(circles: dwellPoints.map((p) => CircleMarker(
                    point: LatLng(p.lat, p.lng),
                    radius: 20,
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderColor: Colors.orange,
                    borderStrokeWidth: 2,
                  )).toList()),
                  // Start / End markers
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(points.first.lat, points.first.lng),
                      width: 36, height: 36,
                      child: const Icon(Icons.play_circle_filled, color: Colors.green, size: 28),
                    ),
                    if (points.length > 1)
                      Marker(
                        point: LatLng(points.last.lat, points.last.lng),
                        width: 36, height: 36,
                        child: Icon(
                          j.isCompleted ? Icons.flag_circle : Icons.my_location,
                          color: j.isCompleted ? Colors.red : Colors.blue,
                          size: 28,
                        ),
                      ),
                    // Dwell markers with time
                    ...dwellPoints.map((p) => Marker(
                      point: LatLng(p.lat, p.lng),
                      width: 80, height: 30,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.orange, width: 0.5),
                        ),
                        child: Text(
                          '${p.dwellMinutes}p${p.nearLocationName != null ? " ${p.nearLocationName}" : ""}',
                          style: const TextStyle(fontSize: 9, color: Colors.deepOrange, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )),
                  ]),
                ],
              ),
            ),
            // Stats + dwell summary
            Expanded(
              flex: 2,
              child: ListView(
                controller: scrollCtl,
                padding: const EdgeInsets.all(12),
                children: [
                  // Journey stats
                  Row(children: [
                    _buildMiniStat('Quãng đường', j.distanceFormatted, Icons.straighten),
                    const SizedBox(width: 8),
                    _buildMiniStat('Thời gian', j.durationFormatted, Icons.timer),
                    const SizedBox(width: 8),
                    _buildMiniStat('Check-in', '${j.checkedInCount}/${j.assignedCount}', Icons.location_on),
                  ].map((w) => Expanded(child: w)).toList()),
                  if (dwellPoints.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Các điểm dừng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    ...dwellPoints.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.pause_circle, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(DateFormat('HH:mm').format(p.time.toLocal()), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        Text('${p.dwellMinutes} phút', style: const TextStyle(fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.w600)),
                        if (p.nearLocationName != null) ...[
                          const SizedBox(width: 8),
                          Expanded(child: Text(p.nearLocationName!, style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis)),
                        ],
                      ]),
                    )),
                  ],
                  // Route point timeline
                  const SizedBox(height: 12),
                  Text('Lộ trình (${points.length} điểm)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  ...List.generate(math.min(points.length, 50), (i) {
                    final p = points[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(children: [
                        SizedBox(
                          width: 20,
                          child: Column(children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: p.isDwell ? Colors.orange : const Color(0xFF1E3A5F),
                            )),
                            if (i < points.length - 1)
                              Container(width: 1, height: 12, color: Colors.grey[300]),
                          ]),
                        ),
                        const SizedBox(width: 6),
                        Text(DateFormat('HH:mm:ss').format(p.time.toLocal()), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                        if (p.isDwell) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                            child: Text('${p.dwellMinutes}p', style: const TextStyle(fontSize: 9, color: Colors.deepOrange)),
                          ),
                        ],
                        if (p.speed != null) ...[
                          const SizedBox(width: 6),
                          Text('${p.speed!.toStringAsFixed(1)} km/h', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                        ],
                      ]),
                    );
                  }),
                  if (points.length > 50)
                    Text('... và ${points.length - 50} điểm nữa', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Icon(icon, size: 18, color: const Color(0xFF1E3A5F)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A5F))),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ]),
    );
  }

  Widget _buildManagerAssignmentCard(FieldLocationAssignment a) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16, backgroundColor: Colors.indigo.shade50,
          child: Text(a.employeeName.isNotEmpty ? a.employeeName[0].toUpperCase() : '?',
              style: TextStyle(color: Colors.indigo[700], fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        title: Text(a.employeeName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        subtitle: Text('${a.location?.name ?? ""} • ${a.dayOfWeekLabel}', style: const TextStyle(fontSize: 11)),
        trailing: Provider.of<PermissionProvider>(context, listen: false).canDelete('FieldCheckIn')
            ? IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Xoá giao điểm?'),
                      content: Text('${a.location?.name} - ${a.employeeName}'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('Xoá')),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final resp = await _apiService.deleteFieldAssignment(a.id);
                    if (mounted && resp['isSuccess'] == true) {
                      NotificationOverlayManager().showSuccess(title: 'Xoá', message: 'Đã xoá');
                      _loadManagerData();
                    }
                  }
                },
              )
            : null,
      ),
    );
  }

  Widget _buildManagerReportCard(VisitReport visit) {
    final reportData = visit.reportData ?? const <String, dynamic>{};
    final meetingSummary = (reportData['meetingSummary'] ?? '').toString().trim();
    final customerStatus = (reportData['customerStatus'] ?? '').toString().trim();
    final nextAction = (reportData['nextAction'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.teal.shade50,
                  child: Text(
                    (visit.employeeName ?? '?')[0].toUpperCase(),
                    style: TextStyle(color: Colors.teal[700], fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${visit.employeeName ?? ""} - ${visit.locationName ?? ""}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        '${DateFormat('dd/MM HH:mm').format(visit.visitDate.toLocal())} • ${visit.timeSpentFormatted}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                visit.status == 'checked_out'
                    ? TextButton(
                        onPressed: () => _reviewVisit(visit),
                        child: const Text('Duyệt', style: TextStyle(fontSize: 11)),
                      )
                    : _buildStatusChip(visit.status),
              ],
            ),
            if (meetingSummary.isNotEmpty || customerStatus.isNotEmpty || nextAction.isNotEmpty || (visit.reportNote?.isNotEmpty ?? false) || visit.photos.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (meetingSummary.isNotEmpty)
                _managerInfoLine(Icons.people_outline, 'Tình hình gặp khách', meetingSummary),
              if (customerStatus.isNotEmpty)
                _managerInfoLine(Icons.support_agent, 'Kết quả chăm sóc', customerStatus),
              if (nextAction.isNotEmpty)
                _managerInfoLine(Icons.event_note, 'Hành động tiếp theo', nextAction),
              if (visit.reportNote != null && visit.reportNote!.isNotEmpty)
                _managerInfoLine(Icons.notes, 'Ghi chú', visit.reportNote!),
              if (visit.photos.isNotEmpty)
                _managerInfoLine(Icons.photo_library, 'Ảnh chăm sóc', '${visit.photos.length} ảnh'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _managerInfoLine(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: Colors.grey[600]),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                children: [
                  TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== ASSIGN DIALOG ==========

  Future<void> _showAssignDialog() async {
    if (_employees.isEmpty) {
      try {
        final resp = await _apiService.getEmployees(pageSize: 500);
        _employees = resp.map((e) => e as Map<String, dynamic>).toList();
      } catch (_) {}
    }
    if (_locations.isEmpty) {
      try {
        final resp = await _apiService.getWorkLocations();
        if (resp['isSuccess'] == true && resp['data'] != null) {
          _locations = (resp['data'] as List).map((e) => e as Map<String, dynamic>).toList();
        }
      } catch (_) {}
    }
    if (!mounted) return;

    String? selectedEmployeeId;
    String? selectedEmployeeName;
    String? selectedLocationId;
    int? selectedDow;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void doAssign() async {
            final resp = await _apiService.createFieldAssignment({
              'employeeId': selectedEmployeeId,
              'employeeName': selectedEmployeeName ?? '',
              'locationId': selectedLocationId,
              'dayOfWeek': selectedDow,
            });
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              if (resp['isSuccess'] == true) {
                NotificationOverlayManager().showSuccess(title: 'Giao điểm', message: 'Đã giao');
                _loadManagerData();
              } else {
                NotificationOverlayManager().showWarning(title: 'Lỗi', message: resp['message'] ?? 'Lỗi');
              }
            }
          }

          return AlertDialog(
            title: const Text('Giao điểm cho nhân viên'),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Nhân viên', border: OutlineInputBorder()),
                  isExpanded: true,
                  items: _employees.map((e) {
                    final name = e['fullName'] ?? e['employeeName'] ?? e['name'] ?? '';
                    final id = (e['applicationUserId'] ?? e['id'] ?? '').toString();
                    return DropdownMenuItem(value: id, child: Text(name, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (v) {
                    setDialogState(() {
                      selectedEmployeeId = v;
                      final emp = _employees.firstWhere(
                          (e) => (e['applicationUserId'] ?? e['id'] ?? '').toString() == v,
                          orElse: () => {});
                      selectedEmployeeName = emp['fullName'] ?? emp['employeeName'] ?? '';
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Điểm bán', border: OutlineInputBorder()),
                  isExpanded: true,
                  items: _locations.map((l) => DropdownMenuItem(
                    value: (l['id'] ?? '').toString(),
                    child: Text(l['name'] ?? '', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) => setDialogState(() => selectedLocationId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  decoration: const InputDecoration(labelText: 'Ngày trong tuần', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tất cả')),
                    DropdownMenuItem(value: 1, child: Text('T2')),
                    DropdownMenuItem(value: 2, child: Text('T3')),
                    DropdownMenuItem(value: 3, child: Text('T4')),
                    DropdownMenuItem(value: 4, child: Text('T5')),
                    DropdownMenuItem(value: 5, child: Text('T6')),
                    DropdownMenuItem(value: 6, child: Text('T7')),
                    DropdownMenuItem(value: 7, child: Text('CN')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedDow = v),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
              FilledButton(
                onPressed: selectedEmployeeId != null && selectedLocationId != null ? doAssign : null,
                child: const Text('Giao điểm'),
              ),
            ],
          );
        },
      ),
    );
  }
}
