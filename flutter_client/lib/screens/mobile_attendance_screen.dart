import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/mobile_attendance.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/face_storage_service.dart';
import '../services/face_embedding_service_stub.dart'
    if (dart.library.io) '../services/face_embedding_service.dart';
import '../utils/platform_geolocation.dart';
import '../widgets/face_verification_camera.dart';
import '../widgets/notification_overlay.dart';
import 'mobile_attendance_history_screen.dart';

class MobileAttendanceScreen extends StatefulWidget {
  const MobileAttendanceScreen({super.key});

  @override
  State<MobileAttendanceScreen> createState() => _MobileAttendanceScreenState();
}

class _MobileAttendanceScreenState extends State<MobileAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final ApiService _apiService = ApiService();
  
  bool _isLocationVerified = false;
  bool _isGettingLocation = false;
  bool _isWifiVerified = false;
  bool _isCheckingWifi = false;
  String? _connectedWifiSsid;
  String? _wifiLocationName;
  String? _detectedBssid;
  double? _currentLatitude;
  double? _currentLongitude;
  double? _distanceFromOffice;
  String? _nearestLocationName;
  
  // Employee data from auth
  String _employeeName = '';
  String _department = '';
  String _employeeId = '';

  // Work locations from API
  List<WorkLocation> _workLocations = [];

  // Today's attendance records from API
  List<MobileAttendanceRecord> _todayRecords = [];

  // Device registration state
  bool _isDeviceRegistered = false;
  bool _isDeviceApproved = false;
  String? _registeredDeviceId;

  // Device outside check-in permission
  bool _allowOutsideCheckIn = false;

  // Face verification state
  bool _isFaceVerified = false;
  double? _faceMatchScore;
  String? _faceImageBase64;
  List<String> _cachedFacePaths = []; // On-device face registration images

  // Settings for verification requirements
  MobileAttendanceSettings? _settings;

  // Continuous monitoring timer
  Timer? _monitorTimer;
  int _monitorFailCount = 0; // for backoff

  // Auto-submit state
  bool _isAutoSubmitting = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _loadEmployeeData();
    _initVerification();
  }

  /// Optimized startup: request permission once, then parallelize everything
  Future<void> _initVerification() async {
    // 1. Request location permission once (needed by both GPS + WiFi BSSID)
    if (!kIsWeb) {
      final granted = await ensureLocationPermission();
      if (!mounted) return;
      // Also set permission_handler status for WiFi
      if (granted) {
        _wifiPermissionsRequested = true;
      }
    }

    // 2. Instant GPS from OS cache (< 50ms)
    final lastPos = await getLastKnownPosition();
    if (lastPos != null && mounted) {
      setState(() {
        _currentLatitude = lastPos.latitude;
        _currentLongitude = lastPos.longitude;
      });
    }

    // 3. Parallelize ALL network calls + fresh GPS + WiFi scan
    await Future.wait([
      _loadWorkLocations(),
      _loadDeviceStatus(),
      _loadSettings(),
      _loadTodayRecords(),
      _getCurrentLocation(),
      _checkWifiConnection(requestPermissions: true),
    ]);

    // 4. Recalculate with both workLocations + GPS ready
    if (mounted) _calculateNearestLocation();

    // 5. Start monitoring with backoff
    _startMonitoring();
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Stream<DateTime> _clockStream() => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());

  void _loadEmployeeData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user != null) {
      setState(() {
        _employeeName = user.fullName;
        _employeeId = user.id;
        _department = user.department ?? '';
      });
    }
  }

  Future<void> _loadDeviceStatus() async {
    try {
      final response = await _apiService.getMyDeviceStatus();
      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'];
        if (mounted) {
          setState(() {
            _isDeviceRegistered = data['registered'] == true;
            _isDeviceApproved = data['approved'] == true;
            _registeredDeviceId = data['deviceId'] as String?;
            _allowOutsideCheckIn = data['allowOutsideCheckIn'] == true;
          });
        }

        // Download face registration images for on-device comparison
        final faceImages = data['faceImages'];
        if (faceImages != null && faceImages is List && faceImages.isNotEmpty && _employeeId.isNotEmpty) {
          final imageUrls = List<String>.from(faceImages);
          final storageService = FaceStorageService(baseUrl: ApiService.baseUrl);
          final paths = await storageService.downloadAndCacheFaces(_employeeId, imageUrls);
          if (mounted && paths.isNotEmpty) {
            setState(() => _cachedFacePaths = paths);
            debugPrint('Face images cached: ${paths.length} files for on-device comparison');
            // Pre-load MobileFaceNet model and clear old cached embeddings
            FaceEmbeddingService.clearCache();
            await FaceEmbeddingService.initialize();
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading device status: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final response = await _apiService.getMyMobileSettings();
      if (response['isSuccess'] == true && response['data'] != null) {
        if (mounted) {
          setState(() {
            _settings = MobileAttendanceSettings.fromJson(response['data'] as Map<String, dynamic>);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  void _startMonitoring() {
    _monitorTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final needGps = !_isLocationVerified;
      final needWifi = !_isWifiVerified;
      if (!needGps && !needWifi) {
        // Both verified - no need to poll
        _monitorFailCount = 0;
        return;
      }
      // Exponential backoff: skip more cycles as failures accumulate (max gap ~60s)
      _monitorFailCount++;
      final skipCycles = (_monitorFailCount ~/ 3).clamp(0, 4);
      if (_monitorFailCount % (skipCycles + 1) != 0) return;
      
      if (needGps) _getCurrentLocation();
      if (needWifi) _checkWifiConnection();
    });
  }

  /// Check if all required conditions are met for attendance
  bool get _conditionsMet {
    // Must have registered & approved device
    if (!_isDeviceRegistered || !_isDeviceApproved) return false;

    if (_allowOutsideCheckIn) return true;
    
    final settings = _settings;
    if (settings == null) return false;

    // Count enabled & passed methods
    final mode = settings.verificationMode; // "any" or "all"
    int enabledCount = 0;
    int passedCount = 0;

    if (settings.enableFaceId) {
      enabledCount++;
      if (_isFaceVerified) passedCount++;
    }
    if (settings.enableGps) {
      enabledCount++;
      if (_isLocationVerified) passedCount++;
    }
    if (settings.enableWifi) {
      enabledCount++;
      if (_isWifiVerified) passedCount++;
    }

    if (enabledCount == 0) return true; // No method enabled = allow

    if (mode == 'any') {
      return passedCount >= 1; // At least 1 method passed
    } else {
      // "all" mode
      return passedCount >= enabledCount; // All must pass
    }
  }

  /// Whether the punch button should be tappable.
  /// Face is interactive (opens camera on tap), so we allow tapping
  /// when all non-face conditions are met, or in "any" mode with at least 1 pass.
  bool get _canTapPunch {
    if (!_isDeviceRegistered || !_isDeviceApproved) return false;
    if (_allowOutsideCheckIn) return true;

    final settings = _settings;
    if (settings == null) return false;

    final mode = settings.verificationMode;
    int enabledNonFace = 0;
    int passedNonFace = 0;

    if (settings.enableGps) {
      enabledNonFace++;
      if (_isLocationVerified) passedNonFace++;
    }
    if (settings.enableWifi) {
      enabledNonFace++;
      if (_isWifiVerified) passedNonFace++;
    }

    // If face is enabled, the button tap will open camera
    if (settings.enableFaceId) {
      if (_isFaceVerified) {
        // Already verified = treat as passed in _conditionsMet
        return _conditionsMet;
      }
      if (mode == 'any') {
        // In "any" mode: button can be tapped (face will be scanned as one option)
        return true; // User can scan face even if GPS/WiFi failed
      } else {
        // "all" mode: all non-face conditions must pass; face will be done on tap
        return enabledNonFace == 0 || passedNonFace >= enabledNonFace;
      }
    }

    // No face enabled = rely on _conditionsMet
    return _conditionsMet;
  }

  /// Auto-determine next punch type from today's records
  int _getNextPunchType() {
    if (_todayRecords.isEmpty) return 0; // check-in
    final sorted = List.of(_todayRecords)
      ..sort((a, b) => b.punchTime.compareTo(a.punchTime));
    return sorted.first.punchType == 0 ? 1 : 0; // toggle
  }

  Future<void> _autoSubmitAttendance() async {
    if (_isAutoSubmitting) return;

    // Pre-check device status
    if (!_isDeviceRegistered) {
      _showError('Thiết bị chưa được đăng ký. Vui lòng đăng ký thiết bị trước.');
      return;
    }
    if (!_isDeviceApproved) {
      _showError('Thiết bị chưa được duyệt hoặc đã bị thu hồi. Vui lòng liên hệ quản lý.');
      return;
    }

    // If face is enabled and not yet verified, open camera first
    final settings = _settings;
    if (settings != null && settings.enableFaceId && !_isFaceVerified && !_allowOutsideCheckIn) {
      // Block if employee has no face registration
      if (_cachedFacePaths.isEmpty) {
        _showError('Chưa đăng ký khuôn mặt. Vui lòng liên hệ quản lý để đăng ký Face ID.');
        return;
      }
      final result = await FaceVerificationCamera.show(
        context,
        registeredFacePaths: _cachedFacePaths,
        minMatchScore: settings.minFaceMatchScore,
      );
      if (result == null) return; // User cancelled
      setState(() {
        _isFaceVerified = true;
        _faceMatchScore = result.matchScore;
        _faceImageBase64 = result.faceImageBase64;
      });
      // Re-check conditions after face scan
      if (!_conditionsMet) {
        _showError('Chưa đạt đủ điều kiện xác thực');
        return;
      }
    }

    setState(() => _isAutoSubmitting = true);

    try {
      final punchType = _getNextPunchType();
      final response = await _apiService.submitMobileAttendance(
        employeeId: _employeeId,
        employeeName: _employeeName,
        punchType: punchType,
        latitude: _currentLatitude ?? 0,
        longitude: _currentLongitude ?? 0,
        faceImage: _faceImageBase64 ?? '',
        distanceFromLocation: _distanceFromOffice,
        faceMatchScore: _faceMatchScore,
        deviceId: _registeredDeviceId,
        wifiSsid: _connectedWifiSsid,
        wifiBssid: _detectedBssid,
      );

      if (!mounted) return;

      if (response['isSuccess'] == true) {

        _showSuccess(
          punchType == 0 ? 'Chấm công VÀO thành công!' : 'Chấm công RA thành công!',
          _isWifiVerified
              ? 'Đã xác thực qua WiFi: ${_connectedWifiSsid ?? ''}'
              : _isLocationVerified
                  ? 'Tự động duyệt (trong phạm vi ${_distanceFromOffice?.toInt()}m)'
                  : _allowOutsideCheckIn
                      ? 'Chấm công ngoài công ty'
                      : 'Đang chờ duyệt',
        );

        _loadTodayRecords();
        // Reset face verification for next punch
        setState(() {
          _isFaceVerified = false;
          _faceMatchScore = null;
          _faceImageBase64 = null;
        });
      } else {
        _showError(response['message'] ?? 'Không thể chấm công');
      }
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _isAutoSubmitting = false);
    }
  }

  Future<void> _loadWorkLocations() async {
    try {
      final response = await _apiService.getWorkLocations();
      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is List) {
          setState(() {
            _workLocations = data.map((e) => WorkLocation.fromJson(e as Map<String, dynamic>)).toList();
          });
          // Recalculate distance if we already have GPS
          if (_currentLatitude != null && _currentLongitude != null) {
            _calculateNearestLocation();
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading work locations: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    if (_isGettingLocation) return; // Guard against concurrent
    setState(() => _isGettingLocation = true);
    try {
      // Try last known position first (instant, <50ms)
      if (_currentLatitude == null) {
        final cached = await getLastKnownPosition();
        if (cached != null && mounted) {
          setState(() {
            _currentLatitude = cached.latitude;
            _currentLongitude = cached.longitude;
          });
          _calculateNearestLocation();
          if (_isLocationVerified) {
            setState(() => _isGettingLocation = false);
            _refineLocationInBackground();
            return;
          }
        }
      }

      // Fast low accuracy (2s timeout)
      final fastPosition = await getCurrentPosition(
        enableHighAccuracy: false,
        timeout: 2000,
      );
      if (!mounted) return;
      setState(() {
        _currentLatitude = fastPosition.latitude;
        _currentLongitude = fastPosition.longitude;
      });
      _calculateNearestLocation();
      
      // If already in range, stop early
      if (_isLocationVerified) {
        setState(() => _isGettingLocation = false);
        _monitorFailCount = 0; // reset backoff
        _refineLocationInBackground();
        return;
      }
      
      // Not in range → high accuracy (6s timeout, reduced from 10)
      final position = await getCurrentPosition(
        enableHighAccuracy: true,
        timeout: 6000,
      );
      if (!mounted) return;
      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
        _isGettingLocation = false;
      });
      _calculateNearestLocation();
      if (_isLocationVerified) _monitorFailCount = 0;
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        setState(() => _isGettingLocation = false);
      }
    }
  }
  
  /// Quietly update location with high accuracy in background
  Future<void> _refineLocationInBackground() async {
    try {
      final position = await getCurrentPosition(
        enableHighAccuracy: true,
        timeout: 8000,
      );
      if (!mounted) return;
      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
      });
      _calculateNearestLocation();
    } catch (_) {}
  }

  void _calculateNearestLocation() {
    if (_currentLatitude == null || _currentLongitude == null || _workLocations.isEmpty) return;

    double? nearestDist;
    String? nearestName;
    int nearestRadius = 100;

    for (final loc in _workLocations) {
      if (!loc.isActive) continue;
      final d = _haversineDistance(_currentLatitude!, _currentLongitude!, loc.latitude, loc.longitude);
      if (nearestDist == null || d < nearestDist) {
        nearestDist = d;
        nearestName = loc.name;
        nearestRadius = loc.radius;
      }
    }

    setState(() {
      _distanceFromOffice = nearestDist;
      _nearestLocationName = nearestName;
      _isLocationVerified = nearestDist != null && nearestDist <= nearestRadius;
    });
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  Future<void> _loadTodayRecords() async {
    try {
      final now = DateTime.now();
      debugPrint('📋 _loadTodayRecords: employeeId=$_employeeId, from=${DateTime(now.year, now.month, now.day)}, to=${DateTime(now.year, now.month, now.day, 23, 59, 59)}');
      final response = await _apiService.getMobileAttendanceHistory(
        employeeId: _employeeId.isNotEmpty ? _employeeId : null,
        fromDate: DateTime(now.year, now.month, now.day),
        toDate: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );

      if (!mounted) return;
      debugPrint('📋 _loadTodayRecords response: isSuccess=${response['isSuccess']}, data type=${response['data']?.runtimeType}, data=${response['data']}');
      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'];
        debugPrint('📋 _loadTodayRecords: data is List=${data is List}, length=${data is List ? data.length : 'N/A'}');
        if (data is List) {
          setState(() {
            _todayRecords = data
                .map((e) => MobileAttendanceRecord.fromJson(e as Map<String, dynamic>))
                .toList();
          });
          debugPrint('📋 _loadTodayRecords: parsed ${_todayRecords.length} records');
        }
      }
    } catch (e, st) {
      debugPrint('Error loading today records: $e\n$st');
    }
  }

  bool _wifiPermissionsRequested = false; // only request permissions once

  Future<void> _checkWifiConnection({bool requestPermissions = false}) async {
    if (_isCheckingWifi) return; // Guard against concurrent checks
    
    // Only show loading indicator on manual/first check, not periodic
    if (requestPermissions || !_wifiPermissionsRequested) {
      setState(() {
        _isCheckingWifi = true;
      });
    } else {
      _isCheckingWifi = true; // set flag without triggering full UI rebuild
    }
    
    final debugLines = <String>[];
    try {
      // Try to detect BSSID (router MAC address) on supported platforms
      String? bssid;
      String? ssid;
      if (!kIsWeb) {
        try {
          // Check location permission status
          var locationStatus = await Permission.locationWhenInUse.status;
          debugLines.add('LocationWhenInUse: $locationStatus');
          
          // Only request permissions on first call or manual refresh
          if (!locationStatus.isGranted && (requestPermissions || !_wifiPermissionsRequested)) {
            locationStatus = await Permission.locationWhenInUse.request();
            debugLines.add('Requested → $locationStatus');
          }
          
          // Mark that we've attempted permission requests
          _wifiPermissionsRequested = true;
          
          if (!locationStatus.isGranted) {
            debugPrint('Location permission denied - BSSID unavailable');
            _detectedBssid = null;
            debugLines.add('⚠ Quyền vị trí bị từ chối');
            final response = await _apiService.checkWifi(bssid: null).timeout(const Duration(seconds: 5), onTimeout: () => <String, dynamic>{'isSuccess': false, 'message': 'Timeout'});
            debugLines.add('API(bssid=null): ${response['isSuccess']}');
            if (!mounted) { _isCheckingWifi = false; return; }
            if (response['isSuccess'] == true && response['data'] != null) {
              final data = response['data'] as Map<String, dynamic>;
              debugLines.add('Verified: ${data['isWifiVerified']}, locs: ${data['locationsChecked']}');
              setState(() {
                _isWifiVerified = data['isWifiVerified'] == true;
                _wifiLocationName = data['locationName'] as String?;
                _connectedWifiSsid = data['wifiSsid'] as String?;
                if (!_isWifiVerified) {
                  _connectedWifiSsid = 'Chưa cấp quyền vị trí';
                }
                _isCheckingWifi = false;
              });
            } else {
              setState(() {
                _connectedWifiSsid = 'Chưa cấp quyền vị trí';
                _isCheckingWifi = false;
              });
            }
            return;
          }

          final networkInfo = NetworkInfo();
          // Fetch BSSID and SSID in parallel (saves ~3s)
          final wifiResults = await Future.wait([
            networkInfo.getWifiBSSID().timeout(const Duration(seconds: 3), onTimeout: () => null),
            networkInfo.getWifiName().timeout(const Duration(seconds: 3), onTimeout: () => null),
          ]);
          bssid = wifiResults[0];
          ssid = wifiResults[1];
          // Remove quotes from SSID if present
          if (ssid != null) {
            ssid = ssid.replaceAll('"', '');
          }
          debugLines.add('Raw BSSID: $bssid');
          debugLines.add('Raw SSID: $ssid');
          debugPrint('WiFi BSSID detected: $bssid, SSID: $ssid');
          if (bssid != null && bssid.isNotEmpty && bssid != '02:00:00:00:00:00') {
            _detectedBssid = bssid.toLowerCase().trim();
            debugLines.add('✓ BSSID OK: $_detectedBssid');
          } else {
            debugPrint('BSSID unavailable or placeholder: $bssid');
            _detectedBssid = null;
            if (bssid == '02:00:00:00:00:00') {
              debugLines.add('⚠ BSSID=02:00:... → GPS tắt?');
            } else {
              debugLines.add('⚠ BSSID null/empty → không có WiFi?');
            }
          }
        } catch (e) {
          debugPrint('BSSID detection error: $e');
          debugLines.add('⚠ Lỗi: $e');
        }
      }

      debugLines.add('Gọi API bssid=${_detectedBssid ?? "null"}');
      final response = await _apiService.checkWifi(bssid: _detectedBssid).timeout(const Duration(seconds: 5), onTimeout: () => <String, dynamic>{'isSuccess': false, 'message': 'Timeout'});
      debugPrint('WiFi check response: $response');
      if (!mounted) { _isCheckingWifi = false; return; }
      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'] as Map<String, dynamic>;
        final isVerified = data['isWifiVerified'] == true;
        debugLines.add('Verified: $isVerified, type: ${data['verifyType']}');
        debugLines.add('Location: ${data['locationName'] ?? "-"}');
        debugLines.add('Locs checked: ${data['locationsChecked'] ?? "-"}');
        debugLines.add('UserStoreId: ${data['userStoreId'] ?? "-"}');
        if (data['receivedBssid'] != null) {
          debugLines.add('Server got: ${data['receivedBssid']}');
        }
        if (data['message'] != null && !isVerified) {
          debugLines.add('Msg: ${data['message']}');
        }
        setState(() {
          _isWifiVerified = isVerified;
          _wifiLocationName = data['locationName'] as String?;
          _connectedWifiSsid = ssid ?? (data['wifiSsid'] as String?);

          _isCheckingWifi = false;
        });
        if (isVerified) _monitorFailCount = 0;
      } else {
        debugLines.add('API error: ${response['message'] ?? "unknown"}');
        setState(() {
          _connectedWifiSsid = ssid;
          _isCheckingWifi = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking wifi: $e');
      debugLines.add('Exception: $e');
      if (mounted) {
        setState(() {
          _isCheckingWifi = false;
        });
      } else {
        _isCheckingWifi = false;
      }
    }
  }



  void _showSuccess(String title, String message) {
    NotificationOverlayManager().showSuccess(title: title, message: message);
  }

  void _showError(String message) {
    NotificationOverlayManager().showError(title: 'Lỗi', message: message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Background gradient orbs
          Positioned(top: -80, right: -60, child: _bgOrb(200, const Color(0xFF3B82F6), 0.15)),
          Positioned(bottom: 100, left: -40, child: _bgOrb(160, const Color(0xFF8B5CF6), 0.1)),
          Positioned(top: 300, right: -30, child: _bgOrb(120, const Color(0xFF06B6D4), 0.08)),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 8),
                  _buildClockAndPunchButton(),
                  const SizedBox(height: 16),
                  _buildVerificationCards(),
                  const SizedBox(height: 16),
                  _buildTodayRecords(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bgOrb(double size, Color color, double opacity) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color.withValues(alpha: opacity), Colors.transparent]),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
            ),
            child: Center(
              child: Text(
                _employeeName.isNotEmpty ? _employeeName[0].toUpperCase() : 'U',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _employeeName,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _department,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _glassIconButton(
            Icons.history_rounded,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MobileAttendanceHistoryScreen())),
          ),
        ],
      ),
    );
  }

  Widget _glassIconButton(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon, color: const Color(0xFF94A3B8), size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildClockAndPunchButton() {
    final isEnabled = _canTapPunch && !_isAutoSubmitting;
    final nextPunchType = _getNextPunchType();
    final isCheckIn = nextPunchType == 0;
    final faceEnabled = _settings?.enableFaceId ?? false;
    final needsFaceScan = faceEnabled && !_isFaceVerified && !_allowOutsideCheckIn;
    final now = DateTime.now();
    final weekdays = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];

    final List<Color> activeGradient = isCheckIn
        ? [const Color(0xFF3B82F6), const Color(0xFF2563EB)]
        : [const Color(0xFFEF4444), const Color(0xFFDC2626)];
    final List<Color> disabledGradient = [const Color(0xFF334155), const Color(0xFF1E293B)];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _glassCard(
        child: Column(
          children: [
            // Clock
            StreamBuilder<DateTime>(
              stream: _clockStream(),
              initialData: DateTime.now(),
              builder: (context, snapshot) {
                final t = snapshot.data ?? DateTime.now();
                return ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF60A5FA), Color(0xFFA78BFA)],
                  ).createShader(bounds),
                  child: Text(
                    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w200,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                      letterSpacing: 4,
                      height: 1.1,
                    ),
                  ),
                );
              },
            ),
            StreamBuilder<DateTime>(
              stream: _clockStream(),
              initialData: DateTime.now(),
              builder: (context, snapshot) {
                final t = snapshot.data ?? DateTime.now();
                return Text(
                  ':${t.second.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w300, color: Color(0xFF64748B), fontFeatures: [FontFeature.tabularFigures()]),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              '${weekdays[now.weekday % 7]}, ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), letterSpacing: 0.5),
            ),
            const SizedBox(height: 28),
            // Punch button with outer ring
            GestureDetector(
              onTap: isEnabled ? _autoSubmitAttendance : null,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  final scale = isEnabled ? _pulseAnimation.value : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 148, height: 148,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isEnabled ? activeGradient[0].withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
                          width: 3,
                        ),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: isEnabled ? activeGradient : disabledGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: isEnabled ? [
                            BoxShadow(color: activeGradient[0].withValues(alpha: 0.4), blurRadius: 28, spreadRadius: 0, offset: const Offset(0, 8)),
                          ] : [],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isEnabled
                                  ? needsFaceScan ? Icons.face_rounded : (isCheckIn ? Icons.fingerprint_rounded : Icons.logout_rounded)
                                  : Icons.lock_outline_rounded,
                              color: Colors.white.withValues(alpha: isEnabled ? 1.0 : 0.4),
                              size: 42,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isEnabled ? (isCheckIn ? 'CHECK IN' : 'CHECK OUT') : 'LOCKED',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: isEnabled ? 0.95 : 0.3),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_isAutoSubmitting)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: activeGradient[0])),
                  const SizedBox(width: 8),
                  const Text('Đang xử lý...', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                ],
              )
            else
              Text(
                isEnabled
                    ? needsFaceScan ? 'Nhấn để quét mặt & chấm công' : 'Nhấn để chấm công'
                    : !_isDeviceRegistered ? 'Thiết bị chưa đăng ký'
                    : !_isDeviceApproved ? 'Thiết bị chưa được duyệt'
                    : 'Đang kiểm tra...',
                style: TextStyle(fontSize: 12, color: isEnabled ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child, EdgeInsets? padding, EdgeInsets? margin}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: padding ?? const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          margin: margin,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildVerificationCards() {
    final settings = _settings;
    final faceRequired = settings?.enableFaceId ?? true;
    final gpsRequired = settings?.enableGps ?? true;
    final wifiRequired = settings?.enableWifi ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Status bar
          _buildStatusBar(faceRequired, gpsRequired, wifiRequired),
          const SizedBox(height: 10),
          // GPS & WiFi cards
          if (!_allowOutsideCheckIn)
            Row(
              children: [
                if (gpsRequired) Expanded(child: _buildGpsCard()),
                if (gpsRequired && wifiRequired) const SizedBox(width: 10),
                if (wifiRequired) Expanded(child: _buildWifiCard()),
              ],
            ),
          if (_allowOutsideCheckIn) _buildOutsideChip(),
        ],
      ),
    );
  }

  Widget _buildStatusBar(bool faceRequired, bool gpsRequired, bool wifiRequired) {
    final mode = _settings?.verificationMode ?? 'all';
    final ready = _canTapPunch;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: ready
                ? const Color(0xFF16A34A).withValues(alpha: 0.1)
                : const Color(0xFFF59E0B).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ready ? const Color(0xFF16A34A).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ready ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                  boxShadow: [BoxShadow(color: (ready ? const Color(0xFF22C55E) : const Color(0xFFF59E0B)).withValues(alpha: 0.4), blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 6, runSpacing: 4,
                  children: [
                    _buildMiniChip('Thiết bị', _isDeviceRegistered && _isDeviceApproved),
                    if (faceRequired && !_allowOutsideCheckIn) _buildMiniChip('Face', _isFaceVerified),
                    if (gpsRequired && !_allowOutsideCheckIn) _buildMiniChip('GPS', _isLocationVerified),
                    if (wifiRequired && !_allowOutsideCheckIn) _buildMiniChip('WiFi', _isWifiVerified),
                    if (_allowOutsideCheckIn) _buildMiniChip('Ngoài CT', true),
                  ],
                ),
              ),
              if (mode == 'any' && !_allowOutsideCheckIn)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
                  child: const Text('ANY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 1)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniChip(String label, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFF22C55E).withValues(alpha: 0.12) : const Color(0xFFEF4444).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ok ? const Color(0xFF22C55E).withValues(alpha: 0.2) : const Color(0xFFEF4444).withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ok ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
            ),
          ),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: ok ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5))),
        ],
      ),
    );
  }

  Widget _buildGpsCard() {
    final statusColor = _isLocationVerified
        ? const Color(0xFF22C55E)
        : _isGettingLocation ? const Color(0xFFF59E0B) : const Color(0xFF64748B);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: statusColor.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: statusColor.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      _isLocationVerified ? Icons.location_on_rounded : Icons.gps_not_fixed_rounded,
                      size: 16, color: statusColor,
                    ),
                  ),
                  const Spacer(),
                  if (_isGettingLocation)
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: statusColor))
                  else
                    GestureDetector(
                      onTap: _getCurrentLocation,
                      child: Icon(Icons.refresh_rounded, size: 18, color: Colors.white.withValues(alpha: 0.3)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _isGettingLocation ? 'Định vị...' : _isLocationVerified ? 'Trong phạm vi' : 'Ngoài phạm vi',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: statusColor),
              ),
              if (_nearestLocationName != null) ...[
                const SizedBox(height: 3),
                Text(
                  _nearestLocationName!,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
              if (_distanceFromOffice != null) ...[
                const SizedBox(height: 2),
                Text('${_distanceFromOffice!.toInt()}m', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: statusColor)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWifiCard() {
    final statusColor = _isWifiVerified
        ? const Color(0xFF22C55E)
        : _isCheckingWifi ? const Color(0xFFF59E0B) : const Color(0xFF64748B);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: statusColor.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: statusColor.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      _isWifiVerified ? Icons.wifi_rounded : Icons.wifi_find_rounded,
                      size: 16, color: statusColor,
                    ),
                  ),
                  const Spacer(),
                  if (_isCheckingWifi)
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: statusColor))
                  else
                    GestureDetector(
                      onTap: () => _checkWifiConnection(requestPermissions: true),
                      child: Icon(Icons.refresh_rounded, size: 18, color: Colors.white.withValues(alpha: 0.3)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _isCheckingWifi ? 'Kiểm tra...' : _isWifiVerified ? 'Đã xác thực' : 'Chưa xác thực',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: statusColor),
              ),
              if (_wifiLocationName != null) ...[
                const SizedBox(height: 3),
                Text(
                  _wifiLocationName!,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
              if (_connectedWifiSsid != null) ...[
                const SizedBox(height: 2),
                Text(
                  _connectedWifiSsid!,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: statusColor),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutsideChip() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF22C55E)),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Được phép chấm công ngoài công ty', style: TextStyle(fontSize: 12, color: Color(0xFF4ADE80))),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayRecords() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _glassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  ),
                  child: const Icon(Icons.timeline_rounded, size: 16, color: Color(0xFF60A5FA)),
                ),
                const SizedBox(width: 10),
                const Text('Hôm nay', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
                  child: Text('${_todayRecords.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_todayRecords.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.event_note_rounded, size: 32, color: Colors.white.withValues(alpha: 0.1)),
                      const SizedBox(height: 8),
                      const Text('Chưa có lượt chấm công', style: TextStyle(fontSize: 13, color: Color(0xFF475569))),
                    ],
                  ),
                ),
              )
            else
              ...(_todayRecords.map((record) => _buildRecordItem(record))),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordItem(MobileAttendanceRecord record) {
    final isCheckIn = record.punchType == 0;
    final approved = record.status == 'auto_approved' || record.status == 'approved';
    final color = isCheckIn ? const Color(0xFF3B82F6) : const Color(0xFFEF4444);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(isCheckIn ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${record.punchTime.hour.toString().padLeft(2, '0')}:${record.punchTime.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Text(
                    isCheckIn ? 'Check in' : 'Check out',
                    style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
                  ),
                  if (record.distanceFromLocation != null) ...[
                    Text(' · ', style: TextStyle(color: Colors.white.withValues(alpha: 0.2))),
                    Text('${record.distanceFromLocation!.toInt()}m', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ],
                ],
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: approved ? const Color(0xFF22C55E).withValues(alpha: 0.1) : const Color(0xFFF59E0B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: (approved ? const Color(0xFF22C55E) : const Color(0xFFF59E0B)).withValues(alpha: 0.15)),
            ),
            child: Text(
              approved ? 'Duyệt' : 'Chờ',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: approved ? const Color(0xFF4ADE80) : const Color(0xFFFCD34D)),
            ),
          ),
        ],
      ),
    );
  }
}
