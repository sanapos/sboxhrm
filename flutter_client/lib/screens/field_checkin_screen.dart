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
  final List<Map<String, dynamic>> _pendingTrackPoints = [];
  static const _kPendingPointsKey = 'field_checkin_pending_gps';

  // History tab
  List<VisitReport> _historyVisits = [];
  List<JourneyTracking> _journeyHistory = [];
  DateTime _historyFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _historyTo = DateTime.now();
  bool _isLoadingHistory = false;

  // Manager tab
  List<FieldLocationAssignment> _allAssignments = [];
  List<VisitReport> _reports = [];
  List<JourneyTracking> _managerJourneys = [];
  bool _isLoadingManager = false;
  DateTime _reportFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _reportTo = DateTime.now();
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _locations = [];

  // Manager map
  List<Map<String, dynamic>> _activeJourneys = [];
  List<Map<String, dynamic>> _employeeLocations = [];
  String? _selectedEmployeeId;
  bool _showManagerMap = true;

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
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _managerRefreshTimer?.cancel();
    _tabCtl.dispose();
    _sheetCtl.dispose();
    _mapController.dispose();
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
        }
        _initGps();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMyData = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final results = await Future.wait([
        _apiService.getMyFieldVisits(fromDate: _historyFrom, toDate: _historyTo),
        _apiService.getJourneyReports(fromDate: _historyFrom, toDate: _historyTo),
      ]);
      if (mounted) {
        setState(() {
          if (results[0]['isSuccess'] == true && results[0]['data'] != null) {
            _historyVisits = (results[0]['data'] as List)
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
            _reports = (results[0]['data'] as List)
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

  // ========== JOURNEY ACTIONS ==========

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

  Future<void> _endJourney() async {
    // Flush pending points
    if (_pendingTrackPoints.isNotEmpty) {
      await _apiService.trackJourneyPoints(List<Map<String, dynamic>>.from(_pendingTrackPoints));
      _pendingTrackPoints.clear();
      _savePendingPoints();
    }

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
    final List<XFile> selectedPhotos = [];
    final picker = ImagePicker();

    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
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
                const SizedBox(height: 16),
                TextField(
                  controller: noteCtl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú / Báo cáo',
                    hintText: 'Nhập ghi chú...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // Photos
                Row(children: [
                  Text('Ảnh (${selectedPhotos.length}/5)', style: const TextStyle(fontWeight: FontWeight.w500)),
                  const Spacer(),
                  if (selectedPhotos.length < 5) ...[
                    IconButton(icon: const Icon(Icons.camera_alt), onPressed: () async {
                      final p = await picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1280);
                      if (p != null) setDialogState(() => selectedPhotos.add(p));
                    }),
                    IconButton(icon: const Icon(Icons.photo_library), onPressed: () async {
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
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, {'note': noteCtl.text}),
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
                : const LatLng(10.8231, 106.6297), // Default HCM
            initialZoom: 14,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.zktecoadms.app',
            ),
            // Route polyline
            if (_todayJourney != null && _todayJourney!.routePoints.isNotEmpty)
              PolylineLayer(polylines: [
                Polyline(
                  points: _todayJourney!.routePoints.map((p) => LatLng(p.lat, p.lng)).toList(),
                  color: const Color(0xFF1E3A5F),
                  strokeWidth: 4,
                ),
              ]),
            // Dwell zone circles
            if (_todayJourney != null)
              CircleLayer(circles: _todayJourney!.routePoints
                  .where((p) => p.isDwell)
                  .map((p) => CircleMarker(
                    point: LatLng(p.lat, p.lng),
                    radius: 30,
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderColor: Colors.orange,
                    borderStrokeWidth: 2,
                  ))
                  .toList()),
            // Location markers
            MarkerLayer(markers: [
              // Dwell location markers (with time badge)
              if (_todayJourney != null)
                ..._todayJourney!.routePoints.where((p) => p.isDwell).map((p) => Marker(
                  point: LatLng(p.lat, p.lng),
                  width: 70,
                  height: 36,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.access_time, size: 12, color: Colors.white),
                      const SizedBox(width: 3),
                      Text(
                        p.dwellMinutes! >= 60
                            ? '${p.dwellMinutes! ~/ 60}h${p.dwellMinutes! % 60}p'
                            : '${p.dwellMinutes}p',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ]),
                  ),
                )),
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
              ..._myAssignments.where((a) => a.location != null).map((a) {
                final visited = _todayVisits.any((v) => v.locationId == a.locationId);
                final activeVisit = _todayVisits.where((v) => v.locationId == a.locationId && v.isCheckedIn).firstOrNull;
                return Marker(
                  point: LatLng(a.location!.latitude, a.location!.longitude),
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () {
                      if (activeVisit != null) {
                        _doCheckOut(activeVisit);
                      } else if (!visited) {
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
              // Field location pins (registered by employees)
              ..._fieldLocations.where((loc) =>
                !_myAssignments.any((a) => a.location != null
                    && (a.location!.latitude - loc.latitude).abs() < 0.0001
                    && (a.location!.longitude - loc.longitude).abs() < 0.0001)
              ).map((loc) {
                final visited = _todayVisits.any((v) => v.locationId == loc.id);
                final activeVisit = _todayVisits.where((v) => v.locationId == loc.id && v.isCheckedIn).firstOrNull;
                return Marker(
                  point: LatLng(loc.latitude, loc.longitude),
                  width: 42,
                  height: 42,
                  child: GestureDetector(
                    onTap: () {
                      if (activeVisit != null) {
                        _doCheckOut(activeVisit);
                      } else if (!visited) {
                        _doCheckInAtFieldLocation(loc);
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
                                  : const Color(0xFF6366F1),
                          width: 2,
                        ),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
                      ),
                      child: Center(
                        child: Icon(
                          activeVisit != null
                              ? Icons.radio_button_checked
                              : visited
                                  ? Icons.check
                                  : Icons.storefront,
                          color: activeVisit != null || visited ? Colors.white : const Color(0xFF6366F1),
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                );
              }),
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
                          Row(children: [
                            const Icon(Icons.place, size: 16, color: Colors.orange),
                            const SizedBox(width: 6),
                            const Text('Các điểm dừng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange)),
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
                    'Điểm bán hôm nay (${_myAssignments.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF18181B)),
                  ),
                ),
                const SizedBox(height: 8),

                if (_myAssignments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(children: [
                      Icon(Icons.location_off, size: 40, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Text('Chưa được giao điểm nào', style: TextStyle(color: Colors.grey[500])),
                    ]),
                  )
                else
                  ..._myAssignments.map((a) => _buildLocationCard(a)),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Field Locations header + register button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(child: Text(
                      'Điểm bán đã đăng ký (${_fieldLocations.length})',
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

                if (_fieldLocations.isEmpty)
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
                  ..._fieldLocations.map((loc) => _buildFieldLocationCard(loc)),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _fitAllMarkers() {
    final points = <LatLng>[];
    if (_currentLat != null) points.add(LatLng(_currentLat!, _currentLng!));
    for (final a in _myAssignments) {
      if (a.location != null) points.add(LatLng(a.location!.latitude, a.location!.longitude));
    }
    for (final loc in _fieldLocations) {
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
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _startJourney,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Bắt đầu hành trình', style: TextStyle(fontWeight: FontWeight.bold)),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF22C55E),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    if (_todayJourney!.isActive) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _endJourney,
          icon: const Icon(Icons.stop),
          label: Text('Kết thúc hành trình • ${_todayJourney!.durationFormatted}', style: const TextStyle(fontWeight: FontWeight.bold)),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    // Completed
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Hành trình đã hoàn thành', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
                  Text(
                    '${_todayJourney!.distanceFormatted} • ${_todayJourney!.durationFormatted} • ${_todayJourney!.checkedInCount}/${_todayJourney!.assignedCount} điểm',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _startJourney,
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('Bắt đầu lại hành trình'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1E3A5F),
              side: const BorderSide(color: Color(0xFF1E3A5F)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCard(FieldLocationAssignment a) {
    final todayVisit = _todayVisits.where((v) => v.locationId == a.locationId).toList();
    final activeVisit = todayVisit.where((v) => v.isCheckedIn).firstOrNull;
    final completedVisit = todayVisit.where((v) => v.isCheckedOut).firstOrNull;

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
    } else if (completedVisit != null) {
      accentColor = const Color(0xFF22C55E);
      statusIcon = Icons.check_circle;
      statusLabel = '${completedVisit.timeSpentFormatted}';
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
            : completedVisit == null
                ? _actionButton('Check-in', Icons.login, const Color(0xFF1E3A5F), () => _doCheckIn(a))
                : Icon(Icons.check_circle, color: const Color(0xFF22C55E).withValues(alpha: 0.7)),
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
    final completedVisit = todayVisit.where((v) => v.isCheckedOut).firstOrNull;

    Color accentColor;
    IconData statusIcon;
    String statusLabel;
    if (activeVisit != null) {
      accentColor = Colors.orange;
      statusIcon = Icons.radio_button_checked;
      statusLabel = 'Đang ở điểm';
    } else if (completedVisit != null) {
      accentColor = const Color(0xFF22C55E);
      statusIcon = Icons.check_circle;
      statusLabel = completedVisit.timeSpentFormatted;
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
            : completedVisit == null
                ? _actionButton('Check-in', Icons.login, const Color(0xFF6366F1), () => _doCheckInAtFieldLocation(loc))
                : Icon(Icons.check_circle, color: const Color(0xFF22C55E).withValues(alpha: 0.7)),
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
                      value: selectedCategory,
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
                            if (mounted) {
                              Navigator.pop(ctx);
                              NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã đăng ký điểm bán thành công!');
                              _loadMyData();
                            }
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

  Widget _buildHistoryTab() {
    return Column(
      children: [
        // Date filter
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                    initialDateRange: DateTimeRange(start: _historyFrom, end: _historyTo),
                  );
                  if (picked != null) {
                    setState(() { _historyFrom = picked.start; _historyTo = picked.end; });
                    _loadHistory();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.date_range, size: 18),
                    const SizedBox(width: 8),
                    Text('${DateFormat('dd/MM').format(_historyFrom)} - ${DateFormat('dd/MM/yyyy').format(_historyTo)}',
                        style: const TextStyle(fontSize: 13)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
        // List
        Expanded(
          child: _isLoadingHistory
              ? const Center(child: CircularProgressIndicator())
              : (_journeyHistory.isEmpty && _historyVisits.isEmpty)
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.history, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('Chưa có lịch sử', style: TextStyle(color: Colors.grey[500])),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _loadHistory,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          // Journey cards
                          if (_journeyHistory.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('Hành trình', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                            ..._journeyHistory.map(_buildJourneyHistoryCard),
                            const SizedBox(height: 12),
                          ],
                          // Visit cards
                          if (_historyVisits.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text('Check-in (${_historyVisits.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                            ..._historyVisits.map(_buildHistoryVisitCard),
                          ],
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

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
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: v.isCheckedIn ? Colors.orange.shade50 : Colors.green.shade50,
          child: Icon(v.isCheckedIn ? Icons.location_on : Icons.check, size: 18,
              color: v.isCheckedIn ? Colors.orange : Colors.green),
        ),
        title: Text(v.locationName ?? '', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text(
          '${DateFormat('dd/MM HH:mm').format(v.visitDate.toLocal())} • ${v.timeSpentFormatted}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: _buildStatusChip(v.status),
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
    LatLng center = const LatLng(10.8231, 106.6297);
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
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                onTap: (_, __) => setState(() => _selectedEmployeeId = null),
              ),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                if (circles.isNotEmpty) CircleLayer(circles: circles),
                if (markers.isNotEmpty) MarkerLayer(markers: markers),
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
        onTap: () => setState(() => _selectedEmployeeId = isSelected ? null : emp['employeeId']),
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
            ])),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
          ]),
        ),
      ),
    );
  }

  Widget _buildManagerListView() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
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
        Text('Báo cáo check-in (${_reports.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        ..._reports.map(_buildManagerReportCard),
      ],
    );
  }

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
        _buildStatCard('Km', '${journeyKm.toStringAsFixed(1)}', Icons.route, const Color(0xFF1E3A5F)),
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
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16, backgroundColor: Colors.teal.shade50,
          child: Text((visit.employeeName ?? '?')[0].toUpperCase(),
              style: TextStyle(color: Colors.teal[700], fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        title: Text('${visit.employeeName ?? ""} - ${visit.locationName ?? ""}',
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        subtitle: Text(
          '${DateFormat('dd/MM HH:mm').format(visit.visitDate.toLocal())} • ${visit.timeSpentFormatted}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: visit.status == 'checked_out'
            ? TextButton(onPressed: () => _reviewVisit(visit), child: const Text('Duyệt', style: TextStyle(fontSize: 11)))
            : _buildStatusChip(visit.status),
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
